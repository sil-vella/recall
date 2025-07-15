import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';
import '../00_base/module_base.dart';

/// class ModuleManager - Manages application state and operations
///
/// Manages application state and operations
///
/// Example:
/// ```dart
/// final modulemanager = ModuleManager();
/// ```
///
class ModuleManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final ModuleManager _instance = ModuleManager._internal();
  factory ModuleManager() => _instance;
  ModuleManager._internal();

  final Map<String, ModuleBase> _modules = {};
  final List<String> _moduleLoadOrder = [];
  final Map<String, String> _initializationErrors = {};

  // Getter to access modules
  Map<String, ModuleBase> get modules => _modules;

  /// ✅ Register a module manually
  void registerModule(String moduleKey, ModuleBase module) {
    if (_modules.containsKey(moduleKey)) {
      _log.error('❌ Module with key "$moduleKey" is already registered.');
      return;
    }

    _modules[moduleKey] = module;
    _log.info('✅ Module registered: $moduleKey');
    notifyListeners();
  }

  /// ✅ Get a specific module by key
  ModuleBase? getModule(String moduleKey) {
    final module = _modules[moduleKey];
    if (module == null) {
      _log.error('❌ Module "$moduleKey" is not registered.');
    }
    return module;
  }

  /// ✅ Get module by type
  T? getModuleByType<T extends ModuleBase>() {
    for (var module in _modules.values) {
      if (module is T) {
        return module;
      }
    }
    _log.error('❌ No module found of type: ${T.toString()}');
    return null;
  }

  /// ✅ Initialize all registered modules
  Future<void> initializeModules(BuildContext context) async {
    _log.info('🚀 Starting module initialization process...');

    // Clear initialization state but don't dispose modules
    _moduleLoadOrder.clear();
    _initializationErrors.clear();

    // Initialize modules in registration order
    for (var entry in _modules.entries) {
      final moduleKey = entry.key;
      final module = entry.value;

      try {
        _log.info('🔄 Initializing module: $moduleKey');
        module.initialize(context, this);
        _moduleLoadOrder.add(moduleKey);
        _log.info('✅ Module $moduleKey initialized successfully');
      } catch (e) {
        final errorMsg = 'Failed to initialize module $moduleKey: $e';
        _log.error('❌ $errorMsg');
        _initializationErrors[moduleKey] = errorMsg;
      }
    }

    // Summary
    final initializedCount = _modules.values.where((m) => m.isInitialized).length;
    _log.info('✅ Module initialization complete: $initializedCount/${_modules.length} modules initialized');

    if (_initializationErrors.isNotEmpty) {
      _log.error('⚠️ Initialization errors: $_initializationErrors');
    }

    notifyListeners();
  }

  /// ✅ Get module status
  Map<String, dynamic> getModuleStatus() {
    final moduleStatus = <String, Map<String, dynamic>>{};
    
    for (var entry in _modules.entries) {
      final moduleKey = entry.key;
      final module = entry.value;
      
      moduleStatus[moduleKey] = {
        'info': module.getModuleInfo(),
        'health': module.healthCheck(),
      };
    }

    return {
      'total_modules': _modules.length,
      'initialized_modules': _modules.values.where((m) => m.isInitialized).length,
      'module_load_order': _moduleLoadOrder,
      'initialization_errors': _initializationErrors,
      'modules': moduleStatus,
    };
  }

  /// ✅ Call a method on a specific module
  dynamic callModuleMethod(String moduleKey, String methodName, [List<dynamic>? args, Map<String, dynamic>? kwargs]) {
    final module = getModule(moduleKey);
    if (module == null) {
      throw Exception('Module "$moduleKey" is not registered.');
    }

    // Use reflection to call the method
    final mirror = (module as dynamic);
    if (mirror.hasMethod(methodName)) {
      _log.info('📞 Calling method "$methodName" on module "$moduleKey"');
      final result = mirror[methodName](args ?? [], kwargs ?? {});
      _log.info('✅ Method "$methodName" on module "$moduleKey" completed');
      return result;
    } else {
      throw Exception('Module "$moduleKey" has no method "$methodName"');
    }
  }

  /// ✅ Deregister a module
  void deregisterModule(String moduleKey) {
    if (!_modules.containsKey(moduleKey)) {
      _log.error('❌ Module "$moduleKey" is not registered.');
      return;
    }

    final module = _modules[moduleKey]!;
    module.dispose();
    _modules.remove(moduleKey);
    _moduleLoadOrder.remove(moduleKey);
    _initializationErrors.remove(moduleKey);

    _log.info('✅ Module deregistered: $moduleKey');
    notifyListeners();
  }

  /// ✅ Dispose all modules
  void dispose() {
    for (var module in _modules.values) {
      module.dispose();
    }
    _modules.clear();
    _moduleLoadOrder.clear();
    _initializationErrors.clear();
    _log.info('🗑 All modules disposed.');
    notifyListeners();
  }
}
