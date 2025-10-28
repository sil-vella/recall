class Room {
  final String roomId;
  final String ownerId; // Renamed from creatorId to match Python
  final List<String> sessionIds = [];
  final DateTime createdAt = DateTime.now();
  
  // Room settings (matching Python backend)
  final int maxSize;
  final int minPlayers;
  final String gameType;
  final String permission; // 'public' or 'private'
  final String? password; // for private rooms
  final int turnTimeLimit; // in seconds
  final bool autoStart;
  
  Room({
    required this.roomId,
    required this.ownerId,
    this.maxSize = 8,
    this.minPlayers = 2,
    this.gameType = 'classic',
    this.permission = 'public',
    this.password,
    this.turnTimeLimit = 30,
    this.autoStart = true,
  });
  
  // Getter for current size
  int get currentSize => sessionIds.length;
  
  // Check if room has capacity
  bool get hasCapacity => currentSize < maxSize;
  
  // Check if room meets minimum players
  bool get meetsMinPlayers => currentSize >= minPlayers;
  
  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'owner_id': ownerId, // Changed from creator_id to match Python
      'creator_id': ownerId, // Keep both for compatibility
      'current_size': currentSize,
      'max_size': maxSize,
      'min_players': minPlayers,
      'game_type': gameType,
      'permission': permission,
      'turn_time_limit': turnTimeLimit,
      'auto_start': autoStart,
      'created_at': createdAt.toIso8601String(),
      'player_count': sessionIds.length, // Keep for backward compatibility
    };
  }
}

class RoomManager {
  final Map<String, Room> _rooms = {};
  final Map<String, String> _sessionToRoom = {}; // sessionId -> roomId
  
  // Callback for room closure events
  Function(String roomId, String reason)? onRoomClosed;
  
  String createRoom(String creatorSessionId, String userId, {
    int? maxSize,
    int? minPlayers,
    String? gameType,
    String? permission,
    String? password,
    int? turnTimeLimit,
    bool? autoStart,
  }) {
    final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final room = Room(
      roomId: roomId,
      ownerId: userId,
      maxSize: maxSize ?? 8,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'classic',
      permission: permission ?? 'public',
      password: password,
      turnTimeLimit: turnTimeLimit ?? 30,
      autoStart: autoStart ?? true,
    );
    room.sessionIds.add(creatorSessionId);
    
    _rooms[roomId] = room;
    _sessionToRoom[creatorSessionId] = roomId;
    
    print('🏠 Room created: $roomId by $userId (max: ${room.maxSize}, permission: ${room.permission})');
    return roomId;
  }
  
  bool joinRoom(String roomId, String sessionId, String userId, {String? password}) {
    final room = _rooms[roomId];
    if (room == null) {
      print('❌ Room not found: $roomId');
      return false;
    }
    
    // Check if user is already in room
    if (isUserInRoom(sessionId, roomId)) {
      print('⚠️  User $userId already in room $roomId');
      return false; // Will be handled as "already_joined" in message handler
    }
    
    // Check room capacity
    if (!room.hasCapacity) {
      print('❌ Room $roomId is full (${room.currentSize}/${room.maxSize})');
      return false;
    }
    
    // Validate password for private rooms
    if (!validateRoomPassword(roomId, password)) {
      print('❌ Invalid password for private room $roomId');
      return false;
    }
    
    room.sessionIds.add(sessionId);
    _sessionToRoom[sessionId] = roomId;
    
    print('👤 $userId joined room $roomId (Players: ${room.currentSize}/${room.maxSize})');
    return true;
  }
  
  void leaveRoom(String sessionId) {
    final roomId = _sessionToRoom[sessionId];
    if (roomId == null) return;
    
    final room = _rooms[roomId];
    room?.sessionIds.remove(sessionId);
    _sessionToRoom.remove(sessionId);
    
    print('👋 Session $sessionId left room $roomId');
    
    // Destroy empty rooms
    if (room != null && room.sessionIds.isEmpty) {
      // 🎣 Trigger room_closed hook before cleanup
      onRoomClosed?.call(roomId, 'empty');
      
      _rooms.remove(roomId);
      print('🗑️  Room destroyed: $roomId (empty)');
    }
  }
  
  /// Manually close a room (for TTL expiry, admin action, etc.)
  void closeRoom(String roomId, String reason) {
    final room = _rooms[roomId];
    if (room == null) return;
    
    // 🎣 Trigger room_closed hook before cleanup
    onRoomClosed?.call(roomId, reason);
    
    // Remove all sessions from this room
    for (final sessionId in List.from(room.sessionIds)) {
      _sessionToRoom.remove(sessionId);
    }
    
    // Remove the room
    _rooms.remove(roomId);
    print('🗑️  Room manually closed: $roomId (reason: $reason)');
  }

  void handleDisconnect(String sessionId) {
    leaveRoom(sessionId);
  }
  
  Room? getRoom(String roomId) => _rooms[roomId];
  
  String? getRoomForSession(String sessionId) => _sessionToRoom[sessionId];
  
  List<String> getSessionsInRoom(String roomId) {
    return _rooms[roomId]?.sessionIds ?? [];
  }
  
  List<Room> getAllRooms() => _rooms.values.toList();
  
  int get roomCount => _rooms.length;
  
  // ========= HELPER METHODS (matching Python backend) =========
  
  /// Get room info with all data
  Room? getRoomInfo(String roomId) => _rooms[roomId];
  
  /// Get room owner ID
  String? getRoomOwner(String roomId) => _rooms[roomId]?.ownerId;
  
  /// Get current room size
  int getRoomSize(String roomId) => _rooms[roomId]?.currentSize ?? 0;
  
  /// Check if user is already in room
  bool isUserInRoom(String sessionId, String roomId) {
    final userRoomId = _sessionToRoom[sessionId];
    return userRoomId == roomId;
  }
  
  /// Check if room has capacity for more players
  bool canJoinRoom(String roomId) {
    final room = _rooms[roomId];
    return room?.hasCapacity ?? false;
  }
  
  /// Validate password for private rooms
  bool validateRoomPassword(String roomId, String? password) {
    final room = _rooms[roomId];
    if (room == null) return false;
    
    // Public rooms don't need password validation
    if (room.permission == 'public') return true;
    
    // Private rooms require password match
    return room.password == password;
  }
}
