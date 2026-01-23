import '../state_manager.dart';
import '../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for debugging WebSocket state validation

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
      if (LOGGING_SWITCH) {
        _logger.info('🔄 WebSocket state update requested with ${updates.length} fields');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('Update fields: ${updates.keys.toList()}');
      }
      
      // Get current state
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
      if (LOGGING_SWITCH) {
        _logger.debug('Current WebSocket state: ${currentState.keys.toList()}');
      }
      
      // Validate updates
      final validatedUpdates = <String, dynamic>{};
      
      for (final entry in updates.entries) {
        final fieldName = entry.key;
        final value = entry.value;
        
        if (LOGGING_SWITCH) {
          _logger.debug('Validating field: $fieldName (${value.runtimeType})');
        }
        
        // Check if field is allowed
        if (!_stateSchema.containsKey(fieldName)) {
          if (LOGGING_SWITCH) {
            _logger.error('Field "$fieldName" is not allowed in WebSocket state schema');
          }
          throw WebSocketStateException(
            'Field "$fieldName" is not allowed in WebSocket state schema',
            fieldName,
          );
        }
        
        final spec = _stateSchema[fieldName]!;
        
        // Validate type (allow null for non-required fields)
        if (value != null) {
          if (spec.type == String && value is! String) {
            if (LOGGING_SWITCH) {
              _logger.error('Field "$fieldName" must be of type String, got ${value.runtimeType}');
            }
            throw WebSocketStateException(
              'Field "$fieldName" must be of type String, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == bool && value is! bool) {
            if (LOGGING_SWITCH) {
              _logger.error('Field "$fieldName" must be of type bool, got ${value.runtimeType}');
            }
            throw WebSocketStateException(
              'Field "$fieldName" must be of type bool, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == Map && value is! Map) {
            if (LOGGING_SWITCH) {
              _logger.error('Field "$fieldName" must be of type Map, got ${value.runtimeType}');
            }
            throw WebSocketStateException(
              'Field "$fieldName" must be of type Map, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == List && value is! List) {
            if (LOGGING_SWITCH) {
              _logger.error('Field "$fieldName" must be of type List, got ${value.runtimeType}');
            }
            throw WebSocketStateException(
              'Field "$fieldName" must be of type List, got ${value.runtimeType}',
              fieldName,
            );
          } else if (spec.type == int && value is! int) {
            if (LOGGING_SWITCH) {
              _logger.error('Field "$fieldName" must be of type int, got ${value.runtimeType}');
            }
            throw WebSocketStateException(
              'Field "$fieldName" must be of type int, got ${value.runtimeType}',
              fieldName,
            );
          }
        }
        
        // Custom validation
        if (spec.validator != null && !spec.validator!(value)) {
          if (LOGGING_SWITCH) {
            _logger.error('Field "$fieldName" failed custom validation');
          }
          throw WebSocketStateException(
            'Field "$fieldName" failed custom validation',
            fieldName,
          );
        }
        
        validatedUpdates[fieldName] = value;
        if (LOGGING_SWITCH) {
          _logger.debug('Field "$fieldName" validated successfully');
        }
      }
      
      // Add timestamp if not provided
      if (!validatedUpdates.containsKey('lastUpdated')) {
        validatedUpdates['lastUpdated'] = DateTime.now().toIso8601String();
        if (LOGGING_SWITCH) {
          _logger.debug('Added timestamp to WebSocket state update');
        }
      }
      
      // Merge with current state
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket state updated successfully with ${validatedUpdates.length} fields');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('New state keys: ${newState.keys.toList()}');
      }
      
      // Update state manager
      _stateManager.updateModuleState('websocket', newState);

      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Failed to update WebSocket state: $e');
      }
      throw WebSocketStateException('Failed to update WebSocket state: $e');
    }
  }

  /// Clear WebSocket state (reset to defaults)
  static void clearState() {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🔄 Clearing WebSocket state to defaults');
      }
      
      final defaultState = <String, dynamic>{};
      for (final spec in _stateSchema.values) {
        defaultState[spec.name] = spec.defaultValue;
      }
      defaultState['lastUpdated'] = DateTime.now().toIso8601String();
      
      if (LOGGING_SWITCH) {
        _logger.debug('Default state keys: ${defaultState.keys.toList()}');
      }
      
      _stateManager.updateModuleState('websocket', defaultState);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ WebSocket state cleared successfully');
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Failed to clear WebSocket state: $e');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('🔄 Updating WebSocket connection status: $isConnected');
    }
    if (sessionData != null) {
      if (LOGGING_SWITCH) {
        _logger.debug('Session data provided: ${sessionData.keys.toList()}');
      }
    }
    
    final updates = <String, dynamic>{
      'isConnected': isConnected,
    };
    
    if (sessionData != null) {
      updates['sessionData'] = sessionData;
    }
    
    // Clear room data on disconnect
    if (!isConnected) {
      if (LOGGING_SWITCH) {
        _logger.info('🔌 Connection lost - clearing room data');
      }
      updates['currentRoomId'] = null;
      updates['currentRoomInfo'] = null;
      updates['sessionData'] = null;
    }
    
    WebSocketStateUpdater.updateState(updates);
    if (LOGGING_SWITCH) {
      _logger.info('✅ Connection status updated successfully');
    }
  }

  /// Update room information
  static void updateRoomInfo({
    String? roomId,
    Map<String, dynamic>? roomInfo,
  }) {
    if (LOGGING_SWITCH) {
      _logger.info('🔄 Updating room information');
    }
    if (roomId != null) {
      if (LOGGING_SWITCH) {
        _logger.debug('Room ID: $roomId');
      }
    }
    if (roomInfo != null) {
      if (LOGGING_SWITCH) {
        _logger.debug('Room info keys: ${roomInfo.keys.toList()}');
      }
    }
    
    final updates = <String, dynamic>{};
    
    if (roomId != null) {
      updates['currentRoomId'] = roomId;
    }
    
    if (roomInfo != null) {
      updates['currentRoomInfo'] = roomInfo;
    }
    
    WebSocketStateUpdater.updateState(updates);
    if (LOGGING_SWITCH) {
      _logger.info('✅ Room information updated successfully');
    }
  }

  /// Clear room information
  static void clearRoomInfo() {
    if (LOGGING_SWITCH) {
      _logger.info('🔄 Clearing room information');
    }
    
    WebSocketStateUpdater.updateState({
      'currentRoomId': null,
      'currentRoomInfo': null,
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ Room information cleared successfully');
    }
  }

  /// Update session data
  static void updateSessionData(Map<String, dynamic>? sessionData) {
    if (LOGGING_SWITCH) {
      _logger.info('🔄 Updating session data');
    }
    if (sessionData != null) {
      if (LOGGING_SWITCH) {
        _logger.debug('Session data keys: ${sessionData.keys.toList()}');
      }
    }
    
    WebSocketStateUpdater.updateState({
      'sessionData': sessionData,
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ Session data updated successfully');
    }
  }

  /// Update joined rooms information
  static void updateJoinedRooms({
    required String sessionId,
    required List<Map<String, dynamic>> joinedRooms,
    required int totalRooms,
    required String timestamp,
  }) {
    if (LOGGING_SWITCH) {
      _logger.info('🔄 Updating joined rooms information');
    }
    if (LOGGING_SWITCH) {
      _logger.debug('Session ID: $sessionId, Total rooms: $totalRooms, Timestamp: $timestamp');
    }
    if (LOGGING_SWITCH) {
      _logger.debug('Joined rooms count: ${joinedRooms.length}');
    }
    
    WebSocketStateUpdater.updateState({
      'joinedRooms': joinedRooms,
      'totalJoinedRooms': totalRooms,
      'joinedRoomsTimestamp': timestamp,
      'joinedRoomsSessionId': sessionId,
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ Joined rooms information updated successfully');
    }
  }
  
  /// Update authentication status
  static void updateAuthenticationStatus({
    required bool isAuthenticated,
    String? userId,
    String? error,
  }) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    
    stateManager.updateModuleState('websocket', {
      ...currentState,
      'is_authenticated': isAuthenticated,
      'user_id': userId,
      'auth_error': error,
      'auth_timestamp': DateTime.now().toIso8601String(),
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ Authentication status updated: authenticated=$isAuthenticated');
    }
  }
}
