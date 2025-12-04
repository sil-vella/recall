import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

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
      _logger.info('🔌 Starting WebSocket connection to: $url', isOn: LOGGING_SWITCH);
      final token = options['query']?['token'] ?? options['auth']?['token'];
      _logger.debug('🔌 Token available: ${token != null}', isOn: LOGGING_SWITCH);
      
      _logger.info('🔌 Creating WebSocketChannel...', isOn: LOGGING_SWITCH);
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _logger.info('✅ WebSocketChannel created', isOn: LOGGING_SWITCH);
      
      _logger.info('🔌 Setting up stream listener...', isOn: LOGGING_SWITCH);
      _channel!.stream.listen(
        _onMessage,
        onDone: () => _onDisconnect(),
        onError: (error) => _onError(error),
      );
      _logger.info('✅ Stream listener registered', isOn: LOGGING_SWITCH);
      
      final completer = Completer<bool>();
      
      _logger.info('🔌 Registering once listener for "connected" event...', isOn: LOGGING_SWITCH);
      once('connected', (data) {
        _logger.info('🎯 IMPORTANT: Received connected event in adapter! Data: $data', isOn: LOGGING_SWITCH);
        if (data is Map && data.containsKey('session_id')) {
          _sessionId = data['session_id'];
          _isConnected = true;
          _logger.info('🎯 IMPORTANT: Set sessionId=$_sessionId, _isConnected=true', isOn: LOGGING_SWITCH);
          
          if (token != null) {
            _logger.info('🔐 Emitting authenticate event...', isOn: LOGGING_SWITCH);
            emit('authenticate', {'token': token});
          }
          
          completer.complete(true);
        } else {
          _logger.warning('⚠️ Connected event received but no session_id in data: $data', isOn: LOGGING_SWITCH);
        }
      });
      _logger.info('✅ Once listener for "connected" event registered', isOn: LOGGING_SWITCH);
      
      _logger.info('⏳ Waiting for connected event (5s timeout)...', isOn: LOGGING_SWITCH);
      final result = await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          _logger.warning('⚠️ Timeout waiting for connected event! Channel still active: ${_channel != null}', isOn: LOGGING_SWITCH);
          _logger.warning('⚠️ Current sessionId: $_sessionId, _isConnected: $_isConnected', isOn: LOGGING_SWITCH);
          _logger.warning('⚠️ Registered listeners: ${_onceListeners.keys.toList()}', isOn: LOGGING_SWITCH);
          _logger.warning('⚠️ Registered event listeners: ${_eventListeners.keys.toList()}', isOn: LOGGING_SWITCH);
          return false;
        },
      );
      
      _logger.info('🔍 connect() completed with result: $result, sessionId: $_sessionId', isOn: LOGGING_SWITCH);
      return result;
    } catch (e) {
      _logger.error('❌ WebSocket connection error: $e', isOn: LOGGING_SWITCH);
      _logger.error('❌ Stack trace: ${StackTrace.current}', isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  void emit(String event, dynamic data) {
    _logger.debug('📤 Attempting to emit event: $event, _channel: ${_channel != null}, _isConnected: $_isConnected', isOn: LOGGING_SWITCH);
    if (_channel == null || !_isConnected) {
      _logger.warning('⚠️ Cannot emit event: not connected (channel: ${_channel != null}, connected: $_isConnected)', isOn: LOGGING_SWITCH);
      return;
    }
    
    try {
      final message = jsonEncode({
        'event': event,
        ...((data is Map<String, dynamic>) ? data : {'data': data}),
      });
      _logger.info('📤 Emitting event "$event" to WebSocket (message length: ${message.length} bytes)', isOn: LOGGING_SWITCH);
      _channel!.sink.add(message);
      _logger.debug('✅ Event "$event" added to sink successfully', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error emitting event $event: $e', isOn: LOGGING_SWITCH);
      _logger.error('❌ Stack trace: ${StackTrace.current}', isOn: LOGGING_SWITCH);
    }
  }
  
  void on(String event, Function(dynamic) callback) {
    _logger.debug('🎧 Registering persistent listener for event: $event', isOn: LOGGING_SWITCH);
    _eventListeners.putIfAbsent(event, () => []).add(callback);
    _logger.debug('✅ Persistent listener registered for event: $event (total listeners: ${_eventListeners[event]?.length ?? 0})', isOn: LOGGING_SWITCH);
  }
  
  void once(String event, Function(dynamic) callback) {
    _logger.info('🎯 Registering once listener for event: $event', isOn: LOGGING_SWITCH);
    _onceListeners[event] = callback;
    _logger.info('✅ Once listener registered for event: $event (total once listeners: ${_onceListeners.length})', isOn: LOGGING_SWITCH);
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
      // Log raw message first
      final messageStr = message.toString();
      final truncatedMessage = messageStr.length > 200 ? messageStr.substring(0, 200) : messageStr;
      _logger.debug('📥 Raw WebSocket message received: $truncatedMessage', isOn: LOGGING_SWITCH);
      
      final data = jsonDecode(message as String);
      final event = data['event'] as String?;
      
      _logger.debug('📨 WebSocket message received: event=$event, data=${data.keys.toList()}', isOn: LOGGING_SWITCH);
      _logger.debug('📨 Current sessionId: $_sessionId, _isConnected: $_isConnected', isOn: LOGGING_SWITCH);
      _logger.debug('📨 Available once listeners: ${_onceListeners.keys.toList()}', isOn: LOGGING_SWITCH);
      _logger.debug('📨 Available event listeners: ${_eventListeners.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Special logging for join_room_success and room_joined events
      if (event == 'join_room_success' || event == 'room_joined') {
        _logger.info('🎯 IMPORTANT: Received $event event! Room ID: ${data['room_id']}, Session ID: ${data['session_id']}', isOn: LOGGING_SWITCH);
        _logger.info('🎯 Full message data: $data', isOn: LOGGING_SWITCH);
        _logger.info('🎯 Current adapter sessionId: $_sessionId', isOn: LOGGING_SWITCH);
      }
      
      if (event == null) {
        _logger.warning('⚠️ WebSocket message has no event field. Full message: $data', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Special logging for 'connected' event
      if (event == 'connected') {
        _logger.info('🔌🔌🔌 Connected event received in _onMessage! Session ID: ${data['session_id']}', isOn: LOGGING_SWITCH);
        _logger.info('🔌 Checking for once listener: ${_onceListeners.containsKey(event)}', isOn: LOGGING_SWITCH);
        _logger.info('🔌 Checking for event listeners: ${_eventListeners.containsKey(event)}', isOn: LOGGING_SWITCH);
      }
      
      if (_onceListeners.containsKey(event)) {
        _logger.info('🎯 Triggering once listener for event: $event', isOn: LOGGING_SWITCH);
        _onceListeners[event]!(data);
        _onceListeners.remove(event);
        _logger.info('✅ Once listener executed and removed for event: $event', isOn: LOGGING_SWITCH);
        return;
      }
      
      final listeners = _eventListeners[event];
      if (listeners != null) {
        _logger.debug('🎧 Triggering ${listeners.length} listeners for event: $event', isOn: LOGGING_SWITCH);
        for (final listener in listeners) {
          listener(data);
        }
      } else {
        _logger.warning('❓ No listeners registered for event: $event', isOn: LOGGING_SWITCH);
        _logger.warning('❓ This message will be ignored!', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      _logger.error('❌ Error processing message: $e', isOn: LOGGING_SWITCH);
      _logger.error('❌ Stack trace: ${StackTrace.current}', isOn: LOGGING_SWITCH);
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
