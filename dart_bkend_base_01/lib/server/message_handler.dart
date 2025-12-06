import 'dart:math';
import 'room_manager.dart';
import 'websocket_server.dart';
import '../utils/server_logger.dart';
import '../utils/config.dart';
import 'random_join_timer_manager.dart';
import '../modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart';
import '../modules/cleco_game/backend_core/services/game_state_store.dart';
import '../modules/cleco_game/utils/platform/shared_imports.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true; // Enabled for jack swap tracing

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
      case 'join_random_game':
        _handleJoinRandomGame(sessionId, data);
        break;

      // Game events (all handled uniformly)
      case 'start_match':
      case 'draw_card':
      case 'play_card':
      case 'discard_card':
      case 'take_from_discard':
      case 'call_cleco':
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
    final maxPlayers = 4; // Hardcoded to 4, no options
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
        'session_id': sessionId, // Add session_id for player ID assignment
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
      
      // Schedule auto-start timer if autoStart is enabled
      if (room.autoStart == true) {
        final delaySeconds = 5;
        _logger.room('⏱️  Scheduling auto-start timer for room: $roomId (delay: ${delaySeconds}s, maxSize: ${room.maxSize})', isOn: LOGGING_SWITCH);
        
        RandomJoinTimerManager.instance.scheduleStartMatch(
          roomId,
          delaySeconds,
          (roomId) => _startMatchForRoom(roomId),
        );
      }
      
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
    // Use sessionId directly as player ID (userId kept for backward compatibility in events)
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
    _logger.room('🔍 _handleJoinRoom: About to join room with sessionId=$sessionId, userId=$userId, roomId=$roomId', isOn: LOGGING_SWITCH);
    if (_roomManager.joinRoom(roomId, sessionId, userId, password: password)) {
      // Send join_room_success (primary event matching Python)
      _logger.room('📤 Sending join_room_success to session: $sessionId (userId=$userId)', isOn: LOGGING_SWITCH);
      _logger.room('🔍 VERIFY: Using sessionId=$sessionId for sendToSession, NOT userId=$userId', isOn: LOGGING_SWITCH);
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
      _logger.room('📤 Sending room_joined to session: $sessionId', isOn: LOGGING_SWITCH);
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
      // Note: sessionId is used as player ID, userId kept for backward compatibility
      _server.triggerHook('room_joined', data: {
        'room_id': roomId,
        'session_id': sessionId, // This is now the player ID
        'user_id': userId, // Kept for backward compatibility
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      // Check if room has active timer and max players reached - start immediately
      // This handles both random join rooms and regular rooms with autoStart
      if (RandomJoinTimerManager.instance.isTimerActive(roomId)) {
        // For random join rooms, check against Config.RANDOM_JOIN_MAX_PLAYERS
        if (room.currentSize >= Config.RANDOM_JOIN_MAX_PLAYERS) {
          _logger.room('🚀 Max players reached, starting match immediately for random join room: $roomId', isOn: LOGGING_SWITCH);
          RandomJoinTimerManager.instance.cancelTimer(roomId);
          _startMatchForRandomJoin(roomId);
        }
        // For regular rooms, check against room.maxSize
        else if (room.currentSize >= room.maxSize) {
          _logger.room('🚀 Max players reached, starting match immediately for room: $roomId', isOn: LOGGING_SWITCH);
          RandomJoinTimerManager.instance.cancelTimer(roomId);
          _startMatchForRoom(roomId);
        }
      }
      
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
      
      // Cleanup timer if room becomes empty during delay period
      if (room != null && room.currentSize == 0) {
        RandomJoinTimerManager.instance.cleanup(roomId);
        _logger.room('🧹 Cleaned up timer for empty room: $roomId', isOn: LOGGING_SWITCH);
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
  
  /// Handle join random game event
  /// Searches for available public games or auto-creates and auto-starts a new one
  void _handleJoinRandomGame(String sessionId, Map<String, dynamic> data) {
    // Get userId from server's session mapping (more reliable than data)
    final userId = _server.getUserIdForSession(sessionId) ?? sessionId;
    
    _logger.room('🔍 _handleJoinRandomGame: sessionId=$sessionId, userId=$userId', isOn: LOGGING_SWITCH);
    
    try {
      // Get available rooms for random join
      final availableRooms = _getAvailableRoomsForRandomJoin();
      
      if (availableRooms.isNotEmpty) {
        // Pick a random room
        final random = Random();
        final selectedRoom = availableRooms[random.nextInt(availableRooms.length)];
        
        _logger.room('🎲 Joining random room: ${selectedRoom.roomId}', isOn: LOGGING_SWITCH);
        _logger.room('🔍 About to call _handleJoinRoom with sessionId=$sessionId, userId=$userId', isOn: LOGGING_SWITCH);
        
        // Use existing join room logic
        _handleJoinRoom(sessionId, {
          'room_id': selectedRoom.roomId,
          'user_id': userId,
        });
        
        return;
      }
      
      // No available rooms - create new room and auto-start
      _logger.room('🎲 No available rooms found, creating new room for random join', isOn: LOGGING_SWITCH);
      
      // Create room with default settings (using config values)
      final roomId = _roomManager.createRoom(
        sessionId,
        userId,
        maxSize: Config.RANDOM_JOIN_MAX_PLAYERS,
        minPlayers: Config.RANDOM_JOIN_MIN_PLAYERS,
        gameType: 'classic',
        permission: 'public',
        autoStart: true,
      );
      
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
        'turn_time_limit': room.turnTimeLimit,
        'auto_start': room.autoStart,
        'is_random_join': true, // Flag to indicate this was auto-created for random join
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
      });
      
      // Send room_joined event (auto-join creator)
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
      
      // Trigger room_joined hook (adds player to game state)
      // Note: sessionId is used as player ID, userId kept for backward compatibility
      _server.triggerHook('room_joined', data: {
        'room_id': roomId,
        'session_id': sessionId, // This is now the player ID
        'user_id': userId, // Kept for backward compatibility
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      // Schedule delayed match start instead of immediate start
      final delaySeconds = Config.RANDOM_JOIN_DELAY_SECONDS;
      _logger.room('⏱️  Scheduling delayed match start for random join room: $roomId (delay: ${delaySeconds}s)', isOn: LOGGING_SWITCH);
      
      RandomJoinTimerManager.instance.scheduleStartMatch(
        roomId,
        delaySeconds,
        (roomId) => _startMatchForRandomJoin(roomId),
      );
      
      _logger.room('✅ Random join room created with ${delaySeconds}s delay: $roomId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('❌ Error in _handleJoinRandomGame: $e', isOn: LOGGING_SWITCH);
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
        _logger.game('⚠️  Match already starting for room: $roomId', isOn: LOGGING_SWITCH);
        return;
      }

      // Set isStarting flag to prevent duplicate starts
      // This must be set before any async operations to prevent race conditions
      RandomJoinTimerManager.instance.setStarting(roomId);

      // Check if room still exists
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        _logger.error('❌ Room not found when starting match: $roomId', isOn: LOGGING_SWITCH);
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      // Check if game already started (check phase)
      final store = GameStateStore.instance;
      try {
        final gameState = store.getGameState(roomId);
        final phase = gameState['phase'] as String?;
        if (phase != null && phase != 'waiting_for_players') {
          _logger.game('⚠️  Game already started for room: $roomId (phase: $phase)', isOn: LOGGING_SWITCH);
          RandomJoinTimerManager.instance.cleanup(roomId);
          return;
        }
      } catch (e) {
        // Game state might not exist yet, continue
      }

      // Get a session ID from the room (use first available session)
      final sessions = _roomManager.getSessionsInRoom(roomId);
      if (sessions.isEmpty) {
        _logger.error('❌ No sessions in room when starting match: $roomId', isOn: LOGGING_SWITCH);
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      final sessionId = sessions.first;
      
      // Start the match
      _logger.game('🎮 Starting match for random join room: $roomId', isOn: LOGGING_SWITCH);
      _gameCoordinator.handle(sessionId, 'start_match', {
        'game_id': roomId,
        'min_players': room.minPlayers,
        'max_players': room.maxSize,
      });

      // Cleanup timer state
      RandomJoinTimerManager.instance.cleanup(roomId);
      
      _logger.room('✅ Match started for random join room: $roomId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error starting match for random join room $roomId: $e', isOn: LOGGING_SWITCH);
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
        _logger.game('⚠️  Match already starting for room: $roomId', isOn: LOGGING_SWITCH);
        return;
      }

      // Set isStarting flag to prevent duplicate starts
      // This must be set before any async operations to prevent race conditions
      RandomJoinTimerManager.instance.setStarting(roomId);

      // Check if room still exists
      final room = _roomManager.getRoomInfo(roomId);
      if (room == null) {
        _logger.error('❌ Room not found when starting match: $roomId', isOn: LOGGING_SWITCH);
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      // Check if game already started (check phase)
      final store = GameStateStore.instance;
      try {
        final gameState = store.getGameState(roomId);
        final phase = gameState['phase'] as String?;
        if (phase != null && phase != 'waiting_for_players') {
          _logger.game('⚠️  Game already started for room: $roomId (phase: $phase)', isOn: LOGGING_SWITCH);
          RandomJoinTimerManager.instance.cleanup(roomId);
          return;
        }
      } catch (e) {
        // Game state might not exist yet, continue
      }

      // Get a session ID from the room (use first available session)
      final sessions = _roomManager.getSessionsInRoom(roomId);
      if (sessions.isEmpty) {
        _logger.error('❌ No sessions in room when starting match: $roomId', isOn: LOGGING_SWITCH);
        RandomJoinTimerManager.instance.cleanup(roomId);
        return;
      }

      final sessionId = sessions.first;
      
      // Start the match
      _logger.game('🎮 Starting match for room: $roomId', isOn: LOGGING_SWITCH);
      _gameCoordinator.handle(sessionId, 'start_match', {
        'game_id': roomId,
        'min_players': room.minPlayers,
        'max_players': room.maxSize,
        'auto_start': room.autoStart, // Pass autoStart flag so coordinator can fill to maxPlayers
      });

      // Cleanup timer state (this also clears isStarting flag)
      RandomJoinTimerManager.instance.cleanup(roomId);
      
      _logger.room('✅ Match started for room: $roomId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error starting match for room $roomId: $e', isOn: LOGGING_SWITCH);
      RandomJoinTimerManager.instance.cleanup(roomId);
    }
  }

  /// Get available rooms for random join
  /// Filters rooms by: public permission, has capacity, phase is waiting_for_players
  List<Room> _getAvailableRoomsForRandomJoin() {
    final allRooms = _roomManager.getAllRooms();
    final store = GameStateStore.instance;
    final availableRooms = <Room>[];
    
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
  
  // ========= GAME EVENT HANDLER (UNIFIED) =========

  void _handleGameEvent(
    String sessionId,
    String event,
    Map<String, dynamic> data,
  ) {
    _logger.game('🎮 Game event: $event', isOn: LOGGING_SWITCH);
    _logger.game('📦 Data: $data', isOn: LOGGING_SWITCH);
    if (event == 'jack_swap') {
      _logger.game('🃏 _handleGameEvent: jack_swap event received - routing to GameEventCoordinator', isOn: LOGGING_SWITCH);
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
