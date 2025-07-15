import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../state_manager.dart';
import '../module_manager.dart';
import '../../../tools/logging/logger.dart';
import 'ws_event_handler.dart';

/// WebSocket Event Listener
/// Centralized Socket.IO event listener registration and management
class WSEventListener {
  final IO.Socket? _socket;
  final WSEventHandler _eventHandler;
  final StateManager _stateManager;
  final ModuleManager _moduleManager;
  final Logger _log;

  WSEventListener({
    required IO.Socket? socket,
    required WSEventHandler eventHandler,
    required StateManager stateManager,
    required ModuleManager moduleManager,
  })  : _socket = socket,
        _eventHandler = eventHandler,
        _stateManager = stateManager,
        _moduleManager = moduleManager,
        _log = Logger();

  /// Register all Socket.IO event listeners
  void registerAllListeners() {
    _log.info("🔧 Registering all WebSocket event listeners...");

    // Connection events
    _registerConnectListener();
    _registerDisconnectListener();
    _registerConnectErrorListener();

    // Session events
    _registerSessionDataListener();

    // Room events
    _registerRoomJoinedListener();
    _registerJoinRoomSuccessListener();
    _registerJoinRoomErrorListener();
    _registerCreateRoomSuccessListener();
    _registerRoomCreatedListener();
    _registerCreateRoomErrorListener();
    _registerLeaveRoomSuccessListener();
    _registerLeaveRoomErrorListener();

    // Message events
    _registerMessageListener();
    _registerErrorListener();

    _log.info("✅ All WebSocket event listeners registered successfully");
  }

  /// Register connection event listener
  void _registerConnectListener() {
    _socket?.on('connect', (data) {
      _log.info("🔍 [CONNECT] Connection event received");
      _eventHandler.handleConnect(data);
    });
  }

  /// Register disconnect event listener
  void _registerDisconnectListener() {
    _socket?.on('disconnect', (data) {
      _log.info("🔍 [DISCONNECT] Disconnection event received");
      _eventHandler.handleDisconnect(data);
    });
  }

  /// Register connection error listener
  void _registerConnectErrorListener() {
    _socket?.on('connect_error', (data) {
      _log.info("🔍 [CONNECT_ERROR] Connection error event received");
      _eventHandler.handleConnectError(data);
    });
  }

  /// Register session data listener
  void _registerSessionDataListener() {
    _socket?.on('session_data', (data) {
      _log.info("🔍 [SESSION_DATA] Session data event received");
      _eventHandler.handleSessionData(data);
    });
  }

  /// Register room joined listener
  void _registerRoomJoinedListener() {
    _socket?.on('room_joined', (data) {
      _log.info("🔍 [ROOM_JOINED] Room joined event received");
      _eventHandler.handleRoomJoined(data);
    });
  }

  /// Register join room success listener
  void _registerJoinRoomSuccessListener() {
    _socket?.on('join_room_success', (data) {
      _log.info("🔍 [JOIN_ROOM_SUCCESS] Join room success event received");
      _eventHandler.handleJoinRoomSuccess(data);
    });
  }

  /// Register join room error listener
  void _registerJoinRoomErrorListener() {
    _socket?.on('join_room_error', (data) {
      _log.info("🔍 [JOIN_ROOM_ERROR] Join room error event received");
      _eventHandler.handleJoinRoomError(data);
    });
  }

  /// Register create room success listener
  void _registerCreateRoomSuccessListener() {
    _socket?.on('create_room_success', (data) {
      _log.info("🔍 [CREATE_ROOM_SUCCESS] Create room success event received");
      _eventHandler.handleCreateRoomSuccess(data);
    });
  }

  /// Register room created listener
  void _registerRoomCreatedListener() {
    _socket?.on('room_created', (data) {
      _log.info("🔍 [ROOM_CREATED] Room created event received");
      _eventHandler.handleRoomCreated(data);
    });
  }

  /// Register create room error listener
  void _registerCreateRoomErrorListener() {
    _socket?.on('create_room_error', (data) {
      _log.info("🔍 [CREATE_ROOM_ERROR] Create room error event received");
      _eventHandler.handleCreateRoomError(data);
    });
  }

  /// Register leave room success listener
  void _registerLeaveRoomSuccessListener() {
    _socket?.on('leave_room_success', (data) {
      _log.info("🔍 [LEAVE_ROOM_SUCCESS] Leave room success event received");
      _eventHandler.handleLeaveRoomSuccess(data);
    });
  }

  /// Register leave room error listener
  void _registerLeaveRoomErrorListener() {
    _socket?.on('leave_room_error', (data) {
      _log.info("🔍 [LEAVE_ROOM_ERROR] Leave room error event received");
      _eventHandler.handleLeaveRoomError(data);
    });
  }

  /// Register message listener
  void _registerMessageListener() {
    _socket?.on('message', (data) {
      _log.info("🔍 [MESSAGE] Message event received");
      _eventHandler.handleMessage(data);
    });
  }

  /// Register error listener
  void _registerErrorListener() {
    _socket?.on('error', (data) {
      _log.info("🔍 [ERROR] Error event received");
      _eventHandler.handleError(data);
    });
  }

  /// Register a custom event listener
  void registerCustomListener(String eventName, Function(dynamic) handler) {
    _socket?.on(eventName, (data) {
      _log.info("🔍 [CUSTOM] Custom event '$eventName' received");
      handler(data);
    });
    _log.info("✅ Custom event listener registered for: $eventName");
  }

  /// Unregister all listeners
  void unregisterAllListeners() {
    _socket?.off('connect');
    _socket?.off('disconnect');
    _socket?.off('connect_error');
    _socket?.off('session_data');
    _socket?.off('room_joined');
    _socket?.off('join_room_success');
    _socket?.off('join_room_error');
    _socket?.off('create_room_success');
    _socket?.off('room_created');
    _socket?.off('create_room_error');
    _socket?.off('leave_room_success');
    _socket?.off('leave_room_error');
    _socket?.off('message');
    _socket?.off('error');
    
    _log.info("✅ All WebSocket event listeners unregistered");
  }

  /// Unregister a specific listener
  void unregisterListener(String eventName) {
    _socket?.off(eventName);
    _log.info("✅ Unregistered event listener for: $eventName");
  }
} 