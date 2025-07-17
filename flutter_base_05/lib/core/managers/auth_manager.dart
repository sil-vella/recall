import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../tools/logging/logger.dart';
import '../services/shared_preferences.dart';
import '../managers/services_manager.dart';
import '../managers/state_manager.dart';
import '../managers/module_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../utils/consts/config.dart';
import 'dart:async'; // Added for Timer

enum AuthStatus {
  loggedIn,
  loggedOut,
  tokenExpired,
  sessionExpired,
  error
}

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

  // Token refresh cooldown and state management
  DateTime? _lastTokenRefresh;
  bool _isRefreshingToken = false;
  static Duration get _tokenRefreshCooldown => Duration(seconds: Config.jwtTokenRefreshCooldown);
  static Duration get _tokenLifetime => Duration(seconds: Config.jwtAccessTokenExpires);

  factory AuthManager() => _instance;
  AuthManager._internal();

  /// ✅ Initialize AuthManager with dependencies
  void initialize(BuildContext context) {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    _connectionModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    
    // Initialize state-aware token refresh system
    initializeStateAwareRefresh();
    
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
      await _secureStorage.write(key: 'token_stored_at', value: DateTime.now().toIso8601String());
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
      await _secureStorage.delete(key: 'token_stored_at');
      _lastTokenRefresh = null;
      _isRefreshingToken = false;
      _log.info('✅ JWT tokens cleared from secure storage');
    } catch (e) {
      _log.error('❌ Error clearing JWT tokens: $e');
      rethrow;
    }
  }

  /// ✅ Check if token needs refresh based on configurable cooldown time
  bool _shouldRefreshToken() {
    if (_lastTokenRefresh == null) return true;
    
    final timeSinceLastRefresh = DateTime.now().difference(_lastTokenRefresh!);
    return timeSinceLastRefresh >= _tokenRefreshCooldown;
  }
  
  /// ✅ Force refresh token (bypasses cooldown)
  Future<String?> forceRefreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      _log.error('❌ No refresh token available for force refresh');
      return null;
    }
    
    _log.info('🔄 Force refreshing token (bypassing cooldown)...');
    _lastTokenRefresh = null; // Reset cooldown
    return await refreshAccessToken(refreshToken);
  }

  /// ✅ Check token consistency (ensures tokens exist if user data exists)
  Future<bool> _checkTokenConsistency() async {
    try {
      // Check if user data exists
      final hasUserData = _sharedPref!.getBool('is_logged_in') == true &&
                          _sharedPref!.getString('user_id') != null &&
                          _sharedPref!.getString('username') != null;
      
      // Check if tokens exist
      final accessToken = await getAccessToken();
      final refreshToken = await getRefreshToken();
      final hasTokens = accessToken != null && refreshToken != null;
      
      // Log consistency check
      _log.info('🔍 Token consistency check:');
      _log.info('  - Has user data: $hasUserData');
      _log.info('  - Has tokens: $hasTokens');
      
      // If user data exists but tokens don't, that's inconsistent
      if (hasUserData && !hasTokens) {
        _log.info('⚠️ Inconsistent state: User data exists but tokens are missing');
        return false;
      }
      
      // If tokens exist but no user data, that's also inconsistent
      if (hasTokens && !hasUserData) {
        _log.info('⚠️ Inconsistent state: Tokens exist but user data is missing');
        return false;
      }
      
      _log.info('✅ Token consistency check passed');
      return true;
    } catch (e) {
      _log.error('❌ Error checking token consistency: $e');
      return false;
    }
  }

  /// ✅ Check if token is likely expired based on configurable lifetime
  Future<bool> _isTokenLikelyExpired() async {
    try {
      final storedAt = await _secureStorage.read(key: 'token_stored_at');
      if (storedAt == null) return true;
      
      final storedTime = DateTime.parse(storedAt);
      final timeSinceStored = DateTime.now().difference(storedTime);
      return timeSinceStored >= _tokenLifetime;
    } catch (e) {
      _log.error('❌ Error checking token expiration: $e');
      return true;
    }
  }

  /// ✅ Refresh access token using refresh token
  Future<String?> refreshAccessToken(String refreshToken) async {
    if (_connectionModule == null) {
      _log.error('❌ Connection module not available for token refresh');
      return null;
    }

    // Prevent concurrent token refreshes
    if (_isRefreshingToken) {
      _log.info('⏸️ Token refresh already in progress, skipping...');
      return await getAccessToken();
    }

    // Check cooldown period
    if (!_shouldRefreshToken()) {
      _log.info('⏸️ Token refresh in cooldown period, using existing token');
      return await getAccessToken();
    }

    _isRefreshingToken = true;
    _lastTokenRefresh = DateTime.now();

    try {
      _log.info('🔄 Refreshing access token...');
      
      final response = await _connectionModule!.sendPostRequest('/public/refresh', {
        'refresh_token': refreshToken
      });
      
      // Check if response is an error
      if (response is Map && response.containsKey('error')) {
        _log.error('❌ Token refresh error: ${response['error']}');
        _isRefreshingToken = false;
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
        _isRefreshingToken = false;
        return newAccessToken;
      }
      
      _log.error('❌ Failed to refresh token: Invalid response format');
      _isRefreshingToken = false;
      return null;
    } catch (e) {
      _log.error('❌ Failed to refresh token: $e');
      _isRefreshingToken = false;
      return null;
    }
  }

  /// ✅ Get current valid JWT token (with state-aware refresh logic)
  Future<String?> getCurrentValidToken() async {
    try {
      // First, try to get the current access token
      final accessToken = await getAccessToken();
      if (accessToken == null) {
        _log.info('⚠️ No access token available');
        return null;
      }
      
      // Check if token is likely expired
      final isExpired = await _isTokenLikelyExpired();
      if (!isExpired) {
        _log.info('✅ Token is still fresh, using existing token');
        return accessToken;
      }
      
      // ✅ SINGLE STATE-AWARE REFRESH LOGIC
      return await _performStateAwareTokenRefresh(accessToken);
    } catch (e) {
      _log.error('❌ Error retrieving valid JWT token: $e');
      return null;
    }
  }

  /// ✅ Single state-aware token refresh method
  Future<String?> _performStateAwareTokenRefresh(String currentToken) async {
    final stateManager = StateManager();
    final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
    
    // Don't refresh during game-related states
    if (mainState == "active_game" || mainState == "pre_game" || mainState == "post_game") {
      _log.info('⏸️ App is in game state (state: $mainState), queuing refresh for later...');
      _queueTokenRefreshForNonGameState();
      // Return existing token to avoid breaking gameplay
      return currentToken;
    }
    
    // ✅ Perform refresh when not in game state
    _log.info('🔄 App is not in game state (state: $mainState), proceeding with token refresh...');
    
    final refreshToken = await getRefreshToken();
    if (refreshToken != null && _shouldRefreshToken()) {
      _log.info('🔄 Token appears expired, attempting refresh...');
      final newToken = await refreshAccessToken(refreshToken);
      if (newToken != null) {
        _log.info('✅ Retrieved fresh JWT token');
        return newToken;
      } else {
        _log.info('❌ Token refresh failed, token is invalid');
        return null;
      }
    } else if (refreshToken == null) {
      _log.info('⚠️ No refresh token available, token is invalid');
      return null;
    } else {
      _log.info('⏸️ Token refresh in cooldown, but token is expired');
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
        _log.info('⚠️ No valid JWT token found, attempting force refresh...');
        
        // Try force refresh on startup if token is invalid
        final forceRefreshedToken = await forceRefreshToken();
        if (forceRefreshedToken != null) {
          _log.info('✅ Force refresh successful on startup');
          _currentStatus = AuthStatus.loggedIn;
          _isValidating = false;
          notifyListeners();
          return AuthStatus.loggedIn;
        } else {
          _log.info('❌ Force refresh failed, clearing stored data');
          await _clearStoredData();
          _currentStatus = AuthStatus.tokenExpired;
          _isValidating = false;
          notifyListeners();
          return AuthStatus.tokenExpired;
        }
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

  /// ✅ Initialize state-aware token refresh system
  void initializeStateAwareRefresh() {
    _log.info("✅ State-aware token refresh system initialized");
  }

  /// ✅ Queue token refresh for when app is NOT in game-related states
  void _queueTokenRefreshForNonGameState() {
    _pendingTokenRefresh = true;
    
    // Set up state listener only when we need to queue a refresh
    _setupStateListener();
    
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
        
        // Perform the actual refresh
        _performQueuedTokenRefresh();
        
        // Clean up state listener since refresh is completed
        _cleanupStateListener();
      }
    }
  }

  /// ✅ Perform the actual queued token refresh
  Future<void> _performQueuedTokenRefresh() async {
    try {
      final currentToken = await getAccessToken();
      if (currentToken != null) {
        final newToken = await _performStateAwareTokenRefresh(currentToken);
        if (newToken != null) {
          _log.info("✅ Queued token refresh completed successfully");
        } else {
          _log.error("❌ Queued token refresh failed");
        }
      }
    } catch (e) {
      _log.error("❌ Error during queued token refresh: $e");
    }
  }

  /// ✅ Clean up state listener when no longer needed
  void _cleanupStateListener() {
    if (_stateListenerSetup) {
      _stateListenerSetup = false;
      _log.info("🛑 State listener cleanup completed");
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
    // Prevent setting up multiple listeners
    if (_stateListenerSetup) {
      _log.info("✅ State listener already setup, skipping...");
      return;
    }
    
    final stateManager = StateManager();
    stateManager.addListener(() {
      // Check if we have a queued token refresh and app state is now idle
      checkQueuedTokenRefresh();
    });
    
    _stateListenerSetup = true;
    _log.info("✅ State listener setup for queued token refreshes");
  }

  // Token refresh timer and state management
  Timer? _tokenRefreshTimer;
  // State management for queued refreshes
  bool _pendingTokenRefresh = false;
  bool _stateListenerSetup = false;

  @override
  void dispose() {
    super.dispose();
    _log.info('🛑 AuthManager disposed');
  }
} 