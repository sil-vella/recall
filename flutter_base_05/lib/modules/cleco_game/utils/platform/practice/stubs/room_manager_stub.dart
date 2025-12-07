import 'package:cleco/tools/logging/logger.dart';

/// Room information for practice mode
class RoomInfoStub {
  final String roomId;
  final String ownerId;
  final int currentSize;
  final int maxSize;
  final int minPlayers;
  final String gameType;
  final String permission;
  final int turnTimeLimit;
  final bool autoStart;

  RoomInfoStub({
    required this.roomId,
    required this.ownerId,
    this.currentSize = 1,
    this.maxSize = 4,
    this.minPlayers = 2,
    this.gameType = 'practice',
    this.permission = 'private',
    this.turnTimeLimit = 30,
    this.autoStart = false,
  });
}

/// Stub implementation of RoomManager for practice mode
class RoomManagerStub {
  final Logger _logger = Logger();
  final Map<String, RoomInfoStub> _rooms = {};
  final Map<String, String> _sessionToRoom = {};

  static const bool LOGGING_SWITCH = false;

  RoomManagerStub();

  String createRoom(String creatorSessionId, String userId, {
    int? maxSize,
    int? minPlayers,
    String? gameType,
    String? permission,
    String? password,
    int? turnTimeLimit,
    bool? autoStart,
  }) {
    final roomId = 'practice_room_${DateTime.now().millisecondsSinceEpoch}';
    final room = RoomInfoStub(
      roomId: roomId,
      ownerId: userId,
      currentSize: 1,
      maxSize: maxSize ?? 4,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'practice',
      permission: permission ?? 'private',
      turnTimeLimit: turnTimeLimit ?? 30,
      autoStart: autoStart ?? false,
    );
    
    _rooms[roomId] = room;
    _sessionToRoom[creatorSessionId] = roomId;
    
    _logger.info('RoomManagerStub: Created practice room $roomId', isOn: LOGGING_SWITCH);
    return roomId;
  }

  bool joinRoom(String roomId, String sessionId, String userId, {String? password}) {
    final room = _rooms[roomId];
    if (room == null) return false;
    
    _sessionToRoom[sessionId] = roomId;
    _logger.info('RoomManagerStub: Joined practice room $roomId', isOn: LOGGING_SWITCH);
    return true;
  }

  void leaveRoom(String sessionId) {
    _sessionToRoom.remove(sessionId);
  }

  void closeRoom(String roomId, String reason) {
    _rooms.remove(roomId);
    _sessionToRoom.removeWhere((_, rid) => rid == roomId);
  }

  void handleDisconnect(String sessionId) {
    leaveRoom(sessionId);
  }

  String? getRoomForSession(String sessionId) {
    return _sessionToRoom[sessionId];
  }

  RoomInfoStub? getRoomInfo(String roomId) {
    return _rooms[roomId];
  }

  List<String> getSessionsInRoom(String roomId) {
    return _sessionToRoom.entries
        .where((e) => e.value == roomId)
        .map((e) => e.key)
        .toList();
  }

  bool isUserInRoom(String sessionId, String roomId) {
    return _sessionToRoom[sessionId] == roomId;
  }

  bool canJoinRoom(String roomId) {
    final room = _rooms[roomId];
    if (room == null) return false;
    return room.currentSize < room.maxSize;
  }

  bool validateRoomPassword(String roomId, String? password) {
    // Practice rooms don't need passwords
    return true;
  }

  List<RoomInfoStub> getAllRooms() {
    return _rooms.values.toList();
  }
}

