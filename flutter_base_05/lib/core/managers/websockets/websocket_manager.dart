import 'dart:async';
import '../../../tools/logging/logger.dart';
import '../../../utils/consts/config.dart';
import '../../../modules/login_module/login_module.dart';
import '../module_manager.dart';
import '../state_manager.dart';
import '../hooks_manager.dart';
import 'ws_event_manager.dart';
import 'ws_event_listener.dart';
import 'ws_event_handler.dart';
import 'websocket_events.dart';
import 'websocket_state_validator.dart';
import 'native_websocket_adapter.dart';

const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues

class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() {
    return _instance;
  }
  WebSocketManager._internal();

  static final Logger _logger = Logger();
  
  NativeWebSocketAdapter? _socket;
  bool _isInitialized = false;
  bool _isConnected = false; // Track connection state explicitly
  bool _isConnecting = false; // Track if we're in the process of connecting
  
  // Event streams for UI updates
  final StreamController<WebSocketEvent> _eventController = StreamController<WebSocketEvent>.broadcast();
  final StreamController<ConnectionStatusEvent> _connectionController = StreamController<ConnectionStatusEvent>.broadcast();
  final StreamController<MessageEvent> _messageController = StreamController<MessageEvent>.broadcast();
  final StreamController<RoomEvent> _roomController = StreamController<RoomEvent>.broadcast();
  final StreamController<ErrorEvent> _errorController = StreamController<ErrorEvent>.broadcast();
  
  // Note: Event handling is now delegated to WSEventManager
  
  // Module manager for accessing LoginModule
  final ModuleManager _moduleManager = ModuleManager();
  
  // Event manager instance (singleton)
  WSEventManager? _eventManager;
  
  // New centralized event listener and handler
  WSEventListener? _eventListener;
  WSEventHandler? _eventHandler;

  // Getters
  NativeWebSocketAdapter? get socket => _socket;
  bool get isInitialized => _isInitialized;
  
  // Event streams for UI
  Stream<WebSocketEvent> get events => _eventController.stream;
  Stream<ConnectionStatusEvent> get connectionStatus => _connectionController.stream;
  Stream<MessageEvent> get messages => _messageController.stream;
  Stream<RoomEvent> get roomEvents => _roomController.stream;
  Stream<ErrorEvent> get errors => _errorController.stream;
  
  // Static getter for easy access
  static WebSocketManager get instance {
    return _instance;
  }

  /// Get the event manager instance
  WSEventManager get eventManager {
    _eventManager ??= WSEventManager.instance;
    return _eventManager!;
  }

  /// Get the event listener instance
  WSEventListener? get eventListener => _eventListener;

  /// Check if connected - direct socket check (no context needed)
  bool get isConnected {
    // Use both our tracked state and socket state for reliability
    final socketConnected = _socket?.connected ?? false;
    
    // If socket is connected but our tracked state is false, update it
    if (socketConnected && !_isConnected) {
      _isConnected = true;
      _isConnecting = false; // We're no longer connecting
    }
    
    // If we have a socket but it's not connected, but we think we're connected, reset
    if (_socket != null && !socketConnected && _isConnected) {
      _isConnected = false;
    }
    
    final connected = _isConnected && socketConnected;
    
    return connected;
  }

  /// Check if we're in the process of connecting
  bool get isConnecting => _isConnecting;

  /// Force refresh connection state (for debugging)
  void _refreshConnectionState() {
    final socketConnected = _socket?.connected ?? false;
    if (socketConnected != _isConnected) {
      _isConnected = socketConnected;
    }
  }

  /// Initialize the WebSocket manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      return isConnected;
    }

    try {
      // Check if socket is already connected
      // Refresh connection state before checking
      _refreshConnectionState();
      
      if (_socket != null && _socket!.connected && _isConnected) {
        _isInitialized = true;
        return true;
      }
      
      // Get JWT token from login module for authentication
      final loginModule = _moduleManager.getModuleByType<LoginModule>();
      if (loginModule == null) {
        return false;
      }
      
      // Check if user has valid JWT token
      final hasToken = await loginModule.hasValidToken();
      if (!hasToken) {
        // Return false - navigation handled by calling module (e.g., Dutch game module)
        return false;
      }
      
      // Get the JWT token
      final authToken = await loginModule.getCurrentToken();
      if (authToken == null) {
        // Return false - navigation handled by calling module (e.g., Dutch game module)
        return false;
      }
      
      // Create native WebSocket adapter (but don't connect yet)
      _socket = NativeWebSocketAdapter();
      
      // Initialize event manager BEFORE connecting
      eventManager.initialize();
      
      // Set up hook triggering logic
      _setupHookTriggers();
      
      // Initialize new centralized event listener and handler BEFORE connecting
      final stateManager = StateManager();
      _eventHandler = WSEventHandler(
        socket: _socket,
        eventManager: eventManager,
        stateManager: stateManager,
        moduleManager: _moduleManager,
      );
      
      _eventListener = WSEventListener(
        socket: _socket,
        eventHandler: _eventHandler!,
        stateManager: stateManager,
        moduleManager: _moduleManager,
      );
      
      // Register all event listeners BEFORE connecting
      _eventListener!.registerAllListeners();
      
      // NOW establish the WebSocket connection (after listeners are ready)
      final connected = await _socket!.connect(Config.wsUrl, <String, dynamic>{
        'query': {
          'token': authToken,
          'client_id': 'flutter_app_${DateTime.now().millisecondsSinceEpoch}',
          'version': '1.0.0',
        },
        'auth': {
          'token': authToken,
        },
      });

      if (!connected) {
        _socket = null;
        return false;
      }
      
      // Update connection state in StateManager since connection is established
      _logger.info('🔌 Connection established in initialize(), updating StateManager', isOn: LOGGING_SWITCH);
      _isConnected = true;
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: true,
        sessionData: null, // No session data available yet
      );
      _logger.info('✅ StateManager updated with connection status in initialize()', isOn: LOGGING_SWITCH);
      
      // Token refresh is now handled by AuthManager
      // No need to setup token refresh here
      
      _isInitialized = true;
      
      // 🎣 Trigger websocket_initialized hook for other modules
      HooksManager().triggerHookWithData('websocket_initialized', {
        'websocket_manager': this,
        'event_listener': _eventListener,
        'event_manager': _eventManager,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // 🎣 Trigger websocket_event_listeners_ready hook specifically for event registration
      HooksManager().triggerHookWithData('websocket_event_listeners_ready', {
        'websocket_manager': this,
        'event_listener': _eventListener,
        'event_manager': _eventManager,
        'is_ready': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      return true;
      
    } catch (e) {
      return false;
    }
  }

  /// ✅ Setup state listener for queued token refreshes
  void _setupStateListener() {
    final stateManager = StateManager();
    // Token refresh is now handled by AuthManager
    // No need to setup state listener here
  }

  /// Set up Socket.IO event handlers
  void _setupEventHandlers() {
    if (_socket == null) return;
    
    // Use 'connect' event instead of onConnect to avoid conflicts with one-time listeners
    _socket!.on('connect', (_) {
      // Update our tracked connection state and use validated system
      _isConnected = true;
      _isConnecting = false; // Reset connecting state
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: true,
        sessionData: null,
      );

      // Logs are now sent via HTTP endpoint, no need to drain pending logs
      
      // Emit connection event
      final event = ConnectionStatusEvent(
        status: ConnectionStatus.connected,
        sessionId: _socket!.id,
      );
      _connectionController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.onDisconnect();

    // Use 'connect_error' event instead of onConnectError to avoid conflicts
    _socket!.on('connect_error', (error) {
      // Update our tracked connection state and use validated system
      _isConnected = false;
      _isConnecting = false; // Reset connecting state
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
      
      // Emit error event
      final event = ConnectionStatusEvent(
        status: ConnectionStatus.error,
        error: error.toString(),
      );
      _connectionController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('session_data', (data) {
      // Use validated state updater
      WebSocketStateHelpers.updateSessionData(
        data is Map<String, dynamic> ? data : null,
      );
      
      // Emit session data event
      final event = SessionDataEvent(data);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('room_joined', (data) {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Emit room event
      final event = RoomEvent(
        roomId: roomId,
        roomData: roomData,
        action: 'joined',
      );
      _roomController.add(event);
      _eventController.add(event);
      
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('join_room_success', (data) {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Emit room event (same as room_joined)
      final event = RoomEvent(
        roomId: roomId,
        roomData: roomData,
        action: 'joined',
      );
      _roomController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('join_room_error', (data) {
      // Emit error event
      final errorEvent = ErrorEvent(
        'Failed to join room',
        details: data.toString(),
      );
      _errorController.add(errorEvent);
      _eventController.add(errorEvent);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('create_room_success', (data) {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Emit room event
      final event = RoomEvent(
        roomId: roomId,
        roomData: roomData,
        action: 'created',
      );
      _roomController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('room_created', (data) {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: roomId,
        roomInfo: roomData,
      );
      
      // Emit room event
      final event = RoomEvent(
        roomId: roomId,
        roomData: roomData,
        action: 'created',
      );
      _roomController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('create_room_error', (data) {
      // Emit error event
      final errorEvent = ErrorEvent(
        'Failed to create room',
        details: data.toString(),
      );
      _errorController.add(errorEvent);
      _eventController.add(errorEvent);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('leave_room_success', (data) {
      final roomId = data['room_id'] ?? '';
      final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      
      // Use validated state updater
      WebSocketStateHelpers.updateRoomInfo(
        roomId: null,
        roomInfo: null,
      );
      
      // Emit room event
      final event = RoomEvent(
        roomId: roomId,
        roomData: roomData,
        action: 'left',
      );
      _roomController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('leave_room_error', (data) {
      // Emit error event
      final errorEvent = ErrorEvent(
        'Failed to leave room',
        details: data.toString(),
      );
      _errorController.add(errorEvent);
      _eventController.add(errorEvent);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('message', (data) {
      // Emit message event
      final event = MessageEvent(
        roomId: data['room_id'] ?? '',
        message: data['message'] ?? '',
        sender: data['sender'] ?? 'unknown',
        additionalData: data,
      );
      _messageController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.on('error', (data) {
      // Emit error event
      final errorEvent = ErrorEvent(
        'WebSocket error',
        details: data.toString(),
      );
      _errorController.add(errorEvent);
      _eventController.add(errorEvent);
      
      // Events are handled through the stream system, not direct handlers
    });

    // Note: Custom event handling is now delegated to WSEventManager
  }

  /// Note: All events are now handled through the stream system
  /// and delegated to WSEventManager for processing

  /// ✅ Token refresh is now handled by AuthManager
  /// This ensures proper separation of concerns

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return false;
      }
      // Continue with connection after initialization
    }

    // Check if the socket is already connected
    // Refresh connection state before checking
    _refreshConnectionState();
    
    if (isConnected) {
      return true;
    }

    // Check if we're already connecting
    if (_isConnecting) {
      return false;
    }

    try {
      // Set connecting state
      _isConnecting = true;
      
      if (_socket == null) {
        _isConnecting = false;
        return false;
      }
      
      // Emit connecting event
      final connectingEvent = ConnectionStatusEvent(
        status: ConnectionStatus.connecting,
      );
      _connectionController.add(connectingEvent);
      _eventController.add(connectingEvent);
      
      // Check if connection is already established (from initialize())
      if (_socket!.connected) {
        _logger.info('🔌 Connection already established, updating state immediately', isOn: LOGGING_SWITCH);
        // Connection already established, update state immediately
        _isConnected = true;
        _isConnecting = false;
        
        _logger.info('🔄 Calling WebSocketStateHelpers.updateConnectionStatus() for pre-established connection', isOn: LOGGING_SWITCH);
        // Update StateManager for UI indicators
        WebSocketStateHelpers.updateConnectionStatus(
          isConnected: true,
          sessionData: null, // No session data available for pre-established connection
        );
        _logger.info('✅ WebSocketStateHelpers.updateConnectionStatus() completed for pre-established connection', isOn: LOGGING_SWITCH);
        
        // 🎣 Trigger websocket_connected hook for other modules
        HooksManager().triggerHookWithData('websocket_connected', {
          'websocket_manager': this,
          'socket_id': _socket!.id,
          'event_listener': _eventListener,
          'event_manager': _eventManager,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        return true;
      }
      
      // Create a completer to wait for the connection event
      final completer = Completer<bool>();
      
      // Set up a one-time listener for the connect event
      void onConnect(dynamic data) {
        _logger.info('🔌 onConnect callback executing with data: $data', isOn: LOGGING_SWITCH);
        
        // Update our tracked connection state
        _logger.info('🔄 Updating _isConnected to true', isOn: LOGGING_SWITCH);
        _isConnected = true;
        _isConnecting = false; // Reset connecting state
        
        _logger.info('🔄 Calling WebSocketStateHelpers.updateConnectionStatus()', isOn: LOGGING_SWITCH);
        // Update StateManager for UI indicators
        WebSocketStateHelpers.updateConnectionStatus(
          isConnected: true,
          sessionData: data is Map<String, dynamic> ? data : null,
        );
        _logger.info('✅ WebSocketStateHelpers.updateConnectionStatus() completed', isOn: LOGGING_SWITCH);
        
        // 🎣 Trigger websocket_connected hook for other modules
        _logger.info('🎣 Triggering websocket_connected hook', isOn: LOGGING_SWITCH);
        HooksManager().triggerHookWithData('websocket_connected', {
          'websocket_manager': this,
          'socket_id': _socket!.id,
          'event_listener': _eventListener,
          'event_manager': _eventManager,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        _logger.info('✅ Completing completer with true', isOn: LOGGING_SWITCH);
        completer.complete(true);
      }
      
      // Set up a one-time listener for connection errors
      void onConnectError(dynamic error) {
        _logger.error('❌ onConnectError callback executing with error: $error', isOn: LOGGING_SWITCH);
        
        // Update our tracked connection state
        _isConnected = false;
        _isConnecting = false;
        
        _logger.error('❌ Completing completer with false due to error', isOn: LOGGING_SWITCH);
        completer.complete(false);
      }
      
      // Add one-time event listeners (these will be removed after use)
      _socket!.once('connected', onConnect);
      _socket!.once('connect_error', onConnectError);
      
      // Wait for connection confirmation
      try {
        final result = await completer.future.timeout(
          Duration(seconds: Config.websocketTimeout),
          onTimeout: () {
            _isConnecting = false; // Reset connecting state on timeout
            return false;
          },
        );
        
        return result;
      } catch (e) {
        _isConnecting = false; // Reset connecting state on exception
        return false;
      }
      
    } catch (e) {
      _isConnecting = false; // Reset connecting state on error
      return false;
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    try {
      _socket?.disconnect();
      
      // Update our tracked connection state
      _isConnected = false;
    } catch (e) {
      // Error disconnecting WebSocket
    }
  }

  /// Create a room
  Future<Map<String, dynamic>> createRoom(String userId, [Map<String, dynamic>? roomData]) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }

    try {
      final data = {
        'user_id': userId,
        ...?roomData, // Spread room data if provided
      };

      // Create a completer to wait for the room_joined event (server response)
      final completer = Completer<Map<String, dynamic>>();
      
      // Set up a one-time listener for the room_joined event (server response to create_room)
      void onRoomJoined(dynamic eventData) {
        if (eventData is Map<String, dynamic>) {
          final roomId = eventData['room_id'];
          completer.complete({
            "success": "Room created successfully", 
            "data": {
              'room_id': roomId,
              'current_size': eventData['current_size'],
              'max_size': eventData['max_size']
            }
          });
        }
      }

      // Set up a one-time listener for create room errors
      void onError(dynamic eventData) {
        if (eventData is Map<String, dynamic>) {
          final message = eventData['message']?.toString() ?? '';
          if (message.contains('Failed to create room')) {
            completer.complete({"error": message});
          }
        }
      }

      // Add event listeners
      _socket!.on('room_joined', onRoomJoined);
      _socket!.on('create_room_error', onError);

      // Emit create_room event
      _socket!.emit('create_room', data);

      // Wait for the room_joined event with a timeout
      try {
        final result = await completer.future.timeout(
          Duration(seconds: Config.websocketTimeout),
          onTimeout: () {
            return {"error": "Timeout waiting for room creation confirmation"};
          },
        );
        
        // Remove event listeners
        _socket!.off('room_joined', onRoomJoined);
        _socket!.off('create_room_error', onError);
        return result;
      } catch (e) {
        // Remove event listeners
        _socket!.off('room_joined', onRoomJoined);
        _socket!.off('create_room_error', onError);
        return {"error": "Failed to create room: $e"};
      }
      
    } catch (e) {
      return {"error": "Failed to create room: $e"};
    }
  }

  /// Join a room
  Future<Map<String, dynamic>> joinRoom(String roomId, String userId) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }

    try {
      final data = {
        'room_id': roomId,
        'user_id': userId,
      };

      // Create a completer to wait for the join_room_success event (server response)
      final completer = Completer<Map<String, dynamic>>();
      
      // Set up a one-time listener for the join_room_success event (server response)
      void onJoinSuccess(dynamic eventData) {
        if (eventData is Map<String, dynamic>) {
          completer.complete({
            "success": "Successfully joined room", 
            "data": {
              'room_id': roomId,
              'current_size': eventData['current_size'],
              'max_size': eventData['max_size']
            }
          });
        }
      }

      // Set up a one-time listener for join room errors
      void onError(dynamic eventData) {
        if (eventData is Map<String, dynamic>) {
          final message = eventData['message']?.toString() ?? '';
          if (message.contains('Failed to join room')) {
            completer.complete({"error": message});
          }
        }
      }

      // Add event listeners
      _socket!.on('join_room_success', onJoinSuccess);
      _socket!.on('join_room_error', onError);

      // Emit join_room event
      _socket!.emit('join_room', data);

      // Wait for the join_room_success event with a timeout
      try {
        final result = await completer.future.timeout(
          Duration(seconds: Config.websocketTimeout),
          onTimeout: () {
            return {"error": "Timeout waiting for room join confirmation"};
          },
        );
        
        // Remove event listeners
        _socket!.off('join_room_success', onJoinSuccess);
        _socket!.off('join_room_error', onError);
        return result;
      } catch (e) {
        // Remove event listeners
        _socket!.off('join_room_success', onJoinSuccess);
        _socket!.off('join_room_error', onError);
        return {"error": "Failed to join room: $e"};
      }
      
    } catch (e) {
      return {"error": "Failed to join room: $e"};
    }
  }

  /// Leave a room
  Future<Map<String, dynamic>> leaveRoom(String roomId) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }

    try {
      final data = {
        'room_id': roomId,
      };

      _socket!.emit('leave_room', data);
      
      // Don't return success immediately - wait for server response
      return {"pending": "Leave room request sent"};
      
    } catch (e) {
      return {"error": "Failed to leave room: $e"};
    }
  }

  /// Send a message to a room
  Future<Map<String, dynamic>> sendMessage(String roomId, String message, [Map<String, dynamic>? additionalData]) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }

    try {
      final data = {
        'room_id': roomId,
        'message': message,
        ...?additionalData, // Spread additional data if provided
      };

      _socket!.emit('send_message', data);
      
      return {"success": "Message sent successfully"};
      
    } catch (e) {
      return {"error": "Failed to send message: $e"};
    }
  }

  /// Broadcast a message to all connected clients
  Future<Map<String, dynamic>> broadcastMessage(String message, [Map<String, dynamic>? additionalData]) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }

    try {
      final data = {
        'message': message,
        ...?additionalData, // Spread additional data if provided
      };

      _socket!.emit('broadcast', data);
      
      return {"success": "Message broadcasted successfully"};
      
    } catch (e) {
      return {"error": "Failed to broadcast message: $e"};
    }
  }

  /// Emit a custom Socket.IO event with arbitrary payload
  Future<Map<String, dynamic>> sendCustomEvent(String eventName, Map<String, dynamic> data) async {
    if (_socket == null) {
      return {"error": "Socket not initialized"};
    }
    if (!_socket!.connected) {
      return {"error": "WebSocket not connected"};
    }
    try {
      // Auto-include user ID from login state
      final currentUserId = _getCurrentUserId();
      if (currentUserId.isNotEmpty) {
        data['user_id'] = currentUserId;
      }
      
      _socket!.emit(eventName, data);
      return {"success": true};
    } catch (e) {
      return {"error": "Failed to emit custom event: $e"};
    }
  }

  /// Get current connection status
  Map<String, dynamic> getStatus() {
      return {
        'isInitialized': _isInitialized,
      'connected': isConnected,
      'sessionId': _socket?.id,
      'error': null,
      'connectionTime': null,
      'lastActivity': null,
    };
  }

  /// Debug method to check room membership and connection status
  void logConnectionDebugInfo([String? context]) {
    // Debug logging functionality removed
  }

  /// Set up hook triggering logic - triggers hooks when WebSocket events occur
  void _setupHookTriggers() {
    try {
      final hooksManager = HooksManager();
      
      // Set up callback for room_closed events to trigger the hook
      eventManager.onEvent('room_closed', (data) {
        hooksManager.triggerHookWithData('room_closed', data);
      });
    } catch (e) {
      // Error setting up WebSocket hook triggers
    }
  }

  /// Dispose of the WebSocket manager
  void dispose() {
    try {
      _socket?.disconnect();
      _socket = null;
      // Token refresh is now handled by AuthManager
      _eventController.close();
      _connectionController.close();
      _messageController.close();
      _roomController.close();
      _errorController.close();
      _isInitialized = false;
    } catch (e) {
      // Error disposing WebSocket manager
    }
  }

  /// Get current user ID from login state
  String _getCurrentUserId() {
    try {
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      return loginState['userId']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }
} 