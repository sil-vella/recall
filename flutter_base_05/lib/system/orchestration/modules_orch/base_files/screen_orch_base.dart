import 'package:flutter/material.dart';
import '../../../../tools/logging/logger.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/auth_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../managers/navigation_manager.dart';
import '../../../managers/event_bus.dart';

/// Screen Orchestrator Base
/// 
/// Base class for all screen orchestrators in Flutter.
/// Handles common manager access and screen orchestration.
abstract class ScreenOrchestratorBase {
  static final Logger _log = Logger();
  
  // Common managers accessible to all screen orchestrators
  late HooksManager _hooksManager;
  late StateManager _stateManager;
  late AuthManager _authManager;
  late ServicesManager _servicesManager;
  late NavigationManager _navigationManager;
  late EventBus _eventBus;
  
  // Screen registry
  final Map<String, Widget Function(BuildContext)> _screens = {};
  
  /// Initialize the screen orchestrator with context
  void initialize(BuildContext context) {
    _log.info('🔧 Initializing ${runtimeType.toString()}...');
    
    try {
      // Store common managers
      _storeCommonManagers(context);
      
      // Initialize the specific screen orchestrator
      _initializeScreenOrchestrator(context);
      
      // Register screen hooks and navigation
      _registerScreenHooks();
      _registerScreenNavigation();
      
      _log.info('✅ ${runtimeType.toString()} initialized successfully');
      
    } catch (e) {
      _log.error('❌ Error initializing ${runtimeType.toString()}: $e');
      rethrow;
    }
  }
  
  /// Store common managers for easy access
  void _storeCommonManagers(BuildContext context) {
    _hooksManager = HooksManager();
    _stateManager = StateManager();
    _authManager = AuthManager();
    _servicesManager = ServicesManager();
    _navigationManager = NavigationManager();
    _eventBus = EventBus();
    
    _log.info('✅ Common managers stored for ${runtimeType.toString()}');
  }
  
  /// Initialize the specific screen orchestrator implementation
  void _initializeScreenOrchestrator(BuildContext context);
  
  /// Register screen-specific hooks
  void _registerScreenHooks();
  
  /// Register screen navigation
  void _registerScreenNavigation();
  
  /// Register a screen
  void _registerScreen(String key, Widget Function(BuildContext) screenBuilder) {
    if (_screens.containsKey(key)) {
      _log.error('❌ Screen with key "$key" is already registered.');
      return;
    }
    
    _screens[key] = screenBuilder;
    _log.info('✅ Screen registered: $key');
  }
  
  /// Get a screen by key
  Widget Function(BuildContext)? getScreen(String key) {
    final screen = _screens[key];
    if (screen == null) {
      _log.error('❌ Screen "$key" is not registered.');
    }
    return screen;
  }
  
  /// Get all registered screens
  Map<String, Widget Function(BuildContext)> get screens => _screens;
  
  /// Navigate to a screen
  void navigateToScreen(BuildContext context, String screenKey, {Map<String, dynamic>? arguments}) {
    final screenBuilder = getScreen(screenKey);
    if (screenBuilder != null) {
      // For now, use a simple route-based navigation
      // In a real implementation, this would handle screen builders
      final route = '/screen/$screenKey';
      _navigationManager.navigateTo(route, parameters: arguments);
      _log.info('✅ Navigated to screen: $screenKey');
    } else {
      _log.error('❌ Screen "$screenKey" not found for navigation');
    }
  }
  
  /// Handle screen lifecycle events
  void onScreenAppear(BuildContext context, String screenKey) {
    _log.info('📱 Screen appeared: $screenKey');
    _hooksManager.triggerHookWithData('screen_appeared', {
      'screen_key': screenKey,
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle screen lifecycle events
  void onScreenDisappear(BuildContext context, String screenKey) {
    _log.info('📱 Screen disappeared: $screenKey');
    _hooksManager.triggerHookWithData('screen_disappeared', {
      'screen_key': screenKey,
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle screen state updates
  void updateScreenState(String screenKey, Map<String, dynamic> state) {
    _stateManager.updateModuleState('screen_$screenKey', state);
    _log.info('📱 Updated screen state for: $screenKey');
  }
  
  /// Get screen state
  Map<String, dynamic>? getScreenState(String screenKey) {
    return _stateManager.getModuleState<Map<String, dynamic>>('screen_$screenKey');
  }
  
  /// Handle screen-specific actions
  void handleScreenAction(BuildContext context, String screenKey, String action, Map<String, dynamic>? data) {
    _log.info('📱 Screen action: $action for screen: $screenKey');
    _hooksManager.triggerHookWithData('screen_action', {
      'screen_key': screenKey,
      'action': action,
      'data': data,
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Health check for screen orchestrator
  Map<String, dynamic> healthCheck() {
    return {
      'orchestrator': runtimeType.toString(),
      'status': 'healthy',
      'registered_screens': _screens.length,
      'screens': _screens.keys.toList(),
    };
  }
  
  /// Dispose screen orchestrator resources
  void dispose() {
    _log.info('🗑 Disposing ${runtimeType.toString()}');
    _screens.clear();
  }
} 