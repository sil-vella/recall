typedef HookCallback = void Function();
typedef HookCallbackWithData = void Function(Map<String, dynamic> data);

class HooksManager {

  static final HooksManager _instance = HooksManager._internal();

  factory HooksManager() => _instance;

  HooksManager._internal();

  // App initialization state
  bool _isAppInitialized = false;
  final List<Map<String, dynamic>> _pendingHooks = [];

  // Map of hooks with a list of (priority, callback) pairs
  final Map<String, List<MapEntry<int, HookCallback>>> _hooks = {};
  
  // Map of hooks with data support
  final Map<String, List<MapEntry<int, HookCallbackWithData>>> _hooksWithData = {};
  
  // Track hooks that have been triggered and their last data (for late-registering listeners)
  final Map<String, Map<String, dynamic>?> _triggeredHooksData = {};

  void registerHook(String hookName, HookCallback callback, {int priority = 10}) {

    if (_hooks.containsKey(hookName) &&
        _hooks[hookName]!.any((entry) => entry.value == callback)) {
      return;
    }

    _hooks.putIfAbsent(hookName, () => []).add(MapEntry(priority, callback));
    _hooks[hookName]!.sort((a, b) => a.key.compareTo(b.key)); // Sort by priority
  }

  void registerHookWithData(String hookName, HookCallbackWithData callback, {int priority = 10}) {
    if (_hooksWithData.containsKey(hookName) &&
        _hooksWithData[hookName]!.any((entry) => entry.value == callback)) {
      return;
    }

    _hooksWithData.putIfAbsent(hookName, () => []).add(MapEntry(priority, callback));
    _hooksWithData[hookName]!.sort((a, b) => a.key.compareTo(b.key)); // Sort by priority
    
    // If this hook was already triggered, immediately call the new callback with the last data
    // This ensures late-registering modules (like after async initialization) still get the hook
    if (_triggeredHooksData.containsKey(hookName) && _isAppInitialized) {
      final lastData = _triggeredHooksData[hookName];
      if (lastData != null) {
        // Execute the newly registered callback immediately with the last data
        callback(lastData);
      }
    }
  }

  void triggerHook(String hookName) {
    _hooks.putIfAbsent(hookName, () => []); // ✅ Ensure the hook exists

    if (!_isAppInitialized) {
      _pendingHooks.add({
        'type': 'simple',
        'hookName': hookName,
        'data': null,
      });
      return;
    }

    if (_hooks[hookName]!.isNotEmpty) {
      for (final entry in _hooks[hookName]!) {
        entry.value(); // Execute the callback
      }
    } else {
    }
  }

  void triggerHookWithData(String hookName, Map<String, dynamic> data) {
    _hooksWithData.putIfAbsent(hookName, () => []); // ✅ Ensure the hook exists

    if (!_isAppInitialized) {
      _pendingHooks.add({
        'type': 'with_data',
        'hookName': hookName,
        'data': data,
      });
      return;
    }

    // Store the data for this hook so late-registering listeners can receive it
    _triggeredHooksData[hookName] = data;

    if (_hooksWithData[hookName]!.isNotEmpty) {
      for (final entry in _hooksWithData[hookName]!) {
        entry.value(data); // Execute the callback with data
      }
    } else {
    }
  }

  /// Deregister all hooks for a specific event
  void deregisterHook(String hookName) {
    _hooks.remove(hookName);
    _hooksWithData.remove(hookName);
    _triggeredHooksData.remove(hookName); // Clean up triggered data
  }

  /// Deregister a specific callback from a hook
  void deregisterCallback(String hookName, HookCallback callback) {
    _hooks[hookName]?.removeWhere((entry) => entry.value == callback);
    if (_hooks[hookName]?.isEmpty ?? true) {
      _hooks.remove(hookName);
    }
  }

  /// Deregister a specific callback with data from a hook
  void deregisterCallbackWithData(String hookName, HookCallbackWithData callback) {
    _hooksWithData[hookName]?.removeWhere((entry) => entry.value == callback);
    if (_hooksWithData[hookName]?.isEmpty ?? true) {
      _hooksWithData.remove(hookName);
    }
  }

  /// ✅ Mark app as initialized and process pending hooks
  void markAppInitialized() {
    _isAppInitialized = true;
    
    if (_pendingHooks.isNotEmpty) {
      
      for (final pendingHook in _pendingHooks) {
        if (pendingHook['type'] == 'simple') {
          triggerHook(pendingHook['hookName']);
        } else if (pendingHook['type'] == 'with_data') {
          triggerHookWithData(pendingHook['hookName'], pendingHook['data']);
        }
      }
      
      _pendingHooks.clear();
    } else {
    }
  }

  /// ✅ Check if app is initialized
  bool get isAppInitialized => _isAppInitialized;

  /// ✅ Get pending hooks count
  int get pendingHooksCount => _pendingHooks.length;
}
