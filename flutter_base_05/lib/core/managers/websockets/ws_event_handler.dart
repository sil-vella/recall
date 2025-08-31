import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../state_manager.dart';
import '../module_manager.dart';
import '../hooks_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'ws_event_manager.dart';
import 'websocket_state_validator.dart';

/// WebSocket Event Handler
/// Centralized event processing logic for all WebSocket events
class WSEventHandler {
  final IO.Socket? _socket;
  final WSEventManager _eventManager;
  final StateManager _stateManager;
  final ModuleManager _moduleManager;
  final Logger _log;

  WSEventHandler({
    required IO.Socket? socket,
    required WSEventManager eventManager,
    required StateManager stateManager,
    required ModuleManager moduleManager,
  })  : _socket = socket,
        _eventManager = eventManager,
        _stateManager = stateManager,
        _moduleManager = moduleManager,
        _log = Logger();

  /// Handle connection event
  void handleConnect(dynamic data) {
    _log.info("🔧 [HANDLER-CONNECT] Handling connection event");
    
    try {
      // Use validated state updater
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: true,
        sessionData: data is Map<String, dynamic> ? data : null,
      );
      
      // 🎣 Trigger websocket_connect hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_connect hook");
      HooksManager().triggerHookWithData('websocket_connect', {
        'status': 'connected',
        'session_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Connection handled successfully");
    } catch (e) {
      _log.error("❌ Error handling connection: $e");
    }
  }

  /// Handle disconnection event
  void handleDisconnect(dynamic data) {
    _log.info("🔧 [HANDLER-DISCONNECT] Handling disconnection event");
    
    try {
      // Use validated state updater
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
      
      // 🎣 Trigger websocket_disconnect hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_disconnect hook");
      HooksManager().triggerHookWithData('websocket_disconnect', {
        'status': 'disconnected',
        'session_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Disconnection handled successfully");
    } catch (e) {
      _log.error("❌ Error handling disconnection: $e");
    }
  }

  /// Handle connection error event
  void handleConnectError(dynamic data) {
    _log.info("🔧 [HANDLER-CONNECT_ERROR] Handling connection error event");
    
    try {
      // Use validated state updater
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
            
      // 🎣 Trigger websocket_connect_error hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_connect_error hook");
      HooksManager().triggerHookWithData('websocket_connect_error', {
        'status': 'error',
        'error_data': data is Map<String, dynamic> ? data : null,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Connection error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling connection error: $e");
    }
  }

  /// Handle session data event
  void handleSessionData(dynamic data) {
    _log.info("🔧 [HANDLER-SESSION_DATA] Handling session data event");
    
    try {
      // Use validated state updater
      WebSocketStateHelpers.updateSessionData(
        data is Map<String, dynamic> ? data : null,
      );
      
      _log.info("✅ Session data handled successfully");
    } catch (e) {
      _log.error("❌ Error handling session data: $e");
    }
  }

    /// Handle room joined event
  void handleRoomJoined(dynamic data) {
    _log.info("🔧 [HANDLER-ROOM_JOINED] Handling room joined event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
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
      
      // Note: State updates are handled by Recall module via hooks
      _log.info("${isRoomOwner ? '✅' : 'ℹ️'} Set room ownership for user: $currentUserId (isOwner: $isRoomOwner)");
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_joined', data);
      _eventManager.triggerCallbacks('join_room_success', data);
      
      // 🎣 Trigger websocket_room_joined hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_room_joined hook");
      HooksManager().triggerHookWithData('websocket_room_joined', {
        'status': 'joined',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Room joined handled successfully");
    } catch (e) {
      _log.error("❌ Error handling room joined: $e");
    }
  }

  /// Handle join room success event
  void handleJoinRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-JOIN_ROOM_SUCCESS] Handling join room success event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
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
      
      // Note: State updates are handled by Recall module via hooks
      _log.info("${isRoomOwner ? '✅' : 'ℹ️'} Set room ownership for user: $currentUserId (isOwner: $isRoomOwner)");
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
        'isOwner': isRoomOwner,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('join_room_success', data);
      
      // 🎣 Trigger websocket_join_room hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_join_room hook");
      HooksManager().triggerHookWithData('websocket_join_room', {
        'status': 'success',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Join room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling join room success: $e");
    }
  }

  /// Handle already joined event
  void handleAlreadyJoined(dynamic data) {
    _log.info("🔧 [HANDLER-ALREADY_JOINED] Handling already joined event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
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
      
      // Note: State updates are handled by Recall module via hooks
      _log.info("${isRoomOwner ? '✅' : 'ℹ️'} Set room ownership for user: $currentUserId (isOwner: $isRoomOwner) - already joined");
      
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
      _log.info("🎣 [HOOK] Triggering websocket_already_joined hook");
      HooksManager().triggerHookWithData('websocket_already_joined', {
        'status': 'already_joined',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Already joined handled successfully");
    } catch (e) {
      _log.error("❌ Error handling already joined: $e");
    }
  }

  /// Handle join room error event
  void handleJoinRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-JOIN_ROOM_ERROR] Handling join room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to join room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('join_room_error', data);
      
      // 🎣 Trigger websocket_join_room_error hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_join_room_error hook");
      HooksManager().triggerHookWithData('websocket_join_room_error', {
        'status': 'error',
        'error': 'Failed to join room',
        'details': data.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Join room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling join room error: $e");
    }
  }

  /// Handle create room success event
  void handleCreateRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-CREATE_ROOM_SUCCESS] Handling create room success event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;  // Use the entire data object since it's simplified
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
      
      // Set room ownership and game state in recall game state
      final maxSize = roomData['max_size']; // Extract max_size from room data
      final minSize = roomData['min_players']; // Extract min_players from room data
      
      // Ensure we have the required data
      if (maxSize == null || minSize == null) {
        _log.error("❌ Missing room size data: max_size=$maxSize, min_players=$minSize");
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
      _log.info("🎣 [HOOK] Triggering room_creation hook with success data");
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'success',
        'room_id': roomId,
        'room_data': roomData,
        'owner_id': ownerId,
        'is_owner': isRoomOwner,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Create room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling create room success: $e");
    }
  }

  /// Handle room created event
  void handleRoomCreated(dynamic data) {
    _log.info("🔧 [HANDLER-ROOM_CREATED] Handling room created event");
    
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
      _log.info("🎣 [HOOK] Triggering room_creation hook with room created data");
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'created',
        'room_id': roomId,
        'room_data': roomData,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_created', data);
      
      _log.info("✅ Room created handled successfully");
    } catch (e) {
      _log.error("❌ Error handling room created: $e");
    }
  }

  /// Handle create room error event
  void handleCreateRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-CREATE_ROOM_ERROR] Handling create room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to create room',
        'details': data.toString(),
      });
      
      // 🎣 Trigger general room_creation hook for other modules (error case)
      _log.info("🎣 [HOOK] Triggering room_creation hook with error data");
      HooksManager().triggerHookWithData('room_creation', {
        'status': 'error',
        'error': 'Failed to create room',
        'details': data.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('create_room_error', data);
      
      _log.info("✅ Create room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling create room error: $e");
    }
  }

  /// Handle leave room success event
  void handleLeaveRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-LEAVE_ROOM_SUCCESS] Handling leave room success event");
    
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
      
      _log.info("✅ Leave room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling leave room success: $e");
    }
  }

  /// Handle leave room error event
  void handleLeaveRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-LEAVE_ROOM_ERROR] Handling leave room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to leave room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('leave_room_error', data);
      
      _log.info("✅ Leave room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling leave room error: $e");
    }
  }

  /// Handle room closed event
  void handleRoomClosed(dynamic data) {
    _log.info("🔧 [HANDLER-ROOM_CLOSED] Handling room closed event");
    
    try {
      if (data is Map<String, dynamic>) {
        final roomId = data['room_id'] ?? '';
        final reason = data['reason'] ?? 'unknown';
        final timestamp = data['timestamp'];
        
        _log.info("🏠 Room closed: $roomId (reason: $reason)");
        
        // Update WebSocket state to clear room info if it's the current room
        final currentRoomId = WebSocketStateUpdater.getCurrentRoomId();
        if (currentRoomId == roomId) {
          WebSocketStateHelpers.clearRoomInfo();
          _log.info("🔧 Cleared current room info due to room closure");
        }
        
        // Trigger room closed callbacks
        _eventManager.triggerCallbacks('room_closed', {
          'room_id': roomId,
          'reason': reason,
          'timestamp': timestamp,
          'data': data,
        });
        
              _log.info("✅ Room closed event handled successfully");
    }
  } catch (e) {
    _log.error("❌ Error handling room closed event: $e");
  }
}

  /// Handle user joined rooms event
  void handleUserJoinedRooms(dynamic data) {
    _log.info("🔧 [HANDLER-USER_JOINED_ROOMS] Handling user joined rooms event");
    
    try {
      // Validate the data structure
      if (data is! Map<String, dynamic>) {
        _log.error("❌ Invalid data format for user_joined_rooms event");
        return;
      }
      
      final sessionId = data['session_id']?.toString() ?? '';
      final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info("🏠 [USER_JOINED_ROOMS] Session: $sessionId, Total rooms: $totalRooms");
      
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
      _log.info("🎣 [HOOK] Triggering websocket_user_joined_rooms hook");
      HooksManager().triggerHookWithData('websocket_user_joined_rooms', {
        'status': 'updated',
        'session_id': sessionId,
        'rooms': rooms,
        'total_rooms': totalRooms,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ User joined rooms handled successfully");
    } catch (e) {
      _log.error("❌ Error handling user joined rooms: $e");
    }
  }

  /// Handle new player joined event
  void handleNewPlayerJoined(dynamic data) {
    _log.info("🔧 [HANDLER-NEW_PLAYER_JOINED] Handling new player joined event");
    
    try {
      // Validate the data structure
      if (data is! Map<String, dynamic>) {
        _log.error("❌ Invalid data format for new_player_joined event");
        return;
      }
      
      final roomId = data['room_id']?.toString() ?? '';
      final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
      final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info("🎮 [NEW_PLAYER_JOINED] Room: $roomId, Player: ${joinedPlayer['name']}");
      
      // Note: State updates are handled by Recall module via hooks
      
      // Trigger event callbacks for game management
      _eventManager.triggerCallbacks('new_player_joined', {
        'room_id': roomId,
        'joined_player': joinedPlayer,
        'game_state': gameState,
        'timestamp': timestamp,
      });
      
      // 🎣 Trigger websocket_new_player_joined hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_new_player_joined hook");
      HooksManager().triggerHookWithData('websocket_new_player_joined', {
        'status': 'player_joined',
        'room_id': roomId,
        'joined_player': joinedPlayer,
        'game_state': gameState,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ New player joined handled successfully");
    } catch (e) {
      _log.error("❌ Error handling new player joined: $e");
    }
  }

  /// Handle joined games event
  void handleJoinedGames(dynamic data) {
    _log.info("🔧 [HANDLER-JOINED_GAMES] Handling joined games event");
    
    try {
      // Validate the data structure
      if (data is! Map<String, dynamic>) {
        _log.error("❌ Invalid data format for joined_games event");
        return;
      }
      
      final userId = data['user_id']?.toString() ?? '';
      final sessionId = data['session_id']?.toString() ?? '';
      final games = data['games'] as List<dynamic>? ?? [];
      final totalGames = data['total_games'] ?? 0;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info("🎮 [JOINED_GAMES] User: $userId, Session: $sessionId, Total games: $totalGames");
      
      // Note: State updates are handled by Recall module via hooks
      
      // Trigger event callbacks for game management
      _eventManager.triggerCallbacks('joined_games', {
        'user_id': userId,
        'session_id': sessionId,
        'games': games,
        'total_games': totalGames,
        'timestamp': timestamp,
      });
      
      // 🎣 Trigger websocket_joined_games hook for other modules
      _log.info("🎣 [HOOK] Triggering websocket_joined_games hook");
      HooksManager().triggerHookWithData('websocket_joined_games', {
        'status': 'updated',
        'user_id': userId,
        'session_id': sessionId,
        'games': games,
        'total_games': totalGames,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _log.info("✅ Joined games handled successfully");
    } catch (e) {
      _log.error("❌ Error handling joined games: $e");
    }
  }

  /// Handle message event
  void handleMessage(dynamic data) {
    _log.info("🔧 [HANDLER-MESSAGE] Handling message event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final message = data['message'] ?? '';
      final sender = data['sender'] ?? 'unknown';
      
      _log.info("✅ Message handled successfully");
    } catch (e) {
      _log.error("❌ Error handling message: $e");
    }
  }

  /// Handle error events
  void handleError(dynamic data) {
    _log.info("🔧 [HANDLER-ERROR] Handling error event");
    
    try {
      // Log the error event
      _log.error("🚨 Error event received: $data");
      
      _log.info("✅ Error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling error event: $e");
    }
  }



  /// Handle unified event (for custom events)
  void handleUnifiedEvent(String eventName, dynamic data) {
    _log.info("🔧 [HANDLER-UNIFIED] Handling unified event: $eventName");
    
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
        default:
          _log.info("⚠️ Unknown event type: $eventName");
          break;
      }
    } catch (e) {
      _log.error("❌ Error in unified event handler: $e");
    }
  }
} 