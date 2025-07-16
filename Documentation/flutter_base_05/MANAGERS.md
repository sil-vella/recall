# Managers Documentation

## Overview

The Flutter Base 05 application uses a manager-based architecture where each manager handles a specific domain of functionality. This document provides detailed information about each manager, their responsibilities, and usage patterns.

## Manager Hierarchy

```
AppManager (Application Lifecycle)
├── StateManager (Global State)
├── AuthManager (Authentication)
├── ModuleManager (Module Coordination)
├── ServicesManager (Service Registration)
├── NavigationManager (Routing)
├── HooksManager (Event Hooks)
└── EventBus (Event Communication)
```

## StateManager

### Purpose
The StateManager is responsible for managing application-wide state and module-specific states. It provides a centralized state management system with type safety and efficient updates.

### Key Features

- **Module State Management**: Each module can register and manage its own state
- **Type-Safe State Access**: Generic methods for type-safe state retrieval
- **State Merging**: Automatic state merging with existing state
- **Lifecycle Management**: Proper state registration and cleanup
- **Debugging Support**: Comprehensive logging and state inspection

### Core Methods

#### State Registration
```dart
void registerModuleState(String moduleKey, Map<String, dynamic> initialState)
```
Registers a new module state with initial values.

#### State Updates
```dart
void updateModuleState(String moduleKey, Map<String, dynamic> newState, {bool force = false})
```
Updates module state by merging new state with existing state.

#### State Retrieval
```dart
T? getModuleState<T>(String moduleKey)
```
Retrieves module state with type safety.

#### Main App State
```dart
void updateMainAppState(String key, dynamic value)
Map<String, dynamic> get mainAppState
```
Manages application-wide state separate from module states.

### Usage Example

```dart
class ExampleModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    // Register module state
    final stateManager = StateManager();
    stateManager.registerModuleState("example_module", {
      "isLoading": false,
      "data": null,
      "error": null,
    });
  }
  
  void updateData(Map<String, dynamic> newData) {
    final stateManager = StateManager();
    stateManager.updateModuleState("example_module", {
      "data": newData,
      "isLoading": false,
    });
  }
}
```

### State Structure

```dart
class ModuleState {
  final Map<String, dynamic> state;
  
  ModuleState({required this.state});
  
  ModuleState merge(Map<String, dynamic> newState) {
    return ModuleState(state: {...state, ...newState});
  }
}
```

## AuthManager

### Purpose
The AuthManager handles all authentication-related functionality including JWT token management, session validation, and secure storage.

### Key Features

- **JWT Token Management**: Secure storage and automatic refresh of tokens
- **Session Validation**: Automatic session validation on app startup
- **State-Aware Token Refresh**: Intelligent token refresh based on app state
- **Secure Storage**: Encrypted storage for sensitive authentication data
- **Error Handling**: Comprehensive error handling for authentication failures

### Core Methods

#### Token Management
```dart
Future<void> storeTokens({required String accessToken, required String refreshToken})
Future<String?> getAccessToken()
Future<String?> getRefreshToken()
Future<void> clearTokens()
```
Manages JWT tokens in secure storage.

#### Token Refresh
```dart
Future<String?> refreshAccessToken(String refreshToken)
Future<String?> getCurrentValidToken()
```
Handles token refresh and validation.

#### Session Validation
```dart
Future<AuthStatus> validateSessionOnStartup()
```
Validates user session on application startup.

#### Authentication State
```dart
Future<void> handleAuthState(BuildContext context, AuthStatus status)
Map<String, dynamic> getCurrentUserData()
bool get isLoggedIn
```
Manages authentication state and user data.

### Authentication Status

```dart
enum AuthStatus {
  loggedIn,
  loggedOut,
  tokenExpired,
  sessionExpired,
  error
}
```

### Usage Example

```dart
class LoginModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    final authManager = AuthManager();
    
    // Validate session on startup
    authManager.validateSessionOnStartup().then((status) {
      authManager.handleAuthState(context, status);
    });
  }
  
  Future<void> login(String username, String password) async {
    final authManager = AuthManager();
    
    // Perform login
    final response = await apiModule.sendPostRequest('/auth/login', {
      'username': username,
      'password': password,
    });
    
    if (response['success']) {
      await authManager.storeTokens(
        accessToken: response['access_token'],
        refreshToken: response['refresh_token'],
      );
      
      authManager.handleAuthState(context, AuthStatus.loggedIn);
    }
  }
}
```

### Token Refresh Strategy

The AuthManager implements a sophisticated token refresh strategy:

1. **State-Aware Refresh**: Tokens are only refreshed when the app is not in game states
2. **Queue System**: Refresh requests are queued during game states
3. **Automatic Retry**: Failed refreshes are retried automatically
4. **Background Refresh**: Tokens are refreshed in the background when possible

## ModuleManager

### Purpose
The ModuleManager coordinates the lifecycle of all modules in the application, handling registration, initialization, and disposal.

### Key Features

- **Module Registration**: Automatic registration of all modules
- **Dependency Resolution**: Handles module dependencies and initialization order
- **Lifecycle Management**: Proper initialization and disposal of modules
- **Health Monitoring**: Health checks for all modules
- **Module Discovery**: Automatic discovery and registration of modules

### Core Methods

#### Module Registration
```dart
void registerModule(ModuleBase module)
void registerAllModules(List<ModuleBase> modules)
```
Registers modules with the manager.

#### Module Access
```dart
T? getModuleByType<T>()
ModuleBase? getModuleByKey(String moduleKey)
```
Retrieves modules by type or key.

#### Module Lifecycle
```dart
Future<void> initializeAllModules(BuildContext context)
void disposeAllModules()
```
Manages module lifecycle.

#### Health Monitoring
```dart
Map<String, dynamic> getAllModuleHealth()
Map<String, dynamic> getModuleHealth(String moduleKey)
```
Monitors module health and status.

### Usage Example

```dart
class ModuleRegistry {
  void registerAllModules(ModuleManager moduleManager) {
    // Register all modules
    moduleManager.registerModule(ConnectionsApiModule(Config.apiUrl));
    moduleManager.registerModule(LoginModule());
    moduleManager.registerModule(HomeModule());
    moduleManager.registerModule(AudioModule());
    moduleManager.registerModule(AnimationsModule());
  }
}

class ExampleModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    // Get dependencies
    final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    final authModule = moduleManager.getModuleByType<LoginModule>();
    
    // Initialize module with dependencies
    _initializeWithDependencies(apiModule, authModule);
  }
}
```

## ServicesManager

### Purpose
The ServicesManager handles the registration and management of core services that provide essential functionality across the application.

### Key Features

- **Service Registration**: Automatic registration of core services
- **Service Discovery**: Easy access to services throughout the application
- **Lifecycle Management**: Proper initialization and disposal of services
- **Dependency Injection**: Services can depend on other services
- **Health Monitoring**: Health checks for all services

### Core Methods

#### Service Registration
```dart
void registerService(String key, ServicesBase service)
void autoRegisterAllServices()
```
Registers services with the manager.

#### Service Access
```dart
T? getService<T>(String key)
```
Retrieves services by key.

#### Service Lifecycle
```dart
Future<void> initializeAllServices()
void disposeAllServices()
```
Manages service lifecycle.

### Core Services

#### SharedPrefManager
Manages local data persistence using SharedPreferences.

```dart
class SharedPrefManager extends ServicesBase {
  // Create methods (only set if key doesn't exist)
  Future<void> createString(String key, String value)
  Future<void> createInt(String key, int value)
  Future<void> createBool(String key, bool value)
  
  // Setter methods (always set the value)
  Future<void> setString(String key, String value)
  Future<void> setInt(String key, int value)
  Future<void> setBool(String key, bool value)
  
  // Getter methods
  String? getString(String key)
  int? getInt(String key)
  bool? getBool(String key)
}
```

### Usage Example

```dart
class ExampleModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    
    // Get services
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    
    // Use services
    sharedPref?.setString('user_preference', 'value');
  }
}
```

## NavigationManager

### Purpose
The NavigationManager handles all navigation-related functionality including routing, deep linking, and navigation state management.

### Key Features

- **Route Management**: Centralized route definitions
- **Deep Linking**: Support for app deep links
- **Navigation State**: Track navigation state
- **Route Guards**: Authentication-based route protection
- **Navigation History**: Track navigation history

### Core Methods

#### Route Configuration
```dart
GoRouter get router
```
Provides the configured router for the application.

#### Navigation
```dart
void navigateTo(String route)
void goBack()
void navigateToHome()
```
Handles navigation between screens.

#### Deep Linking
```dart
void handleDeepLink(Uri uri)
```
Handles incoming deep links.

### Route Configuration

```dart
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
  redirect: (context, state) {
    // Route guards based on authentication
    final authManager = AuthManager();
    if (!authManager.isLoggedIn && state.location != '/login') {
      return '/login';
    }
    return null;
  },
);
```

### Usage Example

```dart
class ExampleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Example Screen'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              // Navigate to profile
              context.go('/profile');
            },
          ),
        ],
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Navigate to login
            context.go('/login');
          },
          child: Text('Go to Login'),
        ),
      ),
    );
  }
}
```

## AppManager

### Purpose
The AppManager handles application-level lifecycle and initialization.

### Key Features

- **Application Initialization**: Handles app startup and initialization
- **Lifecycle Management**: Manages app lifecycle states
- **Platform Integration**: Handles platform-specific initialization
- **Error Handling**: Application-level error handling

### Core Methods

#### Initialization
```dart
Future<void> initializeApp(BuildContext context)
bool get isInitialized
```
Handles application initialization.

#### Lifecycle Management
```dart
void handleAppLifecycleState(AppLifecycleState state)
```
Manages application lifecycle states.

### Usage Example

```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final AppManager _appManager = AppManager();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appManager.handleAppLifecycleState(state);
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_appManager.isInitialized) {
      return MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    
    return MaterialApp.router(
      routerConfig: navigationManager.router,
    );
  }
}
```

## HooksManager

### Purpose
The HooksManager provides a system for managing application hooks and callbacks.

### Key Features

- **Hook Registration**: Register hooks for various events
- **Event Callbacks**: Execute callbacks when events occur
- **Hook Lifecycle**: Manage hook lifecycle and cleanup
- **Event Filtering**: Filter events based on conditions

### Core Methods

#### Hook Registration
```dart
void registerHook(String event, Function callback)
void unregisterHook(String event, Function callback)
```
Manages hook registration and removal.

#### Event Execution
```dart
void executeHooks(String event, [Map<String, dynamic>? data])
```
Executes hooks for a specific event.

### Usage Example

```dart
class ExampleModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    final hooksManager = HooksManager();
    
    // Register hooks
    hooksManager.registerHook('user_login', (data) {
      print('User logged in: ${data['username']}');
    });
    
    hooksManager.registerHook('user_logout', (data) {
      print('User logged out');
    });
  }
}
```

## EventBus

### Purpose
The EventBus provides a centralized event communication system for loose coupling between components.

### Key Features

- **Event Publishing**: Publish events to subscribers
- **Event Subscription**: Subscribe to specific events
- **Event Filtering**: Filter events based on criteria
- **Asynchronous Events**: Support for asynchronous event handling

### Core Methods

#### Event Publishing
```dart
void publish(String event, [Map<String, dynamic>? data])
```
Publishes events to all subscribers.

#### Event Subscription
```dart
void subscribe(String event, Function callback)
void unsubscribe(String event, Function callback)
```
Manages event subscriptions.

### Usage Example

```dart
class ExampleModule extends ModuleBase {
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    final eventBus = EventBus();
    
    // Subscribe to events
    eventBus.subscribe('data_updated', (data) {
      updateUI(data);
    });
    
    // Publish events
    eventBus.publish('module_initialized', {
      'module': 'example_module',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

## Manager Integration

### Provider Setup

All managers are integrated using the Provider pattern:

```dart
runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppManager()),
      ChangeNotifierProvider(create: (_) => ModuleManager()),
      ChangeNotifierProvider(create: (_) => ServicesManager()),
      ChangeNotifierProvider(create: (_) => StateManager()),
      ChangeNotifierProvider(create: (_) => NavigationManager()),
      ChangeNotifierProvider(create: (_) => AuthManager()),
    ],
    child: const MyApp(),
  ),
);
```

### Manager Dependencies

Managers can depend on each other through Provider:

```dart
class ExampleManager extends ChangeNotifier {
  void initialize(BuildContext context) {
    final stateManager = Provider.of<StateManager>(context, listen: false);
    final authManager = Provider.of<AuthManager>(context, listen: false);
    
    // Use other managers
    stateManager.registerModuleState("example", {});
    authManager.validateSessionOnStartup();
  }
}
```

## Best Practices

### 1. Manager Initialization
- Initialize managers in the correct order
- Handle initialization errors gracefully
- Provide fallback behavior for failed initialization

### 2. State Management
- Use StateManager for all state that needs to be shared
- Register module states with descriptive keys
- Clean up state when modules are disposed

### 3. Authentication
- Always validate sessions on app startup
- Implement proper error handling for authentication failures
- Use secure storage for sensitive data

### 4. Module Management
- Register all modules in ModuleRegistry
- Handle module dependencies properly
- Implement health checks for all modules

### 5. Service Management
- Register all services in ServicesManager
- Use services for cross-cutting concerns
- Implement proper service lifecycle management

## Conclusion

The manager-based architecture provides a robust foundation for building scalable Flutter applications. Each manager has a clear responsibility and provides well-defined interfaces for other components to use.

The key benefits of this architecture are:

- **Separation of Concerns**: Each manager handles a specific domain
- **Testability**: Managers can be tested in isolation
- **Maintainability**: Clear interfaces and responsibilities
- **Scalability**: Easy to add new managers and functionality
- **Reusability**: Managers can be reused across different applications 