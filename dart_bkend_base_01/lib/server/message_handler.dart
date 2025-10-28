import 'room_manager.dart';
import 'websocket_server.dart';
import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true;

class MessageHandler {
  final RoomManager _roomManager;
  final WebSocketServer _server;
  final ServerLogger _logger = ServerLogger();

  MessageHandler(this._roomManager, this._server);
  
  /// Unified event handler - ALL events come through here
  void handleMessage(String sessionId, Map<String, dynamic> data) {
    final event = data['event'] as String?;

    if (event == null) {
      _sendError(sessionId, 'Missing event field');
      return;
    }

    _logger.websocket('📨 Event: $event from session: $sessionId', isOn: LOGGING_SWITCH);

    // Unified switch for ALL events
    switch (event) {
      // Connection events
      case 'ping':
        _handlePing(sessionId);
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

      // Game events (all handled uniformly)
      case 'start_match':
      case 'draw_card':
      case 'play_card':
      case 'discard_card':
      case 'take_from_discard':
      case 'call_recall':
      case 'same_rank_play':
      case 'jack_swap':
      case 'queen_peek':
      case 'completed_initial_peek':
        _handleGameEvent(sessionId, event, data);
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
  
  // ========= ROOM MANAGEMENT HANDLERS =========
  
  void _handleCreateRoom(String sessionId, Map<String, dynamic> data) {
    final userId = data['user_id'] as String? ?? sessionId;
    final roomId = _roomManager.createRoom(sessionId, userId);
    
    _server.sendToSession(sessionId, {
      'event': 'room_created',
      'room_id': roomId,
      'creator_id': userId,
    });
  }
  
  void _handleJoinRoom(String sessionId, Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    final userId = data['user_id'] as String? ?? sessionId;
    
    if (roomId == null) {
      _sendError(sessionId, 'Missing room_id');
      return;
    }
    
    if (_roomManager.joinRoom(roomId, sessionId, userId)) {
      _server.sendToSession(sessionId, {
        'event': 'room_joined',
        'room_id': roomId,
        'user_id': userId,
      });
      
      _server.broadcastToRoom(roomId, {
        'event': 'player_joined',
        'room_id': roomId,
        'user_id': userId,
        'player_count': _roomManager.getSessionsInRoom(roomId).length,
      });
    } else {
      _sendError(sessionId, 'Failed to join room: $roomId');
    }
  }
  
  void _handleLeaveRoom(String sessionId) {
    final roomId = _roomManager.getRoomForSession(sessionId);
    if (roomId != null) {
      _roomManager.leaveRoom(sessionId);
      
      _server.sendToSession(sessionId, {
        'event': 'room_left',
        'room_id': roomId,
      });
      
      _server.broadcastToRoom(roomId, {
        'event': 'player_left',
        'room_id': roomId,
        'player_count': _roomManager.getSessionsInRoom(roomId).length,
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
  
  // ========= GAME EVENT HANDLER (UNIFIED) =========

  void _handleGameEvent(
    String sessionId,
    String event,
    Map<String, dynamic> data,
  ) {
    _logger.game('🎮 Game event: $event', isOn: LOGGING_SWITCH);
    _logger.game('📦 Data: $data', isOn: LOGGING_SWITCH);

    // For now, just acknowledge receipt
    // Game logic execution will be added in future phase
    _server.sendToSession(sessionId, {
      'event': '${event}_acknowledged',
      'original_event': event,
      'session_id': sessionId,
      'message': 'Event received and acknowledged',
      'timestamp': DateTime.now().toIso8601String(),
      'data': data, // Echo back the data
    });

    _logger.game('✅ Game event acknowledged: $event', isOn: LOGGING_SWITCH);
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
