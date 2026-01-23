import 'dart:async';

import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/websockets/websocket_events.dart';
import '../../../tools/logging/logger.dart';
import '../../dutch_game/managers/dutch_event_handler_callbacks.dart';

/// Event configuration class
class EventConfig {
  final Set<String> schema;
  final String? handlerMethod;
  
  const EventConfig({required this.schema, this.handlerMethod});
}

/// Dutch Game Event Listener Validator
/// Ensures all incoming events follow the defined schema and validation rules
class DutchGameEventListenerValidator {
  static const bool LOGGING_SWITCH = false; // Enabled for final round debugging
  static DutchGameEventListenerValidator? _instance;
  
  static DutchGameEventListenerValidator get instance {
    _instance ??= DutchGameEventListenerValidator._internal();
    return _instance!;
  }
  
  final Logger _logger = Logger();
  
  DutchGameEventListenerValidator._internal();
  

  bool _isListenerRegistered = false;
  bool _socketIOListenerRegistered = false;
  
  /// Centralized event configuration: schema + handler mapping
  static const Map<String, EventConfig> _eventConfigs = {
    // Events with handlers
    'dutch_new_player_joined': EventConfig(
      schema: {'event_type', 'room_id', 'owner_id', 'joined_player', 'game_state', 'timestamp'},
      handlerMethod: 'handleDutchNewPlayerJoined',
    ),
    'dutch_joined_games': EventConfig(
      schema: {'event_type', 'user_id', 'session_id', 'games', 'total_games', 'timestamp'},
      handlerMethod: 'handleDutchJoinedGames',
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
      schema: {'game_id', 'game_state', 'owner_id', 'round_number', 'current_player', 'current_player_status', 'round_status', 'timestamp', 'reason', 'changes', 'winners'},
      handlerMethod: 'handleGameStateUpdated',
    ),
    'game_state_partial_update': EventConfig(
      schema: {'game_id', 'changed_properties', 'partial_game_state', 'timestamp', 'winners'},
      handlerMethod: 'handleGameStatePartialUpdate',
    ),
    'player_state_updated': EventConfig(
      schema: {'event_type', 'game_id', 'player_id', 'player_data', 'timestamp'},
      handlerMethod: 'handlePlayerStateUpdated',
    ),
    'dutch_error': EventConfig(
      schema: {'message'},
      handlerMethod: 'handleDutchError',
    ),
    
    // Events without handlers (validation only)
    'game_joined': EventConfig(
      schema: {'game_id', 'player_id', 'player_name', 'game_state', 'player', 'room_id', 'is_owner', 'is_active'},
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
      schema: {'game_id', 'game_state', 'winner', 'winners', 'scores', 'reason', 'timestamp', 'duration'},
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
    'dutch_called': EventConfig(
      schema: {'game_id', 'player_id', 'timestamp', 'scores', 'updated_game_state'},
    ),
    'jack_swap': EventConfig(
      schema: {'game_id', 'player_id', 'first_card_id', 'first_player_id', 'second_card_id', 'second_player_id', 'timestamp'},
    ),
    'queen_peek': EventConfig(
      schema: {'game_id', 'player_id', 'card_id', 'ownerId', 'timestamp'},
    ),
    'completed_initial_peek': EventConfig(
      schema: {'game_id', 'player_id', 'timestamp'},
    ),
    'dutch_message': EventConfig(
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
    }
  }
  
  /// Register the Socket.IO listener when WebSocket is connected
  void _registerSocketIOListener() {
    final wsManager = WebSocketManager.instance;
    
    // Check if WebSocket is already connected
    if (wsManager.isConnected && wsManager.eventListener != null) {
      _registerListenerNow();
    } else {
      // Use the core WebSocket system's connection status stream - same as connection widget
      wsManager.connectionStatus.listen((event) {
        if (event.status == ConnectionStatus.connected && !_socketIOListenerRegistered) {
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
          _handleDirectEvent(eventName, data);
        });
      }
      
      _socketIOListenerRegistered = true;
    }
  }
  
  /// Handle direct game events and route to DutchEventManager
  void _handleDirectEvent(String eventType, Map<String, dynamic> data) {
    try {
        // Log incoming event
        if (LOGGING_SWITCH) {
          _logger.info("📥 Received event: $eventType with data: $data");
        }
        
        // Validate event type
      if (!_eventConfigs.containsKey(eventType)) {
          if (LOGGING_SWITCH) {
            _logger.warning("❌ Unknown event type: $eventType");
          }
          return;
        }

        // Validate event data against schema
      final validatedData = _validateEventData(eventType, data);
        if (validatedData == null) {
          return;
        }

        // Add minimal required context
        final eventPayload = {
        'event_type': eventType,
          'timestamp': DateTime.now().toIso8601String(),
          ...validatedData,
        };

      // Route directly to DutchEventManager based on event type
      if (LOGGING_SWITCH) {
        _logger.info("🔄 Routing event: $eventType to manager");
      }
      _routeEventToManager(eventType, eventPayload);
      if (LOGGING_SWITCH) {
        _logger.info("✅ Successfully processed event: $eventType");
      }

      } catch (e) {
    }
  }

  /// Route validated events directly to DutchEventManager methods
  void _routeEventToManager(String eventType, Map<String, dynamic> eventPayload) {
    final eventConfig = _eventConfigs[eventType];
    final handlerMethod = eventConfig?.handlerMethod;
    
    if (LOGGING_SWITCH) {
      _logger.info("🎯 Calling handler method: $handlerMethod for event: $eventType");
    }
    
    if (handlerMethod == null) {
      return;
    }
    
    try {
      switch (handlerMethod) {
        case 'handleDutchNewPlayerJoined':
          DutchEventHandlerCallbacks.handleDutchNewPlayerJoined(eventPayload);
          break;
        case 'handleDutchJoinedGames':
          DutchEventHandlerCallbacks.handleDutchJoinedGames(eventPayload);
          break;
        case 'handleGameStarted':
          DutchEventHandlerCallbacks.handleGameStarted(eventPayload);
          break;
        case 'handleTurnStarted':
          DutchEventHandlerCallbacks.handleTurnStarted(eventPayload);
          break;
        case 'handleGameStateUpdated':
          DutchEventHandlerCallbacks.handleGameStateUpdated(eventPayload);
          break;
        case 'handleGameStatePartialUpdate':
          DutchEventHandlerCallbacks.handleGameStatePartialUpdate(eventPayload);
          break;
        case 'handlePlayerStateUpdated':
          DutchEventHandlerCallbacks.handlePlayerStateUpdated(eventPayload);
          break;
        case 'handleQueenPeekResult':
          DutchEventHandlerCallbacks.handleQueenPeekResult(eventPayload);
          break;
        case 'handleDutchError':
          DutchEventHandlerCallbacks.handleDutchError(eventPayload);
          break;
        default:
          return;
      }
      
    } catch (e) {
    }
  }

  /// Validate event data against schema
  Map<String, dynamic>? _validateEventData(String eventType, Map<String, dynamic> data) {
    try {
      final eventConfig = _eventConfigs[eventType];
      if (eventConfig == null) {
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

      return validatedData;

    } catch (e) {
      return null;
    }
  }

}