import '../state_manager.dart';
import '../module_manager.dart';
import '../hooks_manager.dart';
import '../../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../../modules/dutch_game/managers/dutch_game_state_updater.dart';
import '../../../modules/notifications_module/notifications_module.dart';
import 'ws_event_manager.dart';
import 'websocket_state_validator.dart';
import 'native_websocket_adapter.dart';
import '../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true; // create_room_success, room_joined, hooks (enable-logging-switch.mdc)

/// WebSocket Event Handler
/// Centralized event processing logic for all WebSocket events
class WSEventHandler {
  final NativeWebSocketAdapter? _socket;
  final WSEventManager _eventManager;
  final StateManager _stateManager;
  final ModuleManager _moduleManager;
  static final Logger _logger = Logger();

  WSEventHandler({
    required NativeWebSocketAdapter? socket,
    required WSEventManager eventManager,
    required StateManager stateManager,
    required ModuleManager moduleManager,
  })  : _socket = socket,
        _eventManager = eventManager,
        _stateManager = stateManager,
        _moduleManager = moduleManager;

  /// Handle connection event
  void handleConnect(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🔌 WebSocket connection established');
      }
      if (data is Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.debug('Connection data: ${data.keys.toList()}');
        }
        if (LOGGING_SWITCH) {
          _logger.debug('Session ID: ${data['session_id']}');
        }
      }
      
      // Use validated state updater
      if (LOGGING_SWITCH) {
        _logger.info('🔄 Calling WebSocketStateHelpers.updateConnectionStatus()');
      }
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: true,
        sessionData: data is Map<String, dynamic> ? data : null,
      );
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocketStateHelpers.updateConnectionStatus() completed');
      }
      
      // 🎣 Trigger websocket_connect hook for other modules
      HooksManager().triggerHookWithData('websocket_connect', {
        'status': 'connected',
        'session_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket connection handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling WebSocket connection: $e');
      }
    }
  }

  /// Handle disconnection event
  void handleDisconnect(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🔌 WebSocket connection lost');
      }
      if (data is Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.debug('Disconnect data: ${data.keys.toList()}');
        }
      }
      
      // Use validated state updater
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
      
      // 🎣 Trigger websocket_disconnect hook for other modules
      HooksManager().triggerHookWithData('websocket_disconnect', {
        'status': 'disconnected',
        'session_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket disconnection handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling WebSocket disconnection: $e');
      }
    }
  }

  /// Handle connection error event
  void handleConnectError(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.error('❌ WebSocket connection error occurred');
      }
      if (data is Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.debug('Error data: ${data.keys.toList()}');
        }
      }
      
      // Use validated state updater
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
            
      // 🎣 Trigger websocket_connect_error hook for other modules
      HooksManager().triggerHookWithData('websocket_connect_error', {
        'status': 'error',
        'error_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket connection error handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling WebSocket connection error: $e');
      }
    }
  }

  /// Handle session data event
  void handleSessionData(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📊 WebSocket session data received');
      }
      if (data is Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.debug('Session data keys: ${data.keys.toList()}');
        }
      }
      
      // Use validated state updater
      WebSocketStateHelpers.updateSessionData(
        data is Map<String, dynamic> ? data : null,
      );
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket session data handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling WebSocket session data: $e');
      }
    }
  }

    /// Handle room joined event
  void handleRoomJoined(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🚪 WebSocket room joined event received');
      }
      
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> convertedData;
      if (data is Map) {
        convertedData = Map<String, dynamic>.from(data);
      } else {
        convertedData = <String, dynamic>{};
      }
      
      final roomId = convertedData['room_id'] ?? '';
      final roomData = convertedData;
      final ownerId = convertedData['owner_id']?.toString() ?? '';
      
      // Get current user ID from login module state
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      
      // Check if current user is the room owner
      final isRoomOwner = currentUserId == ownerId;
      if (LOGGING_SWITCH) {
        _logger.info('📥 room_joined received: roomId=$roomId, owner_id=$ownerId, currentUserId=$currentUserId, isRoomOwner=$isRoomOwner');
      }
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Also reflect ownership in Dutch game main state so UI (GameInfoWidget) can gate Start button
      // Note: isInGame is only stored within games map structure, not as top-level field
      DutchGameHelpers.updateUIState({
        'isRoomOwner': isRoomOwner,
      });
      
      // Ensure games map entry reflects ownership immediately
      try {
        final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
        final current = Map<String, dynamic>.from(games[roomId] as Map<String, dynamic>? ?? {'gameData': {}});
        current['isRoomOwner'] = isRoomOwner;
        current['isInGame'] = true;
        games[roomId] = current;
        DutchGameHelpers.updateUIState({'games': games});
        if (LOGGING_SWITCH) {
          _logger.info('📥 room_joined: games[$roomId] updated, isRoomOwner=$isRoomOwner, owner_id=$ownerId');
        }
      } catch (_) {}
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_joined', convertedData);
      _eventManager.triggerCallbacks('join_room_success', convertedData);
      
      // 🎣 Trigger websocket_room_joined hook for other modules
      HooksManager().triggerHookWithData('websocket_room_joined', {
        'status': 'joined',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Also trigger websocket_join_room hook (for navigation logic)
      // This ensures navigation works even if join_room_success event is not received
      HooksManager().triggerHookWithData('websocket_join_room', {
        'status': 'success',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket room joined event handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling WebSocket room joined event: $e');
      }
    }
  }

  /// Handle join room success event
  void handleJoinRoomSuccess(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket join_room_success event received');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('Join room success data: $data');
      }
      
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> convertedData;
      if (data is Map) {
        convertedData = Map<String, dynamic>.from(data);
      } else {
        convertedData = <String, dynamic>{};
      }
      
      final roomId = convertedData['room_id'] ?? '';
      final roomData = convertedData;
      final ownerId = data['owner_id'] ?? '';
      
      // Get current user ID from login module state
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId'] ?? '';
      
      // Check if current user is the room owner
      final isRoomOwner = currentUserId == ownerId;
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('join_room_success', convertedData);
      
      // 🎣 Trigger websocket_join_room hook for other modules
      HooksManager().triggerHookWithData('websocket_join_room', {
        'status': 'success',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket join_room_success event handled successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error handling join_room_success: $e');
      }
    }
  }

  /// Handle already joined event
  void handleAlreadyJoined(dynamic data) {
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> convertedData;
      if (data is Map) {
        convertedData = Map<String, dynamic>.from(data);
      } else {
        convertedData = <String, dynamic>{};
      }
      
      final roomId = convertedData['room_id'] ?? '';
      final roomData = convertedData;
      final ownerId = data['owner_id'] ?? '';
      
      // Get current user ID from login module state
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId'] ?? '';
      
      // Check if current user is the room owner
      final isRoomOwner = currentUserId == ownerId;
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'already_joined',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('already_joined', data);
      
      // 🎣 Trigger websocket_already_joined hook for other modules
      HooksManager().triggerHookWithData('websocket_already_joined', {
        'status': 'already_joined',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling already joined
    }
  }

  /// Handle join room error event
  void handleJoinRoomError(dynamic data) {
    try {
      final Map<String, dynamic> payload = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      final message = payload['message']?.toString() ?? '';
      if (LOGGING_SWITCH) {
        _logger.info(
          '📛 join_room_error message=$message keys=${payload.keys.toList()} room_id=${payload['room_id']} game_level=${payload['game_level']} required_coins=${payload['required_coins']}',
        );
      }

      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to join room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('join_room_error', data);
      
      // 🎣 Trigger websocket_join_room_error hook for other modules
      HooksManager().triggerHookWithData('websocket_join_room_error', {
        'status': 'error',
        'error': 'Failed to join room',
        'message': message,
        'room_id': payload['room_id'],
        'game_level': payload['game_level'],
        'required_coins': payload['required_coins'],
        'payload': payload,
        'details': data.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling join room error
    }
  }

  /// Handle create room success event
  void handleCreateRoomSuccess(dynamic data) {
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;  // Use the entire data object since it's simplified
      final ownerId = data['owner_id'] ?? '';
      if (LOGGING_SWITCH) {
        _logger.info(
          '🏟 create_room_success — room_id=$roomId owner_id=$ownerId is_tournament=${data['is_tournament']} is_random_join=${data['is_random_join']} min_players=${data['min_players']} accepted_players=${data['accepted_players']}',
        );
      }
      
      // Get current user ID from login module state
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId'] ?? '';
      
      // Check if this is a random join auto-created room
      final isRandomJoin = data['is_random_join'] == true;
      
      // Check if current user is the room owner
      // For random join rooms, always set isOwner to false even if user is the owner
      final isRoomOwner = isRandomJoin ? false : (currentUserId == ownerId);
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Set room ownership and game state in dutch game state
      final maxSize = roomData['max_size']; // Extract max_size from room data
      final minSize = roomData['min_players']; // Extract min_players from room data
      
      // Ensure we have the required data
      if (maxSize == null || minSize == null) {
        return;
      }
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'created',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('create_room_success', data);
      _eventManager.triggerCallbacks('room_created', data);
      
      // 🎣 Trigger general room_creation hook for other modules (success case)
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'success',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'is_random_join': isRandomJoin,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling create room success
    }
  }

  /// Handle room created event
  void handleRoomCreated(dynamic data) {
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'created',
        'roomId': roomId,
        'roomData': roomData,
      });
      
      // 🎣 Trigger general room_creation hook for other modules (room created event)
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'created',
        'room_id': roomId,
        'room_data': roomData,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_created', data);
    } catch (e) {
      // Error handling room created
    }
  }

  /// Handle create room error event
  void handleCreateRoomError(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🏟 create_room_error received — data=$data');
      }
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to create room',
        'details': data.toString(),
      });
      
      // 🎣 Trigger general room_creation hook for other modules (error case)
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'error',
        'error': 'Failed to create room',
        'details': data.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('create_room_error', data);
    } catch (e) {
      // Error handling create room error
    }
  }

  /// Handle leave room success event
  void handleLeaveRoomSuccess(dynamic data) {
    try {
      final roomId = data['room_id'] ?? '';
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: null,
        roomInfo: null,
      );
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'left',
        'roomId': roomId,
        'roomData': data,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('leave_room_success', data);
    } catch (e) {
      // Error handling leave room success
    }
  }

  /// Handle leave room error event
  void handleLeaveRoomError(dynamic data) {
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to leave room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('leave_room_error', data);
    } catch (e) {
      // Error handling leave room error
    }
  }

  /// Handle room closed event
  void handleRoomClosed(dynamic data) {
    try {
      if (data is Map<String, dynamic>) {
        final roomId = data['room_id'] ?? '';
        final reason = data['reason'] ?? 'unknown';
        final timestamp = data['timestamp'];
        
        // Update WebSocket state to clear room info if it's the current room
        final currentRoomId = WebSocketStateUpdater.getCurrentRoomId();
        if (currentRoomId == roomId) {
          WebSocketStateHelpers.clearRoomInfo();
        }
        
        // Trigger room closed callbacks
        _eventManager.triggerCallbacks('room_closed', {
          'room_id': roomId,
          'reason': reason,
          'timestamp': timestamp,
          'data': data,
        });
    }
  } catch (e) {
    // Error handling room closed event
  }
}

  /// Handle user joined rooms event
  void handleUserJoinedRooms(dynamic data) {
    try {
      // Validate the data structure
      if (data is! Map<String, dynamic>) {
        return;
      }
      
      final sessionId = data['session_id']?.toString() ?? '';
      final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      // Update WebSocket state with joined rooms information
      WebSocketStateHelpers.updateJoinedRooms(
        sessionId: sessionId,
        joinedRooms: rooms.cast<Map<String, dynamic>>(),
        totalRooms: totalRooms,
        timestamp: timestamp,
      );
      
      // Trigger event callbacks for room management
      _eventManager.triggerCallbacks('user_joined_rooms', {
        'session_id': sessionId,
        'rooms': rooms,
        'total_rooms': totalRooms,
        'timestamp': timestamp,
      });
      
      // 🎣 Trigger websocket_user_joined_rooms hook for other modules
      HooksManager().triggerHookWithData('websocket_user_joined_rooms', {
        'status': 'updated',
        'session_id': sessionId,
        'rooms': rooms,
        'total_rooms': totalRooms,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling user joined rooms
    }
  }

  /// Handle new player joined event
  void handleNewPlayerJoined(dynamic data) {
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> convertedData;
      if (data is Map) {
        convertedData = Map<String, dynamic>.from(data);
      } else {
        return; // Invalid data structure
      }
      
      final roomId = convertedData['room_id']?.toString() ?? '';
      final joinedPlayer = (convertedData['joined_player'] as Map? ?? {}) is Map
          ? Map<String, dynamic>.from(convertedData['joined_player'] as Map)
          : <String, dynamic>{};
      final gameState = (convertedData['game_state'] as Map? ?? {}) is Map
          ? Map<String, dynamic>.from(convertedData['game_state'] as Map)
          : <String, dynamic>{};
      final timestamp = data['timestamp']?.toString() ?? '';
      
      // Note: State updates are handled by Dutch module via hooks
      
      // Trigger event callbacks for game management
      _eventManager.triggerCallbacks('new_player_joined', {
        'room_id': roomId,
        'joined_player': joinedPlayer,
        'game_state': gameState,
        'timestamp': timestamp,
      });
      
      // 🎣 Trigger websocket_new_player_joined hook for other modules
      HooksManager().triggerHookWithData('websocket_new_player_joined', {
        'status': 'player_joined',
        'room_id': roomId,
        'joined_player': joinedPlayer,
        'game_state': gameState,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling new player joined
    }
  }

  /// Handle joined games event
  void handleJoinedGames(dynamic data) {
    try {
      // Validate the data structure
      if (data is! Map<String, dynamic>) {
        return;
      }
      
      final userId = data['user_id']?.toString() ?? '';
      final sessionId = data['session_id']?.toString() ?? '';
      final games = data['games'] as List<dynamic>? ?? [];
      final totalGames = data['total_games'] ?? 0;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      // Note: State updates are handled by Dutch module via hooks
      
      // Trigger event callbacks for game management
      _eventManager.triggerCallbacks('joined_games', {
        'user_id': userId,
        'session_id': sessionId,
        'games': games,
        'total_games': totalGames,
        'timestamp': timestamp,
      });
      
      // 🎣 Trigger websocket_joined_games hook for other modules
      HooksManager().triggerHookWithData('websocket_joined_games', {
        'status': 'updated',
        'user_id': userId,
        'session_id': sessionId,
        'games': games,
        'total_games': totalGames,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Error handling joined games
    }
  }

  /// Handle message event
  void handleMessage(dynamic data) {
    try {
      final roomId = data['room_id'] ?? '';
      final message = data['message'] ?? '';
      final sender = data['sender'] ?? 'unknown';
    } catch (e) {
      // Error handling message
    }
  }

  /// Handle error events
  void handleError(dynamic data) {
    try {
      // Error event received
    } catch (e) {
      // Error handling error event
    }
  }



  /// Handle unified event (for custom events)
  void handleUnifiedEvent(String eventName, dynamic data) {
    try {
      // Route to appropriate handler based on event name
      switch (eventName) {
        case 'connect':
          handleConnect(data);
          break;
        case 'disconnect':
          handleDisconnect(data);
          break;
        case 'connect_error':
          handleConnectError(data);
          break;
        case 'session_data':
          handleSessionData(data);
          break;
        case 'room_joined':
          handleRoomJoined(data);
          break;
        case 'join_room_success':
          handleJoinRoomSuccess(data);
          break;
        case 'join_room_error':
          handleJoinRoomError(data);
          break;
        case 'create_room_success':
          handleCreateRoomSuccess(data);
          break;
        case 'room_created':
          handleRoomCreated(data);
          break;
        case 'create_room_error':
          handleCreateRoomError(data);
          break;
        case 'leave_room_success':
          handleLeaveRoomSuccess(data);
          break;
        case 'leave_room_error':
          handleLeaveRoomError(data);
          break;
        case 'message':
          handleMessage(data);
          break;
        case 'error':
          handleError(data);
          break;
        case 'rooms_list':
          handleRoomsList(data);
          break;
        default:
          // Unknown event type
          break;
      }
    } catch (e) {
      // Error in unified event handler
    }
  }
  
  /// Handle rooms_list event (response to list_rooms request)
  void handleRoomsList(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📋 Rooms list received');
      }
      
      if (data is! Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.warning('Invalid rooms_list data format');
        }
        return;
      }
      
      final rooms = data['rooms'] as List<dynamic>? ?? [];
      final total = data['total'] as int? ?? rooms.length;
      
      // Convert rooms to available games format
      final availableGames = rooms.map((room) {
        if (room is! Map<String, dynamic>) return null;
        
        // Map room data to game format expected by the UI
        return {
          'gameId': room['room_id'] ?? '',
          'gameName': 'Game_${room['room_id'] ?? 'Unknown'}',
          'roomId': room['room_id'] ?? '',
          'playerCount': room['current_size'] ?? 0,
          'maxPlayers': room['max_size'] ?? 4,
          'minPlayers': room['min_players'] ?? 2,
          'phase': 'waiting_for_players', // Default phase for available games
          'permission': room['permission'] ?? 'public',
          'gameType': room['game_type'] ?? 'classic',
          'ownerId': room['owner_id'] ?? '',
          'createdAt': room['created_at'] ?? '',
        };
      }).whereType<Map<String, dynamic>>().toList();
      
      // Update dutch game state with available games
      final dutchStateUpdater = DutchGameStateUpdater.instance;
      dutchStateUpdater.updateState({
        'availableGames': availableGames,
        'isLoading': false,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ Updated available games: ${availableGames.length} games');
      }
      
      // Trigger custom event callback
      _eventManager.triggerCallbacks('rooms_list', {
        'rooms': rooms,
        'total': total,
        'availableGames': availableGames,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling rooms_list: $e');
      }
    }
  }
  
  /// Handle authentication success
  void handleAuthenticationSuccess(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🔐 User authenticated');
      }
      
      WebSocketStateHelpers.updateAuthenticationStatus(
        isAuthenticated: true,
        userId: data is Map ? data['user_id'] : null,
      );
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling authentication success: $e');
      }
    }
  }
  
  /// Handle authentication failure
  void handleAuthenticationFailed(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.warning('Authentication failed');
      }
      
      WebSocketStateHelpers.updateAuthenticationStatus(
        isAuthenticated: false,
        error: data is Map ? data['message'] : 'Authentication failed',
      );

      // Tear down transport so the next initialize/connect uses a fresh channel + JWT (no app restart).
      HooksManager().triggerHookWithData('websocket_reset_transport', {
        'reason': 'authentication_failed',
      });
      
      // Authentication failure - navigation handled by calling module (e.g., Dutch game module)
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling authentication failure: $e');
      }
    }
  }
  
  /// Handle authentication error
  void handleAuthenticationError(dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.error('Authentication error');
      }
      
      WebSocketStateHelpers.updateAuthenticationStatus(
        isAuthenticated: false,
        error: data is Map ? data['message'] : 'Authentication error',
      );

      HooksManager().triggerHookWithData('websocket_reset_transport', {
        'reason': 'authentication_error',
      });
      
      // Authentication error - navigation handled by calling module (e.g., Dutch game module)
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling authentication error: $e');
      }
    }
  }
  /// Handle core ws_instant_notification event (Dart backend pushes instant notification to session).
  void handleWsInstantNotification(dynamic data) {
    try {
      final payload = data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
      if (payload.isEmpty) return;
      final mod = _moduleManager.getModuleByType<NotificationsModule>();
      mod?.addPendingWsInstant(payload);
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling ws_instant_notification: $e');
      }
    }
  }

  /// Rematch invite from another player — queued as [instant_ws] with Accept/Decline (see [submitRematchInviteResponse]).
  void handleRestartInvite(dynamic data) {
    try {
      final map = data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
      final roomId = map['room_id'] as String? ?? map['game_id'] as String? ?? '';
      if (roomId.isEmpty) return;
      final fromSession = map['from_session_id'] as String? ?? '';
      final fromUser = map['from_user_id'] as String?;
      final gameLevelRaw = map['game_level'];
      final gameLevel = gameLevelRaw is int
          ? gameLevelRaw
          : (gameLevelRaw is num
              ? gameLevelRaw.toInt()
              : int.tryParse(gameLevelRaw?.toString() ?? '') ?? 1);
      final isCoinRequiredRaw = map['is_coin_required'];
      final isCoinRequired = isCoinRequiredRaw is bool
          ? isCoinRequiredRaw
          : (isCoinRequiredRaw?.toString().toLowerCase() != 'false');
      final id = 'restart_invite_${roomId}_${DateTime.now().millisecondsSinceEpoch}';
      final message = <String, dynamic>{
        'id': id,
        'type': 'instant_ws',
        'title': 'Rematch invite',
        'body': 'You were invited to rematch.',
        'responses': [
          {'label': 'Accept', 'action_identifier': 'rematch_accept'},
          {'label': 'Decline', 'action_identifier': 'rematch_decline'},
        ],
        'data': {
          'respond_via': 'rematch_ws',
          'room_id': roomId,
          'game_id': map['game_id'] as String? ?? roomId,
          'from_session_id': fromSession,
          'game_level': gameLevel,
          'is_coin_required': isCoinRequired,
          if (fromUser != null && fromUser.isNotEmpty) 'from_user_id': fromUser,
        },
        'timestamp': map['timestamp'] ?? DateTime.now().toIso8601String(),
      };
      final mod = _moduleManager.getModuleByType<NotificationsModule>();
      mod?.addPendingWsInstant(message);

      // Game-ended overlay: show "Waiting Rematch" on Play Again (same room).
      _stateManager.updateModuleState('dutch_game', {
        'rematch_waiting_game_id': roomId,
      });
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling restart_invite: $e');
      }
    }
  }

  /// Handle custom events (like game event acknowledgments)
  void handleCustomEvent(String eventType, dynamic data) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 Custom event received: $eventType');
      }
      
      // Trigger event callbacks
      _eventManager.triggerCallbacks(eventType, data);
      
      // Trigger hooks for other modules
      HooksManager().triggerHookWithData('websocket_custom_event', {
        'event_type': eventType,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error handling custom event $eventType: $e');
      }
    }
  }
} 