import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../state_manager.dart';
import '../auth_manager.dart';
import '../../../tools/logging/logger.dart';
import '../../models/websocket_events.dart';
import 'ws_event_manager.dart';

/// WebSocket Event Handler
/// Centralized event processing logic for all WebSocket events
class WSEventHandler {
  final IO.Socket? _socket;
  final WSEventManager _eventManager;
  final StateManager _stateManager;
  final AuthManager _authManager;
  final Logger _log;

  WSEventHandler({
    required IO.Socket? socket,
    required WSEventManager eventManager,
    required StateManager stateManager,
    required AuthManager authManager,
  })  : _socket = socket,
        _eventManager = eventManager,
        _stateManager = stateManager,
        _authManager = authManager,
        _log = Logger();

  /// Handle connection event
  void handleConnect(dynamic data) {
    _log.info("🔧 [HANDLER-CONNECT] Handling connection event");
    
    try {
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'currentRoomId': null,
        'currentRoomInfo': null,
        'sessionData': data,
      });
      
      _log.info("✅ Connection handled successfully");
    } catch (e) {
      _log.error("❌ Error handling connection: $e");
    }
  }

  /// Handle disconnection event
  void handleDisconnect(dynamic data) {
    _log.info("🔧 [HANDLER-DISCONNECT] Handling disconnection event");
    
    try {
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': false,
        'currentRoomId': null,
        'currentRoomInfo': null,
        'sessionData': null,
      });
      
      _log.info("✅ Disconnection handled successfully");
    } catch (e) {
      _log.error("❌ Error handling disconnection: $e");
    }
  }

  /// Handle connection error event
  void handleConnectError(dynamic data) {
    _log.info("🔧 [HANDLER-CONNECT_ERROR] Handling connection error event");
    
    try {
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': false,
        'currentRoomId': null,
        'currentRoomInfo': null,
        'sessionData': null,
        'error': data.toString(),
      });
      
      _log.info("✅ Connection error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling connection error: $e");
    }
  }

  /// Handle session data event
  void handleSessionData(dynamic data) {
    _log.info("🔧 [HANDLER-SESSION_DATA] Handling session data event");
    
    try {
      // Update state with session data
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'sessionData': data,
      });
      
      _log.info("✅ Session data handled successfully");
    } catch (e) {
      _log.error("❌ Error handling session data: $e");
    }
  }

  /// Handle room joined event
  void handleRoomJoined(dynamic data) {
    _log.info("🔧 [HANDLER-ROOM_JOINED] Handling room joined event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;
      
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'currentRoomId': roomId,
        'currentRoomInfo': roomData,
      });
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_joined', data);
      _eventManager.triggerCallbacks('join_room_success', data);
      
      _log.info("✅ Room joined handled successfully");
    } catch (e) {
      _log.error("❌ Error handling room joined: $e");
    }
  }

  /// Handle join room success event
  void handleJoinRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-JOIN_ROOM_SUCCESS] Handling join room success event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;
      
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'currentRoomId': roomId,
        'currentRoomInfo': roomData,
      });
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'joined',
        'roomId': roomId,
        'roomData': roomData,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('join_room_success', data);
      
      _log.info("✅ Join room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling join room success: $e");
    }
  }

  /// Handle join room error event
  void handleJoinRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-JOIN_ROOM_ERROR] Handling join room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to join room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('join_room_error', data);
      
      _log.info("✅ Join room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling join room error: $e");
    }
  }

  /// Handle create room success event
  void handleCreateRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-CREATE_ROOM_SUCCESS] Handling create room success event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;
      
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'currentRoomId': roomId,
        'currentRoomInfo': roomData,
      });
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'created',
        'roomId': roomId,
        'roomData': roomData,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('create_room_success', data);
      _eventManager.triggerCallbacks('room_created', data);
      
      _log.info("✅ Create room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling create room success: $e");
    }
  }

  /// Handle room created event
  void handleRoomCreated(dynamic data) {
    _log.info("🔧 [HANDLER-ROOM_CREATED] Handling room created event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final roomData = data;
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'created',
        'roomId': roomId,
        'roomData': roomData,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('room_created', data);
      
      _log.info("✅ Room created handled successfully");
    } catch (e) {
      _log.error("❌ Error handling room created: $e");
    }
  }

  /// Handle create room error event
  void handleCreateRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-CREATE_ROOM_ERROR] Handling create room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to create room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('create_room_error', data);
      
      _log.info("✅ Create room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling create room error: $e");
    }
  }

  /// Handle leave room success event
  void handleLeaveRoomSuccess(dynamic data) {
    _log.info("🔧 [HANDLER-LEAVE_ROOM_SUCCESS] Handling leave room success event");
    
    try {
      final roomId = data['room_id'] ?? '';
      
      // Update state
      _stateManager.updateModuleState('websocket', {
        'isConnected': true,
        'currentRoomId': null,
        'currentRoomInfo': null,
      });
      
      // Trigger event callbacks for room management screen
      _eventManager.triggerCallbacks('room', {
        'action': 'left',
        'roomId': roomId,
        'roomData': data,
      });
      
      // Trigger specific event callbacks
      _eventManager.triggerCallbacks('leave_room_success', data);
      
      _log.info("✅ Leave room success handled successfully");
    } catch (e) {
      _log.error("❌ Error handling leave room success: $e");
    }
  }

  /// Handle leave room error event
  void handleLeaveRoomError(dynamic data) {
    _log.info("🔧 [HANDLER-LEAVE_ROOM_ERROR] Handling leave room error event");
    
    try {
      // Trigger error callbacks
      _eventManager.triggerCallbacks('error', {
        'error': 'Failed to leave room',
        'details': data.toString(),
      });
      
      // Trigger specific error callbacks
      _eventManager.triggerCallbacks('leave_room_error', data);
      
      _log.info("✅ Leave room error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling leave room error: $e");
    }
  }

  /// Handle message event
  void handleMessage(dynamic data) {
    _log.info("🔧 [HANDLER-MESSAGE] Handling message event");
    
    try {
      final roomId = data['room_id'] ?? '';
      final message = data['message'] ?? '';
      final sender = data['sender'] ?? 'unknown';
      
      _log.info("✅ Message handled successfully");
    } catch (e) {
      _log.error("❌ Error handling message: $e");
    }
  }

  /// Handle error event
  void handleError(dynamic data) {
    _log.info("🔧 [HANDLER-ERROR] Handling error event");
    
    try {
      _log.info("✅ Error handled successfully");
    } catch (e) {
      _log.error("❌ Error handling error event: $e");
    }
  }

  /// Handle unified event (for custom events)
  void handleUnifiedEvent(String eventName, dynamic data) {
    _log.info("🔧 [HANDLER-UNIFIED] Handling unified event: $eventName");
    
    try {
      // Route to appropriate handler based on event name
      switch (eventName) {
        case 'connect':
          handleConnect(data);
          break;
        case 'disconnect':
          handleDisconnect(data);
          break;
        case 'connect_error':
          handleConnectError(data);
          break;
        case 'session_data':
          handleSessionData(data);
          break;
        case 'room_joined':
          handleRoomJoined(data);
          break;
        case 'join_room_success':
          handleJoinRoomSuccess(data);
          break;
        case 'join_room_error':
          handleJoinRoomError(data);
          break;
        case 'create_room_success':
          handleCreateRoomSuccess(data);
          break;
        case 'room_created':
          handleRoomCreated(data);
          break;
        case 'create_room_error':
          handleCreateRoomError(data);
          break;
        case 'leave_room_success':
          handleLeaveRoomSuccess(data);
          break;
        case 'leave_room_error':
          handleLeaveRoomError(data);
          break;
        case 'message':
          handleMessage(data);
          break;
        case 'error':
          handleError(data);
          break;
        default:
          _log.info("⚠️ Unknown event type: $eventName");
          break;
      }
    } catch (e) {
      _log.error("❌ Error in unified event handler: $e");
    }
  }
} 