import 'package:flutter/material.dart';
import '../../../tools/logging/logger.dart';
import '../../managers/hooks_manager.dart';
import '../../managers/auth_manager.dart';
import '../../managers/state_manager.dart';
import '../../managers/services_manager.dart';
import '../../managers/navigation_manager.dart';
import '../../managers/event_bus.dart';
import '../modules_orch/base_files/module_orch_base.dart';
import '../modules_orch/admobs_orch/admobs_orchestrator.dart';
import '../modules_orch/animations_orch/animations_orchestrator.dart';
import '../modules_orch/audio_orch/audio_orchestrator.dart';
import '../modules_orch/login_orch/login_orchestrator.dart';
import 'manager_initializer.dart';
import 'middleware_setup.dart';
import 'health_checker.dart';

/// AppInitializer - Central orchestrator for the Flutter application.
/// Mirrors the Python AppInitializer pattern with manager initialization
/// and module orchestration.
class AppInitializer extends ChangeNotifier {
  static final Logger _log = Logger();
  static final AppInitializer _instance = AppInitializer._internal();
  static late BuildContext globalContext;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  factory AppInitializer() => _instance;
  AppInitializer._internal();

    // Core managers
  late HooksManager _hooksManager;
  late AuthManager _authManager;
  late StateManager _stateManager;
  late ServicesManager _servicesManager;
  late NavigationManager _navigationManager;
  late EventBus _eventBus;
  
  // Expose managers for ManagerInitializer
  set hooksManager(HooksManager manager) => _hooksManager = manager;
  set authManager(AuthManager manager) => _authManager = manager;
  set stateManager(StateManager manager) => _stateManager = manager;
  set servicesManager(ServicesManager manager) => _servicesManager = manager;
  set navigationManager(NavigationManager manager) => _navigationManager = manager;
  set eventBus(EventBus manager) => _eventBus = manager;
  
  // Module orchestrators registry
  final Map<String, ModuleOrchestratorBase> _orchestrators = {};
  
  // Initialize specialized components
  late ManagerInitializer _managerInitializer;
  late MiddlewareSetup _middlewareSetup;
  late HealthChecker _healthChecker;

  /// Initialize the application with all managers and orchestrators
  Future<void> initializeApp(BuildContext context) async {
    if (_isInitialized) {
      _log.info('✅ App already initialized');
      return;
    }

    try {
      globalContext = context;
      _log.info('🚀 Starting app initialization...');

      // Initialize specialized components
      _managerInitializer = ManagerInitializer(this);
      _middlewareSetup = MiddlewareSetup(this);
      _healthChecker = HealthChecker(this);

      // Initialize all managers through the specialized initializer
      await _managerInitializer.initializeAllManagers(context);

      // Set up all middleware through the specialized setup class
      await _middlewareSetup.setupAllMiddleware(context);

      // Register global hooks
      _registerGlobalHooks();

      // Initialize module orchestrators
      await _initializeOrchestrators(context);

      // Validate session on startup
      final authStatus = await _authManager.validateSessionOnStartup();

      // Handle authentication state
      await _authManager.handleAuthState(context, authStatus);

      _isInitialized = true;
      notifyListeners();

      // Mark app as initialized in HooksManager to process pending hooks
      _hooksManager.markAppInitialized();

      _log.info('✅ App initialization complete with auth status: $authStatus');

    } catch (e) {
      _log.error('❌ Error during app initialization: $e');
      rethrow;
    }
  }



  /// Register global hooks that orchestrators can subscribe to
  void _registerGlobalHooks() {
    _log.info('🔗 Registering global hooks...');

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

    // App lifecycle hooks
    _hooksManager.registerHookWithData('app_initialized', (data) {
      _log.info('📢 App initialized hook triggered');
    }, priority: 1);

    _hooksManager.registerHookWithData('app_paused', (data) {
      _log.info('📢 App paused hook triggered');
    }, priority: 1);

    _hooksManager.registerHookWithData('app_resumed', (data) {
      _log.info('📢 App resumed hook triggered');
    }, priority: 1);

    _log.info('✅ Global hooks registered successfully');
  }

  /// Initialize all module orchestrators
  Future<void> _initializeOrchestrators(BuildContext context) async {
    _log.info('🎼 Initializing module orchestrators...');

    try {
      // Register orchestrators here as they are created
      _registerOrchestrator('admobs', AdMobsOrchestrator());
      _registerOrchestrator('animations', AnimationsOrchestrator());
      _registerOrchestrator('audio', AudioOrchestrator());
      _registerOrchestrator('login', LoginOrchestrator());
      // Example:
      // _registerOrchestrator('stripe', StripeOrchestrator());
      // _registerOrchestrator('user_management', UserManagementOrchestrator());

      // Initialize all registered orchestrators
      for (final entry in _orchestrators.entries) {
        final orchestrator = entry.value;
        final key = entry.key;

        try {
          orchestrator.initialize(context);
          _log.info('✅ Orchestrator initialized: $key');
        } catch (e) {
          _log.error('❌ Error initializing orchestrator $key: $e');
        }
      }

      _log.info('✅ Module orchestrators initialized successfully');

    } catch (e) {
      _log.error('❌ Error initializing orchestrators: $e');
      rethrow;
    }
  }

  /// Register a module orchestrator
  void _registerOrchestrator(String key, ModuleOrchestratorBase orchestrator) {
    if (_orchestrators.containsKey(key)) {
      _log.error('❌ Orchestrator with key "$key" is already registered.');
      return;
    }

    _orchestrators[key] = orchestrator;
    _log.info('✅ Orchestrator registered: $key');
  }

  /// Get a specific orchestrator by key
  ModuleOrchestratorBase? getOrchestrator(String key) {
    final orchestrator = _orchestrators[key];
    if (orchestrator == null) {
      _log.error('❌ Orchestrator "$key" is not registered.');
    }
    return orchestrator;
  }

  /// Get orchestrator by type
  T? getOrchestratorByType<T extends ModuleOrchestratorBase>() {
    for (var orchestrator in _orchestrators.values) {
      if (orchestrator is T) {
        return orchestrator;
      }
    }
    _log.error('❌ No orchestrator found of type: ${T.toString()}');
    return null;
  }

  /// Get all registered orchestrators
  Map<String, ModuleOrchestratorBase> get orchestrators => _orchestrators;

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

  /// Trigger app initialized hook
  void triggerAppInitializedHook(BuildContext context) {
    _hooksManager.triggerHookWithData('app_initialized', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Trigger app paused hook
  void triggerAppPausedHook(BuildContext context) {
    _hooksManager.triggerHookWithData('app_paused', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Trigger app resumed hook
  void triggerAppResumedHook(BuildContext context) {
    _hooksManager.triggerHookWithData('app_resumed', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get HooksManager for modules to register callbacks
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


  
  /// Get ManagerInitializer
  ManagerInitializer get managerInitializer => _managerInitializer;
  
  /// Get MiddlewareSetup
  MiddlewareSetup get middlewareSetup => _middlewareSetup;
  
  /// Get HealthChecker
  HealthChecker get healthChecker => _healthChecker;

  /// Get orchestrator status for health checks
  Map<String, dynamic> getOrchestratorStatus() {
    final status = {
      'total_orchestrators': _orchestrators.length,
      'initialized_orchestrators': 0,
      'orchestrator_errors': <String, dynamic>{},
      'orchestrators': <String, dynamic>{}
    };

    for (final entry in _orchestrators.entries) {
      final key = entry.key;
      final orchestrator = entry.value;

      try {
        final healthCheck = orchestrator.healthCheck();
        (status['orchestrators'] as Map<String, dynamic>)[key] = healthCheck;
        
        if (healthCheck['status'] == 'healthy') {
          status['initialized_orchestrators'] = (status['initialized_orchestrators'] as int) + 1;
        } else {
          (status['orchestrator_errors'] as Map<String, dynamic>)[key] = healthCheck['error'] ?? 'Unknown error';
        }
      } catch (e) {
        (status['orchestrator_errors'] as Map<String, dynamic>)[key] = e.toString();
      }
    }

    return status;
  }

  /// Check if all orchestrators are healthy
  bool checkOrchestratorHealth() {
    final status = getOrchestratorStatus();
    final totalOrchestrators = status['total_orchestrators'] as int;
    final initializedOrchestrators = status['initialized_orchestrators'] as int;
    final errors = status['orchestrator_errors'] as Map<String, dynamic>;

    return totalOrchestrators > 0 && 
           initializedOrchestrators == totalOrchestrators && 
           errors.isEmpty;
  }

  /// Get comprehensive app status
  Map<String, dynamic> getAppStatus(BuildContext context) {
    return {
      'app_initialized': _isInitialized,
      'orchestrator_status': getOrchestratorStatus(),
      'orchestrator_health': checkOrchestratorHealth(),
      'managers': {
        'hooks_manager': _hooksManager != null ? 'available' : 'not_available',
        'auth_manager': _authManager != null ? 'available' : 'not_available',
        'state_manager': _stateManager != null ? 'available' : 'not_available',
        'services_manager': _servicesManager != null ? 'available' : 'not_available',
        'navigation_manager': _navigationManager != null ? 'available' : 'not_available',
        'event_bus': _eventBus != null ? 'available' : 'not_available',

      },
      'components': {
        'manager_initializer': _managerInitializer != null ? 'available' : 'not_available',
        'middleware_setup': _middlewareSetup != null ? 'available' : 'not_available',
        'health_checker': _healthChecker != null ? 'available' : 'not_available',
      },
      'middleware_status': _middlewareSetup?.getMiddlewareStatus(),
      'health_status': _healthChecker?.comprehensiveHealthCheck(context),
    };
  }

  /// Cleanup app resources
  void dispose() {
    _log.info('🧹 Disposing AppInitializer...');

    // Dispose all orchestrators
    for (final orchestrator in _orchestrators.values) {
      try {
        orchestrator.dispose();
      } catch (e) {
        _log.error('❌ Error disposing orchestrator: $e');
      }
    }

    // Clear orchestrators
    _orchestrators.clear();

    _isInitialized = false;
    super.dispose();

    _log.info('✅ AppInitializer disposed successfully');
  }
} 