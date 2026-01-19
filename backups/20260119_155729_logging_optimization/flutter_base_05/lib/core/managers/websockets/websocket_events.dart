

/// WebSocket connection status events
enum ConnectionStatus {
  connecting,
  connected,
  disconnected,
  error,
  reconnecting
}

/// WebSocket message types
enum MessageType {
  connect,
  disconnect,
  sessionUpdate,
  roomJoined,
  roomLeft,
  message,
  error,
  custom
}

/// WebSocket event base class
abstract class WebSocketEvent {
  final DateTime timestamp;
  final MessageType type;
  
  WebSocketEvent(this.type) : timestamp = DateTime.now();
  
  Map<String, dynamic> toJson();
}

/// Connection status event
class ConnectionStatusEvent extends WebSocketEvent {
  final ConnectionStatus status;
  final String? sessionId;
  final String? error;
  
  ConnectionStatusEvent({
    required this.status,
    this.sessionId,
    this.error,
  }) : super(MessageType.connect);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'connection_status',
      'status': status.name,
      'sessionId': sessionId,
      'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Session data event
class SessionDataEvent extends WebSocketEvent {
  final Map<String, dynamic> sessionData;
  
  SessionDataEvent(this.sessionData) : super(MessageType.sessionUpdate);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'session_data',
      'data': sessionData,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Room event
class RoomEvent extends WebSocketEvent {
  final String roomId;
  final Map<String, dynamic> roomData;
  final String action; // 'joined', 'left', 'created'
  
  RoomEvent({
    required this.roomId,
    required this.roomData,
    required this.action,
  }) : super(MessageType.roomJoined);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'room_event',
      'roomId': roomId,
      'action': action,
      'data': roomData,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Message event
class MessageEvent extends WebSocketEvent {
  final String roomId;
  final String message;
  final String sender;
  final Map<String, dynamic>? additionalData;
  
  MessageEvent({
    required this.roomId,
    required this.message,
    required this.sender,
    this.additionalData,
  }) : super(MessageType.message);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'message',
      'roomId': roomId,
      'message': message,
      'sender': sender,
      'additionalData': additionalData,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Error event
class ErrorEvent extends WebSocketEvent {
  final String error;
  final String? details;
  
  ErrorEvent(this.error, {this.details}) : super(MessageType.error);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'error',
      'error': error,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Custom event
class CustomEvent extends WebSocketEvent {
  final String eventName;
  final Map<String, dynamic> data;
  
  CustomEvent(this.eventName, this.data) : super(MessageType.custom);
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'custom',
      'eventName': eventName,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
} 