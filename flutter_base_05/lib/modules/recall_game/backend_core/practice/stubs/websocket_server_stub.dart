import 'package:recall/tools/logging/logger.dart';

/// Stub implementation of WebSocketServer for practice mode
/// Routes messages to practice bridge callbacks instead of actual WebSocket connections
class WebSocketServerStub {
  final Logger _logger = Logger();
  final Function(String sessionId, Map<String, dynamic> message)? _onSendToSession;
  final Function(String roomId, Map<String, dynamic> message)? _onBroadcastToRoom;
  
  WebSocketServerStub({
    Function(String sessionId, Map<String, dynamic> message)? onSendToSession,
    Function(String roomId, Map<String, dynamic> message)? onBroadcastToRoom,
  }) : _onSendToSession = onSendToSession,
       _onBroadcastToRoom = onBroadcastToRoom;

  void sendToSession(String sessionId, Map<String, dynamic> message) {
    _logger.info('WebSocketServerStub: sendToSession $sessionId', isOn: false);
    _onSendToSession?.call(sessionId, message);
  }

  void broadcastToRoom(String roomId, Map<String, dynamic> message) {
    _logger.info('WebSocketServerStub: broadcastToRoom $roomId', isOn: false);
    _onBroadcastToRoom?.call(roomId, message);
  }

  String? getUserIdForSession(String sessionId) {
    // In practice mode, sessionId is typically the userId
    return sessionId;
  }

  String? getSessionForUser(String userId) {
    // In practice mode, userId is typically the sessionId
    return userId;
  }

  String? getRoomOwner(String roomId) {
    // In practice mode, owner is typically the practice user
    return 'practice_user';
  }

  int get connectionCount => 1;
}

