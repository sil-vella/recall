import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
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
  static final Logger _log = Logger();
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
    _log.info('🚀 Initializing modules...');

    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    
    // Initialize all registered modules
    await moduleManager.initializeModules(context);

    // Don't set _isInitialized here - app initialization is not complete yet
    _log.info('✅ All modules initialized successfully.');
  }

  Future<void> initializeApp(BuildContext context) async {
    _log.info('🔍 initializeApp called, _isInitialized: $_isInitialized');
    
    if (!_isInitialized) {
      try {
        _log.info('🚀 Starting app initialization...');
        
        // Register core providers
        _log.info('📦 Registering core providers...');
        _registerCoreProviders();
        _log.info('✅ Core providers registered');
        
        // Initialize ServicesManager and register core services
        _log.info('🔧 Initializing ServicesManager...');
        final servicesManager = Provider.of<ServicesManager>(context, listen: false);
        await servicesManager.autoRegisterAllServices();
        _log.info('✅ ServicesManager initialized');
        
        // Initialize AuthManager first
        _log.info('🔐 Initializing AuthManager...');
        _authManager.initialize(context);
        _log.info('✅ AuthManager initialized');
        
        // Initialize AdaptersManager (automatically registers all adapters)
        _log.info('🔌 Initializing AdaptersManager...');
        _adaptersManager.initialize(this);
        _log.info('✅ AdaptersManager initialized');
        
        // Initialize adapters
        _log.info('🔧 Initializing adapters...');
        await _initializeAdapters();
        _log.info('✅ Adapters initialized');
        
        // Initialize modules (StateManager, NavigationManager, etc.)
        _log.info('📦 Initializing modules...');
        await _initializeModules(context);
        _log.info('✅ Modules initialized');
        
        // Register global hooks
        _log.info('🪝 Registering global hooks...');
        _registerGlobalHooks();
        _log.info('✅ Global hooks registered');
        
        // Validate session on startup
        _log.info('🔐 Validating session on startup...');
        final authStatus = await _authManager.validateSessionOnStartup();
        _log.info('✅ Session validation complete: $authStatus');
        
        // Initialize WebSocketManager after authentication (if user is authenticated)
        if (authStatus == 'authenticated') {
          _log.info('🔌 User is authenticated, initializing WebSocketManager...');
          try {
            // Initialize WebSocketManager
            final webSocketManager = WebSocketManager.instance;
            final wsInitialized = await webSocketManager.initialize();
            if (wsInitialized) {
              _log.info('✅ WebSocketManager initialized successfully');
            } else {
              _log.warning('⚠️ WebSocketManager initialization failed');
            }
          } catch (e) {
            _log.error('❌ Error initializing WebSocketManager: $e');
          }
        } else {
          _log.info('🔌 User not authenticated, WebSocketManager will be initialized later');
        }
        
        // Handle authentication state
        _log.info('🔐 Handling authentication state...');
        await _authManager.handleAuthState(context, authStatus);
        _log.info('✅ Authentication state handled');
        
        _isInitialized = true;
        notifyListeners();
        
        // Mark app as initialized in HooksManager to process pending hooks
        _log.info('🪝 Marking app as initialized in HooksManager...');
        _hooksManager.markAppInitialized();
        _log.info('✅ HooksManager notified');
        
        _log.info('🎉 App initialization complete with auth status: $authStatus');
        
      } catch (e) {
        _log.error('❌ App initialization failed: $e');
        _log.error('Stack trace: ${StackTrace.current}');
        rethrow;
      }
    } else {
      _log.info('✅ App already initialized, skipping initialization');
    }
  }

  /// Register core providers with ProviderManager
  void _registerCoreProviders() {
    _log.info('📦 Registering core providers...');
    
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
    
    _log.info('✅ Core providers registered');
  }


  /// Initialize all registered adapters
  Future<void> _initializeAdapters() async {
    _log.info('🚀 Initializing adapters...');
    await _adaptersManager.initializeAdapters();
  }

  /// Register global hooks for RevenueCat integration
  void _registerGlobalHooks() {
    // Register hooks for subscription state changes
    _hooksManager.registerHook('subscription_active', () {
      _log.info('🎣 Subscription active hook triggered');
      // Handle subscription activation
    });
    
    _hooksManager.registerHook('subscription_inactive', () {
      _log.info('🎣 Subscription inactive hook triggered');
      // Handle subscription deactivation
    });
    
    // Banner ad hooks
    _hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      _log.info('📢 Top banner bar hook triggered');
    }, priority: 1);
    
    _hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      _log.info('📢 Bottom banner bar hook triggered');
    }, priority: 1);
    
    // Home screen hooks
    _hooksManager.registerHookWithData('home_screen_main', (data) {
      _log.info('📢 Home screen main hook triggered');
    }, priority: 1);
    
    _log.info('✅ Global hooks registered');
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
    _log.info('🛑 AppManager disposed');
  }
}
