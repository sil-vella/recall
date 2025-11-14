import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'room_manager.dart';
import 'message_handler.dart';
import '../services/python_api_client.dart';
import '../utils/server_logger.dart';
import '../managers/hooks_manager.dart';
import '../modules/recall_game/recall_game_main.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

class WebSocketServer {
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, String> _sessionToUser = {};
  final Map<String, bool> _authenticatedSessions = {};
  final RoomManager _roomManager = RoomManager();
  late MessageHandler _messageHandler;
  late PythonApiClient _pythonClient;
  final Logger _logger = Logger();
  final HooksManager _hooksManager = HooksManager();
  // ignore: unused_field
  late RecallGameModule _recallGameModule;

  WebSocketServer() {
    _logger.initialize();
    _messageHandler = MessageHandler(_roomManager, this);
    _pythonClient = PythonApiClient(baseUrl: 'http://localhost:5001'); // Updated to port 5001
    
    // Wire up room closure hook
    _roomManager.onRoomClosed = (roomId, reason) {
      _logger.info('🎣 Room closure hook triggered: $roomId (reason: $reason)', isOn: LOGGING_SWITCH);
      
      // Trigger room_closed hook
      triggerHook('room_closed', data: {
        'room_id': roomId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      });
    };
    
    // Initialize hooks for room events
    _initializeHooks();
    
    // Initialize Recall Game module (registers hooks for game lifecycle)
    _recallGameModule = RecallGameModule(this, _roomManager, _hooksManager);
    
    _logger.info('📡 WebSocket server initialized', isOn: LOGGING_SWITCH);
  }
  
  /// Initialize hooks for room events
  void _initializeHooks() {
    // Register hook event types
    _hooksManager.registerHook('room_joined');
    _hooksManager.registerHook('room_created');
    _hooksManager.registerHook('leave_room');
    _hooksManager.registerHook('room_closed');
    
    _logger.info('🎣 Hooks initialized for room events', isOn: LOGGING_SWITCH);
  }

  /// Get user ID for a session
  String? getUserIdForSession(String sessionId) {
    return _sessionToUser[sessionId];
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
    _authenticatedSessions[sessionId] = false;

    _logger.connection('✅ Client connected: $sessionId (Total: ${_connections.length})', isOn: LOGGING_SWITCH);

    _logger.connection('📤 Sending connected event to session: $sessionId', isOn: LOGGING_SWITCH);
    sendToSession(sessionId, {
      'event': 'connected',
      'session_id': sessionId,
      'message': 'Welcome to Recall Game Server',
      'authenticated': false,
    });
    _logger.connection('✅ Connected event sent to session: $sessionId', isOn: LOGGING_SWITCH);

    webSocket.stream.listen(
      (message) => _onMessage(sessionId, message),
      onDone: () => _onDisconnect(sessionId),
      onError: (error) => _onError(sessionId, error),
    );
  }
  
  void _onMessage(String sessionId, dynamic message) {
    try {
      final data = jsonDecode(message as String);

      // Check for authentication token
      if (data.containsKey('token') && !_authenticatedSessions[sessionId]!) {
        validateAndAuthenticate(sessionId, data['token'] as String);
      }

      // Route to unified message handler
      _messageHandler.handleMessage(sessionId, data);
    } catch (e) {
      _logger.error('❌ Message parse error: $e', isOn: LOGGING_SWITCH);
      sendToSession(sessionId, {
        'event': 'error',
        'message': 'Invalid message format',
      });
    }
  }
  
  Future<void> validateAndAuthenticate(String sessionId, String token) async {
    _logger.auth('🔐 Validating token for session: $sessionId', isOn: LOGGING_SWITCH);
    
    try {
      final result = await _pythonClient.validateToken(token);

      if (result['valid'] == true) {
        _authenticatedSessions[sessionId] = true;
        _sessionToUser[sessionId] = result['user_id'] ?? sessionId;

        _logger.auth('✅ Session authenticated: $sessionId', isOn: LOGGING_SWITCH);
        sendToSession(sessionId, {
          'event': 'authenticated',
          'session_id': sessionId,
          'user_id': result['user_id'],
          'message': 'Authentication successful',
        });
      } else {
        _logger.auth('❌ Authentication failed: ${result['error']}', isOn: LOGGING_SWITCH);
        sendToSession(sessionId, {
          'event': 'authentication_failed',
          'message': result['error'] ?? 'Invalid token',
        });
      }
    } catch (e) {
      _logger.auth('❌ Auth error: $e', isOn: LOGGING_SWITCH);
      sendToSession(sessionId, {
          'event': 'authentication_error',
          'message': 'Authentication service unavailable',
      });
    }
  }
  
  void _onDisconnect(String sessionId) {
    _logger.connection('👋 Client disconnected: $sessionId', isOn: LOGGING_SWITCH);
    
    // Get user's current room before cleanup
    final roomId = _roomManager.getRoomForSession(sessionId);
    final room = roomId != null ? _roomManager.getRoomInfo(roomId) : null;
    
    // Clean up connections and authentication
    _connections.remove(sessionId);
    _sessionToUser.remove(sessionId);
    _authenticatedSessions.remove(sessionId);
    
    // Handle room cleanup
    _roomManager.handleDisconnect(sessionId);
    
    // Broadcast to remaining room members if user was in a room
    if (roomId != null && room != null) {
      _logger.room('📢 Broadcasting player_left to room $roomId', isOn: LOGGING_SWITCH);
      broadcastToRoom(roomId, {
        'event': 'player_left',
        'room_id': roomId,
        'player_count': room.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    
    _logger.connection('📊 Active connections: ${_connections.length}', isOn: LOGGING_SWITCH);
  }

  void _onError(String sessionId, dynamic error) {
    _logger.error('❌ Error on connection $sessionId: $error', isOn: LOGGING_SWITCH);
  }
  
  void sendToSession(String sessionId, Map<String, dynamic> message) {
    final connection = _connections[sessionId];
    if (connection != null) {
      try {
        connection.sink.add(jsonEncode(message));
      } catch (e) {
        _logger.error('❌ Error sending to $sessionId: $e', isOn: LOGGING_SWITCH);
      }
    }
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    _logger.room('📢 Broadcasting to room $roomId (${sessions.length} clients)', isOn: LOGGING_SWITCH);
    for (final sessionId in sessions) {
      sendToSession(sessionId, message);
    }
  }
  
  int get connectionCount => _connections.length;
}
