import 'package:recall/tools/logging/logger.dart';
import 'room_manager_stub.dart';

/// Stub implementation of WebSocketServer for practice mode
/// Routes messages to practice bridge callbacks instead of actual WebSocket connections
class WebSocketServerStub {
  final Logger _logger = Logger();
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
    _logger.info('WebSocketServerStub: sendToSession $sessionId', isOn: false);
    _onSendToSession?.call(sessionId, message);
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    _logger.info('WebSocketServerStub: broadcastToRoom $roomId', isOn: false);
    _onBroadcastToRoom?.call(roomId, message);
  }

  /// Broadcast to all sessions in a room except the specified session
  /// In practice mode, this is typically a no-op since there's only one player
  void broadcastToRoomExcept(String roomId, Map<String, dynamic> message, String excludeSessionId) {
    final sessions = _roomManager.getSessionsInRoom(roomId);
    final filteredSessions = sessions.where((sessionId) => sessionId != excludeSessionId).toList();
    _logger.info('WebSocketServerStub: broadcastToRoomExcept $roomId (excluding $excludeSessionId, ${filteredSessions.length} sessions)', isOn: false);
    
    // In practice mode, if we're excluding the only player, this is a no-op
    // Otherwise, broadcast to remaining sessions
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
  
  // Method to trigger hooks (needed for compatibility with backend interface)
  void triggerHook(String hookName, {Map<String, dynamic>? data, String? context}) {
    _logger.info('WebSocketServerStub: triggerHook $hookName', isOn: false);
    _onTriggerHook?.call(hookName, data: data, context: context);
  }

  int get connectionCount => 1;
}

