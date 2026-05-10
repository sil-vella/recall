import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'state/immutable_state.dart';

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
    }
    return _instance!;
  }

  // ------ Module State Methods ------

  bool isModuleStateRegistered(String moduleKey) {
    return _moduleStates.containsKey(moduleKey);
  }

  /// ✅ Strictly register module states with `ModuleState` structure
  void registerModuleState(String moduleKey, dynamic initialState) {
    if (!_moduleStates.containsKey(moduleKey)) {
      // Convert LinkedMap/any Map to Map<String, dynamic> if needed
      dynamic processedState = initialState;
      if (initialState is Map && initialState is! Map<String, dynamic>) {
        processedState = initialState.map((key, value) => MapEntry(key.toString(), value));
      }
      
      _moduleStates[moduleKey] = ModuleState(state: processedState);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
      });
    }
  }

  /// ✅ Unregister module state
  void unregisterModuleState(String moduleKey) {
    if (_moduleStates.containsKey(moduleKey)) {
      _moduleStates.remove(moduleKey);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
      });
    }
  }

  T? getModuleState<T>(String moduleKey) {
    final ModuleState? storedState = _moduleStates[moduleKey];

    if (storedState == null) {
      return null; // Ensure we don't attempt to access a null object
    }

    T? result;
    
    // Handle immutable state
    if (storedState.state is ImmutableState && T != Map<String, dynamic>) {
      if (storedState.state is T) {
        result = storedState.state as T;
      } else {
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
        return null;
      }
    }
    // Handle direct type match
    else if (storedState.state is T) {
      result = storedState.state as T;
    } else {
      return null;
    }

    return result;
  }


  /// Update module state (supports both immutable and legacy map-based states)
  void updateModuleState(String moduleKey, dynamic newState, {bool force = false}) {
    if (!_moduleStates.containsKey(moduleKey)) {
      return;
    }

    final existingState = _moduleStates[moduleKey];

    if (existingState != null) {
      // Handle immutable state updates
      if (newState is ImmutableState) {
        // Reference equality check (fast path for immutable objects)
        if (!force && identical(existingState.state, newState)) {
          return;
        }
        
        // Structural equality check
        if (!force && existingState.state is ImmutableState && existingState.state == newState) {
          return;
        }
        
        _moduleStates[moduleKey] = ModuleState(state: newState);
      }
      // Handle legacy map-based state updates (including LinkedMap from jsonDecode)
      else if (newState is Map) {
        if (existingState.state is ImmutableState) {
          return;
        }
        
        // Convert LinkedMap/any Map to Map<String, dynamic> for merging
        final newStateMap = newState.map((key, value) => MapEntry(key.toString(), value));
      
        // Use deprecated merge for backward compatibility
        final newMergedState = existingState.merge(newStateMap);
      _moduleStates[moduleKey] = newMergedState;
      } else {
        return;
      }
      
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() {
        notifyListeners();
      });
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
    return allStates;
  }

  /// Returns a map of all registered states including main app state
  Map<String, dynamic> getAllStates() {
    final moduleStates = getAllModuleStates();
    final allStates = {
      'module_states': moduleStates,
      'main_app_state': _mainAppState,
    };
    return allStates;
  }

  /// Returns a list of all registered module keys
  List<String> getRegisteredModuleKeys() {
    return _moduleStates.keys.toList();
  }

  /// Returns the number of registered module states
  int getModuleStateCount() {
    return _moduleStates.length;
  }

  /// Returns true if any module state is registered
  bool hasModuleStates() {
    return _moduleStates.isNotEmpty;
  }

  // ------ Main App State Methods ------

  void setMainAppState(Map<String, dynamic> initialState) {
    _mainAppState = {
      'app_state': 'resumed',  // App lifecycle state (resumed, paused, etc.)
      'main_state': 'idle',    // Main app state (idle, active, busy, etc.)
      ...initialState
    };
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() {
      notifyListeners();
    });
  }

  Map<String, dynamic> get mainAppState {
    return _mainAppState;
  }

  void updateMainAppState(String key, dynamic value) {
    _mainAppState[key] = value;
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() {
      notifyListeners();
    });
  }

  T? getMainAppState<T>(String key) {
    return _mainAppState[key] as T?;
  }
}
