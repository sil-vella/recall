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

/// class StateManager - Manages application state and operations
///
/// Manages application state and operations
///
/// Example:
/// ```dart
/// final statemanager = StateManager();
/// ```
///
class StateManager with ChangeNotifier {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods
  static StateManager? _instance;

  final Map<String, ModuleState> _moduleStates = {}; // Stores structured module states
  Map<String, dynamic> _mainAppState = {
    'app_state': 'resumed',  // App lifecycle state (resumed, paused, etc.)
    'main_state': 'idle'     // Main app state (idle, active, busy, etc.)
  }; // Default main app state


  StateManager._internal() {
    _log.info('StateManager instance created.');
  }

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
      _log.info("✅ Registered module state for key: $moduleKey");
      _log.info("📊 Current app state after registration:");
      _logAppState();
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    } else {
      _log.error("⚠️ Module state for '$moduleKey' is already registered.");
    }
  }

  /// ✅ Unregister module state
  void unregisterModuleState(String moduleKey) {
    if (_moduleStates.containsKey(moduleKey)) {
      _moduleStates.remove(moduleKey);
      _log.info("🗑 Unregistered state for key: $moduleKey");
      _log.info("📊 Current app state after unregistration:");
      _logAppState();
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    } else {
      _log.error("⚠️ Module state for '$moduleKey' does not exist.");
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

    _log.error("❌ Type mismatch: Requested '$T' but found '${storedState.state.runtimeType}' for module '$moduleKey'");
    return null;
  }

  /// Log the entire app state for debugging
  void _logAppState() {
    final allStates = getAllStates();
    _log.info("📊 Complete App State:");
    _log.info("🔧 Module States: ${allStates['module_states']}");
    _log.info("📱 Main App State: ${allStates['main_app_state']}");
    _log.info("📈 Total Module States: ${getModuleStateCount()}");
    _log.info("🔑 Registered Keys: ${getRegisteredModuleKeys()}");
  }

  void updateModuleState(String moduleKey, Map<String, dynamic> newState, {bool force = false}) {
    if (!_moduleStates.containsKey(moduleKey)) {
      _log.error("❌ Cannot update state for '$moduleKey' - it is not registered.");
      return;
    }

    final existingState = _moduleStates[moduleKey];

    if (existingState != null) {
      // ✅ Ensure `merge` exists (assuming it's a custom method)
      final newMergedState = existingState.merge(newState);
      _moduleStates[moduleKey] = newMergedState;
      _log.info("✅ Updated state for module '$moduleKey'");
      _log.info("📊 Current app state after update:");
      _logAppState();
      // Use Future.microtask to avoid calling notifyListeners during build
      Future.microtask(() => notifyListeners());
    } else {
      _log.error("❌ Cannot update state for '$moduleKey' - existing state is null");
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
    _log.info("📌 Main app state initialized: $_mainAppState");
    _log.info("📊 Current app state after main app state initialization:");
    _logAppState();
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() => notifyListeners());
  }

  Map<String, dynamic> get mainAppState => _mainAppState;

  void updateMainAppState(String key, dynamic value) {
    _mainAppState[key] = value;
    _log.info("📌 Main app state updated: key=$key, value=$value");
    _log.info("📊 Current app state after main app state update:");
    _logAppState();
    // Use Future.microtask to avoid calling notifyListeners during build
    Future.microtask(() => notifyListeners());
  }

  T? getMainAppState<T>(String key) {
    return _mainAppState[key] as T?;
  }
}
