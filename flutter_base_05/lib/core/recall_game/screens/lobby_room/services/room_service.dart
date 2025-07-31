import 'dart:async';
import '../../../../../tools/logging/logger.dart';
import '../../../../managers/websockets/websocket_manager.dart';
import '../../../../managers/websockets/ws_event_manager.dart';
import '../../../../managers/state_manager.dart';

class RoomService {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  final StateManager _stateManager = StateManager();

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
        
        // Refresh public rooms to get the latest list from backend
        if (roomSettings['permission'] == 'public') {
          await _refreshPublicRooms();
        }
        
        return newRoom;
      } else {
        throw Exception(result?['error'] ?? 'Failed to create room');
      }
      
    } catch (e) {
      _logger.error("Error creating room: $e");
      throw Exception('Failed to create room: $e');
    }
  }

  Future<void> _refreshPublicRooms() async {
    try {
      final rooms = await loadPublicRooms();
      
      // Update StateManager with refreshed public rooms
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
      final updatedState = {
        ...currentState,
        'rooms': rooms,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      _stateManager.updateModuleState("recall_game", updatedState);
      
      _logger.info("📊 Refreshed public rooms list");
    } catch (e) {
      _logger.error("Error refreshing public rooms: $e");
    }
  }

  void _updateRoomState(Map<String, dynamic> roomData) {
    // Get current room state
    final currentRoomState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    // Get current lists
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
    
    // Update with new room data
    final updatedState = {
      ...currentRoomState,
      'currentRoom': roomData,
      'currentRoomId': roomData['room_id'],
      'isInRoom': true,
      'myRooms': updatedMyRooms,
      'rooms': updatedPublicRooms,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update StateManager - this will trigger StateManager provider notifications
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
      // Check if connected before leaving room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot leave room: WebSocket not connected");
        throw Exception('Cannot leave room: WebSocket not connected');
      }
      
      _logger.info("🚪 Leaving room: $roomId");
      
      // Create a completer to wait for the server response
      final completer = Completer<Map<String, dynamic>>();
      
      // Listen for the success event
      _wsEventManager.onEvent('leave_room_success', (data) {
        _logger.info("📨 Received leave_room_success event: $data");
        completer.complete({'success': true, 'data': data});
      });
      
      // Listen for the error event
      _wsEventManager.onEvent('leave_room_error', (data) {
        _logger.error("📨 Received leave_room_error event: $data");
        completer.complete({'success': false, 'error': data['error']});
      });
      
      // Send leave room request
      final result = await _wsEventManager.leaveRoom(roomId);
      
      // If the request was sent successfully, wait for server confirmation
      if (result['pending'] != null) {
        // Wait for server confirmation with timeout
        final response = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _logger.warning("⚠️ Timeout waiting for leave room response");
            return {'success': false, 'error': 'Timeout waiting for server response'};
          },
        );
        
        if (response['success'] == true) {
          // Update recall_game state to reflect leaving the room
          _updateLeaveRoomState();
          _logger.info("✅ Successfully left room: $roomId");
        } else {
          throw Exception(response['error'] ?? 'Failed to leave room');
        }
      } else if (result['error'] != null) {
        throw Exception(result['error']);
      } else {
        throw Exception('Unexpected response from leave room request');
      }
      
    } catch (e) {
      _logger.error("Error leaving room: $e");
      throw Exception('Failed to leave room: $e');
    } finally {
      // Clean up event listeners
      _wsEventManager.offEvent('leave_room_success', (data) {});
      _wsEventManager.offEvent('leave_room_error', (data) {});
    }
  }

  void _updateLeaveRoomState() {
    // Get current room state
    final currentRoomState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    // Get current lists
    final currentMyRooms = (currentRoomState['myRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final currentPublicRooms = (currentRoomState['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Update state to reflect leaving the room
    final updatedState = {
      ...currentRoomState,
      'currentRoom': null,
      'currentRoomId': null,
      'isInRoom': false,
      'myRooms': currentMyRooms, // Keep my rooms list
      'rooms': currentPublicRooms, // Keep public rooms list
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update StateManager
    _stateManager.updateModuleState("recall_game", updatedState);
    _logger.info("📊 Updated room state after leaving room");
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

    // Listen for leave room events
    _wsEventManager.onEvent('leave_room_success', (data) {
      _logger.info("📨 Received leave_room_success event: $data");
    });

    _wsEventManager.onEvent('leave_room_error', (data) {
      _logger.error("📨 Received leave_room_error event: $data");
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
    _wsEventManager.offEvent('room_joined', (data) {});
    _wsEventManager.offEvent('join_room_success', (data) {});
    _wsEventManager.offEvent('create_room_success', (data) {});
    _wsEventManager.offEvent('room_created', (data) {});
    _wsEventManager.offEvent('leave_room_success', (data) {});
    _wsEventManager.offEvent('leave_room_error', (data) {});
    _wsEventManager.offEvent('error', (data) {});
  }

  bool get isConnected => _websocketManager.isConnected;
  bool get isConnecting => _websocketManager.isConnecting;
} 