import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'room_manager.dart';
import 'message_handler.dart';
import 'random_join_timer_manager.dart';

import '../services/python_api_client.dart';
import '../utils/config.dart';
import '../managers/hooks_manager.dart';
import '../modules/dutch_game/dutch_main.dart';
import '../modules/dutch_game/backend_core/services/game_state_store.dart';
import '../modules/dutch_game/backend_core/utils/progression_config_store.dart';

/// Core WebSocket event name for instant notifications pushed by the backend to a session.
const String kWsInstantNotificationEvent = 'ws_instant_notification';

/// Python notified Dart → push to this user's WS sessions: client should GET inbox from API.
const String kWsInboxChangedEvent = 'inbox_changed';

class _PendingDisconnectGrace {
  final String roomId;
  final String stablePlayerId;
  final String disconnectedSessionId;
  final String userId;

  Timer? timer;

  _PendingDisconnectGrace({
    required this.roomId,
    required this.stablePlayerId,
    required this.disconnectedSessionId,
    required this.userId,
  });
}

class WebSocketServer {
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, String> _connectionHashes = {}; // Track connection object identity
  /// Ensures each session processes one message at a time (authenticate awaits Python; later events must wait).
  final Map<String, Future<void>> _sessionMessageChain = {};
  final Map<String, String> _sessionToUser = {};
  final Map<String, bool> _authenticatedSessions = {};
  final Map<String, String?> _sessionToRank = {}; // Track user rank per session
  final Map<String, int?> _sessionToLevel = {}; // Track user level per session
  final RoomManager _roomManager = RoomManager();
  late MessageHandler _messageHandler;
  late PythonApiClient _pythonClient;
  final HooksManager _hooksManager = HooksManager();
  late DutchGameModule _dutchGameModule;

  /// Per `roomId` + stable seat id; holds timer for delayed leave after socket drop.
  final Map<String, _PendingDisconnectGrace> _disconnectGracePending = {};

  /// Single resumable room hint per authenticated user (latest grace entry wins).
  final Map<String, String> _resumableRoomByUserId = {};

  WebSocketServer({required String pythonApiUrl}) {
    _messageHandler = MessageHandler(_roomManager, this);
    // Python API URL is passed from app.dart (VPS) or app.debug.dart (local)
    _pythonClient = PythonApiClient(baseUrl: pythonApiUrl);
    ProgressionConfigStore.ensureEnvFallback();
    _pythonClient.fetchInitConfig();

    // Wire up room closure hook
    _roomManager.onRoomClosed = (roomId, reason) {
      _cancelAllDisconnectGraceForRoom(roomId);
      
      // Cleanup timer if room is closed during delay period
      RandomJoinTimerManager.instance.cleanup(roomId);
      
      // Trigger room_closed hook
      triggerHook('room_closed', data: {
        'room_id': roomId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      });
    };
    
    // Initialize hooks for room events
    _initializeHooks();
    
    // Initialize Dutch Game module (registers hooks for game lifecycle)
    _dutchGameModule = DutchGameModule(this, _roomManager, _hooksManager);
  }
  
  /// Initialize hooks for room events
  void _initializeHooks() {
    // Register hook event types
    _hooksManager.registerHook('room_joined');
    _hooksManager.registerHook('room_created');
    _hooksManager.registerHook('leave_room');
    _hooksManager.registerHook('room_closed');
  }

  /// Check if a session is authenticated
  bool isSessionAuthenticated(String sessionId) {
    return _authenticatedSessions[sessionId] == true;
  }

  /// Get user ID for a session
  String? getUserIdForSession(String sessionId) {
    return _sessionToUser[sessionId];
  }

  /// Update session to user mapping (for account conversion scenarios)
  void updateSessionUserId(String sessionId, String userId) {
    _sessionToUser[sessionId] = userId;
  }

  /// Get user rank for a session
  String? getUserRankForSession(String sessionId) {
    return _sessionToRank[sessionId];
  }

  /// Get user level for a session
  int? getUserLevelForSession(String sessionId) {
    return _sessionToLevel[sessionId];
  }

  /// Set user rank and level for a session
  void setUserRankAndLevel(String sessionId, String? rank, int? level) {
    if (rank != null) {
      _sessionToRank[sessionId] = rank.toLowerCase();
    }
    if (level != null) {
      _sessionToLevel[sessionId] = level;
    }
  }

  /// Get session ID for a user (reverse lookup)
  String? getSessionForUser(String userId) {
    for (final entry in _sessionToUser.entries) {
      if (entry.value == userId) {
        return entry.key;
      }
    }
    return null;
  }

  /// Get the owner/userId for a room
  String? getRoomOwner(String roomId) {
    final info = _roomManager.getRoomInfo(roomId);
    return info?.ownerId;
  }

  /// Get Python API client for making API calls
  PythonApiClient get pythonClient => _pythonClient;

  /// Get room info for a room
  /// Returns the Room object or null if not found
  Room? getRoomInfo(String roomId) {
    return _roomManager.getRoomInfo(roomId);
  }

  /// Trigger a hook with optional data and context
  void triggerHook(
    String hookName, {
    Map<String, dynamic>? data,
    String? context,
  }) {
    _hooksManager.triggerHook(hookName, data: data, context: context);
  }

  String _disconnectGraceKey(String roomId, String stablePlayerId) => '$roomId|${stablePlayerId}';

  void _clearResumableHintIfMatch(String? userId, String? roomId) {
    final u = userId?.trim() ?? '';
    final r = roomId?.trim() ?? '';
    if (u.isEmpty || r.isEmpty) return;
    if (_resumableRoomByUserId[u] == r) {
      _resumableRoomByUserId.remove(u);
    }
  }

  void _cancelAllDisconnectGraceForRoom(String roomId) {
    final cancelKeys = <String>[];
    for (final e in _disconnectGracePending.entries) {
      if (e.value.roomId == roomId) {
        cancelKeys.add(e.key);
      }
    }
    for (final k in cancelKeys) {
      final g = _disconnectGracePending.remove(k);
      g?.timer?.cancel();
      _clearResumableHintIfMatch(g?.userId, g?.roomId);
    }
  }

  void _cancelDisconnectGraceForSession(String disconnectedSessionId) {
    final cancelKeys = <String>[];
    for (final e in _disconnectGracePending.entries) {
      if (e.value.disconnectedSessionId == disconnectedSessionId) {
        cancelKeys.add(e.key);
      }
    }
    for (final k in cancelKeys) {
      final g = _disconnectGracePending.remove(k);
      g?.timer?.cancel();
      _clearResumableHintIfMatch(g?.userId, g?.roomId);
      if (g != null) {
        _dutchGameModule.clearDisconnectGracePause(g.roomId, g.stablePlayerId);
      }
    }
  }

  /// Public: optional `resumable_room_id` hint after authenticate.
  String? resumableRoomHintForUser(String userId) {
    final u = userId.trim();
    if (u.isEmpty) return null;
    return _resumableRoomByUserId[u];
  }

  /// Map canonical game seat id → active websocket session id for targeted emits.
  String? websocketSessionForGamePlayer(String roomId, String gamePlayerSeatId) {
    return _roomManager.getRoom(roomId)?.websocketSessionForSeat(gamePlayerSeatId);
  }

  bool _disconnectEligibleGameState(String roomId) {
    try {
      final gs = GameStateStore.instance.getGameState(roomId);
      final phase = gs['phase']?.toString() ?? '';
      if (phase == 'waiting_for_players' || phase == 'game_ended') {
        return false;
      }
      if (gs['isGameActive'] == true) return true;
      return phase.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _shouldOfferDisconnectGrace({
    required bool wasAuthenticated,
    required String userId,
    required String? roomId,
  }) {
    if (!Config.enableDisconnectRejoinGrace) return false;
    if (!wasAuthenticated || userId.trim().isEmpty) return false;
    final rid = roomId?.trim() ?? '';
    if (rid.isEmpty || !rid.startsWith('room_')) return false;
    if (!_disconnectEligibleGameState(rid)) return false;
    return true;
  }

  /// Returns true when grace was scheduled (socket row kept in room until timer or resume).
  bool _tryScheduleDisconnectGrace({
    required String disconnectedSessionId,
    required String roomId,
    required String userId,
  }) {
    final room = _roomManager.getRoom(roomId);
    if (room == null) return false;

    final stable = room.seatIdForSession(disconnectedSessionId) ??
        canonicalMultiplayerHumanPlayerId(disconnectedSessionId, userId);
    final key = _disconnectGraceKey(roomId, stable);
    final existing = _disconnectGracePending[key];
    existing?.timer?.cancel();

    final entry = _PendingDisconnectGrace(
      roomId: roomId,
      stablePlayerId: stable,
      disconnectedSessionId: disconnectedSessionId,
      userId: userId,
    );
    _disconnectGracePending[key] = entry;
    _resumableRoomByUserId[userId.trim()] = roomId;

    _dutchGameModule.pauseActionTimersForDisconnectGrace(roomId, stable);

    final secs = Config.disconnectRejoinGraceSeconds;
    final expiresAt = DateTime.now().add(Duration(seconds: secs));
    entry.timer = Timer(Duration(seconds: secs), () {
      _finalizeDisconnectGraceExpiry(key);
    });

    broadcastToRoom(roomId, {
      'event': 'player_disconnected',
      'room_id': roomId,
      'game_player_id': stable,
      'grace_seconds': secs,
      'expires_at': expiresAt.toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
    });

    return true;
  }

  void _finalizeDisconnectGraceExpiry(String key) {
    final g = _disconnectGracePending.remove(key);
    if (g == null) return;
    g.timer?.cancel();
    _clearResumableHintIfMatch(g.userId, g.roomId);

    final roomId = g.roomId;
    if (_roomManager.getRoom(roomId) == null) {
      return;
    }

    _roomManager.leaveRoom(g.disconnectedSessionId);

    triggerHook('leave_room', data: {
      'room_id': roomId,
      'session_id': g.disconnectedSessionId,
      'user_id': g.userId,
      'game_player_id': g.stablePlayerId,
      'reason': 'grace_expired_leave',
      'left_at': DateTime.now().toIso8601String(),
    });

    final roomAfter = _roomManager.getRoomInfo(roomId);

    broadcastToRoom(roomId, {
      'event': 'player_left',
      'room_id': roomId,
      'player_count': roomAfter?.currentSize ?? 0,
      'reason': 'grace_expired_leave',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Resume in-grace player: swap websocket session, cancel timer, send snapshot.
  bool tryResumeRoomForUser({
    required String newSessionId,
    required String roomId,
    required String userId,
  }) {
    final u = userId.trim();
    final expectedStable = canonicalMultiplayerHumanPlayerId(newSessionId, u);
    final key = _disconnectGraceKey(roomId, expectedStable);
    final g = _disconnectGracePending[key];
    if (g == null || g.userId != u) {
      return false;
    }

    final room = _roomManager.getRoom(roomId);
    if (room == null) {
      _disconnectGracePending.remove(key);
      g.timer?.cancel();
      _clearResumableHintIfMatch(u, roomId);
      return false;
    }

    g.timer?.cancel();
    _disconnectGracePending.remove(key);
    _clearResumableHintIfMatch(u, roomId);

    final oldS = g.disconnectedSessionId;
    final i = room.sessionIds.indexOf(oldS);
    if (i >= 0) {
      room.sessionIds[i] = newSessionId;
    } else if (!room.sessionIds.contains(newSessionId)) {
      room.sessionIds.add(newSessionId);
    }
    _roomManager.replaceSessionMapping(oldS, newSessionId, roomId);
    room.rebindSessionSeat(expectedStable, oldS, newSessionId);

    _dutchGameModule.resumeActionTimersAfterReconnect(roomId, expectedStable);

    sendToSession(newSessionId, {
      'event': 'rejoin_success',
      'room_id': roomId,
      'game_player_id': expectedStable,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _dutchGameModule.sendGameSnapshotToSession(newSessionId, roomId);

    broadcastToRoomExcept(roomId, {
      'event': 'player_reconnected',
      'room_id': roomId,
      'game_player_id': expectedStable,
      'timestamp': DateTime.now().toIso8601String(),
    }, newSessionId);

    return true;
  }

  void handleConnection(WebSocketChannel webSocket) {
    final sessionId = const Uuid().v4();
    _connections[sessionId] = webSocket;
    _connectionHashes[sessionId] = webSocket.hashCode.toString();
    _authenticatedSessions[sessionId] = false;

    sendToSession(sessionId, {
      'event': 'connected',
      'session_id': sessionId,
      'message': 'Welcome to Dutch Game Server',
      'authenticated': false,
    });

    webSocket.stream.listen(
      (message) => _onMessage(sessionId, message),
      onDone: () => _onDisconnect(sessionId),
      onError: (error) => _onError(sessionId, error),
    );
  }
  
  void _onMessage(String sessionId, dynamic message) {
    final prev = _sessionMessageChain[sessionId] ?? Future.value();
    // Recover from prior failures so one bad message does not stall the session forever.
    _sessionMessageChain[sessionId] = prev
        .catchError((_) {})
        .then((_) => _processMessage(sessionId, message));
  }

  Future<void> _processMessage(String sessionId, dynamic message) async {
    try {
      final decoded = jsonDecode(message as String);

      // Convert LinkedMap<dynamic, dynamic> to Map<String, dynamic>
      // jsonDecode can return LinkedMap which is not compatible with Map<String, dynamic>
      final Map<String, dynamic> data;
      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      } else {
        throw FormatException('Expected JSON object, got ${decoded.runtimeType}');
      }

      // Route to unified message handler (await so authenticate finishes before next message).
      await _messageHandler.handleMessage(sessionId, data);
    } catch (e) {
      sendToSession(sessionId, {
        'event': 'error',
        'message': 'Invalid message format',
      });
    }
  }
  
  Future<void> validateAndAuthenticate(String sessionId, String token) async {
    try {
      final result = await _pythonClient.validateToken(token);

      if (result['valid'] == true) {
        final newUserId = result['user_id'] ?? sessionId;

        _authenticatedSessions[sessionId] = true;
        _sessionToUser[sessionId] = newUserId;

        // Store rank and level from validation response
        final rank = result['rank'] as String?;
        final level = result['level'] as int?;
        if (rank != null || level != null) {
          setUserRankAndLevel(sessionId, rank, level);
        }

        final authenticatedPayload = <String, dynamic>{
          'event': 'authenticated',
          'session_id': sessionId,
          'user_id': result['user_id'],
          'message': 'Authentication successful',
        };
        final uidHint = '${result['user_id']}'.trim();
        if (uidHint.isNotEmpty) {
          final hr = resumableRoomHintForUser(uidHint);
          if (hr != null && hr.isNotEmpty) {
            authenticatedPayload['resumable_room_id'] = hr;
          }
        }
        sendToSession(sessionId, authenticatedPayload);
      } else {
        sendToSession(sessionId, {
          'event': 'authentication_failed',
          'message': result['error'] ?? 'Invalid token',
        });
      }
    } catch (e) {
      sendToSession(sessionId, {
          'event': 'authentication_error',
          'message': 'Authentication service unavailable',
      });
    }
  }
  
  void _onDisconnect(String sessionId) {
    // Get user's current room before cleanup
    final roomId = _roomManager.getRoomForSession(sessionId);
    final room = roomId != null ? _roomManager.getRoomInfo(roomId) : null;
    final userIdSnap = _sessionToUser[sessionId] ?? '';
    final wasAuth = isSessionAuthenticated(sessionId) && userIdSnap.trim().isNotEmpty;
    
    // Clean up connections and authentication
    _connections.remove(sessionId);
    _connectionHashes.remove(sessionId);
    _sessionMessageChain.remove(sessionId);
    _sessionToUser.remove(sessionId);
    _authenticatedSessions.remove(sessionId);
    _sessionToRank.remove(sessionId);
    _sessionToLevel.remove(sessionId);

    var scheduledGrace = false;
    if (roomId != null &&
        room != null &&
        _shouldOfferDisconnectGrace(
          wasAuthenticated: wasAuth,
          userId: userIdSnap,
          roomId: roomId,
        )) {
      scheduledGrace = _tryScheduleDisconnectGrace(
        disconnectedSessionId: sessionId,
        roomId: roomId,
        userId: userIdSnap,
      );
    }

    if (!scheduledGrace) {
      _roomManager.handleDisconnect(sessionId);

      if (roomId != null && room != null) {
        final after = _roomManager.getRoomInfo(roomId);
        broadcastToRoom(roomId, {
          'event': 'player_left',
          'room_id': roomId,
          'player_count': after?.currentSize ?? 0,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  void _onError(String sessionId, dynamic error) {}

  void sendToSession(String sessionId, Map<String, dynamic> message) {
    final connection = _connections[sessionId];

    if (connection != null) {
      try {
        final messageJson = jsonEncode(message);

        try {
          connection.sink.add(messageJson);
        } catch (_) {
          connection.sink.done.then((_) {
            _connections.remove(sessionId);
            _connectionHashes.remove(sessionId);
          }).catchError((_) {});
          rethrow;
        }
      } catch (_) {
        _connections.remove(sessionId);
        _connectionHashes.remove(sessionId);
      }
    }
  }

  /// Sends a core instant notification to a session.
  /// Event name: [kWsInstantNotificationEvent].
  /// [payload] should include: title, body, and optionally: data, responses, id, subtype.
  /// Responses: list of { label, action_identifier } for modal buttons.
  void sendInstantNotification(String sessionId, Map<String, dynamic> payload) {
    final message = Map<String, dynamic>.from(payload);
    message['event'] = kWsInstantNotificationEvent;
    sendToSession(sessionId, message);
  }

  /// Notify every authenticated WebSocket session mapped to [userId] (multi-tab / multi-device).
  /// Returns count of sessions that received the event.
  int notifyInboxChangedForUser(String userId) {
    if (userId.isEmpty) return 0;
    var n = 0;
    for (final e in _sessionToUser.entries) {
      if (e.value == userId && _connections.containsKey(e.key)) {
        sendToSession(e.key, {'event': kWsInboxChangedEvent});
        n++;
      }
    }
    return n;
  }

  /// Same side effects as handling an inbound `leave_room` message: remove [sessionId] from its
  /// room, optional random-join timer cleanup, send `leave_room_success`, run `leave_room` hook,
  /// then `player_left` to remaining members. Used when the game layer removes a player (e.g.
  /// missed-action kick) so they are no longer in the room and stop receiving room broadcasts.
  ///
  /// When [reason] is non-null and non-empty, it is included on `leave_room_success` and the hook
  /// payload (e.g. `removed_inactivity` for inactivity removal).
  void forceSessionLeaveRoom(String sessionId, {String? reason}) {
    final roomId = _roomManager.getRoomForSession(sessionId);
    if (roomId == null) {
      return;
    }
    final roomBefore = _roomManager.getRoomInfo(roomId);
    final gamePlayerSeat =
        roomBefore?.seatIdForSession(sessionId) ?? sessionId;
    final userId = getUserIdForSession(sessionId) ?? sessionId;

    _cancelDisconnectGraceForSession(sessionId);

    _roomManager.leaveRoom(sessionId);

    final roomAfter = _roomManager.getRoomInfo(roomId);

    final leaveSuccess = <String, dynamic>{
      'event': 'leave_room_success',
      'room_id': roomId,
      'session_id': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (reason != null && reason.isNotEmpty) {
      leaveSuccess['reason'] = reason;
    }
    sendToSession(sessionId, leaveSuccess);

    final hookData = <String, dynamic>{
      'room_id': roomId,
      'session_id': sessionId,
      'user_id': userId,
      'game_player_id': gamePlayerSeat,
      'left_at': DateTime.now().toIso8601String(),
    };
    if (reason != null && reason.isNotEmpty) {
      hookData['reason'] = reason;
    }
    triggerHook('leave_room', data: hookData);

    if (roomAfter != null) {
      broadcastToRoom(roomId, {
        'event': 'player_left',
        'room_id': roomId,
        'player_count': roomAfter.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    for (final sessionId in sessions) {
      sendToSession(sessionId, message);
    }
  }

  /// Returns active session IDs currently joined to [roomId].
  List<String> getSessionsInRoom(String roomId) {
    return List<String>.from(_roomManager.getSessionsInRoom(roomId));
  }

  /// Broadcast to all sessions in a room except the specified session
  /// 
  /// [roomId] The room ID to broadcast to
  /// [message] The message to send
  /// [excludeSessionId] The session ID to exclude from the broadcast
  void broadcastToRoomExcept(String roomId, Map<String, dynamic> message, String excludeSessionId) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    final filteredSessions = sessions.where((sessionId) => sessionId != excludeSessionId).toList();
    for (final sessionId in filteredSessions) {
      sendToSession(sessionId, message);
    }
  }
  
  int get connectionCount => _connections.length;
}
