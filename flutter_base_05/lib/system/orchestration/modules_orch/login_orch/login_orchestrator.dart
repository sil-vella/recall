import 'package:flutter/material.dart';
import '../../../../tools/logging/logger.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/auth_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../managers/navigation_manager.dart';
import '../../../managers/event_bus.dart';
import '../../../services/shared_preferences.dart';
import '../base_files/module_orch_base.dart';
import '../../../../modules/login_module/login_module.dart';

/// Login Orchestrator
/// 
/// Handles all system integration for login functionality.
/// Delegates business logic to the pure LoginModule.
/// Manages hooks, routes, and system integration.
class LoginOrchestrator extends ModuleOrchestratorBase {
  static final Logger _log = Logger();
  
  // Module instance
  late LoginModule _module;
  bool _isInitialized = false;
  
  // System dependencies
  late SharedPrefManager _sharedPref;
  
  /// Initialize the specific orchestrator implementation
  @override
  void _initializeOrchestrator(BuildContext context) {
    _log.info('🔐 Initializing Login orchestrator...');
    
    try {
      // Create and initialize the pure business logic module
      _module = LoginModule();
      _module.initialize();
      
      // Initialize system dependencies
      _initializeSystemDependencies(context);
      
      // Initialize module-specific components
      _initializeLoginSystem();
      
      _isInitialized = true;
      _log.info('✅ Login orchestrator initialized successfully');
      
    } catch (e) {
      _log.error('❌ Error initializing Login orchestrator: $e');
      rethrow;
    }
  }
  
  /// Initialize system dependencies
  void _initializeSystemDependencies(BuildContext context) {
    _log.info('🔧 Initializing Login system dependencies...');
    
    // Get SharedPrefManager from services manager
    _sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref')!;
    
    _log.info('✅ Login system dependencies initialized');
  }
  
  /// Initialize the login system
  void _initializeLoginSystem() {
    _log.info('🔐 Initializing login system...');
    
    // Register with state manager using module info
    final moduleInfo = _module.getConfigRequirements();
    stateManager.registerModuleState('login', {
      'is_initialized': _isInitialized,
      'module_info': moduleInfo,
      'is_logged_in': _sharedPref.getBool('is_logged_in') ?? false,
      'user_id': _sharedPref.getString('user_id'),
      'username': _sharedPref.getString('username'),
      'email': _sharedPref.getString('email'),
    });
    
    _log.info('✅ Login system initialized');
  }
  
  /// Register hooks for this orchestrator
  @override
  void _registerHooks() {
    _log.info('🔗 Registering Login hooks...');
    
    // Get hooks needed from the module
    final hooksNeeded = _module.getHooksNeeded();
    
    for (final hookInfo in hooksNeeded) {
      final event = hookInfo['hookName'] as String;
      final priority = hookInfo['priority'] as int;
      final context = hookInfo['context'] as String;
      
      hooksManager.registerHookWithData(event, (data) {
        _log.info('🔐 Hook triggered: $event with data: $data');
        _handleHookEvent(event, data);
      }, priority: priority);
    }
    
    _log.info('✅ Login hooks registered');
  }
  
  /// Register routes for this orchestrator
  @override
  void _registerRoutes() {
    _log.info('🛣️ Registering Login routes...');
    
    // Get routes needed from the module
    final routesNeeded = _module.getRoutesNeeded();
    
    for (final routeInfo in routesNeeded) {
      final route = routeInfo['route'] as String;
      final methods = routeInfo['methods'] as List<String>;
      final handler = routeInfo['handler'] as String;
      final authRequired = routeInfo['auth_required'] as bool;
      final description = routeInfo['description'] as String;
      
      // Register route with navigation manager
      navigationManager.registerRoute(
        path: route,
        screen: (context) {
          _handleRouteAction(route);
          return Container(); // Placeholder widget
        },
      );
      
      _log.info('🛣️ Route: ${methods.join(',')} $route - $description');
    }
    
    _log.info('✅ Login routes registered');
  }
  
  /// Handle route actions
  void _handleRouteAction(String route) {
    _log.info('🛣️ Login route action: $route');
    
    switch (route) {
      case '/public/register':
        _handleRegisterRoute();
        break;
      case '/public/login':
        _handleLoginRoute();
        break;
      case '/account':
        _handleAccountRoute();
        break;
      default:
        _log.warning('⚠️ Unknown login route: $route');
    }
  }
  
  /// Handle register route
  void _handleRegisterRoute() {
    _log.info('📝 Handle register route');
    // Navigation would be handled here
  }
  
  /// Handle login route
  void _handleLoginRoute() {
    _log.info('🔑 Handle login route');
    // Navigation would be handled here
  }
  
  /// Handle account route
  void _handleAccountRoute() {
    _log.info('👤 Handle account route');
    // Navigation would be handled here
  }
  
  /// Handle hook events
  void _handleHookEvent(String eventName, Map<String, dynamic> eventData) {
    _log.info('🔐 Login hook event: $eventName');
    
    switch (eventName) {
      case 'auth_required':
        _handleAuthRequired(eventData);
        break;
      case 'refresh_token_expired':
        _handleRefreshTokenExpired();
        break;
      case 'auth_token_refresh_failed':
        _handleTokenRefreshFailed();
        break;
      case 'auth_error':
        _handleAuthError();
        break;
      case 'login_success':
        _handleLoginSuccess(eventData);
        break;
      case 'logout_success':
        _handleLogoutSuccess();
        break;
      default:
        _log.warning('⚠️ Unknown login hook event: $eventName');
    }
  }
  
  /// Handle auth required
  void _handleAuthRequired(Map<String, dynamic> data) {
    _log.info('🔓 Handling auth required');
    final reason = data['reason'] ?? 'unknown';
    final message = data['message'] ?? 'Authentication required';
    
    // Perform logout
    _performLogout();
    
    // Navigate to account screen
    navigationManager.navigateToWithDelay('/account', parameters: {
      'auth_reason': reason,
      'auth_message': message,
    });
  }
  
  /// Handle refresh token expired
  void _handleRefreshTokenExpired() {
    _log.info('🔓 Handling refresh token expired');
    
    // Perform logout
    _performLogout();
    
    // Navigate to account screen
    navigationManager.navigateToWithDelay('/account', parameters: {
      'auth_reason': 'refresh_token_expired',
      'auth_message': 'Refresh token has expired. Please log in again.',
    });
  }
  
  /// Handle token refresh failed
  void _handleTokenRefreshFailed() {
    _log.info('🔓 Handling token refresh failed');
    
    // Perform logout
    _performLogout();
    
    // Navigate to account screen
    navigationManager.navigateToWithDelay('/account', parameters: {
      'auth_reason': 'token_refresh_failed',
      'auth_message': 'Token refresh failed. Please log in again.',
    });
  }
  
  /// Handle auth error
  void _handleAuthError() {
    _log.info('🔓 Handling auth error');
    
    // Perform logout
    _performLogout();
    
    // Navigate to account screen
    navigationManager.navigateToWithDelay('/account', parameters: {
      'auth_reason': 'auth_error',
      'auth_message': 'Authentication error occurred. Please log in again.',
    });
  }
  
  /// Handle login success
  void _handleLoginSuccess(Map<String, dynamic> data) {
    _log.info('✅ Handling login success');
    
    // Update state
    stateManager.updateModuleState('login', {
      'is_logged_in': true,
      'user_id': data['user_id'],
      'username': data['username'],
      'email': data['email'],
    });
    
    // Trigger success hook
    hooksManager.triggerHookWithData('login_success', data);
  }
  
  /// Handle logout success
  void _handleLogoutSuccess() {
    _log.info('🔓 Handling logout success');
    
    // Update state
    stateManager.updateModuleState('login', {
      'is_logged_in': false,
      'user_id': null,
      'username': null,
      'email': null,
    });
    
    // Trigger success hook
    hooksManager.triggerHookWithData('logout_success', {});
  }
  
  /// Perform logout
  void _performLogout() {
    _log.info('🔓 Performing logout');
    
    try {
      // Clear JWT tokens using AuthManager
      authManager.clearTokens();
      
      // Clear stored user data
      _sharedPref.setBool('is_logged_in', false);
      _sharedPref.remove('user_id');
      _sharedPref.remove('username');
      _sharedPref.remove('email');
      
      _log.info('✅ Logout completed');
    } catch (e) {
      _log.error('❌ Logout error: $e');
    }
  }
  
  /// Get screen orchestrator
  // LoginScreenOrchestrator get screenOrchestrator => _screenOrchestrator;
  
  /// Register user (orchestrator method)
  Future<Map<String, dynamic>> registerUser({
    required String username,
    required String email,
    required String password,
  }) async {
    _log.info('📝 Registering user: $username');
    
    try {
      // Delegate to module for business logic
      final result = _module.prepareRegistrationData(
        username: username,
        email: email,
        password: password,
      );
      
      if (!result['success']) {
        return {
          'success': false,
          'error': result['error'],
        };
      }
      
      // For now, return success (API call would be handled by orchestrator)
      return {
        'success': true,
        'message': 'Registration successful. Please log in.',
      };
      
    } catch (e) {
      _log.error('❌ Error registering user: $e');
      return {
        'success': false,
        'error': 'Server error. Check network connection.',
      };
    }
  }
  
  /// Login user (orchestrator method)
  Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    _log.info('🔑 Logging in user: $email');
    
    try {
      // Delegate to module for business logic
      final result = _module.prepareLoginData(
        email: email,
        password: password,
      );
      
      if (!result['success']) {
        return {
          'success': false,
          'error': result['error'],
        };
      }
      
      // For now, return success (API call would be handled by orchestrator)
      return {
        'success': true,
        'message': 'Login successful',
        'user_data': {
          'user_id': '123',
          'username': 'testuser',
          'email': email,
        },
        'tokens': {
          'access_token': 'mock_token',
          'refresh_token': 'mock_refresh_token',
          'access_token_ttl': 3600,
          'refresh_token_ttl': 604800,
        },
      };
      
    } catch (e) {
      _log.error('❌ Error logging in user: $e');
      return {
        'success': false,
        'error': 'Server error. Check network connection.',
      };
    }
  }
  
  /// Logout user (orchestrator method)
  Future<Map<String, dynamic>> logoutUser() async {
    _log.info('🔓 Logging out user');
    
    try {
      // Delegate to module for business logic
      final result = _module.prepareLogoutData();
      
      // Clear tokens using AuthManager
      await authManager.clearTokens();
      
      // Clear stored user data
      await _sharedPref.setBool('is_logged_in', false);
      await _sharedPref.remove('user_id');
      await _sharedPref.remove('username');
      await _sharedPref.remove('email');
      
      // Update state
      stateManager.updateModuleState('login', {
        'is_logged_in': false,
        'user_id': null,
        'username': null,
        'email': null,
      });
      
      // Trigger success hook
      hooksManager.triggerHookWithData('logout_success', {});
      
      return {
        'success': true,
        'message': 'Logout successful',
      };
      
    } catch (e) {
      _log.error('❌ Error logging out user: $e');
      return {
        'success': false,
        'error': 'Logout failed',
      };
    }
  }
  
  /// Get user status (orchestrator method)
  Map<String, dynamic> getUserStatus() {
    _log.info('👤 Getting user status');
    
    final isLoggedIn = _sharedPref.getBool('is_logged_in') ?? false;
    
    if (!isLoggedIn) {
      return {
        'success': true,
        'status': 'logged_out',
      };
    }
    
    return {
      'success': true,
      'status': 'logged_in',
      'user_id': _sharedPref.getString('user_id'),
      'username': _sharedPref.getString('username'),
      'email': _sharedPref.getString('email'),
    };
  }
  
  /// Health check for orchestrator
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'orchestrator': runtimeType.toString(),
      'status': _isInitialized ? 'healthy' : 'not_initialized',
      'module_initialized': _module != null,
      'shared_pref_available': _sharedPref != null,
      'user_status': getUserStatus(),
    };
  }
  
  /// Dispose orchestrator resources
  @override
  void dispose() {
    _log.info('🗑 Disposing Login orchestrator');
    _module.cleanup();
    super.dispose();
  }
} 