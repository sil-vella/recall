import 'dart:async';
import '../../../tools/logging/logger.dart';
import '../../../core/managers/websockets/ws_event_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/websockets/websocket_events.dart';
import 'recall_game_helpers.dart';

/// Recall Game Event Listener Validator
/// Ensures all incoming events follow the defined schema and validation rules
class RecallGameEventListenerValidator {
  static final Logger _log = Logger();
  static final WSEventManager _wsEvents = WSEventManager.instance;
  static RecallGameEventListenerValidator? _instance;
  
  static RecallGameEventListenerValidator get instance {
    _instance ??= RecallGameEventListenerValidator._internal();
    return _instance!;
  }
  
  RecallGameEventListenerValidator._internal();
  
  // Track registered callbacks for each event type
  final Map<String, List<Function(Map<String, dynamic>)>> _callbacks = {};
  bool _isListenerRegistered = false;
  bool _socketIOListenerRegistered = false;
  
  /// Event schema for validation
  static const Map<String, Set<String>> _eventSchema = {
    'game_joined': {
      'game_id', 'player_id', 'player_name', 'game_state', 'player',
      'room_id', 'room_name', 'is_owner', 'is_active',
    },
    'game_left': {
      'game_id', 'player_id', 'reason', 'timestamp',
    },
    'player_joined': {
      'game_id', 'player_id', 'player_name', 'player', 'players',
      'timestamp', 'room_id',
    },
    'player_left': {
      'game_id', 'player_id', 'player_name', 'reason', 'players',
      'timestamp', 'room_id',
    },
    'game_started': {
      'game_id', 'game_state', 'timestamp', 'started_by',
      'player_order', 'initial_hands',
    },
    'game_phase_changed': {
      'game_id', 'new_phase', 'current_player', 'timestamp',
    },
    'game_ended': {
      'game_id', 'game_state', 'winner', 'scores', 'reason',
      'timestamp', 'duration',
    },
    'turn_changed': {
      'game_id', 'current_turn', 'previous_turn', 'turn_number',
      'round_number', 'timestamp',
    },
    'turn_started': {
      'game_id', 'game_state', 'player_id', 'turn_timeout', 'timestamp',
    },
    'card_played': {
      'game_id', 'player_id', 'card', 'position', 'timestamp',
      'is_out_of_turn', 'remaining_cards',
    },
    'card_drawn': {
      'game_id', 'player_id', 'source', 'card', 'timestamp',
      'remaining_deck', 'discard_top',
    },
    'replace_drawn_card': {
      'game_id', 'player_id', 'card_index', 'timestamp',
    },
    'play_drawn_card': {
      'game_id', 'player_id', 'timestamp',
    },
    'recall_called': {
      'game_id', 'player_id', 'timestamp', 'scores',
      'updated_game_state',
    },
    'game_state_updated': {
      'game_id', 'game_state', 'timestamp', 'reason',
      'changes',
    },
    'room_event': {
      'action', 'room_id', 'room_data', 'timestamp',
    },
    'room_joined': {
      'room_id', 'player_id', 'player_name', 'timestamp',
      'current_players', 'room_data',
    },
    'join_room_success': {
      'room_id', 'player_id', 'player_name', 'timestamp',
      'room_data', 'current_players',
    },
    'create_room_success': {
      'room_id', 'room_name', 'owner_id', 'timestamp',
      'room_data', 'permission', 'max_players', 'min_players',
    },
    'room_created': {
      'room_id', 'room_name', 'owner_id', 'permission',
      'max_players', 'min_players', 'timestamp',
    },
    'leave_room_success': {
      'room_id', 'player_id', 'reason', 'timestamp',
      'remaining_players',
    },
    'leave_room_error': {
      'room_id', 'player_id', 'error', 'message', 'timestamp',
    },
    'room_left': {
      'room_id', 'player_id', 'reason', 'timestamp',
      'remaining_players',
    },
    'room_closed': {
      'room_id', 'reason', 'timestamp', 'owner_id',
    },
    'recall_new_player_joined': {
      'event_type', 'room_id', 'owner_id', 'joined_player', 'game_state', 'timestamp',
    },
    'recall_joined_games': {
      'event_type', 'user_id', 'session_id', 'games', 'total_games', 'timestamp',
    },
    'create_room': {
      'room_name', 'permission', 'max_players', 'min_players',
      'game_type', 'turn_time_limit', 'auto_start', 'password',
      'timestamp',
    },
    'join_game': {
      'game_id', 'player_name', 'timestamp',
    },
    'start_match': {
      'game_id', 'timestamp',
    },
    'play_card': {
      'game_id', 'card_id', 'player_id', 'replace_index', 'timestamp',
    },
    'call_recall': {
      'game_id', 'player_id', 'timestamp',
    },
    'draw_card': {
      'game_id', 'player_id', 'source', 'timestamp',
    },
    'leave_game': {
      'game_id', 'player_id', 'reason', 'timestamp',
    },
    'play_out_of_turn': {
      'game_id', 'card_id', 'player_id', 'timestamp',
    },
    'use_special_power': {
      'game_id', 'card_id', 'player_id', 'power_data', 'timestamp',
    },
    'get_public_rooms': {
      'timestamp',
    },
    'recall_message': {
      'scope', 'target_id', 'level', 'title', 'message',
      'data', 'timestamp',
    },
    'error': {
      'error', 'message', 'code', 'details', 'timestamp',
    },
    'connection_status': {
      'status', 'session_id', 'error', 'timestamp',
    },
  };

  /// Add event listener with validation
  void addListener(String eventType, Function(Map<String, dynamic>) callback) {
    // Register the main listener only once
    if (!_isListenerRegistered) {
      // Register the Socket.IO listener when WebSocket is connected
      _registerSocketIOListener();
      _isListenerRegistered = true;
    }
    
    // Add callback to the list for this event type
    _callbacks.putIfAbsent(eventType, () => []).add(callback);
    _log.info('📝 Added callback for event type: $eventType (total: ${_callbacks[eventType]?.length})');
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
      // Register listeners for all the direct game events
      final directEvents = [
        'game_joined', 'game_left', 'player_joined', 'player_left',
        'game_started', 'game_phase_changed', 'game_ended', 'turn_changed',
        'turn_started', 'card_played', 'card_drawn', 'replace_drawn_card', 'play_drawn_card',
        'recall_called', 'game_state_updated', 'recall_new_player_joined',
        'recall_joined_games', 'recall_message'
      ];
      
      for (final eventName in directEvents) {
        wsManager.eventListener!.registerCustomListener(eventName, (data) {
          _log.info('🎧 [DirectEvent] Raw event received: $eventName');
          _handleDirectEvent(eventName, data);
        });
      }
      
      _socketIOListenerRegistered = true;
      _log.info('📝 Registered Socket.IO listeners for ${directEvents.length} direct game events via core WebSocket system');
    } else {
      _log.error('❌ WebSocket event listener not available, cannot register direct game event listeners');
    }
  }
  
  /// Handle direct game events and route to appropriate callbacks
  void _handleDirectEvent(String eventType, Map<String, dynamic> data) {
    _log.info('🎧 [DirectEvent] ===== PROCESSING DIRECT GAME EVENT =====');
    _log.info('🎧 [DirectEvent] Event type: $eventType');
    _log.info('🎧 [DirectEvent] Raw data type: ${data.runtimeType}');
    _log.info('🎧 [DirectEvent] Raw data: $data');
    _log.info('🎧 [DirectEvent] Data keys: ${data.keys.toList()}');
    _log.info('🎧 [DirectEvent] Data size: ${data.length} fields');
    
    try {
        // Validate event type
      _log.info('🎧 [DirectEvent] Checking if event type exists in schema...');
      _log.info('🎧 [DirectEvent] Available schema types: ${_eventSchema.keys.toList()}');
      
      if (!_eventSchema.containsKey(eventType)) {
        _log.error('❌ [DirectEvent] Unknown game event type: $eventType');
        _log.error('❌ [DirectEvent] Available schema types: ${_eventSchema.keys.toList()}');
          return;
        }
      
      _log.info('✅ [DirectEvent] Event type validated: $eventType');

        // Validate event data against schema
      _log.info('🎧 [DirectEvent] Validating event data against schema...');
      final validatedData = _validateEventData(eventType, data);
        if (validatedData == null) {
        _log.error('❌ [DirectEvent] Invalid data for game event: $eventType');
        _log.error('❌ [DirectEvent] Validation failed - see validation logs above');
          return;
        }
      
      _log.info('✅ [DirectEvent] Event data validation passed');
      _log.info('🎧 [DirectEvent] Validated data: $validatedData');

        // Add minimal required context
        final eventPayload = {
        'event_type': eventType,
          'timestamp': DateTime.now().toIso8601String(),
          ...validatedData,
        };
      
      _log.info('🎧 [DirectEvent] Final event payload: $eventPayload');

        // Log the event
      _logEvent(eventType, eventPayload);

      // Call all registered callbacks for this event type
      _log.info('🎧 [DirectEvent] Looking for callbacks for event type: $eventType');
      final callbacks = _callbacks[eventType];
      if (callbacks != null) {
        _log.info('🎧 [DirectEvent] Found ${callbacks.length} callbacks for event type: $eventType');
        for (int i = 0; i < callbacks.length; i++) {
          final callback = callbacks[i];
          _log.info('🎧 [DirectEvent] Executing callback ${i + 1}/${callbacks.length}');
          try {
          callback(eventPayload);
            _log.info('✅ [DirectEvent] Callback ${i + 1} executed successfully');
          } catch (e) {
            _log.error('❌ [DirectEvent] Error in callback ${i + 1} for event type $eventType: $e');
            _log.error('❌ [DirectEvent] Error stack trace: ${StackTrace.current}');
          }
        }
      } else {
        _log.warning('⚠️ [DirectEvent] No callbacks registered for event type: $eventType');
        _log.info('🎧 [DirectEvent] Available callback types: ${_callbacks.keys.toList()}');
        }

      } catch (e) {
      _log.error('❌ [DirectEvent] Error handling direct game event: $e');
      _log.error('❌ [DirectEvent] Error stack trace: ${StackTrace.current}');
      }
    
    _log.info('🎧 [DirectEvent] ===== END PROCESSING DIRECT GAME EVENT =====');
  }

  /// Validate event data against schema
  Map<String, dynamic>? _validateEventData(String eventType, Map<String, dynamic> data) {
    _log.info('🔍 [VALIDATION] ===== VALIDATING EVENT DATA =====');
    _log.info('🔍 [VALIDATION] Event type: $eventType');
    _log.info('🔍 [VALIDATION] Input data: $data');
    _log.info('🔍 [VALIDATION] Input data keys: ${data.keys.toList()}');
    
    try {
      final schema = _eventSchema[eventType];
      if (schema == null) {
        _log.error('❌ [VALIDATION] No schema found for event type: $eventType');
        _log.error('❌ [VALIDATION] Available schemas: ${_eventSchema.keys.toList()}');
        return null;
      }
      
      _log.info('✅ [VALIDATION] Found schema for event type: $eventType');
      _log.info('🔍 [VALIDATION] Expected schema fields: ${schema.toList()}');
      _log.info('🔍 [VALIDATION] Schema field count: ${schema.length}');

      final validatedData = <String, dynamic>{};
      final missingFields = <String>[];
      final foundFields = <String>[];

      // Check for required fields based on event type
      for (final field in schema) {
        if (data.containsKey(field)) {
          validatedData[field] = data[field];
          foundFields.add(field);
          _log.info('✅ [VALIDATION] Field found: $field = ${data[field]}');
        } else {
          missingFields.add(field);
          _log.warning('⚠️ [VALIDATION] Missing expected field: $field');
        }
      }
      
      _log.info('🔍 [VALIDATION] Found fields: $foundFields');
      _log.info('🔍 [VALIDATION] Missing fields: $missingFields');
      _log.info('🔍 [VALIDATION] Found field count: ${foundFields.length}/${schema.length}');

      // Add any additional fields that might be useful
      final extraFields = data.keys.where((field) => !schema.contains(field)).toList();
      if (extraFields.isNotEmpty) {
        _log.info('🔍 [VALIDATION] Extra fields found: $extraFields');
        for (final field in extraFields) {
          _log.info('🔍 [VALIDATION] Extra field: $field = ${data[field]}');
        }
      }
      
      if (data.containsKey('metadata')) {
        validatedData['metadata'] = data['metadata'];
        _log.info('✅ [VALIDATION] Added metadata field');
      }

      _log.info('🔍 [VALIDATION] Final validated data: $validatedData');
      _log.info('🔍 [VALIDATION] Validated data keys: ${validatedData.keys.toList()}');
      _log.info('🔍 [VALIDATION] Validated data size: ${validatedData.length} fields');
      
      if (missingFields.isEmpty) {
        _log.info('✅ [VALIDATION] All expected fields present - validation PASSED');
      } else {
        _log.warning('⚠️ [VALIDATION] Missing fields but continuing - validation PARTIAL');
      }
      
      _log.info('🔍 [VALIDATION] ===== END VALIDATION =====');
      return validatedData;

    } catch (e) {
      _log.error('❌ [VALIDATION] Error validating recall game event data: $e');
      _log.error('❌ [VALIDATION] Error stack trace: ${StackTrace.current}');
      _log.info('🔍 [VALIDATION] ===== END VALIDATION (ERROR) =====');
      return null;
    }
  }

  /// Log validated event
  void _logEvent(String eventType, Map<String, dynamic> data) {
    _log.info('✅ [RecallGameEvent] $eventType');
    _log.debug('   Fields: ${data.keys.where((k) => k != 'timestamp').join(', ')}');
  }
}

/// Extension on RecallGameHelpers to provide easy access to event listener
extension RecallGameEventListenerExtension on RecallGameHelpers {
  /// Add validated event listener
  static void onEvent(String eventType, Function(Map<String, dynamic>) callback) {
    RecallGameEventListenerValidator.instance.addListener(eventType, callback);
  }
}
