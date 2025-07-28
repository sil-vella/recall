import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../tools/logging/logger.dart';
import 'websocket_events.dart';
import 'websocket_manager.dart';
import '../state_manager.dart';

/// WebSocket Event Manager - Centralized event handling for WebSocket operations
class WSEventManager {
  static final Logger _log = Logger();
  static final WSEventManager _instance = WSEventManager._internal();
  
  // WebSocket manager instance
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  
  // Event streams for different event types
  final StreamController<RoomEvent> _roomEventController = StreamController<RoomEvent>.broadcast();
  final StreamController<MessageEvent> _messageEventController = StreamController<MessageEvent>.broadcast();
  final StreamController<ConnectionStatusEvent> _connectionEventController = StreamController<ConnectionStatusEvent>.broadcast();
  final StreamController<SessionDataEvent> _sessionEventController = StreamController<SessionDataEvent>.broadcast();
  final StreamController<ErrorEvent> _errorEventController = StreamController<ErrorEvent>.broadcast();
  final StreamController<CustomEvent> _customEventController = StreamController<CustomEvent>.broadcast();
  
  // Event handlers map
  final Map<String, Function(Map<String, dynamic>)> _eventHandlers = {};
  
  // State tracking
  String? _currentRoomId;
  Map<String, dynamic>? _currentRoomInfo;
  Map<String, dynamic>? _sessionData;
  bool _isConnected = false;
  
  // Event callbacks
  final Map<String, List<Function(Map<String, dynamic>)>> _eventCallbacks = {};
  
  factory WSEventManager() => _instance;
  WSEventManager._internal();

  // Static getter for easy access
  static WSEventManager get instance {
    _log.info("🔍 WSEventManager.instance getter called");
    return _instance;
  }

  /// Initialize the event manager
  void initialize() {
    _log.info('🔌 Initializing WebSocket Event Manager');
    _setupEventListeners();
    _registerWithStateManager();
  }

  /// Register with StateManager
  void _registerWithStateManager() {
    final stateManager = StateManager();
    stateManager.registerModuleState("websocket", {
      "isConnected": _isConnected,
      "currentRoomId": _currentRoomId,
      "currentRoomInfo": _currentRoomInfo,
      "sessionData": _sessionData,
    });
    _log.info('✅ Registered with StateManager');
  }

  /// Set up event listeners for all WebSocket events
  void _setupEventListeners() {
    // Listen to WebSocket manager events
    _websocketManager.events.listen((event) {
      _handleIncomingEvent(event);
    });

    _websocketManager.connectionStatus.listen((event) {
      _handleConnectionEvent(event);
    });

    _websocketManager.messages.listen((event) {
      _handleMessageEvent(event);
    });

    _websocketManager.roomEvents.listen((event) {
      _handleRoomEvent(event);
    });

    _websocketManager.errors.listen((event) {
      _handleErrorEvent(event);
    });
  }

  /// Handle incoming WebSocket events
  void _handleIncomingEvent(WebSocketEvent event) {
    _log.info('📨 Received WebSocket event: ${event.runtimeType}');
    
    switch (event.runtimeType) {
      case ConnectionStatusEvent:
        _handleConnectionEvent(event as ConnectionStatusEvent);
        break;
      case SessionDataEvent:
        _handleSessionEvent(event as SessionDataEvent);
        break;
      case RoomEvent:
        _handleRoomEvent(event as RoomEvent);
        break;
      case MessageEvent:
        _handleMessageEvent(event as MessageEvent);
        break;
      case ErrorEvent:
        _handleErrorEvent(event as ErrorEvent);
        break;
      case CustomEvent:
        _handleCustomEvent(event as CustomEvent);
        break;
      default:
        _log.info('⚠️ Unknown event type: ${event.runtimeType}');
    }
  }

  /// Handle connection status events
  void _handleConnectionEvent(ConnectionStatusEvent event) {
    _log.info('🔌 Connection status: ${event.status}');
    _isConnected = event.status == ConnectionStatus.connected;
    _connectionEventController.add(event);
    
    // Update StateManager
    _updateStateManager();
    
    // Trigger connection callbacks
    _triggerCallbacks('connection', {
      'status': event.status.name,
      'sessionId': event.sessionId,
      'error': event.error,
    });
  }

  /// Handle session data events
  void _handleSessionEvent(SessionDataEvent event) {
    _log.info('📋 Session data updated');
    _sessionData = event.sessionData;
    _sessionEventController.add(event);
    
    // Update StateManager
    _updateStateManager();
    
    // Trigger session callbacks
    _triggerCallbacks('session', event.sessionData);
  }

  /// Handle room events
  void _handleRoomEvent(RoomEvent event) {
    _log.info('🏠 Room event: ${event.action} for room ${event.roomId}');
    
    switch (event.action) {
      case 'joined':
        _currentRoomId = event.roomId;
        _currentRoomInfo = event.roomData;
        _log.info('✅ User joined room: ${event.roomId}');
        break;
      case 'left':
        if (_currentRoomId == event.roomId) {
          _currentRoomId = null;
          _currentRoomInfo = null;
        }
        _log.info('🚪 User left room: ${event.roomId}');
        break;
      case 'created':
        _log.info('🏠 Room created: ${event.roomId}');
        // After room creation, the user is automatically joined
        // The room_joined event will handle setting current room
        break;
      default:
        _log.info('⚠️ Unknown room action: ${event.action}');
    }
    
    // Update StateManager
    _updateStateManager();
    
    _roomEventController.add(event);
    
    // Trigger room callbacks
    _triggerCallbacks('room', {
      'action': event.action,
      'roomId': event.roomId,
      'roomData': event.roomData,
    });
  }

  /// Handle message events
  void _handleMessageEvent(MessageEvent event) {
    _log.info('💬 Message received in room ${event.roomId}: ${event.message}');
    _messageEventController.add(event);
    
    // Trigger message callbacks
    _triggerCallbacks('message', {
      'roomId': event.roomId,
      'message': event.message,
      'sender': event.sender,
      'additionalData': event.additionalData,
    });
  }

  /// Handle error events
  void _handleErrorEvent(ErrorEvent event) {
    _log.error('🚨 Error event: ${event.error}');
    _errorEventController.add(event);
    
    // Trigger error callbacks
    _triggerCallbacks('error', {
      'error': event.error,
      'details': event.details,
    });
  }

  /// Handle custom events
  void _handleCustomEvent(CustomEvent event) {
    _log.info('📨 Custom event: ${event.eventName}');
    _customEventController.add(event);
    
    // Trigger custom event callbacks
    _triggerCallbacks(event.eventName, event.data);
  }

  /// Trigger callbacks for a specific event type
  void _triggerCallbacks(String eventType, Map<String, dynamic> data) {
    final callbacks = _eventCallbacks[eventType];
    if (callbacks != null) {
      for (final callback in callbacks) {
        try {
          callback(data);
        } catch (e) {
          _log.error('❌ Error in event callback for $eventType: $e');
        }
      }
    }
  }

  // ==================== PUBLIC API ====================

  /// Register a callback for a specific event type
  void onEvent(String eventType, Function(Map<String, dynamic>) callback) {
    if (!_eventCallbacks.containsKey(eventType)) {
      _eventCallbacks[eventType] = [];
    }
    _eventCallbacks[eventType]!.add(callback);
    _log.info('📝 Registered callback for event: $eventType');
  }

  /// Unregister a callback for a specific event type
  void offEvent(String eventType, Function(Map<String, dynamic>) callback) {
    final callbacks = _eventCallbacks[eventType];
    if (callbacks != null) {
      callbacks.remove(callback);
      _log.info('🗑️ Unregistered callback for event: $eventType');
    }
  }

  /// Register a one-time callback for a specific event type
  void onceEvent(String eventType, Function(Map<String, dynamic>) callback) {
    late Function(Map<String, dynamic>) wrappedCallback;
    wrappedCallback = (data) {
      callback(data);
      offEvent(eventType, wrappedCallback);
    };
    onEvent(eventType, wrappedCallback);
  }

  /// Trigger callbacks for a specific event type (public method)
  void triggerCallbacks(String eventType, Map<String, dynamic> data) {
    _triggerCallbacks(eventType, data);
  }

  // ==================== ROOM MANAGEMENT ====================

  /// Create a room
  Future<Map<String, dynamic>> createRoom(String userId, [Map<String, dynamic>? roomData]) async {
    _log.info('🏠 Creating room for user: $userId');
    
    try {
      final result = await _websocketManager.createRoom(userId, roomData);
      
      if (result['success'] != null) {
        _log.info('✅ Room created successfully');
        
        // The server will automatically join the user to the room
        // and send a 'room_joined' event, which will update our state
        return result;
      } else {
        _log.error('❌ Failed to create room: ${result['error']}');
        return result;
      }
    } catch (e) {
      _log.error('❌ Error creating room: $e');
      return {'error': 'Failed to create room: $e'};
    }
  }

  /// Join a room
  Future<Map<String, dynamic>> joinRoom(String roomId, String userId) async {
    _log.info('🚪 Joining room: $roomId for user: $userId');
    
    try {
      final result = await _websocketManager.joinRoom(roomId, userId);
      
      if (result['success'] != null) {
        _log.info('✅ Joined room successfully');
        return result;
      } else {
        _log.error('❌ Failed to join room: ${result['error']}');
        return result;
      }
    } catch (e) {
      _log.error('❌ Error joining room: $e');
      return {'error': 'Failed to join room: $e'};
    }
  }

  /// Leave a room
  Future<Map<String, dynamic>> leaveRoom(String roomId) async {
    _log.info('🚪 Leaving room: $roomId');
    
    try {
      final result = await _websocketManager.leaveRoom(roomId);
      
      if (result['success'] != null) {
        _log.info('✅ Left room successfully');
        return result;
      } else {
        _log.error('❌ Failed to leave room: ${result['error']}');
        return result;
      }
    } catch (e) {
      _log.error('❌ Error leaving room: $e');
      return {'error': 'Failed to leave room: $e'};
    }
  }

  /// Send a message to a room
  Future<Map<String, dynamic>> sendMessage(String roomId, String message) async {
    _log.info('💬 Sending message to room: $roomId');
    
    try {
      final result = await _websocketManager.sendMessage(roomId, message);
      
      if (result['success'] != null) {
        _log.info('✅ Message sent successfully');
        return result;
      } else {
        _log.error('❌ Failed to send message: ${result['error']}');
        return result;
      }
    } catch (e) {
      _log.error('❌ Error sending message: $e');
      return {'error': 'Failed to send message: $e'};
    }
  }

  /// Broadcast a message to all rooms
  Future<Map<String, dynamic>> broadcastMessage(String message) async {
    _log.info('📢 Broadcasting message: $message');
    
    try {
      final result = await _websocketManager.broadcastMessage(message);
      
      if (result['success'] != null) {
        _log.info('✅ Message broadcasted successfully');
        return result;
      } else {
        _log.error('❌ Failed to broadcast message: ${result['error']}');
        return result;
      }
    } catch (e) {
      _log.error('❌ Error broadcasting message: $e');
      return {'error': 'Failed to broadcast message: $e'};
    }
  }

  // ==================== STATE GETTERS ====================

  /// Get current room ID
  String? get currentRoomId => _currentRoomId;

  /// Get current room info
  Map<String, dynamic>? get currentRoomInfo => _currentRoomInfo;

  /// Get session data
  Map<String, dynamic>? get sessionData => _sessionData;

  /// Check if connected
  bool get isConnected => _isConnected;

  /// Check if user is in a specific room
  bool isInRoom(String roomId) => _currentRoomId == roomId;

  // ==================== EVENT STREAMS ====================

  /// Stream of room events
  Stream<RoomEvent> get roomEvents => _roomEventController.stream;

  /// Stream of message events
  Stream<MessageEvent> get messageEvents => _messageEventController.stream;

  /// Stream of connection events
  Stream<ConnectionStatusEvent> get connectionEvents => _connectionEventController.stream;

  /// Stream of session events
  Stream<SessionDataEvent> get sessionEvents => _sessionEventController.stream;

  /// Stream of error events
  Stream<ErrorEvent> get errorEvents => _errorEventController.stream;

  /// Stream of custom events
  Stream<CustomEvent> get customEvents => _customEventController.stream;

  // ==================== UTILITY METHODS ====================

  /// Update state manager with current state
  void _updateStateManager() {
    final stateManager = StateManager();
    stateManager.updateModuleState("websocket", {
      "isConnected": _isConnected,
      "currentRoomId": _currentRoomId,
      "currentRoomInfo": _currentRoomInfo,
      "sessionData": _sessionData,
    });
  }

  /// Clear all event callbacks
  void clearCallbacks() {
    _eventCallbacks.clear();
    _log.info('🗑️ Cleared all event callbacks');
  }

  /// Dispose of the event manager
  void dispose() {
    _roomEventController.close();
    _messageEventController.close();
    _connectionEventController.close();
    _sessionEventController.close();
    _errorEventController.close();
    _customEventController.close();
    clearCallbacks();
    _log.info('🛑 WebSocket Event Manager disposed');
  }
} 