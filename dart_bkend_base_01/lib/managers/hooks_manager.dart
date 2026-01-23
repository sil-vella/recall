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
      if (LOGGING_SWITCH) {
        _logger.error('❌ Hook "$hookName" is already registered');
      }
      throw ArgumentError('Hook "$hookName" is already registered.');
    }
    
    _hooks[hookName] = [];
    if (LOGGING_SWITCH) {
      _logger.info('🎣 Hook registered: $hookName');
    }
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
    
    if (LOGGING_SWITCH) {
      _logger.info(
        '🎣 Callback registered: $hookName -> $callbackName (priority: $priority)$contextInfo',
      );
    }
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
    
    if (LOGGING_SWITCH) {
      _logger.info(
        '🎣 Triggering hook: $hookName (${callbacks.length} callbacks registered)',
      );
      if (data != null) {
        _logger.debug('🎣 Hook data: $data');
      }
    }
    
    for (final hookCallback in callbacks) {
      // Execute only callbacks matching the context or global callbacks (no context)
      if (context == null || hookCallback.context == context) {
        try {
          if (LOGGING_SWITCH) {
            _logger.debug(
              '🎣 Executing callback: $hookName (priority: ${hookCallback.priority})',
            );
          }
          
          // Call the callback with data
          hookCallback.callback(data);
          executedCount++;
          
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error(
              '❌ Error in hook callback: $hookName - $e',
            );
          }
          // Continue executing remaining callbacks (don't break hook chain)
        }
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info(
        '🎣 Hook completed: $hookName ($executedCount callbacks executed)',
      );
    }
  }

  /// Clear all callbacks registered to a specific hook
  void clearHook(String hookName) {
    if (_hooks.containsKey(hookName)) {
      final count = _hooks[hookName]!.length;
      _hooks[hookName]!.clear();
      if (LOGGING_SWITCH) {
        _logger.info('🎣 Cleared hook: $hookName ($count callbacks removed)');
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('🎣 Hook not found for clearing: $hookName');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('🎣 HooksManager disposed ($hookCount hooks cleared)');
    }
  }
}
