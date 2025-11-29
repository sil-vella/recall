import 'package:recall/tools/logging/logger.dart';

import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/state_manager.dart';
import '../utils/field_specifications.dart';
import '../practice/practice_mode_bridge.dart';

/// Transport mode for event emission
enum EventTransportMode {
  websocket,
  practice,
}

/// Validated event emitter for recall game WebSocket events
/// Ensures all events follow consistent structure and validation rules
/// Supports dual transport: WebSocket (multiplayer) or Practice (local)
class RecallGameEventEmitter {
  static RecallGameEventEmitter? _instance;
  static RecallGameEventEmitter get instance {
    _instance ??= RecallGameEventEmitter._internal();
    return _instance!;
  }
  
  RecallGameEventEmitter._internal();
  
  // Dependencies
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final PracticeModeBridge _practiceBridge = PracticeModeBridge.instance;
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Temporarily enabled for debugging
  
  // Current transport mode (defaults to WebSocket for backward compatibility)
  EventTransportMode _transportMode = EventTransportMode.websocket;
  
  /// Set the transport mode
  void setTransportMode(EventTransportMode mode) {
    _transportMode = mode;
    _logger.info('RecallGameEventEmitter: Transport mode set to $mode', isOn: LOGGING_SWITCH);
  }
  
  /// Get the current transport mode
  EventTransportMode get transportMode => _transportMode;
  
  /// Define allowed fields for each event type
  static const Map<String, Set<String>> _allowedEventFields = {
    'get_public_rooms': {
      'filter', 'timestamp'
    },
    'list_rooms': {
      // No required fields - just request all rooms
    },
    'join_random_game': {
      // No required fields - backend will search for available rooms or create new one
    },
    'create_room': {
      'permission', 'max_players', 'min_players', 
      'turn_time_limit', 'auto_start', 'game_type', 'password'
    },
    'join_room': {'room_id', 'password'},
    'join_game': {'game_id', 'player_name', 'max_players'},
    'start_match': {'game_id'},
    'play_card': {'game_id', 'card_id', 'replace_index'}, // player_id auto-added
    'replace_drawn_card': {'game_id', 'card_index'}, // player_id auto-added
    'play_drawn_card': {'game_id'}, // player_id auto-added
    'call_recall': {'game_id'}, // player_id auto-added
    'leave_game': {'game_id', 'reason'},
    'draw_card': {'game_id', 'source'}, // player_id auto-added
    'play_out_of_turn': {'game_id', 'card_id'}, // player_id auto-added
    'use_special_power': {'game_id', 'card_id', 'power_data'}, // player_id auto-added
    'same_rank_play': {'game_id', 'card_id'}, // player_id auto-added
    'jack_swap': {'game_id', 'first_card_id', 'first_player_id', 'second_card_id', 'second_player_id'}, // player_id auto-added
    'queen_peek': {'game_id', 'card_id', 'ownerId'}, // ownerId for card owner
    'completed_initial_peek': {'game_id', 'card_ids'}, // player_id auto-added
    'collect_from_discard': {'game_id'}, // player_id auto-added
  };
  
  /// Define validation rules for each field
  static const Map<String, RecallEventFieldSpec> _fieldValidation = {
    // Filter fields
    'filter': RecallEventFieldSpec(
      type: Map,
      description: 'Filter criteria for room query',
    ),
    'timestamp': RecallEventFieldSpec(
      type: String,
      pattern: r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3,6}Z?$',
      description: 'ISO timestamp for request',
    ),

    'permission': RecallEventFieldSpec(
      type: String,
      allowedValues: ['public', 'private'],
      description: 'Room visibility: public or private',
    ),
    'max_players': RecallEventFieldSpec(
      type: int,
      required: false,
      min: 2,
      max: 10,
      description: 'Maximum players for the game: 2-10 (optional)',
    ),
    'min_players': RecallEventFieldSpec(
      type: int,
      min: 2,
      max: 8,
      description: 'Minimum players: 2-8',
    ),
    'turn_time_limit': RecallEventFieldSpec(
      type: int,
      min: 10,
      max: 300,
      description: 'Turn time limit in seconds: 10-300',
    ),
    'auto_start': RecallEventFieldSpec(
      type: bool,
      description: 'Whether to auto-start when room is full',
    ),
    'game_type': RecallEventFieldSpec(
      type: String,
      allowedValues: ['classic', 'speed', 'tournament'],
      description: 'Game type variant',
    ),
    'password': RecallEventFieldSpec(
      type: String,
      required: false,
      minLength: 4,
      maxLength: 20,
      description: 'Room password for private rooms: 4-20 characters',
    ),
    
    // Join room fields
    'room_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^room_[a-zA-Z0-9_]+$',
      description: 'Room ID in format: room_xxxxx',
    ),
    
    // Game fields
    'game_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^(room_|practice_room_)[a-zA-Z0-9_]+$',
      description: 'Game/Room ID in format: room_xxxxx or practice_room_xxxxx',
    ),
    'player_name': RecallEventFieldSpec(
      type: String,
      minLength: 1,
      maxLength: 20,
      pattern: r'^[a-zA-Z0-9_\s]+$',
      description: 'Player name: 1-20 alphanumeric characters',
    ),
    'player_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^(player_[a-zA-Z0-9_]+|computer_[a-zA-Z0-9_]+|cpu_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'Player ID in format: player_xxxxx, computer_xxxxx, cpu_xxxxx, or MongoDB ObjectId',
    ),
    'card_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^card_[a-zA-Z0-9_]+$',
      description: 'Card ID in format: card_xxxxx',
    ),
    'replace_index': RecallEventFieldSpec(
      type: int,
      required: false,
      min: 0,
      max: 3,
      description: 'Card index to replace: 0-3',
    ),
    'card_index': RecallEventFieldSpec(
      type: int,
      required: true,
      min: 0,
      max: 3,
      description: 'Card index to replace: 0-3',
    ),
    'reason': RecallEventFieldSpec(
      type: String,
      required: false,
      maxLength: 100,
      description: 'Reason for leaving game',
    ),
    'source': RecallEventFieldSpec(
      type: String,
      allowedValues: ['deck', 'discard'],
      description: 'Source of card draw: deck or discard pile',
    ),
    'power_data': RecallEventFieldSpec(
      type: Map,
      required: false,
      description: 'Special power specific data',
    ),
    
    // Jack swap fields
    'first_card_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^card_[a-zA-Z0-9_]+$',
      description: 'First card ID in format: card_xxxxx',
    ),
    'first_player_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^(player_[a-zA-Z0-9_]+|computer_[a-zA-Z0-9_]+|cpu_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'First player ID in format: player_xxxxx, computer_xxxxx, cpu_xxxxx, or MongoDB ObjectId',
    ),
    'second_card_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^card_[a-zA-Z0-9_]+$',
      description: 'Second card ID in format: card_xxxxx',
    ),
    'second_player_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^(player_[a-zA-Z0-9_]+|computer_[a-zA-Z0-9_]+|cpu_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'Second player ID in format: player_xxxxx, computer_xxxxx, cpu_xxxxx, or MongoDB ObjectId',
    ),
    'queen_peek_card_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^card_[a-zA-Z0-9_]+$',
      description: 'Card ID to peek at in format: card_xxxxx',
    ),
    'queen_peek_player_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^(player_[a-zA-Z0-9_]+|computer_[a-zA-Z0-9_]+|cpu_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'Player ID whose card to peek at in format: player_xxxxx, computer_xxxxx, cpu_xxxxx, or MongoDB ObjectId',
    ),
    'ownerId': RecallEventFieldSpec(
      type: String,
      pattern: r'^(player_[a-zA-Z0-9_]+|computer_[a-zA-Z0-9_]+|cpu_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'Owner ID of the card being peeked at in format: player_xxxxx, computer_xxxxx, cpu_xxxxx, or MongoDB ObjectId',
    ),
  };
  
  /// Emit a validated event
  Future<Map<String, dynamic>> emit({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    try {
      // 🎯 Validate event type and fields
      final validatedData = _validateAndParseEventData(eventType, data);
      
      // Add minimal required context
      final eventPayload = {
        'event_type': eventType,
        'session_id': _getSessionId(),
        'timestamp': DateTime.now().toIso8601String(),
        ...validatedData, // Only validated fields
      };
      
      // 🎯 Auto-include user ID for events that need player_id
      final eventsNeedingPlayerId = {
        'play_card', 'replace_drawn_card', 'play_drawn_card', 
        'call_recall', 'draw_card', 'play_out_of_turn', 'use_special_power', 'same_rank_play', 'jack_swap', 'completed_initial_peek', 'collect_from_discard'
      };
      
      if (eventsNeedingPlayerId.contains(eventType)) {
        final currentUserId = _getCurrentUserId();
        if (currentUserId.isNotEmpty) {
          eventPayload['player_id'] = currentUserId;
        }
      }

      _logger.info('Sending event to backend: $eventPayload', isOn: LOGGING_SWITCH);
      
      // Route based on transport mode
      if (_transportMode == EventTransportMode.practice) {
        // Route to practice bridge
        await _practiceBridge.handleEvent(eventType, eventPayload);
        return {'success': true, 'mode': 'practice'};
      } else {
        // Send via WebSocket (default)
      return await _wsManager.sendCustomEvent(eventType, eventPayload);
      }
      
    } catch (e) {
      rethrow;
    }
  }
  
  /// Validate and parse event data
  Map<String, dynamic> _validateAndParseEventData(String eventType, Map<String, dynamic> data) {
    final allowedFields = _allowedEventFields[eventType];
    if (allowedFields == null) {
      throw RecallEventException(
        'Unknown event type: $eventType. '
        'Allowed types: ${_allowedEventFields.keys.join(', ')}',
        eventType: eventType,
      );
    }
    
    final validatedData = <String, dynamic>{};
    
    // Validate each provided field
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // 🚨 Check if field is allowed for this event type
      if (!allowedFields.contains(key)) {
        throw RecallEventException(
          'Invalid field "$key" for event type "$eventType". '
          'Allowed fields: ${allowedFields.join(', ')}',
          eventType: eventType,
          fieldName: key,
        );
      }
      
      // 🚨 Validate field value
      final validatedValue = _validateFieldValue(eventType, key, value);
      validatedData[key] = validatedValue;
    }
    
    // 🚨 Check for required fields
    _validateRequiredFields(eventType, allowedFields, validatedData);
    
    return validatedData;
  }
  
  /// Validate individual field value
  dynamic _validateFieldValue(String eventType, String key, dynamic value) {
    final fieldSpec = _fieldValidation[key];
    if (fieldSpec == null) {
      // Field is allowed but has no specific validation - pass through
      return value;
    }
    
    // Handle null values
    if (value == null) {
      if (fieldSpec.required) {
        throw RecallEventException(
          'Field "$key" is required and cannot be null',
          eventType: eventType,
          fieldName: key,
        );
      }
      return null;
    }
    
    // Type validation
    if (!ValidationUtils.isValidType(value, fieldSpec.type)) {
      throw RecallEventException(
        'Field "$key" must be of type ${fieldSpec.type}, got ${value.runtimeType}',
        eventType: eventType,
        fieldName: key,
      );
    }
    
    // String-specific validations
    if (value is String) {
      // Length validation
      if (!ValidationUtils.isValidLength(value, minLength: fieldSpec.minLength, maxLength: fieldSpec.maxLength)) {
        final lengthDesc = [
          if (fieldSpec.minLength != null) 'min: ${fieldSpec.minLength}',
          if (fieldSpec.maxLength != null) 'max: ${fieldSpec.maxLength}',
        ].join(', ');
        throw RecallEventException(
          'Field "$key" length ${value.length} is invalid ($lengthDesc)',
          eventType: eventType,
          fieldName: key,
        );
      }
      
      // Pattern validation
      if (fieldSpec.pattern != null && !ValidationUtils.matchesPattern(value, fieldSpec.pattern!)) {
        throw RecallEventException(
          'Field "$key" value "$value" does not match required pattern: ${fieldSpec.pattern}',
          eventType: eventType,
          fieldName: key,
        );
      }
    }
    
    // Numeric range validation
    if (value is num) {
      if (!ValidationUtils.isValidRange(value, min: fieldSpec.min, max: fieldSpec.max)) {
        final rangeDesc = [
          if (fieldSpec.min != null) 'min: ${fieldSpec.min}',
          if (fieldSpec.max != null) 'max: ${fieldSpec.max}',
        ].join(', ');
        throw RecallEventException(
          'Field "$key" value $value is out of range ($rangeDesc)',
          eventType: eventType,
          fieldName: key,
        );
      }
    }
    
    // Allowed values validation
    if (fieldSpec.allowedValues != null && !ValidationUtils.isAllowedValue(value, fieldSpec.allowedValues!)) {
      throw RecallEventException(
        'Field "$key" value "$value" is not allowed. '
        'Allowed values: ${fieldSpec.allowedValues!.join(', ')}',
        eventType: eventType,
        fieldName: key,
      );
    }
    
    return value;
  }
  
  /// Validate required fields are present
  void _validateRequiredFields(String eventType, Set<String> allowedFields, Map<String, dynamic> data) {
    for (final fieldName in allowedFields) {
      final fieldSpec = _fieldValidation[fieldName];
      if (fieldSpec?.required == true && !data.containsKey(fieldName)) {
        throw RecallEventException(
          'Required field "$fieldName" is missing',
          eventType: eventType,
          fieldName: fieldName,
        );
      }
    }
  }
  
  /// Get current session ID
  String _getSessionId() {
    try {
      return _wsManager.socket?.id ?? 'unknown_session';
    } catch (e) {
      return 'unknown_session';
    }
  }
  
  /// Get current user ID from login state
  String _getCurrentUserId() {
    try {
      // Import StateManager to access login state
      // Note: This creates a dependency on StateManager, but it's needed for user identification
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      return loginState['userId']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }
  
}
