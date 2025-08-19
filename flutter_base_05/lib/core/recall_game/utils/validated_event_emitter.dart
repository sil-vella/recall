import '../../managers/websockets/websocket_manager.dart';
import 'field_specifications.dart';
import '../../../tools/logging/logger.dart';

/// Validated event emitter for recall game WebSocket events
/// Ensures all events follow consistent structure and validation rules
class RecallGameEventEmitter {
  static final Logger _log = Logger();
  static RecallGameEventEmitter? _instance;
  static RecallGameEventEmitter get instance {
    _instance ??= RecallGameEventEmitter._internal();
    return _instance!;
  }
  
  RecallGameEventEmitter._internal();
  
  // Dependencies
  final WebSocketManager _wsManager = WebSocketManager.instance;
  
  /// Define allowed fields for each event type
  static const Map<String, Set<String>> _allowedEventFields = {
    'get_public_rooms': {
      'filter', 'timestamp'
    },
    'create_room': {
      'room_name', 'permission', 'max_players', 'min_players', 
      'turn_time_limit', 'auto_start', 'game_type', 'password'
    },
    'join_game': {'game_id', 'player_name', 'max_players'},
    'start_match': {'game_id'},
    'play_card': {'game_id', 'card_id', 'player_id', 'replace_index'},
    'replace_drawn_card': {'game_id', 'player_id', 'card_index'},
    'play_drawn_card': {'game_id', 'player_id'},
    'call_recall': {'game_id', 'player_id'},
    'leave_game': {'game_id', 'reason'},
    'draw_card': {'game_id', 'player_id', 'source'},
    'play_out_of_turn': {'game_id', 'card_id', 'player_id'},
    'use_special_power': {'game_id', 'card_id', 'player_id', 'power_data'},
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
    // Room fields
    'room_name': RecallEventFieldSpec(
      type: String,
      minLength: 1,
      maxLength: 50,
      description: 'Room name between 1-50 characters',
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
    
    // Game fields
    'game_id': RecallEventFieldSpec(
      type: String,
      pattern: r'^room_[a-zA-Z0-9_]+$',
      description: 'Game/Room ID in format: room_xxxxx',
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
      pattern: r'^(player_[a-zA-Z0-9_]+|[a-f0-9]{24})$',
      description: 'Player ID in format: player_xxxxx or MongoDB ObjectId',
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
  };
  
  /// Emit a validated event
  Future<Map<String, dynamic>> emit({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    try {
      _log.info('🎯 [RecallEventEmitter.emit] Starting validation for $eventType');
      _log.info('🎯 [RecallEventEmitter.emit] Input data: ${data.keys.join(', ')}');
      
      // 🎯 Validate event type and fields
      final validatedData = _validateAndParseEventData(eventType, data);
      
      _log.info('🎯 [RecallEventEmitter.emit] Validation passed, validated data: ${validatedData.keys.join(', ')}');
      
      // Add minimal required context
      final eventPayload = {
        'event_type': eventType,
        'session_id': _getSessionId(),
        'timestamp': DateTime.now().toIso8601String(),
        ...validatedData, // Only validated fields
      };
      
      _log.info('🎯 [RecallEventEmitter.emit] Final payload keys: ${eventPayload.keys.join(', ')}');
      
      // Log the event for debugging
      _logEvent(eventType, eventPayload);
      
      // Send via WebSocket
                _log.info('🎯 [RecallEventEmitter.emit] Sending via WebSocket...');
          return await _wsManager.sendCustomEvent(eventType, eventPayload);
      
    } catch (e) {
      // Log validation errors
      _log.error('❌ [RecallEventEmitter.emit] Validation failed for $eventType:');
      _log.error('❌ [RecallEventEmitter.emit] Error: $e');
      _log.error('❌ [RecallEventEmitter.emit] Error type: ${e.runtimeType}');
      _log.error('❌ [RecallEventEmitter.emit] Original data: ${data.keys.join(', ')}');
      _logEventError(eventType, data, e);
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
  
  /// Log successful event emission
  void _logEvent(String eventType, Map<String, dynamic> payload) {
    _log.info('🎯 [RecallEventEmitter] Emitting $eventType with ${payload.length} fields');
    _log.info('   Fields: ${payload.keys.where((k) => k != 'session_id' && k != 'timestamp').join(', ')}');
  }
  
  /// Log validation errors
  void _logEventError(String eventType, Map<String, dynamic> originalData, dynamic error) {
    _log.error('❌ [RecallEventEmitter] Validation failed for $eventType:');
    _log.error('   Error: $error');
    _log.error('   Original data: ${originalData.keys.join(', ')}');
  }
}
