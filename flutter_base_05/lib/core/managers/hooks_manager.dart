import '../../tools/logging/logger.dart';

typedef HookCallback = void Function();
typedef HookCallbackWithData = void Function(Map<String, dynamic> data);

class HooksManager {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  static final HooksManager _instance = HooksManager._internal();

  factory HooksManager() => _instance;

  HooksManager._internal();

  // Map of hooks with a list of (priority, callback) pairs
  final Map<String, List<MapEntry<int, HookCallback>>> _hooks = {};
  
  // Map of hooks with data support
  final Map<String, List<MapEntry<int, HookCallbackWithData>>> _hooksWithData = {};

  void registerHook(String hookName, HookCallback callback, {int priority = 10}) {
    _log.info('Registering hook: $hookName with priority $priority');

    if (_hooks.containsKey(hookName) &&
        _hooks[hookName]!.any((entry) => entry.value == callback)) {
      _log.info('⚠️ Hook "$hookName" already has this callback registered. Skipping.');
      return;
    }

    _hooks.putIfAbsent(hookName, () => []).add(MapEntry(priority, callback));
    _hooks[hookName]!.sort((a, b) => a.key.compareTo(b.key)); // Sort by priority
    _log.info('Current hooks: $hookName - ${_hooks[hookName]}');
  }

  void registerHookWithData(String hookName, HookCallbackWithData callback, {int priority = 10}) {
    _log.info('Registering hook with data: $hookName with priority $priority');

    if (_hooksWithData.containsKey(hookName) &&
        _hooksWithData[hookName]!.any((entry) => entry.value == callback)) {
      _log.info('⚠️ Hook with data "$hookName" already has this callback registered. Skipping.');
      return;
    }

    _hooksWithData.putIfAbsent(hookName, () => []).add(MapEntry(priority, callback));
    _hooksWithData[hookName]!.sort((a, b) => a.key.compareTo(b.key)); // Sort by priority
    _log.info('Current hooks with data: $hookName - ${_hooksWithData[hookName]}');
  }

  void triggerHook(String hookName) {
    _hooks.putIfAbsent(hookName, () => []); // ✅ Ensure the hook exists

    if (_hooks[hookName]!.isNotEmpty) {
      _log.info('Triggering hook: $hookName with ${_hooks[hookName]!.length} callbacks');
      for (final entry in _hooks[hookName]!) {
        _log.info('Executing callback for hook: $hookName with priority ${entry.key}');
        entry.value(); // Execute the callback
      }
    } else {
      _log.info('⚠️ Hook "$hookName" triggered but has no registered callbacks.');
    }
  }

  void triggerHookWithData(String hookName, Map<String, dynamic> data) {
    _hooksWithData.putIfAbsent(hookName, () => []); // ✅ Ensure the hook exists

    if (_hooksWithData[hookName]!.isNotEmpty) {
      _log.info('Triggering hook with data: $hookName with ${_hooksWithData[hookName]!.length} callbacks');
      for (final entry in _hooksWithData[hookName]!) {
        _log.info('Executing callback for hook: $hookName with priority ${entry.key}');
        entry.value(data); // Execute the callback with data
      }
    } else {
      _log.info('⚠️ Hook with data "$hookName" triggered but has no registered callbacks.');
    }
  }

  /// Deregister all hooks for a specific event
  void deregisterHook(String hookName) {
    _hooks.remove(hookName);
    _hooksWithData.remove(hookName);
    _log.info('Deregistered all callbacks for hook: $hookName');
  }

  /// Deregister a specific callback from a hook
  void deregisterCallback(String hookName, HookCallback callback) {
    _hooks[hookName]?.removeWhere((entry) => entry.value == callback);
    if (_hooks[hookName]?.isEmpty ?? true) {
      _hooks.remove(hookName);
    }
    _log.info('Deregistered a callback for hook: $hookName');
  }

  /// Deregister a specific callback with data from a hook
  void deregisterCallbackWithData(String hookName, HookCallbackWithData callback) {
    _hooksWithData[hookName]?.removeWhere((entry) => entry.value == callback);
    if (_hooksWithData[hookName]?.isEmpty ?? true) {
      _hooksWithData.remove(hookName);
    }
    _log.info('Deregistered a callback with data for hook: $hookName');
  }
}
