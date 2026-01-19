import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../services/version_check_service.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
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
  static const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues

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
        _logger.info('AppManager: Validating session on startup', isOn: LOGGING_SWITCH);
        final authStatus = await _authManager.validateSessionOnStartup();
        _logger.info('AppManager: Session validation result: $authStatus', isOn: LOGGING_SWITCH);
        
        // Initialize WebSocketManager after authentication (if user is authenticated)
        // Note: authStatus is an AuthStatus enum, not a string
        if (authStatus == AuthStatus.loggedIn) {
          _logger.info('AppManager: User is authenticated, initializing WebSocketManager', isOn: LOGGING_SWITCH);
          try {
            // Initialize WebSocketManager
            final webSocketManager = WebSocketManager.instance;
            final initialized = await webSocketManager.initialize();
            _logger.info('AppManager: WebSocketManager initialization result: $initialized', isOn: LOGGING_SWITCH);
          } catch (e) {
            _logger.error('AppManager: Error initializing WebSocketManager: $e', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.info('AppManager: User is not authenticated (status: $authStatus), skipping WebSocket initialization', isOn: LOGGING_SWITCH);
        }
        
        // Handle authentication state
        _logger.info('AppManager: Handling authentication state', isOn: LOGGING_SWITCH);
        await _authManager.handleAuthState(context, authStatus);
        _logger.info('AppManager: Authentication state handled', isOn: LOGGING_SWITCH);
        
        _isInitialized = true;
        notifyListeners();
        
        // Mark app as initialized in HooksManager to process pending hooks
        _hooksManager.markAppInitialized();
        
      } catch (e) {
        rethrow;
      }
    }
    
    // Always check for app updates on every app start (not just first initialization)
    // This ensures version check runs even if app was previously initialized
    _checkForAppUpdates(context);
  }
  
  /// Check for app updates after initialization (non-blocking)
  void _checkForAppUpdates(BuildContext context) {
    // Skip version check on web - web apps update automatically
    if (kIsWeb) {
      _logger.info('AppManager: Skipping version check on web platform', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Run asynchronously without blocking app startup
    Future.microtask(() async {
      try {
        _logger.info('AppManager: Starting version check', isOn: LOGGING_SWITCH);
        
        // Get ModuleManager to access ConnectionsApiModule
        final moduleManager = Provider.of<ModuleManager>(context, listen: false);
        final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
        
        if (apiModule == null) {
          _logger.warning('AppManager: ConnectionsApiModule not available for version check', isOn: LOGGING_SWITCH);
          return;
        }
        
        // Initialize VersionCheckService if needed
        final versionCheckService = VersionCheckService();
        if (!versionCheckService.isInitialized) {
          await versionCheckService.initialize();
        }
        
        // Check for updates
        final result = await versionCheckService.checkForUpdates(apiModule);
        
        if (result['success'] == true) {
          final updateAvailable = result['update_available'] == true;
          final updateRequired = result['update_required'] == true;
          final currentVersion = result['current_version'];
          final serverVersion = result['server_version'];
          final downloadLink = result['download_link']?.toString() ?? '';
          
          _logger.info('AppManager: Version check completed - Current: $currentVersion, Server: $serverVersion, Update Available: $updateAvailable, Update Required: $updateRequired', isOn: LOGGING_SWITCH);
          
          // If update is required, navigate to blocking update screen
          if (updateRequired && downloadLink.isNotEmpty) {
            _logger.info('AppManager: Update required - navigating to update screen', isOn: LOGGING_SWITCH);
            
            // Wait for router to be initialized before navigating
            final navigationManager = Provider.of<NavigationManager>(context, listen: false);
            
            // Use a small delay to ensure router is ready, then navigate
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Navigate to update screen with download link as parameter
            // Use go() which replaces current route (prevents back navigation)
            final router = navigationManager.router;
            final updateRoute = '/update-required?download_link=${Uri.encodeComponent(downloadLink)}';
            router.go(updateRoute);
            _logger.info('AppManager: Navigated to update screen', isOn: LOGGING_SWITCH);
            return; // Exit early - don't trigger hook since we're blocking
          }
          
          // Trigger hook for modules to listen to version check results (only if update not required)
          _hooksManager.triggerHookWithData('app_version_checked', {
            'update_available': updateAvailable,
            'update_required': updateRequired,
            'current_version': currentVersion,
            'server_version': serverVersion,
            'download_link': downloadLink,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } else {
          _logger.warning('AppManager: Version check failed: ${result['error']}', isOn: LOGGING_SWITCH);
        }
        
      } catch (e) {
        // Don't let version check errors affect app startup
        _logger.error('AppManager: Error during version check: $e', isOn: LOGGING_SWITCH);
      }
    });
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
