import 'dart:async';
import '../utils/config.dart';
import '../utils/server_logger.dart';

/// Set to true to log Room TTL events to server.log for testing (plan: Room TTL implementation).
const bool LOGGING_SWITCH = true; // Room create/join/capacity before match start (enable-logging-switch.mdc; set false after test)

class Room {
  final String roomId;
  final String ownerId; // Renamed from creatorId to match Python
  final List<String> sessionIds = [];
  final DateTime createdAt = DateTime.now();
  DateTime _ttlExpiresAt; // TTL expiration time
  
  // Room settings (matching Python backend)
  final int maxSize;
  final int minPlayers;
  final String gameType;
  final String permission; // 'public' or 'private'
  final String? password; // for private rooms
  final bool autoStart;
  /// True when room was created by join_random_game (uses its own delay + _startMatchForRandomJoin).
  final bool isRandomJoin;
  /// Game level (e.g. 1, 2, 3) from create_room payload; optional.
  final int? gameLevel;
  String? difficulty; // Room difficulty (set by first human player's rank)
  /// Accepted players for create-match invite flow: [{ user_id, username, is_comp_player }]. Available in _handleJoinRoom.
  final List<Map<String, dynamic>>? acceptedPlayers;
  /// True when this room is for a tournament match (create_room or rematch snapshot from Python).
  bool isTournament;
  /// Tournament payload (tournament_id, match_index, type, format, matches, …). May be set at create or after rematch.
  Map<String, dynamic>? tournamentData;

  /// Set by Python `rematch-tournament-snapshot` before lobby reset; merged into `game_state` once then cleared.
  Map<String, dynamic>? pendingRematchTournamentData;

  /// Set to `true` after a **rematch** request has been processed (`restart_invite` sent). Cleared when a new match **starts** (`start_match`).
  /// Prevents duplicate rematch handling for the same ended match until the next match begins.
  bool hasMatchRestarted = false;

  /// Cancelled when rematch completes or aborts (no scheduled rematch timer — all must accept first).
  Timer? rematchPendingTimer;

  /// Rematch accept list: `{session_id, user_id}` (initiator is seeded when `rematch` is received).
  final List<Map<String, dynamic>> rematchAccepted = [];

  /// Rematch decline list: `{session_id, user_id}`.
  final List<Map<String, dynamic>> rematchDeclined = [];

  String? rematchInitiatorSessionId;
  String? rematchInitiatorUserId;

  Room({
    required this.roomId,
    required this.ownerId,
    this.maxSize = 8,
    this.minPlayers = 2,
    this.gameType = 'classic',
    this.permission = 'public',
    this.password,
    this.autoStart = true,
    this.isRandomJoin = false,
    this.gameLevel,
    this.difficulty,
    this.acceptedPlayers,
    this.isTournament = false,
    this.tournamentData,
    DateTime? ttlExpiresAt,
  }) : _ttlExpiresAt = ttlExpiresAt ?? DateTime.now().add(Duration(seconds: 86400)); // Default 24 hours
  
  // Getter for current size
  int get currentSize => sessionIds.length;
  
  // Check if room has capacity
  bool get hasCapacity => currentSize < maxSize;
  
  // Check if room meets minimum players
  bool get meetsMinPlayers => currentSize >= minPlayers;
  
  // Get TTL expiration time
  DateTime get ttlExpiresAt => _ttlExpiresAt;
  
  // Check if room has expired
  bool get isExpired => DateTime.now().isAfter(_ttlExpiresAt);
  
  // Extend TTL (called on join or activity)
  void extendTtl(Duration ttl) {
    _ttlExpiresAt = DateTime.now().add(ttl);
  }
  
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'room_id': roomId,
      'owner_id': ownerId, // Changed from creator_id to match Python
      'creator_id': ownerId, // Keep both for compatibility
      'current_size': currentSize,
      'max_size': maxSize,
      'min_players': minPlayers,
      'game_type': gameType,
      'permission': permission,
      'auto_start': autoStart,
      'difficulty': difficulty, // Room difficulty (rank-based)
      'created_at': createdAt.toIso8601String(),
      'player_count': sessionIds.length, // Keep for backward compatibility
    };
    if (gameLevel != null) m['game_level'] = gameLevel;
    if (isTournament) m['is_tournament'] = true;
    if (tournamentData != null && tournamentData!.isNotEmpty) m['tournament_data'] = tournamentData;
    return m;
  }
}

class RoomManager {
  final Map<String, Room> _rooms = {};
  final Map<String, String> _sessionToRoom = {}; // sessionId -> roomId
  static final Logger _logger = Logger();

  // Callback for room closure events
  Function(String roomId, String reason)? onRoomClosed;

  // TTL cleanup timer
  Timer? _ttlCleanupTimer;
  bool _ttlMonitorStarted = false;

  // Import config for TTL values
  RoomManager() {
    _startTtlMonitor();
  }
  
  String createRoom(String creatorSessionId, String userId, {
    int? maxSize,
    int? minPlayers,
    String? gameType,
    String? permission,
    String? password,
    bool? autoStart,
    bool? isRandomJoin,
    int? gameLevel,
    List<Map<String, dynamic>>? acceptedPlayers,
    /// When true (default), creator is added to the room. When false, room is created but creator is not in it.
    bool addCreatorToRoom = true,
    /// True when this room is for a tournament match (payload from start-tournament-match).
    bool isTournament = false,
    /// Tournament data from DB; passed into game state when match starts.
    Map<String, dynamic>? tournamentData,
  }) {
    final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    // Initialize TTL from config
    final ttl = Duration(seconds: Config.WS_ROOM_TTL);
    final room = Room(
      roomId: roomId,
      ownerId: userId,
      maxSize: maxSize ?? 8,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'classic',
      permission: permission ?? 'public',
      password: password,
      autoStart: autoStart ?? true,
      isRandomJoin: isRandomJoin ?? false,
      gameLevel: gameLevel,
      acceptedPlayers: acceptedPlayers,
      isTournament: isTournament,
      tournamentData: tournamentData,
      ttlExpiresAt: DateTime.now().add(ttl),
    );
    if (addCreatorToRoom) {
      room.sessionIds.add(creatorSessionId);
      _sessionToRoom[creatorSessionId] = roomId;
    }

    _rooms[roomId] = room;

    // Set/extend TTL when room is created (or first join)
    reinstateRoomTtl(roomId);

    if (LOGGING_SWITCH) {
      _logger.info('RoomManager: Room created $roomId by $userId (max: ${room.maxSize}, permission: ${room.permission}, TTL: ${Config.WS_ROOM_TTL}s, expires: ${room.ttlExpiresAt.toIso8601String()})');
    }
    print('🏠 Room created: $roomId by $userId (max: ${room.maxSize}, permission: ${room.permission}, TTL: ${Config.WS_ROOM_TTL}s)');
    return roomId;
  }
  
  bool joinRoom(String roomId, String sessionId, String userId) {
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
    
    room.sessionIds.add(sessionId);
    _sessionToRoom[sessionId] = roomId;
    
    // Reinstate TTL on join (extend expiration time)
    reinstateRoomTtl(roomId);
    
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
  
  // ========= TTL MANAGEMENT =========
  
  /// Reinstate/extend the room TTL (call on each join or activity)
  void reinstateRoomTtl(String roomId, {Duration? ttl}) {
    final room = _rooms[roomId];
    if (room == null) return;

    final ttlDuration = ttl ?? Duration(seconds: Config.WS_ROOM_TTL);
    room.extendTtl(ttlDuration);
    if (LOGGING_SWITCH) {
      _logger.info('RoomManager: TTL extended for room $roomId (${Config.WS_ROOM_TTL}s), new expires: ${room.ttlExpiresAt.toIso8601String()}');
    }
  }
  
  /// Start TTL monitor for automatic room expiration
  void _startTtlMonitor() {
    if (_ttlMonitorStarted) return;
    _ttlMonitorStarted = true;

    final intervalSeconds = Config.WS_ROOM_TTL_PERIODIC_TIMER;
    _ttlCleanupTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _cleanupExpiredRooms();
    });

    if (LOGGING_SWITCH) {
      _logger.info('RoomManager: TTL monitor started (check interval: ${intervalSeconds}s, room TTL: ${Config.WS_ROOM_TTL}s)');
    }
    print('⏰ Room TTL monitor started (check interval: ${intervalSeconds}s, room TTL: ${Config.WS_ROOM_TTL}s)');
  }

  /// Cleanup expired rooms
  void _cleanupExpiredRooms() {
    final expiredRooms = <String>[];

    // Find expired rooms
    for (final entry in _rooms.entries) {
      final room = entry.value;
      if (room.isExpired) {
        expiredRooms.add(entry.key);
      }
    }

    // Close expired rooms
    for (final roomId in expiredRooms) {
      if (LOGGING_SWITCH) {
        _logger.info('RoomManager: Room $roomId expired (TTL: ${Config.WS_ROOM_TTL}s), closing with reason ttl_expired');
      }
      print('⏰ Room $roomId expired (TTL: ${Config.WS_ROOM_TTL}s)');
      closeRoom(roomId, 'ttl_expired');
    }

    if (expiredRooms.isNotEmpty && LOGGING_SWITCH) {
      _logger.info('RoomManager: Cleaned up ${expiredRooms.length} expired room(s)');
    }
    if (expiredRooms.isNotEmpty) {
      print('🧹 Cleaned up ${expiredRooms.length} expired room(s)');
    }
  }
  
  /// Dispose resources (stop TTL monitor)
  void dispose() {
    _ttlCleanupTimer?.cancel();
    _ttlCleanupTimer = null;
    _ttlMonitorStarted = false;
  }
}
