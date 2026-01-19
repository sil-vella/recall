import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/shared_preferences.dart';
import '../managers/services_manager.dart';
import '../managers/state_manager.dart';
import '../managers/module_manager.dart';
import '../managers/hooks_manager.dart';
import '../managers/navigation_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../utils/consts/config.dart';
import '../../tools/logging/logger.dart';
import 'dart:async'; // Added for Timer

enum AuthStatus {
  loggedIn,
  loggedOut,
  tokenExpired,
  sessionExpired,
  error
}

class AuthManager extends ChangeNotifier {
  // Logging switch for guest registration testing
  static const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues
  
  static final AuthManager _instance = AuthManager._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPrefManager? _sharedPref;
  ConnectionsApiModule? _connectionModule;
  
  AuthStatus _currentStatus = AuthStatus.loggedOut;
  AuthStatus get currentStatus => _currentStatus;
  
  bool _isValidating = false;
  bool get isValidating => _isValidating;

  // Token refresh state management (no cooldown)
  bool _isRefreshingToken = false;
  
  // TTL values from backend (stored in secure storage)
  int? _accessTokenTtl;
  int? _refreshTokenTtl;
  
  // Flag to prevent duplicate hook triggers during validation
  bool _hasTriggeredAuthHook = false;
  


  factory AuthManager() => _instance;
  AuthManager._internal();

  /// ✅ Initialize AuthManager with dependencies
  void initialize(BuildContext context) {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    _connectionModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    
    // Register authentication navigation callbacks
    _registerAuthNavigationCallbacks();
  }

  /// ✅ Register navigation callbacks for authentication events
  void _registerAuthNavigationCallbacks() {
    final hooksManager = HooksManager();
    final navigationManager = NavigationManager();
    
    // Register callback for when authentication is required
    hooksManager.registerHookWithData('auth_required', (data) {
      // Navigation handled by LoginModule
    });
    
    // Register callback for when token refresh fails
    hooksManager.registerHookWithData('auth_token_refresh_failed', (data) {
      // Navigation handled by LoginModule
    });
    
    // Register callback for authentication errors
    hooksManager.registerHookWithData('auth_error', (data) {
      // Navigation handled by LoginModule
    });
    
    // Register callback for refresh token expiration
    hooksManager.registerHookWithData('refresh_token_expired', (data) {
      // Navigation handled by LoginModule
    });
    
    // Register callback for router initialization
    hooksManager.registerHook('router_initialized', () {
      // Router is now ready for navigation
    });
  }

  /// ✅ Store JWT tokens in secure storage
  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
    int? accessTokenTtl,
    int? refreshTokenTtl,
  }) async {
    try {
      await _secureStorage.write(key: 'access_token', value: accessToken);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
      await _secureStorage.write(key: 'token_stored_at', value: DateTime.now().toIso8601String());
      
      // Store TTL values from backend if provided
      if (accessTokenTtl != null) {
        await _secureStorage.write(key: 'access_token_ttl', value: accessTokenTtl.toString());
        _accessTokenTtl = accessTokenTtl;
      }
      
      if (refreshTokenTtl != null) {
        await _secureStorage.write(key: 'refresh_token_ttl', value: refreshTokenTtl.toString());
        _refreshTokenTtl = refreshTokenTtl;
      }
      
    } catch (e) {
      rethrow;
    }
  }

  /// ✅ Get access token from secure storage
  Future<String?> getAccessToken() async {
    try {
      final token = await _secureStorage.read(key: 'access_token');
      if (token != null) {
      } else {
      }
      return token;
    } catch (e) {
      return null;
    }
  }

  /// ✅ Get refresh token from secure storage
  Future<String?> getRefreshToken() async {
    try {
      final token = await _secureStorage.read(key: 'refresh_token');
      if (token != null) {
      } else {
      }
      return token;
    } catch (e) {
      return null;
    }
  }

  /// ✅ Get access token TTL (from backend or fallback)
  Future<int> getAccessTokenTtl() async {
    try {
      
      // Try to get TTL from secure storage (from backend)
      final storedTtl = await _secureStorage.read(key: 'access_token_ttl');
      
      if (storedTtl != null) {
        final ttl = int.tryParse(storedTtl);
        if (ttl != null) {
          _accessTokenTtl = ttl;
          return ttl;
        }
      }
      
      // Fallback to config value
      return Config.jwtAccessTokenExpiresFallback;
    } catch (e) {
      return Config.jwtAccessTokenExpiresFallback;
    }
  }

  /// ✅ Get refresh token TTL (from backend or fallback)
  Future<int> getRefreshTokenTtl() async {
    try {
      // Try to get TTL from secure storage (from backend)
      final storedTtl = await _secureStorage.read(key: 'refresh_token_ttl');
      if (storedTtl != null) {
        final ttl = int.tryParse(storedTtl);
        if (ttl != null) {
          _refreshTokenTtl = ttl;
          return ttl;
        }
      }
      
      // Fallback to config value
      return Config.jwtRefreshTokenExpiresFallback;
    } catch (e) {
      return Config.jwtRefreshTokenExpiresFallback;
    }
  }

  /// ✅ Get token lifetime duration
  Future<Duration> getTokenLifetime() async {
    final ttl = await getAccessTokenTtl();
    return Duration(seconds: ttl);
  }

  /// ✅ Clear all JWT tokens from secure storage
  Future<void> clearTokens() async {
    try {
      await _secureStorage.delete(key: 'access_token');
      await _secureStorage.delete(key: 'refresh_token');
      await _secureStorage.delete(key: 'token_stored_at');
      await _secureStorage.delete(key: 'access_token_ttl');
      await _secureStorage.delete(key: 'refresh_token_ttl');
      _isRefreshingToken = false;
      _accessTokenTtl = null;
      _refreshTokenTtl = null;
    } catch (e) {
      rethrow;
    }
  }

  /// ✅ Refresh token (no cooldown)
  Future<String?> refreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      return null;
    }
    
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
      
      // If user data exists but tokens don't, that's inconsistent
      if (hasUserData && !hasTokens) {
        return false;
      }
      
      // If tokens exist but no user data, that's also inconsistent
      if (hasTokens && !hasUserData) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ✅ Check if token is likely expired based on configurable lifetime
  Future<bool> _isTokenLikelyExpired() async {
    try {
      
      final storedAt = await _secureStorage.read(key: 'token_stored_at');
      
      if (storedAt == null) {
        return true;
      }
      
      final storedTime = DateTime.parse(storedAt);
      final timeSinceStored = DateTime.now().difference(storedTime);
      
      final tokenLifetime = await getTokenLifetime();
      
      final isExpired = timeSinceStored >= tokenLifetime;
      
      return isExpired;
    } catch (e) {
      return true;
    }
  }

  /// ✅ Check if refresh token is likely expired
  Future<bool> _isRefreshTokenLikelyExpired() async {
    try {
      
      final storedAt = await _secureStorage.read(key: 'token_stored_at');
      
      if (storedAt == null) {
        return true;
      }
      
      final storedTime = DateTime.parse(storedAt);
      final timeSinceStored = DateTime.now().difference(storedTime);
      
      final refreshTokenLifetime = await getRefreshTokenTtl();
      
      final isExpired = timeSinceStored.inSeconds >= refreshTokenLifetime;
      
      return isExpired;
    } catch (e) {
      return true;
    }
  }

  /// ✅ Refresh access token using refresh token
  Future<String?> refreshAccessToken(String refreshToken) async {
    if (_connectionModule == null) {
      return null;
    }

    // Prevent concurrent token refreshes
    if (_isRefreshingToken) {
      return await getAccessToken();
    }

    _isRefreshingToken = true;

    try {
      
      final response = await _connectionModule!.sendPostRequest('/public/refresh', {
        'refresh_token': refreshToken
      });
      
      // Check if response is an error
      if (response is Map && response.containsKey('error')) {
        _isRefreshingToken = false;
        return null;
      }
      
      // Check if response has access token
      if (response is Map && response.containsKey('data') && response['data'] is Map) {
        final data = response['data'] as Map<String, dynamic>;
        final newAccessToken = data['access_token'];
        final newRefreshToken = data['refresh_token'] ?? refreshToken;
        
        // Extract TTL values from refresh response
        final expiresIn = data['expires_in'];
        final refreshExpiresIn = data['refresh_expires_in'];
        final accessTokenTtl = expiresIn is int ? expiresIn : null;
        final refreshTokenTtl = refreshExpiresIn is int ? refreshExpiresIn : null;
        
        // Store the new tokens with TTL values
        await storeTokens(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
          accessTokenTtl: accessTokenTtl,
          refreshTokenTtl: refreshTokenTtl,
        );
        
        _isRefreshingToken = false;
        return newAccessToken;
      }
      
      _isRefreshingToken = false;
      return null;
    } catch (e) {
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
        // Try to refresh even without access token
        return await _performStateAwareTokenRefresh(null);
      }
      
      // Check if token is likely expired
      final isExpired = await _isTokenLikelyExpired();
      
      if (!isExpired) {
        return accessToken;
      }
      
      // ✅ STATE-AWARE REFRESH LOGIC
      return await _performStateAwareTokenRefresh(accessToken);
    } catch (e) {
      return null;
    }
  }

  /// ✅ State-aware token refresh method
  Future<String?> _performStateAwareTokenRefresh(String? currentToken) async {
    final stateManager = StateManager();
    final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
    
    // Don't refresh during game-related states
    if (mainState == "active_game" || mainState == "pre_game" || mainState == "post_game") {
      _queueTokenRefreshForNonGameState();
      // Return existing token to avoid breaking gameplay (expired tokens accepted in game state)
      return currentToken;
    }
    
    // If no current token, we can't use it in game state
    if (currentToken == null) {
    }
    
    // ✅ Perform refresh when not in game state
    
    final refreshToken = await getRefreshToken();
    if (refreshToken != null) {
      // ✅ Check if refresh token is expired before using it
      final isRefreshTokenExpired = await _isRefreshTokenLikelyExpired();
      
      if (isRefreshTokenExpired) {
        
        // Clear stored data since both tokens are expired
        await _clearStoredData();
        
        // Trigger refresh token expired hook (LoginModule will handle navigation)
        if (!_hasTriggeredAuthHook) {
          _hasTriggeredAuthHook = true;
          final hooksManager = HooksManager();
          hooksManager.triggerHookWithData('refresh_token_expired', {
            'status': 'refresh_token_expired',
            'reason': 'refresh_token_expired',
            'message': 'Refresh token has expired. Please log in again.',
          });
        } else {
        }
        return null;
      }
      
      final newToken = await refreshAccessToken(refreshToken);
      if (newToken != null) {
        return newToken;
      } else {
        
        // Clear stored data since refresh failed
        await _clearStoredData();
        
        // Trigger token refresh failed hook for actual refresh failure
        if (!_hasTriggeredAuthHook) {
          _hasTriggeredAuthHook = true;
          final hooksManager = HooksManager();
          hooksManager.triggerHookWithData('auth_token_refresh_failed', {
            'status': 'token_refresh_failed',
            'reason': 'refresh_attempt_failed',
            'message': 'Token refresh failed. Please log in again.',
          });
        } else {
        }
        return null;
      }
    } else {
      // No tokens available - navigation will be handled by WebSocket connection failure
      // Don't trigger auth_required hook here to avoid premature navigation during app init
      return null;
    }
  }

  /// ✅ Check if user has valid JWT token
  Future<bool> hasValidToken() async {
    try {
      final token = await getCurrentValidToken();
      return token != null;
    } catch (e) {
      return false;
    }
  }

  /// ✅ Validate session on app startup
  Future<AuthStatus> validateSessionOnStartup() async {
    if (_sharedPref == null) {
      return AuthStatus.error;
    }

    _hasTriggeredAuthHook = false;
    _isValidating = true;
    notifyListeners();

    try {
      // Step 1: Check if user thinks they're logged in
      final isLoggedIn = _sharedPref!.getBool('is_logged_in') ?? false;
      
      // Step 2: Check if JWT token exists and is valid
      final hasValidJWT = await hasValidToken();
      
      // Only restore guest credentials if user is NOT logged in and has valid guest credentials
      // Do NOT restore if user was logged in but tokens are invalid (could be converted account)
      if (!isLoggedIn || !hasValidJWT) {
        // Check if guest account credentials exist (only if not logged in or tokens invalid)
        final isGuestAccount = _sharedPref!.getBool('is_guest_account') ?? false;
        final guestUsername = _sharedPref!.getString('guest_username');
        final guestEmail = _sharedPref!.getString('guest_email');
        final guestUserId = _sharedPref!.getString('guest_user_id');
        
        // Only restore guest credentials if:
        // 1. User is not logged in (fresh start), OR
        // 2. User was logged in but tokens are invalid AND we have guest credentials
        // But do NOT restore if tokens are invalid - let user log in fresh
        if (!isLoggedIn && isGuestAccount && guestUsername != null && guestEmail != null) {
          Logger().info("AuthManager: Restoring guest credentials on session validation - Username: $guestUsername", isOn: LOGGING_SWITCH);
          await _sharedPref!.setString('username', guestUsername);
          await _sharedPref!.setString('email', guestEmail);
          if (guestUserId != null) {
            await _sharedPref!.setString('user_id', guestUserId);
          }
        }
      }
      
      if (!isLoggedIn) {
        _currentStatus = AuthStatus.loggedOut;
        _isValidating = false;
        notifyListeners();
        return AuthStatus.loggedOut;
      }
      
      if (!hasValidJWT) {
        // hasValidToken() already attempted token refresh, so we know it failed
        // Clear all stored data including guest credentials if tokens are invalid
        // This prevents auto-login with converted accounts
        await _clearStoredData();
        
        _currentStatus = AuthStatus.tokenExpired;
        _isValidating = false;
        notifyListeners();
        
        // No need to trigger auth_required hook - refresh_token_expired hook already handled it
        
        return AuthStatus.tokenExpired;
      }

      // Step 3: Check session age (optional)
      final lastLogin = _sharedPref!.getString('last_login_timestamp');
      
      if (lastLogin != null) {
        final lastLoginTime = DateTime.parse(lastLogin);
        final daysSinceLogin = DateTime.now().difference(lastLoginTime).inDays;
        
        if (daysSinceLogin > 30) { // Configurable
          // Clear all stored data - do NOT restore guest credentials
          // This prevents auto-login with converted accounts
          await _clearStoredData();
          
          _currentStatus = AuthStatus.sessionExpired;
          _isValidating = false;
          notifyListeners();
          return AuthStatus.sessionExpired;
        }
      }

      _currentStatus = AuthStatus.loggedIn;
      _isValidating = false;
      notifyListeners();
      return AuthStatus.loggedIn;

    } catch (e) {
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
    final hooksManager = HooksManager();
    
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
        
        // Trigger login success hook
        hooksManager.triggerHookWithData('auth_login_success', {
          'status': 'logged_in',
          'userData': userData,
        });
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
        String reason = "logged_out";
        if (status == AuthStatus.tokenExpired) {
          message = "Session expired. Please log in again.";
          reason = "token_expired";
        } else if (status == AuthStatus.sessionExpired) {
          message = "Session expired due to inactivity. Please log in again.";
          reason = "session_expired";
        }
        
        
        // Navigation handled by LoginModule hooks - no need to navigate here
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
        
        // Trigger authentication error hook
        hooksManager.triggerHookWithData('auth_error', {
          'status': 'error',
          'message': 'Authentication error occurred',
        });
        break;
    }
  }

  /// ✅ Clear all stored authentication data (minimal version - logout handled by LoginModule)
  Future<void> _clearStoredData() async {
    // Prevent duplicate token clearing
    if (_isClearingTokens) {
      return;
    }
    
    _isClearingTokens = true;
    
    try {
      // Clear tokens
      await clearTokens();
      
      // Clear session data to prevent auto-login with invalid tokens
      // This is especially important for converted guest accounts
      if (_sharedPref != null) {
        await _sharedPref!.setBool('is_logged_in', false);
        await _sharedPref!.remove('user_id');
        await _sharedPref!.remove('username');
        await _sharedPref!.remove('email');
        await _sharedPref!.remove('last_login_timestamp');
      }
    } catch (e) {
    } finally {
      _isClearingTokens = false;
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

  /// ✅ Queue token refresh for when app is NOT in game-related states
  void _queueTokenRefreshForNonGameState() {
    _pendingTokenRefresh = true;
    
    // Set up state listener only when we need to queue a refresh
    _setupStateListener();
    
  }

  /// ✅ Check and perform queued token refresh when state changes
  void checkQueuedTokenRefresh() {
    if (_pendingTokenRefresh) {
      final stateManager = StateManager();
      final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
      
      // Only refresh when NOT in game-related states
      if (mainState != "active_game" && mainState != "pre_game" && mainState != "post_game") {
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
        } else {
        }
      }
    } catch (e) {
    }
  }

  /// ✅ Clean up state listener when no longer needed
  void _cleanupStateListener() {
    if (_stateListenerSetup) {
      _stateListenerSetup = false;
    }
  }

  /// ✅ Update main app state for testing (can be called from UI)
  void updateMainAppState(String state) {
    final stateManager = StateManager();
    stateManager.updateMainAppState("main_state", state);
    
    // Check if we have a queued refresh and app is not in game state
    checkQueuedTokenRefresh();
  }

  /// ✅ Get current main app state for debugging
  String getCurrentMainAppState() {
    final stateManager = StateManager();
    return stateManager.getMainAppState<String>("main_state") ?? "unknown";
  }

  // Navigation methods removed - handled by LoginModule

  /// ✅ Setup state listener for queued token refreshes
  void _setupStateListener() {
    // Prevent setting up multiple listeners
    if (_stateListenerSetup) {
      return;
    }
    
    final stateManager = StateManager();
    stateManager.addListener(() {
      // Check if we have a queued token refresh and app state is now idle
      checkQueuedTokenRefresh();
    });
    
    _stateListenerSetup = true;
  }

  // State management for queued refreshes (no cooldown)
  bool _pendingTokenRefresh = false;
  bool _stateListenerSetup = false;
  bool _isClearingTokens = false; // Prevent duplicate token clearing

  @override
  void dispose() {
    super.dispose();
  }

  /// ✅ TEST METHOD: Manually set access token TTL for testing
  Future<void> setTestAccessTokenTtl(int ttlSeconds) async {
    try {
      await _secureStorage.write(key: 'access_token_ttl', value: ttlSeconds.toString());
      _accessTokenTtl = ttlSeconds;
    } catch (e) {
    }
  }

  /// ✅ TEST METHOD: Manually set token stored timestamp for testing
  Future<void> setTestTokenStoredAt(DateTime storedTime) async {
    try {
      await _secureStorage.write(key: 'token_stored_at', value: storedTime.toIso8601String());
    } catch (e) {
    }
  }

  /// ✅ TEST METHOD: Set TTL to 10 seconds for testing
  Future<void> setTtlTo10Seconds() async {
    try {
      await setTestAccessTokenTtl(10);
    } catch (e) {
    }
  }

  /// ✅ TEST METHOD: Set refresh token TTL to 10 seconds for testing
  Future<void> setRefreshTtlTo10Seconds() async {
    try {
      await _secureStorage.write(key: 'refresh_token_ttl', value: '10');
      _refreshTokenTtl = 10;
    } catch (e) {
    }
  }

  /// ✅ Wait for queued token refresh to complete
  Future<void> waitForQueuedRefresh() async {
    if (!_pendingTokenRefresh) {
      return;
    }
    
    
    // Wait for the refresh to complete (max 30 seconds)
    int attempts = 0;
    const maxAttempts = 30; // 30 seconds max wait
    
    while (_pendingTokenRefresh && attempts < maxAttempts) {
      await Future.delayed(Duration(seconds: Config.tokenRefreshWaitTimeout));
      attempts++;
    }
    
    if (_pendingTokenRefresh) {
      throw Exception('Token refresh timeout');
    } else {
    }
  }
} 