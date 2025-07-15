import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../tools/logging/logger.dart';

/// Template for creating new modules
/// 
/// Usage:
/// 1. Copy this file to your new module directory
/// 2. Rename the class to your module name
/// 3. Implement required methods
/// 4. Add your module-specific functionality
class TemplateModule extends ModuleBase {
  static final Logger _log = Logger();
  late ModuleManager _localModuleManager;
  late ServicesManager _servicesManager;

  /// ✅ Constructor with module key and dependencies
  TemplateModule() : super("template_module", dependencies: []);

  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _localModuleManager = moduleManager;
    _initDependencies(context);
    _log.info('✅ TemplateModule initialized with context.');
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    // Add other dependencies as needed
    // Example: _otherModule = _localModuleManager.getModuleByType<OtherModule>();
  }

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    _log.info('🗑 TemplateModule disposed.');
    super.dispose();
  }

  /// ✅ Example method - add your module-specific methods below
  Future<Map<String, dynamic>> exampleMethod(BuildContext context) async {
    try {
      _log.info('🔧 TemplateModule example method called');
      return {"success": "Example method executed successfully"};
    } catch (e) {
      _log.error('❌ Error in example method: $e');
      return {"error": "Example method failed: $e"};
    }
  }

  /// ✅ Example health check override
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': isInitialized ? 'TemplateModule is functioning normally' : 'TemplateModule not initialized',
      'custom_metric': 'example_value'
    };
  }
}