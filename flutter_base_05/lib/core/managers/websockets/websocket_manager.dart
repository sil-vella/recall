import 'package:socket_io_client/socket_io_client.dart' as IO;
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

class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() {
    Logger().info("🔍 WebSocketManager factory called - returning singleton instance");
    return _instance;
  }
  WebSocketManager._internal() {
    Logger().info("🔍 WebSocketManager singleton instance created");
    // Register a remote log sink that emits logs over the socket when available
    Logger.registerSink((payload) {
      try {
        if (_socket != null && _socket!.connected) {
          final data = Map<String, dynamic>.from(payload);
          data['event'] = 'client_log';
          _socket!.emit('client_log', data);
        }
      } catch (_) {}
    });
  }

  static final Logger _log = Logger();
  
  IO.Socket? _socket;
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
  IO.Socket? get socket => _socket;
  bool get isInitialized => _isInitialized;
  
  // Event streams for UI
  Stream<WebSocketEvent> get events => _eventController.stream;
  Stream<ConnectionStatusEvent> get connectionStatus => _connectionController.stream;
  Stream<MessageEvent> get messages => _messageController.stream;
  Stream<RoomEvent> get roomEvents => _roomController.stream;
  Stream<ErrorEvent> get errors => _errorController.stream;
  
  // Static getter for easy access
  static WebSocketManager get instance {
    Logger().info("🔍 WebSocketManager.instance getter called");
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
      _log.info("🔍 Fixing tracked state: socket is connected but tracked state is false");
      _isConnected = true;
      _isConnecting = false; // We're no longer connecting
    }
    
    // If we have a socket but it's not connected, but we think we're connected, reset
    if (_socket != null && !socketConnected && _isConnected) {
      _log.info("🔍 Fixing tracked state: socket is not connected but tracked state is true");
      _isConnected = false;
    }
    
    final connected = _isConnected && socketConnected;
    _log.info("🔍 Connection check: tracked=$_isConnected, socket=$socketConnected, connecting=$_isConnecting, final=$connected, socket_id=${_socket?.id}");
    
    return connected;
  }

  /// Check if we're in the process of connecting
  bool get isConnecting => _isConnecting;

  /// Force refresh connection state (for debugging)
  void _refreshConnectionState() {
    final socketConnected = _socket?.connected ?? false;
    if (socketConnected != _isConnected) {
      _log.info("🔍 Refreshing connection state: socket=$socketConnected, tracked=$_isConnected");
      _isConnected = socketConnected;
    }
  }

  /// Initialize the WebSocket manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log.info("✅ WebSocket manager already initialized");
      return isConnected;
    }

    try {
      _log.info("🔄 Initializing WebSocket manager...");
      
      // Check if socket is already connected
      _log.info("🔍 Checking socket connection in initialize: socket=${_socket != null}, connected=${_socket?.connected ?? false}, tracked=$_isConnected");
      
      // Refresh connection state before checking
      _refreshConnectionState();
      
      if (_socket != null && _socket!.connected && _isConnected) {
        _log.info("✅ WebSocket socket is already connected");
        _isInitialized = true;
        return true;
      }
      
      // Get JWT token from login module for authentication
      final loginModule = _moduleManager.getModuleByType<LoginModule>();
      if (loginModule == null) {
        _log.error("❌ Login module not available for WebSocket authentication");
        return false;
      }
      
      // Check if user has valid JWT token
      final hasToken = await loginModule.hasValidToken();
      if (!hasToken) {
        _log.error("❌ No valid JWT token available for WebSocket authentication");
        return false;
      }
      
      // Get the JWT token
      final authToken = await loginModule.getCurrentToken();
      if (authToken == null) {
        _log.error("❌ Failed to retrieve JWT token for WebSocket authentication");
        return false;
      }
      
      _log.info("✅ Using JWT token for WebSocket authentication");
      
      // Create Socket.IO connection
      _log.info("🔍 Creating new Socket.IO connection...");
      _socket = IO.io(Config.wsUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'query': {
          'token': authToken,
          'client_id': 'flutter_app_${DateTime.now().millisecondsSinceEpoch}',
          'version': '1.0.0',
        },
        'auth': {
          'token': authToken,
        },
      });
      _log.info("🔍 Socket created: ${_socket != null}");
      
      // Initialize event manager
      eventManager.initialize();
      
      // Register WebSocket hooks
      _registerWebSocketHooks();
      
      // Initialize new centralized event listener and handler
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
      
      // Register all event listeners
      _eventListener!.registerAllListeners();
      
      // Token refresh is now handled by AuthManager
      // No need to setup token refresh here
      
      _isInitialized = true;
      _log.info("✅ WebSocket manager initialized successfully");
      return true;
      
    } catch (e) {
      _log.error("❌ Error initializing WebSocket manager: $e");
      return false;
    }
  }

  /// ✅ Setup state listener for queued token refreshes
  void _setupStateListener() {
    final stateManager = StateManager();
    // Token refresh is now handled by AuthManager
    // No need to setup state listener here
    _log.info("✅ State listener setup for queued token refreshes");
  }

  /// Set up Socket.IO event handlers
  void _setupEventHandlers() {
    if (_socket == null) return;
    
    // Use 'connect' event instead of onConnect to avoid conflicts with one-time listeners
    _socket!.on('connect', (_) {
      _log.info("✅ WebSocket connected successfully");
      _log.info("✅ Session ID: ${_socket!.id}");
      _log.info("🔍 Socket state after connect: connected=${_socket!.connected}");
      
      // Update our tracked connection state and use validated system
      _isConnected = true;
      _isConnecting = false; // Reset connecting state
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: true,
        sessionData: null,
      );
      _log.info("🔍 Updated tracked connection state: $_isConnected");

      // Drain any pending remote logs accumulated before transport was ready
      final pending = Logger.drainPending();
      if (pending.isNotEmpty) {
        try {
          for (final p in pending) {
            final data = Map<String, dynamic>.from(p);
            data['event'] = 'client_log';
            _socket!.emit('client_log', data);
          }
          _log.info("📤 Flushed ${pending.length} buffered frontend logs to backend");
        } catch (e) {
          _log.error("❌ Failed flushing buffered logs: $e");
        }
      }
      
      // Emit connection event
      final event = ConnectionStatusEvent(
        status: ConnectionStatus.connected,
        sessionId: _socket!.id,
      );
      _connectionController.add(event);
      _eventController.add(event);
      
      // Trigger websocket_connected hook for modules that need to set up listeners
      _log.info("🔌 Triggering websocket_connected hook for modules...");
      HooksManager().triggerHook('websocket_connected');
      _log.info("✅ websocket_connected hook triggered successfully");
      
      // Events are handled through the stream system, not direct handlers
    });

    _socket!.onDisconnect((_) {
      _log.info("❌ WebSocket disconnected");
      _log.info("🔍 Socket state after disconnect: connected=${_socket!.connected}");
      
      // Update our tracked connection state and use validated system
      _isConnected = false;
      WebSocketStateHelpers.updateConnectionStatus(
        isConnected: false,
      );
      
      // Emit disconnection event
      final event = ConnectionStatusEvent(
        status: ConnectionStatus.disconnected,
      );
      _connectionController.add(event);
      _eventController.add(event);
      
      // Events are handled through the stream system, not direct handlers
    });

    // Use 'connect_error' event instead of onConnectError to avoid conflicts
    _socket!.on('connect_error', (error) {
      _log.error("🚨 WebSocket connection error: $error");
      
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
      _log.info("📋 Received session data from WebSocket server");
      
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
      _log.info("🏠 Successfully joined room: $data");
      
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
      _log.info("🏠 Join room success: $data");
      
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
      _log.error("🚨 Failed to join room: $data");
      
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
      _log.info("🏠 Successfully created room");
      
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
      _log.info("🏠 Room created: $data");
      
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
      _log.error("🚨 Failed to create room: $data");
      
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
      _log.info("✅ Successfully left room: $data");
      
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
      _log.error("🚨 Failed to leave room: $data");
      
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
      _log.info("💬 Received message: $data");
      
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
      _log.error("🚨 WebSocket error: $data");
      
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
    _log.info("🔍 Checking if socket is already connected...");
    
    // Refresh connection state before checking
    _refreshConnectionState();
    
    if (isConnected) {
      _log.info("✅ WebSocket socket is already connected");
      return true;
    }

    // Check if we're already connecting
    if (_isConnecting) {
      _log.info("🔄 WebSocket is already connecting, waiting...");
      return false;
    }
    
    _log.info("🔍 Socket not connected, proceeding with new connection...");
    _log.info("🔍 Connection state: tracked=$_isConnected, socket=${_socket?.connected ?? false}");

    try {
      _log.info("🔄 Connecting to WebSocket server...");
      
      // Set connecting state
      _isConnecting = true;
      
      if (_socket == null) {
        _log.error("❌ Socket not initialized");
        _isConnecting = false;
        return false;
      }
      
      // Emit connecting event
      final connectingEvent = ConnectionStatusEvent(
        status: ConnectionStatus.connecting,
      );
      _connectionController.add(connectingEvent);
      _eventController.add(connectingEvent);
      
      // Create a completer to wait for the connection event
      final completer = Completer<bool>();
      
      // Set up a one-time listener for the connect event
      void onConnect(dynamic _) {
        _log.info("✅ WebSocket connected successfully");
        _log.info("✅ Session ID: ${_socket!.id}");
        
        // Update our tracked connection state
        _isConnected = true;
        _isConnecting = false; // Reset connecting state
        
        completer.complete(true);
      }
      
      // Set up a one-time listener for connection errors
      void onConnectError(dynamic error) {
        _log.error("❌ WebSocket connection error: $error");
        
        // Update our tracked connection state
        _isConnected = false;
        _isConnecting = false;
        
        completer.complete(false);
      }
      
      // Add one-time event listeners (these will be removed after use)
      _socket!.once('connect', onConnect);
      _socket!.once('connect_error', onConnectError);
      
      // Start connection
      _socket!.connect();
      
      // Wait for connection with timeout
      try {
        final result = await completer.future.timeout(
          Duration(seconds: Config.websocketTimeout),
          onTimeout: () {
            _log.error("❌ WebSocket connection timeout");
            _isConnecting = false; // Reset connecting state on timeout
            return false;
          },
        );
        
        return result;
      } catch (e) {
        _log.error("❌ WebSocket connection exception: $e");
        _isConnecting = false; // Reset connecting state on exception
        return false;
      }
      
    } catch (e) {
      _log.error("❌ Error connecting to WebSocket: $e");
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
      
      _log.info("🔌 WebSocket disconnected");
    } catch (e) {
      _log.error("❌ Error disconnecting WebSocket: $e");
    }
  }

  /// Create a room
  Future<Map<String, dynamic>> createRoom(String userId, [Map<String, dynamic>? roomData]) async {
    if (_socket == null) {
      _log.error("❌ Cannot create room: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      _log.error("❌ Cannot create room: WebSocket not connected");
      return {"error": "WebSocket not connected"};
    }

    try {
      _log.info("🏠 Creating room for user: $userId");
      
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
      _log.error("❌ Error creating room: $e");
      return {"error": "Failed to create room: $e"};
    }
  }

  /// Join a room
  Future<Map<String, dynamic>> joinRoom(String roomId, String userId) async {
    if (_socket == null) {
      _log.error("❌ Cannot join room: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      _log.error("❌ Cannot join room: WebSocket not connected");
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
      _log.error("❌ Error joining room: $e");
      return {"error": "Failed to join room: $e"};
    }
  }

  /// Leave a room
  Future<Map<String, dynamic>> leaveRoom(String roomId) async {
    if (_socket == null) {
      _log.error("❌ Cannot leave room: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      _log.error("❌ Cannot leave room: WebSocket not connected");
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
      _log.error("❌ Error leaving room: $e");
      return {"error": "Failed to leave room: $e"};
    }
  }

  /// Send a message to a room
  Future<Map<String, dynamic>> sendMessage(String roomId, String message, [Map<String, dynamic>? additionalData]) async {
    if (_socket == null) {
      _log.error("❌ Cannot send message: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      _log.error("❌ Cannot send message: WebSocket not connected");
      return {"error": "WebSocket not connected"};
    }

    try {
      _log.info("💬 Sending message to room: $roomId");
      
      final data = {
        'room_id': roomId,
        'message': message,
        ...?additionalData, // Spread additional data if provided
      };

      _socket!.emit('send_message', data);
      
      return {"success": "Message sent successfully"};
      
    } catch (e) {
      _log.error("❌ Error sending message: $e");
      return {"error": "Failed to send message: $e"};
    }
  }

  /// Broadcast a message to all connected clients
  Future<Map<String, dynamic>> broadcastMessage(String message, [Map<String, dynamic>? additionalData]) async {
    if (_socket == null) {
      _log.error("❌ Cannot broadcast message: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    
    // Check if socket is actually connected
    if (!_socket!.connected) {
      _log.error("❌ Cannot broadcast message: WebSocket not connected");
      return {"error": "WebSocket not connected"};
    }

    try {
      _log.info("📢 Broadcasting message to all clients");
      
      final data = {
        'message': message,
        ...?additionalData, // Spread additional data if provided
      };

      _socket!.emit('broadcast', data);
      
      return {"success": "Message broadcasted successfully"};
      
    } catch (e) {
      _log.error("❌ Error broadcasting message: $e");
      return {"error": "Failed to broadcast message: $e"};
    }
  }

  /// Emit a custom Socket.IO event with arbitrary payload
  Future<Map<String, dynamic>> sendCustomEvent(String eventName, Map<String, dynamic> data) async {
    if (_socket == null) {
      _log.error("❌ Cannot send custom event: Socket not initialized");
      return {"error": "Socket not initialized"};
    }
    if (!_socket!.connected) {
      _log.error("❌ Cannot send custom event: WebSocket not connected");
      return {"error": "WebSocket not connected"};
    }
    try {
      _log.info("📡 Emitting custom event '$eventName'");
      _socket!.emit(eventName, data);
      return {"success": true};
    } catch (e) {
      _log.error("❌ Error emitting custom event '$eventName': $e");
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

  /// Register WebSocket hooks with HooksManager
  void _registerWebSocketHooks() {
    try {
      final hooksManager = HooksManager();
      
      // Register room_closed hook that will be triggered by WebSocket events
      _log.info("🎣 Registering WebSocket hooks...");
      
      // Set up callback for room_closed events to trigger the hook
      eventManager.onEvent('room_closed', (data) {
        _log.info("🎣 Triggering room_closed hook with data: $data");
        hooksManager.triggerHookWithData('room_closed', data);
      });
      
      _log.info("✅ WebSocket hooks registered successfully");
    } catch (e) {
      _log.error("❌ Error registering WebSocket hooks: $e");
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
      
      _log.info("🗑️ WebSocket manager disposed");
    } catch (e) {
      _log.error("❌ Error disposing WebSocket manager: $e");
    }
  }
} 