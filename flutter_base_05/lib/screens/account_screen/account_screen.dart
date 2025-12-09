import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../modules/login_module/login_module.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';

class AccountScreen extends BaseScreen {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AccountScreen> createState() => _AccountScreenState();

  @override
  String computeTitle(BuildContext context) => 'Account';
}

class _AccountScreenState extends BaseScreenState<AccountScreen> {
  static const bool LOGGING_SWITCH = false; // Enabled for guest registration testing
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
  
  // Module manager
  final ModuleManager _moduleManager = ModuleManager();
  LoginModule? _loginModule;
  
  @override
  void initState() {
    super.initState();
    _logger.info('🔍 AccountScreen initState called', isOn: LOGGING_SWITCH);
    _initializeModules();
    _checkForGuestCredentials();
  }
  
  void _initializeModules() {
    _loginModule = _moduleManager.getModuleByType<LoginModule>();
    if (_loginModule == null) {
      _logger.error('❌ Login module not available', isOn: LOGGING_SWITCH);
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
        _logger.info('AccountScreen: Found preserved guest credentials - Username: $guestUsername', isOn: LOGGING_SWITCH);
        
        // Auto-populate login form with guest credentials
        // Email: guest_{username}@guest.local, Password: {username}
        final guestEmailFull = 'guest_$guestUsername@guest.local';
        _emailController.text = guestEmailFull;
        _passwordController.text = guestUsername; // Password is same as username
        
        _logger.info('AccountScreen: Auto-populated login form with guest credentials', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      _logger.error('AccountScreen: Error checking for guest credentials', error: e, isOn: LOGGING_SWITCH);
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
    });
    
    // If switching to login mode, check for guest credentials
    if (_isLoginMode) {
      _checkForGuestCredentials();
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
  
  // State Management Methods
  String _getCurrentAppState() {
    final stateManager = StateManager();
    final mainState = stateManager.getMainAppState<String>("main_state");
    return mainState ?? "unknown";
  }
  
  void _showStateSelectionDialog() {
    final List<String> availableStates = [
      'active_game',
      'pre_game', 
      'post_game',
      'idle'
    ];
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select App State'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableStates.map((state) {
              final isCurrentState = state == _getCurrentAppState();
              return ListTile(
                leading: Icon(
                  isCurrentState ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isCurrentState ? Theme.of(context).primaryColor : Colors.grey,
                ),
                title: Text(
                  state.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontWeight: isCurrentState ? FontWeight.bold : FontWeight.normal,
                    color: isCurrentState ? Theme.of(context).primaryColor : Colors.black,
                  ),
                ),
                subtitle: Text(
                  _getStateDescription(state),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _updateAppState(state);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  String _getStateDescription(String state) {
    switch (state) {
      case 'active_game':
        return 'Game is currently in progress';
      case 'pre_game':
        return 'Game is about to start';
      case 'post_game':
        return 'Game has just ended';
      case 'idle':
        return 'App is in idle state';
      default:
        return 'Unknown state';
    }
  }
  
  void _updateAppState(String newState) {
    final stateManager = StateManager();
    stateManager.updateMainAppState("main_state", newState);
    
    _logger.info('📱 App state updated to: $newState', isOn: LOGGING_SWITCH);
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('App state changed to: ${newState.replaceAll('_', ' ').toUpperCase()}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  Future<void> _handleLogin() async {
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
  
  Future<void> _handleRegister() async {
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
      );
      
      if (result['success'] != null) {
        setState(() {
          _successMessage = result['success'];
          _isLoading = false;
        });
        
        // Switch to login mode after successful registration
        Future.delayed(const Duration(seconds: 2), () {
          setState(() {
            _isLoginMode = true;
            _clearForms();
            _clearMessages();
          });
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
  
  /// Check if guest credentials exist in SharedPreferences
  Future<bool> _hasGuestCredentials() async {
    try {
      final sharedPref = SharedPrefManager();
      await sharedPref.initialize();
      
      final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
      final guestUsername = sharedPref.getString('guest_username');
      
      return isGuestAccount && guestUsername != null;
    } catch (e) {
      _logger.error('AccountScreen: Error checking for guest credentials', error: e, isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  /// Handle guest login using preserved credentials
  Future<void> _handleGuestLogin() async {
    _logger.info("AccountScreen: Guest login button pressed", isOn: LOGGING_SWITCH);
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
      
      _logger.info("AccountScreen: Logging in with guest credentials - Username: $guestUsername", isOn: LOGGING_SWITCH);
      
      final result = await _loginModule!.loginUser(
        context: context,
        email: guestEmail,
        password: guestUsername,
      );
      
      if (result['success'] != null) {
        _logger.info("AccountScreen: Guest login successful", isOn: LOGGING_SWITCH);
        setState(() {
          _successMessage = 'Welcome back, $guestUsername!';
          _isLoading = false;
        });
        
        // Navigate to main screen after successful login
        Future.delayed(const Duration(seconds: 2), () {
          context.go('/');
        });
      } else {
        _logger.error("AccountScreen: Guest login failed - Error: ${result['error']}", isOn: LOGGING_SWITCH);
        setState(() {
          _errorMessage = result['error'] ?? 'Login failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.error("AccountScreen: Exception during guest login", error: e, isOn: LOGGING_SWITCH);
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _handleGuestRegister() async {
    _logger.info("AccountScreen: Guest registration button pressed", isOn: LOGGING_SWITCH);
    setState(() {
      _isLoading = true;
      _clearMessages();
    });
    
    try {
      _logger.debug("AccountScreen: Calling registerGuestUser", isOn: LOGGING_SWITCH);
      final result = await _loginModule!.registerGuestUser(
        context: context,
      );
      
      if (result['success'] != null) {
        final username = result['username']?.toString() ?? '';
        _logger.info("AccountScreen: Guest registration successful - Username: $username", isOn: LOGGING_SWITCH);
        
        setState(() {
          _successMessage = 'Guest account created! Your username is: $username\n\nYour credentials are saved. You can log in again even after closing the app.';
          _isLoading = false;
        });
        
        // If auto-login was successful, navigate to main screen
        if (result['success'].toString().contains('logged in')) {
          _logger.info("AccountScreen: Auto-login successful, navigating to main screen", isOn: LOGGING_SWITCH);
          Future.delayed(const Duration(seconds: 3), () {
            context.go('/');
          });
        } else {
          _logger.info("AccountScreen: Auto-login not successful, switching to login mode", isOn: LOGGING_SWITCH);
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
        _logger.error("AccountScreen: Guest registration failed - Error: ${result['error']}", isOn: LOGGING_SWITCH);
        setState(() {
          _errorMessage = result['error'];
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.error("AccountScreen: Exception during guest registration", error: e, isOn: LOGGING_SWITCH);
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
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget buildContent(BuildContext context) {
    _logger.info('🔍 AccountScreen buildContent called', isOn: LOGGING_SWITCH);
    // Use AnimatedBuilder to listen to StateManager changes
    return AnimatedBuilder(
      animation: StateManager(),
      builder: (context, child) {
        // Get login state from StateManager
        final stateManager = StateManager();
        final loginState = stateManager.getModuleState("login");
        final isLoggedIn = loginState?["isLoggedIn"] ?? false;
        final username = loginState?["username"] ?? "";
        final email = loginState?["email"] ?? "";
        
        _logger.info('🔍 AccountScreen - isLoggedIn: $isLoggedIn, username: $username', isOn: LOGGING_SWITCH);
        
        // If user is logged in, show user profile
        if (isLoggedIn) {
          return SafeArea(
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
                        Icon(
                          Icons.account_circle,
                          size: 80,
                          color: Theme.of(context).primaryColor,
                        ),
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
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // User Info Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
                  
                  // State Management Section
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
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
                          'App State Management',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow('Current State', _getCurrentAppState()),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showStateSelectionDialog,
                          icon: const Icon(Icons.settings),
                          label: const Text('Change App State'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
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
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
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
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[600]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[700]),
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
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.green[600]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: TextStyle(color: Colors.green[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        
        // If user is not logged in, show login/register forms
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoginMode 
                      ? 'Sign in to your account' 
                      : 'Join our community',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Mode Toggle
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
                            style: TextStyle(
                              color: _isLoginMode ? Colors.white : Colors.grey[600],
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
                            style: TextStyle(
                              color: !_isLoginMode ? Colors.white : Colors.grey[600],
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: TextStyle(color: Colors.green[700]),
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
              onPressed: _isLoading ? null : (_isLoginMode ? _handleLogin : _handleRegister),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isLoginMode ? 'Sign In' : 'Create Account',
                    style: const TextStyle(
                      fontSize: 16,
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
                    onPressed: _isLoading ? null : _handleGuestRegister,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
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
                  if (snapshot.data == true) {
                    return Column(
                      children: [
                        const Divider(),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleGuestLogin,
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            
            // Mode Switch
            TextButton(
              onPressed: _isLoading ? null : _toggleMode,
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
        );
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
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