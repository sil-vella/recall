import '../../tools/logging/logger.dart';

typedef HookCallback = void Function();

class HooksManager {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  static final HooksManager _instance = HooksManager._internal();

  factory HooksManager() => _instance;

  HooksManager._internal();

  // Map of hooks with a list of (priority, callback) pairs
  final Map<String, List<MapEntry<int, HookCallback>>> _hooks = {};

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


  /// Deregister all hooks for a specific event
  void deregisterHook(String hookName) {
    _hooks.remove(hookName);
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
}
