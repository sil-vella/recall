import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true;

class NativeWebSocketAdapter {
  static final Logger _logger = Logger();
  
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
      _logger.error('WebSocket connection error: $e');
      return false;
    }
  }
  
  void emit(String event, dynamic data) {
    if (_channel == null || !_isConnected) {
      _logger.warning('Cannot emit event: not connected');
      return;
    }
    
    try {
      final message = jsonEncode({
        'event': event,
        ...((data is Map<String, dynamic>) ? data : {'data': data}),
      });
      _channel!.sink.add(message);
    } catch (e) {
      _logger.error('Error emitting event $event: $e');
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
      _logger.error('Error disconnecting: $e');
    }
  }
  
  void onDisconnect() {
    disconnect();
  }
  
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final event = data['event'] as String?;
      
      _logger.debug('📨 WebSocket message received: event=$event, data=${data.keys.toList()}', isOn: LOGGING_SWITCH);
      
      if (event == null) {
        _logger.warning('⚠️ WebSocket message has no event field', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Special logging for 'connected' event
      if (event == 'connected') {
        _logger.info('🔌 Connected event received! Session ID: ${data['session_id']}', isOn: LOGGING_SWITCH);
      }
      
      if (_onceListeners.containsKey(event)) {
        _logger.debug('🎯 Triggering once listener for event: $event', isOn: LOGGING_SWITCH);
        _onceListeners[event]!(data);
        _onceListeners.remove(event);
        return;
      }
      
      final listeners = _eventListeners[event];
      if (listeners != null) {
        _logger.debug('🎧 Triggering ${listeners.length} listeners for event: $event', isOn: LOGGING_SWITCH);
        for (final listener in listeners) {
          listener(data);
        }
      } else {
        _logger.debug('❓ No listeners registered for event: $event', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      _logger.error('Error processing message: $e', isOn: LOGGING_SWITCH);
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
    _logger.error('WebSocket error: $error');
    
    final listeners = _eventListeners['connect_error'];
    if (listeners != null) {
      for (final listener in listeners) {
        listener(error);
      }
    }
  }
}
