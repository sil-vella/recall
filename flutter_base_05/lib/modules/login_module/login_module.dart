import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
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
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';

class LoginModule extends ModuleBase {
  // Logging switch for guest registration, login, and backend connectivity
  static const bool LOGGING_SWITCH = false; // Enabled for testing auto-guest creation, game creation loops, and registration differences

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
    try {
      // Check if guest account
      final isGuestAccount = _sharedPref?.getBool('is_guest_account') ?? false;
      
      if (isGuestAccount) {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Synchronous guest account logout - preserving permanent credentials");
        }
      }
      
      // Clear JWT tokens using AuthManager
      _authManager?.clearTokens();
      
      // Clear session state
      _sharedPref?.setBool('is_logged_in', false);
      
      if (isGuestAccount) {
        // Guest account: Only clear session keys, preserve permanent guest credentials
        _sharedPref?.remove('user_id');
        _sharedPref?.remove('username');
        _sharedPref?.remove('email');
        if (LOGGING_SWITCH) {
          Logger().debug("LoginModule: Guest account session keys cleared in synchronous logout");
        }
        // DO NOT clear: guest_username, guest_email, guest_user_id, is_guest_account
      } else {
        // Regular account: Clear all credentials (existing behavior)
        _sharedPref?.remove('user_id');
        _sharedPref?.remove('username');
        _sharedPref?.remove('email');
      }
      
      // Update state manager
      final stateManager = StateManager();
      stateManager.updateModuleState("login", {
        "isLoggedIn": false,
        "userId": null,
        "username": null,
        "email": null,
        "error": null
      });
    } catch (e) {
      // Handle error silently
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
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: Guest account conversion successful - Username: $username, Email: $email, clearing guest credentials");
            }
            await _sharedPref!.remove('guest_username');
            await _sharedPref!.remove('guest_email');
            await _sharedPref!.remove('guest_user_id');
            await _sharedPref!.setBool('is_guest_account', false);
          } else {
            if (LOGGING_SWITCH) {
              Logger().info("LoginModule: Regular registration successful - Username: $username, Email: $email");
            }
          }
          return {"success": "Registration successful. Please log in."};
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
  }) async {
    _initDependencies(context);

    if (_connectionModule == null || _sharedPref == null || _authManager == null) {
      return {"error": "Service not available."};
    }

    try {
      // Log login attempt
      if (LOGGING_SWITCH) {
        Logger().info("LoginModule: Login request initiated - Email: $email");
      }
      
      // Use the correct backend route
      final response = await _connectionModule!.sendPostRequest(
        "/public/login",
        {"email": email, "password": password},
      );

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
        
        // Store user data in SharedPreferences
        await _sharedPref!.setBool('is_logged_in', true);
        final userId = userData['_id'] ?? userData['id'] ?? '';
        final username = userData['username'] ?? '';
        
        await _sharedPref!.setString('user_id', userId);
        await _sharedPref!.setString('username', username);
        await _sharedPref!.setString('email', email);
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
      if (isConvertingGuest && guestEmail != null && guestPassword != null) {
        requestPayload["convert_from_guest"] = true;
        requestPayload["guest_email"] = guestEmail;
        requestPayload["guest_password"] = guestPassword;
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Adding guest account conversion info to Google Sign-In request");
        }
      }

      // Send to backend
      final response = await _connectionModule!.sendPostRequest(
        "/public/google-signin",
        requestPayload,
      );

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
        final accountType = userData['account_type']?.toString();
        final isGuestAccount = accountType == 'guest' || email.endsWith('@guest.local');
        
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
          Logger().info("LoginModule: Google Sign-In successful - Username: $username, Email: $email");
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
      // Check if guest account
      final isGuestAccount = await _sharedPref!.getBool('is_guest_account') ?? false;
      
      if (isGuestAccount) {
        if (LOGGING_SWITCH) {
          Logger().info("LoginModule: Guest account logout - preserving permanent credentials");
        }
      } else {
        if (LOGGING_SWITCH) {
          Logger().debug("LoginModule: Regular account logout");
        }
      }
      
      // Clear JWT tokens using AuthManager
      await _authManager!.clearTokens();
      
      // Clear session state
      await _sharedPref!.setBool('is_logged_in', false);
      
      if (isGuestAccount) {
        // Guest account: Only clear session keys, preserve permanent guest credentials
        await _sharedPref!.remove('user_id');
        await _sharedPref!.remove('username');
        await _sharedPref!.remove('email');
        if (LOGGING_SWITCH) {
          Logger().debug("LoginModule: Guest account session keys cleared, permanent credentials preserved");
        }
        // DO NOT clear: guest_username, guest_email, guest_user_id, is_guest_account
      } else {
        // Regular account: Clear all credentials (existing behavior)
        await _sharedPref!.remove('user_id');
        await _sharedPref!.remove('username');
        await _sharedPref!.remove('email');
      }
      
      // Update state manager
      final stateManager = StateManager();
      stateManager.updateModuleState("login", {
        "isLoggedIn": false,
        "userId": null,
        "username": null,
        "email": null,
        "error": null
      });
      
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
      
      // Update StateManager with profile data
      final stateManager = StateManager();
      final currentLoginState = stateManager.getModuleState<Map<String, dynamic>>("login") ?? {};
      
      stateManager.updateModuleState("login", {
        ...currentLoginState,
        "profile": profile ?? {},
        "profilePicture": pictureUrl,
      });
      
      if (pictureUrl != null && pictureUrl.isNotEmpty) {
        if (LOGGING_SWITCH) {
          Logger().info('LoginModule: Profile picture updated: $pictureUrl');
        }
      } else {
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

  /// ✅ Get current JWT token for WebSocket authentication
  Future<String?> getCurrentToken() async {
    if (_authManager == null) {
      return null;
    }
    
    try {
      // Use AuthManager to get current valid token
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
