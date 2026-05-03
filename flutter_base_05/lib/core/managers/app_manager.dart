import 'dart:async' show unawaited;

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
import '../../tools/logging/logger.dart';
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
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Set true to trace app init + WebSocket ensureInitializedAndConnected (enable-logging-switch.mdc)

  Future<void> _initializeModules(BuildContext context) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    
    // Initialize all registered modules
    await moduleManager.initializeModules(context);
  }

  /// Connect to the Dart WS server without blocking [initializeApp] / first frame (JWT via [WebSocketManager.initialize]).
  Future<void> _initWebSocketInBackground() async {
    try {
      final webSocketManager = WebSocketManager.instance;
      final ok = await webSocketManager.ensureInitializedAndConnected();
      if (LOGGING_SWITCH) {
        _logger.info('AppManager: WebSocket ensureInitializedAndConnected result: $ok');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AppManager: Error initializing WebSocketManager: $e');
      }
    }
  }

  Future<void> initializeApp(BuildContext context) async {
    if (!_isInitialized) {
      try {
        if (LOGGING_SWITCH) _logger.info('AppManager: initializeApp start');
        // Register core providers
        _registerCoreProviders();

        // Initialize ServicesManager and register core services
        final servicesManager = Provider.of<ServicesManager>(context, listen: false);
        await servicesManager.autoRegisterAllServices();
        if (LOGGING_SWITCH) _logger.info('AppManager: autoRegisterAllServices done');

        // Initialize AuthManager first
        _authManager.initialize(context);
        if (LOGGING_SWITCH) _logger.info('AppManager: AuthManager initialized');

        // Initialize AdaptersManager (automatically registers all adapters)
        _adaptersManager.initialize(this);
        if (LOGGING_SWITCH) _logger.info('AppManager: AdaptersManager initialized');

        // Initialize adapters
        await _initializeAdapters();
        if (LOGGING_SWITCH) _logger.info('AppManager: _initializeAdapters done');

        // Initialize modules (StateManager, NavigationManager, etc.)
        await _initializeModules(context);
        if (LOGGING_SWITCH) _logger.info('AppManager: _initializeModules done');
        
        // Register global hooks
        _registerGlobalHooks();
        
        // Validate session on startup
        if (LOGGING_SWITCH) {
          _logger.info('AppManager: Validating session on startup');
        }
        final authStatus = await _authManager.validateSessionOnStartup();
        if (LOGGING_SWITCH) {
          _logger.info('AppManager: Session validation result: $authStatus');
        }
        
        // WebSocket (Dart game server): init in background so cold start is not blocked when WS is down.
        // NativeWebSocketAdapter already uses a short connect timeout, but awaiting here still delayed UI.
        if (authStatus == AuthStatus.loggedIn) {
          if (LOGGING_SWITCH) {
            _logger.info('AppManager: User is authenticated, scheduling WebSocketManager init (non-blocking)');
          }
          unawaited(_initWebSocketInBackground());
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('AppManager: User is not authenticated (status: $authStatus), skipping WebSocket initialization');
          }
        }
        
        // Handle authentication state
        if (LOGGING_SWITCH) {
          _logger.info('AppManager: Handling authentication state');
        }
        await _authManager.handleAuthState(context, authStatus);
        if (LOGGING_SWITCH) {
          _logger.info('AppManager: Authentication state handled');
        }
        
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

    // After login (fresh session), connect WS so inbox/game events work before opening Dutch lobby.
    _hooksManager.registerHookWithData('auth_login_complete', (data) {
      unawaited(_initWebSocketInBackground());
    }, priority: 20);
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
