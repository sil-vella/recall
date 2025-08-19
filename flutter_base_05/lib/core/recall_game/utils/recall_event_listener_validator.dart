import '../../../tools/logging/logger.dart';
import '../../managers/websockets/ws_event_manager.dart';
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
    _wsEvents.onEvent('recall_game_event', (data) {
      try {
        // Extract event type from data
        final type = data['event_type'] as String?;
        if (type == null) {
          _log.error('❌ Missing event_type in recall game event');
          return;
        }

        // Validate event type
        if (!_eventSchema.containsKey(type)) {
          _log.error('❌ Unknown recall game event type: $type');
          return;
        }

        // Validate event data against schema
        final validatedData = _validateEventData(type, data);
        if (validatedData == null) {
          _log.error('❌ Invalid data for recall game event: $type');
          return;
        }

        // Add minimal required context
        final eventPayload = {
          'event_type': type,
          'timestamp': DateTime.now().toIso8601String(),
          ...validatedData,
        };

        // Log the event
        _logEvent(type, eventPayload);

        // Call the callback with validated data
        if (type == eventType) {
          callback(eventPayload);
        }

      } catch (e) {
        _log.error('❌ Error handling recall game event: $e');
      }
    });
  }

  /// Validate event data against schema
  Map<String, dynamic>? _validateEventData(String eventType, Map<String, dynamic> data) {
    try {
      final schema = _eventSchema[eventType];
      if (schema == null) return null;

      final validatedData = <String, dynamic>{};

      // Check for required fields based on event type
      for (final field in schema) {
        if (data.containsKey(field)) {
          validatedData[field] = data[field];
        }
      }

      // Add any additional fields that might be useful
      if (data.containsKey('metadata')) {
        validatedData['metadata'] = data['metadata'];
      }

      return validatedData;

    } catch (e) {
      _log.error('❌ Error validating recall game event data: $e');
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
