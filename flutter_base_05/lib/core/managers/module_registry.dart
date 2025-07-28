import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';
import '../00_base/module_base.dart';
import 'module_manager.dart';
import '../../utils/consts/config.dart';

// Import all modules
import '../../modules/main_helper_module/main_helper_module.dart';
import '../../modules/login_module/login_module.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
// WebSocket module removed - now using WebSocketManager directly
import '../../modules/audio_module/audio_module.dart';
import '../../modules/animations_module/animations_module.dart';
// In-app purchases module removed - switching to RevenueCat
import '../../modules/admobs/banner/banner_ad.dart';
import '../../modules/admobs/interstitial/interstitial_ad.dart';
import '../../modules/admobs/rewarded/rewarded_ad.dart';

class ModuleRegistry {
  static final Logger _log = Logger();
  static final ModuleRegistry _instance = ModuleRegistry._internal();
  factory ModuleRegistry() => _instance;
  ModuleRegistry._internal();

  final Map<String, ModuleBase Function()> _moduleFactories = {};
  final Map<String, List<String>> _moduleDependencies = {};

  /// ✅ Register a module factory with optional dependencies
  void registerModule(String moduleKey, ModuleBase Function() factory, {List<String> dependencies = const []}) {
    if (_moduleFactories.containsKey(moduleKey)) {
      _log.error('❌ Module with key "$moduleKey" is already registered.');
      return;
    }

    _moduleFactories[moduleKey] = factory;
    _moduleDependencies[moduleKey] = dependencies;
    _log.info('✅ Module factory registered: $moduleKey');
  }

  /// ✅ Get all registered module keys
  List<String> get registeredModuleKeys => _moduleFactories.keys.toList();

  /// ✅ Get module dependencies
  List<String> getModuleDependencies(String moduleKey) {
    return _moduleDependencies[moduleKey] ?? [];
  }

  /// ✅ Create and register all modules with ModuleManager
  void registerAllModules(ModuleManager moduleManager) {
    _log.info('🚀 Registering all modules with ModuleManager...');

    // Register modules in dependency order
    final registeredModules = <String>{};
    final modulesToRegister = _moduleFactories.keys.toList();

    while (modulesToRegister.isNotEmpty) {
      bool progress = false;

      for (final moduleKey in modulesToRegister.toList()) {
        final dependencies = _moduleDependencies[moduleKey] ?? [];
        
        // Check if all dependencies are registered
        if (dependencies.every((dep) => registeredModules.contains(dep))) {
          try {
            final moduleFactory = _moduleFactories[moduleKey]!;
            final module = moduleFactory();
            moduleManager.registerModule(moduleKey, module);
            registeredModules.add(moduleKey);
            modulesToRegister.remove(moduleKey);
            progress = true;
            _log.info('✅ Module registered: $moduleKey');
          } catch (e) {
            _log.error('❌ Failed to register module $moduleKey: $e');
            modulesToRegister.remove(moduleKey);
          }
        }
      }

      // If no progress was made, there might be a circular dependency
      if (!progress && modulesToRegister.isNotEmpty) {
        _log.error('❌ Circular dependency detected or missing dependencies for modules: $modulesToRegister');
        // Register remaining modules anyway
        for (final moduleKey in modulesToRegister) {
          try {
            final moduleFactory = _moduleFactories[moduleKey]!;
            final module = moduleFactory();
            moduleManager.registerModule(moduleKey, module);
            _log.info('✅ Module registered (with dependency issues): $moduleKey');
          } catch (e) {
            _log.error('❌ Failed to register module $moduleKey: $e');
          }
        }
        break;
      }
    }

    _log.info('✅ All modules registered successfully');
  }

  /// ✅ Initialize the registry with all available modules
  void initializeRegistry() {
    _log.info('🔧 Initializing module registry...');

    // Register all available modules
    registerModule('main_helper', () => MainHelperModule());
    
    registerModule('login', () => LoginModule());
    
    registerModule('connections_api', () => ConnectionsApiModule(Config.apiUrl));
    
    // WebSocket module removed - now using WebSocketManager directly
    // registerModule('websocket', () => WebSocketModule(), 
    //   dependencies: ['connections_api']);
    
    registerModule('audio', () => AudioModule());
    
    registerModule('animations', () => AnimationsModule());
    
    // In-app purchases module removed - switching to RevenueCat
    // registerModule('in_app_purchases', () => InAppPurchasesModule());
    
    // Ad modules temporarily disabled - will be converted to hooks
    // registerModule('admobs_banner_ad_module', () => BannerAdModule());
    // registerModule('admobs_interstitial_ad_module', () => InterstitialAdModule(Config.admobsInterstitial01));
    // registerModule('admobs_rewarded_ad_module', () => RewardedAdModule(Config.admobsRewarded01));

    _log.info('✅ Module registry initialized with ${_moduleFactories.length} modules');
  }

  /// ✅ Get module status information
  Map<String, dynamic> getRegistryStatus() {
    return {
      'total_modules': _moduleFactories.length,
      'registered_modules': _moduleFactories.keys.toList(),
      'module_dependencies': _moduleDependencies,
    };
  }
} 