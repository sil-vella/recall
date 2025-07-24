import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';
import 'dart:convert';
import '../../tools/logging/logger.dart';
import '../services/shared_preferences.dart';
import 'services_manager.dart';
import 'state_manager.dart';
import 'hooks_manager.dart';
import 'navigation_manager.dart';
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
  
  // HTTP client with auth interceptor
  late final InterceptedClient _httpClient;
  
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
    
    // Initialize HTTP client
    _httpClient = InterceptedClient.build(
      interceptors: [],
      requestTimeout: Duration(seconds: Config.httpRequestTimeout),
    );
    
    // Register authentication navigation callbacks
    _registerAuthNavigationCallbacks();
  }

  /// ✅ Register navigation callbacks for authentication events
  void _registerAuthNavigationCallbacks() {
    final hooksManager = HooksManager();
    final navigationManager = NavigationManager();
    
    _log.info('🔧 Registering authentication navigation callbacks');
    
    // Register callback for when authentication is required
    hooksManager.registerHookWithData('auth_required', (data) {
      _log.info('🔔 Auth required navigation callback triggered: $data');
      // Navigation handled by LoginModule
    });
    
    // Register callback for when token refresh fails
    hooksManager.registerHookWithData('auth_token_refresh_failed', (data) {
      _log.info('🔔 Token refresh failed navigation callback triggered: $data');
      // Navigation handled by LoginModule
    });
    
    // Register callback for authentication errors
    hooksManager.registerHookWithData('auth_error', (data) {
      _log.info('🔔 Auth error navigation callback triggered: $data');
      // Navigation handled by LoginModule
    });
    
    // Register callback for refresh token expiration
    hooksManager.registerHookWithData('refresh_token_expired', (data) {
      _log.info('🔔 Refresh token expired navigation callback triggered: $data');
      // Navigation handled by LoginModule
    });
    
    // Register callback for router initialization
    hooksManager.registerHook('router_initialized', () {
      _log.info('🔔 Router initialized hook triggered');
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
        _log.info('✅ Access token TTL stored: ${accessTokenTtl}s');
      }
      
      if (refreshTokenTtl != null) {
        await _secureStorage.write(key: 'refresh_token_ttl', value: refreshTokenTtl.toString());
        _refreshTokenTtl = refreshTokenTtl;
        _log.info('✅ Refresh token TTL stored: ${refreshTokenTtl}s');
      }
      
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

  /// ✅ Get access token TTL (from backend or fallback)
  Future<int> getAccessTokenTtl() async {
    try {
      _log.info('🔍 getAccessTokenTtl: Starting...');
      
      // Try to get TTL from secure storage (from backend)
      final storedTtl = await _secureStorage.read(key: 'access_token_ttl');
      _log.info('🔍 getAccessTokenTtl: Stored TTL: $storedTtl');
      
      if (storedTtl != null) {
        final ttl = int.tryParse(storedTtl);
        if (ttl != null) {
          _accessTokenTtl = ttl;
          _log.info('🔍 getAccessTokenTtl: Using stored TTL: ${ttl}s');
          return ttl;
        }
      }
      
      // Fallback to config value
      _log.info('⚠️ Using fallback access token TTL: ${Config.jwtAccessTokenExpiresFallback}s');
      return Config.jwtAccessTokenExpiresFallback;
    } catch (e) {
      _log.error('❌ Error getting access token TTL: $e');
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
      _log.info('⚠️ Using fallback refresh token TTL: ${Config.jwtRefreshTokenExpiresFallback}s');
      return Config.jwtRefreshTokenExpiresFallback;
    } catch (e) {
      _log.error('❌ Error getting refresh token TTL: $e');
      return Config.jwtRefreshTokenExpiresFallback;
    }
  }

  /// ✅ Get token lifetime duration
  Future<Duration> getTokenLifetime() async {
    _log.info('🔍 getTokenLifetime: Starting...');
    final ttl = await getAccessTokenTtl();
    _log.info('🔍 getTokenLifetime: TTL: ${ttl}s');
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
      _log.info('✅ JWT tokens and TTL values cleared from secure storage');
    } catch (e) {
      _log.error('❌ Error clearing JWT tokens: $e');
      rethrow;
    }
  }

  /// ✅ Refresh token (no cooldown)
  Future<String?> refreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      _log.error('❌ No refresh token available for refresh');
      return null;
    }
    
    _log.info('🔄 Refreshing token...');
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
      _log.info('🔍 _isTokenLikelyExpired: Starting...');
      
      final storedAt = await _secureStorage.read(key: 'token_stored_at');
      _log.info('🔍 _isTokenLikelyExpired: Stored at: $storedAt');
      
      if (storedAt == null) {
        _log.info('🔍 _isTokenLikelyExpired: No stored timestamp, token expired');
        return true;
      }
      
      final storedTime = DateTime.parse(storedAt);
      final timeSinceStored = DateTime.now().difference(storedTime);
      _log.info('🔍 _isTokenLikelyExpired: Time since stored: ${timeSinceStored.inSeconds}s');
      
      final tokenLifetime = await getTokenLifetime();
      _log.info('🔍 _isTokenLikelyExpired: Token lifetime: ${tokenLifetime.inSeconds}s');
      
      final isExpired = timeSinceStored >= tokenLifetime;
      _log.info('🔍 _isTokenLikelyExpired: Is expired: $isExpired');
      
      return isExpired;
    } catch (e) {
      _log.error('❌ Error checking token expiration: $e');
      return true;
    }
  }

  /// ✅ Check if refresh token is likely expired
  Future<bool> _isRefreshTokenLikelyExpired() async {
    try {
      _log.info('🔍 _isRefreshTokenLikelyExpired: Starting...');
      
      final storedAt = await _secureStorage.read(key: 'token_stored_at');
      _log.info('🔍 _isRefreshTokenLikelyExpired: Stored at: $storedAt');
      
      if (storedAt == null) {
        _log.info('🔍 _isRefreshTokenLikelyExpired: No stored timestamp, refresh token expired');
        return true;
      }
      
      final storedTime = DateTime.parse(storedAt);
      final timeSinceStored = DateTime.now().difference(storedTime);
      _log.info('🔍 _isRefreshTokenLikelyExpired: Time since stored: ${timeSinceStored.inSeconds}s');
      
      final refreshTokenLifetime = await getRefreshTokenTtl();
      _log.info('🔍 _isRefreshTokenLikelyExpired: Refresh token lifetime: ${refreshTokenLifetime}s');
      
      final isExpired = timeSinceStored.inSeconds >= refreshTokenLifetime;
      _log.info('🔍 _isRefreshTokenLikelyExpired: Is expired: $isExpired');
      
      return isExpired;
    } catch (e) {
      _log.error('❌ Error checking refresh token expiration: $e');
      return true;
    }
  }



  /// ✅ Refresh access token using refresh token
  Future<String?> refreshAccessToken(String refreshToken) async {
    // Prevent concurrent token refreshes
    if (_isRefreshingToken) {
      _log.info('⏸️ Token refresh already in progress, skipping...');
      return await getAccessToken();
    }

    _isRefreshingToken = true;

    try {
      _log.info('🔄 Refreshing access token...');
      
      final url = Uri.parse('${Config.apiUrl}/public/refresh');
      final response = await _httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      
      final responseData = jsonDecode(response.body);
      
      // Check if response is an error
      if (responseData is Map && responseData.containsKey('error')) {
        _log.error('❌ Token refresh error: ${responseData['error']}');
        _isRefreshingToken = false;
        return null;
      }
      
      // Check if response has access token
      if (responseData is Map && responseData.containsKey('data') && responseData['data'] is Map) {
        final data = responseData['data'] as Map<String, dynamic>;
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
      _log.info('🔍 getCurrentValidToken: Starting...');
      
      // First, try to get the current access token
      _log.info('🔍 getCurrentValidToken: Getting access token...');
      final accessToken = await getAccessToken();
      _log.info('🔍 getCurrentValidToken: Access token result: ${accessToken != null ? "found" : "null"}');
      
      if (accessToken == null) {
        _log.info('⚠️ No access token available, attempting refresh...');
        // Try to refresh even without access token
        return await _performStateAwareTokenRefresh(null);
      }
      
      // Check if token is likely expired
      _log.info('🔍 getCurrentValidToken: Checking if token is expired...');
      final isExpired = await _isTokenLikelyExpired();
      _log.info('🔍 getCurrentValidToken: Token expired: $isExpired');
      
      if (!isExpired) {
        _log.info('✅ Token is still fresh, using existing token');
        return accessToken;
      }
      
      // ✅ STATE-AWARE REFRESH LOGIC
      _log.info('🔍 getCurrentValidToken: Token expired, performing state-aware refresh...');
      return await _performStateAwareTokenRefresh(accessToken);
    } catch (e) {
      _log.error('❌ Error retrieving valid JWT token: $e');
      return null;
    }
  }

  /// ✅ State-aware token refresh method
  Future<String?> _performStateAwareTokenRefresh(String? currentToken) async {
    final stateManager = StateManager();
    final mainState = stateManager.getMainAppState<String>("main_state") ?? "unknown";
    
    // Don't refresh during game-related states
    if (mainState == "active_game" || mainState == "pre_game" || mainState == "post_game") {
      _log.info('⏸️ App is in game state (state: $mainState), queuing refresh for later...');
      _queueTokenRefreshForNonGameState();
      // Return existing token to avoid breaking gameplay (expired tokens accepted in game state)
      _log.info('⚠️ Using expired token in game state - refresh will occur when game ends');
      return currentToken;
    }
    
    // If no current token, we can't use it in game state
    if (currentToken == null) {
      _log.info('⚠️ No current token available, proceeding with refresh...');
    }
    
    // ✅ Perform refresh when not in game state
    _log.info('🔄 App is not in game state (state: $mainState), proceeding with token refresh...');
    
    final refreshToken = await getRefreshToken();
    if (refreshToken != null) {
      // ✅ Check if refresh token is expired before using it
      _log.info('🔍 Checking if refresh token is expired...');
      final isRefreshTokenExpired = await _isRefreshTokenLikelyExpired();
      _log.info('🔍 Refresh token expired: $isRefreshTokenExpired');
      
      if (isRefreshTokenExpired) {
        _log.error('❌ Refresh token is expired, cannot refresh access token');
        
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
          _log.info('⏸️ Skipping duplicate auth hook trigger');
        }
        return null;
      }
      
      _log.info('🔄 Token appears expired, attempting refresh...');
      final newToken = await refreshAccessToken(refreshToken);
      if (newToken != null) {
        _log.info('✅ Retrieved fresh JWT token');
        return newToken;
      } else {
        _log.info('❌ Token refresh failed, token is invalid');
        
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
          _log.info('⏸️ Skipping duplicate auth hook trigger');
        }
        return null;
      }
    } else {
      _log.info('⚠️ No refresh token available, token is invalid');
      
      // Trigger auth required hook when no tokens are available
      if (!_hasTriggeredAuthHook) {
        _hasTriggeredAuthHook = true;
        final hooksManager = HooksManager();
        hooksManager.triggerHookWithData('auth_required', {
          'status': 'auth_required',
          'reason': 'no_tokens_available',
          'message': 'No authentication tokens available. Please log in.',
        });
        _log.info('🔔 Triggered auth_required hook for no tokens available');
      } else {
        _log.info('⏸️ Skipping duplicate auth hook trigger');
      }
      return null;
    }
  }

  /// ✅ Check if user has valid JWT token
  Future<bool> hasValidToken() async {
    try {
      _log.info('🔍 hasValidToken: Starting token validation...');
      final token = await getCurrentValidToken();
      _log.info('🔍 hasValidToken: Token result: ${token != null ? "valid" : "null"}');
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

    _hasTriggeredAuthHook = false;
    _isValidating = true;
    notifyListeners();

    try {
      _log.info('🔍 Validating session on startup...');

      // Step 1: Check if user thinks they're logged in
      _log.info('🔍 Step 1: Checking if user thinks they\'re logged in...');
      final isLoggedIn = _sharedPref!.getBool('is_logged_in') ?? false;
      _log.info('🔍 User logged in status: $isLoggedIn');
      
      if (!isLoggedIn) {
        _log.info('ℹ️ User not logged in');
        _currentStatus = AuthStatus.loggedOut;
        _isValidating = false;
        notifyListeners();
        return AuthStatus.loggedOut;
      }

      // Step 2: Check if JWT token exists and is valid
      _log.info('🔍 Step 2: Checking if JWT token exists and is valid...');
      final hasValidJWT = await hasValidToken();
      _log.info('🔍 Has valid JWT: $hasValidJWT');
      
      if (!hasValidJWT) {
        _log.info('⚠️ No valid JWT token found - token validation already attempted refresh');
        
        // hasValidToken() already attempted token refresh, so we know it failed
        _log.info('❌ Token refresh failed during validation, clearing stored data');
        await _clearStoredData();
        _currentStatus = AuthStatus.tokenExpired;
        _isValidating = false;
        notifyListeners();
        
        // No need to trigger auth_required hook - refresh_token_expired hook already handled it
        _log.info('⏸️ Skipping auth_required hook - refresh_token_expired already handled logout and navigation');
        
        return AuthStatus.tokenExpired;
      }

      // Step 3: Check session age (optional)
      _log.info('🔍 Step 3: Checking session age...');
      final lastLogin = _sharedPref!.getString('last_login_timestamp');
      _log.info('🔍 Last login timestamp: $lastLogin');
      
      if (lastLogin != null) {
        final lastLoginTime = DateTime.parse(lastLogin);
        final daysSinceLogin = DateTime.now().difference(lastLoginTime).inDays;
        _log.info('🔍 Days since login: $daysSinceLogin');
        
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
        _log.info('✅ User logged in: ${userData['username']}');
        
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
        
        _log.info('ℹ️ User needs to log in: $message');
        
        // Navigation handled by LoginModule hooks - no need to navigate here
        _log.info('⏸️ Skipping navigation - LoginModule hooks will handle navigation');
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
      _log.info('⏸️ Token clearing already in progress, skipping...');
      return;
    }
    
    _isClearingTokens = true;
    
    try {
      // Only clear tokens - logout and navigation handled by LoginModule hooks
      await clearTokens();
      _log.info('🗑️ Cleared JWT tokens (logout handled by LoginModule)');
    } catch (e) {
      _log.error('❌ Error clearing tokens: $e');
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

  // Navigation methods removed - handled by LoginModule

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

  // State management for queued refreshes (no cooldown)
  bool _pendingTokenRefresh = false;
  bool _stateListenerSetup = false;
  bool _isClearingTokens = false; // Prevent duplicate token clearing

  @override
  void dispose() {
    super.dispose();
    _log.info('🛑 AuthManager disposed');
  }

  /// ✅ TEST METHOD: Manually set access token TTL for testing
  Future<void> setTestAccessTokenTtl(int ttlSeconds) async {
    try {
      await _secureStorage.write(key: 'access_token_ttl', value: ttlSeconds.toString());
      _accessTokenTtl = ttlSeconds;
      _log.info('🧪 TEST: Set access token TTL to ${ttlSeconds}s for testing');
    } catch (e) {
      _log.error('❌ Error setting test TTL: $e');
    }
  }

  /// ✅ TEST METHOD: Manually set token stored timestamp for testing
  Future<void> setTestTokenStoredAt(DateTime storedTime) async {
    try {
      await _secureStorage.write(key: 'token_stored_at', value: storedTime.toIso8601String());
      _log.info('🧪 TEST: Set token stored at ${storedTime.toIso8601String()} for testing');
    } catch (e) {
      _log.error('❌ Error setting test timestamp: $e');
    }
  }

  /// ✅ TEST METHOD: Set TTL to 10 seconds for testing
  Future<void> setTtlTo10Seconds() async {
    try {
      await setTestAccessTokenTtl(10);
      _log.info('🧪 TEST: Set access token TTL to 10 seconds for testing');
    } catch (e) {
      _log.error('❌ Error setting TTL to 10 seconds: $e');
    }
  }

  /// ✅ TEST METHOD: Set refresh token TTL to 10 seconds for testing
  Future<void> setRefreshTtlTo10Seconds() async {
    try {
      await _secureStorage.write(key: 'refresh_token_ttl', value: '10');
      _refreshTokenTtl = 10;
      _log.info('🧪 TEST: Set refresh token TTL to 10 seconds for testing');
    } catch (e) {
      _log.error('❌ Error setting refresh TTL to 10 seconds: $e');
    }
  }

  /// ✅ Wait for queued token refresh to complete
  Future<void> waitForQueuedRefresh() async {
    if (!_pendingTokenRefresh) {
      _log.info('✅ No queued refresh to wait for');
      return;
    }
    
    _log.info('⏳ Waiting for queued token refresh to complete...');
    
    // Wait for the refresh to complete (max 30 seconds)
    int attempts = 0;
    const maxAttempts = 30; // 30 seconds max wait
    
    while (_pendingTokenRefresh && attempts < maxAttempts) {
      await Future.delayed(Duration(seconds: Config.tokenRefreshWaitTimeout));
      attempts++;
      _log.debug('⏳ Still waiting for refresh... (attempt $attempts/$maxAttempts)');
    }
    
    if (_pendingTokenRefresh) {
      _log.error('❌ Timeout waiting for queued token refresh');
      throw Exception('Token refresh timeout');
    } else {
      _log.info('✅ Queued token refresh completed');
    }
  }
} 