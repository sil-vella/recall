import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'hooks_manager.dart';
import 'module_manager.dart';
import 'auth_manager.dart';
import 'adapters_manager.dart';
import 'provider_manager.dart';
import 'services_manager.dart';
import 'state_manager.dart';
import 'navigation_manager.dart';
import 'websockets/websocket_manager.dart';
class AppManager extends ChangeNotifier {
  static final AppManager _instance = AppManager._internal();
  static late BuildContext globalContext;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  factory AppManager() => _instance;
  AppManager._internal();

  final HooksManager _hooksManager = HooksManager();
  final AuthManager _authManager = AuthManager();
  final AdaptersManager _adaptersManager = AdaptersManager();

  Future<void> _initializeModules(BuildContext context) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    
    // Initialize all registered modules
    await moduleManager.initializeModules(context);
  }

  Future<void> initializeApp(BuildContext context) async {
    if (!_isInitialized) {
      try {
        // Register core providers
        _registerCoreProviders();
        
        // Initialize ServicesManager and register core services
        final servicesManager = Provider.of<ServicesManager>(context, listen: false);
        await servicesManager.autoRegisterAllServices();
        
        // Initialize AuthManager first
        _authManager.initialize(context);
        
        // Initialize AdaptersManager (automatically registers all adapters)
        _adaptersManager.initialize(this);
        
        // Initialize adapters
        await _initializeAdapters();
        
        // Initialize modules (StateManager, NavigationManager, etc.)
        await _initializeModules(context);
        
        // Register global hooks
        _registerGlobalHooks();
        
        // Validate session on startup
        final authStatus = await _authManager.validateSessionOnStartup();
        
        // Initialize WebSocketManager after authentication (if user is authenticated)
        if (authStatus == 'authenticated') {
          try {
            // Initialize WebSocketManager
            final webSocketManager = WebSocketManager.instance;
            await webSocketManager.initialize();
          } catch (e) {
            // Error initializing WebSocketManager
          }
        }
        
        // Handle authentication state
        await _authManager.handleAuthState(context, authStatus);
        
        _isInitialized = true;
        notifyListeners();
        
        // Mark app as initialized in HooksManager to process pending hooks
        _hooksManager.markAppInitialized();
        
      } catch (e) {
        rethrow;
      }
    }
  }

  /// Register core providers with ProviderManager
  void _registerCoreProviders() {
    final providerManager = ProviderManager();
    
    // Register core managers as providers (only those that extend ChangeNotifier)
    providerManager.registerProviderCreate(
      () => _authManager,
      name: 'auth_manager',
    );
    
    // Register other core managers that extend ChangeNotifier
    providerManager.registerProviderCreate(
      () => AppManager(),
      name: 'app_manager',
    );
    
    providerManager.registerProviderCreate(
      () => ModuleManager(),
      name: 'module_manager',
    );
    
    providerManager.registerProviderCreate(
      () => ServicesManager(),
      name: 'services_manager',
    );
    
    providerManager.registerProviderCreate(
      () => StateManager(),
      name: 'state_manager',
    );
    
    providerManager.registerProviderCreate(
      () => NavigationManager(),
      name: 'navigation_manager',
    );
  }


  /// Initialize all registered adapters
  Future<void> _initializeAdapters() async {
    await _adaptersManager.initializeAdapters();
  }

  /// Register global hooks for RevenueCat integration
  void _registerGlobalHooks() {
    // Register hooks for subscription state changes
    _hooksManager.registerHook('subscription_active', () {
      // Handle subscription activation
    });
    
    _hooksManager.registerHook('subscription_inactive', () {
      // Handle subscription deactivation
    });
    
    // Banner ad hooks
    _hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      // Top banner bar hook
    }, priority: 1);
    
    _hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      // Bottom banner bar hook
    }, priority: 1);
    
    // Home screen hooks
    _hooksManager.registerHookWithData('home_screen_main', (data) {
      // Home screen main hook
    }, priority: 1);
  }

  /// Trigger top banner bar hook
  void triggerTopBannerBarHook(BuildContext context) {
    _hooksManager.triggerHookWithData('top_banner_bar_loaded', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Trigger bottom banner bar hook
  void triggerBottomBannerBarHook(BuildContext context) {
    _hooksManager.triggerHookWithData('bottom_banner_bar_loaded', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Trigger home screen main hook
  void triggerHomeScreenMainHook(BuildContext context) {
    _hooksManager.triggerHookWithData('home_screen_main', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get HooksManager for modules to register callbacks
  HooksManager get hooksManager => _hooksManager;

  /// Get AdaptersManager for external access to adapters
  AdaptersManager get adaptersManager => _adaptersManager;

  @override
  void dispose() {
    super.dispose();
  }
}
