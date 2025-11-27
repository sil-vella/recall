import 'room_manager.dart';
import 'websocket_server.dart';
import '../utils/server_logger.dart';
import '../modules/recall_game/backend_core/coordinator/game_event_coordinator.dart';
import '../modules/recall_game/utils/platform/shared_imports.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

class MessageHandler {
  final RoomManager _roomManager;
  final WebSocketServer _server;
  final Logger _logger = Logger();
  late final GameEventCoordinator _gameCoordinator;

  MessageHandler(this._roomManager, this._server) {
    _gameCoordinator = GameEventCoordinator(_roomManager, _server);
  }
  
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
      case 'collect_from_discard':
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
    
    // Extract room settings from data (matching Python backend)
    final maxPlayers = data['max_players'] as int? ?? data['maxPlayers'] as int?;
    final minPlayers = data['min_players'] as int? ?? data['minPlayers'] as int?;
    final gameType = data['game_type'] as String? ?? data['gameType'] as String?;
    final permission = data['permission'] as String?;
    final password = data['password'] as String?;
    final turnTimeLimit = data['turn_time_limit'] as int? ?? data['turnTimeLimit'] as int?;
    final autoStart = data['auto_start'] as bool? ?? data['autoStart'] as bool?;
    
    try {
      // Create room with settings
      final roomId = _roomManager.createRoom(
        sessionId,
        userId,
        maxSize: maxPlayers,
        minPlayers: minPlayers,
        gameType: gameType,
        permission: permission,
        password: password,
        turnTimeLimit: turnTimeLimit,
        autoStart: autoStart,
      );
      
      // Get room info for response
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        _sendError(sessionId, 'Failed to create room');
        return;
      }
      
      // Send create_room_success (primary event matching Python)
      _server.sendToSession(sessionId, {
        'event': 'create_room_success',
        'room_id': roomId,
        'owner_id': room.ownerId,
        'creator_id': room.ownerId, // Keep for compatibility
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'turn_time_limit': room.turnTimeLimit,
        'auto_start': room.autoStart,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Trigger room_created hook
      _server.triggerHook('room_created', data: {
        'room_id': roomId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'min_players': room.minPlayers,
        'game_type': room.gameType,
        'permission': room.permission,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      // Also send room_joined (auto-join creator like Python does)
      _server.sendToSession(sessionId, {
        'event': 'room_joined',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Trigger room_joined hook (for auto-join creator)
      _server.triggerHook('room_joined', data: {
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      _logger.room('✅ Room created and creator auto-joined: $roomId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('❌ Failed to create room: $e', isOn: LOGGING_SWITCH);
      _server.sendToSession(sessionId, {
        'event': 'create_room_error',
        'message': 'Failed to create room: $e',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
  
  void _handleJoinRoom(String sessionId, Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    final userId = data['user_id'] as String? ?? sessionId;
    final password = data['password'] as String?;
    
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
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _logger.room('⚠️  User $userId already in room $roomId', isOn: LOGGING_SWITCH);
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
    
    // Validate password for private rooms
    if (!_roomManager.validateRoomPassword(roomId, password)) {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': room.permission == 'private' 
            ? 'Invalid password for private room' 
            : 'Password required for private room',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }
    
    // Attempt to join room
    if (_roomManager.joinRoom(roomId, sessionId, userId, password: password)) {
      // Send join_room_success (primary event matching Python)
      _server.sendToSession(sessionId, {
        'event': 'join_room_success',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Also send room_joined for backward compatibility
      _server.sendToSession(sessionId, {
        'event': 'room_joined',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Trigger room_joined hook
      _server.triggerHook('room_joined', data: {
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      // Broadcast to other room members
      _server.broadcastToRoom(roomId, {
        'event': 'player_joined',
        'room_id': roomId,
        'user_id': userId,
        'player_count': room.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _logger.room('✅ User $userId joined room $roomId', isOn: LOGGING_SWITCH);
    } else {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'Failed to join room: $roomId',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
  
  void _handleLeaveRoom(String sessionId) {
    final roomId = _roomManager.getRoomForSession(sessionId);
    if (roomId != null) {
      final room = _roomManager.getRoomInfo(roomId);
      final userId = _server.getUserIdForSession(sessionId) ?? sessionId; // Get userId from server
      _roomManager.leaveRoom(sessionId);
      
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
      
      _logger.room('✅ Session $sessionId left room $roomId', isOn: LOGGING_SWITCH);
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
  
  // ========= GAME EVENT HANDLER (UNIFIED) =========

  void _handleGameEvent(
    String sessionId,
    String event,
    Map<String, dynamic> data,
  ) {
    _logger.game('🎮 Game event: $event', isOn: LOGGING_SWITCH);
    _logger.game('📦 Data: $data', isOn: LOGGING_SWITCH);
    _gameCoordinator.handle(sessionId, event, data);
  }

  /// Handle authenticate event
  void _handleAuthenticate(String sessionId, Map<String, dynamic> data) {
    final token = data['token'] as String?;
    
    if (token == null) {
      _sendError(sessionId, 'Missing token in authenticate event');
      return;
    }
    
    _logger.auth('🔐 Authenticate event received for session: $sessionId', isOn: LOGGING_SWITCH);
    
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
