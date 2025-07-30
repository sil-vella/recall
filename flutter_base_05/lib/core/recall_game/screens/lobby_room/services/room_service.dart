import 'dart:async';
import '../../../../managers/websockets/websocket_manager.dart';
import '../../../../managers/websockets/ws_event_manager.dart';
import '../../../../managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

class RoomService {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  final StateManager _stateManager = StateManager();
  final Logger _logger = Logger();

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
      // For now, we'll simulate some rooms since we need to implement room discovery
      // In a real implementation, this would come from WebSocket events
      await Future.delayed(const Duration(seconds: 1));
      
      return [
        {
          'room_id': 'demo-room-1',
          'owner_id': 'user123',
          'permission': 'public',
          'current_size': 2,
          'max_size': 10,
          'created_at': '2024-01-15T10:30:00Z'
        },
        {
          'room_id': 'demo-room-2', 
          'owner_id': 'user456',
          'permission': 'public',
          'current_size': 1,
          'max_size': 10,
          'created_at': '2024-01-15T11:00:00Z'
        }
      ];
    } catch (e) {
      _logger.error("Error loading public rooms: $e");
      throw Exception('Failed to load public rooms: $e');
    }
  }

  Future<Map<String, dynamic>> createRoom(Map<String, dynamic> roomSettings) async {
    try {
      // Check if connected before creating room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot create room: WebSocket not connected");
        throw Exception('Cannot create room: WebSocket not connected');
      }
      
      // Prepare room data
      Map<String, dynamic> roomData = {
        'room_name': roomSettings['roomName'],
        'permission': roomSettings['permission'],
        'max_players': roomSettings['maxPlayers'],
        'min_players': roomSettings['minPlayers'],
        'turn_time_limit': roomSettings['turnTimeLimit'],
        'auto_start': roomSettings['autoStart'],
        'game_type': roomSettings['gameType'],
      };

      // Add password for private rooms
      if (roomSettings['permission'] != 'public' && roomSettings['password']?.isNotEmpty == true) {
        roomData['password'] = roomSettings['password'];
      }

      // Create room via WebSocket manager
      _logger.info("🏠 Attempting to create room with data: $roomData");
      
      final result = await _wsEventManager.createRoom('current_user', roomData);
      
      _logger.info("🏠 Create room result: $result");
      
      if (result?['success'] != null && result!['success'].toString().contains('successfully')) {
        // Use the actual room data from the server response
        final createdRoomData = result!['data'] as Map<String, dynamic>;
        
        // Update StateManager with the new room
        final newRoom = {
          'room_id': createdRoomData['room_id'],
          'owner_id': 'current_user',
          'permission': roomSettings['permission'],
          'current_size': createdRoomData['current_size'] ?? 1,
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
        
        return newRoom;
      } else {
        throw Exception(result?['error'] ?? 'Failed to create room');
      }
      
    } catch (e) {
      _logger.error("Error creating room: $e");
      throw Exception('Failed to create room: $e');
    }
  }

  void _updateRoomState(Map<String, dynamic> roomData) {
    // Get current room state
    final currentRoomState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    // Update with new room data
    final updatedState = {
      ...currentRoomState,
      'currentRoom': roomData,
      'currentRoomId': roomData['room_id'],
      'isInRoom': true,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update StateManager
    _stateManager.updateModuleState("recall_game", updatedState);
    _logger.info("📊 Updated room state in StateManager");
  }

  Future<void> joinRoom(String roomId) async {
    try {
      // Check if connected before joining room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot join room: WebSocket not connected");
        throw Exception('Cannot join room: WebSocket not connected');
      }
      
      // Join room via WebSocket event manager
      _logger.info("🚪 Joining room: $roomId");
      final result = await _wsEventManager.joinRoom(roomId, 'current_user');
      
      if (result?['success'] != true) {
        throw Exception(result?['error'] ?? 'Failed to join room');
      }
      
    } catch (e) {
      _logger.error("Error joining room: $e");
      throw Exception('Failed to join room: $e');
    }
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      // Leave room via WebSocket event manager
      _logger.info("🚪 Leaving room: $roomId");
      final result = await _wsEventManager.leaveRoom(roomId);
      
      if (result?['success'] != true) {
        throw Exception(result?['error'] ?? 'Failed to leave room');
      }
      
    } catch (e) {
      _logger.error("Error leaving room: $e");
      throw Exception('Failed to leave room: $e');
    }
  }

  void setupEventCallbacks(Function(String, String) onRoomEvent, Function(String) onError) {
    // Listen for room events
    _wsEventManager.onEvent('room', (data) {
      final action = data['action'];
      final roomId = data['roomId'];
      
      _logger.info("📨 Received room event: action=$action, roomId=$roomId");
      onRoomEvent(action, roomId);
    });

    // Listen for specific room events for better debugging
    _wsEventManager.onEvent('room_joined', (data) {
      _logger.info("📨 Received room_joined event: $data");
    });

    _wsEventManager.onEvent('join_room_success', (data) {
      _logger.info("📨 Received join_room_success event: $data");
    });

    _wsEventManager.onEvent('create_room_success', (data) {
      _logger.info("📨 Received create_room_success event: $data");
    });

    _wsEventManager.onEvent('room_created', (data) {
      _logger.info("📨 Received room_created event: $data");
    });

    // Listen for error events
    _wsEventManager.onEvent('error', (data) {
      final error = data['error'];
      _logger.error("📨 Received error event: $error");
      onError(error);
    });
  }

  void cleanupEventCallbacks() {
    _wsEventManager.offEvent('room', (data) {});
    _wsEventManager.offEvent('error', (data) {});
  }

  bool get isConnected => _websocketManager.isConnected;
  bool get isConnecting => _websocketManager.isConnecting;
} 