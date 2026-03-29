import 'dart:convert';
import 'dart:math';
import 'room_manager.dart';
import 'websocket_server.dart';
import '../utils/server_logger.dart';
import '../utils/config.dart';
import 'random_join_timer_manager.dart';
import '../modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart';
import '../modules/dutch_game/backend_core/services/game_state_store.dart';
import '../modules/dutch_game/backend_core/services/game_registry.dart';
import '../modules/dutch_game/utils/platform/shared_imports.dart';
import '../modules/dutch_game/backend_core/utils/rank_matcher.dart';
import '../modules/dutch_game/backend_core/utils/level_matcher.dart';
import '../modules/dutch_game/backend_core/utils/wins_level_rank_matcher.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true; // create_room WS → RoomManager (enable-logging-switch.mdc)

/// Builds per-player rows for the game that just ended (`game_ended`, `winners` list),
/// for Python to persist as tournament `match_index` 1 when creating `single_room_league` on first rematch.
///
/// [GameRegistry._applyValidatedUpdates] merges `gamePhase` and `winners` onto the **store root**
/// (`mergeRoot`); inner [game_state] uses `phase` (not `gamePhase`) for broadcast. Read root first.
List<Map<String, dynamic>>? buildInitialMatchGameResultsForRematchSnapshot(
  Map<String, dynamic> storeRoot,
  String? Function(String sessionId) getUserIdForSession,
) {
  final gs = storeRoot['game_state'];
  final gsMap = gs is Map ? Map<String, dynamic>.from(gs) : null;

  final phaseRoot = storeRoot['gamePhase']?.toString() ?? '';
  final phaseInner = gsMap?['gamePhase']?.toString() ??
      gsMap?['phase']?.toString() ??
      '';
  final phase = phaseRoot.isNotEmpty ? phaseRoot : phaseInner;
  if (phase != 'game_ended') return null;

  final raw = storeRoot['winners'] ?? gsMap?['winners'];
  if (raw is! List || raw.isEmpty) return null;

  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final m = item.map((k, v) => MapEntry(k.toString(), v));
    final playerId = m['playerId']?.toString() ?? '';
    if (playerId.isEmpty) continue;
    var uid = getUserIdForSession(playerId);
    uid ??= m['userId']?.toString();
    if (uid == null || uid.isEmpty) continue;
    final winType = m['winType'];
    final isWinner = winType != null;
    final pts = m['points'];
    final cc = m['cardCount'];
    final pi = pts is num ? pts.toInt() : int.tryParse('$pts') ?? 0;
    final ci = cc is num ? cc.toInt() : int.tryParse('$cc') ?? 0;
    out.add({
      'user_id': uid,
      'is_winner': isWinner,
      'total_end_points': pi,
      'end_card_count': ci,
      'pot': 0,
      if (isWinner && winType != null) 'win_type': winType.toString(),
    });
  }
  return out.isEmpty ? null : out;
}

class MessageHandler {
  final RoomManager _roomManager;
  final WebSocketServer _server;
  final Logger _logger = Logger();
  late final GameEventCoordinator _gameCoordinator;

  MessageHandler(this._roomManager, this._server) {
    _gameCoordinator = GameEventCoordinator(_roomManager, _server);
  }

  /// True if accepted player entry is a computer player (bool or string "true"/"1" from JSON).
  static bool _isCompPlayer(Map<String, dynamic> e) {
    final v = e['is_comp_player'] ?? e['isCompPlayer'];
    if (v == true) return true;
    if (v is String && (v == 'true' || v == '1')) return true;
    return false;
  }

  static bool _coerceBool(dynamic v, {required bool ifNull}) {
    if (v == null) return ifNull;
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return ifNull;
  }

  /// Display / identity fields to carry across rematch; hands and round state are reset separately.
  static Map<String, dynamic> _lobbyPlayerExtrasFromPrevious(Map<String, dynamic> prev) {
    final out = <String, dynamic>{};
    final u = prev['username'];
    if (u is String && u.isNotEmpty) out['username'] = u;
    final pic = prev['profile_picture'];
    if (pic is String && pic.isNotEmpty) out['profile_picture'] = pic;
    final comp = prev['is_comp_player'] ?? prev['isCompPlayer'];
    if (comp != null) out['is_comp_player'] = comp;
    return out;
  }

  /// Verify user has enough coins to join/create a room (SSOT for all join flows).
  /// [roomGameTableLevel] is the room's table tier (1–4); required coins come from [LevelMatcher] only.
  /// Returns true only if subscription_tier is explicitly 'promotional' (skip coins) or coins >= required.
  /// No default tier; if no tier and no stats, fail (same as frontend).
  Future<bool> _verifyCoinsForJoin(String userId, int roomGameTableLevel) async {
    try {
      final result = await _server.pythonClient.getUserStatsForJoin(userId);
      if (result['success'] != true) {
        if (LOGGING_SWITCH) {
          _logger.room('📊 Coins check: getUserStatsForJoin failed for $userId: ${result['error']}');
        }
        return false;
      }
      final tier = (result['subscription_tier'] as String?)?.trim().toLowerCase() ?? '';
      if (tier == 'promotional') {
        if (LOGGING_SWITCH) {
          _logger.room('📊 Coins check: userId=$userId tier=promotional -> allow (skip coins)');
        }
        return true;
      }
      final coins = result['coins'] as int?;
      if (coins == null) {
        if (LOGGING_SWITCH) {
          _logger.room('📊 Coins check: no tier and no coins for $userId -> fail');
        }
        return false;
      }
      final required = LevelMatcher.tableLevelToCoinFee(roomGameTableLevel, defaultFee: 25);
      final ok = coins >= required;
      if (LOGGING_SWITCH) {
        _logger.room('📊 Coins check: userId=$userId roomTable=$roomGameTableLevel required=$required coins=$coins -> ${ok ? "ok" : "insufficient"}');
      }
      return ok;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Coins check error for $userId: $e');
      }
      return false;
    }
  }

  /// join_room_error payload for insufficient coins (client shows buy-coins flow).
  Map<String, dynamic> _joinRoomCoinErrorPayload({
    required String message,
    required String roomId,
    required int gameLevel,
  }) {
    final requiredCoins = LevelMatcher.tableLevelToCoinFee(gameLevel, defaultFee: 25);
    return {
      'event': 'join_room_error',
      'message': message,
      'room_id': roomId,
      'game_level': gameLevel,
      'required_coins': requiredCoins,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Unified event handler - ALL events come through here
  void handleMessage(String sessionId, Map<String, dynamic> data) {
    final event = data['event'] as String?;

    if (event == null) {
      if (LOGGING_SWITCH) {
        _logger.websocket('❌ Event validation failed: Missing event field from session: $sessionId, data keys: ${data.keys.toList()}');
      }
      _sendError(sessionId, 'Missing event field');
      return;
    }

    // Event validation logging
    if (LOGGING_SWITCH) {
      _logger.websocket('📨 Event validation: Received event "$event" from session: $sessionId');
      _logger.websocket('📦 Event validation: Event data keys: ${data.keys.join(', ')}');
      _logger.websocket('📦 Event validation: Event data: $data');
    }
    
    if (event == 'leave_room') {
      if (LOGGING_SWITCH) {
        _logger.websocket('🎯 LEAVE_ROOM: Received leave_room event from session: $sessionId, data keys: ${data.keys.toList()}');
      }
    }

    // Events that don't require authentication
    final publicEvents = {'ping', 'authenticate'};
    
    // Check authentication for room/game events
    if (!publicEvents.contains(event)) {
      if (!_server.isSessionAuthenticated(sessionId)) {
        if (LOGGING_SWITCH) {
          _logger.auth('❌ Event validation failed: Event $event requires authentication but session $sessionId is not authenticated');
        }
        _sendError(sessionId, 'Authentication required. Please wait for authentication to complete.');
        return;
      }
      if (LOGGING_SWITCH) {
        _logger.auth('✅ Event validation: Event $event authentication check passed for session: $sessionId');
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.auth('✅ Event validation: Event $event is a public event, skipping authentication');
      }
    }

    // Unified switch for ALL events
    switch (event) {
      // Connection events
      case 'ping':
        _handlePing(sessionId);
        break;
      case 'authenticate':
        _handleAuthenticate(sessionId, data);
        break;

      // Room management events
      case 'create_room':
        _handleCreateRoom(sessionId, data);
        break;
      case 'join_room':
        _handleJoinRoom(sessionId, data);
        break;
      case 'leave_room':
        _handleLeaveRoom(sessionId);
        break;
      case 'list_rooms':
        _handleListRooms(sessionId);
        break;
      case 'join_random_game':
        // Fire and forget - async operation for account type logging
        _handleJoinRandomGame(sessionId, data).catchError((e) {
          if (LOGGING_SWITCH) {
            _logger.error('❌ Error in _handleJoinRandomGame: $e');
          }
        });
        break;

      // Game events (all handled uniformly)
      case 'start_match':
        // Allow room owner to start match remotely (e.g. dashboard) when not in room: send start_match with game_id/room_id
        final inRoomId = _roomManager.getRoomForSession(sessionId);
        if (inRoomId == null) {
          final remoteRoomId = data['game_id'] as String? ?? data['room_id'] as String?;
          if (remoteRoomId != null && remoteRoomId.isNotEmpty) {
            final room = _roomManager.getRoomInfo(remoteRoomId);
            final userId = _server.getUserIdForSession(sessionId);
            if (room == null) {
              _sendError(sessionId, 'Room not found');
              break;
            }
            if (userId == null || room.ownerId != userId) {
              _sendError(sessionId, 'Only the room owner can start the match remotely');
              break;
            }
            if (LOGGING_SWITCH) {
              _logger.room(
                '🏟 Remote start_match (dashboard owner): room=$remoteRoomId userId=$userId',
              );
            }
            _startMatchForRoom(remoteRoomId);
            break;
          }
        }
        _handleGameEvent(sessionId, event, data);
        break;
      case 'draw_card':
      case 'play_card':
      case 'discard_card':
      case 'take_from_discard':
      case 'call_dutch':
      case 'call_final_round':
      case 'same_rank_play':
      case 'jack_swap':
      case 'queen_peek':
      case 'completed_initial_peek':
      case 'collect_from_discard':
        _handleGameEvent(sessionId, event, data);
        break;

      case 'rematch':
        _handleRematchStub(sessionId, data);
        break;

      case 'rematch_accepted':
      case 'rematch_declined':
        _handleRematchDecisionStub(sessionId, event, data);
        break;

      case 'start_rematch':
        _handleStartRematch(sessionId, data);
        break;

      default:
        _sendError(sessionId, 'Unknown event: $event');
    }
  }
  
  // ========= BASIC EVENT HANDLERS =========
  
  void _handlePing(String sessionId) {
    _server.sendToSession(sessionId, {
      'event': 'pong',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Client **rematch** (Play Again): duplicate guard via [Room.hasMatchRestarted], then `restart_invite` to others.
  /// Initiator is appended to [Room.rematchAccepted] only after [_verifyCoinsForJoin] succeeds; then
  /// [hasMatchRestarted] is set and invites go out. Match start runs only when every session is in
  /// [rematchAccepted] after their own coin checks ([_tryCompleteRematchIfReady]).
  ///
  /// TODO(rematch — eligibility): Before accepting rematch (when [Room.hasMatchRestarted] is false), verify
  /// **authoritative** game status / phase is `game_ended` (do not rely only on client `game_state`).
  /// Only then proceed with restart / tournament persistence.
  void _handleRematchStub(String sessionId, Map<String, dynamic> data) {
    final gameId = data['game_id'] as String?;
    final gameState = data['game_state'];
    final userId = data['user_id'] as String?;

    if (gameId == null || gameId.isEmpty) {
      _sendError(sessionId, 'rematch requires game_id');
      return;
    }

    final roomIdForSession = _roomManager.getRoomForSession(sessionId);
    if (roomIdForSession == null || roomIdForSession != gameId) {
      _sendError(sessionId, 'rematch: session not in room or game_id mismatch');
      return;
    }

    final room = _roomManager.getRoomInfo(gameId);
    if (room == null) {
      _sendError(sessionId, 'rematch: room not found');
      return;
    }
    if (!room.sessionIds.contains(sessionId)) {
      _sendError(sessionId, 'rematch: session not in room');
      return;
    }

    if (room.hasMatchRestarted) {
      print('[rematch] early exit: hasMatchRestarted=true room=$gameId session=$sessionId');
      return;
    }

    final resolvedUserId = userId ?? _server.getUserIdForSession(sessionId);
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      _sendError(sessionId, 'rematch: user id required');
      return;
    }
    final joinLevel = room.gameLevel ?? 1;

    _verifyCoinsForJoin(resolvedUserId, joinLevel).then((ok) {
      if (!ok) {
        if (LOGGING_SWITCH) {
          _logger.room('📊 Coins check: rematch failed for $resolvedUserId room=$gameId');
        }
        _server.sendToSession(
          sessionId,
          _joinRoomCoinErrorPayload(
            message: 'Insufficient coins to start a rematch at this table. Check your balance.',
            roomId: gameId,
            gameLevel: joinLevel,
          ),
        );
        return;
      }

      final r = _roomManager.getRoomInfo(gameId);
      if (r == null || !r.sessionIds.contains(sessionId)) {
        return;
      }
      if (r.hasMatchRestarted) {
        print('[rematch] coin ok but another rematch already started room=$gameId');
        return;
      }

      r.rematchPendingTimer?.cancel();
      r.rematchInitiatorSessionId = sessionId;
      r.rematchInitiatorUserId = resolvedUserId;
      r.rematchAccepted.clear();
      r.rematchDeclined.clear();
      // Seed initiator only after coin check — peers are added the same way in [rematch_accepted].
      r.rematchAccepted.add({
        'session_id': sessionId,
        'user_id': resolvedUserId,
      });
      r.hasMatchRestarted = true;

      if (LOGGING_SWITCH) {
        _logger.websocket(
          '🔄 rematch: sessionId=$sessionId user_id=$resolvedUserId game_id=$gameId keys=${data.keys.toList()}',
        );
      }

      print('[rematch] sessionId=$sessionId user_id=$resolvedUserId game_id=$gameId — broadcasting restart_invite to others');
      try {
        if (gameState is Map) {
          final encoded = jsonEncode(gameState);
          final preview =
              encoded.length > 8000 ? '${encoded.substring(0, 8000)}…(truncated, len=${encoded.length})' : encoded;
          print('[rematch] game_state: $preview');
        } else {
          print('[rematch] game_state: ${gameState?.toString() ?? 'null'} (not a Map)');
        }
      } catch (e, st) {
        print('[rematch] game_state log error: $e\n$st');
      }

      var isCoinRequired = true;
      try {
        final gs = GameStateStore.instance.getGameState(gameId);
        final v = gs['isCoinRequired'];
        if (v is bool) {
          isCoinRequired = v;
        }
      } catch (_) {}

      _server.broadcastToRoomExcept(
        gameId,
        {
          'event': 'restart_invite',
          'room_id': gameId,
          'game_id': gameId,
          'from_session_id': sessionId,
          'from_user_id': resolvedUserId,
          'game_level': joinLevel,
          'is_coin_required': isCoinRequired,
          'timestamp': DateTime.now().toIso8601String(),
        },
        sessionId,
      );
    });
  }

  /// Clears [Room.hasMatchRestarted] when a new match is about to start.
  void _resetMatchRestartedFlag(String roomId) {
    final room = _roomManager.getRoomInfo(roomId);
    if (room != null) {
      room.hasMatchRestarted = false;
    }
  }

  /// Peer responded to `restart_invite` (Accept / Decline).
  /// For [rematch_accepted], the session is appended to [Room.rematchAccepted] only after
  /// [_verifyCoinsForJoin] succeeds — never before. Then [_tryCompleteRematchIfReady] runs;
  /// [_handleStartRematch] is invoked only when every [Room.sessionIds] entry is in [rematchAccepted].
  void _handleRematchDecisionStub(String sessionId, String event, Map<String, dynamic> data) {
    final gameId = data['game_id'] as String? ?? data['room_id'] as String?;
    if (gameId == null || gameId.isEmpty) {
      _sendError(sessionId, 'rematch decision requires game_id or room_id');
      return;
    }
    final room = _roomManager.getRoomInfo(gameId);
    if (room == null) {
      _sendError(sessionId, 'rematch decision: room not found');
      return;
    }
    if (!room.sessionIds.contains(sessionId)) {
      _sendError(sessionId, 'rematch decision: session not in room');
      return;
    }
    if (!room.hasMatchRestarted) {
      return;
    }

    final userId = data['user_id'] as String? ?? _server.getUserIdForSession(sessionId) ?? '';
    final entry = <String, dynamic>{
      'session_id': sessionId,
      'user_id': userId,
    };

    if (event == 'rematch_declined') {
      if (!_rematchEntryHasSession(room.rematchDeclined, sessionId)) {
        room.rematchDeclined.add(entry);
      }
      room.rematchPendingTimer?.cancel();
      room.rematchPendingTimer = null;
      _clearRematchLobbyRoom(room);
      room.hasMatchRestarted = false;
      print('[rematch_declined] sessionId=$sessionId user_id=$userId room=$gameId — rematch cancelled');
      return;
    }

    if (event == 'rematch_accepted') {
      if (userId.isEmpty) {
        _sendError(sessionId, 'rematch_accepted: user id required');
        return;
      }
      // Idempotent: already recorded after a prior successful coin check.
      if (_rematchEntryHasSession(room.rematchAccepted, sessionId)) {
        _tryCompleteRematchIfReady(gameId);
        return;
      }

      final acceptEntry = <String, dynamic>{
        'session_id': sessionId,
        'user_id': userId,
      };
      final joinLevel = room.gameLevel ?? 1;
      _verifyCoinsForJoin(userId, joinLevel).then((ok) {
        if (!ok) {
          if (LOGGING_SWITCH) {
            _logger.room('📊 Coins check: rematch_accepted failed for $userId room=$gameId');
          }
          _server.sendToSession(
            sessionId,
            _joinRoomCoinErrorPayload(
              message: 'Insufficient coins to accept this rematch. Check your balance.',
              roomId: gameId,
              gameLevel: joinLevel,
            ),
          );
          return;
        }
        final r = _roomManager.getRoomInfo(gameId);
        if (r == null || !r.sessionIds.contains(sessionId) || !r.hasMatchRestarted) {
          return;
        }
        // Only append after coin verification; do not add on failed or pending coin paths.
        if (!_rematchEntryHasSession(r.rematchAccepted, sessionId)) {
          r.rematchAccepted.add(acceptEntry);
        }
        _tryCompleteRematchIfReady(gameId);
      });
    }
  }

  bool _rematchEntryHasSession(List<Map<String, dynamic>> list, String sessionId) {
    return list.any((e) => e['session_id'] == sessionId);
  }

  /// True when every [Room.sessionIds] session appears in [Room.rematchAccepted]
  /// (initiator seeded after coin check on `rematch`; others after coin check on `rematch_accepted`).
  bool _allSessionsAcceptedRematch(Room room) {
    final needed = room.sessionIds.toSet();
    if (needed.isEmpty) return false;
    final accepted = room.rematchAccepted
        .map((e) => e['session_id'] as String?)
        .whereType<String>()
        .toSet();
    return needed.every(accepted.contains);
  }

  void _clearRematchLobbyRoom(Room room) {
    room.rematchPendingTimer?.cancel();
    room.rematchPendingTimer = null;
    room.rematchAccepted.clear();
    room.rematchDeclined.clear();
    room.rematchInitiatorSessionId = null;
    room.rematchInitiatorUserId = null;
  }

  /// When [Room.rematchAccepted] contains every session in [Room.sessionIds] (each added only after
  /// that session's coin check), starts the rematch flow.
  void _tryCompleteRematchIfReady(String roomId) {
    final room = _roomManager.getRoomInfo(roomId);
    if (room == null || !room.hasMatchRestarted) return;
    if (!_allSessionsAcceptedRematch(room)) return;
    if (room.rematchDeclined.isNotEmpty) return;

    room.rematchPendingTimer?.cancel();
    room.rematchPendingTimer = null;

    final initiatorSid = room.rematchInitiatorSessionId ?? room.sessionIds.first;
    _handleStartRematch(initiatorSid, {
      'room_id': roomId,
      'game_id': roomId,
      if (room.rematchInitiatorUserId != null && room.rematchInitiatorUserId!.isNotEmpty)
        'user_id': room.rematchInitiatorUserId,
      'trigger': 'all_accepted',
    });
  }

  /// Sends pre-reset [GameStateStore] root + [Room] snapshot to Python (`/service/dutch/rematch-tournament-snapshot`).
  /// On success, sets [Room.pendingRematchTournamentData] for the next [_resetGameStateForRematch]. Rematch continues if the call fails.
  Future<void> _notifyRematchTournamentPython(String roomId, Room room) async {
    Map<String, dynamic> storeSnapshot;
    try {
      final storeRoot = GameStateStore.instance.getState(roomId);
      storeSnapshot = jsonDecode(jsonEncode(storeRoot)) as Map<String, dynamic>;
    } catch (e, st) {
      if (LOGGING_SWITCH) {
        _logger.error('rematch tournament snapshot: store JSON encode failed: $e\n$st');
      }
      storeSnapshot = {
        'error': 'store_encode_failed',
        'detail': e.toString(),
      };
    }

    final roomSnapshot = <String, dynamic>{
      ...room.toJson(),
      'session_ids': List<String>.from(room.sessionIds),
      'is_random_join': room.isRandomJoin,
      'has_match_restarted': room.hasMatchRestarted,
      'rematch_accepted': room.rematchAccepted
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      'rematch_declined': room.rematchDeclined
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      'rematch_initiator_session_id': room.rematchInitiatorSessionId,
      'rematch_initiator_user_id': room.rematchInitiatorUserId,
    };
    if (room.acceptedPlayers != null && room.acceptedPlayers!.isNotEmpty) {
      roomSnapshot['accepted_players'] = room.acceptedPlayers!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final initialMatch = buildInitialMatchGameResultsForRematchSnapshot(
      storeSnapshot,
      _server.getUserIdForSession,
    );
    final result = await _server.pythonClient.notifyRematchTournamentSnapshot(
      roomId: roomId,
      storeSnapshot: storeSnapshot,
      roomSnapshot: roomSnapshot,
      initialMatchGameResults: initialMatch,
    );
    room.pendingRematchTournamentData = null;
    if (result['success'] == true) {
      final td = result['tournament_data'];
      if (td is Map) {
        final merged = Map<String, dynamic>.from(td);
        final topTid = result['tournament_id']?.toString();
        if (topTid != null && topTid.isNotEmpty) {
          merged['tournament_id'] = merged['tournament_id'] ?? topTid;
        }
        room.pendingRematchTournamentData = merged;
        // Persist on Room so start_match, game end stats, and join payloads see tournament context.
        room.isTournament = true;
        room.tournamentData = merged;
      }
    }
    if (LOGGING_SWITCH) {
      _logger.room(
        '📤 rematch-tournament-snapshot room=$roomId success=${result['success']}',
      );
    }
  }

  /// Drop prior round + store; recreate [DutchGameRound] and a fresh `waiting_for_players` blob matching
  /// [GameStateStore.ensure] / `room_created` shape (same [roomId] as `game_id`).
  ///
  /// Preserves room-level intent from [Room] + pre-reset store (e.g. `isClearAndCollect` on root for random
  /// join, `isCoinRequired`, player names / profile fields). Strips gameplay-only state (hands, known_cards,
  /// piles, round flags) by rebuilding the lobby from scratch.
  void _resetGameStateForRematch(String roomId) {
    final room = _roomManager.getRoomInfo(roomId);
    if (room == null) return;

    final store = GameStateStore.instance;
    Map<String, dynamic> prevGs = {};
    Map<String, dynamic> prevRoot = {};
    try {
      final raw = store.getState(roomId);
      prevRoot = Map<String, dynamic>.from(raw);
      final gs = raw['game_state'];
      if (gs is Map<String, dynamic>) {
        prevGs = Map<String, dynamic>.from(gs);
      }
    } catch (_) {}

    final prevPlayersById = <String, Map<String, dynamic>>{};
    final pl = prevGs['players'];
    if (pl is List) {
      for (final p in pl) {
        if (p is Map<String, dynamic>) {
          final id = p['id']?.toString();
          if (id != null && id.isNotEmpty) {
            prevPlayersById[id] = Map<String, dynamic>.from(p);
          }
        }
      }
    }

    GameRegistry.instance.dispose(roomId);
    GameRegistry.instance.getOrCreate(roomId, _server);

    final players = <Map<String, dynamic>>[];
    for (final sid in room.sessionIds) {
      final uid = _server.getUserIdForSession(sid) ?? '';
      final prevP = prevPlayersById[sid];
      final short = sid.length > 8 ? 8 : sid.length;
      final fallbackName = 'Player_${sid.substring(0, short)}';
      final fromPrevName = prevP?['name']?.toString().trim();
      players.add({
        'id': sid,
        'name': (fromPrevName != null && fromPrevName.isNotEmpty) ? fromPrevName : fallbackName,
        'isHuman': prevP?['isHuman'] ?? true,
        'status': 'waiting',
        'hand': <Map<String, dynamic>>[],
        'visible_cards': <Map<String, dynamic>>[],
        'points': 0,
        'known_cards': <String, dynamic>{},
        'collection_rank_cards': <String>[],
        'isActive': true,
        if (uid.isNotEmpty) 'userId': uid,
        if (prevP != null) ..._lobbyPlayerExtrasFromPrevious(prevP),
      });
    }

    final defaultClearCollect = room.gameType == 'clear_and_collect';
    final isClearAndCollectRoot = prevRoot.containsKey('isClearAndCollect')
        ? _coerceBool(prevRoot['isClearAndCollect'], ifNull: defaultClearCollect)
        : defaultClearCollect;

    final isCoinRequired = _coerceBool(prevGs['isCoinRequired'], ifNull: true);

    Map<String, dynamic>? effectiveTournamentData;
    if (room.pendingRematchTournamentData != null &&
        room.pendingRematchTournamentData!.isNotEmpty) {
      effectiveTournamentData =
          Map<String, dynamic>.from(room.pendingRematchTournamentData!);
    } else if (room.tournamentData != null && room.tournamentData!.isNotEmpty) {
      effectiveTournamentData = Map<String, dynamic>.from(room.tournamentData!);
    }
    final includeTournament = room.isTournament ||
        (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty);

    final gameStateInner = <String, dynamic>{
      'gameId': roomId,
      'gameName': 'Game_$roomId',
      'gameType': room.gameType,
      'maxPlayers': room.maxSize,
      'minPlayers': room.minPlayers,
      'isGameActive': false,
      'phase': 'waiting_for_players',
      'playerCount': players.length,
      'players': players,
      'drawPile': <Map<String, dynamic>>[],
      'discardPile': <Map<String, dynamic>>[],
      'originalDeck': <Map<String, dynamic>>[],
      if (room.gameLevel != null) 'gameLevel': room.gameLevel,
      'isCoinRequired': isCoinRequired,
      'permission': room.permission,
      'created_at': room.createdAt.toIso8601String(),
      'current_size': room.sessionIds.length,
      'owner_id': room.ownerId,
      if (includeTournament) 'is_tournament': true,
      if (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty)
        'tournament_data': effectiveTournamentData,
      if (room.rematchInitiatorUserId != null && room.rematchInitiatorUserId!.isNotEmpty)
        'rematch_creator_id': room.rematchInitiatorUserId,
    };

    room.pendingRematchTournamentData = null;

    store.mergeRoot(roomId, {
      'game_id': roomId,
      'roomDifficulty': room.difficulty ?? prevRoot['roomDifficulty'],
      'isClearAndCollect': isClearAndCollectRoot,
      'game_state': gameStateInner,
    });
  }

  /// After [Room.rematchAccepted] lists every in-room session (post coin-check) and none declined:
  /// [GameRegistry] reset, fresh lobby state, then [_startMatchForRoom].
  Future<void> _handleStartRematch(String sessionId, Map<String, dynamic> data) async {
    if (LOGGING_SWITCH) {
      _logger.websocket('start_rematch sessionId=$sessionId keys=${data.keys.toList()}');
    }
    final trigger = data['trigger'] as String?;
    final gameId = data['game_id'] as String? ?? data['room_id'] as String?;
    print(
      '[start_rematch] sessionId=$sessionId trigger=$trigger room_id=${data['room_id']} game_id=$gameId',
    );

    if (gameId == null || gameId.isEmpty) {
      _sendError(sessionId, 'start_rematch requires game_id');
      return;
    }

    final roomIdForSession = _roomManager.getRoomForSession(sessionId);
    if (roomIdForSession != gameId) {
      _sendError(sessionId, 'start_rematch: session not in room');
      return;
    }

    final room = _roomManager.getRoomInfo(gameId);
    if (room == null) {
      _sendError(sessionId, 'start_rematch: room not found');
      return;
    }

    room.rematchPendingTimer?.cancel();
    room.rematchPendingTimer = null;

    if (room.rematchDeclined.isNotEmpty) {
      print('[start_rematch] aborted: room has declines');
      _clearRematchLobbyRoom(room);
      room.hasMatchRestarted = false;
      return;
    }

    if (!_allSessionsAcceptedRematch(room)) {
      print('[start_rematch] skip: not all sessions accepted (trigger=$trigger)');
      return;
    }

    await _notifyRematchTournamentPython(gameId, room);
    _resetGameStateForRematch(gameId);
    _startMatchForRoom(gameId);
    _clearRematchLobbyRoom(room);
  }

  // ========= ROOM MANAGEMENT HANDLERS =========
  
  void _handleCreateRoom(String sessionId, Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      _logger.room('📥 create_room received: sessionId=$sessionId, data keys=${data.keys.toList()}, game_type=${data['game_type'] ?? data['gameType']}, permission=${data['permission']}, auto_start=${data['auto_start'] ?? data['autoStart']}, tournamentName=${data['tournament_name'] ?? data['tournamentName']}, tournamentFormat=${data['tournament_format'] ?? data['tournamentFormat']}');
    }
    // UserId: session mapping is SSOT (set at authenticate). Payload user_id is fallback when session is null (e.g. race).
    var userId = _server.getUserIdForSession(sessionId);
    if (userId == null) {
      final payloadUserId = data['user_id'] as String?;
      if (payloadUserId != null && payloadUserId.isNotEmpty) {
        userId = payloadUserId;
        _server.updateSessionUserId(sessionId, userId);
        if (LOGGING_SWITCH) {
          _logger.room('📥 _handleCreateRoom: Using payload user_id (session was null): $userId');
        }
      }
    }
    if (userId == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleCreateRoom: Session $sessionId has no userId (session or payload)');
      }
      _sendError(sessionId, 'User ID not available. Please reconnect.');
      return;
    }

    // Extract room settings from data (matching Python backend)
    // max_players from payload; default 4 if not passed, clamp 2-4
    final maxPlayersRaw = data['max_players'] as int? ?? data['maxPlayers'] as int?;
    final maxPlayers = (maxPlayersRaw != null && maxPlayersRaw >= 2 && maxPlayersRaw <= 4)
        ? maxPlayersRaw
        : 4;
    final minPlayers = data['min_players'] as int? ?? data['minPlayers'] as int?;
    final gameType = data['game_type'] as String? ?? data['gameType'] as String?;
    final permission = data['permission'] as String?;
    final password = data['password'] as String?;
    final autoStart = data['auto_start'] as bool? ?? data['autoStart'] as bool?;
    final isTournament = data['is_tournament'] as bool? ?? data['isTournament'] as bool? ?? false;
    final tournamentData = data['tournament_data'] as Map<String, dynamic>? ?? data['tournamentData'] as Map<String, dynamic>?;
    final acceptedPlayersRaw = data['accepted_players'] ?? data['acceptedPlayers'];
    final List<Map<String, dynamic>>? acceptedPlayers = acceptedPlayersRaw is List
        ? acceptedPlayersRaw.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList()
        : null;
    final addCreatorToRoom = data['add_creator_to_room'] as bool? ?? data['addCreatorToRoom'] as bool? ?? true;
    final gameLevel = data['game_level'] as int? ?? data['gameLevel'] as int?;
    final isCoinRequired =
        data['is_coin_required'] as bool? ?? data['isCoinRequired'] as bool? ?? true;

    // Log create_room payload for debugging (visible in container logs)
    print('[create_room] payload: is_tournament=$isTournament is_coin_required=$isCoinRequired add_creator_to_room=$addCreatorToRoom auto_start=$autoStart min_players=$minPlayers max_players=$maxPlayers');
    print('[create_room] accepted_players count=${acceptedPlayers?.length ?? 0}');
    if (acceptedPlayers != null && acceptedPlayers.isNotEmpty) {
      for (var i = 0; i < acceptedPlayers.length; i++) {
        final p = acceptedPlayers[i];
        print('[create_room]   accepted_players[$i]: user_id=${p['user_id']} username=${p['username']} is_comp_player=${p['is_comp_player']}');
      }
    }

    final uid = userId;
    Future<void> doCreateRoom() async {
      try {
        // Create room with settings (timer values are now phase-based, managed by RoomManager)
        final roomId = _roomManager.createRoom(
        sessionId,
        uid,
        maxSize: maxPlayers,
        minPlayers: minPlayers,
        gameType: gameType,
        permission: permission,
        password: password,
        autoStart: autoStart,
        gameLevel: gameLevel,
        acceptedPlayers: acceptedPlayers?.isNotEmpty == true ? acceptedPlayers : null,
        addCreatorToRoom: addCreatorToRoom,
        isTournament: isTournament,
        tournamentData: tournamentData,
      );
      
      // Get room info for response
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        _sendError(sessionId, 'Failed to create room');
        return;
      }

      Map<String, dynamic>? effectiveTournamentData = tournamentData != null
          ? Map<String, dynamic>.from(tournamentData)
          : null;

      // Tournament: attach room in Python DB and merge match roster (comps + humans) into tournament_data before room_created hook
      if (isTournament &&
          effectiveTournamentData != null &&
          effectiveTournamentData.isNotEmpty) {
        final tid = (effectiveTournamentData['tournament_id']?.toString() ?? '').trim();
        final mid = effectiveTournamentData['match_index'] ?? effectiveTournamentData['match_id'];
        if (tid.isNotEmpty && mid != null) {
          if (LOGGING_SWITCH) {
            _logger.room('🏟 Tournament room: attach-tournament-match-room (await) tournament_id=$tid match_id=$mid room_id=$roomId');
          }
          final result = await _server.pythonClient.attachTournamentMatchRoom(
            tournamentId: tid,
            roomId: roomId,
            matchIndex: mid,
          );
          if (result['success'] == true) {
            final mp = result['match_players'];
            if (mp is List && mp.isNotEmpty) {
              effectiveTournamentData['match_players'] = mp;
              room.tournamentData = effectiveTournamentData;
              if (LOGGING_SWITCH) {
                _logger.room('🏟 Merged match_players into tournament_data count=${mp.length}');
              }
            }
          } else if (LOGGING_SWITCH) {
            _logger.game('⚠️ attach-tournament-match-room failed: ${result['error']}');
          }
        }
      }

      if (LOGGING_SWITCH) {
        final roomData = Map<String, dynamic>.from(room.toJson())
          ..['session_ids'] = room.sessionIds
          ..['is_random_join'] = room.isRandomJoin;
        if (room.acceptedPlayers != null) roomData['accepted_players'] = room.acceptedPlayers;
        _logger.room('📋 _handleCreateRoom room data: $roomData');
      }

      // Send create_room_success (primary event matching Python)
      final createSuccessPayload = {
        'event': 'create_room_success',
        'room_id': roomId,
        'owner_id': room.ownerId,
        'creator_id': room.ownerId, // Keep for compatibility
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'auto_start': room.autoStart,
        'difficulty': room.difficulty, // Room difficulty (rank-based)
        'is_random_join': false, // Lobby / explicit create — client skips auto-nav to play
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (isTournament) createSuccessPayload['is_tournament'] = true;
      if (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty) {
        createSuccessPayload['tournament_data'] = effectiveTournamentData;
      }
      if (room.acceptedPlayers != null && room.acceptedPlayers!.isNotEmpty) {
        createSuccessPayload['accepted_players'] = room.acceptedPlayers;
      }
      if (room.gameLevel != null) createSuccessPayload['game_level'] = room.gameLevel;
      createSuccessPayload['is_coin_required'] = isCoinRequired;
      _server.sendToSession(sessionId, createSuccessPayload);
      
      // 🎣 Trigger room_created hook (Dutch uses add_creator_to_room to decide whether to add creator as first player in game state)
      final roomCreatedData = {
        'room_id': roomId,
        'owner_id': room.ownerId,
        'session_id': sessionId, // Add session_id for player ID assignment
        'add_creator_to_room': addCreatorToRoom,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'created_at': DateTime.now().toIso8601String(),
      };
      if (isTournament) roomCreatedData['is_tournament'] = true;
      if (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty) {
        roomCreatedData['tournament_data'] = effectiveTournamentData;
      }
      if (room.gameLevel != null) roomCreatedData['game_level'] = room.gameLevel!;
      roomCreatedData['is_coin_required'] = isCoinRequired;
      if (LOGGING_SWITCH) {
        _logger.room('🎣 Triggering room_created hook: roomId=$roomId add_creator_to_room=$addCreatorToRoom is_tournament=$isTournament is_coin_required=$isCoinRequired');
      }
      _server.triggerHook('room_created', data: roomCreatedData);
      
      // When addCreatorToRoom is true, send room_joined and trigger hook (auto-join creator like Python does)
      if (addCreatorToRoom) {
        final level = room.gameLevel ?? gameLevel ?? 1;
        final creatorRoomJoinedPayload = {
          'event': 'room_joined',
          'room_id': roomId,
          'session_id': sessionId,
        'user_id': uid,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': level,
        'timestamp': DateTime.now().toIso8601String(),
        };
        if (isTournament) creatorRoomJoinedPayload['is_tournament'] = true;
        if (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty) {
          creatorRoomJoinedPayload['tournament_data'] = effectiveTournamentData;
        }
        // Keep invite roster on the payload that follows create_room_success so clients
        // merging room state do not drop accepted_players (play screen Start / effective count).
        final ap = room.acceptedPlayers;
        if (ap != null && ap.isNotEmpty) {
          creatorRoomJoinedPayload['accepted_players'] =
              List<Map<String, dynamic>>.from(ap);
        }
        creatorRoomJoinedPayload['min_players'] = room.minPlayers;
        _server.sendToSession(sessionId, creatorRoomJoinedPayload);
        
        final creatorRoomJoinedHookData = {
          'room_id': roomId,
          'session_id': sessionId,
          'user_id': uid,
          'owner_id': room.ownerId,
          'current_size': room.currentSize,
          'max_size': room.maxSize,
          'game_level': level,
          'joined_at': DateTime.now().toIso8601String(),
        };
        if (isTournament) creatorRoomJoinedHookData['is_tournament'] = true;
        if (effectiveTournamentData != null && effectiveTournamentData.isNotEmpty) {
          creatorRoomJoinedHookData['tournament_data'] = effectiveTournamentData;
        }
        _server.triggerHook('room_joined', data: creatorRoomJoinedHookData);
      }

      // Create-room (invite or tournament) with autoStart: do not wait for comp players to join (they never do).
      // effectiveMax = maxSize - compCount; if already reached at create (e.g. all-comp or tournament 0 humans), start now.
      if (room.autoStart == true && room.isRandomJoin != true) {
        final compCount = room.acceptedPlayers
            ?.where((e) => _isCompPlayer(e))
            .length ?? 0;
        final effectiveMax = room.maxSize - compCount;
        print('[create_room] at create: roomId=$roomId currentSize=${room.currentSize} compCount=$compCount effectiveMax=$effectiveMax (start=${room.currentSize >= effectiveMax})');
        if (room.currentSize >= effectiveMax) {
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Effective max reached at create ($room.currentSize >= $effectiveMax, compCount=$compCount), starting match for create-room: $roomId');
          }
          _startMatchForRoom(roomId);
        }
      }

      if (LOGGING_SWITCH) {
        _logger.room(addCreatorToRoom
            ? '✅ Room created and creator auto-joined: $roomId'
            : '✅ Room created (creator not in room): $roomId');
      }
      
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Failed to create room: $e');
        }
        _server.sendToSession(sessionId, {
          'event': 'create_room_error',
          'message': 'Failed to create room: $e',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    if (addCreatorToRoom) {
      final createGameLevel = gameLevel ?? 1;
      final creatorUserLevel = _server.getUserLevelForSession(sessionId) ?? 1;
      if (!WinsLevelRankMatcher.userMayJoinGameTable(creatorUserLevel, createGameLevel)) {
        _server.sendToSession(sessionId, {
          'event': 'create_room_error',
          'message':
              'Your level ($creatorUserLevel) is too low for this table (requires level $createGameLevel or higher). Win more games to increase your level.',
          'timestamp': DateTime.now().toIso8601String(),
        });
        if (LOGGING_SWITCH) {
          _logger.room('❌ create_room: table gate userLevel=$creatorUserLevel gameLevel=$createGameLevel');
        }
        return;
      }
      if (LOGGING_SWITCH) {
        _logger.room('📊 Coins check: create_room (creator auto-join) -> verifying userId=$userId level=$createGameLevel');
      }
      _verifyCoinsForJoin(userId, createGameLevel).then((ok) {
        if (!ok) {
          if (LOGGING_SWITCH) {
            _logger.room('📊 Coins check: create_room failed for $userId -> sending create_room_error');
          }
          _server.sendToSession(sessionId, {
            'event': 'create_room_error',
            'message': 'Insufficient coins to create a game. Check your balance.',
            'timestamp': DateTime.now().toIso8601String(),
          });
          return;
        }
        doCreateRoom();
      });
    } else {
      doCreateRoom();
    }
  }
  
  void _handleJoinRoom(String sessionId, Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    final gameLevel = data['game_level'] as int? ?? data['gameLevel'] as int? ?? 1;
    final isTournament = data['is_tournament'] as bool? ?? data['isTournament'] as bool? ?? false;
    final tournamentData = data['tournament_data'] as Map<String, dynamic>? ?? data['tournamentData'] as Map<String, dynamic>?;
    
    // UserId: session mapping is SSOT. Payload user_id is fallback when session is null.
    var userId = _server.getUserIdForSession(sessionId);
    if (userId == null) {
      final payloadUserId = data['user_id'] as String?;
      if (payloadUserId != null && payloadUserId.isNotEmpty) {
        userId = payloadUserId;
        _server.updateSessionUserId(sessionId, userId);
        if (LOGGING_SWITCH) {
          _logger.room('📥 _handleJoinRoom: Using payload user_id (session was null): $userId');
        }
      }
    }
    if (userId == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleJoinRoom: Session $sessionId has no userId (session or payload)');
      }
      _sendError(sessionId, 'User ID not available. Please reconnect.');
      return;
    }

    if (roomId == null) {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'No room_id provided',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }
    
    // Check if room exists
    final room = _roomManager.getRoomInfo(roomId);
    if (room == null) {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'Room $roomId not found',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }
    if (LOGGING_SWITCH) {
      final roomData = Map<String, dynamic>.from(room.toJson())
        ..['session_ids'] = room.sessionIds
        ..['is_random_join'] = room.isRandomJoin;
      if (room.acceptedPlayers != null) roomData['accepted_players'] = room.acceptedPlayers;
      _logger.room('📋 _handleJoinRoom room data: $roomData');
    }

    // Check if user is already in room
    if (_roomManager.isUserInRoom(sessionId, roomId)) {
      // Send already_joined event (matching Python behavior)
      _server.sendToSession(sessionId, {
        'event': 'already_joined',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': room.gameLevel ?? 1,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.room('⚠️  User $userId already in room $roomId');
      }
      return;
    }
    
    // Check room capacity
    if (!_roomManager.canJoinRoom(roomId)) {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'Room $roomId is full',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    // Validate rank compatibility (if room has difficulty set and user has rank)
    final userRank = _server.getUserRankForSession(sessionId);
    if (room.difficulty != null && userRank != null) {
      final roomDifficulty = room.difficulty!.toLowerCase();
      final normalizedUserRank = userRank.toLowerCase();

      // Check if ranks are compatible (±1)
      if (!RankMatcher.areRanksCompatible(roomDifficulty, normalizedUserRank)) {
        _server.sendToSession(sessionId, {
          'event': 'join_room_error',
          'message': 'Your rank ($userRank) is not compatible with this room\'s difficulty ($roomDifficulty). You can only join rooms within ±1 rank of your own.',
          'timestamp': DateTime.now().toIso8601String(),
        });
        if (LOGGING_SWITCH) {
          _logger.room('❌ Rank mismatch: user rank=$userRank, room difficulty=$roomDifficulty');
        }
        return;
      }
    }
    // If room difficulty is null (first human) or user has no rank, allow join (fallback behavior)

    final joinLevel = room.gameLevel ?? gameLevel;
    final joinerUserLevel = _server.getUserLevelForSession(sessionId) ?? 1;
    if (!WinsLevelRankMatcher.userMayJoinGameTable(joinerUserLevel, joinLevel)) {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message':
            'Your level ($joinerUserLevel) is too low for this table (requires level $joinLevel or higher). Win more games to increase your level.',
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (LOGGING_SWITCH) {
        _logger.room('❌ join_room: table gate userLevel=$joinerUserLevel joinLevel=$joinLevel');
      }
      return;
    }
    final String jr = roomId;
    final String ju = userId;
    final joinGameState = GameStateStore.instance.getGameState(jr);
    final joinCoinReqRaw = joinGameState['isCoinRequired'];
    final matchRequiresCoinsForJoin =
        joinCoinReqRaw is bool ? joinCoinReqRaw : true;

    void completeJoinAfterOptionalCoinCheck() {
      if (LOGGING_SWITCH) {
        _logger.room('🔍 _handleJoinRoom: About to join room with sessionId=$sessionId, userId=$ju, roomId=$jr');
      }
      if (_roomManager.joinRoom(jr, sessionId, ju)) {
      // Send join_room_success (primary event matching Python)
      if (LOGGING_SWITCH) {
        _logger.room('📤 Sending join_room_success to session: $sessionId (userId=$ju)');
        _logger.room('🔍 VERIFY: Using sessionId=$sessionId for sendToSession, NOT userId=$ju');
      }
      final joinSuccessPayload = {
        'event': 'join_room_success',
        'room_id': jr,
        'session_id': sessionId,
        'user_id': ju,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'difficulty': room.difficulty, // Room difficulty (rank-based)
        'game_level': gameLevel,
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (isTournament) joinSuccessPayload['is_tournament'] = true;
      if (tournamentData != null && tournamentData.isNotEmpty) joinSuccessPayload['tournament_data'] = tournamentData;
      _server.sendToSession(sessionId, joinSuccessPayload);
      
      // Also send room_joined for backward compatibility
      if (LOGGING_SWITCH) {
        _logger.room('📤 Sending room_joined to session: $sessionId');
      }
      final roomJoinedPayload = {
        'event': 'room_joined',
        'room_id': jr,
        'session_id': sessionId,
        'user_id': ju,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': joinLevel,
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (isTournament) roomJoinedPayload['is_tournament'] = true;
      if (tournamentData != null && tournamentData.isNotEmpty) roomJoinedPayload['tournament_data'] = tournamentData;
      _server.sendToSession(sessionId, roomJoinedPayload);
      
      // 🎣 Trigger room_joined hook
      // Note: sessionId is used as player ID, userId kept for backward compatibility
      final roomJoinedHookData = {
        'room_id': jr,
        'session_id': sessionId, // This is now the player ID
        'user_id': ju, // Kept for backward compatibility
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': joinLevel,
        'joined_at': DateTime.now().toIso8601String(),
      };
      if (isTournament) roomJoinedHookData['is_tournament'] = true;
      if (tournamentData != null && tournamentData.isNotEmpty) roomJoinedHookData['tournament_data'] = tournamentData;
      _server.triggerHook('room_joined', data: roomJoinedHookData);
      
      // Max players reached: start match (random join has timer; create-room with autoStart has no timer)
      if (RandomJoinTimerManager.instance.isTimerActive(jr)) {
        // Random join rooms: cancel timer and start
        if (room.currentSize >= Config.RANDOM_JOIN_MAX_PLAYERS) {
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Max players reached, starting match immediately for random join room: $jr');
          }
          RandomJoinTimerManager.instance.cancelTimer(jr);
          _startMatchForRandomJoin(jr);
        }
        // Create-room with timer (legacy): cancel and start
        else if (room.currentSize >= room.maxSize) {
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Max players reached, starting match immediately for room: $jr');
          }
          RandomJoinTimerManager.instance.cancelTimer(jr);
          _startMatchForRoom(jr);
        }
      }
      // Create-room (invite or tournament) with autoStart: computer players never send join_room,
      // so we use effectiveMax = maxSize - compCount; when currentSize >= effectiveMax we start (same as lobby Create New flow).
      else if (room.autoStart == true && room.isRandomJoin != true) {
        final compCount = room.acceptedPlayers
            ?.where((e) => _isCompPlayer(e))
            .length ?? 0;
        final effectiveMax = room.maxSize - compCount;
        print('[join_room] autoStart check: roomId=$jr currentSize=${room.currentSize} compCount=$compCount effectiveMax=$effectiveMax (start=${room.currentSize >= effectiveMax})');
        if (room.currentSize >= effectiveMax) {
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Effective max reached ($room.currentSize >= $effectiveMax, compCount=$compCount), starting match for create-room: $jr');
          }
          _startMatchForRoom(jr);
        }
      }
      
      // Broadcast to other room members
      _server.broadcastToRoom(jr, {
        'event': 'player_joined',
        'room_id': jr,
        'user_id': ju,
        'player_count': room.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ User $ju joined room $jr');
      }
      } else {
        _server.sendToSession(sessionId, {
          'event': 'join_room_error',
          'message': 'Failed to join room: $jr',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }

    if (!matchRequiresCoinsForJoin) {
      if (LOGGING_SWITCH) {
        _logger.room('📊 Coins check: join_room skipped (game_state isCoinRequired=false) roomId=$jr');
      }
      completeJoinAfterOptionalCoinCheck();
      return;
    }
    if (LOGGING_SWITCH) {
      _logger.room('📊 Coins check: join_room -> verifying userId=$ju roomId=$jr level=$joinLevel');
    }
    _verifyCoinsForJoin(ju, joinLevel).then((ok) {
      if (!ok) {
        if (LOGGING_SWITCH) {
          _logger.room('📊 Coins check: join_room failed for $ju -> sending join_room_error');
        }
        _server.sendToSession(
          sessionId,
          _joinRoomCoinErrorPayload(
            message: 'Insufficient coins to join this game. Check your balance.',
            roomId: jr,
            gameLevel: joinLevel,
          ),
        );
        return;
      }
      completeJoinAfterOptionalCoinCheck();
    });
  }
  
  void _handleLeaveRoom(String sessionId) {
    if (LOGGING_SWITCH) {
      _logger.room('🎯 LEAVE_ROOM: _handleLeaveRoom called for session: $sessionId');
    }
    final roomId = _roomManager.getRoomForSession(sessionId);
    if (LOGGING_SWITCH) {
      _logger.room('🎯 LEAVE_ROOM: getRoomForSession returned roomId: $roomId for session: $sessionId');
    }
    if (roomId != null) {
      final room = _roomManager.getRoomInfo(roomId);
      final userId = _server.getUserIdForSession(sessionId) ?? sessionId; // Get userId from server
      _roomManager.leaveRoom(sessionId);
      
      // Cleanup timer if room becomes empty during delay period
      if (room != null && room.currentSize == 0) {
        RandomJoinTimerManager.instance.cleanup(roomId);
        if (LOGGING_SWITCH) {
          _logger.room('🧹 Cleaned up timer for empty room: $roomId');
        }
      }
      
      // Send leave_room_success (primary event matching Python)
      _server.sendToSession(sessionId, {
        'event': 'leave_room_success',
        'room_id': roomId,
        'session_id': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Trigger leave_room hook
      _server.triggerHook('leave_room', data: {
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'left_at': DateTime.now().toIso8601String(),
      });
      
      // Broadcast to remaining room members
      if (room != null) {
        _server.broadcastToRoom(roomId, {
          'event': 'player_left',
          'room_id': roomId,
          'player_count': room.currentSize,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ Session $sessionId left room $roomId');
      }
    } else {
      _server.sendToSession(sessionId, {
        'event': 'leave_room_error',
        'message': 'Not in any room',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
  
  void _handleListRooms(String sessionId) {
    final rooms = _roomManager.getAllRooms();
    _server.sendToSession(sessionId, {
      'event': 'rooms_list',
      'rooms': rooms.map((r) => r.toJson()).toList(),
      'total': rooms.length,
    });
  }
  
  /// Handle join random game event
  /// Searches for available public games or auto-creates and auto-starts a new one
  Future<void> _handleJoinRandomGame(String sessionId, Map<String, dynamic> data) async {
    // Get userId from server's session mapping (should be set after authentication)
    var userId = _server.getUserIdForSession(sessionId);
    
    // CRITICAL: Check if event payload includes a user_id that differs from session mapping
    // This handles account conversion scenarios (e.g., guest to Google) where the session
    // mapping hasn't been updated yet but the event has the correct new user_id
    final eventUserId = data['user_id'] as String?;
    if (eventUserId != null && eventUserId != userId) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ _handleJoinRandomGame: Event user_id ($eventUserId) differs from session mapping ($userId) - using event user_id (likely account conversion)');
      }
      userId = eventUserId;
      // Update session mapping to match event (session should be re-authenticated, but this is a safety measure)
      // Note: This is a temporary fix - ideally the session should be re-authenticated with new token
      _server.updateSessionUserId(sessionId, userId);
    }
    
    if (userId == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleJoinRandomGame: Session $sessionId is authenticated but userId is null');
      }
      _sendError(sessionId, 'User ID not available. Please reconnect.');
      return;
    }
    
    // Extract isClearAndCollect from event data (default to true for backward compatibility)
    // Handle both bool and string values (JSON serialization can convert bools to strings)
    final isClearAndCollectValue = data['isClearAndCollect'];
    if (LOGGING_SWITCH) {
      _logger.room('🔍 _handleJoinRandomGame: raw isClearAndCollect from event data: value=$isClearAndCollectValue (type: ${isClearAndCollectValue.runtimeType})');
    }
    final isClearAndCollect = isClearAndCollectValue is bool 
        ? isClearAndCollectValue 
        : (isClearAndCollectValue is String 
            ? (isClearAndCollectValue.toLowerCase() == 'true')
            : true); // Default to true for backward compatibility
    final requestedGameLevelRaw = data['game_level'] ?? data['gameLevel'];
    int requestedGameLevel = 1;
    if (requestedGameLevelRaw is int) {
      requestedGameLevel = requestedGameLevelRaw;
    } else if (requestedGameLevelRaw is String) {
      requestedGameLevel = int.tryParse(requestedGameLevelRaw) ?? 1;
    }
    if (requestedGameLevel < 1 || requestedGameLevel > 4) {
      requestedGameLevel = 1;
    }
    if (LOGGING_SWITCH) {
      _logger.room('✅ _handleJoinRandomGame: parsed isClearAndCollect: value=$isClearAndCollect (type: ${isClearAndCollect.runtimeType})');
      _logger.room('🔍 _handleJoinRandomGame: sessionId=$sessionId, userId=$userId, isClearAndCollect=$isClearAndCollect, requestedGameLevel=$requestedGameLevel');
    }
    
    // Log user account type for registration differences testing
    try {
      final profileResult = await _server.pythonClient.getUserProfile(userId);
      if (profileResult['success'] == true) {
        final accountType = profileResult['account_type'] as String? ?? 'unknown';
        final username = profileResult['username'] as String? ?? 'unknown';
        if (LOGGING_SWITCH) {
          _logger.room('👤 _handleJoinRandomGame: User account info - userId=$userId, username=$username, account_type=$accountType');
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ _handleJoinRandomGame: Could not fetch user profile for account type logging: $e');
      }
    }
    
    try {
      // Get available rooms for random join
      var availableRooms = _getAvailableRoomsForRandomJoin();
      if (LOGGING_SWITCH) {
        _logger.room('🔍 _handleJoinRandomGame: availableRooms (before rank filter): ${availableRooms.length}');
      }
      
      // Filter by rank compatibility
      final userRank = _server.getUserRankForSession(sessionId);
      availableRooms = _filterRoomsByRank(availableRooms, userRank);
      if (LOGGING_SWITCH) {
        _logger.room('🔍 _handleJoinRandomGame: availableRooms (after rank filter), userRank=$userRank: ${availableRooms.length}');
      }
      availableRooms = _filterRoomsByTableLevel(availableRooms, requestedGameLevel);
      if (LOGGING_SWITCH) {
        _logger.room('🔍 _handleJoinRandomGame: availableRooms (after table filter), requestedGameLevel=$requestedGameLevel: ${availableRooms.length}');
      }
      
      if (availableRooms.isNotEmpty) {
        // Pick a random room
        final random = Random();
        final selectedRoom = availableRooms[random.nextInt(availableRooms.length)];
        
        if (LOGGING_SWITCH) {
          _logger.room('🎲 Joining random room: ${selectedRoom.roomId}');
          _logger.room('🔍 About to call _handleJoinRoom with sessionId=$sessionId, userId=$userId');
        }
        
        // Use existing join room logic
        _handleJoinRoom(sessionId, {
          'room_id': selectedRoom.roomId,
          'user_id': userId,
        });
        
        // Note: When joining an existing room, the isClearAndCollect setting is already
        // determined by the room creator. We don't override it here.
        
        return;
      }
      
      // No available rooms - create new room and auto-start (verify coins first)
      if (LOGGING_SWITCH) {
        _logger.room('🎲 No available rooms found, creating new room for random join');
      }

      final uid = userId;
      final joinerUserLevel = _server.getUserLevelForSession(sessionId) ?? 1;
      if (!WinsLevelRankMatcher.userMayJoinGameTable(joinerUserLevel, requestedGameLevel)) {
        _server.sendToSession(sessionId, {
          'event': 'join_room_error',
          'message':
              'Your level ($joinerUserLevel) is too low for this table (requires level $requestedGameLevel or higher). Win more games to increase your level.',
          'timestamp': DateTime.now().toIso8601String(),
        });
        if (LOGGING_SWITCH) {
          _logger.room('❌ join_random_game(create new): table gate userLevel=$joinerUserLevel requestedGameLevel=$requestedGameLevel');
        }
        return;
      }
      if (LOGGING_SWITCH) {
        _logger.room('📊 Coins check: join_random_game (create new room) -> verifying userId=$uid level=$requestedGameLevel');
      }
      _verifyCoinsForJoin(uid, requestedGameLevel).then((ok) {
        if (!ok) {
          if (LOGGING_SWITCH) {
            _logger.room('📊 Coins check: join_random_game failed for $uid -> sending join_room_error');
          }
          _server.sendToSession(
            sessionId,
            _joinRoomCoinErrorPayload(
              message: 'Insufficient coins to join a game. Check your balance.',
              roomId: '',
              gameLevel: requestedGameLevel,
            )..['join_source'] = 'join_random_game',
          );
          return;
        }
        // Create room with default settings (using config values)
        final roomId = _roomManager.createRoom(
        sessionId,
        uid,
        maxSize: Config.RANDOM_JOIN_MAX_PLAYERS,
        minPlayers: Config.RANDOM_JOIN_MIN_PLAYERS,
        gameType: 'classic',
        permission: 'public',
        autoStart: true,
        isRandomJoin: true,
        gameLevel: requestedGameLevel,
      );
      
      // Store isClearAndCollect in game state store for later use when starting match
      final store = GameStateStore.instance;
      final roomState = store.ensure(roomId);
      if (LOGGING_SWITCH) {
        _logger.room('💾 Storing isClearAndCollect in roomState: value=$isClearAndCollect (type: ${isClearAndCollect.runtimeType})');
      }
      roomState['isClearAndCollect'] = isClearAndCollect;
      if (LOGGING_SWITCH) {
        _logger.room('✅ Stored isClearAndCollect in roomState[$roomId]: ${roomState['isClearAndCollect']} (type: ${roomState['isClearAndCollect'].runtimeType})');
      }
      
      // Get room info
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        _sendError(sessionId, 'Failed to create room for random join');
        return;
      }
      
      // Send create_room_success with flag indicating it's for random join
      _server.sendToSession(sessionId, {
        'event': 'create_room_success',
        'room_id': roomId,
        'owner_id': room.ownerId,
        'creator_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'auto_start': room.autoStart,
        'is_random_join': true, // Flag to indicate this was auto-created for random join
        'is_coin_required': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger room_created hook (creates game state)
      _server.triggerHook('room_created', data: {
        'room_id': roomId,
        'owner_id': room.ownerId,
        'session_id': sessionId, // Add session_id for player ID assignment
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'created_at': DateTime.now().toIso8601String(),
        'is_coin_required': true,
      });
      
      // Send room_joined event (auto-join creator)
      final level = room.gameLevel ?? 1;
      _server.sendToSession(sessionId, {
        'event': 'room_joined',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': level,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger room_joined hook (adds player to game state)
      // Note: sessionId is used as player ID, userId kept for backward compatibility
      _server.triggerHook('room_joined', data: {
        'room_id': roomId,
        'session_id': sessionId, // This is now the player ID
        'user_id': userId, // Kept for backward compatibility
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'game_level': level,
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      // Schedule delayed match start instead of immediate start
      final delaySeconds = Config.RANDOM_JOIN_DELAY_SECONDS;
      if (LOGGING_SWITCH) {
        _logger.room('⏱️  Scheduling delayed match start for random join room: $roomId (delay: ${delaySeconds}s, isClearAndCollect=$isClearAndCollect)');
      }
      
      RandomJoinTimerManager.instance.scheduleStartMatch(
        roomId,
        delaySeconds,
        (roomId) => _startMatchForRandomJoin(roomId),
      );
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ Random join room created with ${delaySeconds}s delay: $roomId');
      }
      });
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _handleJoinRandomGame: $e');
      }
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'Failed to join random game: $e',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
  
  /// Start match for a random join room (called after delay or when max players reached)
  /// Handles race conditions and ensures match only starts once
  void _startMatchForRandomJoin(String roomId) {
    try {
      // Check if match is already starting or started
      // This prevents race conditions when called from multiple paths (timer + early start)
      if (RandomJoinTimerManager.instance.isStarting(roomId)) {
        if (LOGGING_SWITCH) {
          _logger.game('⚠️  Match already starting for room: $roomId');
        }
        return;
      }

      // Set isStarting flag to prevent duplicate starts
      // This must be set before any async operations to prevent race conditions
      RandomJoinTimerManager.instance.setStarting(roomId);

      // Check if room still exists
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Room not found when starting match: $roomId');
        }
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      // Check if game already started (check phase)
      final stateStore = GameStateStore.instance;
      try {
        final gameState = stateStore.getGameState(roomId);
        final phase = gameState['phase'] as String?;
        if (phase != null && phase != 'waiting_for_players') {
          if (LOGGING_SWITCH) {
            _logger.game('⚠️  Game already started for room: $roomId (phase: $phase)');
          }
          RandomJoinTimerManager.instance.cleanup(roomId);
          return;
        }
      } catch (e) {
        // Game state might not exist yet, continue
      }

      // Get a session ID from the room (use first available session)
      final sessions = _roomManager.getSessionsInRoom(roomId);
      if (sessions.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ No sessions in room when starting match: $roomId');
        }
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      final sessionId = sessions.first;
      
      // Get isClearAndCollect from game state store (stored when room was created)
      final roomState = stateStore.getState(roomId);
      final isClearAndCollectValue = roomState['isClearAndCollect'];
      if (LOGGING_SWITCH) {
        _logger.game('🔍 Retrieved isClearAndCollect from roomState: value=$isClearAndCollectValue (type: ${isClearAndCollectValue.runtimeType})');
      }
      // Handle both bool and string values (JSON serialization can convert bools to strings)
      final isClearAndCollect = isClearAndCollectValue is bool 
          ? isClearAndCollectValue 
          : (isClearAndCollectValue is String 
              ? (isClearAndCollectValue.toLowerCase() == 'true')
              : true); // Default to true for backward compatibility
      if (LOGGING_SWITCH) {
        _logger.game('✅ Parsed isClearAndCollect: value=$isClearAndCollect (type: ${isClearAndCollect.runtimeType})');
        _logger.game('🎮 Starting match for random join room: $roomId (isClearAndCollect=$isClearAndCollect)');
        _logger.game('📤 Passing isClearAndCollect to start_match: value=$isClearAndCollect (type: ${isClearAndCollect.runtimeType})');
      }
      room.hasMatchRestarted = false;
      _gameCoordinator.handle(sessionId, 'start_match', {
        'game_id': roomId,
        'min_players': room.minPlayers,
        'max_players': room.maxSize,
        'isClearAndCollect': isClearAndCollect,
      });
      if (LOGGING_SWITCH) {
        _logger.game('✅ Called _gameCoordinator.handle with isClearAndCollect=$isClearAndCollect');
      }

      // Cleanup timer state
      RandomJoinTimerManager.instance.cleanup(roomId);
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ Match started for random join room: $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error starting match for random join room $roomId: $e');
      }
      RandomJoinTimerManager.instance.cleanup(roomId);
    }
  }

  /// Start match for a regular room (called after timer expires or max players reached)
  /// Handles race conditions and ensures match only starts once
  void _startMatchForRoom(String roomId) {
    try {
      // Check if match is already starting or started
      // This prevents race conditions when called from multiple paths (timer + early start)
      if (RandomJoinTimerManager.instance.isStarting(roomId)) {
        if (LOGGING_SWITCH) {
          _logger.game('⚠️  Match already starting for room: $roomId');
        }
        return;
      }

      // Set isStarting flag to prevent duplicate starts
      // This must be set before any async operations to prevent race conditions
      RandomJoinTimerManager.instance.setStarting(roomId);

      // Check if room still exists
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Room not found when starting match: $roomId');
        }
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      // Check if game already started (check phase)
      final store = GameStateStore.instance;
      try {
        final gameState = store.getGameState(roomId);
        final phase = gameState['phase'] as String?;
        if (phase != null && phase != 'waiting_for_players') {
          if (LOGGING_SWITCH) {
            _logger.game('⚠️  Game already started for room: $roomId (phase: $phase)');
          }
          RandomJoinTimerManager.instance.cleanup(roomId);
          return;
        }
      } catch (e) {
        // Game state might not exist yet, continue
      }

      // Get a session ID from the room (use first available session)
      final sessions = _roomManager.getSessionsInRoom(roomId);
      if (sessions.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ No sessions in room when starting match: $roomId');
        }
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      final sessionId = sessions.first;

      // Prefer store root (random join stores user choice here; game_type may stay `classic`).
      final roomState = store.getState(roomId);
      final defaultFromGameType = room.gameType == 'clear_and_collect';
      final isClearAndCollect = roomState.containsKey('isClearAndCollect')
          ? _coerceBool(roomState['isClearAndCollect'], ifNull: defaultFromGameType)
          : defaultFromGameType;
      if (LOGGING_SWITCH) {
        _logger.game(
          '🎮 Starting match for room: $roomId (gameType=${room.gameType}, isClearAndCollect=$isClearAndCollect)',
        );
      }
      final Map<String, dynamic> startMatchData = {
        'game_id': roomId,
        'min_players': room.minPlayers,
        'max_players': room.maxSize,
        'auto_start': room.autoStart, // Pass autoStart flag so coordinator can fill to maxPlayers
        'is_random_join': room.isRandomJoin, // Must match room_created / join_random_game semantics for CPU fill
        'isClearAndCollect': isClearAndCollect,
      };
      if (room.acceptedPlayers != null && room.acceptedPlayers!.isNotEmpty) {
        startMatchData['accepted_players'] = room.acceptedPlayers!;
      }
      final gsForStart = store.getGameState(roomId);
      final gsTd = gsForStart['tournament_data'] as Map<String, dynamic>?;
      Map<String, dynamic>? tdForStart;
      if (room.tournamentData != null && room.tournamentData!.isNotEmpty) {
        tdForStart = Map<String, dynamic>.from(room.tournamentData!);
      } else if (gsTd != null && gsTd.isNotEmpty) {
        tdForStart = Map<String, dynamic>.from(gsTd);
      }
      final tournamentForStart = room.isTournament ||
          gsForStart['is_tournament'] == true ||
          (tdForStart != null && tdForStart.isNotEmpty);
      if (tournamentForStart) startMatchData['is_tournament'] = true;
      if (tdForStart != null && tdForStart.isNotEmpty) {
        startMatchData['tournament_data'] = tdForStart;
      }
      room.hasMatchRestarted = false;
      _gameCoordinator.handle(sessionId, 'start_match', startMatchData);

      // Cleanup timer state (this also clears isStarting flag)
      RandomJoinTimerManager.instance.cleanup(roomId);
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ Match started for room: $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error starting match for room $roomId: $e');
      }
      RandomJoinTimerManager.instance.cleanup(roomId);
    }
  }

  /// Get available rooms for random join
  /// Filters rooms by: public permission, has capacity, phase is waiting_for_players, rank compatibility
  List<Room> _getAvailableRoomsForRandomJoin() {
    final allRooms = _roomManager.getAllRooms();
    final store = GameStateStore.instance;
    final availableRooms = <Room>[];
    
    // Get current user's rank (if available) - we need sessionId for this
    // For now, we'll filter in the calling method where we have sessionId
    // This method will filter by basic criteria, rank filtering happens in caller
    
    for (final room in allRooms) {
      // Filter: public permission
      if (room.permission != 'public') continue;
      
      // Filter: has capacity
      if (room.currentSize >= room.maxSize) continue;
      
      // Filter: phase is waiting_for_players
      try {
        final gameState = store.getGameState(room.roomId);
        final phase = gameState['phase'] as String?;
        if (phase != 'waiting_for_players') continue;
      } catch (e) {
        // If game state doesn't exist yet, skip this room
        continue;
      }
      
      availableRooms.add(room);
    }
    
    return availableRooms;
  }
  
  /// Filter rooms by rank compatibility
  List<Room> _filterRoomsByRank(List<Room> rooms, String? userRank) {
    if (userRank == null) {
      // If user has no rank, allow all rooms (fallback behavior)
      return rooms;
    }
    
    final compatibleRooms = <Room>[];
    final normalizedUserRank = userRank.toLowerCase();
    
    for (final room in rooms) {
      // If room has no difficulty set, allow it (first human will set it)
      if (room.difficulty == null) {
        compatibleRooms.add(room);
        continue;
      }
      
      // Check if room difficulty is compatible with user rank
      final roomDifficulty = room.difficulty!.toLowerCase();
      if (RankMatcher.areRanksCompatible(roomDifficulty, normalizedUserRank)) {
        compatibleRooms.add(room);
      }
    }
    
    return compatibleRooms;
  }

  /// Filter rooms by requested table tier (room.gameLevel).
  /// Rooms without explicit gameLevel are treated as level 1 for compatibility.
  List<Room> _filterRoomsByTableLevel(List<Room> rooms, int requestedGameLevel) {
    return rooms.where((room) {
      final roomLevel = room.gameLevel ?? 1;
      return roomLevel == requestedGameLevel;
    }).toList();
  }
  
  // ========= GAME EVENT HANDLER (UNIFIED) =========

  void _handleGameEvent(
    String sessionId,
    String event,
    Map<String, dynamic> data,
  ) {
    if (LOGGING_SWITCH) {
      _logger.game('🎮 Game event: $event');
      _logger.game('📦 Data: $data');
      if (event == 'jack_swap') {
        _logger.game('🃏 _handleGameEvent: jack_swap event received - routing to GameEventCoordinator');
      }
    }
    if (event == 'start_match') {
      final gid = data['game_id'] as String? ?? data['room_id'] as String?;
      if (gid != null && gid.isNotEmpty) {
        _resetMatchRestartedFlag(gid);
      }
    }
    _gameCoordinator.handle(sessionId, event, data);
  }

  /// Handle authenticate event
  void _handleAuthenticate(String sessionId, Map<String, dynamic> data) {
    final token = data['token'] as String?;
    
    if (token == null) {
      _sendError(sessionId, 'Missing token in authenticate event');
      return;
    }
    
    if (LOGGING_SWITCH) {
      _logger.auth('🔐 Authenticate event received for session: $sessionId');
    }
    
    // Trigger authentication validation
    _server.validateAndAuthenticate(sessionId, token);
  }
  
  // ========= UTILITY METHODS =========
  
  void _sendError(String sessionId, String message) {
    _server.sendToSession(sessionId, {
      'event': 'error',
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
