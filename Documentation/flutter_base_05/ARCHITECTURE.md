# Architecture Documentation

## Overview

Flutter Base 05 implements a sophisticated architecture designed for scalability, maintainability, and testability. The architecture follows several key patterns and principles:

## Core Architecture Patterns

### 1. Manager Pattern

The application uses a manager-based architecture where each manager handles a specific domain of functionality. This pattern provides:

- **Separation of Concerns**: Each manager has a single responsibility
- **Dependency Injection**: Managers can depend on each other through Provider
- **Lifecycle Management**: Proper initialization and disposal of resources
- **State Coordination**: Centralized state management across the application

#### Manager Hierarchy

```
AppManager (Application Lifecycle)
├── StateManager (Global State)
├── AuthManager (Authentication)
├── ModuleManager (Module Coordination)
├── ServicesManager (Service Registration)
└── NavigationManager (Routing)
```

### 2. Module System

The module system provides a structured way to organize features and functionality:

#### Module Structure

```dart
class ExampleModule extends ModuleBase {
  ExampleModule() : super("example_module", dependencies: ["dependency_module"]);
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    // Module initialization
  }
  
  @override
  void dispose() {
    // Cleanup resources
  }
  
  @override
  Map<String, dynamic> healthCheck() {
    // Health monitoring
  }
}
```

#### Module Lifecycle

1. **Registration**: Modules are registered in ModuleRegistry
2. **Initialization**: Dependencies are resolved and module is initialized
3. **Operation**: Module provides its functionality
4. **Disposal**: Resources are cleaned up when module is disposed

### 3. Service Layer

The service layer provides core functionality that can be used across modules:

#### Service Registration

```dart
class ServicesManager extends ChangeNotifier {
  final Map<String, ServicesBase> _services = {};
  
  void registerService(String key, ServicesBase service) {
    _services[key] = service;
    service.initialize();
  }
  
  T? getService<T>(String key) {
    return _services[key] as T?;
  }
}
```

## State Management Architecture

### StateManager Design

The StateManager implements a sophisticated state management system with the following features:

#### Module State Management

```dart
class ModuleState {
  final Map<String, dynamic> state;
  
  ModuleState({required this.state});
  
  ModuleState merge(Map<String, dynamic> newState) {
    return ModuleState(state: {...state, ...newState});
  }
}
```

#### State Registration Process

1. **Registration**: Modules register their state with a unique key
2. **Initialization**: Initial state is set during registration
3. **Updates**: State updates are merged with existing state
4. **Cleanup**: State is unregistered when module is disposed

#### State Update Flow

```
Module Update Request
    ↓
StateManager.updateModuleState()
    ↓
ModuleState.merge()
    ↓
notifyListeners()
    ↓
UI Rebuild
```

### Authentication Architecture

#### AuthManager Features

- **JWT Token Management**: Secure storage and refresh of tokens
- **Session Validation**: Automatic session validation on startup
- **State-Aware Token Refresh**: Intelligent token refresh based on app state
- **Secure Storage**: Encrypted storage for sensitive data

#### Authentication Flow

```
App Startup
    ↓
AuthManager.validateSessionOnStartup()
    ↓
Check Stored Tokens
    ↓
Validate with Server
    ↓
Update Auth State
    ↓
Notify UI
```

#### Token Refresh Strategy

The AuthManager implements a state-aware token refresh system:

- **Background Refresh**: Tokens are refreshed when app is not in game states
- **Queue System**: Refresh requests are queued during game states
- **Automatic Retry**: Failed refreshes are retried automatically
- **Error Handling**: Comprehensive error handling for network issues

## Module Architecture

### Module Base Class

```dart
abstract class ModuleBase {
  final String moduleKey;
  final List<String> dependencies;
  bool isInitialized = false;
  
  ModuleBase(this.moduleKey, {required this.dependencies});
  
  void initialize(BuildContext context, ModuleManager moduleManager);
  void dispose();
  Map<String, dynamic> healthCheck();
}
```

### Module Dependencies

Modules can declare dependencies on other modules:

```dart
class ExampleModule extends ModuleBase {
  ExampleModule() : super("example_module", dependencies: ["auth_module", "api_module"]);
}
```

### Module Health Monitoring

Each module implements a health check method:

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

## API Architecture

### ConnectionsApiModule

The API module provides centralized HTTP communication:

#### Features

- **Automatic Token Injection**: JWT tokens are automatically added to requests
- **Error Handling**: Comprehensive error handling and logging
- **Request Interception**: Custom interceptors for authentication
- **Response Processing**: Standardized response processing

#### Request Flow

```
Module Request
    ↓
ConnectionsApiModule.sendRequest()
    ↓
AuthInterceptor (Adds JWT Token)
    ↓
HTTP Request
    ↓
Response Processing
    ↓
Error Handling
    ↓
Return Result
```

#### Interceptor Pattern

```dart
class AuthInterceptor implements InterceptorContract {
  @override
  Future<RequestData> interceptRequest({required RequestData data}) async {
    // Add JWT token to headers
    final token = await AuthManager().getCurrentValidToken();
    if (token != null) {
      data.headers['Authorization'] = 'Bearer $token';
    }
    return data;
  }
}
```

## Navigation Architecture

### NavigationManager

The NavigationManager handles routing and navigation with a sophisticated route registration system:

#### Features

- **Dynamic Route Registration**: Routes can be registered programmatically
- **Drawer Navigation**: Automatic drawer generation with positioning
- **Route Filtering**: Smart filtering for drawer vs non-drawer routes
- **Position-Based Sorting**: Drawer items sorted by position
- **Duplicate Prevention**: Automatic prevention of duplicate routes

#### Route Registration System

```dart
class RegisteredRoute {
  final String path;
  final Widget Function(BuildContext) screen;
  final String? drawerTitle;
  final IconData? drawerIcon;
  final int drawerPosition;

  RegisteredRoute({
    required this.path,
    required this.screen,
    this.drawerTitle,
    this.drawerIcon,
    this.drawerPosition = 999,
  });
}
```

#### Route Registration Process

```dart
void registerRoute({
  required String path,
  required Widget Function(BuildContext) screen,
  String? drawerTitle,
  IconData? drawerIcon,
  int drawerPosition = 999,
}) {
  if (_routes.any((r) => r.path == path)) return; // Prevent duplicates
  
  final newRoute = RegisteredRoute(
    path: path,
    screen: screen,
    drawerTitle: drawerTitle,
    drawerIcon: drawerIcon,
    drawerPosition: drawerPosition,
  );
  
  _routes.add(newRoute);
  notifyListeners();
}
```

#### Drawer Navigation Logic

The system automatically generates drawer navigation based on registered routes:

```dart
List<RegisteredRoute> get drawerRoutes {
  final filteredRoutes = _routes.where((r) => r.shouldAppearInDrawer).toList();
  
  // Sort drawer items based on drawerPosition
  filteredRoutes.sort((a, b) => a.drawerPosition.compareTo(b.drawerPosition));
  
  return filteredRoutes;
}

bool get shouldAppearInDrawer {
  return drawerTitle != null && drawerIcon != null;
}
```

#### Router Configuration

```dart
GoRouter get router {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      ...routes, // Include dynamically registered routes
    ],
  );
}
```

#### Navigation Flow

```
Route Registration
    ↓
NavigationManager.registerRoute()
    ↓
RegisteredRoute Creation
    ↓
Route Storage & Notification
    ↓
Drawer Generation (if applicable)
    ↓
Router Update
    ↓
UI Navigation
```

## Logging Architecture

### Logger System

The application implements a structured logging system:

#### Features

- **Configurable Logging**: Enable/disable logging via configuration
- **Log Levels**: Different log levels for different types of messages
- **Structured Logging**: Consistent log format across the application
- **Performance**: Efficient logging that doesn't impact performance

#### Usage

```dart
class Logger {
  void info(String message) => log(message, level: 800);
  void debug(String message) => log(message, level: 500);
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(message, level: 1000, error: error, stackTrace: stackTrace);
}
```

## Configuration Architecture

### Environment-Based Configuration

The application uses environment-based configuration:

#### Configuration Sources

1. **Build-Time Constants**: Environment variables set during build
2. **Runtime Configuration**: Configuration loaded at runtime
3. **Platform-Specific**: Different configurations for different platforms

#### Configuration Management

```dart
class Config {
  static const String apiUrl = String.fromEnvironment(
    'API_URL_LOCAL',
    defaultValue: 'http://10.0.2.2:8081',
  );
  
  static const String wsUrl = String.fromEnvironment(
    'WS_URL_LOCAL',
    defaultValue: 'ws://10.0.2.2:8081',
  );
}
```

## Security Architecture

### Secure Storage

The application implements secure storage for sensitive data:

#### Features

- **Encrypted Storage**: Data is encrypted at rest
- **Platform-Specific**: Uses platform-specific secure storage
- **Automatic Cleanup**: Secure data is automatically cleaned up
- **Error Handling**: Comprehensive error handling for storage operations

#### Usage

```dart
class AuthManager {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: 'access_token', value: accessToken);
    await _secureStorage.write(key: 'refresh_token', value: refreshToken);
  }
}
```

## Performance Architecture

### Optimization Strategies

1. **Lazy Loading**: Modules are loaded only when needed
2. **State Optimization**: Efficient state updates and notifications
3. **Memory Management**: Proper disposal of resources
4. **Network Optimization**: Efficient API calls and caching

### Monitoring

The architecture includes comprehensive monitoring:

- **Module Health**: Health checks for all modules
- **Performance Metrics**: Performance monitoring and logging
- **Error Tracking**: Comprehensive error tracking and reporting
- **State Monitoring**: State change monitoring and logging

## Testing Architecture

### Testing Strategy

1. **Unit Tests**: Test individual components and methods
2. **Widget Tests**: Test UI components in isolation
3. **Integration Tests**: Test complete user flows
4. **Module Tests**: Test module functionality and interactions

### Test Structure

```
test/
├── unit/           # Unit tests
├── widget/         # Widget tests
├── integration/    # Integration tests
└── mocks/          # Mock objects
```

## Deployment Architecture

### Build Configuration

The application supports multiple build configurations:

- **Development**: Debug builds with hot reload
- **Staging**: Release builds for testing
- **Production**: Optimized release builds

### Platform Support

- **Android**: APK and App Bundle builds
- **iOS**: App Store and enterprise builds
- **Web**: Progressive Web App builds

## Conclusion

The Flutter Base 05 architecture provides a solid foundation for building scalable, maintainable Flutter applications. The modular design, comprehensive state management, and robust authentication system make it suitable for enterprise-level applications.

The architecture emphasizes:

- **Scalability**: Easy to add new features and modules
- **Maintainability**: Clear separation of concerns and well-defined interfaces
- **Testability**: Comprehensive testing support
- **Security**: Secure handling of sensitive data
- **Performance**: Optimized for performance and user experience 