import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'room_manager.dart';
import 'message_handler.dart';
import 'random_join_timer_manager.dart';
import '../services/python_api_client.dart';
import '../utils/server_logger.dart';
import '../managers/hooks_manager.dart';
import '../modules/dutch_game/dutch_main.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false; // Enabled for testing game finding/initialization and registration differences

class WebSocketServer {
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, String> _connectionHashes = {}; // Track connection object identity
  final Map<String, String> _sessionToUser = {};
  final Map<String, bool> _authenticatedSessions = {};
  final Map<String, String?> _sessionToRank = {}; // Track user rank per session
  final Map<String, int?> _sessionToLevel = {}; // Track user level per session
  final RoomManager _roomManager = RoomManager();
  late MessageHandler _messageHandler;
  late PythonApiClient _pythonClient;
  final Logger _logger = Logger();
  final HooksManager _hooksManager = HooksManager();
  // ignore: unused_field
  late DutchGameModule _dutchGameModule;

  WebSocketServer({required String pythonApiUrl}) {
    _logger.initialize();
    _messageHandler = MessageHandler(_roomManager, this);
    // Python API URL is passed from app.dart (VPS) or app.debug.dart (local)
    _pythonClient = PythonApiClient(baseUrl: pythonApiUrl);
    if (LOGGING_SWITCH) {
      _logger.info('🔗 Python API client configured: $pythonApiUrl');
    }
    
    // Wire up room closure hook
    _roomManager.onRoomClosed = (roomId, reason) {
      if (LOGGING_SWITCH) {
        _logger.info('🎣 Room closure hook triggered: $roomId (reason: $reason)');
      }
      
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
    
    if (LOGGING_SWITCH) {
      _logger.info('📡 WebSocket server initialized');
    }
  }
  
  /// Initialize hooks for room events
  void _initializeHooks() {
    // Register hook event types
    _hooksManager.registerHook('room_joined');
    _hooksManager.registerHook('room_created');
    _hooksManager.registerHook('leave_room');
    _hooksManager.registerHook('room_closed');
    
    if (LOGGING_SWITCH) {
      _logger.info('🎣 Hooks initialized for room events');
    }
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
    final oldUserId = _sessionToUser[sessionId];
    _sessionToUser[sessionId] = userId;
    if (oldUserId != null && oldUserId != userId) {
      if (LOGGING_SWITCH) {
        _logger.auth('🔄 Updated session $sessionId user mapping: $oldUserId -> $userId');
      }
    }
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

  void handleConnection(WebSocketChannel webSocket) {
    final sessionId = const Uuid().v4();
    _connections[sessionId] = webSocket;
    _connectionHashes[sessionId] = webSocket.hashCode.toString();
    _authenticatedSessions[sessionId] = false;

    if (LOGGING_SWITCH) {
      _logger.connection('✅ Client connected: $sessionId (Total: ${_connections.length})');
      _logger.connection('🔍 Connection hash: ${webSocket.hashCode}');
      _logger.connection('📤 Sending connected event to session: $sessionId');
    }
    sendToSession(sessionId, {
      'event': 'connected',
      'session_id': sessionId,
      'message': 'Welcome to Dutch Game Server',
      'authenticated': false,
    });
    if (LOGGING_SWITCH) {
      _logger.connection('✅ Connected event sent to session: $sessionId');
    }

    webSocket.stream.listen(
      (message) => _onMessage(sessionId, message),
      onDone: () => _onDisconnect(sessionId),
      onError: (error) => _onError(sessionId, error),
    );
  }
  
  void _onMessage(String sessionId, dynamic message) {
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

      // JWT hardening: only validate token when client explicitly sends "authenticate" event.
      // Re-authentication (e.g. account conversion) still works by sending event: "authenticate" with token.
      final event = data['event'] as String?;
      if (event == 'authenticate' && data.containsKey('token')) {
        validateAndAuthenticate(sessionId, data['token'] as String);
      }

      // Route to unified message handler
      _messageHandler.handleMessage(sessionId, data);
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Message parse error: $e');
      }
      sendToSession(sessionId, {
        'event': 'error',
        'message': 'Invalid message format',
      });
    }
  }
  
  Future<void> validateAndAuthenticate(String sessionId, String token) async {
    if (LOGGING_SWITCH) {
      _logger.auth('🔐 Validating token for session: $sessionId');
    }
    
    try {
      final result = await _pythonClient.validateToken(token);

      if (result['valid'] == true) {
        final newUserId = result['user_id'] ?? sessionId;
        final oldUserId = _sessionToUser[sessionId];
        
        // Check if user ID changed (e.g., after account conversion)
        if (oldUserId != null && oldUserId != newUserId) {
          if (LOGGING_SWITCH) {
            _logger.auth('🔄 User ID changed for session $sessionId: $oldUserId -> $newUserId (likely account conversion)');
          }
        }
        
        _authenticatedSessions[sessionId] = true;
        _sessionToUser[sessionId] = newUserId;
        
        // Store rank and level from validation response
        final rank = result['rank'] as String?;
        final level = result['level'] as int?;
        final accountType = result['account_type'] as String?; // Get account type from token validation
        if (rank != null || level != null) {
          setUserRankAndLevel(sessionId, rank, level);
          if (LOGGING_SWITCH) {
            _logger.auth('✅ Stored rank=$rank, level=$level for session: $sessionId');
          }
        }

        if (LOGGING_SWITCH) {
          _logger.auth('✅ Session authenticated: $sessionId, userId=$newUserId, account_type=${accountType ?? 'unknown'}');
        }
        sendToSession(sessionId, {
          'event': 'authenticated',
          'session_id': sessionId,
          'user_id': result['user_id'],
          'message': 'Authentication successful',
        });
      } else {
        if (LOGGING_SWITCH) {
          _logger.auth('❌ Authentication failed: ${result['error']}');
        }
        sendToSession(sessionId, {
          'event': 'authentication_failed',
          'message': result['error'] ?? 'Invalid token',
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.auth('❌ Auth error: $e');
      }
      sendToSession(sessionId, {
          'event': 'authentication_error',
          'message': 'Authentication service unavailable',
      });
    }
  }
  
  void _onDisconnect(String sessionId) {
    if (LOGGING_SWITCH) {
      _logger.connection('👋 Client disconnected: $sessionId');
    }
    
    // Get user's current room before cleanup
    final roomId = _roomManager.getRoomForSession(sessionId);
    final room = roomId != null ? _roomManager.getRoomInfo(roomId) : null;
    
    // Clean up connections and authentication
    _connections.remove(sessionId);
    _connectionHashes.remove(sessionId);
    _sessionToUser.remove(sessionId);
    _authenticatedSessions.remove(sessionId);
    _sessionToRank.remove(sessionId);
    _sessionToLevel.remove(sessionId);
    
    // Handle room cleanup
    _roomManager.handleDisconnect(sessionId);
    
    // Broadcast to remaining room members if user was in a room
    if (roomId != null && room != null) {
      if (LOGGING_SWITCH) {
        _logger.room('📢 Broadcasting player_left to room $roomId');
      }
      broadcastToRoom(roomId, {
        'event': 'player_left',
        'room_id': roomId,
        'player_count': room.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    
    if (LOGGING_SWITCH) {
      _logger.connection('📊 Active connections: ${_connections.length}');
    }
  }

  void _onError(String sessionId, dynamic error) {
    if (LOGGING_SWITCH) {
      _logger.error('❌ Error on connection $sessionId: $error');
    }
  }
  
  void sendToSession(String sessionId, Map<String, dynamic> message) {
    final connection = _connections[sessionId];
    final eventName = message['event'] as String? ?? 'unknown';
    
    // CRITICAL: Verify we're using sessionId, not userId
    final userIdInMessage = message['user_id'] as String?;
    if (LOGGING_SWITCH) {
      _logger.info('🔍 sendToSession called: sessionId=$sessionId, event=$eventName, userIdInMessage=$userIdInMessage');
      _logger.info('🔍 VERIFY: sessionId != userIdInMessage? ${sessionId != userIdInMessage}');
    }
    
    if (connection != null) {
      try {
        final messageJson = jsonEncode(message);
        if (LOGGING_SWITCH) {
          _logger.info('📤 Sending event "$eventName" to session: $sessionId');
          _logger.debug('📤 Message payload: $messageJson');
          _logger.debug('📤 Total connections: ${_connections.length}');
          _logger.debug('📤 Connection type: ${connection.runtimeType}');
          _logger.debug('📤 All session IDs in _connections: ${_connections.keys.toList()}');
          _logger.debug('📤 Connection hash: ${connection.hashCode}, Stored hash: ${_connectionHashes[sessionId]}');
          _logger.debug('📤 Connection identity match: ${connection.hashCode.toString() == _connectionHashes[sessionId]}');
        }
        
        // Check if sink is closed by attempting to add
        try {
          // Check sink.done Future to see if it's already completed (closed)
          connection.sink.done.then((_) {
            if (LOGGING_SWITCH) {
              _logger.warning('⚠️  Sink is done (closed) for session: $sessionId - message may not be delivered');
            }
          }).catchError((e) {
            // Sink is not done, which is good
          });
          
          // Attempt to send the message
          connection.sink.add(messageJson);
          if (LOGGING_SWITCH) {
            _logger.info('✅ Event "$eventName" sent successfully to session: $sessionId');
            _logger.debug('✅ Message length: ${messageJson.length} bytes');
          }
        } catch (sinkError) {
          if (LOGGING_SWITCH) {
            _logger.error('❌ Sink error when sending to $sessionId: $sinkError');
            _logger.error('❌ Sink error type: ${sinkError.runtimeType}');
            _logger.error('❌ Sink error stack: ${StackTrace.current}');
          }
          // Check if sink is done
          connection.sink.done.then((_) {
            if (LOGGING_SWITCH) {
              _logger.warning('⚠️  Sink is done (closed) for session: $sessionId');
            }
            _connections.remove(sessionId);
            _connectionHashes.remove(sessionId);
          }).catchError((e) {
            if (LOGGING_SWITCH) {
              _logger.error('❌ Error checking sink.done: $e');
            }
          });
          rethrow;
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Error sending to $sessionId: $e');
          _logger.error('❌ Error stack trace: ${StackTrace.current}');
        }
        // Clean up the connection if there's an error
        _connections.remove(sessionId);
        _connectionHashes.remove(sessionId);
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  Cannot send event "$eventName" to session $sessionId: connection not found');
        _logger.warning('⚠️  Available sessions: ${_connections.keys.toList()}');
        _logger.warning('⚠️  Looking for session: $sessionId');
        _logger.warning('⚠️  Session exists in map: ${_connections.containsKey(sessionId)}');
      }
    }
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    if (LOGGING_SWITCH) {
      _logger.room('📢 Broadcasting to room $roomId (${sessions.length} clients)');
    }
    for (final sessionId in sessions) {
      sendToSession(sessionId, message);
    }
  }

  /// Broadcast to all sessions in a room except the specified session
  /// 
  /// [roomId] The room ID to broadcast to
  /// [message] The message to send
  /// [excludeSessionId] The session ID to exclude from the broadcast
  void broadcastToRoomExcept(String roomId, Map<String, dynamic> message, String excludeSessionId) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    final filteredSessions = sessions.where((sessionId) => sessionId != excludeSessionId).toList();
    if (LOGGING_SWITCH) {
      _logger.room('📢 Broadcasting to room $roomId (${filteredSessions.length} clients, excluding $excludeSessionId)');
    }
    for (final sessionId in filteredSessions) {
      sendToSession(sessionId, message);
    }
  }
  
  int get connectionCount => _connections.length;
}
