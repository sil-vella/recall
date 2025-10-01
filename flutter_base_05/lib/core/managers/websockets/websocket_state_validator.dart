import '../state_manager.dart';
import '../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// WebSocket State Field Specification
class WebSocketStateFieldSpec {
  final String name;
  final Type type;
  final bool required;
  final dynamic defaultValue;
  final bool Function(dynamic)? validator;

  const WebSocketStateFieldSpec({
    required this.name,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.validator,
  });
}

/// WebSocket State Exception
class WebSocketStateException implements Exception {
  final String message;
  final String? fieldName;

  WebSocketStateException(this.message, [this.fieldName]);

  @override
  String toString() => fieldName != null
      ? 'WebSocketStateException in field $fieldName: $message'
      : 'WebSocketStateException: $message';
}

/// Validated WebSocket State Updater
class WebSocketStateUpdater {
  static final Logger _logger = Logger();
  static final StateManager _stateManager = StateManager();

  /// WebSocket state schema definition
  static const Map<String, WebSocketStateFieldSpec> _stateSchema = {
    'isConnected': WebSocketStateFieldSpec(
      name: 'isConnected',
      type: bool,
      required: true,
      defaultValue: false,
    ),
    'currentRoomId': WebSocketStateFieldSpec(
      name: 'currentRoomId',
      type: String,
      required: false,
      defaultValue: null,
    ),
    'currentRoomInfo': WebSocketStateFieldSpec(
      name: 'currentRoomInfo',
      type: Map,
      required: false,
      defaultValue: null,
    ),
    'sessionData': WebSocketStateFieldSpec(
      name: 'sessionData',
      type: Map,
      required: false,
      defaultValue: null,
    ),
    'joinedRooms': WebSocketStateFieldSpec(
      name: 'joinedRooms',
      type: List,
      required: false,
      defaultValue: [],
    ),
    'totalJoinedRooms': WebSocketStateFieldSpec(
      name: 'totalJoinedRooms',
      type: int,
      required: false,
      defaultValue: 0,
    ),
    'joinedRoomsTimestamp': WebSocketStateFieldSpec(
      name: 'joinedRoomsTimestamp',
      type: String,
      required: false,
      defaultValue: null,
    ),
    'joinedRoomsSessionId': WebSocketStateFieldSpec(
      name: 'joinedRoomsSessionId',
      type: String,
      required: false,
      defaultValue: null,
    ),
    'lastUpdated': WebSocketStateFieldSpec(
      name: 'lastUpdated',
      type: String,
      required: false,
      defaultValue: null,
    ),
  };

  /// Update WebSocket state with validation
  static void updateState(Map<String, dynamic> updates) {
    try {
      _logger.info('🔄 WebSocket state update requested with ${updates.length} fields', isOn: LOGGING_SWITCH);
      _logger.debug('Update fields: ${updates.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Get current state
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
      _logger.debug('Current WebSocket state: ${currentState.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Validate updates
      final validatedUpdates = <String, dynamic>{};
      
      for (final entry in updates.entries) {
        final fieldName = entry.key;
        final value = entry.value;
        
        _logger.debug('Validating field: $fieldName (${value.runtimeType})', isOn: LOGGING_SWITCH);
        
        // Check if field is allowed
        if (!_stateSchema.containsKey(fieldName)) {
          _logger.error('Field "$fieldName" is not allowed in WebSocket state schema', isOn: LOGGING_SWITCH);
          throw WebSocketStateException(
            'Field "$fieldName" is not allowed in WebSocket state schema',
            fieldName,
          );
        }
        
        final spec = _stateSchema[fieldName]!;
        
        // Validate type (allow null for non-required fields)
        if (value != null) {
          if (spec.type == String && value is! String) {
            _logger.error('Field "$fieldName" must be of type String, got ${value.runtimeType}', isOn: LOGGING_SWITCH);
            throw WebSocketStateException(
              'Field "$fieldName" must be of type String, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == bool && value is! bool) {
            _logger.error('Field "$fieldName" must be of type bool, got ${value.runtimeType}', isOn: LOGGING_SWITCH);
            throw WebSocketStateException(
              'Field "$fieldName" must be of type bool, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == Map && value is! Map) {
            _logger.error('Field "$fieldName" must be of type Map, got ${value.runtimeType}', isOn: LOGGING_SWITCH);
            throw WebSocketStateException(
              'Field "$fieldName" must be of type Map, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == List && value is! List) {
            _logger.error('Field "$fieldName" must be of type List, got ${value.runtimeType}', isOn: LOGGING_SWITCH);
            throw WebSocketStateException(
              'Field "$fieldName" must be of type List, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == int && value is! int) {
            _logger.error('Field "$fieldName" must be of type int, got ${value.runtimeType}', isOn: LOGGING_SWITCH);
            throw WebSocketStateException(
              'Field "$fieldName" must be of type int, got ${value.runtimeType}',
              fieldName,
            );
          }
        }
        
        // Custom validation
        if (spec.validator != null && !spec.validator!(value)) {
          _logger.error('Field "$fieldName" failed custom validation', isOn: LOGGING_SWITCH);
          throw WebSocketStateException(
            'Field "$fieldName" failed custom validation',
            fieldName,
          );
        }
        
        validatedUpdates[fieldName] = value;
        _logger.debug('Field "$fieldName" validated successfully', isOn: LOGGING_SWITCH);
      }
      
      // Add timestamp if not provided
      if (!validatedUpdates.containsKey('lastUpdated')) {
        validatedUpdates['lastUpdated'] = DateTime.now().toIso8601String();
        _logger.debug('Added timestamp to WebSocket state update', isOn: LOGGING_SWITCH);
      }
      
      // Merge with current state
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      _logger.info('✅ WebSocket state updated successfully with ${validatedUpdates.length} fields', isOn: LOGGING_SWITCH);
      _logger.debug('New state keys: ${newState.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Update state manager
      _stateManager.updateModuleState('websocket', newState);

      
    } catch (e) {
      _logger.error('❌ Failed to update WebSocket state: $e', isOn: LOGGING_SWITCH);
      throw WebSocketStateException('Failed to update WebSocket state: $e');
    }
  }

  /// Clear WebSocket state (reset to defaults)
  static void clearState() {
    try {
      _logger.info('🔄 Clearing WebSocket state to defaults', isOn: LOGGING_SWITCH);
      
      final defaultState = <String, dynamic>{};
      for (final spec in _stateSchema.values) {
        defaultState[spec.name] = spec.defaultValue;
      }
      defaultState['lastUpdated'] = DateTime.now().toIso8601String();
      
      _logger.debug('Default state keys: ${defaultState.keys.toList()}', isOn: LOGGING_SWITCH);
      
      _stateManager.updateModuleState('websocket', defaultState);
      
      _logger.info('✅ WebSocket state cleared successfully', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('❌ Failed to clear WebSocket state: $e', isOn: LOGGING_SWITCH);
      throw WebSocketStateException('Failed to clear WebSocket state: $e');
    }
  }

  /// Get current WebSocket state
  static Map<String, dynamic> getCurrentState() {
    return _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
  }

  /// Check if WebSocket is connected
  static bool isConnected() {
    final state = getCurrentState();
    return state['isConnected'] == true;
  }

  /// Get current room ID
  static String? getCurrentRoomId() {
    final state = getCurrentState();
    return state['currentRoomId'] as String?;
  }

  /// Get current room info
  static Map<String, dynamic>? getCurrentRoomInfo() {
    final state = getCurrentState();
    return state['currentRoomInfo'] as Map<String, dynamic>?;
  }

  /// Get session data
  static Map<String, dynamic>? getSessionData() {
    final state = getCurrentState();
    return state['sessionData'] as Map<String, dynamic>?;
  }
}

/// WebSocket State Helper Methods
class WebSocketStateHelpers {
  static final Logger _logger = Logger();

  /// Update connection status
  static void updateConnectionStatus({
    required bool isConnected,
    Map<String, dynamic>? sessionData,
  }) {
    _logger.info('🔄 Updating WebSocket connection status: $isConnected', isOn: LOGGING_SWITCH);
    if (sessionData != null) {
      _logger.debug('Session data provided: ${sessionData.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    final updates = <String, dynamic>{
      'isConnected': isConnected,
    };
    
    if (sessionData != null) {
      updates['sessionData'] = sessionData;
    }
    
    // Clear room data on disconnect
    if (!isConnected) {
      _logger.info('🔌 Connection lost - clearing room data', isOn: LOGGING_SWITCH);
      updates['currentRoomId'] = null;
      updates['currentRoomInfo'] = null;
      updates['sessionData'] = null;
    }
    
    WebSocketStateUpdater.updateState(updates);
    _logger.info('✅ Connection status updated successfully', isOn: LOGGING_SWITCH);
  }

  /// Update room information
  static void updateRoomInfo({
    String? roomId,
    Map<String, dynamic>? roomInfo,
  }) {
    _logger.info('🔄 Updating room information', isOn: LOGGING_SWITCH);
    if (roomId != null) {
      _logger.debug('Room ID: $roomId', isOn: LOGGING_SWITCH);
    }
    if (roomInfo != null) {
      _logger.debug('Room info keys: ${roomInfo.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    final updates = <String, dynamic>{};
    
    if (roomId != null) {
      updates['currentRoomId'] = roomId;
    }
    
    if (roomInfo != null) {
      updates['currentRoomInfo'] = roomInfo;
    }
    
    WebSocketStateUpdater.updateState(updates);
    _logger.info('✅ Room information updated successfully', isOn: LOGGING_SWITCH);
  }

  /// Clear room information
  static void clearRoomInfo() {
    _logger.info('🔄 Clearing room information', isOn: LOGGING_SWITCH);
    
    WebSocketStateUpdater.updateState({
      'currentRoomId': null,
      'currentRoomInfo': null,
    });
    
    _logger.info('✅ Room information cleared successfully', isOn: LOGGING_SWITCH);
  }

  /// Update session data
  static void updateSessionData(Map<String, dynamic>? sessionData) {
    _logger.info('🔄 Updating session data', isOn: LOGGING_SWITCH);
    if (sessionData != null) {
      _logger.debug('Session data keys: ${sessionData.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    WebSocketStateUpdater.updateState({
      'sessionData': sessionData,
    });
    
    _logger.info('✅ Session data updated successfully', isOn: LOGGING_SWITCH);
  }

  /// Update joined rooms information
  static void updateJoinedRooms({
    required String sessionId,
    required List<Map<String, dynamic>> joinedRooms,
    required int totalRooms,
    required String timestamp,
  }) {
    _logger.info('🔄 Updating joined rooms information', isOn: LOGGING_SWITCH);
    _logger.debug('Session ID: $sessionId, Total rooms: $totalRooms, Timestamp: $timestamp', isOn: LOGGING_SWITCH);
    _logger.debug('Joined rooms count: ${joinedRooms.length}', isOn: LOGGING_SWITCH);
    
    WebSocketStateUpdater.updateState({
      'joinedRooms': joinedRooms,
      'totalJoinedRooms': totalRooms,
      'joinedRoomsTimestamp': timestamp,
      'joinedRoomsSessionId': sessionId,
    });
    
    _logger.info('✅ Joined rooms information updated successfully', isOn: LOGGING_SWITCH);
  }
}
