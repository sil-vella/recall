import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';

class ModuleState {
  final Map<String, dynamic> state;

  ModuleState({required this.state});

  /// Ensures all keys are Strings and values are valid JSON types
  factory ModuleState.fromDynamic(Map<dynamic, dynamic> rawState) {
    return ModuleState(
      state: rawState.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  /// Merges the new state with the existing one
  ModuleState merge(Map<String, dynamic> newState) {
    return ModuleState(state: {...state, ...newState});
  }
}

class StateManager with ChangeNotifier {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods
  static StateManager? _instance;

  final Map<String, ModuleState> _moduleStates = {}; // Stores structured module states
  Map<String, dynamic> _mainAppState = {
    'app_state': 'resumed',  // App lifecycle state (resumed, paused, etc.)
    'main_state': 'idle'     // Main app state (idle, active, busy, etc.)
  }; // Default main app state


  StateManager._internal();

  /// Factory method to provide the singleton instance
  factory StateManager() {
    _instance ??= StateManager._internal();
    return _instance!;
  }

  // ------ Module State Methods ------

  bool isModuleStateRegistered(String moduleKey) {
    return _moduleStates.containsKey(moduleKey);
  }

  /// ✅ Strictly register module states with `ModuleState` structure
  void registerModuleState(String moduleKey, Map<String, dynamic> initialState) {
    if (!_moduleStates.containsKey(moduleKey)) {
      _moduleStates[moduleKey] = ModuleState(state: initialState);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    }
  }

  /// ✅ Unregister module state
  void unregisterModuleState(String moduleKey) {
    if (_moduleStates.containsKey(moduleKey)) {
      _moduleStates.remove(moduleKey);
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    }
  }

  T? getModuleState<T>(String moduleKey) {
    final ModuleState? storedState = _moduleStates[moduleKey];

    if (storedState == null) {
      return null; // Ensure we don't attempt to access a null object
    }

    if (T == Map<String, dynamic>) {
      // Ensure that all keys are Strings and cast properly
      return storedState.state.map((key, value) => MapEntry(key.toString(), value)) as T;
    }

    if (storedState.state is T) {
      return storedState.state as T;
    }

    return null;
  }

  /// Log the entire app state for debugging
  void _logAppState() {
    // Logging functionality removed
  }

  void updateModuleState(String moduleKey, Map<String, dynamic> newState, {bool force = false}) {
    if (!_moduleStates.containsKey(moduleKey)) {
      return;
    }

    final existingState = _moduleStates[moduleKey];

    if (existingState != null) {
      // ✅ Ensure `merge` exists (assuming it's a custom method)
      final newMergedState = existingState.merge(newState);
      _moduleStates[moduleKey] = newMergedState;
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    }
  }

  /// Returns a map of all registered module states
  Map<String, Map<String, dynamic>> getAllModuleStates() {
    return _moduleStates.map((key, value) => MapEntry(key, value.state));
  }

  /// Returns a map of all registered states including main app state
  Map<String, dynamic> getAllStates() {
    return {
      'module_states': getAllModuleStates(),
      'main_app_state': _mainAppState,
    };
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
    Future.microtask(() => notifyListeners());
  }

  Map<String, dynamic> get mainAppState => _mainAppState;

  void updateMainAppState(String key, dynamic value) {
    _mainAppState[key] = value;
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() => notifyListeners());
  }

  T? getMainAppState<T>(String key) {
    return _mainAppState[key] as T?;
  }
}
