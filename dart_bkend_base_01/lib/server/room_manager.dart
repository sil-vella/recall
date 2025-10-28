class Room {
  final String roomId;
  final String creatorId;
  final List<String> sessionIds = [];
  final DateTime createdAt = DateTime.now();
  
  Room(this.roomId, this.creatorId);
  
  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'creator_id': creatorId,
      'player_count': sessionIds.length,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class RoomManager {
  final Map<String, Room> _rooms = {};
  final Map<String, String> _sessionToRoom = {}; // sessionId -> roomId
  
  String createRoom(String creatorSessionId, String userId) {
    final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final room = Room(roomId, userId);
    room.sessionIds.add(creatorSessionId);
    
    _rooms[roomId] = room;
    _sessionToRoom[creatorSessionId] = roomId;
    
    print('🏠 Room created: $roomId by $userId');
    return roomId;
  }
  
  bool joinRoom(String roomId, String sessionId, String userId) {
    final room = _rooms[roomId];
    if (room == null) {
      print('❌ Room not found: $roomId');
      return false;
    }
    
    room.sessionIds.add(sessionId);
    _sessionToRoom[sessionId] = roomId;
    
    print('👤 $userId joined room $roomId (Players: ${room.sessionIds.length})');
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
      _rooms.remove(roomId);
      print('🗑️  Room destroyed: $roomId (empty)');
    }
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
}
