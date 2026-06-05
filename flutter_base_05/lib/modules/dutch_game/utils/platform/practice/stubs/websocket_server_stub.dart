import 'room_manager_stub.dart';

/// Stub implementation of WebSocketServer for practice mode
/// Routes messages to practice bridge callbacks instead of actual WebSocket connections
class WebSocketServerStub {
  final RoomManagerStub _roomManager;
  final Function(String sessionId, Map<String, dynamic> message)? _onSendToSession;
  final Function(String roomId, Map<String, dynamic> message)? _onBroadcastToRoom;
  final Function(String hookName, {Map<String, dynamic>? data, String? context})? _onTriggerHook;
  
  WebSocketServerStub({
    required RoomManagerStub roomManager,
    Function(String sessionId, Map<String, dynamic> message)? onSendToSession,
    Function(String roomId, Map<String, dynamic> message)? onBroadcastToRoom,
    Function(String hookName, {Map<String, dynamic>? data, String? context})? onTriggerHook,
  }) : _roomManager = roomManager,
       _onSendToSession = onSendToSession,
       _onBroadcastToRoom = onBroadcastToRoom,
       _onTriggerHook = onTriggerHook;

  void sendToSession(String sessionId, Map<String, dynamic> message) {
    
    _onSendToSession?.call(sessionId, message);
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    
    _onBroadcastToRoom?.call(roomId, message);
  }

  /// Broadcast to all sessions in a room except [excludeSessionId].
  ///
  /// When [excludeSessionId] is a CPU seat (`cpu_*`) it is not a real session, so the
  /// human observer still receives the message (opponent draw/peek STEP-1 updates).
  void broadcastToRoomExcept(String roomId, Map<String, dynamic> message, String excludeSessionId) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    final filteredSessions = sessions.where((sessionId) => sessionId != excludeSessionId).toList();
    for (final sessionId in filteredSessions) {
      _onSendToSession?.call(sessionId, message);
    }
  }

  String? getUserIdForSession(String sessionId) {
    // In practice mode, extract userId from sessionId
    if (sessionId.startsWith('practice_session_')) {
      return sessionId.replaceFirst('practice_session_', '');
    }
    return sessionId;
  }

  String? getSessionForUser(String userId) {
    // In practice mode, sessionId is practice_session_<userId>
    return 'practice_session_$userId';
  }

  String? getRoomOwner(String roomId) {
    // Use room manager to get owner (matches backend behavior)
    final info = _roomManager.getRoomInfo(roomId);
    return info?.ownerId;
  }

  /// Map canonical seat id → practice websocket session id (mirror backend API).
  ///
  /// Returns [gamePlayerSeatId] when it is a connected session (the human).
  /// Returns null for CPU/comp seats so [broadcastGameStateExcept] does not exclude
  /// the human when an opponent draws or peeks.
  String? websocketSessionForGamePlayer(String roomId, String gamePlayerSeatId) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    if (sessions.contains(gamePlayerSeatId)) return gamePlayerSeatId;
    return null;
  }

  /// Get room info for a room
  /// Returns the RoomInfoStub object or null if not found
  RoomInfoStub? getRoomInfo(String roomId) {
    return _roomManager.getRoomInfo(roomId);
  }
  
  // Method to trigger hooks (needed for compatibility with backend interface)
  void triggerHook(String hookName, {Map<String, dynamic>? data, String? context}) {
    
    _onTriggerHook?.call(hookName, data: data, context: context);
  }

  /// Mirrors [WebSocketServer.forceSessionLeaveRoom] for practice / embedded coordinator.
  void forceSessionLeaveRoom(String sessionId, {String? reason}) {
    final rid = _roomManager.getRoomForSession(sessionId);
    if (rid == null) return;
    final userId = getUserIdForSession(sessionId) ?? sessionId;
    _roomManager.leaveRoom(sessionId);

    final leaveSuccess = <String, dynamic>{
      'event': 'leave_room_success',
      'room_id': rid,
      'session_id': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (reason != null && reason.isNotEmpty) {
      leaveSuccess['reason'] = reason;
    }
    sendToSession(sessionId, leaveSuccess);

    final hookData = <String, dynamic>{
      'room_id': rid,
      'session_id': sessionId,
      'user_id': userId,
      'left_at': DateTime.now().toIso8601String(),
    };
    if (reason != null && reason.isNotEmpty) {
      hookData['reason'] = reason;
    }
    triggerHook('leave_room', data: hookData);

    final roomAfter = _roomManager.getRoomInfo(rid);
    if (roomAfter != null) {
      broadcastToRoom(rid, {
        'event': 'player_left',
        'room_id': rid,
        'player_count': roomAfter.currentSize,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  int get connectionCount => 1;
}

