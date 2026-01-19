import '../utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false; // Enabled for rank-based matching testing

/// Represents a hook callback with priority and optional context
class HookCallback {
  final int priority;
  final Function callback;
  final String? context;
  
  HookCallback(this.callback, this.priority, this.context);
}

/// Hooks Manager - Event-driven callback system matching Python HooksManager
/// 
/// Enables modules to register callbacks for WebSocket events like room creation,
/// room joining, and room closure. Used for game creation logic and other event-driven features.
class HooksManager {
  final Map<String, List<HookCallback>> _hooks = {
    'app_startup': [], // Predefined default hook
  };
  
  final Logger _logger = Logger();

  /// Register a new hook with the given name
  void registerHook(String hookName) {
    if (_hooks.containsKey(hookName)) {
      _logger.error('❌ Hook "$hookName" is already registered', isOn: LOGGING_SWITCH);
      throw ArgumentError('Hook "$hookName" is already registered.');
    }
    
    _hooks[hookName] = [];
    _logger.info('🎣 Hook registered: $hookName', isOn: LOGGING_SWITCH);
  }

  /// Register a callback function to a specific hook with priority and optional context
  /// 
  /// [hookName] The name of the hook
  /// [callback] The callback function to register
  /// [priority] The priority of the callback (lower number = higher priority)
  /// [context] Optional context for filtering callbacks
  void registerHookCallback(
    String hookName, 
    Function callback, {
    int priority = 10,
    String? context,
  }) {
    // Auto-register hook if it doesn't exist (matching Python behavior)
    if (!_hooks.containsKey(hookName)) {
      registerHook(hookName);
    }
    
    final hookCallback = HookCallback(callback, priority, context);
    _hooks[hookName]!.add(hookCallback);
    
    // Sort callbacks by priority (lower number = higher priority)
    _hooks[hookName]!.sort((a, b) => a.priority.compareTo(b.priority));
    
    final contextInfo = context != null ? ' (context: $context)' : '';
    final callbackName = callback.toString().split(' ').last.replaceAll(')', '');
    
    _logger.info(
      '🎣 Callback registered: $hookName -> $callbackName (priority: $priority)$contextInfo',
      isOn: LOGGING_SWITCH,
    );
  }

  /// Trigger a specific hook, executing callbacks matching the context
  /// 
  /// [hookName] The name of the hook to trigger
  /// [data] Optional data to pass to the callbacks
  /// [context] Optional context to filter callbacks
  void triggerHook(
    String hookName, {
    Map<String, dynamic>? data,
    String? context,
  }) {
    // Auto-register hook if it doesn't exist (matching Python behavior)
    if (!_hooks.containsKey(hookName)) {
      registerHook(hookName);
    }
    
    final callbacks = _hooks[hookName]!;
    int executedCount = 0;
    
    _logger.info(
      '🎣 Triggering hook: $hookName (${callbacks.length} callbacks registered)',
      isOn: LOGGING_SWITCH,
    );
    
    if (data != null) {
      _logger.debug('🎣 Hook data: $data', isOn: LOGGING_SWITCH);
    }
    
    for (final hookCallback in callbacks) {
      // Execute only callbacks matching the context or global callbacks (no context)
      if (context == null || hookCallback.context == context) {
        try {
          _logger.debug(
            '🎣 Executing callback: $hookName (priority: ${hookCallback.priority})',
            isOn: LOGGING_SWITCH,
          );
          
          // Call the callback with data
          hookCallback.callback(data);
          executedCount++;
          
        } catch (e) {
          _logger.error(
            '❌ Error in hook callback: $hookName - $e',
            isOn: LOGGING_SWITCH,
          );
          // Continue executing remaining callbacks (don't break hook chain)
        }
      }
    }
    
    _logger.info(
      '🎣 Hook completed: $hookName ($executedCount callbacks executed)',
      isOn: LOGGING_SWITCH,
    );
  }

  /// Clear all callbacks registered to a specific hook
  void clearHook(String hookName) {
    if (_hooks.containsKey(hookName)) {
      final count = _hooks[hookName]!.length;
      _hooks[hookName]!.clear();
      _logger.info('🎣 Cleared hook: $hookName ($count callbacks removed)', isOn: LOGGING_SWITCH);
    } else {
      _logger.warning('🎣 Hook not found for clearing: $hookName', isOn: LOGGING_SWITCH);
    }
  }

  /// Get the number of callbacks registered for a hook
  int getHookCallbackCount(String hookName) {
    return _hooks[hookName]?.length ?? 0;
  }

  /// Get all registered hook names
  List<String> getRegisteredHooks() {
    return _hooks.keys.toList();
  }

  /// Check if a hook is registered
  bool isHookRegistered(String hookName) {
    return _hooks.containsKey(hookName);
  }

  /// Dispose of all hooks and their callbacks
  void dispose() {
    final hookCount = _hooks.length;
    _hooks.clear();
    _logger.info('🎣 HooksManager disposed ($hookCount hooks cleared)', isOn: LOGGING_SWITCH);
  }
}
