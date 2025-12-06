# API Reference Documentation

## Overview

This document provides a comprehensive API reference for all components in the Flutter Base 05 application. It includes detailed information about classes, methods, properties, and usage examples.

## Core Managers

### StateManager

**File**: `lib/core/managers/state_manager.dart`

#### Class Definition
```dart
class StateManager with ChangeNotifier
```

#### Key Methods

##### `registerModuleState(String moduleKey, Map<String, dynamic> initialState)`
Registers a new module state with initial values.

**Parameters**:
- `moduleKey` (String): Unique identifier for the module state
- `initialState` (Map<String, dynamic>): Initial state values

**Example**:
```dart
final stateManager = StateManager();
stateManager.registerModuleState("user_module", {
  "isLoggedIn": false,
  "userData": null,
  "preferences": {},
});
```

##### `updateModuleState(String moduleKey, Map<String, dynamic> newState, {bool force = false})`
Updates module state by merging new state with existing state.

**Parameters**:
- `moduleKey` (String): Module state identifier
- `newState` (Map<String, dynamic>): New state values to merge
- `force` (bool): Force update even if module not registered

**Example**:
```dart
stateManager.updateModuleState("user_module", {
  "isLoggedIn": true,
  "userData": {"id": "123", "name": "John"},
});
```

##### `T? getModuleState<T>(String moduleKey)`
Retrieves module state with type safety.

**Parameters**:
- `moduleKey` (String): Module state identifier

**Returns**: Module state of type T or null

**Example**:
```dart
final userState = stateManager.getModuleState<Map<String, dynamic>>("user_module");
final isLoggedIn = userState?["isLoggedIn"] ?? false;
```

##### `void updateMainAppState(String key, dynamic value)`
Updates main application state.

**Parameters**:
- `key` (String): State key
- `value` (dynamic): State value

**Example**:
```dart
stateManager.updateMainAppState("app_state", "active");
stateManager.updateMainAppState("current_screen", "home");
```

##### `Map<String, dynamic> get mainAppState`
Gets the current main application state.

**Returns**: Map containing main app state

**Example**:
```dart
final mainState = stateManager.mainAppState;
final appState = mainState["app_state"];
```

### AuthManager

**File**: `lib/core/managers/auth_manager.dart`

#### Class Definition
```dart
class AuthManager extends ChangeNotifier
```

#### Enums
```dart
enum AuthStatus {
  loggedIn,
  loggedOut,
  tokenExpired,
  sessionExpired,
  error
}
```

#### Key Methods

##### `Future<void> storeTokens({required String accessToken, required String refreshToken})`
Stores JWT tokens in secure storage.

**Parameters**:
- `accessToken` (String): JWT access token
- `refreshToken` (String): JWT refresh token

**Example**:
```dart
final authManager = AuthManager();
await authManager.storeTokens(
  accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  refreshToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
);
```

##### `Future<String?> getAccessToken()`
Retrieves access token from secure storage.

**Returns**: Access token string or null

**Example**:
```dart
final token = await authManager.getAccessToken();
if (token != null) {
  // Use token for API requests
}
```

##### `Future<String?> getCurrentValidToken()`
Gets current valid JWT token, refreshing if necessary.

**Returns**: Valid access token or null

**Example**:
```dart
final token = await authManager.getCurrentValidToken();
if (token != null) {
  // Token is valid and fresh
}
```

##### `Future<AuthStatus> validateSessionOnStartup()`
Validates user session on application startup.

**Returns**: Authentication status

**Example**:
```dart
final status = await authManager.validateSessionOnStartup();
switch (status) {
  case AuthStatus.loggedIn:
    // User is logged in
    break;
  case AuthStatus.loggedOut:
    // User needs to log in
    break;
  case AuthStatus.tokenExpired:
    // Token expired, need refresh
    break;
}
```

##### `Future<void> handleAuthState(BuildContext context, AuthStatus status)`
Handles authentication state changes.

**Parameters**:
- `context` (BuildContext): Flutter context
- `status` (AuthStatus): Authentication status

**Example**:
```dart
await authManager.handleAuthState(context, AuthStatus.loggedIn);
```

##### `bool get isLoggedIn`
Checks if user is currently logged in.

**Returns**: True if user is logged in

**Example**:
```dart
if (authManager.isLoggedIn) {
  // User is logged in
}
```

### ModuleManager

**File**: `lib/core/managers/module_manager.dart`

#### Class Definition
```dart
class ModuleManager extends ChangeNotifier
```

#### Key Methods

##### `void registerModule(ModuleBase module)`
Registers a module with the manager.

**Parameters**:
- `module` (ModuleBase): Module to register

**Example**:
```dart
final moduleManager = ModuleManager();
moduleManager.registerModule(LoginModule());
moduleManager.registerModule(HomeModule());
```

##### `T? getModuleByType<T>()`
Retrieves module by type.

**Returns**: Module of type T or null

**Example**:
```dart
final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
if (apiModule != null) {
  // Use API module
}
```

##### `ModuleBase? getModuleByKey(String moduleKey)`
Retrieves module by key.

**Parameters**:
- `moduleKey` (String): Module key

**Returns**: Module or null

**Example**:
```dart
final module = moduleManager.getModuleByKey("login_module");
```

##### `Future<void> initializeAllModules(BuildContext context)`
Initializes all registered modules.

**Parameters**:
- `context` (BuildContext): Flutter context

**Example**:
```dart
await moduleManager.initializeAllModules(context);
```

##### `Map<String, dynamic> getAllModuleHealth()`
Gets health status of all modules.

**Returns**: Map of module health statuses

**Example**:
```dart
final health = moduleManager.getAllModuleHealth();
for (final entry in health.entries) {
  print("${entry.key}: ${entry.value['status']}");
}
```

### ServicesManager

**File**: `lib/core/managers/services_manager.dart`

#### Class Definition
```dart
class ServicesManager extends ChangeNotifier
```

#### Key Methods

##### `void registerService(String key, ServicesBase service)`
Registers a service with the manager.

**Parameters**:
- `key` (String): Service key
- `service` (ServicesBase): Service to register

**Example**:
```dart
final servicesManager = ServicesManager();
servicesManager.registerService("shared_pref", SharedPrefManager());
```

##### `T? getService<T>(String key)`
Retrieves service by key.

**Parameters**:
- `key` (String): Service key

**Returns**: Service of type T or null

**Example**:
```dart
final sharedPref = servicesManager.getService<SharedPrefManager>("shared_pref");
if (sharedPref != null) {
  await sharedPref.setString("key", "value");
}
```

##### `Future<void> autoRegisterAllServices()`
Automatically registers all core services.

**Example**:
```dart
await servicesManager.autoRegisterAllServices();
```

## Core Services

### SharedPrefManager

**File**: `lib/core/services/shared_preferences.dart`

#### Class Definition
```dart
class SharedPrefManager extends ServicesBase
```

#### Key Methods

##### Create Methods (Only set if key doesn't exist)

###### `Future<void> createString(String key, String value)`
Creates a string value only if the key doesn't exist.

**Parameters**:
- `key` (String): Preference key
- `value` (String): String value

**Example**:
```dart
await sharedPref.createString("user_id", "12345");
```

###### `Future<void> createInt(String key, int value)`
Creates an integer value only if the key doesn't exist.

**Parameters**:
- `key` (String): Preference key
- `value` (int): Integer value

**Example**:
```dart
await sharedPref.createInt("theme_mode", 1);
```

###### `Future<void> createBool(String key, bool value)`
Creates a boolean value only if the key doesn't exist.

**Parameters**:
- `key` (String): Preference key
- `value` (bool): Boolean value

**Example**:
```dart
await sharedPref.createBool("is_first_run", true);
```

##### Setter Methods (Always set the value)

###### `Future<void> setString(String key, String value)`
Sets a string value.

**Parameters**:
- `key` (String): Preference key
- `value` (String): String value

**Example**:
```dart
await sharedPref.setString("username", "john_doe");
```

###### `Future<void> setInt(String key, int value)`
Sets an integer value.

**Parameters**:
- `key` (String): Preference key
- `value` (int): Integer value

**Example**:
```dart
await sharedPref.setInt("score", 100);
```

###### `Future<void> setBool(String key, bool value)`
Sets a boolean value.

**Parameters**:
- `key` (String): Preference key
- `value` (bool): Boolean value

**Example**:
```dart
await sharedPref.setBool("notifications_enabled", true);
```

##### Getter Methods

###### `String? getString(String key)`
Gets a string value.

**Parameters**:
- `key` (String): Preference key

**Returns**: String value or null

**Example**:
```dart
final username = sharedPref.getString("username");
```

###### `int? getInt(String key)`
Gets an integer value.

**Parameters**:
- `key` (String): Preference key

**Returns**: Integer value or null

**Example**:
```dart
final score = sharedPref.getInt("score");
```

###### `bool? getBool(String key)`
Gets a boolean value.

**Parameters**:
- `key` (String): Preference key

**Returns**: Boolean value or null

**Example**:
```dart
final notificationsEnabled = sharedPref.getBool("notifications_enabled");
```

##### Utility Methods

###### `Future<void> remove(String key)`
Removes a preference key.

**Parameters**:
- `key` (String): Preference key to remove

**Example**:
```dart
await sharedPref.remove("old_preference");
```

###### `Future<void> clear()`
Clears all preferences.

**Example**:
```dart
await sharedPref.clear();
```

## API Module

### ConnectionsApiModule

**File**: `lib/modules/connections_api_module/connections_api_module.dart`

#### Class Definition
```dart
class ConnectionsApiModule extends ModuleBase
```

#### Constructor
```dart
ConnectionsApiModule(String baseUrl)
```

**Parameters**:
- `baseUrl` (String): Base URL for API requests

**Example**:
```dart
final apiModule = ConnectionsApiModule("https://api.example.com");
```

#### Key Methods

##### `Future<dynamic> sendGetRequest(String route)`
Sends a GET request to the API.

**Parameters**:
- `route` (String): API route

**Returns**: API response

**Example**:
```dart
final response = await apiModule.sendGetRequest("/users/profile");
if (response is Map && response.containsKey('data')) {
  final userData = response['data'];
}
```

##### `Future<dynamic> sendPostRequest(String route, Map<String, dynamic> data)`
Sends a POST request to the API.

**Parameters**:
- `route` (String): API route
- `data` (Map<String, dynamic>): Request data

**Returns**: API response

**Example**:
```dart
final response = await apiModule.sendPostRequest("/auth/login", {
  "username": "john_doe",
  "password": "password123",
});
```

##### `Future<dynamic> sendRequest(String route, {required String method, Map<String, dynamic>? data})`
Sends a generic HTTP request.

**Parameters**:
- `route` (String): API route
- `method` (String): HTTP method (GET, POST, PUT, DELETE)
- `data` (Map<String, dynamic>?): Request data (optional)

**Returns**: API response

**Example**:
```dart
// GET request
final getResponse = await apiModule.sendRequest("/users", method: "GET");

// POST request
final postResponse = await apiModule.sendRequest("/users", 
  method: "POST", 
  data: {"name": "John", "email": "john@example.com"}
);

// PUT request
final putResponse = await apiModule.sendRequest("/users/123", 
  method: "PUT", 
  data: {"name": "John Updated"}
);

// DELETE request
final deleteResponse = await apiModule.sendRequest("/users/123", method: "DELETE");
```

##### `static Map<String, String> generateLinks(String path)`
Generates HTTP and app deep links for a given path.

**Parameters**:
- `path` (String): Path to generate links for

**Returns**: Map containing HTTP and app links

**Example**:
```dart
final links = ConnectionsApiModule.generateLinks("/profile");
// Returns: {"http": "https://example.com/profile", "app": "cleco://profile"}
```

##### `static Future<bool> launchUrl(String url)`
Launches a URL in the browser or app.

**Parameters**:
- `url` (String): URL to launch

**Returns**: True if URL was launched successfully

**Example**:
```dart
final success = await ConnectionsApiModule.launchUrl("https://example.com");
if (success) {
  print("URL launched successfully");
}
```

## Models

### CreditBucket

**File**: `lib/models/credit_bucket.dart`

#### Class Definition
```dart
class CreditBucket
```

#### Properties
- `id` (String): Unique identifier
- `userId` (String): User identifier
- `balance` (double): Current balance
- `lockedAmount` (double): Locked amount
- `createdAt` (DateTime): Creation timestamp
- `updatedAt` (DateTime): Last update timestamp

#### Constructor
```dart
CreditBucket({
  required this.id,
  required this.userId,
  required this.balance,
  required this.lockedAmount,
  required this.createdAt,
  required this.updatedAt,
})
```

#### Key Methods

##### `factory CreditBucket.fromJson(Map<String, dynamic> json)`
Creates a CreditBucket instance from JSON data.

**Parameters**:
- `json` (Map<String, dynamic>): JSON data

**Returns**: CreditBucket instance

**Example**:
```dart
final json = {
  "id": "bucket_123",
  "userId": "user_456",
  "balance": 100.50,
  "lockedAmount": 10.00,
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-02T00:00:00Z",
};

final creditBucket = CreditBucket.fromJson(json);
```

##### `Map<String, dynamic> toJson()`
Converts CreditBucket instance to JSON.

**Returns**: JSON representation

**Example**:
```dart
final json = creditBucket.toJson();
// Returns: {"id": "bucket_123", "userId": "user_456", ...}
```

## Utilities

### Logger

**File**: `lib/tools/logging/logger.dart`

#### Class Definition
```dart
class Logger
```

#### Key Methods

##### `void info(String message)`
Logs an informational message.

**Parameters**:
- `message` (String): Message to log

**Example**:
```dart
final logger = Logger();
logger.info("User logged in successfully");
```

##### `void debug(String message)`
Logs a debug message.

**Parameters**:
- `message` (String): Message to log

**Example**:
```dart
logger.debug("Processing user data");
```

##### `void error(String message, {Object? error, StackTrace? stackTrace})`
Logs an error message.

**Parameters**:
- `message` (String): Error message
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)

**Example**:
```dart
try {
  // Some operation
} catch (e, stackTrace) {
  logger.error("Operation failed", error: e, stackTrace: stackTrace);
}
```

##### `void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0})`
Forces a log message regardless of configuration.

**Parameters**:
- `message` (String): Message to log
- `name` (String): Logger name (default: 'AppLogger')
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `level` (int): Log level (default: 0)

**Example**:
```dart
logger.forceLog("Critical error occurred", level: 1000);
```

## Configuration

### Config

**File**: `lib/utils/consts/config.dart`

#### Class Definition
```dart
class Config
```

#### Static Properties

##### `static const bool loggerOn`
Controls whether logging is enabled.

**Example**:
```dart
if (Config.loggerOn) {
  logger.info("This will be logged");
}
```

##### `static const String appTitle`
Application title.

**Example**:
```dart
final title = Config.appTitle; // Returns "cleco"
```

##### `static const String apiUrl`
API base URL.

**Example**:
```dart
final apiUrl = Config.apiUrl; // Returns "http://10.0.2.2:8081"
```

##### `static const String wsUrl`
WebSocket URL.

**Example**:
```dart
final wsUrl = Config.wsUrl; // Returns "ws://10.0.2.2:8081"
```

##### `static const String apiKey`
API key for authentication.

**Example**:
```dart
final apiKey = Config.apiKey;
```

##### `static const String stripePublishableKey`
Stripe publishable key.

**Example**:
```dart
final stripeKey = Config.stripePublishableKey;
```

##### AdMob Configuration
```dart
static const String admobsTopBanner
static const String admobsBottomBanner
static const String admobsInterstitial01
static const String admobsRewarded01
```

**Example**:
```dart
final topBanner = Config.admobsTopBanner;
final bottomBanner = Config.admobsBottomBanner;
```

## Theme Constants

### AppColors

**File**: `lib/utils/consts/theme_consts.dart`

#### Class Definition
```dart
class AppColors
```

#### Static Properties

##### Color Constants
```dart
static const Color primaryColor = Color(0xFF41282F);
static const Color accentColor = Color.fromARGB(255, 120, 67, 82);
static const Color accentColor2 = Color(0xFFFBC02D);
static const Color scaffoldBackgroundColor = Color.fromARGB(255, 255, 249, 240);
static const Color white = Colors.white;
static const Color darkGray = Color(0xFF333333);
static const Color lightGray = Color(0xFFB0BEC5);
static const Color redAccent = Colors.redAccent;
```

**Example**:
```dart
Container(
  color: AppColors.primaryColor,
  child: Text("Hello", style: TextStyle(color: AppColors.white)),
)
```

### AppTextStyles

**File**: `lib/utils/consts/theme_consts.dart`

#### Class Definition
```dart
class AppTextStyles
```

#### Static Methods

##### `static TextStyle headingLarge({Color color = AppColors.accentColor})`
Large heading text style.

**Parameters**:
- `color` (Color): Text color (default: AppColors.accentColor)

**Returns**: TextStyle for large headings

**Example**:
```dart
Text("Title", style: AppTextStyles.headingLarge())
```

##### `static TextStyle headingMedium({Color color = AppColors.accentColor})`
Medium heading text style.

**Parameters**:
- `color` (Color): Text color (default: AppColors.accentColor)

**Returns**: TextStyle for medium headings

**Example**:
```dart
Text("Subtitle", style: AppTextStyles.headingMedium())
```

##### `static TextStyle headingSmall({Color color = AppColors.accentColor})`
Small heading text style.

**Parameters**:
- `color` (Color): Text color (default: AppColors.accentColor)

**Returns**: TextStyle for small headings

**Example**:
```dart
Text("Section", style: AppTextStyles.headingSmall())
```

##### `static const TextStyle bodyMedium`
Medium body text style.

**Example**:
```dart
Text("Body text", style: AppTextStyles.bodyMedium)
```

##### `static const TextStyle bodyLarge`
Large body text style.

**Example**:
```dart
Text("Large body text", style: AppTextStyles.bodyLarge)
```

##### `static const TextStyle buttonText`
Button text style.

**Example**:
```dart
ElevatedButton(
  onPressed: () {},
  child: Text("Click me", style: AppTextStyles.buttonText),
)
```

### AppTheme

**File**: `lib/utils/consts/theme_consts.dart`

#### Class Definition
```dart
class AppTheme
```

#### Static Methods

##### `static ThemeData get darkTheme`
Returns the dark theme configuration.

**Returns**: ThemeData for dark theme

**Example**:
```dart
MaterialApp(
  theme: AppTheme.darkTheme,
  home: MyHomePage(),
)
```

## Module Base Class

### ModuleBase

**File**: `lib/core/00_base/module_base.dart`

#### Abstract Class Definition
```dart
abstract class ModuleBase
```

#### Properties
- `final String moduleKey`: Unique module identifier
- `final List<String> dependencies`: List of module dependencies
- `bool isInitialized`: Module initialization status

#### Constructor
```dart
ModuleBase(String moduleKey, {required List<String> dependencies})
```

#### Abstract Methods

##### `void initialize(BuildContext context, ModuleManager moduleManager)`
Initializes the module.

**Parameters**:
- `context` (BuildContext): Flutter context
- `moduleManager` (ModuleManager): Module manager instance

**Example**:
```dart
@override
void initialize(BuildContext context, ModuleManager moduleManager) {
  super.initialize(context, moduleManager);
  
  // Get dependencies
  final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
  
  // Initialize module
  _initializeModule(apiModule);
}
```

##### `void dispose()`
Disposes the module and cleans up resources.

**Example**:
```dart
@override
void dispose() {
  // Cleanup resources
  _disposeResources();
  
  super.dispose();
}
```

##### `Map<String, dynamic> healthCheck()`
Performs health check on the module.

**Returns**: Health check results

**Example**:
```dart
@override
Map<String, dynamic> healthCheck() {
  return {
    'module': moduleKey,
    'status': isInitialized ? 'healthy' : 'not_initialized',
    'details': 'Module is functioning normally',
    'custom_metric': 'example_value'
  };
}
```

## Usage Examples

### Complete Module Example

```dart
class UserModule extends ModuleBase {
  static final Logger _logger = Logger();
  late ConnectionsApiModule _apiModule;
  
  UserModule() : super("user_module", dependencies: ["connections_api_module"]);
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    
    // Get dependencies
    _apiModule = moduleManager.getModuleByType<ConnectionsApiModule>()!;
    
    // Register module state
    final stateManager = StateManager();
    stateManager.registerModuleState("user_module", {
      "isLoading": false,
      "userData": null,
      "error": null,
    });
    
    _logger.info('✅ UserModule initialized');
  }
  
  Future<void> loadUserProfile() async {
    final stateManager = StateManager();
    
    // Update loading state
    stateManager.updateModuleState("user_module", {"isLoading": true});
    
    try {
      // Fetch user data
      final response = await _apiModule.sendGetRequest("/user/profile");
      
      if (response is Map && response.containsKey('data')) {
        stateManager.updateModuleState("user_module", {
          "userData": response['data'],
          "isLoading": false,
          "error": null,
        });
      }
    } catch (e) {
      stateManager.updateModuleState("user_module", {
        "error": e.toString(),
        "isLoading": false,
      });
    }
  }
  
  @override
  void dispose() {
    _logger.info('🗑 UserModule disposed');
    super.dispose();
  }
  
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': 'User module is functioning normally',
      'user_data_loaded': _getUserData() != null,
    };
  }
  
  Map<String, dynamic>? _getUserData() {
    final stateManager = StateManager();
    final state = stateManager.getModuleState<Map<String, dynamic>>("user_module");
    return state?["userData"];
  }
}
```

### Authentication Flow Example

```dart
class AuthFlow {
  static Future<void> login(String username, String password) async {
    final authManager = AuthManager();
    final apiModule = ConnectionsApiModule(Config.apiUrl);
    
    try {
      // Send login request
      final response = await apiModule.sendPostRequest("/auth/login", {
        "username": username,
        "password": password,
      });
      
      if (response is Map && response.containsKey('data')) {
        final data = response['data'];
        
        // Store tokens
        await authManager.storeTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
        );
        
        // Update auth state
        await authManager.handleAuthState(context, AuthStatus.loggedIn);
        
        print("Login successful");
      } else {
        print("Login failed: ${response['message']}");
      }
    } catch (e) {
      print("Login error: $e");
    }
  }
  
  static Future<void> logout() async {
    final authManager = AuthManager();
    
    // Clear tokens
    await authManager.clearTokens();
    
    // Update auth state
    await authManager.handleAuthState(context, AuthStatus.loggedOut);
    
    print("Logout successful");
  }
}
```

### State Management Example

```dart
class GameStateManager {
  static void updateGameState(String gameId, Map<String, dynamic> gameData) {
    final stateManager = StateManager();
    
    stateManager.updateModuleState("game_module", {
      "currentGameId": gameId,
      "gameData": gameData,
      "lastUpdated": DateTime.now().toIso8601String(),
    });
  }
  
  static Map<String, dynamic>? getCurrentGame() {
    final stateManager = StateManager();
    final state = stateManager.getModuleState<Map<String, dynamic>>("game_module");
    return state?["gameData"];
  }
  
  static void clearGameState() {
    final stateManager = StateManager();
    stateManager.updateModuleState("game_module", {
      "currentGameId": null,
      "gameData": null,
      "lastUpdated": null,
    });
  }
}
```

## Error Handling

### Common Error Patterns

#### API Error Handling
```dart
try {
  final response = await apiModule.sendGetRequest("/api/endpoint");
  
  if (response is Map && response.containsKey('error')) {
    // Handle API error
    print("API Error: ${response['error']}");
    return;
  }
  
  // Process successful response
  processResponse(response);
} catch (e) {
  // Handle network or other errors
  print("Request failed: $e");
}
```

#### State Management Error Handling
```dart
try {
  stateManager.updateModuleState("module_key", newState);
} catch (e) {
  logger.error("Failed to update module state", error: e);
  // Handle state update error
}
```

#### Authentication Error Handling
```dart
try {
  final status = await authManager.validateSessionOnStartup();
  
  switch (status) {
    case AuthStatus.loggedIn:
      // User is logged in
      break;
    case AuthStatus.tokenExpired:
      // Handle token expiration
      await authManager.clearTokens();
      break;
    case AuthStatus.error:
      // Handle authentication error
      logger.error("Authentication error occurred");
      break;
    default:
      // Handle other statuses
      break;
  }
} catch (e) {
  logger.error("Session validation failed", error: e);
}
```

## Best Practices

### 1. Module Development
- Always extend ModuleBase for new modules
- Implement proper initialization and disposal
- Add health checks for monitoring
- Handle dependencies correctly

### 2. State Management
- Use descriptive module keys
- Implement proper state cleanup
- Handle state updates efficiently
- Use type-safe state access

### 3. API Communication
- Use the ConnectionsApiModule for all API calls
- Handle errors consistently
- Implement proper retry logic
- Use authentication interceptors

### 4. Authentication
- Always validate sessions on startup
- Implement proper token refresh
- Handle authentication errors gracefully
- Use secure storage for sensitive data

### 5. Logging
- Use the Logger class for all logging
- Include appropriate log levels
- Add context to error messages
- Use structured logging for debugging

## Conclusion

This API reference provides comprehensive documentation for all components in the Flutter Base 05 application. The modular architecture, comprehensive state management, and robust authentication system make it suitable for building enterprise-level Flutter applications.

For additional information about specific components or usage patterns, refer to the individual documentation files or the source code comments. 