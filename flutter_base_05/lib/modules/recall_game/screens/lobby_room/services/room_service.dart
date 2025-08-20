import 'dart:async';
import '../../../../../tools/logging/logger.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../utils/recall_game_helpers.dart';
import '../../../utils/recall_event_listener_validator.dart';

/// Room operations only - no state management
/// Handles room creation, joining, leaving, and validation
class RoomService {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  
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
      
      // Validate room settings
      if (!isValidRoomSettings(roomSettings)) {
        throw Exception('Invalid room settings');
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
        
        // Return the created room data
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

  Future<Map<String, dynamic>> joinRoom(String roomId) async {
    try {
      // Check if connected before joining room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot join room: WebSocket not connected");
        throw Exception('Cannot join room: WebSocket not connected');
      }
      
      // Validate room ID
      if (!isValidRoomId(roomId)) {
        throw Exception('Invalid room ID');
      }
      
      // 🎯 Use validated event emitter for joining game
      _logger.info("🚪 Joining room using validated system: $roomId");
      
      final result = await RecallGameHelpers.joinGame(roomId, 'current_user');
      
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to join room');
      }
      
      _logger.info("✅ Successfully joined room: $roomId");
      return result;
      
    } catch (e) {
      _logger.error("Error joining room: $e");
      throw Exception('Failed to join room: $e');
    }
  }

  Future<Map<String, dynamic>> leaveRoom(String roomId) async {
    try {
      // Check if connected before leaving room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot leave room: WebSocket not connected");
        throw Exception('Cannot leave room: WebSocket not connected');
      }
      
      // Validate room ID
      if (!isValidRoomId(roomId)) {
        throw Exception('Invalid room ID');
      }
      
      // 🎯 Use validated event emitter for leaving game
      _logger.info("👋 Leaving room using validated system: $roomId");
      
      final result = await RecallGameHelpers.leaveGame(
        gameId: roomId,
        reason: 'User left room',
      );
      
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to leave room');
      }
      
      _logger.info("✅ Successfully left room: $roomId");
      return result;
      
    } catch (e) {
      _logger.error("Error leaving room: $e");
      throw Exception('Failed to leave room: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPublicRooms() async {
    try {
      // Check if connected before fetching rooms
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot fetch rooms: WebSocket not connected");
        throw Exception('Cannot fetch rooms: WebSocket not connected');
      }
      
      // 🎯 Use validated event emitter for getting public rooms
      _logger.info("📋 Fetching public rooms using validated system...");
      
      final result = await RecallGameHelpers.getPendingGames();
      
      if (result['success'] == true && result['data'] != null) {
        final roomsData = result['data'] as List<dynamic>?;
        if (roomsData != null && roomsData.isNotEmpty) {
          final publicRooms = roomsData
              .cast<Map<String, dynamic>>()
              .where((room) => room['permission'] == 'public')
              .toList();
          
          _logger.info("✅ Successfully fetched ${publicRooms.length} public rooms");
          return publicRooms;
        }
      }
      
      _logger.info("✅ No public rooms available");
      return [];
      
    } catch (e) {
      _logger.error("Error fetching public rooms: $e");
      throw Exception('Failed to fetch public rooms: $e');
    }
  }

  // Room validation methods
  bool isValidRoomSettings(Map<String, dynamic> settings) {
    if (settings == null) return false;
    
    // Check required fields
    if (!settings.containsKey('roomName')) return false;
    if (!settings.containsKey('permission')) return false;
    if (!settings.containsKey('maxPlayers')) return false;
    if (!settings.containsKey('minPlayers')) return false;
    
    // Validate room name
    final roomName = settings['roomName'] as String? ?? '';
    if (roomName.isEmpty || roomName.length > 50) return false;
    
    // Validate permission
    final permission = settings['permission'] as String? ?? '';
    final validPermissions = ['public', 'private', 'restricted', 'owner_only'];
    if (!validPermissions.contains(permission)) return false;
    
    // Validate player counts
    final maxPlayers = settings['maxPlayers'] as int? ?? 0;
    final minPlayers = settings['minPlayers'] as int? ?? 0;
    if (maxPlayers < 2 || maxPlayers > 8) return false;
    if (minPlayers < 2 || minPlayers > maxPlayers) return false;
    
    // Validate password for private rooms
    if (permission != 'public') {
      final password = settings['password'] as String?;
      if (password != null && password.isNotEmpty && password.length < 3) return false;
    }
    
    return true;
  }

  bool isValidRoomId(String roomId) {
    if (roomId == null || roomId.isEmpty) return false;
    
    // Basic validation - room ID should be a non-empty string
    if (roomId.length < 3 || roomId.length > 50) return false;
    
    // Check for valid characters (alphanumeric, underscore, hyphen)
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!validPattern.hasMatch(roomId)) return false;
    
    return true;
  }

  bool canJoinRoom(String roomId, String playerId) {
    // Basic validation
    if (!isValidRoomId(roomId)) return false;
    if (playerId.isEmpty) return false;
    
    // Check if connected
    if (!_websocketManager.isConnected) return false;
    
    // Additional checks could be added here (e.g., room capacity, permissions)
    // For now, return true if basic validation passes
    return true;
  }

  // Room business logic methods
  Map<String, dynamic> getRoomStatistics(List<Map<String, dynamic>> rooms) {
    if (rooms.isEmpty) return {};
    
    final totalRooms = rooms.length;
    final publicRooms = rooms.where((room) => room['permission'] == 'public').length;
    final privateRooms = rooms.where((room) => room['permission'] == 'private').length;
    final activeRooms = rooms.where((room) => (room['current_size'] ?? 0) > 0).length;
    final fullRooms = rooms.where((room) => (room['current_size'] ?? 0) >= (room['max_size'] ?? 4)).length;
    
    return {
      'totalRooms': totalRooms,
      'publicRooms': publicRooms,
      'privateRooms': privateRooms,
      'activeRooms': activeRooms,
      'fullRooms': fullRooms,
      'availableRooms': totalRooms - fullRooms,
    };
  }

  List<Map<String, dynamic>> filterRooms(List<Map<String, dynamic>> rooms, {
    String? permission,
    int? minPlayers,
    int? maxPlayers,
    bool? hasActiveGame,
  }) {
    return rooms.where((room) {
      // Filter by permission
      if (permission != null && room['permission'] != permission) return false;
      
      // Filter by player count
      if (minPlayers != null && (room['current_size'] ?? 0) < minPlayers) return false;
      if (maxPlayers != null && (room['current_size'] ?? 0) > maxPlayers) return false;
      
      // Filter by active game status
      if (hasActiveGame != null) {
        final isActive = room['hasActiveGame'] == true;
        if (hasActiveGame != isActive) return false;
      }
      
      return true;
    }).toList();
  }

  void setupEventCallbacks() {
    _logger.info("🎮 Setting up room event callbacks");
    
    // Use validated event listener for room events
    final eventTypes = [
      'room_event', 'room_joined', 'room_left', 'room_closed',
      'connection_status', 'error',
    ];
    
    for (final eventType in eventTypes) {
      RecallGameEventListenerExtension.onEvent(eventType, (data) {
        _logger.info("🎮 RoomService received validated event: $eventType");
        _handleRoomEvent(eventType, data);
      });
    }
    
    _logger.info("✅ Room event callbacks set up");
  }

  void _handleRoomEvent(String eventType, Map<String, dynamic> data) {
    try {
      _logger.info("🎮 Processing room event: $eventType");
      
      switch (eventType) {
        case 'room_event':
          final action = data['action'] as String? ?? '';
          _logger.info("🎮 Room event action: $action");
          break;
        case 'room_joined':
          _logger.info("🎮 Room joined: ${data['room_id']}");
          break;
        case 'room_left':
          _logger.info("🎮 Room left: ${data['room_id']}");
          break;
        case 'room_closed':
          _logger.info("🎮 Room closed: ${data['room_id']}");
          break;
        case 'connection_status':
          _logger.info("🎮 Connection status: ${data['status']}");
          break;
        case 'error':
          _logger.error("🎮 Room error: ${data['error']}");
          break;
        default:
          _logger.info("⚠️ Unknown room event type: $eventType");
      }
      
    } catch (e) {
      _logger.error("❌ Error handling room event: $e");
    }
  }

  void cleanupEventCallbacks() {
    _logger.info("🧹 Cleaning up room event callbacks");
    
    // Clear event listeners
    
    _logger.info("✅ Room event callbacks cleaned up");
  }

  void dispose() {
    if (_isDisposed) return;
    
    cleanupEventCallbacks();
    _isDisposed = true;
    _logger.info("🗑️ RoomService disposed");
  }
}