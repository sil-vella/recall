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
import '../../utils/web_bootstrap_log.dart';

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

  /// Connect to the Dart WS server without blocking [initializeApp] / first frame (JWT via [WebSocketManager.initialize]).
  Future<void> _initWebSocketInBackground() async {
    try {
      final webSocketManager = WebSocketManager.instance;
      await webSocketManager.ensureInitializedAndConnected();
    } catch (_) {
      // Non-fatal; connection retries elsewhere as needed.
    }
  }

  Future<void> initializeApp(BuildContext context) async {
    if (!_isInitialized) {
      try {
        webBootstrapLog('AppManager: registerCoreProviders');
        _registerCoreProviders();

        final servicesManager = Provider.of<ServicesManager>(context, listen: false);
        webBootstrapLog('AppManager: autoRegisterAllServices');
        await servicesManager.autoRegisterAllServices();

        webBootstrapLog('AppManager: auth/adapters init');
        _authManager.initialize(context);
        _adaptersManager.initialize(this);

        webBootstrapLog('AppManager: initializeAdapters');
        await _initializeAdapters();

        webBootstrapLog('AppManager: initializeModules');
        await _initializeModules(context);

        _registerGlobalHooks();

        webBootstrapLog('AppManager: validateSessionOnStartup');
        final authStatus = await _authManager.validateSessionOnStartup();
        webBootstrapLog('AppManager: authStatus=$authStatus');

        if (authStatus == AuthStatus.loggedIn) {
          unawaited(_initWebSocketInBackground());
        }

        webBootstrapLog('AppManager: handleAuthState');
        await _authManager.handleAuthState(context, authStatus);

        _isInitialized = true;
        notifyListeners();
        _hooksManager.markAppInitialized();
        webBootstrapLog('AppManager: initialized');
      } catch (e) {
        webBootstrapLog('AppManager: initializeApp error $e');
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

  void _registerGlobalHooks() {
    // Subscription / billing hooks (reserved for future use)
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
