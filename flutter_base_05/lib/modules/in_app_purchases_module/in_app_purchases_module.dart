import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../tools/logging/logger.dart';
import 'services/platform_purchase_service.dart';

class InAppPurchasesModule extends ModuleBase {
  static final Logger _log = Logger();
  late ModuleManager _localModuleManager;
  late ServicesManager _servicesManager;
  BuildContext? _currentContext;

  /// ✅ Constructor with module key and dependencies
  InAppPurchasesModule() : super("in_app_purchases_module", dependencies: ["connections_api_module"]);
  
  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _localModuleManager = moduleManager;
    _initDependencies(context);
    _initializePurchases();
    _log.info('✅ InAppPurchasesModule initialized with context.');
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _currentContext = context;
    // Add other dependencies as needed
    // Example: _otherModule = _localModuleManager.getModuleByType<OtherModule>();
  }
  
  Future<void> _initializePurchases() async {
    // Register module state with existing StateManager after the current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      stateManager.registerModuleState("in_app_purchases", {
        "isLoading": false,
        "products": [],
        "purchases": [],
        "error": null,
        "isAvailable": false
      });
      _log.info('✅ InAppPurchasesModule state registered');
    });
    
    // Initialize platform purchase service
    try {
      final platformService = PlatformPurchaseService();
      await platformService.initialize(_localModuleManager);
      _log.info('✅ PlatformPurchaseService initialized');
    } catch (e) {
      _log.error('❌ Error initializing PlatformPurchaseService: $e');
    }
  }
  
  @override
  void dispose() {
    // Cleanup resources
    _log.info('Cleaning up InAppPurchasesModule resources.');
    super.dispose();
  }
  
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': 'In-App Purchases Module'
    };
  }
} 