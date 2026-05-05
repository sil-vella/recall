import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../connections_api_module/connections_api_module.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/websockets/websocket_manager.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';
import '../../utils/analytics_service.dart';
import 'utils/ws_jwt_access_expiry.dart';

class LoginModule extends ModuleBase {
  // Logging switch for guest registration, login, and backend connectivity
  static const bool LOGGING_SWITCH = true; // Profile avatar upload + auth trace (enable-logging-switch.mdc) — set false after debugging

  late ServicesManager _servicesManager;
  late ModuleManager _localModuleManager;
  SharedPrefManager? _sharedPref;
  ConnectionsApiModule? _connectionModule;
  AuthManager? _authManager;
  BuildContext? _currentContext;

  /// ✅ Constructor with module key and dependencies
  LoginModule() : super("login_module", dependencies: ["connections_api_module"]);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _localModuleManager = moduleManager;
    _initDependencies(context);
    _registerAuthHooks();
  }

  /// ✅ Fetch dependencies once per context
  void _initDependencies(BuildContext context) {
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    _connectionModule = _localModuleManager.getModuleByType<ConnectionsApiModule>();
    _authManager = AuthManager();
    _currentContext = context;

    // Initialize login state in StateManager after the current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      stateManager.registerModuleState("login", {
        "isLoggedIn": _sharedPref?.getBool('is_logged_in') ?? false,
        "userId": _sharedPref?.getString('user_id'),
        "username": _sharedPref?.getString('username'),
        "email": _sharedPref?.getString('email'),
        // Hydrate avatar URL immediately for already-authenticated sessions.
        // This avoids initials fallback while profile refresh is still in flight.
        "profilePicture": _sharedPref?.getString('profile_picture'),
        "error": null
      });
    });
  }

  /// ✅ Register authentication hooks for logout handling
  void _registerAuthHooks() {
    final hooksManager = HooksManager();
    
    // Register hook for auth required
    hooksManager.registerHookWithData('auth_required', (data) {
      _handleAuthRequired(data);
    });
    
    // Register hook for refresh token expiration
    hooksManager.registerHookWithData('refresh_token_expired', (data) {
      _handleRefreshTokenExpired();
    });
    
    // Register hook for token refresh failure
    hooksManager.registerHookWithData('auth_token_refresh_failed', (data) {
      _handleTokenRefreshFailed();
    });
    
    // Register hook for general auth errors
    hooksManager.registerHookWithData('auth_error', (data) {
      _handleAuthError();
    });
  }

  /// ✅ Handle refresh token expiration
  void _handleRefreshTokenExpired() {
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _handleRefreshTokenExpired called');
    }
    if (_currentContext != null) {
      // Only logout and navigate if not already logged out
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>("login");
      final isLoggedIn = loginState?["isLoggedIn"] ?? false;
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: _handleRefreshTokenExpired - isLoggedIn: $isLoggedIn');
      }
      
      if (isLoggedIn) {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is logged in, performing logout and navigating');
        }
        _performSynchronousLogout();
        _navigateToAccountScreen('refresh_token_expired', 'Refresh token has expired. Please log in again.');
      } else {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is already logged out, navigating to account screen');
        }
        // Still navigate to account screen even if already logged out
        _navigateToAccountScreen('refresh_token_expired', 'Refresh token has expired. Please log in again.');
      }
    } else {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: _handleRefreshTokenExpired called but _currentContext is null, skipping navigation');
      }
    }
  }

  /// ✅ Perform synchronous logout (for hook callbacks)
  void _performSynchronousLogout() {
    if (LOGGING_SWITCH) {
      final isGuestAccount = _sharedPref?.getBool('is_guest_account') ?? false;
      if (isGuestAccount) {
        Logger().info("LoginModule: Synchronous guest account logout - preserving permanent guest + form keys");
      }
    }
    final ctx = _currentContext;
    unawaited(_runFullAuthTeardown(triggerContext: ctx));
  }

  /// Notify backend (revoke JWTs, bump auth gen), then wipe local auth artifacts.
  /// [keepLoginFormFields]: keeps SharedPreferences email/username/password for pre-fill when true.
  Future<void> _runFullAuthTeardown({
    BuildContext? triggerContext,
    bool keepLoginFormFields = true,
  }) async {
    if (LOGGING_SWITCH) {
      Logger().info(
        'LoginModule: _runFullAuthTeardown start keepLoginFormFields=$keepLoginFormFields context=${triggerContext != null}',
      );
    }
    try {
      if (triggerContext != null) {
        _initDependencies(triggerContext);
      }
      await _notifyBackendLogoutIfPossible();
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: Auth teardown (server phase): $e');
      }
    }
    await _clearAllLocalAuthArtifacts(keepLoginFormFields: keepLoginFormFields);
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _runFullAuthTeardown done (local auth cleared)');
    }
  }

  /// POST /userauth/logout with Bearer access + optional refresh in body (while tokens still exist).
  Future<void> _notifyBackendLogoutIfPossible() async {
    if (_connectionModule == null) {
      return;
    }
    final am = _authManager ?? AuthManager();
    final access = await am.getAccessToken();
    if (access == null || access.isEmpty) {
      return;
    }
    final refresh = await am.getRefreshToken();
    final body = <String, dynamic>{};
    if (refresh != null && refresh.isNotEmpty) {
      body['refresh_token'] = refresh;
    }
    try {
      if (LOGGING_SWITCH) {
        Logger().info(
          'LoginModule: POST /userauth/logout (refresh_in_body=${body.containsKey('refresh_token')})',
        );
      }
      await _connectionModule!.sendPostRequest('/userauth/logout', body);
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: POST /userauth/logout completed');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: Backend logout request failed (local wipe still runs): $e');
      }
    }
  }

  /// Tokens, session prefs, in-memory login/profile/role, WebSocket disconnect.
  Future<void> _clearAllLocalAuthArtifacts({bool keepLoginFormFields = true}) async {
    try {
      final am = _authManager ?? AuthManager();
      await am.clearSessionAuthData(
        keepLoginFormFields: keepLoginFormFields,
        prefs: _sharedPref,
      );
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: clearSessionAuthData failed: $e');
      }
    }

    final stateManager = StateManager();
    stateManager.updateModuleState('login', {
      'isLoggedIn': false,
      'userId': null,
      'username': null,
      'email': null,
      'error': null,
      'profile': null,
      'profilePicture': null,
      'role': null,
    });

    try {
      WebSocketManager.instance.disconnect();
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: WebSocket disconnected after auth clear');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: WebSocket disconnect on auth clear: $e');
      }
    }
  }

  /// Drop JWT + session flags before [/public/register] and [/public/register-guest] so stale
  /// tokens do not trigger refresh or attach Authorization to public signup calls.
  /// Keeps username/email/password prefs for form pre-fill; does not call backend logout.
  Future<void> _clearStaleAuthBeforePublicSignup() async {
    try {
      await _clearAllLocalAuthArtifacts(keepLoginFormFields: true);
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: Cleared stale local auth before public signup');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: Pre-signup auth clear failed (continuing): $e');
      }
    }
  }

  /// ✅ Handle token refresh failure
  void _handleTokenRefreshFailed() {
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _handleTokenRefreshFailed called');
    }
    if (_currentContext != null) {
      // Only logout and navigate if not already logged out
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>("login");
      final isLoggedIn = loginState?["isLoggedIn"] ?? false;
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: _handleTokenRefreshFailed - isLoggedIn: $isLoggedIn');
      }
      
      if (isLoggedIn) {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is logged in, performing logout and navigating');
        }
        _performSynchronousLogout();
        _navigateToAccountScreen('token_refresh_failed', 'Token refresh failed. Please log in again.');
      } else {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is already logged out, navigating to account screen');
        }
        // Still navigate to account screen even if already logged out
        _navigateToAccountScreen('token_refresh_failed', 'Token refresh failed. Please log in again.');
      }
    } else {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: _handleTokenRefreshFailed called but _currentContext is null, skipping navigation');
      }
    }
  }

  /// ✅ Handle auth required (user needs to log in)
  void _handleAuthRequired(Map<String, dynamic> data) {
    final reason = data['reason'] ?? 'unknown';
    final message = data['message'] ?? 'Authentication required';
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _handleAuthRequired called - reason: $reason, message: $message');
    }
    
    if (_currentContext != null) {
      // Only logout and navigate if not already logged out
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>("login");
      final isLoggedIn = loginState?["isLoggedIn"] ?? false;
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: _handleAuthRequired - isLoggedIn: $isLoggedIn');
      }
      
      if (isLoggedIn) {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is logged in, performing logout and navigating');
        }
        _performSynchronousLogout();
        _navigateToAccountScreen(reason, message);
      } else {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is already logged out, navigating to account screen');
        }
        // Still navigate to account screen even if already logged out
        _navigateToAccountScreen(reason, message);
      }
    } else {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: _handleAuthRequired called but _currentContext is null, skipping navigation');
      }
    }
  }

  /// ✅ Handle general auth error
  void _handleAuthError() {
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _handleAuthError called');
    }
    if (_currentContext != null) {
      // Only logout and navigate if not already logged out
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>("login");
      final isLoggedIn = loginState?["isLoggedIn"] ?? false;
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: _handleAuthError - isLoggedIn: $isLoggedIn');
      }
      
      if (isLoggedIn) {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is logged in, performing logout and navigating');
        }
        _performSynchronousLogout();
        _navigateToAccountScreen('auth_error', 'Authentication error occurred. Please log in again.');
      } else {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: User is already logged out, navigating to account screen');
        }
        // Still navigate to account screen even if already logged out
        _navigateToAccountScreen('auth_error', 'Authentication error occurred. Please log in again.');
      }
    } else {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: _handleAuthError called but _currentContext is null, skipping navigation');
      }
    }
  }



  /// ✅ Navigate to account screen with auth parameters
  void _navigateToAccountScreen(String reason, String message) {
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: _navigateToAccountScreen called - reason: $reason, message: $message');
    }
    if (LOGGING_SWITCH) {
      Logger().info('LoginModule: Current context: ${_currentContext != null ? "available" : "null"}');
    }
    try {
    final navigationManager = NavigationManager();
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: NavigationManager obtained, navigating to /account');
      }
    // Use NavigationManager's queuing system to ensure router is ready
    navigationManager.navigateToWithDelay('/account', parameters: {
      'auth_reason': reason,
      'auth_message': message,
    });
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: Navigation to /account initiated');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        Logger().error('LoginModule: Error navigating to account screen: $e', error: e, stackTrace: stackTrace);
      }
    }
  }

  Future<Map<String, dynamic>> getUserStatus(BuildContext context) async {
    _initDependencies(context);

    if (_sharedPref == null) {
      return {"error": "Service not available."};
    }

    bool isLoggedIn = _sharedPref!.getBool('is_logged_in') ?? false;

    if (!isLoggedIn) {
      return {"status": "logged_out"};
    }

    return {
      "status": "logged_in",
      "user_id": _sharedPref!.getString('user_id'),
      "username": _sharedPref!.getString('username'),
      "email": _sharedPref!.getString('email'),
    };
  }

  /// Returns saved credentials (temp keys) for pre-filling the login form.
  /// Call this when showing the account screen login form (e.g. initState and when
  /// transitioning to logged-out view) so saved email/username/password appear immediately.
  /// Keys: username, email, password (all String?); isGuestAccount (bool).
  /// Email may be null if stored value is encrypted (det_...); do not pre-fill encrypted values.
  Future<Map<String, dynamic>> getPreservedCredentialsForForm(BuildContext context) async {
    _initDependencies(context);

    if (_sharedPref == null) {
      return {};
    }

    final isGuestAccount = _sharedPref!.getBool('is_guest_account') ?? false;
    String? username = _sharedPref!.getString('username');
    String? email = _sharedPref!.getString('email');
    if (email != null && email.startsWith('det_')) {
      email = null;
    }
    final password = _sharedPref!.getString('password');

    return {
      'username': username,
      'email': email,
      'password': password,
      'isGuestAccount': isGuestAccount,
    };
  }

  Future<Map<String, dynamic>> registerUser({
    required BuildContext context,
    required String username,
    required String email,
    required String password,
    String? guestEmail,
    String? guestPassword,
  }) async {
    _initDependencies(context);

    if (_connectionModule == null) {
      return {"error": "Service not available."};
    }

    await _clearStaleAuthBeforePublicSignup();

    // Validate username
    if (username.length < 3) {
      return {"error": "Username must be at least 3 characters long"};
    }
    if (username.length > 20) {
      return {"error": "Username cannot be longer than 20 characters"};
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$').hasMatch(username)) {
      return {"error": "Username can only contain letters, numbers, underscores, and hyphens"};
    }
    if (RegExp(r'[-_]{2,}').hasMatch(username)) {
      return {"error": "Username cannot contain consecutive special characters"};
    }
    if (username.startsWith('_') || username.startsWith('-') || 
        username.endsWith('_') || username.endsWith('-')) {
      return {"error": "Username cannot start or end with special characters"};
    }

    // Validate email format
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return {"error": "Invalid email format. Please enter a valid email address."};
    }

    // Validate password requirements (aligned with backend)
    if (password.length < 8) {
      return {"error": "Password must be at least 8 characters long"};
    }

    try {
      // Log registration attempt
      if (guestEmail != null && guestPassword != null) {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Registration request initiated (with guest conversion) - Username: $username, Email: $email, Guest Email: $guestEmail");
        }
      } else {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Regular registration request initiated - Username: $username, Email: $email");
        }
      }
      
      // Prepare request data
      final Map<String, dynamic> requestData = <String, dynamic>{
        "username": username,
        "email": email,
        "password": password,
      };
      
      // Include guest account conversion info if provided
      if (guestEmail != null && guestPassword != null) {
        requestData["convert_from_guest"] = true;
        requestData["guest_email"] = guestEmail;
        requestData["guest_password"] = guestPassword;
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Registering with guest account conversion - Guest Email: $guestEmail");
        }
      }
      
      // Use the correct backend route
      final response = await _connectionModule!.sendPostRequest(
        "/public/register",
        requestData,
      );

      if (response is Map) {
        if (response["success"] == true || response["message"] == "User created successfully") {
          // Log successful registration
          if (guestEmail != null && guestPassword != null) {
            await AnalyticsService.logEvent(name: 'account_guest_converted_email');
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: Guest account conversion successful - Username: $username, Email: $email, clearing guest keys and updating temp keys");
            }
            // Clear all guest keys
            await _sharedPref!.remove('guest_username');
            await _sharedPref!.remove('guest_email');
            await _sharedPref!.remove('guest_user_id');
            await _sharedPref!.setBool('is_guest_account', false);
            // Update temp keys with new regular account data
            await _sharedPref!.setString('username', username);
            await _sharedPref!.setString('email', email);
            await _sharedPref!.setString('password', password);
          } else {
            await AnalyticsService.logEvent(name: 'account_created_regular');
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: Regular registration successful - Username: $username, Email: $email");
            }
            // Update temp keys for new account
            await _sharedPref!.setString('username', username);
            await _sharedPref!.setString('email', email);
            await _sharedPref!.setString('password', password);
          }
          return {"success": "Registration successful. Please log in. Check your inbox and spam folder for a confirmation email."};
        } else if (response["error"] != null) {
          // Log registration failure
          if (LOGGING_SWITCH) {
            Logger().warning("LoginModule: Registration failed - Username: $username, Email: $email, Error: ${response["error"]}");
          }
          // Handle rate limiting errors
          if (response["status"] == 429) {
            return {
              "error": response["error"] ?? "Too many registration attempts. Please try again later.",
              "isRateLimited": true
            };
          }
          
          return {"error": response["error"]};
        }
      }

      return {"error": "Unexpected server response format"};
    } catch (e) {
      return {"error": "Server error. Check network connection."};
    }
  }

  Future<Map<String, dynamic>> registerGuestUser({
    required BuildContext context,
    /// `ui` from Account screen; `auto_websocket` from [DutchGameHelpers.ensureWebSocketReady].
    String guestProvisionSource = 'ui',
  }) async {
    if (LOGGING_SWITCH) {
      Logger().info("LoginModule: Guest registration request initiated");
    }
    _initDependencies(context);

    if (_connectionModule == null) {
      if (LOGGING_SWITCH) {
        Logger().error("LoginModule: Connection module not available for guest registration");
      }
      return {"error": "Service not available."};
    }

    await _clearStaleAuthBeforePublicSignup();

    try {
      if (LOGGING_SWITCH) {
        Logger().debug("LoginModule: Calling /public/register-guest endpoint");
      }
      // Call guest registration endpoint
      final response = await _connectionModule!.sendPostRequest(
        "/public/register-guest",
        {},
      );

      if (response is Map) {
        if (response["success"] == true || response["message"] == "Guest account created successfully") {
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Guest registration successful, processing credentials");
          }
          // Extract credentials from response
          final credentials = response["data"]?["credentials"] as Map<String, dynamic>?;
          final userData = response["data"]?["user"] as Map<String, dynamic>?;
          
          if (credentials != null && userData != null) {
            final username = credentials["username"]?.toString() ?? '';
            final email = credentials["email"]?.toString() ?? '';
            final password = credentials["password"]?.toString() ?? '';
            final userId = userData["_id"]?.toString() ?? userData["id"]?.toString() ?? '';
            
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: Storing guest credentials - Username: $username, User ID: $userId");
            }
            
            // Store credentials in PERMANENT SharedPreferences keys (never cleared on logout)
            await _sharedPref!.setString('guest_username', username);
            await _sharedPref!.setString('guest_email', email);
            await _sharedPref!.setString('guest_user_id', userId);
            await _sharedPref!.setBool('is_guest_account', true);
            
            // Also store in regular keys for current session
            await _sharedPref!.setString('username', username);
            await _sharedPref!.setString('email', email);
            await _sharedPref!.setString('password', password);
            await _sharedPref!.setString('user_id', userId);
            
            if (LOGGING_SWITCH) {
              Logger().debug("LoginModule: Guest credentials stored, attempting auto-login");
            }
            
            // Auto-login the guest user
            final loginResult = await loginUser(
              context: context,
              email: email,
              password: password,
            );
            
            if (loginResult['success'] != null) {
              await AnalyticsService.logEvent(
                name: 'account_created_guest',
                parameters: {
                  'provision_source': guestProvisionSource,
                  'auto_login_ok': 1,
                },
              );
              if (LOGGING_SWITCH) {
                Logger().info("LoginModule: Guest account created and auto-login successful - Username: $username");
              }
              return {
                "success": "Guest account created and logged in successfully",
                "username": username,
                "email": email,
                "credentials": credentials,
              };
            } else {
              await AnalyticsService.logEvent(
                name: 'account_created_guest',
                parameters: {
                  'provision_source': guestProvisionSource,
                  'auto_login_ok': 0,
                },
              );
              if (LOGGING_SWITCH) {
                Logger().warning("LoginModule: Guest registration succeeded but auto-login failed - Username: $username, Error: ${loginResult['error']}");
              }
              // Registration succeeded but login failed
              return {
                "success": "Guest account created. Please log in with username: $username",
                "username": username,
                "email": email,
                "credentials": credentials,
                "loginError": loginResult['error'],
              };
            }
          }
          
          if (LOGGING_SWITCH) {
            Logger().warning("LoginModule: Guest registration response missing credentials or user data");
          }
          await AnalyticsService.logEvent(
            name: 'account_created_guest',
            parameters: {
              'provision_source': guestProvisionSource,
              'auto_login_ok': 0,
            },
          );
          return {"success": "Guest account created successfully"};
        } else if (response["error"] != null) {
          // Handle rate limiting errors
          if (response["status"] == 429) {
            return {
              "error": response["error"] ?? "Too many registration attempts. Please try again later.",
              "isRateLimited": true
            };
          }
          
          return {"error": response["error"]};
        }
      }

      return {"error": "Unexpected server response format"};
    } catch (e) {
      return {"error": "Server error. Check network connection."};
    }
  }

  Future<Map<String, dynamic>> loginUser({
    required BuildContext context,
    required String email,
    required String password,
    bool forceNewSession = false,
  }) async {
    _initDependencies(context);

    if (_connectionModule == null || _sharedPref == null || _authManager == null) {
      return {"error": "Service not available."};
    }

    try {
      // Log login attempt
      if (LOGGING_SWITCH) {
        Logger().info(
          "LoginModule: POST /public/login email=$email forceNewSession=$forceNewSession",
        );
      }
      
      // Use the correct backend route
      final response = await _connectionModule!.sendPostRequest(
        "/public/login",
        {
          "email": email,
          "password": password,
          if (forceNewSession) "force_new_session": true,
        },
      );

      // Another device has an active session (single-session policy)
      if (response?["status"] == 409 &&
          (response?["code"] == "SESSION_ACTIVE_ELSEWHERE" ||
              response?["error"] == "SESSION_ACTIVE_ELSEWHERE")) {
        if (LOGGING_SWITCH) {
          Logger().warning('LoginModule: Login -> sessionConflict (409 SESSION_ACTIVE_ELSEWHERE)');
        }
        return {
          "sessionConflict": true,
          "message": response?["message"]?.toString() ??
              "This account is already signed in on another device.",
        };
      }

      // Handle error responses
      if (response?["status"] == 409 || response?["code"] == "CONFLICT") {
        return {
          "error": response["message"] ?? "A conflict occurred",
          "user": response["user"]
        };
      }

      if (response?["error"] != null || response?["message"]?.contains("error") == true) {
        String errorMessage = response?["message"] ?? response?["error"] ?? "Unknown error occurred";
        
        // Log login failure
        if (LOGGING_SWITCH) {
          Logger().warning("LoginModule: Login failed - Email: $email, Error: $errorMessage");
        }
        
        // Handle rate limiting errors
        if (response?["status"] == 429) {
          return {
            "error": errorMessage,
            "isRateLimited": true
          };
        }
        
        return {"error": errorMessage};
      }

      // Handle successful login (aligned with backend response format)
      if (response?["success"] == true || response?["message"] == "Login successful") {
        // Extract user data from response
        final userData = response?["data"]?["user"] ?? {};
        final accessToken = response?["data"]?["access_token"];
        final refreshToken = response?["data"]?["refresh_token"];
        
        if (accessToken == null) {
          return {"error": "Login successful but no access token received"};
        }
        
        // Check if this is a guest account (from user data or email pattern)
        final accountType = userData['account_type']?.toString();
        final isGuestAccount = accountType == 'guest' || email.endsWith('@guest.local');
        
        if (isGuestAccount) {
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Guest account login detected - Username: ${userData['username']}, Email: $email");
          }
        }
        
        // Extract TTL values from backend response
        final expiresIn = response?["data"]?["expires_in"];
        final refreshExpiresIn = response?["data"]?["refresh_expires_in"];
        final accessTokenTtl = expiresIn is int ? expiresIn : null;
        final refreshTokenTtl = refreshExpiresIn is int ? refreshExpiresIn : null;
        
        // Store JWT tokens using AuthManager with TTL values
        await _authManager!.storeTokens(
          accessToken: accessToken,
          refreshToken: refreshToken ?? '',
          accessTokenTtl: accessTokenTtl,
          refreshTokenTtl: refreshTokenTtl,
        );
        // New JWT must be used on the next WS handshake; drop any half-open/stale transport.
        WebSocketManager.instance.resetTransportState(reason: 'new_credentials_email_login');

        // Store user data in SharedPreferences
        await _sharedPref!.setBool('is_logged_in', true);
        final userId = userData['_id'] ?? userData['id'] ?? '';
        final username = userData['username'] ?? '';
        
        await _sharedPref!.setString('user_id', userId);
        await _sharedPref!.setString('username', username);
        await _sharedPref!.setString('email', email);
        await _sharedPref!.setString('password', password);
        await _sharedPref!.setString('last_login_timestamp', DateTime.now().toIso8601String());
        
        // Set guest account flag based on account_type from backend
        if (isGuestAccount) {
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Storing permanent guest credentials - Username: $username, User ID: $userId");
          }
          await _sharedPref!.setString('guest_username', username);
          await _sharedPref!.setString('guest_email', email);
          await _sharedPref!.setString('guest_user_id', userId);
          await _sharedPref!.setBool('is_guest_account', true);
        } else {
          // Explicitly set to false for regular accounts to clear any previous guest account flag
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Regular account login - clearing guest account flag");
          }
          await _sharedPref!.setBool('is_guest_account', false);
        }
        
        // Log successful login
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Login successful - Username: $username, Email: $email, Account Type: ${isGuestAccount ? 'guest' : 'regular'}");
        }

        await AnalyticsService.setUserId(userId.toString());
        await AnalyticsService.logEvent(
          name: 'account_login',
          parameters: {
            'method': isGuestAccount ? 'guest' : 'email',
          },
        );
        
        // Update state manager
        final stateManager = StateManager();
        stateManager.updateModuleState("login", {
          "isLoggedIn": true,
          "userId": userId,
          "username": username,
          "email": email,
          "error": null
        });
        
        // Fetch and update user profile (including picture) after login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          fetchAndUpdateUserProfile();
        });
        
        // Trigger auth_login_complete hook after tokens are stored and user is fully logged in
        final hooksManager = HooksManager();
        hooksManager.triggerHookWithData('auth_login_complete', {
          'status': 'logged_in',
          'userData': {
            "isLoggedIn": true,
            "userId": userId,
            "username": username,
            "email": email,
          },
        });
        
        return {
          "success": "Login successful",
          "user_id": userId,
          "username": username,
          "email": email,
          "access_token": accessToken,
          "refresh_token": refreshToken
        };
      }

      return {"error": "Unexpected server response"};
    } catch (e) {
      return {"error": "Server error. Check network connection."};
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle({
    required BuildContext context,
    String? guestEmail,
    String? guestPassword,
    bool forceNewSession = false,
  }) async {
    _initDependencies(context);

    if (_connectionModule == null || _sharedPref == null || _authManager == null) {
      return {"error": "Service not available."};
    }

    try {
      if (LOGGING_SWITCH) {
        Logger().info("LoginModule: Google Sign-In request initiated");
      }
      
      // Check if guest account conversion is requested
      final isConvertingGuest = guestEmail != null && guestPassword != null;
      if (isConvertingGuest) {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Guest account conversion requested for Google Sign-In - Guest Email: $guestEmail");
        }
      }

      // Initialize Google Sign-In
      // Web uses clientId (Web OAuth client ID)
      // Android uses serverClientId (Web OAuth client ID - for ID tokens to send to backend)
      // Android OAuth client (with SHA-1) is automatically detected via package name + SHA-1
      // 'openid' scope is required for ID tokens on web
      final String? webClientId = Config.googleClientId; // Web Client ID (same for both web and Android serverClientId)
      
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile', 'openid'],
        clientId: kIsWeb ? webClientId : null, // For web only
        serverClientId: kIsWeb ? null : webClientId, // For Android: use Web Client ID to get ID tokens
      );
      
      final String clientIdDisplay = webClientId != null && webClientId.isNotEmpty
          ? '${webClientId.substring(0, webClientId.length > 20 ? 20 : webClientId.length)}...'
          : 'Not configured';
      if (LOGGING_SWITCH) {
        Logger().info("LoginModule: Google Sign-In initialized - Platform: ${kIsWeb ? 'Web' : 'Android'}, ${kIsWeb ? 'Client ID' : 'Server Client ID (Web)'}: $clientIdDisplay");
      }
      if (!kIsWeb) {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Android OAuth client is auto-detected via package name + SHA-1 fingerprint");
        }
      }

      // Trigger the authentication flow
      // On web, try signInSilently first, then fall back to signIn
      GoogleSignInAccount? googleUser;
      if (kIsWeb) {
        try {
          // Try silent sign-in first (for returning users)
          googleUser = await googleSignIn.signInSilently();
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Silent sign-in attempted on web");
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Silent sign-in failed, will prompt user: $e");
          }
        }
      }
      
      // If silent sign-in didn't work or not on web, prompt user
      if (googleUser == null) {
        try {
          googleUser = await googleSignIn.signIn();
        } catch (e) {
          if (LOGGING_SWITCH) {
            Logger().error("LoginModule: Google Sign-In failed - Error: $e, Error Type: ${e.runtimeType}");
          }
          // Extract more details from PlatformException if available
          if (e.toString().contains("sign_in_failed") || e.toString().contains("10")) {
            if (LOGGING_SWITCH) {
              Logger().error("LoginModule: This is error code 10 - likely SHA-1 fingerprint mismatch. Check Google Cloud Console Android OAuth client configuration.");
            }
            if (LOGGING_SWITCH) {
              Logger().error("LoginModule: Current Server Client ID (Web): ${webClientId ?? 'Not set'}");
            }
            if (LOGGING_SWITCH) {
              Logger().error("LoginModule: Platform: ${kIsWeb ? 'Web' : 'Android'}");
            }
            if (!kIsWeb) {
              if (LOGGING_SWITCH) {
                Logger().error("LoginModule: Verify Android OAuth client has SHA-1: 8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76");
              }
              if (LOGGING_SWITCH) {
                Logger().error("LoginModule: Verify package name: com.reignofplay.dutch");
              }
            }
          }
          return {"error": "Google Sign-In failed: $e"};
        }
      }

      if (googleUser == null) {
        // User cancelled the sign-in
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Google Sign-In cancelled by user");
        }
        return {"error": "Sign-in cancelled"};
      }

      // Obtain the auth details from the request
      GoogleSignInAuthentication googleAuth;
      try {
        googleAuth = await googleUser.authentication;
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Google authentication obtained - Email: ${googleUser.email}, Has ID Token: ${googleAuth.idToken != null}, Has Access Token: ${googleAuth.accessToken != null}");
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          Logger().error("LoginModule: Failed to get Google authentication - Error: $e");
        }
        return {"error": "Failed to get authentication: $e"};
      }

      // Get the ID token or access token
      final String? idToken = googleAuth.idToken;
      final String? accessToken = googleAuth.accessToken;

      // Prepare request payload
      Map<String, dynamic> requestPayload;

      if (idToken != null) {
        // Preferred: Use ID token if available
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Google Sign-In - ID token obtained, sending to backend");
        }
        requestPayload = {"id_token": idToken};
      } else if (accessToken != null && kIsWeb) {
        // Fallback for web: Use access token to get user info, then send to backend
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Google Sign-In - No ID token, using access token to fetch user info (web)");
        }
        
        try {
          // Fetch user info from Google using access token
          final userInfoResponse = await http.get(
            Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );

          if (userInfoResponse.statusCode == 200) {
            final userInfo = json.decode(userInfoResponse.body);
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: User info fetched from Google API - Email: ${userInfo['email']}");
            }
            
            // Send access token and user info to backend
            requestPayload = {
              "access_token": accessToken,
              "user_info": userInfo,
            };
          } else {
            if (LOGGING_SWITCH) {
              Logger().error("LoginModule: Failed to fetch user info from Google API: ${userInfoResponse.statusCode}");
            }
            return {"error": "Failed to get user information from Google"};
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            Logger().error("LoginModule: Error fetching user info from Google: $e");
          }
          return {"error": "Failed to get user information from Google"};
        }
      } else {
        if (LOGGING_SWITCH) {
          Logger().warning("LoginModule: Google Sign-In - No ID token or access token received");
        }
        return {"error": "Failed to get Google authentication token. Please ensure Google Sign-In is properly configured."};
      }

      // Add guest account conversion info if provided
      if (isConvertingGuest) {
        requestPayload["convert_from_guest"] = true;
        requestPayload["guest_email"] = guestEmail;
        requestPayload["guest_password"] = guestPassword;
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Adding guest account conversion info to Google Sign-In request");
        }
      }
      if (forceNewSession) {
        requestPayload["force_new_session"] = true;
      }

      // Send to backend
      final response = await _connectionModule!.sendPostRequest(
        "/public/google-signin",
        requestPayload,
      );

      if (response?["status"] == 409 &&
          (response?["code"] == "SESSION_ACTIVE_ELSEWHERE" ||
              response?["error"] == "SESSION_ACTIVE_ELSEWHERE")) {
        return {
          "sessionConflict": true,
          "message": response?["message"]?.toString() ??
              "This account is already signed in on another device.",
        };
      }

      // Handle error responses
      if (response?["error"] != null || response?["message"]?.contains("error") == true) {
        String errorMessage = response?["message"] ?? response?["error"] ?? "Unknown error occurred";
        
        if (LOGGING_SWITCH) {
          Logger().warning("LoginModule: Google Sign-In failed - Error: $errorMessage");
        }
        
        // Handle rate limiting errors
        if (response?["status"] == 429) {
          return {
            "error": errorMessage,
            "isRateLimited": true
          };
        }
        
        return {"error": errorMessage};
      }

      // Handle successful Google Sign-In (aligned with backend response format)
      if (response?["success"] == true || response?["message"] == "Google Sign-In successful") {
        // Extract user data from response
        final userData = response?["data"]?["user"] ?? {};
        final accessToken = response?["data"]?["access_token"];
        final refreshToken = response?["data"]?["refresh_token"];
        
        if (accessToken == null) {
          return {"error": "Google Sign-In successful but no access token received"};
        }
        
        // Extract user information
        final email = userData['email']?.toString() ?? googleUser.email;
        final userId = userData['_id'] ?? userData['id'] ?? '';
        final username = userData['username'] ?? '';
        
        // Extract TTL values from backend response
        final expiresIn = response?["data"]?["expires_in"];
        final refreshExpiresIn = response?["data"]?["refresh_expires_in"];
        final accessTokenTtl = expiresIn is int ? expiresIn : null;
        final refreshTokenTtl = refreshExpiresIn is int ? refreshExpiresIn : null;
        
        // Store JWT tokens using AuthManager with TTL values
        await _authManager!.storeTokens(
          accessToken: accessToken,
          refreshToken: refreshToken ?? '',
          accessTokenTtl: accessTokenTtl,
          refreshTokenTtl: refreshTokenTtl,
        );
        WebSocketManager.instance.resetTransportState(reason: 'new_credentials_google_login');

        // Store user data in SharedPreferences
        await _sharedPref!.setBool('is_logged_in', true);
        await _sharedPref!.setString('user_id', userId);
        await _sharedPref!.setString('username', username);
        await _sharedPref!.setString('email', email);
        await _sharedPref!.setString('last_login_timestamp', DateTime.now().toIso8601String());
        
        // Clear guest account flags if conversion happened
        if (isConvertingGuest) {
          await _sharedPref!.remove('is_guest_account');
          await _sharedPref!.remove('guest_username');
          await _sharedPref!.remove('guest_email');
          await _sharedPref!.remove('guest_user_id');
          if (LOGGING_SWITCH) {
            Logger().info("LoginModule: Cleared guest account credentials after Google Sign-In conversion");
          }
        }
        
        // Set guest account flag (should be false for Google Sign-In)
        await _sharedPref!.setBool('is_guest_account', false);
        
        // Log successful Google Sign-In
        if (LOGGING_SWITCH) {
          Logger().info(
            "LoginModule: Google Sign-In successful - Username: $username, Email: $email, account_type: ${userData['account_type']}",
          );
        }

        await AnalyticsService.setUserId(userId.toString());
        await AnalyticsService.logEvent(
          name: 'account_login',
          parameters: {'method': 'google'},
        );
        if (isConvertingGuest) {
          await AnalyticsService.logEvent(name: 'account_guest_converted_google');
        }
        
        // Update state manager
        final stateManager = StateManager();
        stateManager.updateModuleState("login", {
          "isLoggedIn": true,
          "userId": userId,
          "username": username,
          "email": email,
          "error": null
        });
        
        // Fetch and update user profile (including picture) after Google Sign-In
        WidgetsBinding.instance.addPostFrameCallback((_) {
          fetchAndUpdateUserProfile();
        });
        
        // Trigger auth_login_complete hook after tokens are stored and user is fully logged in
        final hooksManager = HooksManager();
        hooksManager.triggerHookWithData('auth_login_complete', {
          'status': 'logged_in',
          'userData': {
            "isLoggedIn": true,
            "userId": userId,
            "username": username,
            "email": email,
          },
        });
        
        return {
          "success": "Google Sign-In successful",
          "user_id": userId,
          "username": username,
          "email": email,
          "access_token": accessToken,
          "refresh_token": refreshToken
        };
      }

      return {"error": "Unexpected server response"};
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        Logger().error("LoginModule: Google Sign-In error: $e");
      }
      if (LOGGING_SWITCH) {
        Logger().error("LoginModule: Google Sign-In error stack trace: $stackTrace");
      }
      
      // Handle specific Google Sign-In errors
      final errorString = e.toString().toLowerCase();
      
      if (errorString.contains('sign_in_canceled') || errorString.contains('cancelled')) {
        return {"error": "Sign-in cancelled"};
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        return {"error": "Network error. Please check your connection."};
      } else if (errorString.contains('redirect_uri_mismatch') || errorString.contains('redirect_uri')) {
        return {"error": "OAuth configuration error. Please contact support or try again later."};
      } else if (errorString.contains('clientexception')) {
        // Extract more details from ClientException
        final errorMessage = e.toString();
        if (errorMessage.contains('redirect_uri_mismatch')) {
          return {"error": "OAuth configuration error. The app origin is not authorized. Please contact support."};
        }
        return {"error": "Google Sign-In configuration error: ${errorMessage.length > 100 ? errorMessage.substring(0, 100) + '...' : errorMessage}"};
      }
      
      return {"error": "Google Sign-In failed: ${e.toString().length > 150 ? e.toString().substring(0, 150) + '...' : e.toString()}"};
    }
  }

  Future<Map<String, dynamic>> logoutUser(BuildContext context) async {
    _initDependencies(context);

    if (_authManager == null) {
      return {"error": "Service not available"};
    }

    try {
      if (LOGGING_SWITCH) {
        final isGuestAccount = _sharedPref?.getBool('is_guest_account') ?? false;
        Logger().info(
          isGuestAccount
              ? 'LoginModule: Guest account logout - preserving guest + form prefs'
              : 'LoginModule: Regular account logout',
        );
      }

      await _runFullAuthTeardown(
        triggerContext: context,
        keepLoginFormFields: true,
      );

      await AnalyticsService.setUserId(null);

      return {"success": "Logout successful"};
    } catch (e) {
      return {"error": "Logout failed"};
    }
  }

  /// Fetch and update user profile data including picture
  /// Stores profile data in StateManager under "login" state
  Future<bool> fetchAndUpdateUserProfile() async {
    try {
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: Fetching user profile...');
      }
      
      if (_connectionModule == null) {
        if (LOGGING_SWITCH) {
          Logger().error('LoginModule: ConnectionsApiModule not available');
        }
        return false;
      }
      
      final response = await _connectionModule!.sendGetRequest('/userauth/users/profile');
      
      if (response is Map && response.containsKey('error')) {
        if (LOGGING_SWITCH) {
          Logger().warning('LoginModule: Failed to fetch profile: ${response['error']}');
        }
        return false;
      }
      
      final profile = response['profile'] as Map<String, dynamic>?;
      final pictureUrl = profile?['picture'] as String?;
      // Plain email/username from backend (from JWT); use for display instead of encrypted DB values
      final profileEmail = response['email'] as String?;
      final profileUsername = response['username'] as String?;
      
      // Update StateManager with profile data
      final stateManager = StateManager();
      final currentLoginState = stateManager.getModuleState<Map<String, dynamic>>("login") ?? {};
      
      final updates = <String, dynamic>{
        ...currentLoginState,
        "profile": profile ?? {},
        "profilePicture": pictureUrl,
      };
      final responseRole = response['role'] as String?;
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: Profile response role: ${responseRole ?? "(null/empty)"}');
      }
      if (responseRole != null && responseRole.isNotEmpty) {
        updates["role"] = responseRole;
      }
      if (profileEmail != null && profileEmail.isNotEmpty) {
        updates["email"] = profileEmail;
        // Persist plain email to SharedPref so it stays decrypted for display/pre-fill after logout
        if (!profileEmail.startsWith('det_') && _sharedPref != null) {
          await _sharedPref!.setString('email', profileEmail);
        }
      }
      if (profileUsername != null && profileUsername.isNotEmpty) {
        updates["username"] = profileUsername;
        if (!profileUsername.startsWith('det_') && _sharedPref != null) {
          await _sharedPref!.setString('username', profileUsername);
        }
      }
      stateManager.updateModuleState("login", updates);
      
      if (pictureUrl != null && pictureUrl.isNotEmpty) {
        if (_sharedPref != null) {
          await _sharedPref!.setString('profile_picture', pictureUrl);
        }
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: Profile picture updated: $pictureUrl');
        }
      } else {
        if (_sharedPref != null) {
          await _sharedPref!.remove('profile_picture');
        }
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: No profile picture available');
        }
      }
      
      return true;
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().error('LoginModule: Error fetching user profile: $e');
      }
      return false;
    }
  }

  /// Upload profile photo (multipart `file`). Server normalizes to WebP; client sends JPEG after resize.
  /// On success, refreshes login state via [fetchAndUpdateUserProfile].
  Future<Map<String, dynamic>> uploadProfileAvatar({
    required List<int> bytes,
    String filename = 'profile.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    if (_connectionModule == null) {
      if (LOGGING_SWITCH) {
        Logger().warning('LoginModule: uploadProfileAvatar — ConnectionsApiModule not available');
      }
      return {'success': false, 'message': 'API not available'};
    }
    try {
      if (LOGGING_SWITCH) {
        Logger().info(
          'LoginModule: uploadProfileAvatar POST /userauth/users/profile/avatar '
          'bytes=${bytes.length} filename=$filename mime=$mimeType',
        );
      }
      final res = await _connectionModule!.sendMultipartPostRequest(
        '/userauth/users/profile/avatar',
        fieldName: 'file',
        fileBytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      if (LOGGING_SWITCH) {
        Logger().info('LoginModule: uploadProfileAvatar response: $res');
      }
      if (res is Map && res['success'] == true) {
        await fetchAndUpdateUserProfile();
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: uploadProfileAvatar success — profile refreshed');
        }
      }
      if (res is Map<String, dynamic>) {
        return res;
      }
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      if (LOGGING_SWITCH) {
        Logger().error('LoginModule: uploadProfileAvatar failed: $e');
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  /// ✅ Get current JWT token for WebSocket authentication
  ///
  /// If the access JWT [exp] is past or near expiry, calls [AuthManager.refreshToken] first so
  /// connect/authenticate use a fresh access token. This bypasses [AuthManager]'s game-state
  /// logic that can return a stale access token in `pre_game` / `active_game` / `post_game`,
  /// which would cause Python token validation to fail while the user is in the lobby.
  Future<String?> getCurrentToken() async {
    if (_authManager == null) {
      return null;
    }

    try {
      final access = await _authManager!.getAccessToken();
      if (access != null &&
          WsJwtAccessExpiry.isJwtExpiredOrNearExpiry(
            access,
            within: const Duration(seconds: 90),
          )) {
        final refreshed = await _authManager!.refreshToken();
        if (refreshed != null && refreshed.isNotEmpty) {
          if (LOGGING_SWITCH) {
            Logger().info(
              'LoginModule: WebSocket token path — refreshed access JWT (exp-based)',
            );
          }
          return refreshed;
        }
      }

      final token = await _authManager!.getCurrentValidToken();
      return token;
    } catch (e) {
      return null;
    }
  }

  /// ✅ Check if user has valid JWT token for WebSocket
  Future<bool> hasValidToken() async {
    if (_authManager == null) {
      return false;
    }
    
    try {
      // Use AuthManager to check token validity
      final isValid = await _authManager!.hasValidToken();
      return isValid;
    } catch (e) {
      return false;
    }
  }
}
