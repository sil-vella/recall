import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';

/// Pure business logic module for login functionality
/// Contains no Flutter/system dependencies
class LoginModule {
  static final Logger _log = Logger();

  /// Initialize the module
  void initialize() {
    _log.info('🔧 Initializing LoginModule (pure business logic)');
    _log.info('✅ LoginModule initialized');
  }

  /// Validate username (business logic only)
  Map<String, dynamic> validateUsername(String username) {
    _log.info('🔍 Validating username: $username');
    
    if (username.length < 3) {
      return {
        'valid': false,
        'error': 'Username must be at least 3 characters long'
      };
    }
    
    if (username.length > 20) {
      return {
        'valid': false,
        'error': 'Username cannot be longer than 20 characters'
      };
    }
    
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$').hasMatch(username)) {
      return {
        'valid': false,
        'error': 'Username can only contain letters, numbers, underscores, and hyphens'
      };
    }
    
    if (RegExp(r'[-_]{2,}').hasMatch(username)) {
      return {
        'valid': false,
        'error': 'Username cannot contain consecutive special characters'
      };
    }
    
    if (username.startsWith('_') || username.startsWith('-') || 
        username.endsWith('_') || username.endsWith('-')) {
      return {
        'valid': false,
        'error': 'Username cannot start or end with special characters'
      };
    }
    
    return {
      'valid': true,
      'username': username
    };
  }

  /// Validate email format (business logic only)
  Map<String, dynamic> validateEmail(String email) {
    _log.info('🔍 Validating email: $email');
    
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return {
        'valid': false,
        'error': 'Invalid email format. Please enter a valid email address.'
      };
    }
    
    return {
      'valid': true,
      'email': email
    };
  }

  /// Validate password requirements (business logic only)
  Map<String, dynamic> validatePassword(String password) {
    _log.info('🔍 Validating password');
    
    if (password.length < 8) {
      return {
        'valid': false,
        'error': 'Password must be at least 8 characters long'
      };
    }
    
    return {
      'valid': true,
      'password': password
    };
  }

  /// Prepare registration data (business logic only)
  Map<String, dynamic> prepareRegistrationData({
    required String username,
    required String email,
    required String password,
  }) {
    _log.info('📝 Preparing registration data for: $username');
    
    // Validate all inputs
    final usernameValidation = validateUsername(username);
    if (!usernameValidation['valid']) {
      return {
        'success': false,
        'error': usernameValidation['error']
      };
    }
    
    final emailValidation = validateEmail(email);
    if (!emailValidation['valid']) {
      return {
        'success': false,
        'error': emailValidation['error']
      };
    }
    
    final passwordValidation = validatePassword(password);
    if (!passwordValidation['valid']) {
      return {
        'success': false,
        'error': passwordValidation['error']
      };
    }
    
    return {
      'success': true,
      'registration_data': {
        'username': username,
        'email': email,
        'password': password,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Prepare login data (business logic only)
  Map<String, dynamic> prepareLoginData({
    required String email,
    required String password,
  }) {
    _log.info('📝 Preparing login data for: $email');
    
    // Validate email
    final emailValidation = validateEmail(email);
    if (!emailValidation['valid']) {
      return {
        'success': false,
        'error': emailValidation['error']
      };
    }
    
    // Validate password
    final passwordValidation = validatePassword(password);
    if (!passwordValidation['valid']) {
      return {
        'success': false,
        'error': passwordValidation['error']
      };
    }
    
    return {
      'success': true,
      'login_data': {
        'email': email,
        'password': password,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Process registration response (business logic only)
  Map<String, dynamic> processRegistrationResponse(Map<String, dynamic> response) {
    _log.info('📥 Processing registration response');
    
    if (response is Map) {
      if (response["success"] == true || response["message"] == "User created successfully") {
        _log.info('✅ Registration response indicates success');
        return {
          'success': true,
          'message': 'Registration successful. Please log in.',
          'response_data': response,
        };
      } else if (response["error"] != null) {
        _log.error('❌ Registration response indicates error: ${response["error"]}');
        
        // Handle rate limiting errors
        if (response["status"] == 429) {
          return {
            'success': false,
            'error': response["error"] ?? "Too many registration attempts. Please try again later.",
            'is_rate_limited': true,
            'response_data': response,
          };
        }
        
        return {
          'success': false,
          'error': response["error"],
          'response_data': response,
        };
      }
    }
    
    _log.error('❌ Unexpected registration response format: $response');
    return {
      'success': false,
      'error': 'Unexpected server response format',
      'response_data': response,
    };
  }

  /// Process login response (business logic only)
  Map<String, dynamic> processLoginResponse(Map<String, dynamic> response) {
    _log.info('📥 Processing login response');
    
    // Handle error responses
    if (response?["status"] == 409 || response?["code"] == "CONFLICT") {
      _log.info('⚠️ Login response indicates conflict');
      return {
        'success': false,
        'error': response["message"] ?? "A conflict occurred",
        'user': response["user"],
        'response_data': response,
      };
    }

    if (response?["error"] != null || response?["message"]?.contains("error") == true) {
      String errorMessage = response?["message"] ?? response?["error"] ?? "Unknown error occurred";
      _log.error('❌ Login response indicates error: $errorMessage');
      
      // Handle rate limiting errors
      if (response?["status"] == 429) {
        return {
          'success': false,
          'error': errorMessage,
          'is_rate_limited': true,
          'response_data': response,
        };
      }
      
      return {
        'success': false,
        'error': errorMessage,
        'response_data': response,
      };
    }

    // Handle successful login
    if (response?["success"] == true || response?["message"] == "Login successful") {
      _log.info('✅ Login response indicates success');
      
      // Extract user data from response
      final userData = response?["data"]?["user"] ?? {};
      final accessToken = response?["data"]?["access_token"];
      final refreshToken = response?["data"]?["refresh_token"];
      
      if (accessToken == null) {
        _log.error('❌ No access token in login response');
        return {
          'success': false,
          'error': 'Login successful but no access token received',
          'response_data': response,
        };
      }
      
      // Extract TTL values from backend response
      final expiresIn = response?["data"]?["expires_in"];
      final refreshExpiresIn = response?["data"]?["refresh_expires_in"];
      final accessTokenTtl = expiresIn is int ? expiresIn : null;
      final refreshTokenTtl = refreshExpiresIn is int ? refreshExpiresIn : null;
      
      return {
        'success': true,
        'user_data': {
          'user_id': userData['_id'] ?? userData['id'],
          'username': userData['username'],
          'email': userData['email'] ?? response?["data"]?["email"],
        },
        'tokens': {
          'access_token': accessToken,
          'refresh_token': refreshToken ?? '',
          'access_token_ttl': accessTokenTtl,
          'refresh_token_ttl': refreshTokenTtl,
        },
        'response_data': response,
      };
    }
    
    _log.error('❌ Unexpected login response: $response');
    return {
      'success': false,
      'error': 'Unexpected server response',
      'response_data': response,
    };
  }

  /// Prepare logout data (business logic only)
  Map<String, dynamic> prepareLogoutData() {
    _log.info('📝 Preparing logout data');
    
    return {
      'success': true,
      'logout_data': {
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
  }

  /// Get hooks needed by this module
  List<Map<String, dynamic>> getHooksNeeded() {
    return [
      {
        'hookName': 'auth_required',
        'priority': 1,
        'context': 'authentication',
      },
      {
        'hookName': 'refresh_token_expired',
        'priority': 1,
        'context': 'authentication',
      },
      {
        'hookName': 'auth_token_refresh_failed',
        'priority': 1,
        'context': 'authentication',
      },
      {
        'hookName': 'auth_error',
        'priority': 1,
        'context': 'authentication',
      },
      {
        'hookName': 'login_success',
        'priority': 1,
        'context': 'authentication',
      },
      {
        'hookName': 'logout_success',
        'priority': 1,
        'context': 'authentication',
      },
    ];
  }

  /// Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/public/register',
        'methods': ['POST'],
        'handler': 'register_user',
        'auth_required': false,
        'description': 'User registration endpoint',
      },
      {
        'route': '/public/login',
        'methods': ['POST'],
        'handler': 'login_user',
        'auth_required': false,
        'description': 'User login endpoint',
      },
      {
        'route': '/account',
        'methods': ['GET'],
        'handler': 'account_screen',
        'auth_required': false,
        'description': 'Account management screen',
      },
    ];
  }

  /// Get configuration requirements
  Map<String, dynamic> getConfigRequirements() {
    return {
      'api_url': Config.apiUrl,
      'jwt_access_token_expires': Config.jwtAccessTokenExpiresFallback,
      'jwt_refresh_token_expires': Config.jwtRefreshTokenExpiresFallback,
    };
  }

  /// Health check for this module
  Map<String, dynamic> healthCheck() {
    return {
      'module': 'login_module',
      'status': 'healthy',
      'details': 'Login module is functioning normally',
      'hooks_needed': getHooksNeeded().length,
      'routes_needed': getRoutesNeeded().length,
    };
  }

  /// Cleanup module resources
  Map<String, dynamic> cleanup() {
    _log.info('🗑 Cleaning up LoginModule');
    return {
      'success': true,
      'message': 'LoginModule cleanup completed',
    };
  }
}
