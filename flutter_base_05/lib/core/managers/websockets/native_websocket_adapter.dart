import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false; // WS connect + authenticate emit (enable-logging-switch.mdc; set false after test)

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
      if (LOGGING_SWITCH) {
        _logger.info('🔌 Starting WebSocket connection to: $url');
      }
      final token = options['query']?['token'] ?? options['auth']?['token'];
      if (LOGGING_SWITCH) {
        _logger.debug('🔌 Token available: ${token != null}');
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('🔌 Creating WebSocketChannel...');
      }
      _channel = WebSocketChannel.connect(Uri.parse(url));
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocketChannel created');
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('🔌 Setting up stream listener...');
      }
      _channel!.stream.listen(
        _onMessage,
        onDone: () => _onDisconnect(),
        onError: (error) => _onError(error),
      );
      if (LOGGING_SWITCH) {
        _logger.info('✅ Stream listener registered');
      }
      
      final completer = Completer<bool>();
      
      if (LOGGING_SWITCH) {
        _logger.info('🔌 Registering once listener for "connected" event...');
      }
      once('connected', (data) {
        if (LOGGING_SWITCH) {
          _logger.info('🎯 IMPORTANT: Received connected event in adapter! Data: $data');
        }
        if (data is Map && data.containsKey('session_id')) {
          _sessionId = data['session_id'];
          _isConnected = true;
          if (LOGGING_SWITCH) {
            _logger.info('🎯 IMPORTANT: Set sessionId=$_sessionId, _isConnected=true');
          }
          
          if (token != null) {
            if (LOGGING_SWITCH) {
              _logger.info('🔐 Emitting authenticate event...');
            }
            emit('authenticate', {'token': token});
          }
          
          completer.complete(true);
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Connected event received but no session_id in data: $data');
          }
        }
      });
      if (LOGGING_SWITCH) {
        _logger.info('✅ Once listener for "connected" event registered');
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('⏳ Waiting for connected event (5s timeout)...');
      }
      final result = await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Timeout waiting for connected event! Channel still active: ${_channel != null}');
          }
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Current sessionId: $_sessionId, _isConnected: $_isConnected');
          }
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Registered listeners: ${_onceListeners.keys.toList()}');
          }
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Registered event listeners: ${_eventListeners.keys.toList()}');
          }
          return false;
        },
      );
      
      if (LOGGING_SWITCH) {
        _logger.info('🔍 connect() completed with result: $result, sessionId: $_sessionId');
      }
      return result;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ WebSocket connection error: $e');
      }
      if (LOGGING_SWITCH) {
        _logger.error('❌ Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }
  
  void emit(String event, dynamic data) {
    if (LOGGING_SWITCH) {
      _logger.debug('📤 Attempting to emit event: $event, _channel: ${_channel != null}, _isConnected: $_isConnected');
    }
    if (_channel == null || !_isConnected) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ Cannot emit event: not connected (channel: ${_channel != null}, connected: $_isConnected)');
      }
      return;
    }
    
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> dataMap;
      if (data is Map) {
        dataMap = Map<String, dynamic>.from(data);
      } else {
        dataMap = {'data': data};
      }
      
      final message = jsonEncode({
        'event': event,
        ...dataMap,
      });
      if (LOGGING_SWITCH) {
        _logger.info('📤 Emitting event "$event" to WebSocket (message length: ${message.length} bytes)');
      }
      _channel!.sink.add(message);
      if (LOGGING_SWITCH) {
        _logger.debug('✅ Event "$event" added to sink successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error emitting event $event: $e');
      }
      if (LOGGING_SWITCH) {
        _logger.error('❌ Stack trace: ${StackTrace.current}');
      }
    }
  }
  
  void on(String event, Function(dynamic) callback) {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering persistent listener for event: $event');
    }
    _eventListeners.putIfAbsent(event, () => []).add(callback);
    if (LOGGING_SWITCH) {
      _logger.debug('✅ Persistent listener registered for event: $event (total listeners: ${_eventListeners[event]?.length ?? 0})');
    }
  }
  
  void once(String event, Function(dynamic) callback) {
    if (LOGGING_SWITCH) {
      _logger.info('🎯 Registering once listener for event: $event');
    }
    _onceListeners[event] = callback;
    if (LOGGING_SWITCH) {
      _logger.info('✅ Once listener registered for event: $event (total once listeners: ${_onceListeners.length})');
    }
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
      if (LOGGING_SWITCH) {
        _logger.debug('📥 Raw WebSocket message received: $truncatedMessage');
      }
      
      final decoded = jsonDecode(message as String);
      
      // Convert LinkedMap<dynamic, dynamic> to Map<String, dynamic>
      // jsonDecode can return LinkedMap which is not compatible with Map<String, dynamic>
      final Map<String, dynamic> data;
      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      } else {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Expected JSON object, got ${decoded.runtimeType}');
        }
        return;
      }
      
      final event = data['event'] as String?;
      
      if (LOGGING_SWITCH) {
        _logger.debug('📨 WebSocket message received: event=$event, data=${data.keys.toList()}');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('📨 Current sessionId: $_sessionId, _isConnected: $_isConnected');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('📨 Available once listeners: ${_onceListeners.keys.toList()}');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('📨 Available event listeners: ${_eventListeners.keys.toList()}');
      }
      
      // Special logging for join_room_success and room_joined events
      if (event == 'join_room_success' || event == 'room_joined') {
        if (LOGGING_SWITCH) {
          _logger.info('🎯 IMPORTANT: Received $event event! Room ID: ${data['room_id']}, Session ID: ${data['session_id']}');
        }
        if (LOGGING_SWITCH) {
          _logger.info('🎯 Full message data: $data');
        }
        if (LOGGING_SWITCH) {
          _logger.info('🎯 Current adapter sessionId: $_sessionId');
        }
      }
      
      if (event == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ WebSocket message has no event field. Full message: $data');
        }
        return;
      }
      
      // Special logging for 'connected' event
      if (event == 'connected') {
        if (LOGGING_SWITCH) {
          _logger.info('🔌🔌🔌 Connected event received in _onMessage! Session ID: ${data['session_id']}');
        }
        if (LOGGING_SWITCH) {
          _logger.info('🔌 Checking for once listener: ${_onceListeners.containsKey(event)}');
        }
        if (LOGGING_SWITCH) {
          _logger.info('🔌 Checking for event listeners: ${_eventListeners.containsKey(event)}');
        }
      }
      
      if (_onceListeners.containsKey(event)) {
        if (LOGGING_SWITCH) {
          _logger.info('🎯 Triggering once listener for event: $event');
        }
        _onceListeners[event]!(data);
        _onceListeners.remove(event);
        if (LOGGING_SWITCH) {
          _logger.info('✅ Once listener executed and removed for event: $event');
        }
        return;
      }
      
      final listeners = _eventListeners[event];
      if (listeners != null) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎧 Triggering ${listeners.length} listeners for event: $event');
        }
        for (final listener in listeners) {
          listener(data);
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('❓ No listeners registered for event: $event');
        }
        if (LOGGING_SWITCH) {
          _logger.warning('❓ This message will be ignored!');
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error processing message: $e');
      }
      if (LOGGING_SWITCH) {
        _logger.error('❌ Stack trace: ${StackTrace.current}');
      }
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
