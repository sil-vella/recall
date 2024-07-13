import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static IO.Socket? _socket;
  static List<Map<String, dynamic>>? _eventHandlers;

  static IO.Socket? getSocket() {
    if (_socket == null) {
      _socket = IO.io('http://localhost:5000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket?.on('connect', (_) {
        _setupEventHandlers();
      });

      _socket?.on('disconnect', (_) {
        print('Socket disconnected');
      });

      _socket?.on('connect_error', (error) {
        print('Socket connect error: $error');
      });

      _socket?.on('error', (error) {
        print('Socket error: $error');
      });

      _socket?.on('reconnect', (attempt) {
        print('Socket reconnected on attempt: $attempt');
      });

      _socket?.on('reconnect_attempt', (attempt) {
        print('Socket attempting to reconnect: $attempt');
      });

      _socket?.on('reconnecting', (attempt) {
        print('Socket reconnecting: $attempt');
      });

      _socket?.on('reconnect_error', (error) {
        print('Socket reconnect error: $error');
      });

      _socket?.on('reconnect_failed', (error) {
        print('Socket failed to reconnect');
      });

      _socket?.connect();
    }
    return _socket;
  }

  static void _setupEventHandlers() {
    if (_eventHandlers != null && _socket != null) {
      for (var eventHandler in _eventHandlers!) {
        final event = eventHandler['event'] as String;
        final handler = eventHandler['handler'] as dynamic Function(dynamic);
        _socket?.on(event, (data) {
          handler(data);
        });
      }
    }
  }

  static void setEventHandlers(List<Map<String, dynamic>> eventHandlers) {
    _eventHandlers = eventHandlers;
    _setupEventHandlers();
  }

  static void emitEvent(String eventName, dynamic data) {
    final socket = getSocket();
    if (socket != null) {
      socket.emit(eventName, data);
    }
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket?.close();
    _socket = null;
    _eventHandlers = null;
  }
}
