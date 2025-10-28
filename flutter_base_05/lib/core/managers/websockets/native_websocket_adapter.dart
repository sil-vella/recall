import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../tools/logging/logger.dart';

class NativeWebSocketAdapter {
  static final Logger _log = Logger();
  
  WebSocketChannel? _channel;
  String? _sessionId;
  bool _isConnected = false;
  
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  final Map<String, Function(dynamic)> _onceListeners = {};
  
  String get sessionId => _sessionId ?? '';
  bool get connected => _isConnected;
  String get id => _sessionId ?? 'unknown';
  
  Future<bool> connect(String url, Map<String, dynamic> options) async {
    try {
      final token = options['query']?['token'] ?? options['auth']?['token'];
      
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      _channel!.stream.listen(
        _onMessage,
        onDone: () => _onDisconnect(),
        onError: (error) => _onError(error),
      );
      
      final completer = Completer<bool>();
      
      once('connected', (data) {
        if (data is Map && data.containsKey('session_id')) {
          _sessionId = data['session_id'];
          _isConnected = true;
          
          if (token != null) {
            emit('authenticate', {'token': token});
          }
          
          completer.complete(true);
        }
      });
      
      return await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      _log.error('WebSocket connection error: $e');
      return false;
    }
  }
  
  void emit(String event, dynamic data) {
    if (_channel == null || !_isConnected) {
      _log.warning('Cannot emit event: not connected');
      return;
    }
    
    try {
      final message = jsonEncode({
        'event': event,
        ...((data is Map<String, dynamic>) ? data : {'data': data}),
      });
      _channel!.sink.add(message);
    } catch (e) {
      _log.error('Error emitting event $event: $e');
    }
  }
  
  void on(String event, Function(dynamic) callback) {
    _eventListeners.putIfAbsent(event, () => []).add(callback);
  }
  
  void once(String event, Function(dynamic) callback) {
    _onceListeners[event] = callback;
  }
  
  void off(String event, [Function(dynamic)? callback]) {
    if (callback == null) {
      _eventListeners.remove(event);
    } else {
      _eventListeners[event]?.remove(callback);
    }
  }
  
  void disconnect() {
    try {
      _channel?.sink.close();
      _isConnected = false;
      _sessionId = null;
    } catch (e) {
      _log.error('Error disconnecting: $e');
    }
  }
  
  void onDisconnect() {
    disconnect();
  }
  
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final event = data['event'] as String?;
      
      if (event == null) return;
      
      if (_onceListeners.containsKey(event)) {
        _onceListeners[event]!(data);
        _onceListeners.remove(event);
        return;
      }
      
      final listeners = _eventListeners[event];
      if (listeners != null) {
        for (final listener in listeners) {
          listener(data);
        }
      }
    } catch (e) {
      _log.error('Error processing message: $e');
    }
  }
  
  void _onDisconnect() {
    _isConnected = false;
    _sessionId = null;
    
    final listeners = _eventListeners['disconnect'];
    if (listeners != null) {
      for (final listener in listeners) {
        listener({});
      }
    }
  }
  
  void _onError(dynamic error) {
    _log.error('WebSocket error: $error');
    
    final listeners = _eventListeners['connect_error'];
    if (listeners != null) {
      for (final listener in listeners) {
        listener(error);
      }
    }
  }
}
