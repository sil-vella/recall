import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../modules/login_module/login_module.dart';
import '../../modules/analytics_module/analytics_module.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../core/services/shared_preferences.dart';
import '../../core/services/version_check_service.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/theme_consts.dart';

class AccountScreen extends BaseScreen {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AccountScreen> createState() => _AccountScreenState();

  @override
  String computeTitle(BuildContext context) => 'Account';
}

class _AccountScreenState extends BaseScreenState<AccountScreen> {
  static const bool LOGGING_SWITCH = false; // Enable for debugging guest account creation and game creation loops
  static final Logger _logger = Logger();
  
  // Form controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
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
    _checkForGuestCredentials();
    _checkGuestAccountStatus();
    _trackScreenView();
    _fetchUserProfile();
    // Check for app updates on every account screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdates();
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
  
  /// Check for app updates - runs on every account screen load
  /// This ensures users get update notifications even after skipping
  Future<void> _checkForAppUpdates() async {
    // Skip version check on web - web apps update automatically
    if (kIsWeb) {
      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Skipping version check on web platform');
      }
      return;
    }
    
    try {
      if (LOGGING_SWITCH) {
        _logger.info('AccountScreen: Starting version check');
      }
      
      // Get ConnectionsApiModule
      final apiModule = _moduleManager.getModuleByType<ConnectionsApiModule>();
      
      if (apiModule == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('AccountScreen: ConnectionsApiModule not available for version check');
        }
        return;
      }
      
      // Initialize VersionCheckService if needed
      final versionCheckService = VersionCheckService();
      if (!versionCheckService.isInitialized) {
        await versionCheckService.initialize();
      }
      
      // Check for updates
      final result = await versionCheckService.checkForUpdates(apiModule);
      
      if (result['success'] == true) {
        final updateAvailable = result['update_available'] == true;
        final updateRequired = result['update_required'] == true;
        final currentVersion = result['current_version'];
        final serverVersion = result['server_version'];
        final downloadLink = result['download_link']?.toString() ?? '';
        
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: Version check completed - Current: $currentVersion, Server: $serverVersion, Update Available: $updateAvailable, Update Required: $updateRequired');
        }
        
        // If update is required, navigate to update screen
        if (updateRequired && downloadLink.isNotEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('AccountScreen: Update required - navigating to update screen');
          }
          
          // Wait a moment to ensure context is ready
          await Future.delayed(const Duration(milliseconds: 300));
          
          if (!mounted) return;
          
          // Navigate to update screen with download link as parameter
          final navigationManager = NavigationManager();
          final router = navigationManager.router;
          final updateRoute = '/update-required?download_link=${Uri.encodeComponent(downloadLink)}';
          router.go(updateRoute);
          if (LOGGING_SWITCH) {
            _logger.info('AccountScreen: Navigated to update screen');
          }
        } else if (updateAvailable && !updateRequired) {
          if (LOGGING_SWITCH) {
            _logger.info('AccountScreen: Optional update available (not required)');
          }
          // Optional updates can be shown as a non-blocking notification if desired
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('AccountScreen: Version check failed: ${result['error']}');
        }
      }
      
    } catch (e) {
      // Don't let version check errors affect account screen
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error during version check: $e');
      }
    }
  }
  
  /// Check for preserved guest credentials and auto-populate login form
  Future<void> _checkForGuestCredentials() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final guestUsername = sharedPref.getString('guest_username');
      
      if (isGuestAccount && guestUsername != null) {
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: Found preserved guest credentials - Username: $guestUsername');
        }
        
        // Auto-populate login form with guest credentials
        // Email: guest_{username}@guest.local, Password: {username}
        final guestEmailFull = 'guest_$guestUsername@guest.local';
        _emailController.text = guestEmailFull;
        _passwordController.text = guestUsername; // Password is same as username
        
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: Auto-populated login form with guest credentials');
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking for guest credentials', error: e);
      }
    }
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
  
  /// Check for guest account when in registration mode
  Future<void> _checkForGuestAccountForConversion() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final guestUsername = sharedPref.getString('guest_username');
      final guestEmail = sharedPref.getString('guest_email');
      
      if (isGuestAccount && guestUsername != null && guestEmail != null) {
        setState(() {
          _isConvertingGuest = true;
          _guestEmail = guestEmail;
          _guestPassword = guestUsername; // Password is same as username for guest accounts
        });
        if (LOGGING_SWITCH) {
          _logger.info('AccountScreen: Guest account detected for conversion - Email: $guestEmail');
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
    _emailController.clear();
    _passwordController.clear();
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
      final result = await _loginModule!.loginUser(
        context: context,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (result['success'] != null) {
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // Navigate to main screen after successful login
        Future.delayed(const Duration(seconds: 2), () {
          context.go('/');
        });
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
  
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    // Check for guest account conversion before Google Sign-In
    await _checkForGuestAccountForConversion();
    
    try {
      final result = await _loginModule!.signInWithGoogle(
        context: context,
        guestEmail: _isConvertingGuest ? _guestEmail : null,
        guestPassword: _isConvertingGuest ? _guestPassword : null,
      );
      
      if (result['success'] != null) {
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // Track successful Google Sign-In
        await _analyticsModule?.trackEvent(
          eventType: 'google_sign_in',
          eventData: {
            'auth_method': 'google',
            'screen_name': 'account_screen',
            'converted_from_guest': _isConvertingGuest,
          },
        );
        
        // Navigate to main screen after successful login
        Future.delayed(const Duration(seconds: 2), () {
          context.go('/');
        });
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
        email: _emailController.text.trim(),
        password: _passwordController.text,
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
  
  /// Check if guest credentials exist in SharedPreferences
  Future<bool> _hasGuestCredentials() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final guestUsername = sharedPref.getString('guest_username');
      
      return isGuestAccount && guestUsername != null;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('AccountScreen: Error checking for guest credentials', error: e);
      }
      return false;
    }
  }
  
  /// Handle guest login using preserved credentials
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
      
      final guestUsername = sharedPref.getString('guest_username');
      
      if (guestUsername == null) {
        setState(() {
          _errorMessage = 'No guest account found. Please register as guest first.';
          _isLoading = false;
        });
        return;
      }
      
      // Guest email format: guest_{username}@guest.local
      // Guest password: {username} (same as username)
      final guestEmail = 'guest_$guestUsername@guest.local';
      
      if (LOGGING_SWITCH) {
        _logger.info("AccountScreen: Logging in with guest credentials - Username: $guestUsername");
      }
      
      final result = await _loginModule!.loginUser(
        context: context,
        email: guestEmail,
        password: guestUsername,
      );
      
      if (result['success'] != null) {
        if (LOGGING_SWITCH) {
          _logger.info("AccountScreen: Guest login successful");
        }
        setState(() {
          _successMessage = 'Welcome back, $guestUsername!';
          _isLoading = false;
        });
        
        // Navigate to main screen after successful login
        Future.delayed(const Duration(seconds: 2), () {
          context.go('/');
        });
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
        
        // If auto-login was successful, navigate to main screen
        if (result['success'].toString().contains('logged in')) {
          if (LOGGING_SWITCH) {
            _logger.info("AccountScreen: Auto-login successful, navigating to main screen");
          }
          Future.delayed(const Duration(seconds: 3), () {
            context.go('/');
          });
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
        
        // Navigate to main screen after successful logout
        Future.delayed(const Duration(seconds: 2), () {
          context.go('/');
        });
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
  
  /// Build profile picture widget with fallback to icon
  /// Reads profile picture from StateManager
  Widget _buildProfilePicture() {
    final stateManager = StateManager();
    final loginState = stateManager.getModuleState<Map<String, dynamic>>("login") ?? {};
    final profilePictureUrl = loginState["profilePicture"] as String?;
    
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundImage: NetworkImage(profilePictureUrl),
        backgroundColor: AppColors.surfaceVariant,
        onBackgroundImageError: (exception, stackTrace) {
          if (LOGGING_SWITCH) {
            _logger.warning('AccountScreen: Failed to load profile picture: $exception');
          }
        },
      );
    }
    
    // Fallback to icon if no picture
    return Icon(
      Icons.account_circle,
      size: 80,
      color: Theme.of(context).primaryColor,
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
          final username = loginState?["username"] ?? "";
          final email = loginState?["email"] ?? "";
          
          // Update guest account status only when login state actually changes (prevents rebuild loop)
          if (isLoggedIn != _lastLoggedInState) {
            _lastLoggedInState = isLoggedIn;
            if (isLoggedIn) {
              // Use WidgetsBinding to schedule the check after the current build completes
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  
                  // User Profile Section
                  Center(
                    child: Column(
                      children: [
                        // Profile Picture or Icon
                        _buildProfilePicture(),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome Back!',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          username.isNotEmpty ? username : email,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // User Info Card
                  Container(
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
                          'Account Information',
                          style: AppTextStyles.headingMedium(),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow('Username', username),
                        const SizedBox(height: 8),
                        _buildInfoRow('Email', email),
                        const SizedBox(height: 8),
                        _buildInfoRow('User ID', loginState?["userId"] ?? ""),
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
                ],
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
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isLoginMode ? 'Welcome Back' : 'Create Account',
                    style: AppTextStyles.headingLarge().copyWith(
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoginMode 
                      ? 'Sign in to your account' 
                      : 'Join our community',
                    style: AppTextStyles.bodyLarge().copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Mode Toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
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
                            ? Theme.of(context).primaryColor 
                            : Colors.transparent,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Login',
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: _isLoginMode ? AppColors.textOnAccent : AppColors.textSecondary,
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
                            ? Theme.of(context).primaryColor 
                            : Colors.transparent,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Register',
                            style: AppTextStyles.bodyMedium().copyWith(
                              color: !_isLoginMode ? AppColors.textOnAccent : AppColors.textSecondary,
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
            
            // Google Sign-In Button
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleGoogleSignIn,
              icon: Image.asset(
                'assets/images/google_logo.png',
                height: 20,
                width: 20,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback to icon if image not found
                  return const Icon(Icons.login, size: 20);
                },
              ),
              label: Text(_isLoginMode ? 'Sign in with Google' : 'Sign up with Google'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppColors.borderDefault),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Divider with "OR"
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.borderDefault)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.borderDefault)),
              ],
            ),
            
            const SizedBox(height: 16),
            
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
                backgroundColor: Theme.of(context).primaryColor,
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
                    _isLoginMode ? 'Sign In' : 'Create Account',
                    style: AppTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.bold,
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
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Continue as Guest'),
                    style: OutlinedButton.styleFrom(
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
                      color: AppColors.textSecondary,
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
                            icon: const Icon(Icons.person_outline),
                            label: const Text('Continue as Guest'),
                            style: OutlinedButton.styleFrom(
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
                              color: AppColors.textSecondary,
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
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
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
  
  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          // Email Field
          Semantics(
            label: 'account_email',
            identifier: 'account_email',
            container: true,
            explicitChildNodes: true,
            child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'Enter your email',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
              ),
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
          
          const SizedBox(height: 20),
          
          // Password Field
          Semantics(
            label: 'account_password',
            identifier: 'account_password',
            container: true,
            explicitChildNodes: true,
            child: TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: _togglePasswordVisibility,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
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
    return Form(
      key: _registerFormKey,
      child: Column(
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
            TextFormField(
              initialValue: _guestEmail,
              readOnly: true,
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Guest Email',
                hintText: 'Your guest account email',
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Guest Password (read-only, obscured)
            TextFormField(
              initialValue: _guestPassword,
              readOnly: true,
              enabled: false,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Guest Password',
                hintText: 'Your guest account password',
                prefixIcon: const Icon(Icons.lock_outlined),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Divider
            const Divider(),
            const SizedBox(height: 20),
          ],
          
          // Username Field
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'Choose a username',
              prefixIcon: const Icon(Icons.person_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
              ),
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
          
          const SizedBox(height: 20),
          
          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'Enter your email',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
              ),
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
          
          const SizedBox(height: 20),
          
          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Create a password',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: _togglePasswordVisibility,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
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
          
          const SizedBox(height: 20),
          
          // Confirm Password Field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              hintText: 'Confirm your password',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: _toggleConfirmPasswordVisibility,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderFocused),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
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