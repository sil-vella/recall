import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';
import 'state/immutable_state.dart';

const bool LOGGING_SWITCH = false; // Disabled to reduce log noise - only INFO/WARNING/ERROR logs will show

class ModuleState {
  final dynamic state; // Can be Map<String, dynamic> OR ImmutableState

  ModuleState({required this.state});

  /// Ensures all keys are Strings and values are valid JSON types
  factory ModuleState.fromDynamic(Map<dynamic, dynamic> rawState) {
    return ModuleState(
      state: rawState.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  /// Merges the new state with the existing one
  /// DEPRECATED: Use immutable state updates instead
  /// This method is kept for backward compatibility during migration
  @deprecated
  ModuleState merge(Map<String, dynamic> newState) {
    // If state is already immutable, this should not be called
    if (state is ImmutableState) {
      throw StateError('Cannot merge immutable state. Use copyWith() instead.');
    }
    
    // Legacy behavior for Map-based state (handles LinkedMap, HashMap, etc.)
    if (state is Map) {
      // Convert existing state to Map<String, dynamic> if needed
      final existingMap = (state as Map).map((key, value) => MapEntry(key.toString(), value));
      // Convert newState to ensure all keys are strings
      final newMap = newState.map((key, value) => MapEntry(key.toString(), value));
      return ModuleState(state: {...existingMap, ...newMap});
    }
    
    throw StateError('Invalid state type: ${state.runtimeType}');
  }
  
  /// Check if this state is immutable
  bool get isImmutable => state is ImmutableState;
  
  /// Get state as immutable (throws if not immutable)
  ImmutableState get asImmutable {
    if (state is! ImmutableState) {
      throw StateError('State is not immutable: ${state.runtimeType}');
    }
    return state as ImmutableState;
  }
  
  /// Get state as map (throws if not map)
  Map<String, dynamic> get asMap {
    if (state is! Map<String, dynamic>) {
      throw StateError('State is not a map: ${state.runtimeType}');
    }
    return state as Map<String, dynamic>;
  }
}

class StateManager with ChangeNotifier {
  static final Logger _logger = Logger(); // ✅ Use a static logger for static methods
  static StateManager? _instance;

  final Map<String, ModuleState> _moduleStates = {}; // Stores structured module states
  Map<String, dynamic> _mainAppState = {
    'app_state': 'resumed',  // App lifecycle state (resumed, paused, etc.)
    'main_state': 'idle'     // Main app state (idle, active, busy, etc.)
  }; // Default main app state


  StateManager._internal();

  /// Factory method to provide the singleton instance
  factory StateManager() {
    if (_instance == null) {
      _instance = StateManager._internal();
      if (LOGGING_SWITCH) {
        _logger.info('📦 StateManager: Singleton instance created');
      }
    }
    return _instance!;
  }

  // ------ Module State Methods ------

  bool isModuleStateRegistered(String moduleKey) {
    final isRegistered = _moduleStates.containsKey(moduleKey);
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: isModuleStateRegistered($moduleKey) = $isRegistered');
    }
    return isRegistered;
  }

  /// ✅ Strictly register module states with `ModuleState` structure
  void registerModuleState(String moduleKey, dynamic initialState) {
    if (!_moduleStates.containsKey(moduleKey)) {
      // Convert LinkedMap/any Map to Map<String, dynamic> if needed
      dynamic processedState = initialState;
      if (initialState is Map && initialState is! Map<String, dynamic>) {
        processedState = initialState.map((key, value) => MapEntry(key.toString(), value));
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('📦 StateManager: Registering module state for "$moduleKey" with type: ${processedState.runtimeType}');
      }
      _moduleStates[moduleKey] = ModuleState(state: processedState);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
        if (LOGGING_SWITCH) {
          _logger.debug('📦 StateManager: Notified listeners after registering "$moduleKey"');
        }
      });
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('📦 StateManager: Module state "$moduleKey" already registered, skipping registration');
      }
    }
  }

  /// ✅ Unregister module state
  void unregisterModuleState(String moduleKey) {
    if (_moduleStates.containsKey(moduleKey)) {
      if (LOGGING_SWITCH) {
        _logger.info('📦 StateManager: Unregistering module state for "$moduleKey"');
      }
      _moduleStates.remove(moduleKey);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
        if (LOGGING_SWITCH) {
          _logger.debug('📦 StateManager: Notified listeners after unregistering "$moduleKey"');
        }
      });
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('📦 StateManager: Module state "$moduleKey" not found, cannot unregister');
      }
    }
  }

  T? getModuleState<T>(String moduleKey) {
    final ModuleState? storedState = _moduleStates[moduleKey];

    if (storedState == null) {
      if (LOGGING_SWITCH) {
        _logger.debug('📦 StateManager: getModuleState<$T>("$moduleKey") - Module state not found');
      }
      return null; // Ensure we don't attempt to access a null object
    }

    T? result;
    
    // Handle immutable state
    if (storedState.state is ImmutableState && T != Map<String, dynamic>) {
      if (storedState.state is T) {
        result = storedState.state as T;
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('📦 StateManager: getModuleState<$T>("$moduleKey") - Type mismatch, state is ${storedState.state.runtimeType}');
        }
        return null;
      }
    }
    // Handle legacy map-based state
    else if (T == Map<String, dynamic>) {
      if (storedState.state is Map) {
        // Handle any Map type (including LinkedMap from jsonDecode)
        // Convert to proper Map<String, dynamic>
        final mapState = storedState.state as Map;
        result = mapState.map((key, value) => MapEntry(key.toString(), value)) as T;
      } else if (storedState.state is ImmutableState) {
        // Convert immutable state to JSON for backward compatibility
        result = (storedState.state as ImmutableState).toJson() as T;
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('📦 StateManager: getModuleState<$T>("$moduleKey") - Cannot convert ${storedState.state.runtimeType} to Map');
        }
        return null;
      }
    }
    // Handle direct type match
    else if (storedState.state is T) {
      result = storedState.state as T;
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('📦 StateManager: getModuleState<$T>("$moduleKey") - Type mismatch, state is ${storedState.state.runtimeType}');
      }
      return null;
    }

    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getModuleState<$T>("$moduleKey") - Retrieved state (${storedState.state is ImmutableState ? "immutable" : "map"})');
    }
    return result;
  }


  /// Update module state (supports both immutable and legacy map-based states)
  void updateModuleState(String moduleKey, dynamic newState, {bool force = false}) {
    if (!_moduleStates.containsKey(moduleKey)) {
      if (LOGGING_SWITCH) {
        _logger.warning('📦 StateManager: updateModuleState("$moduleKey") - Module state not registered, cannot update');
      }
      return;
    }

    final existingState = _moduleStates[moduleKey];

    if (existingState != null) {
      // Handle immutable state updates
      if (newState is ImmutableState) {
        // Reference equality check (fast path for immutable objects)
        if (!force && identical(existingState.state, newState)) {
          if (LOGGING_SWITCH) {
            _logger.debug('📦 StateManager: updateModuleState("$moduleKey") - No change (identical reference), skipping update');
          }
          return;
        }
        
        // Structural equality check
        if (!force && existingState.state is ImmutableState && existingState.state == newState) {
          if (LOGGING_SWITCH) {
            _logger.debug('📦 StateManager: updateModuleState("$moduleKey") - No change (equal state), skipping update');
          }
          return;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('📦 StateManager: Updating module state "$moduleKey" (immutable)');
        }
        _moduleStates[moduleKey] = ModuleState(state: newState);
      }
      // Handle legacy map-based state updates (including LinkedMap from jsonDecode)
      else if (newState is Map) {
        if (existingState.state is ImmutableState) {
          if (LOGGING_SWITCH) {
            _logger.error('📦 StateManager: updateModuleState("$moduleKey") - Cannot update immutable state with map. Use immutable state object.');
          }
          return;
        }
        
        // Convert LinkedMap/any Map to Map<String, dynamic> for merging
        final newStateMap = newState.map((key, value) => MapEntry(key.toString(), value));
        final newKeys = newStateMap.keys.toList();
        if (LOGGING_SWITCH) {
          _logger.info('📦 StateManager: Updating module state "$moduleKey" (map) - Keys to update: $newKeys');
        }
      
        // Use deprecated merge for backward compatibility
        final newMergedState = existingState.merge(newStateMap);
      _moduleStates[moduleKey] = newMergedState;
      } else {
        if (LOGGING_SWITCH) {
          _logger.error('📦 StateManager: updateModuleState("$moduleKey") - Invalid state type: ${newState.runtimeType}');
        }
        return;
      }
      
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
        if (LOGGING_SWITCH) {
          _logger.debug('📦 StateManager: Notified listeners after updating "$moduleKey"');
        }
      });
    } else {
      if (LOGGING_SWITCH) {
        _logger.error('📦 StateManager: updateModuleState("$moduleKey") - Existing state is null');
      }
    }
  }

  /// Returns a map of all registered module states
  /// Note: Immutable states are converted to JSON for backward compatibility
  Map<String, Map<String, dynamic>> getAllModuleStates() {
    final allStates = _moduleStates.map((key, value) {
      if (value.state is ImmutableState) {
        return MapEntry(key, (value.state as ImmutableState).toJson());
      } else if (value.state is Map<String, dynamic>) {
        return MapEntry(key, value.state as Map<String, dynamic>);
      } else {
        return MapEntry(key, <String, dynamic>{});
      }
    });
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getAllModuleStates() - Returning ${allStates.length} module states: ${allStates.keys.toList()}');
    }
    return allStates;
  }

  /// Returns a map of all registered states including main app state
  Map<String, dynamic> getAllStates() {
    final moduleStates = getAllModuleStates();
    final allStates = {
      'module_states': moduleStates,
      'main_app_state': _mainAppState,
    };
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getAllStates() - Returning all states (${moduleStates.length} modules + main app state)');
    }
    return allStates;
  }

  /// Returns a list of all registered module keys
  List<String> getRegisteredModuleKeys() {
    final keys = _moduleStates.keys.toList();
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getRegisteredModuleKeys() - Returning ${keys.length} keys: $keys');
    }
    return keys;
  }

  /// Returns the number of registered module states
  int getModuleStateCount() {
    final count = _moduleStates.length;
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getModuleStateCount() - Returning $count');
    }
    return count;
  }

  /// Returns true if any module state is registered
  bool hasModuleStates() {
    final hasStates = _moduleStates.isNotEmpty;
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: hasModuleStates() - Returning $hasStates');
    }
    return hasStates;
  }

  // ------ Main App State Methods ------

  void setMainAppState(Map<String, dynamic> initialState) {
    final oldState = Map<String, dynamic>.from(_mainAppState);
    _mainAppState = {
      'app_state': 'resumed',  // App lifecycle state (resumed, paused, etc.)
      'main_state': 'idle',    // Main app state (idle, active, busy, etc.)
      ...initialState
    };
    if (LOGGING_SWITCH) {
      _logger.info('📦 StateManager: setMainAppState() - Old state: $oldState, New state: $_mainAppState');
    }
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() {
      notifyListeners();
      if (LOGGING_SWITCH) {
        _logger.debug('📦 StateManager: Notified listeners after setMainAppState()');
      }
    });
  }

  Map<String, dynamic> get mainAppState {
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: mainAppState getter - Returning ${_mainAppState.length} keys: ${_mainAppState.keys.toList()}');
    }
    return _mainAppState;
  }

  void updateMainAppState(String key, dynamic value) {
    final oldValue = _mainAppState[key];
    _mainAppState[key] = value;
    if (LOGGING_SWITCH) {
      _logger.info('📦 StateManager: updateMainAppState("$key") - Old value: $oldValue, New value: $value');
    }
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() {
      notifyListeners();
      if (LOGGING_SWITCH) {
        _logger.debug('📦 StateManager: Notified listeners after updateMainAppState("$key")');
      }
    });
  }

  T? getMainAppState<T>(String key) {
    final value = _mainAppState[key] as T?;
    if (LOGGING_SWITCH) {
      _logger.debug('📦 StateManager: getMainAppState<$T>("$key") - Returning: $value');
    }
    return value;
  }
}
