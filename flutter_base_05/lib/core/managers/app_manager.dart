import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
import 'hooks_manager.dart';
import 'module_manager.dart';
import 'auth_manager.dart';
import 'adapters_manager.dart';
import '../recall_game/recall_game_main.dart';

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
  final RecallGameCore _recallGameCore = RecallGameCore();

  Future<void> _initializeModules(BuildContext context) async {
    _log.info('🚀 Initializing modules...');

    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    
    // Initialize all registered modules
    await moduleManager.initializeModules(context);

    _isInitialized = true;
    notifyListeners();
    _log.info('✅ All modules initialized successfully.');
  }

  Future<void> initializeApp(BuildContext context) async {
    if (!_isInitialized) {
      // Initialize AuthManager first
      _authManager.initialize(context);
      
      // Initialize AdaptersManager (automatically registers all adapters)
      _adaptersManager.initialize(this);
      
      // Initialize adapters
      await _initializeAdapters();
      
      // Register global hooks
      _registerGlobalHooks();
      
      // Initialize Recall Game Core
      _recallGameCore.initialize(context);
      
      // Initialize modules
      await _initializeModules(context);
      
      // Validate session on startup
      final authStatus = await _authManager.validateSessionOnStartup();
      
      // Handle authentication state
      await _authManager.handleAuthState(context, authStatus);
      
      _isInitialized = true;
      notifyListeners();
      
      // Mark app as initialized in HooksManager to process pending hooks
      _hooksManager.markAppInitialized();
      
      _log.info('✅ App initialization complete with auth status: $authStatus');
    }
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

  /// Get RecallGameCore for external access to Recall game functionality
  RecallGameCore get recallGameCore => _recallGameCore;

  @override
  void dispose() {
    super.dispose();
    _log.info('🛑 AppManager disposed');
  }
}
