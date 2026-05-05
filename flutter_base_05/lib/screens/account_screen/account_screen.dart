import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../core/managers/websockets/websocket_manager.dart';
import '../../modules/login_module/login_module.dart';
import '../../modules/analytics_module/analytics_module.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_avatar.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_section_header.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_settings_row.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/theme_consts.dart';
import '../../utils/profile_photo_helper.dart';
import 'package:image_picker/image_picker.dart';

class AccountScreen extends BaseScreen {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AccountScreen> createState() => _AccountScreenState();

  @override
  String computeTitle(BuildContext context) => 'Account';
}

class _AccountScreenState extends BaseScreenState<AccountScreen> {
  static const bool LOGGING_SWITCH = true; // Profile photo pick/upload trace (enable-logging-switch.mdc) — set false after debugging
  static final Logger _logger = Logger();
  
  // Form controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _registerEmailController = TextEditingController();
  final TextEditingController _registerPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  // Form keys
  final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _registerFormKey = GlobalKey<FormState>();
  
  // UI state
  bool _isLoginMode = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;
  bool _showRegistrationForm = false; // Allow showing registration form even when logged in
  
  // Guest account conversion state
  String? _guestEmail;
  String? _guestPassword;
  bool _isConvertingGuest = false;
  bool _isGuestAccount = false;
  bool _lastLoggedInState = false; // Track previous login state to prevent rebuild loops
  
  /// Timer for delayed profile refetch (2s after entry); cancelled in dispose.
  Timer? _profileRefetchTimer;

  bool _uploadingProfilePhoto = false;
  Uint8List? _recentUploadedProfilePhotoBytes;
  
  // Module manager
  final ModuleManager _moduleManager = ModuleManager();
  LoginModule? _loginModule;
  AnalyticsModule? _analyticsModule;
  
  @override
  void initState() {
    super.initState();
    if (LOGGING_SWITCH) {
      _logger.info('🔍 AccountScreen initState called');
    }
    _initializeModules();
    _checkGuestAccountStatus();
    // Load preserved credentials in post-frame so form is populated before first paint when possible
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForGuestCredentials();
    });
    _trackScreenView();
    // Always refetch profile on account screen entry
    _fetchUserProfile();
    // Schedule a second refetch after 2 seconds (e.g. to pick up role/DB changes)
    _profileRefetchTimer?.cancel();
    _profileRefetchTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _fetchUserProfile();
    });
  }
  
  /// Track screen view
  Future<void> _trackScreenView() async {
    try {
      _analyticsModule = _moduleManager.getModuleByType<AnalyticsModule>();
      await _analyticsModule?.trackScreenView('account_screen');
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error tracking screen view: $e');
      }
    }
  }
  
  /// Check if current user is a guest account
  Future<void> _checkGuestAccountStatus() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      final newIsGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      
      // Only call setState if the value actually changed (prevents unnecessary rebuilds)
      if (newIsGuestAccount != _isGuestAccount) {
        setState(() {
          _isGuestAccount = newIsGuestAccount;
        });
      }
      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Guest account status checked - isGuestAccount: $_isGuestAccount');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking guest account status: $e');
      }
    }
  }
  
  /// Fetch user profile data using LoginModule helper
  Future<void> _fetchUserProfile() async {
    try {
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState("login");
      final isLoggedIn = loginState?["isLoggedIn"] ?? false;
      
      if (!isLoggedIn) {
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: User not logged in, skipping profile fetch');
        }
        return;
      }
      
      if (_loginModule == null) {
        if (LOGGING_SWITCH) {
          _logger.error('AccountScreen: LoginModule not available');
        }
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Fetching user profile via LoginModule...');
      }
      await _loginModule!.fetchAndUpdateUserProfile();
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error fetching user profile: $e');
      }
    }
  }
  
  void _initializeModules() {
    _loginModule = _moduleManager.getModuleByType<LoginModule>();
    _analyticsModule = _moduleManager.getModuleByType<AnalyticsModule>();
    if (_loginModule == null) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Login module not available');
      }
    }
  }
  
  /// Check for preserved credentials (temp keys) and auto-populate login form.
  /// Uses temp keys (username, email, password). After logout these are kept for pre-fill.
  /// Email must be plain (not encrypted det_...); we do not pre-fill encrypted values.
  Future<void> _checkForGuestCredentials() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final username = sharedPref.getString('username');
      String? email = sharedPref.getString('email');
      final password = sharedPref.getString('password');
      // Backend may store encrypted (det_...) in DB; only show plain email in form
      if (email != null && email.startsWith('det_')) {
        email = null;
      }
      
      final hasEmail = email != null && email.isNotEmpty;
      final hasUsername = username != null && username.isNotEmpty;
      final hasPassword = password != null && password.isNotEmpty;
      if (!hasEmail && !hasUsername) return;

      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Found preserved credentials (temp keys) - username: $username, email: $email');
      }
      // Email: use saved plain email, or for guest without email build from username
      if (hasEmail) {
        _emailController.text = email;
      } else if (isGuestAccount && hasUsername) {
        _emailController.text = 'guest_$username@guest.local';
      }
      // Password: use saved key if present, else for guest use username
      if (hasPassword) {
        _passwordController.text = password;
      } else if (isGuestAccount && hasUsername) {
        _passwordController.text = username;
      }
      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Auto-populated login form from temp keys (guest=$isGuestAccount)');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking for guest credentials', error: e);
      }
    }
  }
  
  @override
  void dispose() {
    _profileRefetchTimer?.cancel();
    _profileRefetchTimer = null;
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
  
  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _clearMessages();
      _clearForms();
      
      // Check for guest account when switching to registration mode
      if (!_isLoginMode) {
        _checkForGuestAccountForConversion();
      } else {
        // Reset guest conversion state when switching to login mode
        _isConvertingGuest = false;
        _guestEmail = null;
        _guestPassword = null;
        // Check for guest credentials for login
        _checkForGuestCredentials();
      }
    });
  }
  
  /// Check for guest account when in registration mode (uses temp keys)
  Future<void> _checkForGuestAccountForConversion() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final username = sharedPref.getString('username');
      final email = sharedPref.getString('email');
      
      if (isGuestAccount && username != null && username.isNotEmpty && email != null && email.isNotEmpty) {
        setState(() {
          _isConvertingGuest = true;
          _guestEmail = email;
          _guestPassword = username; // Guest password is same as username
        });
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: Guest account detected for conversion (temp keys) - Email: $email');
        }
      } else {
        setState(() {
          _isConvertingGuest = false;
          _guestEmail = null;
          _guestPassword = null;
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking for guest account: $e');
      }
      setState(() {
        _isConvertingGuest = false;
      });
    }
  }
  
  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }
  
  void _clearForms() {
    _usernameController.clear();
    _registerEmailController.clear();
    _registerPasswordController.clear();
    _confirmPasswordController.clear();
  }
  
  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }
  
  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }
  
  /// Clear all user data from app storage (SharedPreferences + secure tokens).
  /// Does not delete the user account on the server.
  static const List<String> _userStorageKeys = [
    'user_id', 'username', 'email', 'password',
    'guest_username', 'guest_email', 'guest_user_id',
    'is_guest_account', 'is_logged_in', 'last_login_timestamp',
  ];
  
  Future<void> _handleClearAllUserDataFromStorage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Clear app storage?'),
          content: const Text(
            'This will remove saved login data from this device (email, password, session flags) '
            'and delete JWT access and refresh tokens from secure storage. '
            'You will need to sign in again. Your account on the server is not affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear storage'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    try {
      final auth = AuthManager();
      // Clear JWTs first so stale tokens cannot be used even if prefs cleanup fails mid-way.
      await auth.clearTokens();
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      for (final key in _userStorageKeys) {
        await sharedPref.remove(key);
      }
      await auth.clearSessionAuthData(
        keepLoginFormFields: false,
        prefs: sharedPref,
      );
      StateManager().updateModuleState('login', {
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
      } catch (_) {}
      _clearForms();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage = 'App storage cleared. Your account was not changed.';
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error clearing user data from storage', error: e);
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to clear storage: $e';
        });
      }
    }
  }

  /// Ask whether to revoke the other device's session and continue login on this device.
  Future<bool?> _confirmTakeOverOtherSession(String message) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Already signed in', style: AppTextStyles.headingSmall()),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: AppTextStyles.bodyMedium(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Sign in here',
              style: AppTextStyles.bodyMedium(color: AppColors.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Handles [LoginModule.sessionConflict] by prompting, then retrying with [forceNewSession].
  Future<Map<String, dynamic>> _loginResolvingSessionConflict({
    required String email,
    required String password,
  }) async {
    var result = await _loginModule!.loginUser(
      context: context,
      email: email,
      password: password,
    );
    if (result['sessionConflict'] == true && mounted) {
      final ok = await _confirmTakeOverOtherSession(
        result['message']?.toString() ??
            'This account is already signed in on another device. '
                'Continue to sign out the other session and use this device?',
      );
      if (ok != true) {
        return {'cancelled': true};
      }
      if (!mounted) {
        return {'cancelled': true};
      }
      result = await _loginModule!.loginUser(
        context: context,
        email: email,
        password: password,
        forceNewSession: true,
      );
    }
    return result;
  }
  
  Future<void> _handleLogin() async {
    // Track button click
    await _analyticsModule?.trackButtonClick('login_button', screenName: 'account_screen');
    
    if (!_loginFormKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      final result = await _loginResolvingSessionConflict(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result['cancelled'] == true) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      
      if (result['success'] != null) {
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // Stay on account screen after successful login.
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('AccountScreen: Login failed - result: $result');
        }
        setState(() {
          _errorMessage = result['error'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Login exception', error: e);
      }
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleRegister() async {
    // Track button click
    await _analyticsModule?.trackButtonClick('register_button', screenName: 'account_screen');
    
    if (!_registerFormKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      final result = await _loginModule!.registerUser(
        context: context,
        username: _usernameController.text.trim(),
        email: _registerEmailController.text.trim(),
        password: _registerPasswordController.text,
        guestEmail: _isConvertingGuest ? _guestEmail : null,
        guestPassword: _isConvertingGuest ? _guestPassword : null,
      );
      
      if (result['success'] != null) {
        // Track successful registration
        await _analyticsModule?.trackEvent(
          eventType: 'user_registered',
          eventData: {
            'registration_type': 'email',
            'screen_name': 'account_screen',
            'converted_from_guest': _isConvertingGuest,
          },
        );
        
        // If guest account conversion was successful, update guest account status and log out
        if (_isConvertingGuest) {
          await _checkGuestAccountStatus();
          
          // Log out the guest account session after successful conversion
          // Guest credentials are already cleared in registerUser(), so logout will work normally
          if (LOGGING_SWITCH) {
            _logger.info("AccountScreen: Guest account conversion successful, logging out guest session");
          }
          try {
            final logoutResult = await _loginModule!.logoutUser(context);
            if (logoutResult['success'] != null) {
              if (LOGGING_SWITCH) {
                _logger.info("AccountScreen: Guest session logged out successfully after conversion");
              }
            } else {
              if (LOGGING_SWITCH) {
                _logger.warning("AccountScreen: Logout after conversion returned error: ${logoutResult['error']}");
              }
            }
          } catch (e) {
            if (LOGGING_SWITCH) {
              _logger.error("AccountScreen: Error during logout after guest conversion", error: e);
            }
          }
        }
        
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // If showing registration form while logged in (conversion), hide it after success
        if (_showRegistrationForm) {
          Future.delayed(const Duration(seconds: 2), () {
            setState(() {
              _showRegistrationForm = false;
              _isConvertingGuest = false;
              _isLoginMode = true; // Show login form after conversion
              _clearForms();
              _clearMessages();
            });
          });
        } else {
          // Switch to login mode after successful registration (normal flow)
          Future.delayed(const Duration(seconds: 2), () {
            setState(() {
              _isLoginMode = true;
              _clearForms();
              _clearMessages();
            });
          });
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('AccountScreen: Register failed - result: $result');
        }
        setState(() {
          _errorMessage = result['error'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Register exception', error: e);
      }
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  /// Check if guest credentials exist (temp key username)
  Future<bool> _hasGuestCredentials() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final username = sharedPref.getString('username');
      
      return isGuestAccount && username != null && username.isNotEmpty;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking for guest credentials', error: e);
      }
      return false;
    }
  }
  
  /// Handle guest login using preserved credentials (temp keys)
  Future<void> _handleGuestLogin() async {
    if (LOGGING_SWITCH) {
      _logger.info("AccountScreen: Guest login button pressed");
    }
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final username = sharedPref.getString('username');
      final email = sharedPref.getString('email');
      
      if (username == null || username.isEmpty) {
        setState(() {
          _errorMessage = 'No guest account found. Please register as guest first.';
          _isLoading = false;
        });
        return;
      }
      
      final guestEmail = (email != null && email.isNotEmpty)
          ? email
          : 'guest_$username@guest.local';
      
      if (LOGGING_SWITCH) {
        _logger.info("AccountScreen: Logging in with guest credentials (temp keys) - Username: $username");
      }
      
      final result = await _loginResolvingSessionConflict(
        email: guestEmail,
        password: username,
      );

      if (result['cancelled'] == true) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      
      if (result['success'] != null) {
        if (LOGGING_SWITCH) {
          _logger.info("AccountScreen: Guest login successful");
        }
        setState(() {
          _successMessage = 'Welcome back, $username!';
          _isLoading = false;
        });
        
        // Stay on account screen after successful login.
      } else {
        if (LOGGING_SWITCH) {
          _logger.error("AccountScreen: Guest login failed - Error: ${result['error']}");
        }
        setState(() {
          _errorMessage = result['error'] ?? 'Login failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error("AccountScreen: Exception during guest login", error: e);
      }
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleGuestRegister() async {
    if (LOGGING_SWITCH) {
      _logger.info("AccountScreen: Guest registration button pressed");
    }
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      if (LOGGING_SWITCH) {
        _logger.debug("AccountScreen: Calling registerGuestUser");
      }
      final result = await _loginModule!.registerGuestUser(
        context: context,
      );
      
      if (result['success'] != null) {
        final username = result['username']?.toString() ?? '';
        if (LOGGING_SWITCH) {
          _logger.info("AccountScreen: Guest registration successful - Username: $username");
        }
        
        setState(() {
          _successMessage = 'Guest account created! Your username is: $username\n\nYour credentials are saved. You can log in again even after closing the app.';
          _isLoading = false;
        });
        
        // If auto-login was successful, remain on account screen.
        if (result['success'].toString().contains('logged in')) {
          if (LOGGING_SWITCH) {
            _logger.info("AccountScreen: Auto-login successful, staying on account screen");
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info("AccountScreen: Auto-login not successful, switching to login mode");
          }
          // Switch to login mode after successful registration
          Future.delayed(const Duration(seconds: 3), () {
            setState(() {
              _isLoginMode = true;
              _clearForms();
              _clearMessages();
            });
          });
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.error("AccountScreen: Guest registration failed - Error: ${result['error']}");
        }
        setState(() {
          _errorMessage = result['error'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error("AccountScreen: Exception during guest registration", error: e);
      }
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleLogout() async {
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      final result = await _loginModule!.logoutUser(context);
      
      if (result['success'] != null) {
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // Stay on account screen after successful logout.
      } else {
        setState(() {
          _errorMessage = result['error'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  /// Format role for display (e.g. "player" -> "Player", "admin" -> "Admin").
  String _formatRole(String role) {
    if (role.isEmpty) return 'Player';
    return role.substring(0, 1).toUpperCase() + role.substring(1).toLowerCase();
  }

  /// True when [role] is "admin" (case-insensitive).
  bool _isAdminRole(dynamic role) {
    if (role == null) return false;
    return (role.toString().trim().toLowerCase()) == 'admin';
  }

  /// Navigate to Admin Dashboard only if current user role is still admin.
  void _onAdminDashboardPressed() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login');
    final isLoggedIn = loginState?['isLoggedIn'] == true;
    if (!isLoggedIn || !_isAdminRole(loginState?['role'])) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Admin access required.',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    NavigationManager().navigateTo('/admin/dashboard');
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium().copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _pickAndUploadProfilePhoto() async {
    if (_loginModule == null || !mounted) return;
    if (LOGGING_SWITCH) {
      _logger.info('AccountScreen: _pickAndUploadProfilePhoto started');
    }
    setState(() => _uploadingProfilePhoto = true);
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
        // Avoid extra metadata queries that can pull in stricter permission paths (Play photo policy).
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) {
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: _pickAndUploadProfilePhoto cancelled (no image picked)');
        }
        return;
      }

      final raw = await picked.readAsBytes();
      if (LOGGING_SWITCH) {
        _logger.info(
          'AccountScreen: picked image path=${picked.path} raw_bytes=${raw.length}',
        );
      }
      if (raw.length > kProfileAvatarMaxUploadBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Photo must be 5 MB or smaller.',
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
              ),
              backgroundColor: AppColors.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final prepared = prepareProfilePhotoForUpload(Uint8List.fromList(raw));
      if (LOGGING_SWITCH && prepared != null) {
        _logger.info('AccountScreen: prepared JPEG for upload bytes=${prepared.length}');
      }
      if (prepared == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('AccountScreen: prepareProfilePhotoForUpload returned null');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not read that image. Try JPG or PNG.',
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
              ),
              backgroundColor: AppColors.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (prepared.length > kProfileAvatarMaxUploadBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Compressed image is still too large. Try a smaller photo.',
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
              ),
              backgroundColor: AppColors.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final result = await _loginModule!.uploadProfileAvatar(
        bytes: prepared,
        filename: 'profile.jpg',
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;

      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: upload result success=${result['success']} keys=${result.keys.toList()}');
      }
      if (result['success'] == true) {
        // Keep a local in-memory preview so the profile UI can show the new
        // image immediately even if network fetch is delayed/fails/cached.
        _recentUploadedProfilePhotoBytes = Uint8List.fromList(prepared);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile photo updated',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      } else {
        final msg = (result['message'] ?? result['error'] ?? 'Upload failed').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: _pickAndUploadProfilePhoto error: $e', error: e);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update photo: $e',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePhoto = false);
      }
    }
  }

  /// Profile header used by the logged-in view: themed avatar + welcome title +
  /// "Change photo" affordance. Uses `DutchAvatar` so the same component can be
  /// reused for opponents/leaderboard rows in the future.
  Widget _buildProfileHeader({
    required String username,
    required String email,
  }) {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>("login") ?? {};
    final profilePictureUrl = (loginState["profilePicture"] as String?)?.trim();
    final profile = loginState["profile"] as Map<String, dynamic>? ?? const {};
    final avatarVersion = (profile["updated_at"]?.toString() ??
            loginState["profile_updated_at"]?.toString() ??
            '')
        .trim();
    final effectivePictureUrl = (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
        ? (avatarVersion.isNotEmpty
            ? '$profilePictureUrl${profilePictureUrl.contains('?') ? '&' : '?'}v=${Uri.encodeQueryComponent(avatarVersion)}'
            : profilePictureUrl)
        : null;
    final displayName = username.isNotEmpty ? username : email;
    if (LOGGING_SWITCH) {
      _logger.info(
        'AccountScreen: _buildProfileHeader displayName="$displayName" '
        'profilePictureUrl="${profilePictureUrl ?? "(null)"}" '
        'effectivePictureUrl="${effectivePictureUrl ?? "(null)"}" '
        'hasLocalBytes=${_recentUploadedProfilePhotoBytes != null && _recentUploadedProfilePhotoBytes!.isNotEmpty} '
        'uploading=$_uploadingProfilePhoto',
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              DutchAvatar(
                displayName: displayName.isNotEmpty ? displayName : 'Player',
                imageBytes: _recentUploadedProfilePhotoBytes,
                imageUrl: effectivePictureUrl,
                size: 96,
                semanticIdentifier: 'profile_avatar',
                onTap: _uploadingProfilePhoto ? null : _pickAndUploadProfilePhoto,
              ),
              if (_uploadingProfilePhoto)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Change profile photo',
            identifier: 'profile_photo_change',
            button: true,
            child: TextButton.icon(
              onPressed: _uploadingProfilePhoto ? null : _pickAndUploadProfilePhoto,
              icon: Icon(
                Icons.photo_camera_outlined,
                color: AppColors.accentColor2,
                size: 18,
              ),
              label: Text(
                'Change photo',
                style: AppTextStyles.bodyMedium(color: AppColors.accentColor2),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome back!',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingLarge(color: AppColors.white)
                .copyWith(letterSpacing: 0.3),
          ),
          const SizedBox(height: 4),
          Text(
            displayName.isNotEmpty ? displayName : 'Player',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGameStatisticsCard() {
    // Get user stats from dutch_game state
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
    
    // If no stats available, show empty state or fetch button
    if (userStats == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.cardVariant,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game Statistics',
              style: AppTextStyles.headingMedium(),
            ),
            const SizedBox(height: 16),
            Text(
              'Statistics not available. Play a game to see your stats!',
              style: AppTextStyles.bodyMedium().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : () async {
                setState(() {
                  _isLoading = true;
                });
                await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
                setState(() {
                  _isLoading = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Stats'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // Extract stats with defaults
    final wins = userStats['wins'] as int? ?? 0;
    final losses = userStats['losses'] as int? ?? 0;
    final totalMatches = userStats['total_matches'] as int? ?? 0;
    final points = userStats['points'] as int? ?? 0;
    final coins = userStats['coins'] as int? ?? 0;
    final level = userStats['level'] as int? ?? 1;
    final rank = userStats['rank'] as String? ?? 'beginner';
    final winRate = userStats['win_rate'] as double? ?? 0.0;
    final subscriptionTier = userStats['subscription_tier'] as String? ?? 'promotional';
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardVariant,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Game Statistics',
                style: AppTextStyles.headingMedium(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : () async {
                  setState(() {
                    _isLoading = true;
                  });
                  await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
                  setState(() {
                    _isLoading = false;
                  });
                },
                tooltip: 'Refresh Stats',
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Wins', wins.toString(), Icons.emoji_events, AppColors.successColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem('Losses', losses.toString(), Icons.trending_down, AppColors.errorColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Total Matches', totalMatches.toString(), Icons.games, AppColors.infoColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem('Win Rate', '${(winRate * 100).toStringAsFixed(1)}%', Icons.percent, AppColors.accentColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Coins', coins.toString(), Icons.monetization_on, AppColors.warningColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem('Points', points.toString(), Icons.stars, AppColors.accentColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Level', level.toString(), Icons.trending_up, AppColors.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem('Rank', rank.toUpperCase(), Icons.military_tech, AppColors.accentColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Subscription Tier', subscriptionTier.toUpperCase()),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.label().copyWith(
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headingSmall().copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget buildContent(BuildContext context) {
    if (LOGGING_SWITCH) {
      _logger.info('🔍 AccountScreen buildContent called');
    }
    // Use AnimatedBuilder to listen to StateManager changes
    return AnimatedBuilder(
      animation: StateManager(),
      builder: (context, child) {
        try {
          // Get login state from StateManager
          final stateManager = StateManager();
          final loginState = stateManager.getModuleState("login");
          final isLoggedIn = loginState?["isLoggedIn"] ?? false;
          // Prefer plain email/username: DB may store encrypted (det_...); never show encrypted to user
          final rawUsername = loginState?["username"] ?? "";
          final rawEmail = loginState?["email"] ?? "";
          final sharedPref = SharedPrefManager();
          String username = rawUsername.startsWith("det_")
              ? (sharedPref.getString("username") ?? rawUsername)
              : rawUsername;
          String email = rawEmail.startsWith("det_")
              ? (sharedPref.getString("email") ?? rawEmail)
              : rawEmail;
          if (username.startsWith("det_")) username = "";
          if (email.startsWith("det_")) email = "";
          
          // Update guest account status only when login state actually changes (prevents rebuild loop)
          if (isLoggedIn != _lastLoggedInState) {
            _lastLoggedInState = isLoggedIn;
            if (isLoggedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _checkGuestAccountStatus();
                  _fetchUserProfile(); // Fetch profile when user logs in
                } catch (e, stackTrace) {
                  if (LOGGING_SWITCH) {
                    _logger.error('AccountScreen: Error in postFrameCallback for guest account check', error: e, stackTrace: stackTrace);
                  }
                }
              });
            } else {
              // Just switched to logged-out: repopulate login form from SharedPref so saved creds show immediately
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await _checkForGuestCredentials();
              });
            }
          }
          
          if (LOGGING_SWITCH) {
            _logger.info('🔍 AccountScreen - isLoggedIn: $isLoggedIn, username: $username, isGuestAccount: $_isGuestAccount, showRegistrationForm: $_showRegistrationForm');
          }
          
          // If user is logged in and not showing registration form, show user profile
          if (isLoggedIn && !_showRegistrationForm) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SafeArea(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _fetchUserProfile();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),

                  // Profile header (avatar + name + change-photo affordance)
                  _buildProfileHeader(
                    username: username,
                    email: email,
                  ),

                  const SizedBox(height: 24),

                  // Account Information — themed settings rows from the Dutch UI kit.
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.accentContrast.withValues(alpha: 0.35),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DutchSectionHeader(
                          title: 'Account Information',
                          icon: Icons.person_outline,
                          semanticIdentifier: 'account_info_header',
                        ),
                        const SizedBox(height: 8),
                        DutchSettingsRow(
                          title: 'Username',
                          subtitle: username.isNotEmpty ? username : null,
                          leadingIcon: Icons.badge_outlined,
                          semanticIdentifier: 'account_row_username',
                        ),
                        const SizedBox(height: 8),
                        DutchSettingsRow(
                          title: 'Email',
                          subtitle: email.isNotEmpty ? email : null,
                          leadingIcon: Icons.email_outlined,
                          semanticIdentifier: 'account_row_email',
                        ),
                        const SizedBox(height: 8),
                        DutchSettingsRow(
                          title: 'User ID',
                          subtitle: (loginState?["userId"] ?? "").toString().isNotEmpty
                              ? (loginState!["userId"]).toString()
                              : null,
                          leadingIcon: Icons.fingerprint,
                          semanticIdentifier: 'account_row_user_id',
                        ),
                        const SizedBox(height: 8),
                        DutchSettingsRow(
                          title: 'Role',
                          subtitle: _formatRole(loginState?["role"] ?? "player"),
                          leadingIcon: Icons.shield_outlined,
                          semanticIdentifier: 'account_row_role',
                        ),
                        if (_isAdminRole(loginState?["role"])) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _onAdminDashboardPressed,
                            icon: Icon(Icons.admin_panel_settings, size: 20, color: AppColors.accentColor),
                            label: Text(
                              'Admin Dashboard',
                              style: AppTextStyles.bodyMedium().copyWith(
                                color: AppColors.accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentColor,
                              side: BorderSide(color: AppColors.accentColor),
                              padding: EdgeInsets.symmetric(
                                vertical: AppPadding.mediumPadding.top,
                                horizontal: AppPadding.defaultPadding.left,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppBorderRadius.large),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Game Statistics Card
                  _buildGameStatisticsCard(),
                  
                  const SizedBox(height: 24),
                  
                  // Convert Guest Account Section (if guest account)
                  if (_isGuestAccount)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.infoColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.infoColor.withValues(alpha: 0.3)),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.infoColor, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Guest Account',
                                  style: AppTextStyles.headingMedium().copyWith(
                                    color: AppColors.infoColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'You are currently using a guest account. Convert to a full account to keep your progress and access all features.',
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: AppColors.infoColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : () async {
                              if (LOGGING_SWITCH) {
                                _logger.info('AccountScreen: Convert to Full Account button pressed');
                              }
                              await _checkForGuestAccountForConversion();
                              setState(() {
                                _isLoginMode = false; // Switch to registration mode
                                _showRegistrationForm = true; // Show registration form even when logged in
                                _clearForms(); // Keep new account fields empty during guest conversion
                              });
                              if (LOGGING_SWITCH) {
                                _logger.info('AccountScreen: Switched to registration mode, showRegistrationForm: $_showRegistrationForm');
                              }
                            },
                            icon: const Icon(Icons.person_add),
                            label: const Text('Convert to Full Account'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.infoColor,
                              foregroundColor: AppColors.textOnAccent,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Logout Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorColor,
                      foregroundColor: AppColors.textOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
              child: _isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnAccent),
                    ),
                  )
                : Text(
                    'Logout',
                    style: AppTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ),
                  
                  // Messages
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.errorColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.errorColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTextStyles.errorText(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (_successMessage != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: AppColors.successColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: AppTextStyles.successText(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  _buildClearStorageSection(),
                ],
                    ),
                  ),
                ),
                ),
              ),
            );
          }
        
        // If user is not logged in, or showing registration form while logged in, show login/register forms
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back button (if showing registration form while logged in)
                    if (isLoggedIn && _showRegistrationForm)
                      Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _showRegistrationForm = false;
                      _isConvertingGuest = false;
                      _clearForms();
                      _clearMessages();
                    });
                  },
                  tooltip: 'Back to Profile',
                ),
              ),
            
            const SizedBox(height: 40),
            
            // App Logo/Title
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 80,
                    color: AppColors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isLoginMode ? 'Welcome Back' : 'Create Account',
                    style: AppTextStyles.headingLarge().copyWith(
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoginMode 
                      ? 'Sign in to your account' 
                      : 'Join our community',
                    style: AppTextStyles.bodyLarge().copyWith(
                      color: AppColors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Mode Toggle — deep plum track; active = full light plum, inactive = low-opacity plum.
            Container(
              decoration: BoxDecoration(
                color: AppColors.scaffoldDeepPlumColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardVariant,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isLoginMode = true;
                        _clearMessages();
                        _clearForms();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _isLoginMode
                              ? AppColors.accentContrast
                              : AppColors.accentContrast.withValues(alpha: 0.28),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Login',
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: _isLoginMode
                                  ? AppColors.white
                                  : AppColors.white.withValues(alpha: 0.45),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isLoginMode = false;
                        _clearMessages();
                        _clearForms();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: !_isLoginMode
                              ? AppColors.accentContrast
                              : AppColors.accentContrast.withValues(alpha: 0.28),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Register',
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: !_isLoginMode
                                  ? AppColors.white
                                  : AppColors.white.withValues(alpha: 0.45),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Forms
            Container(
              decoration: BoxDecoration(
                color: AppColors.accentContrast,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardVariant,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: _isLoginMode ? _buildLoginForm() : _buildRegisterForm(),
            ),
            
            const SizedBox(height: 24),
            
            // Messages
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.errorColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.errorColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: AppTextStyles.errorText(),
                      ),
                    ),
                  ],
                ),
              ),
            
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: AppColors.successColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: AppTextStyles.successText(),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 24),

            // Action Button
            Semantics(
              label: 'account_submit',
              identifier: 'account_submit',
              button: true,
              child: ElevatedButton(
              onPressed: _isLoading ? null : () {
                if (LOGGING_SWITCH) {
                  _logger.info('AccountScreen: Main action button pressed - mode: ${_isLoginMode ? "login" : "register"}');
                }
                try {
                  if (_isLoginMode) {
                    _handleLogin();
                  } else {
                    _handleRegister();
                  }
                } catch (e, stackTrace) {
                  if (LOGGING_SWITCH) {
                    _logger.error('AccountScreen: Error in main action button handler', error: e, stackTrace: stackTrace);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.scaffoldDeepPlumColor,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Text(
                    _isLoginMode ? 'Sign In' : 'Create Account',
                    style: AppTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
            ),
            ),
            
            const SizedBox(height: 16),
            
            // Guest Registration Button (only show in register mode)
            if (!_isLoginMode)
              Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : () {
                      if (LOGGING_SWITCH) {
                        _logger.info('AccountScreen: Guest Registration button pressed');
                      }
                      try {
                        _handleGuestRegister();
                      } catch (e, stackTrace) {
                        if (LOGGING_SWITCH) {
                          _logger.error('AccountScreen: Error in guest registration button handler', error: e, stackTrace: stackTrace);
                        }
                      }
                    },
                    icon: Icon(Icons.person_outline, color: AppColors.white.withValues(alpha: 0.92)),
                    label: Text(
                      'Continue as Guest',
                      style: AppTextStyles.bodyMedium(color: AppColors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: AppColors.white.withValues(alpha: 0.55)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No email or password required',
                    style: AppTextStyles.bodySmall().copyWith(
                      color: AppColors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            
            // Guest Login Button (only show in login mode if guest credentials exist)
            if (_isLoginMode)
              FutureBuilder<bool>(
                future: _hasGuestCredentials(),
                builder: (context, snapshot) {
                  try {
                    if (LOGGING_SWITCH) {
                      _logger.debug('AccountScreen: Guest credentials check - hasData: ${snapshot.hasData}, data: ${snapshot.data}, error: ${snapshot.error}');
                    }
                    
                    if (snapshot.hasError) {
                      if (LOGGING_SWITCH) {
                        _logger.error('AccountScreen: Error checking guest credentials', error: snapshot.error);
                      }
                      return const SizedBox.shrink(); // Return empty widget on error
                    }
                    
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          const Divider(),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : () {
                              if (LOGGING_SWITCH) {
                                _logger.info('AccountScreen: Guest Login button pressed');
                              }
                              try {
                                _handleGuestLogin();
                              } catch (e, stackTrace) {
                                if (LOGGING_SWITCH) {
                                  _logger.error('AccountScreen: Error in guest login button handler', error: e, stackTrace: stackTrace);
                                }
                              }
                            },
                            icon: Icon(Icons.person_outline, color: AppColors.white.withValues(alpha: 0.92)),
                            label: Text(
                              'Continue as Guest',
                              style: AppTextStyles.bodyMedium(color: AppColors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.white,
                              backgroundColor: Colors.transparent,
                              side: BorderSide(color: AppColors.white.withValues(alpha: 0.55)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use your saved guest account',
                            style: AppTextStyles.bodySmall().copyWith(
                              color: AppColors.white.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  } catch (e, stackTrace) {
                    if (LOGGING_SWITCH) {
                      _logger.error('AccountScreen: Error in FutureBuilder builder for guest credentials', error: e, stackTrace: stackTrace);
                    }
                    return const SizedBox.shrink(); // Return empty widget on error
                  }
                },
              ),
            
            // Mode Switch
            TextButton(
              onPressed: _isLoading ? null : () {
                if (LOGGING_SWITCH) {
                  _logger.info('AccountScreen: Mode switch button pressed - current mode: ${_isLoginMode ? "login" : "register"}');
                }
                try {
                  _toggleMode();
                } catch (e, stackTrace) {
                  if (LOGGING_SWITCH) {
                    _logger.error('AccountScreen: Error in mode switch button handler', error: e, stackTrace: stackTrace);
                  }
                }
              },
              child: Text(
                _isLoginMode 
                  ? "Don't have an account? Sign up" 
                  : "Already have an account? Sign in",
                style: AppTextStyles.bodyMedium().copyWith(
                  color: AppColors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            
            _buildClearStorageSection(),
                  ],
                ),
              ),
            ),
          ),
        );
        } catch (e, stackTrace) {
          if (LOGGING_SWITCH) {
            _logger.error('AccountScreen: Error in AnimatedBuilder builder', error: e, stackTrace: stackTrace);
          }
          // Return a safe fallback widget to prevent red screen
          return SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: AppColors.errorColor, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading account screen',
                    style: AppTextStyles.headingMedium().copyWith(
                      color: AppColors.errorColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please try again',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
  
  /// Input fields on login/register panels (app bar plum + deeper plum fills).
  InputDecoration _accountAuthFieldDecoration({
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    Color? fillColor,
  }) {
    final radius = BorderRadius.circular(AppBorderRadius.large);
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.bodyMedium().copyWith(
        color: AppColors.white.withValues(alpha: 0.62),
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fillColor ?? AppColors.scaffoldDeepPlumColor,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppPadding.defaultPadding.left,
        vertical: AppPadding.mediumPadding.top,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.92)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.38)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.92), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.errorColor, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.22)),
      ),
    );
  }

  /// Section: button to clear all user data from app storage + explanatory note.
  Widget _buildClearStorageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : () async {
            await _handleClearAllUserDataFromStorage();
          },
          icon: Icon(Icons.delete_outline, size: 20, color: AppColors.textOnPrimary),
          label: Text(
            'Clear all user data from this device',
            style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textOnPrimary,
            side: BorderSide(color: AppColors.borderDefault),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Clears SharedPreferences session data and JWT tokens in secure storage. '
            'Does not delete your user account on the server.',
            style: AppTextStyles.bodySmall().copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Login form: email/password for email accounts.
  /// Email and password are stored in SharedPref for pre-fill after logout.
  Widget _buildLoginForm() {
    final fieldStyle = AppTextStyles.bodyMedium().copyWith(color: AppColors.white);
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email Field
          Text(
            'Email',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          Semantics(
            label: 'account_email',
            identifier: 'account_email',
            container: true,
            explicitChildNodes: true,
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              cursorColor: AppColors.white,
              style: fieldStyle,
              decoration: _accountAuthFieldDecoration(
                hintText: 'Enter your email',
                prefixIcon: Icon(Icons.email_outlined, color: AppColors.white.withValues(alpha: 0.85)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                    .hasMatch(value)) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
          ),
          SizedBox(height: AppPadding.defaultPadding.top),
          // Password Field
          Text(
            'Password',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          Semantics(
            label: 'account_password',
            identifier: 'account_password',
            container: true,
            explicitChildNodes: true,
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              cursorColor: AppColors.white,
              style: fieldStyle,
              decoration: _accountAuthFieldDecoration(
                hintText: 'Enter your password',
                prefixIcon: Icon(Icons.lock_outlined, color: AppColors.white.withValues(alpha: 0.85)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.white.withValues(alpha: 0.85),
                  ),
                  onPressed: _togglePasswordVisibility,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRegisterForm() {
    final fieldStyle = AppTextStyles.bodyMedium().copyWith(color: AppColors.white);
    final guestReadStyle = AppTextStyles.bodyMedium().copyWith(
      color: AppColors.white.withValues(alpha: 0.78),
    );
    return Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Guest Account Conversion Info (if converting)
          if (_isConvertingGuest) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.infoColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.infoColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.infoColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Converting Guest Account',
                        style: AppTextStyles.headingSmall().copyWith(
                          color: AppColors.infoColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your game progress and data will be preserved.',
                    style: AppTextStyles.infoText(),
                  ),
                ],
              ),
            ),
            // Guest Email (read-only)
            Text(
              'Guest Email',
              style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            TextFormField(
              initialValue: _guestEmail,
              readOnly: true,
              enabled: false,
              style: guestReadStyle,
              decoration: _accountAuthFieldDecoration(
                hintText: 'Your guest account email',
                prefixIcon: Icon(Icons.email_outlined, color: AppColors.white.withValues(alpha: 0.55)),
                fillColor: AppColors.scaffoldBackgroundColor,
              ),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            // Guest Password (read-only, obscured)
            Text(
              'Guest Password',
              style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            TextFormField(
              initialValue: _guestPassword,
              readOnly: true,
              enabled: false,
              obscureText: true,
              style: guestReadStyle,
              decoration: _accountAuthFieldDecoration(
                hintText: 'Your guest account password',
                prefixIcon: Icon(Icons.lock_outlined, color: AppColors.white.withValues(alpha: 0.55)),
                fillColor: AppColors.scaffoldBackgroundColor,
              ),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            // Divider
            Divider(color: AppColors.white.withValues(alpha: 0.22)),
            SizedBox(height: AppPadding.defaultPadding.top),
          ],
          // Username Field
          Text(
            'Username',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          TextFormField(
            controller: _usernameController,
            cursorColor: AppColors.white,
            style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            decoration: _accountAuthFieldDecoration(
              hintText: 'Choose a username',
              prefixIcon: Icon(Icons.person_outlined, color: AppColors.white.withValues(alpha: 0.85)),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a username';
              }
              if (value.length < 3) {
                return 'Username must be at least 3 characters long';
              }
              if (value.length > 20) {
                return 'Username cannot be longer than 20 characters';
              }
              if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$').hasMatch(value)) {
                return 'Username can only contain letters, numbers, underscores, and hyphens';
              }
              if (RegExp(r'[-_]{2,}').hasMatch(value)) {
                return 'Username cannot contain consecutive special characters';
              }
              if (value.startsWith('_') || value.startsWith('-') || 
                  value.endsWith('_') || value.endsWith('-')) {
                return 'Username cannot start or end with special characters';
              }
              return null;
            },
          ),
          SizedBox(height: AppPadding.defaultPadding.top),
          // Email Field
          Text(
            'Email',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          TextFormField(
            controller: _registerEmailController,
            keyboardType: TextInputType.emailAddress,
            cursorColor: AppColors.white,
            style: fieldStyle,
            decoration: _accountAuthFieldDecoration(
              hintText: 'Enter your email',
              prefixIcon: Icon(Icons.email_outlined, color: AppColors.white.withValues(alpha: 0.85)),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                  .hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          SizedBox(height: AppPadding.defaultPadding.top),
          // Password Field
          Text(
            'Password',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          TextFormField(
            controller: _registerPasswordController,
            obscureText: _obscurePassword,
            cursorColor: AppColors.white,
            style: fieldStyle,
            decoration: _accountAuthFieldDecoration(
              hintText: 'Create a password',
              prefixIcon: Icon(Icons.lock_outlined, color: AppColors.white.withValues(alpha: 0.85)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.white.withValues(alpha: 0.85),
                ),
                onPressed: _togglePasswordVisibility,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a password';
              }
              if (value.length < 8) {
                return 'Password must be at least 8 characters long';
              }
              return null;
            },
          ),
          SizedBox(height: AppPadding.defaultPadding.top),
          // Confirm Password Field
          Text(
            'Confirm Password',
            style: AppTextStyles.label().copyWith(color: AppColors.white.withValues(alpha: 0.92)),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            cursorColor: AppColors.white,
            style: fieldStyle,
            decoration: _accountAuthFieldDecoration(
              hintText: 'Confirm your password',
              prefixIcon: Icon(Icons.lock_outlined, color: AppColors.white.withValues(alpha: 0.85)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.white.withValues(alpha: 0.85),
                ),
                onPressed: _toggleConfirmPasswordVisibility,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _registerPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
} 