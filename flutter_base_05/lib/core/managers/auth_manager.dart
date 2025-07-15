import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../tools/logging/logger.dart';
import '../services/shared_preferences.dart';
import '../managers/services_manager.dart';
import '../managers/state_manager.dart';
import '../managers/module_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import 'dart:async'; // Added for Timer

enum AuthStatus {
  loggedIn,
  loggedOut,
  tokenExpired,
  sessionExpired,
  error
}

/// class AuthManager - Manages application state and operations
///
/// Manages application state and operations
///
/// Example:
/// ```dart
/// final authmanager = AuthManager();
/// ```
///
class AuthManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final AuthManager _instance = AuthManager._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPrefManager? _sharedPref;
  ConnectionsApiModule? _connectionModule;
  
  AuthStatus _currentStatus = AuthStatus.loggedOut;
  AuthStatus get currentStatus => _currentStatus;
  
  bool _isValidating = false;
  bool get isValidating => _isValidating;

  factory AuthManager() => _instance;
  AuthManager._internal();

  /// ✅ Initialize AuthManager with dependencies
  void initialize(BuildContext context) {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    _connectionModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    
    // Setup state listener for queued token refreshes
    _setupStateListener();
    
    // Start state-aware token refresh timer
    startTokenRefreshTimer();
    
    _log.info('✅ AuthManager initialized');
  }

  /// ✅ Store JWT tokens in secure storage
  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      await _secureStorage.write(key: 'access_token', value: accessToken);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
      _log.info('✅ JWT tokens stored successfully in secure storage');
    } catch (e) {
      _log.error('❌ Failed to store JWT tokens: $e');
      rethrow;
    }
  }

  /// ✅ Get access token from secure storage
  Future<String?> getAccessToken() async {
    try {
      final token = await _secureStorage.read(key: 'access_token');
      if (token != null) {
        _log.debug('✅ Retrieved access token from secure storage');
      } else {
        _log.debug('⚠️ No access token found in secure storage');
      }
      return token;
    } catch (e) {
      _log.error('❌ Error retrieving access token: $e');
      return null;
    }
  }

  /// ✅ Get refresh token from secure storage
  Future<String?> getRefreshToken() async {
    try {
      final token = await _secureStorage.read(key: 'refresh_token');
      if (token != null) {
        _log.debug('✅ Retrieved refresh token from secure storage');
      } else {
        _log.debug('⚠️ No refresh token found in secure storage');
      }
      return token;
    } catch (e) {
      _log.error('❌ Error retrieving refresh token: $e');
      return null;
    }
  }

  /// ✅ Clear all JWT tokens from secure storage
  Future<void> clearTokens() async {
    try {
      await _secureStorage.delete(key: 'access_token');
      await _secureStorage.delete(key: 'refresh_token');
      _log.info('✅ JWT tokens cleared from secure storage');
    } catch (e) {
      _log.error('❌ Error clearing JWT tokens: $e');
      rethrow;
    }
  }

  /// ✅ Refresh access token using refresh token
  Future<String?> refreshAccessToken(String refreshToken) async {
    if (_connectionModule == null) {
      _log.error('❌ Connection module not available for token refresh');
      return null;
    }

    try {
      _log.info('🔄 Refreshing access token...');
      
      final response = await _connectionModule!.sendPostRequest('/public/refresh', {
        'refresh_token': refreshToken
      });
      
      // Check if response is an error
      if (response is Map && response.containsKey('error')) {
        _log.error('❌ Token refresh error: ${response['error']}');
        return null;
      }
      
      // Check if response has access token
      if (response is Map && response.containsKey('data') && response['data'] is Map) {
        final data = response['data'] as Map<String, dynamic>;
        final newAccessToken = data['access_token'];
        final newRefreshToken = data['refresh_token'] ?? refreshToken;
        
        // Store the new tokens
        await storeTokens(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
        );
        
        _log.info('✅ Token refreshed successfully');
        return newAccessToken;
      }
      
      _log.error('❌ Failed to refresh token: Invalid response format');
      return null;
    } catch (e) {
      _log.error('❌ Failed to refresh token: $e');
      return null;
    }
  }

  /// ✅ Get current valid JWT token (with refresh if needed)
  Future<String?> getCurrentValidToken() async {
    try {
      // First, try to get the current access token
      final accessToken = await getAccessToken();
      if (accessToken == null) {
        _log.info('⚠️ No access token available');
        return null;
      }
      
      // Try to refresh the token to ensure we have a fresh one
      final refreshToken = await getRefreshToken();
      if (refreshToken != null) {
        _log.info('🔄 Attempting to refresh token to ensure validity...');
        final newToken = await refreshAccessToken(refreshToken);
        if (newToken != null) {
          _log.info('✅ Retrieved fresh JWT token');
          return newToken;
        } else {
          _log.info('⚠️ Token refresh failed, using existing token');
          return accessToken;
        }
      }
      
      // If no refresh token, use the current access token
      _log.info('✅ Retrieved JWT token (no refresh token available)');
      return accessToken;
    } catch (e) {
      _log.error('❌ Error retrieving valid JWT token: $e');
      return null;
    }
  }

  /// ✅ Check if user has valid JWT token
  Future<bool> hasValidToken() async {
    try {
      final token = await getCurrentValidToken();
      return token != null;
    } catch (e) {
      _log.error('❌ Error checking token validity: $e');
      return false;
    }
  }

  /// ✅ Validate session on app startup
  Future<AuthStatus> validateSessionOnStartup() async {
    if (_sharedPref == null) {
      _log.error('❌ SharedPrefManager not available');
      return AuthStatus.error;
    }

    _isValidating = true;
    notifyListeners();

    try {
      _log.info('🔍 Validating session on startup...');

      // Step 1: Check if user thinks they're logged in
      final isLoggedIn = _sharedPref!.getBool('is_logged_in') ?? false;
      if (!isLoggedIn) {
        _log.info('ℹ️ User not logged in');
        _currentStatus = AuthStatus.loggedOut;
        _isValidating = false;
        notifyListeners();
        return AuthStatus.loggedOut;
      }

      // Step 2: Check if JWT token exists and is valid
      final hasValidJWT = await hasValidToken();
      if (!hasValidJWT) {
        _log.info('⚠️ No valid JWT token found, clearing stored data');
        await _clearStoredData();
        _currentStatus = AuthStatus.tokenExpired;
        _isValidating = false;
        notifyListeners();
        return AuthStatus.tokenExpired;
      }

      // Step 3: Check session age (optional)
      final lastLogin = _sharedPref!.getString('last_login_timestamp');
      if (lastLogin != null) {
        final lastLoginTime = DateTime.parse(lastLogin);
        final daysSinceLogin = DateTime.now().difference(lastLoginTime).inDays;
        if (daysSinceLogin > 30) { // Configurable
          _log.info('⚠️ Session expired (${daysSinceLogin} days old)');
          await _clearStoredData();
          _currentStatus = AuthStatus.sessionExpired;
          _isValidating = false;
          notifyListeners();
          return AuthStatus.sessionExpired;
        }
      }

      _log.info('✅ Session validation successful');
      _currentStatus = AuthStatus.loggedIn;
      _isValidating = false;
      notifyListeners();
      return AuthStatus.loggedIn;

    } catch (e) {
      _log.error('❌ Session validation error: $e');
      await _clearStoredData();
      _currentStatus = AuthStatus.error;
      _isValidating = false;
      notifyListeners();
      return AuthStatus.error;
    }
  }

  /// ✅ Handle authentication state changes
  Future<void> handleAuthState(BuildContext context, AuthStatus status) async {
    final stateManager = StateManager();
    
    switch (status) {
      case AuthStatus.loggedIn:
        // User is logged in, load their data
        final userData = {
          "isLoggedIn": true,
          "userId": _sharedPref?.getString('user_id'),
          "username": _sharedPref?.getString('username'),
          "email": _sharedPref?.getString('email'),
        };
        
        stateManager.updateModuleState("login", userData);
        _log.info('✅ User logged in: ${userData['username']}');
        break;
        
      case AuthStatus.loggedOut:
      case AuthStatus.tokenExpired:
      case AuthStatus.sessionExpired:
        // User needs to log in
        stateManager.updateModuleState("login", {
          "isLoggedIn": false,
          "userId": null,
          "username": null,
          "email": null,
        });
        
        String message = "Please log in";
        if (status == AuthStatus.tokenExpired) {
          message = "Session expired. Please log in again.";
        } else if (status == AuthStatus.sessionExpired) {
          message = "Session expired due to inactivity. Please log in again.";
        }
        
        _log.info('ℹ️ User needs to log in: $message');
        break;
        
      case AuthStatus.error:
        // Handle error state
        stateManager.updateModuleState("login", {
          "isLoggedIn": false,
          "userId": null,
          "username": null,
          "email": null,
          "error": "Authentication error occurred"
        });
        _log.error('❌ Authentication error occurred');
        break;
    }
  }

  /// ✅ Clear all stored authentication data
  Future<void> _clearStoredData() async {
    try {
      // Clear JWT tokens from secure storage
      await clearTokens();
      
      // Clear shared preferences
      if (_sharedPref != null) {
        await _sharedPref!.setBool('is_logged_in', false);
        await _sharedPref!.remove('user_id');
        await _sharedPref!.remove('username');
        await _sharedPref!.remove('email');
        await _sharedPref!.remove('last_login_timestamp');
      }
      
      _log.info('🗑️ Cleared all stored authentication data');
    } catch (e) {
      _log.error('❌ Error clearing stored data: $e');
    }
  }

  /// ✅ Get current user data
  Map<String, dynamic> getCurrentUserData() {
    if (_sharedPref == null) return {};
    
    return {
      "isLoggedIn": _sharedPref!.getBool('is_logged_in') ?? false,
      "userId": _sharedPref!.getString('user_id'),
      "username": _sharedPref!.getString('username'),
      "email": _sharedPref!.getString('email'),
    };
  }

  /// ✅ Check if user is currently logged in
  bool get isLoggedIn {
    return _sharedPref?.getBool('is_logged_in') ?? false;
  }

  /// ✅ Start state-aware token refresh timer
  void startTokenRefreshTimer() {
    _stopTokenRefreshTimer();
    // Refresh token every 1 hour for configurable token lifetime
    // Only refresh when NOT in game-related states to avoid interrupting gameplay
    _tokenRefreshTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      _log.info("🔄 Token refresh timer triggered...");
      
      // Check main app state before attempting refresh
      final stateManager = StateManager();
      final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
      
      // Don't refresh during game-related states
      if (mainState == "active_game" || mainState == "pre_game" || mainState == "post_game") {
        _log.info("⏸️ App is in game state (state: $mainState), queuing refresh for later...");
        _queueTokenRefreshForNonGameState();
      } else {
        _log.info("✅ App is not in game state (state: $mainState), proceeding with token refresh...");
        await _performTokenRefresh();
      }
    });
    _log.info("✅ State-aware token refresh timer started");
  }

  /// ✅ Stop token refresh timer
  void _stopTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _log.info("🛑 Token refresh timer stopped");
  }

  /// ✅ Perform actual token refresh
  Future<void> _performTokenRefresh() async {
    try {
      final hasValidJWT = await hasValidToken();
      if (!hasValidJWT) {
        _log.error("❌ Token refresh failed, stopping timer");
        _stopTokenRefreshTimer();
      } else {
        _log.info("✅ Token refresh completed successfully");
      }
    } catch (e) {
      _log.error("❌ Error during token refresh: $e");
    }
  }

  /// ✅ Queue token refresh for when app becomes backgrounded
  void _queueTokenRefreshForBackground() {
    // Set a flag to refresh when state changes to backgrounded
    _pendingTokenRefresh = true;
    _log.info("📋 Token refresh queued for background state");
  }

  /// ✅ Queue token refresh for when app is NOT in game-related states
  void _queueTokenRefreshForNonGameState() {
    _pendingTokenRefresh = true;
    _log.info("📋 Token refresh queued for non-game state");
  }

  /// ✅ Check and perform queued token refresh when state changes
  void checkQueuedTokenRefresh() {
    if (_pendingTokenRefresh) {
      final stateManager = StateManager();
      final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
      
      // Only refresh when NOT in game-related states
      if (mainState != "active_game" && mainState != "pre_game" && mainState != "post_game") {
        _log.info("✅ App is not in game state (state: $mainState), performing queued token refresh...");
        _pendingTokenRefresh = false;
        _performTokenRefresh();
      }
    }
  }

  /// ✅ Update main app state for testing (can be called from UI)
  void updateMainAppState(String state) {
    final stateManager = StateManager();
    stateManager.updateMainAppState("main_state", state);
    _log.info("📱 Updated main app state to: $state");
    
    // Check if we have a queued refresh and app is not in game state
    checkQueuedTokenRefresh();
  }

  /// ✅ Get current main app state for debugging
  String getCurrentMainAppState() {
    final stateManager = StateManager();
    return stateManager.getMainAppState<String>("main_state") ?? "unknown";
  }

  /// ✅ Setup state listener for queued token refreshes
  void _setupStateListener() {
    final stateManager = StateManager();
    stateManager.addListener(() {
      // Check if we have a queued token refresh and app state is now idle
      checkQueuedTokenRefresh();
    });
    _log.info("✅ State listener setup for queued token refreshes");
  }

  // Token refresh timer and state management
  Timer? _tokenRefreshTimer;
  bool _pendingTokenRefresh = false;

  @override
  void dispose() {
    super.dispose();
    _log.info('🛑 AuthManager disposed');
  }
} 