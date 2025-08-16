import 'dart:async';
import '../../../../../tools/logging/logger.dart';
import '../../../../managers/websockets/websocket_manager.dart';
import '../../../../managers/websockets/ws_event_manager.dart';
import '../../../../managers/state_manager.dart';
import '../../../utils/recall_game_helpers.dart';

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

  Future<List<Map<String, dynamic>>> loadPublicRooms() async {
    try {
      // Check if connected before loading rooms
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot load rooms: WebSocket not connected");
        throw Exception('Cannot load rooms: WebSocket not connected');
      }
      
      _logger.info("🏠 Loading public rooms...");
      
      // Create a completer to wait for the response
      final completer = Completer<List<Map<String, dynamic>>>();
      
      // Listen for the response event
      _wsEventManager.onEvent('get_public_rooms_success', (data) {
        _logger.info("📨 Received get_public_rooms_success event: $data");
        
        if (data['success'] == true) {
          final rooms = (data['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          _logger.info("📊 Loaded ${rooms.length} public rooms");
          completer.complete(rooms);
        } else {
          completer.complete([]);
        }
      });
      
      // Listen for error event
      _wsEventManager.onEvent('get_public_rooms_error', (data) {
        _logger.error("📨 Received get_public_rooms_error event: $data");
        completer.complete([]);
      });
      
      // Request public rooms from the backend via WebSocket
      final result = await _websocketManager.sendMessage('lobby', 'get_public_rooms');
      
      _logger.info("🏠 Load public rooms result: $result");
      
      // Wait for the response with timeout
      final rooms = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _logger.warning("⚠️ Timeout waiting for public rooms response");
          return <Map<String, dynamic>>[];
        },
      );
      
      return rooms;
      
    } catch (e) {
      _logger.error("Error loading public rooms: $e");
      // Return empty list instead of throwing to avoid breaking the UI
      return [];
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
        
        // Update StateManager
        _updateRoomState(newRoom);
        
        // Refresh public rooms to get the latest list from backend
        if (roomSettings['permission'] == 'public') {
          try {
            await _refreshPublicRooms();
            _logger.info("🔄 Public rooms refreshed after room creation");
          } catch (e) {
            _logger.warning("⚠️ Failed to refresh public rooms after creation: $e");
          }
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

  Future<void> _refreshPublicRooms() async {
    try {
      final fetchedRooms = await loadPublicRooms();

      // Merge with existing local rooms to avoid flicker/removal when backend
      // hasn't propagated the newly created room yet.
      // Prefer server values when ids collide; keep local-only rooms.
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
      final existing = (currentState['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

      final Map<String, Map<String, dynamic>> byId = {};
      for (final room in existing) {
        final id = room['room_id']?.toString();
        if (id != null) byId[id] = room;
      }
      for (final room in fetchedRooms) {
        final id = room['room_id']?.toString();
        if (id != null) byId[id] = room; // server wins on conflict
      }

      final mergedRooms = byId.values.toList();

      final updatedState = {
        ...currentState,
        'rooms': mergedRooms,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      _stateManager.updateModuleState("recall_game", updatedState);
      
      _logger.info("📊 Refreshed public rooms list");
    } catch (e) {
      _logger.error("Error refreshing public rooms: $e");
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
    
    // Update room lists (these are not part of our validated schema yet, so use direct StateManager)
    final currentRoomState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final currentMyRooms = (currentRoomState['myRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final currentPublicRooms = (currentRoomState['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Add the new room to myRooms if it's not already there
    final roomExistsInMyRooms = currentMyRooms.any((room) => room['room_id'] == roomData['room_id']);
    final updatedMyRooms = roomExistsInMyRooms ? currentMyRooms : [...currentMyRooms, roomData];
    
    // Add the new room to public rooms if it's public and not already there
    List<Map<String, dynamic>> updatedPublicRooms = currentPublicRooms;
    if (roomData['permission'] == 'public') {
      final roomExistsInPublicRooms = currentPublicRooms.any((room) => room['room_id'] == roomData['room_id']);
      if (!roomExistsInPublicRooms) {
        updatedPublicRooms = [...currentPublicRooms, roomData];
      }
    }
    
    // Update room lists using direct StateManager (TODO: Add to validated schema later)
    final roomListUpdates = {
      'currentRoom': roomData,
      'myRooms': updatedMyRooms,
      'rooms': updatedPublicRooms,
    };
    
    _stateManager.updateModuleState("recall_game", {
      ...currentRoomState,
      ...roomListUpdates,
    });
    
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
      
      // Update room lists using direct StateManager (TODO: Add to validated schema later)
      final currentRecallState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
      _stateManager.updateModuleState("recall_game", {
        ...currentRecallState,
        'currentRoom': currentRoomInfo,
      });
    } else {
      // No room - clear room state
      RecallGameHelpers.clearRoomState();
    }
    
    _logger.info("📊 Synced Recall game state with WebSocket state using validated system");
  }

  void setupEventCallbacks(Function(String, String) onRoomEvent, Function(String) onError) {
    // Clear any existing listeners first
    cleanupEventCallbacks();
    
    // Listen for room events from the WebSocket system
    final roomEventListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      
      final action = data['action'];
      final roomId = data['roomId'];
      
      _logger.info("📨 Received room event: action=$action, roomId=$roomId");
      
      // Sync with WebSocket state after room events
      _syncWithWebSocketState();
      
      onRoomEvent(action, roomId);
    };
    _wsEventManager.onEvent('room', roomEventListener);
    _eventListeners.add(roomEventListener);

    // Listen for specific room events for better debugging
    final roomJoinedListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.info("📨 Received room_joined event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('room_joined', roomJoinedListener);
    _eventListeners.add(roomJoinedListener);

    final joinRoomSuccessListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.info("📨 Received join_room_success event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('join_room_success', joinRoomSuccessListener);
    _eventListeners.add(joinRoomSuccessListener);

    final createRoomSuccessListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.info("📨 Received create_room_success event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('create_room_success', createRoomSuccessListener);
    _eventListeners.add(createRoomSuccessListener);

    final roomCreatedListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.info("📨 Received room_created event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('room_created', roomCreatedListener);
    _eventListeners.add(roomCreatedListener);

    // Listen for leave room events
    final leaveRoomSuccessListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.info("📨 Received leave_room_success event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('leave_room_success', leaveRoomSuccessListener);
    _eventListeners.add(leaveRoomSuccessListener);

    final leaveRoomErrorListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      _logger.error("📨 Received leave_room_error event: $data");
      _syncWithWebSocketState();
    };
    _wsEventManager.onEvent('leave_room_error', leaveRoomErrorListener);
    _eventListeners.add(leaveRoomErrorListener);

    // Listen for error events
    final errorListener = (data) {
      if (_isDisposed) return; // Prevent execution after disposal
      final error = data['error'];
      _logger.error("📨 Received error event: $error");
      onError(error);
    };
    _wsEventManager.onEvent('error', errorListener);
    _eventListeners.add(errorListener);
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