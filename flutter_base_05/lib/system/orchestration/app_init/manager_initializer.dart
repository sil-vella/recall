import 'package:flutter/material.dart';
import '../../../tools/logging/logger.dart';
import '../../managers/hooks_manager.dart';
import '../../managers/auth_manager.dart';
import '../../managers/state_manager.dart';
import '../../managers/services_manager.dart';
import '../../managers/navigation_manager.dart';
import '../../managers/event_bus.dart';
import 'app_initializer.dart';

/// Manager Initializer
/// 
/// This class handles the initialization of all application managers.
/// It centralizes the creation and configuration of all managers used throughout the app.
class ManagerInitializer {
  static final Logger _log = Logger();
  
  final AppInitializer appInitializer;
  
  // Manager instances
  late HooksManager _hooksManager;
  late AuthManager _authManager;
  late StateManager _stateManager;
  late ServicesManager _servicesManager;
  late NavigationManager _navigationManager;
  late EventBus _eventBus;
  
  ManagerInitializer(this.appInitializer) {
    _log.info('ManagerInitializer created');
  }
  
  /// Initialize all application managers in the correct order
  Future<void> initializeAllManagers(BuildContext context) async {
    _log.info('🔧 Starting manager initialization...');
    
    try {
      // Initialize managers in dependency order
      await _initializeHooksManager();
      await _initializeAuthManager(context);
      await _initializeStateManager();
      await _initializeServicesManager();
      await _initializeNavigationManager();
      await _initializeEventBus();
      
      // Set managers in app initializer
      _setManagersInAppInitializer();
      
      _log.info('✅ All managers initialized successfully');
      
    } catch (e) {
      _log.error('❌ Error initializing managers: $e');
      rethrow;
    }
  }
  
  /// Initialize HooksManager
  Future<void> _initializeHooksManager() async {
    _log.info('🔗 Initializing HooksManager...');
    _hooksManager = HooksManager();
    _log.info('✅ HooksManager initialized');
  }
  
  /// Initialize AuthManager
  Future<void> _initializeAuthManager(BuildContext context) async {
    _log.info('🔐 Initializing AuthManager...');
    _authManager = AuthManager();
    _authManager.initialize(context);
    _log.info('✅ AuthManager initialized');
  }
  
  /// Initialize StateManager
  Future<void> _initializeStateManager() async {
    _log.info('📊 Initializing StateManager...');
    _stateManager = StateManager();
    _log.info('✅ StateManager initialized');
  }
  
  /// Initialize ServicesManager
  Future<void> _initializeServicesManager() async {
    _log.info('🔧 Initializing ServicesManager...');
    _servicesManager = ServicesManager();
    await _servicesManager.autoRegisterAllServices();
    _log.info('✅ ServicesManager initialized');
  }
  
  /// Initialize NavigationManager
  Future<void> _initializeNavigationManager() async {
    _log.info('🧭 Initializing NavigationManager...');
    _navigationManager = NavigationManager();
    _log.info('✅ NavigationManager initialized');
  }
  
  /// Initialize EventBus
  Future<void> _initializeEventBus() async {
    _log.info('📡 Initializing EventBus...');
    _eventBus = EventBus();
    _log.info('✅ EventBus initialized');
  }
  
  /// Set all managers in the app initializer
  void _setManagersInAppInitializer() {
    appInitializer.hooksManager = _hooksManager;
    appInitializer.authManager = _authManager;
    appInitializer.stateManager = _stateManager;
    appInitializer.servicesManager = _servicesManager;
    appInitializer.navigationManager = _navigationManager;
    appInitializer.eventBus = _eventBus;
    
    _log.info('✅ All managers set in AppInitializer');
  }
  
  /// Get HooksManager
  HooksManager get hooksManager => _hooksManager;
  
  /// Get AuthManager
  AuthManager get authManager => _authManager;
  
  /// Get StateManager
  StateManager get stateManager => _stateManager;
  
  /// Get ServicesManager
  ServicesManager get servicesManager => _servicesManager;
  
  /// Get NavigationManager
  NavigationManager get navigationManager => _navigationManager;
  
  /// Get EventBus
  EventBus get eventBus => _eventBus;
  

} 