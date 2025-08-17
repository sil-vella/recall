import 'dart:async';
import '../../../../../tools/logging/logger.dart';
import '../../../../managers/websockets/websocket_manager.dart';
import '../../../../managers/websockets/ws_event_manager.dart';
import '../../../../managers/state_manager.dart';
import '../../../utils/recall_game_helpers.dart';
import '../../../utils/recall_event_listener_validator.dart';

class RoomService {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  final StateManager _stateManager = StateManager();
  
  // Store event listener references for proper cleanup
  final List<Function> _eventListeners = [];
  bool _isDisposed = false;

  Future<void> initializeWebSocket() async {
    try {
      // Check if WebSocketManager is already connected
      if (_websocketManager.isConnected) {
        _logger.info("✅ WebSocket already connected");
        return;
      }
      
      // Check if we're already in the process of connecting
      if (_websocketManager.isConnecting) {
        _logger.info("🔄 WebSocket is already connecting, waiting...");
        return;
      }
      
      // Only try to connect if no existing connection
      _logger.info("🔄 No existing connection found, connecting to WebSocket server...");
      final success = await _websocketManager.connect();
      
      if (success) {
        _logger.info("✅ WebSocket connected successfully");
      } else {
        _logger.error("❌ WebSocket connection failed");
        _logger.info("ℹ️ Assuming WebSocket is already connected from another screen");
      }
    } catch (e) {
      _logger.error("❌ Error initializing WebSocket: $e");
      _logger.info("ℹ️ Assuming WebSocket is already connected from another screen");
    }
  }

  Future<Map<String, dynamic>> createRoom(Map<String, dynamic> roomSettings) async {
    try {
      // Check if connected before creating room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot create room: WebSocket not connected");
        throw Exception('Cannot create room: WebSocket not connected');
      }
      
      // 🎯 Use validated event emitter for room creation
      _logger.info("🏠 Creating room using validated system...");
      
      final result = await RecallGameHelpers.createRoom(
        roomName: roomSettings['roomName'],
        permission: roomSettings['permission'],
        maxPlayers: roomSettings['maxPlayers'],
        minPlayers: roomSettings['minPlayers'],
        gameType: roomSettings['gameType'] ?? 'classic',
        turnTimeLimit: roomSettings['turnTimeLimit'] ?? 30,
        autoStart: roomSettings['autoStart'] ?? false,
        password: roomSettings['permission'] != 'public' && roomSettings['password']?.isNotEmpty == true
            ? roomSettings['password']
            : null,
      );
      
      _logger.info("🏠 Validated create room result: $result");
      
      if (result['success'] == true) {
        // Handle different response formats from backend
        final createdRoomData = result['data'] as Map<String, dynamic>?;
        
        // Generate room data based on what we have
        final roomId = createdRoomData?['room_id'] ?? 'room_${DateTime.now().millisecondsSinceEpoch}';
        
        // Update StateManager with the new room
        final newRoom = {
          'room_id': roomId,
          'owner_id': 'current_user',
          'permission': roomSettings['permission'],
          'current_size': createdRoomData?['current_size'] ?? 1,
          'max_size': roomSettings['maxPlayers'],
          'min_size': roomSettings['minPlayers'],
          'created_at': DateTime.now().toIso8601String(),
          'room_name': roomSettings['roomName'],
          'game_type': roomSettings['gameType'],
          'turn_time_limit': roomSettings['turnTimeLimit'],
          'auto_start': roomSettings['autoStart'],
        };
        
        // First update room ownership and current room info
        _updateRoomState(newRoom);
        
        // Register the new game in our tracking system
        RecallGameHelpers.registerActiveGame(
          gameId: roomId,
          gamePhase: 'waiting',
          gameStatus: 'inactive',
          playerCount: newRoom['current_size'] ?? 1,
          roomName: newRoom['room_name'],
          ownerId: newRoom['owner_id'],
          additionalData: {
            'permission': newRoom['permission'],
            'maxPlayers': newRoom['max_size'],
            'minPlayers': newRoom['min_size'],
            'gameType': newRoom['game_type'],
            'turnTimeLimit': newRoom['turn_time_limit'],
            'autoStart': newRoom['auto_start'],
          },
        );
        
        // Then update the user's created rooms list (not public rooms)
        final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
        final currentMyCreatedRooms = (currentState['myCreatedRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        
        // Add to myCreatedRooms if not already there
        if (!currentMyCreatedRooms.any((room) => room['room_id'] == roomId)) {
          RecallGameHelpers.updateUIState({
            'myCreatedRooms': [...currentMyCreatedRooms, newRoom],
          });
        }
        
        _logger.info("✅ Room created successfully: ${newRoom['room_id']}");
        return newRoom;
      } else {
        throw Exception(result['error'] ?? 'Failed to create room');
      }
    } catch (e) {
      _logger.error("Error creating room: $e");
      throw Exception('Failed to create room: $e');
    }
  }

  void _updateRoomState(Map<String, dynamic> roomData) {
    // 🎯 Use validated state updater for room ownership
    _logger.info("📊 Updating room state using validated system...");
    
    RecallGameHelpers.setupRoomOwnership(
      roomId: roomData['room_id'],
      roomName: roomData['room_name'],
      permission: roomData['permission'],
      currentSize: roomData['current_size'] ?? 1,
      maxSize: roomData['max_size'] ?? 4,
      minSize: roomData['min_size'] ?? 2,
    );
    
    // Update room lists using validated state updater
    _logger.info("📊 Updating room lists using validated system...");
    
    // Update current room
    RecallGameHelpers.updateRoomInfo(
      roomId: roomData['room_id'],
      roomName: roomData['room_name'],
      permission: roomData['permission'],
      currentSize: roomData['current_size'] ?? 1,
      maxSize: roomData['max_size'] ?? 4,
      minSize: roomData['min_size'] ?? 2,
      isInRoom: true,
    );
    
    // Update myCreatedRooms list
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final currentMyCreatedRooms = (currentState['myCreatedRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Add to myCreatedRooms if not already there
    if (!currentMyCreatedRooms.any((room) => room['room_id'] == roomData['room_id'])) {
      RecallGameHelpers.updateUIState({
        'myCreatedRooms': [...currentMyCreatedRooms, roomData],
      });
    }
    
    _logger.info("📊 Room state updated using validated system");
  }

  Future<void> joinRoom(String roomId) async {
    try {
      // Check if connected before joining room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot join room: WebSocket not connected");
        throw Exception('Cannot join room: WebSocket not connected');
      }
      
      // 🎯 Use validated event emitter for joining game
      _logger.info("🚪 Joining room using validated system: $roomId");
      
      final result = await RecallGameHelpers.joinGame(roomId, 'current_user');
      
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to join room');
      }
      
      // The WebSocket system will handle the state updates automatically
      // We just need to update the Recall game state based on the WebSocket state
      _syncWithWebSocketState();
      
    } catch (e) {
      _logger.error("Error joining room: $e");
      throw Exception('Failed to join room: $e');
    }
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      // Check if connected before leaving room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot leave room: WebSocket not connected");
        throw Exception('Cannot leave room: WebSocket not connected');
      }
      
      // 🎯 Use validated event emitter for leaving game
      _logger.info("🚪 Leaving room using validated system: $roomId");
      
      final result = await RecallGameHelpers.leaveGame(
        gameId: roomId,
        reason: 'User left room',
      );
      
      if (result['pending'] != null || result['success'] != null) {
        // The WebSocket system will handle the state updates automatically
        // We just need to update the Recall game state based on the WebSocket state
        _syncWithWebSocketState();
      } else {
        throw Exception(result['error'] ?? 'Failed to leave room');
      }
      
    } catch (e) {
      _logger.error("Error leaving room: $e");
      throw Exception('Failed to leave room: $e');
    }
  }

  void _syncWithWebSocketState() {
    // Get the current WebSocket state
    final websocketState = _stateManager.getModuleState<Map<String, dynamic>>("websocket") ?? {};
    final currentRoomId = websocketState['currentRoomId'];
    final currentRoomInfo = websocketState['currentRoomInfo'];
    
    // 🎯 Use validated state updater for room sync
    _logger.info("📊 Syncing with WebSocket state using validated system...");
    
    if (currentRoomId != null) {
      // Update room info using validated helpers
      RecallGameHelpers.updateRoomInfo(
        roomId: currentRoomId,
        roomName: currentRoomInfo?['room_name'],
        permission: currentRoomInfo?['permission'] ?? 'public',
        currentSize: currentRoomInfo?['current_size'] ?? 0,
        maxSize: currentRoomInfo?['max_size'] ?? 4,
        minSize: currentRoomInfo?['min_size'] ?? 2,
        isInRoom: true,
      );
      
      // When joining existing room (not creating), user is not owner
      RecallGameHelpers.updateRoomInfo(isInRoom: true);
      
      // Update current room using validated state updater
      RecallGameHelpers.updateRoomInfo(
        roomId: currentRoomId,
        roomName: currentRoomInfo?['room_name'],
        permission: currentRoomInfo?['permission'] ?? 'public',
        currentSize: currentRoomInfo?['current_size'] ?? 0,
        maxSize: currentRoomInfo?['max_size'] ?? 4,
        minSize: currentRoomInfo?['min_size'] ?? 2,
        isInRoom: true,
      );
    } else {
      // No room - clear room state
      RecallGameHelpers.clearRoomState();
    }
    
    _logger.info("📊 Synced Recall game state with WebSocket state using validated system");
  }

  void setupEventCallbacks(Function(String, String) onRoomEvent, Function(String) onError) {
    // Clear any existing listeners first
    cleanupEventCallbacks();
    
    // 🎯 Use validated event listener system for all room events
    final eventTypes = [
      'room', 'room_joined', 'join_room_success', 'create_room_success',
      'room_created', 'leave_room_success', 'leave_room_error', 'error'
    ];
    
    for (final eventType in eventTypes) {
      RecallGameEventListenerExtension.onEvent(eventType, (data) {
        if (_isDisposed) return; // Prevent execution after disposal
        
        _logger.info("📨 Received validated $eventType event: $data");
        
        // Sync with WebSocket state after room events
        _syncWithWebSocketState();
        
        // Handle specific event types
        switch (eventType) {
          case 'room':
            final action = data['action'] as String? ?? '';
            final roomId = data['room_id'] as String? ?? '';
            if (action.isNotEmpty && roomId.isNotEmpty) {
              onRoomEvent(action, roomId);
            }
            break;
            
          case 'room_joined':
          case 'join_room_success':
            final roomId = data['room_id'] as String? ?? '';
            if (roomId.isNotEmpty) {
              onRoomEvent('joined', roomId);
            }
            break;
            
          case 'create_room_success':
          case 'room_created':
            final roomId = data['room_id'] as String? ?? '';
            if (roomId.isNotEmpty) {
              onRoomEvent('created', roomId);
            }
            break;
            
          case 'leave_room_success':
            final roomId = data['room_id'] as String? ?? '';
            if (roomId.isNotEmpty) {
              onRoomEvent('left', roomId);
            }
            break;
            
          case 'leave_room_error':
            final error = data['error'] as String? ?? 'Unknown error';
            onError(error);
            break;
            
          case 'error':
            final error = data['error'] as String? ?? 'Unknown error';
            onError(error);
            break;
        }
      });
    }
    
    _logger.info("✅ Room service event callbacks set up using validated system");
  }

  void cleanupEventCallbacks() {
    // Mark as disposed to prevent callback execution
    _isDisposed = true;
    
    // Clear the event listeners list
    _eventListeners.clear();
    
    _logger.info("🗑️ Room service event callbacks cleaned up");
  }

  bool get isConnected => _websocketManager.isConnected;
  bool get isConnecting => _websocketManager.isConnecting;
}