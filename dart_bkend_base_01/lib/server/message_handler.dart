import 'dart:math';
import 'room_manager.dart';
import 'websocket_server.dart';
import '../utils/server_logger.dart';
import '../utils/config.dart';
import 'random_join_timer_manager.dart';
import '../modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart';
import '../modules/dutch_game/backend_core/services/game_state_store.dart';
import '../modules/dutch_game/utils/platform/shared_imports.dart';
import '../modules/dutch_game/backend_core/utils/rank_matcher.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true; // Enabled for create room/tournament flow, game finding, match creation

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
    if (LOGGING_SWITCH) {
      _logger.room('📥 create_room received: sessionId=$sessionId, data keys=${data.keys.toList()}, game_type=${data['game_type'] ?? data['gameType']}, permission=${data['permission']}, auto_start=${data['auto_start'] ?? data['autoStart']}, tournamentName=${data['tournament_name'] ?? data['tournamentName']}, tournamentFormat=${data['tournament_format'] ?? data['tournamentFormat']}');
    }
    // Get userId from server's session mapping (should be set after authentication)
    final userId = _server.getUserIdForSession(sessionId);
    
    if (userId == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleCreateRoom: Session $sessionId is authenticated but userId is null');
      }
      _sendError(sessionId, 'User ID not available. Please reconnect.');
      return;
    }
    
    // Extract room settings from data (matching Python backend)
    final maxPlayers = 4; // Hardcoded to 4, no options
    final minPlayers = data['min_players'] as int? ?? data['minPlayers'] as int?;
    final gameType = data['game_type'] as String? ?? data['gameType'] as String?;
    final permission = data['permission'] as String?;
    final password = data['password'] as String?;
    final autoStart = data['auto_start'] as bool? ?? data['autoStart'] as bool?;
    
    try {
      // Create room with settings (timer values are now phase-based, managed by RoomManager)
      final roomId = _roomManager.createRoom(
        sessionId,
        userId,
        maxSize: maxPlayers,
        minPlayers: minPlayers,
        gameType: gameType,
        permission: permission,
        password: password,
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
        'auto_start': room.autoStart,
        'difficulty': room.difficulty, // Room difficulty (rank-based)
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
        if (LOGGING_SWITCH) {
          _logger.room('⏱️  Scheduling auto-start timer for room: $roomId (delay: ${delaySeconds}s, maxSize: ${room.maxSize})');
        }
        
        RandomJoinTimerManager.instance.scheduleStartMatch(
          roomId,
          delaySeconds,
          (roomId) => _startMatchForRoom(roomId),
        );
      }
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ Room created and creator auto-joined: $roomId');
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
  
  void _handleJoinRoom(String sessionId, Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    final password = data['password'] as String?;
    
    // Get userId from server's session mapping (should be set after authentication)
    final userId = _server.getUserIdForSession(sessionId);
    
    if (userId == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleJoinRoom: Session $sessionId is authenticated but userId is null');
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
    
    // Attempt to join room
    if (LOGGING_SWITCH) {
      _logger.room('🔍 _handleJoinRoom: About to join room with sessionId=$sessionId, userId=$userId, roomId=$roomId');
    }
    if (_roomManager.joinRoom(roomId, sessionId, userId, password: password)) {
      // Send join_room_success (primary event matching Python)
      if (LOGGING_SWITCH) {
        _logger.room('📤 Sending join_room_success to session: $sessionId (userId=$userId)');
        _logger.room('🔍 VERIFY: Using sessionId=$sessionId for sendToSession, NOT userId=$userId');
      }
      _server.sendToSession(sessionId, {
        'event': 'join_room_success',
        'room_id': roomId,
        'session_id': sessionId,
        'user_id': userId,
        'owner_id': room.ownerId,
        'current_size': room.currentSize,
        'max_size': room.maxSize,
        'difficulty': room.difficulty, // Room difficulty (rank-based)
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Also send room_joined for backward compatibility
      if (LOGGING_SWITCH) {
        _logger.room('📤 Sending room_joined to session: $sessionId');
      }
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
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Max players reached, starting match immediately for random join room: $roomId');
          }
          RandomJoinTimerManager.instance.cancelTimer(roomId);
          _startMatchForRandomJoin(roomId);
        }
        // For regular rooms, check against room.maxSize
        else if (room.currentSize >= room.maxSize) {
          if (LOGGING_SWITCH) {
            _logger.room('🚀 Max players reached, starting match immediately for room: $roomId');
          }
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
      
      if (LOGGING_SWITCH) {
        _logger.room('✅ User $userId joined room $roomId');
      }
    } else {
      _server.sendToSession(sessionId, {
        'event': 'join_room_error',
        'message': 'Failed to join room: $roomId',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
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
    if (LOGGING_SWITCH) {
      _logger.room('✅ _handleJoinRandomGame: parsed isClearAndCollect: value=$isClearAndCollect (type: ${isClearAndCollect.runtimeType})');
      _logger.room('🔍 _handleJoinRandomGame: sessionId=$sessionId, userId=$userId, isClearAndCollect=$isClearAndCollect');
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
      
      // Filter by rank compatibility
      final userRank = _server.getUserRankForSession(sessionId);
      availableRooms = _filterRoomsByRank(availableRooms, userRank);
      
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
      
      // No available rooms - create new room and auto-start
      if (LOGGING_SWITCH) {
        _logger.room('🎲 No available rooms found, creating new room for random join');
      }
      
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
      
      // Start the match
      if (LOGGING_SWITCH) {
        _logger.game('🎮 Starting match for room: $roomId');
      }
      _gameCoordinator.handle(sessionId, 'start_match', {
        'game_id': roomId,
        'min_players': room.minPlayers,
        'max_players': room.maxSize,
        'auto_start': room.autoStart, // Pass autoStart flag so coordinator can fill to maxPlayers
      });

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
