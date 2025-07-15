import 'package:flutter/material.dart';
import '../managers/module_manager.dart';

abstract class ModuleBase {
  final String moduleKey;
  final List<String> dependencies;
  bool _initialized = false;
  late BuildContext _context;
  late ModuleManager _moduleManager;

  /// ✅ Constructor without auto-registration
  ModuleBase(this.moduleKey, {List<String>? dependencies})
      : dependencies = dependencies ?? [];

  /// ✅ Get initialization status
  bool get isInitialized => _initialized;

  /// ✅ Get module dependencies
  List<String> get moduleDependencies => dependencies;

  /// ✅ Initialize the module with context and module manager
  void initialize(BuildContext context, ModuleManager moduleManager) {
    _context = context;
    _moduleManager = moduleManager;
    _initialized = true;
  }

  /// ✅ Dispose method to clean up resources
  void dispose() {
    _initialized = false;
  }

  /// ✅ Get module information
  Map<String, dynamic> getModuleInfo() {
    return {
      'moduleKey': moduleKey,
      'initialized': _initialized,
      'dependencies': dependencies,
    };
  }

  /// ✅ Health check for the module
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': _initialized ? 'healthy' : 'not_initialized',
      'details': _initialized ? 'Module is functioning normally' : 'Module not initialized'
    };
  }
}
