import 'package:flutter/material.dart';
import '../connections_api_module/connections_api_module.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/auth_manager.dart';

class LoginModule extends ModuleBase {
  static final Logger _log = Logger();

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
    _log.info('✅ LoginModule initialized with context.');
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

  Future<Map<String, dynamic>> getUserStatus(BuildContext context) async {
    _initDependencies(context);

    if (_sharedPref == null) {
      _log.error("❌ SharedPrefManager not available.");
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
  }) async {
    _initDependencies(context);

    if (_connectionModule == null) {
      _log.error("❌ Connection module not available.");
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
      _log.info("⚡ Sending registration request...");
      _log.info("📤 Registration data: username=$username, email=$email");
      
      // Use the correct backend route
      final response = await _connectionModule!.sendPostRequest(
        "/public/register",
        {
          "username": username,
          "email": email,
          "password": password,
        },
      );

      _log.info("📥 Registration response: $response");

      if (response is Map) {
        if (response["success"] == true || response["message"] == "User created successfully") {
          _log.info("✅ User registered successfully.");
          return {"success": "Registration successful. Please log in."};
        } else if (response["error"] != null) {
          _log.error("❌ Registration failed: ${response["error"]}");
          
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

      _log.error("❌ Unexpected response format: $response");
      return {"error": "Unexpected server response format"};
    } catch (e) {
      _log.error("❌ Registration error: $e");
      return {"error": "Server error. Check network connection."};
    }
  }

  Future<Map<String, dynamic>> loginUser({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    _initDependencies(context);
    _log.info("🔑 Starting login process for email: $email");

    if (_connectionModule == null || _sharedPref == null || _authManager == null) {
      _log.error("❌ Missing required modules for login.");
      return {"error": "Service not available."};
    }

    try {
      _log.info("⚡ Preparing login request...");
      _log.info("📤 Sending login request to backend...");
      
      // Use the correct backend route
      final response = await _connectionModule!.sendPostRequest(
        "/public/login",
        {"email": email, "password": password},
      );
      _log.info("📥 Received login response: $response");

      // Handle error responses
      if (response?["status"] == 409 || response?["code"] == "CONFLICT") {
        _log.info("⚠️ Login failed: Conflict detected");
        return {
          "error": response["message"] ?? "A conflict occurred",
          "user": response["user"]
        };
      }

      if (response?["error"] != null || response?["message"]?.contains("error") == true) {
        String errorMessage = response?["message"] ?? response?["error"] ?? "Unknown error occurred";
        _log.error("❌ Login failed: $errorMessage");
        
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
        _log.info("✅ Login successful");
        
        // Extract user data from response
        final userData = response?["data"]?["user"] ?? {};
        final accessToken = response?["data"]?["access_token"];
        final refreshToken = response?["data"]?["refresh_token"];
        
        if (accessToken == null) {
          _log.error("❌ No access token in login response");
          return {"error": "Login successful but no access token received"};
        }
        
        // Store JWT tokens using AuthManager
        await _authManager!.storeTokens(
          accessToken: accessToken,
          refreshToken: refreshToken ?? '',
        );
        
        // Store user data in SharedPreferences
        await _sharedPref!.setBool('is_logged_in', true);
        await _sharedPref!.setString('user_id', userData['_id'] ?? userData['id'] ?? '');
        await _sharedPref!.setString('username', userData['username'] ?? '');
        await _sharedPref!.setString('email', email);
        await _sharedPref!.setString('last_login_timestamp', DateTime.now().toIso8601String());
        
        // Update state manager
        final stateManager = StateManager();
        stateManager.updateModuleState("login", {
          "isLoggedIn": true,
          "userId": userData['_id'] ?? userData['id'],
          "username": userData['username'],
          "email": email,
          "error": null
        });
        
        _log.info("✅ JWT tokens stored for WebSocket authentication");
        
        return {
          "success": "Login successful",
          "user_id": userData['_id'] ?? userData['id'],
          "username": userData['username'],
          "email": email,
          "access_token": accessToken,
          "refresh_token": refreshToken
        };
      }

      _log.error("❌ Unexpected login response: $response");
      return {"error": "Unexpected server response"};
    } catch (e) {
      _log.error("❌ Login error: $e");
      return {"error": "Server error. Check network connection."};
    }
  }

  Future<Map<String, dynamic>> logoutUser(BuildContext context) async {
    _initDependencies(context);
    _log.info("🔓 Starting logout process");

    if (_authManager == null) {
      _log.error("❌ AuthManager not available for logout");
      return {"error": "Service not available"};
    }

    try {
      // Clear JWT tokens using AuthManager
      await _authManager!.clearTokens();
      
      // Clear stored user data
      await _sharedPref!.setBool('is_logged_in', false);
      await _sharedPref!.remove('user_id');
      await _sharedPref!.remove('username');
      await _sharedPref!.remove('email');
      
      // Update state manager
      final stateManager = StateManager();
      stateManager.updateModuleState("login", {
        "isLoggedIn": false,
        "userId": null,
        "username": null,
        "email": null,
        "error": null
      });
      
      _log.info("✅ Logout successful - JWT tokens cleared");
      return {"success": "Logout successful"};
    } catch (e) {
      _log.error("❌ Logout error: $e");
      return {"error": "Logout failed"};
    }
  }

  /// ✅ Get current JWT token for WebSocket authentication
  Future<String?> getCurrentToken() async {
    if (_authManager == null) {
      _log.error("❌ AuthManager not available for token retrieval");
      return null;
    }
    
    try {
      // Use AuthManager to get current valid token
      final token = await _authManager!.getCurrentValidToken();
      if (token != null) {
        _log.info("✅ Retrieved JWT token for WebSocket authentication");
      } else {
        _log.info("⚠️ No JWT token available for WebSocket authentication");
      }
      return token;
    } catch (e) {
      _log.error("❌ Error retrieving JWT token: $e");
      return null;
    }
  }

  /// ✅ Check if user has valid JWT token for WebSocket
  Future<bool> hasValidToken() async {
    if (_authManager == null) {
      _log.error("❌ AuthManager not available for token validation");
      return false;
    }
    
    try {
      // Use AuthManager to check token validity
      final isValid = await _authManager!.hasValidToken();
      if (isValid) {
        _log.info("✅ JWT token is valid for WebSocket authentication");
      } else {
        _log.info("⚠️ JWT token is not valid for WebSocket authentication");
      }
      return isValid;
    } catch (e) {
      _log.error("❌ Error validating token: $e");
      return false;
    }
  }
}
