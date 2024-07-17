import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static IO.Socket? _socket;
  static List<Map<String, dynamic>>? _eventHandlers;

  static IO.Socket? getSocket() {
    if (_socket == null) {
      print('Initializing socket connection...');
      _socket = IO.io('http://192.168.178.80:5000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket?.on('connect', (_) {
        print('Socket connected');
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

      print('Connecting socket...');
      _socket?.connect();
    }
    return _socket;
  }

  static void _setupEventHandlers() {
    if (_eventHandlers != null && _socket != null) {
      print('Setting up event handlers...');
      for (var eventHandler in _eventHandlers!) {
        final event = eventHandler['event'] as String;
        final handler = eventHandler['handler'] as dynamic Function(dynamic);
        print('Listening to event: $event');
        _socket?.on(event, (data) {
          print('Event received: $event, Data: $data');
          handler(data);
        });
      }
    }
  }

  static void setEventHandlers(List<Map<String, dynamic>> eventHandlers) {
    print('Setting event handlers...');
    _eventHandlers = eventHandlers;
    _setupEventHandlers();
  }

  static void emitEvent(String eventName, dynamic data) {
    final socket = getSocket();
    if (socket != null) {
      print('Emitting event: $eventName, Data: $data');
      socket.emit(eventName, data);
    } else {
      print('Socket is not connected, unable to emit event: $eventName');
    }
  }

  static void disconnect() {
    if (_socket != null) {
      print('Disconnecting socket...');
      _socket?.disconnect();
      _socket?.close();
      _socket = null;
      _eventHandlers = null;
      print('Socket disconnected and closed');
    } else {
      print('Socket is already disconnected');
    }
  }
}
