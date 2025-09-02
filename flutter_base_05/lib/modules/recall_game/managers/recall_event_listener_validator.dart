import 'dart:async';
import '../../../tools/logging/logger.dart';

import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/websockets/websocket_events.dart';
import 'recall_event_handler_callbacks.dart';

/// Event configuration class
class EventConfig {
  final Set<String> schema;
  final String? handlerMethod;
  
  const EventConfig({required this.schema, this.handlerMethod});
}

/// Recall Game Event Listener Validator
/// Ensures all incoming events follow the defined schema and validation rules
class RecallGameEventListenerValidator {
  static final Logger _log = Logger();
  static RecallGameEventListenerValidator? _instance;
  
  static RecallGameEventListenerValidator get instance {
    _instance ??= RecallGameEventListenerValidator._internal();
    return _instance!;
  }
  
  RecallGameEventListenerValidator._internal();
  

  bool _isListenerRegistered = false;
  bool _socketIOListenerRegistered = false;
  
  /// Centralized event configuration: schema + handler mapping
  static const Map<String, EventConfig> _eventConfigs = {
    // Events with handlers
    'recall_new_player_joined': EventConfig(
      schema: {'event_type', 'room_id', 'owner_id', 'joined_player', 'game_state', 'timestamp'},
      handlerMethod: 'handleRecallNewPlayerJoined',
    ),
    'recall_joined_games': EventConfig(
      schema: {'event_type', 'user_id', 'session_id', 'games', 'total_games', 'timestamp'},
      handlerMethod: 'handleRecallJoinedGames',
    ),
    'game_started': EventConfig(
      schema: {'game_id', 'game_state', 'timestamp', 'started_by', 'player_order', 'initial_hands'},
      handlerMethod: 'handleGameStarted',
    ),
    'turn_started': EventConfig(
      schema: {'game_id', 'game_state', 'player_id', 'player_status', 'turn_timeout', 'timestamp'},
      handlerMethod: 'handleTurnStarted',
    ),
    'game_state_updated': EventConfig(
      schema: {'game_id', 'game_state', 'round_number', 'current_player', 'current_player_status', 'round_status', 'timestamp', 'reason', 'changes'},
      handlerMethod: 'handleGameStateUpdated',
    ),
    'player_state_updated': EventConfig(
      schema: {'event_type', 'game_id', 'player_id', 'player_data', 'timestamp'},
      handlerMethod: 'handlePlayerStateUpdated',
    ),
    
    // Events without handlers (validation only)
    'game_joined': EventConfig(
      schema: {'game_id', 'player_id', 'player_name', 'game_state', 'player', 'room_id', 'room_name', 'is_owner', 'is_active'},
    ),
    'game_left': EventConfig(
      schema: {'game_id', 'player_id', 'reason', 'timestamp'},
    ),
    'player_joined': EventConfig(
      schema: {'game_id', 'player_id', 'player_name', 'player', 'players', 'timestamp', 'room_id'},
    ),
    'player_left': EventConfig(
      schema: {'game_id', 'player_id', 'player_name', 'reason', 'players', 'timestamp', 'room_id'},
    ),
    'game_phase_changed': EventConfig(
      schema: {'game_id', 'new_phase', 'current_player', 'timestamp'},
    ),
    'game_ended': EventConfig(
      schema: {'game_id', 'game_state', 'winner', 'scores', 'reason', 'timestamp', 'duration'},
    ),
    'turn_changed': EventConfig(
      schema: {'game_id', 'current_turn', 'previous_turn', 'turn_number', 'round_number', 'timestamp'},
    ),
    'card_played': EventConfig(
      schema: {'game_id', 'player_id', 'card', 'position', 'timestamp', 'is_out_of_turn', 'remaining_cards'},
    ),
    'card_drawn': EventConfig(
      schema: {'game_id', 'player_id', 'source', 'card', 'timestamp', 'remaining_deck', 'discard_top'},
    ),
    'replace_drawn_card': EventConfig(
      schema: {'game_id', 'player_id', 'card_index', 'timestamp'},
    ),
    'play_drawn_card': EventConfig(
      schema: {'game_id', 'player_id', 'timestamp'},
    ),
    'recall_called': EventConfig(
      schema: {'game_id', 'player_id', 'timestamp', 'scores', 'updated_game_state'},
    ),
    'recall_message': EventConfig(
      schema: {'scope', 'target_id', 'level', 'title', 'message', 'data', 'timestamp'},
    ),
    'error': EventConfig(
      schema: {'error', 'message', 'code', 'details', 'timestamp'},
    ),
    'connection_status': EventConfig(
      schema: {'status', 'session_id', 'error', 'timestamp'},
    ),
  };

  /// Initialize the event listener system
  void initialize() {
    // Register the main listener only once
    if (!_isListenerRegistered) {
      // Register the Socket.IO listener when WebSocket is connected
      _registerSocketIOListener();
      _isListenerRegistered = true;
      _log.info('📝 RecallGameEventListenerValidator initialized');
    }
  }
  
  /// Register the Socket.IO listener when WebSocket is connected
  void _registerSocketIOListener() {
    final wsManager = WebSocketManager.instance;
    
    // Use the core WebSocket system's connection logic - same as connection widget
    _log.info('🔌 Using core WebSocket connection monitoring for recall_game_event listener');
    
    // Check if WebSocket is already connected
    if (wsManager.isConnected && wsManager.eventListener != null) {
      _log.info('✅ WebSocket already connected, registering recall_game_event listener immediately');
      _registerListenerNow();
    } else {
      _log.info('⏳ WebSocket not connected yet, will register listener when connected');
      
      // Use the core WebSocket system's connection status stream - same as connection widget
      wsManager.connectionStatus.listen((event) {
        _log.info('🔌 Connection status event received: ${event.status}');
        
        if (event.status == ConnectionStatus.connected && !_socketIOListenerRegistered) {
          _log.info('🔌 WebSocket connected, registering recall_game_event listener');
          _registerListenerNow();
        }
      });
      
      // Also check periodically in case the connection status stream misses events
      _setupPeriodicConnectionCheck();
    }
  }
  
  /// Setup periodic connection check as fallback
  void _setupPeriodicConnectionCheck() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_socketIOListenerRegistered) {
        timer.cancel();
        return;
      }
      
      final wsManager = WebSocketManager.instance;
      if (wsManager.isConnected && wsManager.eventListener != null) {
        _log.info('🔌 Periodic check: WebSocket connected, registering recall_game_event listener');
        _registerListenerNow();
        timer.cancel();
      }
    });
  }
  
  /// Register the actual Socket.IO listeners for direct events
  void _registerListenerNow() {
    if (_socketIOListenerRegistered) return;
    
    final wsManager = WebSocketManager.instance;
    
    // Use the core WebSocket system's event listener to register for direct events
    if (wsManager.eventListener != null) {
      // Register listeners for all configured events
      final eventNames = _eventConfigs.keys.toList();
      
      for (final eventName in eventNames) {
        wsManager.eventListener!.registerCustomListener(eventName, (data) {
          _log.info('🎧 [DirectEvent] Raw event received: $eventName');
          _handleDirectEvent(eventName, data);
        });
      }
      
      _socketIOListenerRegistered = true;
      _log.info('📝 Registered Socket.IO listeners for ${eventNames.length} direct game events via core WebSocket system');
    } else {
      _log.error('❌ WebSocket event listener not available, cannot register direct game event listeners');
    }
  }
  
  /// Handle direct game events and route to RecallEventManager
  void _handleDirectEvent(String eventType, Map<String, dynamic> data) {
    _log.info('🎧 [DirectEvent] Processing: $eventType');
    
    try {
        // Validate event type
      if (!_eventConfigs.containsKey(eventType)) {
        _log.error('❌ [DirectEvent] Unknown game event type: $eventType');
          return;
        }

        // Validate event data against schema
      final validatedData = _validateEventData(eventType, data);
        if (validatedData == null) {
        _log.error('❌ [DirectEvent] Invalid data for game event: $eventType');
          return;
        }

        // Add minimal required context
        final eventPayload = {
        'event_type': eventType,
          'timestamp': DateTime.now().toIso8601String(),
          ...validatedData,
        };

        // Log the event
      _logEvent(eventType, eventPayload);

      // Route directly to RecallEventManager based on event type
      _routeEventToManager(eventType, eventPayload);

      } catch (e) {
      _log.error('❌ [DirectEvent] Error handling direct game event: $e');
    }
  }

  /// Route validated events directly to RecallEventManager methods
  void _routeEventToManager(String eventType, Map<String, dynamic> eventPayload) {
    final eventConfig = _eventConfigs[eventType];
    final handlerMethod = eventConfig?.handlerMethod;
    
    if (handlerMethod == null) {
      _log.info('ℹ️ [DirectEvent] No handler configured for event type: $eventType (validation only)');
      return;
    }
    
    try {
      switch (handlerMethod) {
        case 'handleRecallNewPlayerJoined':
          RecallEventHandlerCallbacks.handleRecallNewPlayerJoined(eventPayload);
          break;
        case 'handleRecallJoinedGames':
          RecallEventHandlerCallbacks.handleRecallJoinedGames(eventPayload);
          break;
        case 'handleGameStarted':
          RecallEventHandlerCallbacks.handleGameStarted(eventPayload);
          break;
        case 'handleTurnStarted':
          RecallEventHandlerCallbacks.handleTurnStarted(eventPayload);
          break;
        case 'handleGameStateUpdated':
          RecallEventHandlerCallbacks.handleGameStateUpdated(eventPayload);
          break;
        case 'handlePlayerStateUpdated':
          RecallEventHandlerCallbacks.handlePlayerStateUpdated(eventPayload);
          break;
        default:
          _log.warning('⚠️ [DirectEvent] Unknown handler method: $handlerMethod');
          return;
      }
      
      _log.info('✅ [DirectEvent] Successfully routed $eventType to $handlerMethod');
      
    } catch (e) {
      _log.error('❌ [DirectEvent] Error routing $eventType to $handlerMethod: $e');
    }
  }

  /// Validate event data against schema
  Map<String, dynamic>? _validateEventData(String eventType, Map<String, dynamic> data) {
    try {
      final eventConfig = _eventConfigs[eventType];
      if (eventConfig == null) {
        _log.error('❌ [VALIDATION] No schema found for event type: $eventType');
        return null;
      }
      
      final schema = eventConfig.schema;
      final validatedData = <String, dynamic>{};
      final missingFields = <String>[];

      // Check for required fields based on event type
      for (final field in schema) {
        if (data.containsKey(field)) {
          validatedData[field] = data[field];
        } else {
          missingFields.add(field);
        }
      }
      
      // Add metadata if present
      if (data.containsKey('metadata')) {
        validatedData['metadata'] = data['metadata'];
      }

      if (missingFields.isNotEmpty) {
        _log.warning('⚠️ [VALIDATION] Missing fields for $eventType: $missingFields');
      }
      
      _log.debug('✅ [VALIDATION] Validated $eventType: ${validatedData.length}/${schema.length} fields');
      return validatedData;

    } catch (e) {
      _log.error('❌ [VALIDATION] Error validating $eventType: $e');
      return null;
    }
  }

  /// Log validated event
  void _logEvent(String eventType, Map<String, dynamic> data) {
    _log.info('✅ [RecallGameEvent] $eventType');
    _log.debug('   Fields: ${data.keys.where((k) => k != 'timestamp').join(', ')}');
  }
}