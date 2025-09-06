# Flutter Base 05 - Documentation Index

## Overview

This index provides a comprehensive guide to all documentation files and components in the Flutter Base 05 project. Use this index to quickly locate specific information about the application architecture, components, and development guidelines.

## Documentation Files

### Core Documentation

| File | Description | Key Topics |
|------|-------------|------------|
| [README.md](./README.md) | Main project documentation | Project overview, setup, architecture |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Detailed architecture documentation | Manager pattern, module system, state management |
| [MANAGERS.md](./MANAGERS.md) | Manager components documentation | StateManager, AuthManager, ModuleManager, etc. |
| [API_REFERENCE.md](./API_REFERENCE.md) | Complete API reference | All classes, methods, properties, usage examples |
| [VALIDATED_EVENT_STATE_SYSTEM.md](./VALIDATED_EVENT_STATE_SYSTEM.md) | **NEW** Validated Event/State System | Data validation, event emission, state management, schemas |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Deployment and build documentation | Platform deployment, CI/CD, optimization |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Troubleshooting guide | Common issues, debugging, error resolution |

## Component Index

### Core Managers

#### StateManager
- **File**: `lib/core/managers/state_manager.dart`
- **Purpose**: Centralized state management
- **Key Methods**:
  - `registerModuleState()` - Register module state
  - `updateModuleState()` - Update module state
  - `getModuleState<T>()` - Get typed state
  - `updateMainAppState()` - Update main app state
- **Documentation**: [MANAGERS.md](./MANAGERS.md#statemanager)

#### AuthManager
- **File**: `lib/core/managers/auth_manager.dart`
- **Purpose**: Authentication and session management
- **Key Methods**:
  - `storeTokens()` - Store JWT tokens
  - `getCurrentValidToken()` - Get valid token
  - `validateSessionOnStartup()` - Validate session
  - `handleAuthState()` - Handle auth state changes
- **Documentation**: [MANAGERS.md](./MANAGERS.md#authmanager)

#### ModuleManager
- **File**: `lib/core/managers/module_manager.dart`
- **Purpose**: Module lifecycle and coordination
- **Key Methods**:
  - `registerModule()` - Register module
  - `getModuleByType<T>()` - Get module by type
  - `initializeAllModules()` - Initialize all modules
  - `getAllModuleHealth()` - Get module health
- **Documentation**: [MANAGERS.md](./MANAGERS.md#modulemanager)

#### ServicesManager
- **File**: `lib/core/managers/services_manager.dart`
- **Purpose**: Service registration and management
- **Key Methods**:
  - `registerService()` - Register service
  - `getService<T>()` - Get service by key
  - `autoRegisterAllServices()` - Auto-register services
- **Documentation**: [MANAGERS.md](./MANAGERS.md#servicesmanager)

#### NavigationManager
- **File**: `lib/core/managers/navigation_manager.dart`
- **Purpose**: Routing and navigation
- **Key Methods**:
  - `router` - GoRouter instance
  - `navigateTo()` - Navigate to route
  - `handleDeepLink()` - Handle deep links
- **Documentation**: [MANAGERS.md](./MANAGERS.md#navigationmanager)

#### AppManager
- **File**: `lib/core/managers/app_manager.dart`
- **Purpose**: Application lifecycle management
- **Key Methods**:
  - `initializeApp()` - Initialize application
  - `handleAppLifecycleState()` - Handle lifecycle
- **Documentation**: [MANAGERS.md](./MANAGERS.md#appmanager)

### Core Services

#### SharedPrefManager
- **File**: `lib/core/services/shared_preferences.dart`
- **Purpose**: Local data persistence
- **Key Methods**:
  - `setString()`, `getString()` - String operations
  - `setInt()`, `getInt()` - Integer operations
  - `setBool()`, `getBool()` - Boolean operations
  - `setStringList()`, `getStringList()` - List operations
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#sharedprefmanager)

### API Module

#### ConnectionsApiModule
- **File**: `lib/modules/connections_api_module/connections_api_module.dart`
- **Purpose**: HTTP communication
- **Key Methods**:
  - `sendGetRequest()` - GET requests
  - `sendPostRequest()` - POST requests
  - `sendRequest()` - Generic requests
  - `generateLinks()` - Generate URLs
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#connectionsapimodule)

### Models

#### CreditBucket
- **File**: `lib/models/credit_bucket.dart`
- **Purpose**: Credit bucket data model
- **Key Methods**:
  - `fromJson()` - Create from JSON
  - `toJson()` - Convert to JSON
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#creditbucket)

### Utilities

#### Logger
- **File**: `lib/tools/logging/logger.dart`
- **Purpose**: Structured logging
- **Key Methods**:
  - `info()` - Info logging
  - `debug()` - Debug logging
  - `error()` - Error logging
  - `forceLog()` - Force logging
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#logger)

#### Config
- **File**: `lib/utils/consts/config.dart`
- **Purpose**: Application configuration
- **Key Properties**:
  - `apiUrl` - API base URL
  - `wsUrl` - WebSocket URL
  - `appTitle` - Application title
  - `loggerOn` - Logging toggle
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#config)

#### AppColors
- **File**: `lib/utils/consts/theme_consts.dart`
- **Purpose**: Color constants
- **Key Properties**:
  - `primaryColor` - Primary color
  - `accentColor` - Accent color
  - `scaffoldBackgroundColor` - Background color
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#appcolors)

#### AppTextStyles
- **File**: `lib/utils/consts/theme_consts.dart`
- **Purpose**: Text style constants
- **Key Methods**:
  - `headingLarge()` - Large heading style
  - `headingMedium()` - Medium heading style
  - `bodyMedium()` - Body text style
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#apptextstyles)

### Base Classes

#### ModuleBase
- **File**: `lib/core/00_base/module_base.dart`
- **Purpose**: Base class for modules
- **Key Methods**:
  - `initialize()` - Initialize module
  - `dispose()` - Dispose module
  - `healthCheck()` - Health check
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#modulebase)

## Module Index

### Available Modules

| Module | File | Purpose | Dependencies |
|--------|------|---------|--------------|
| ConnectionsApiModule | `lib/modules/connections_api_module/` | API communication | None |
| LoginModule | `lib/modules/login_module/` | Authentication | ConnectionsApiModule |
| HomeModule | `lib/modules/home_module/` | Home screen | None |
| AudioModule | `lib/modules/audio_module/` | Audio handling | None |
| AnimationsModule | `lib/modules/animations_module/` | UI animations | None |
| AdMobsModule | `lib/modules/admobs/` | Advertisement integration | None |
| MainHelperModule | `lib/modules/main_helper_module/` | Helper utilities | None |

### Module Template

#### TemplateModule
- **File**: `lib/modules/modules_template.dart`
- **Purpose**: Template for new modules
- **Usage**: Copy and customize for new modules
- **Documentation**: [API_REFERENCE.md](./API_REFERENCE.md#template-module-example)

## Screen Index

### Available Screens

| Screen | File | Purpose | Dependencies |
|--------|------|---------|--------------|
| RoomManagementScreen | `lib/screens/room_management_screen.dart` | Room management UI | Multiple modules |
| WebSocketScreen | `lib/screens/websocket_screen.dart` | WebSocket testing | ConnectionsApiModule |
| AccountScreen | `lib/screens/account_screen/` | Account management | AuthManager |

## Configuration Index

### Build Configuration

#### Environment Variables
- `API_URL_LOCAL` - API base URL
- `WS_URL_LOCAL` - WebSocket URL
- `API_KEY` - API authentication key
- `STRIPE_PUBLISHABLE_KEY` - Stripe key
- `ADMOBS_*` - AdMob configuration

#### Platform Configuration
- **Android**: `android/app/build.gradle`
- **iOS**: `ios/Runner/Info.plist`
- **Web**: `web/index.html`

### Theme Configuration

#### Color Scheme
- Primary: `#41282F`
- Accent: `#784352`
- Background: `#FFF9F0`
- Text: `#FFFFFF`

#### Text Styles
- Heading Large: 28px, bold
- Heading Medium: 24px, semibold
- Body Medium: 16px, regular
- Button Text: 18px, semibold

## Development Workflow

### 1. Project Setup
1. Clone repository
2. Run `flutter pub get`
3. Configure environment variables
4. Run `python3 configure_app.py`

### 2. Development Process
1. Create new modules extending `ModuleBase`
2. Register modules in `ModuleRegistry`
3. Implement state management with `StateManager`
4. Add authentication with `AuthManager`
5. Configure API communication with `ConnectionsApiModule`

### 3. Testing Process
1. Write unit tests for modules
2. Test state management
3. Verify API communication
4. Test authentication flow
5. Validate UI components

### 4. Deployment Process
1. Configure build environment
2. Set production environment variables
3. Build for target platforms
4. Deploy to app stores/web

## Quick Reference

### Common Patterns

#### Module Creation
```dart
class MyModule extends ModuleBase {
  MyModule() : super("my_module", dependencies: ["required_module"]);
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    // Initialize module
  }
  
  @override
  void dispose() {
    // Cleanup resources
    super.dispose();
  }
  
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
    };
  }
}
```

#### State Management
```dart
// Register state
stateManager.registerModuleState("module_key", {
  "initial_value": "default",
});

// Update state
stateManager.updateModuleState("module_key", {
  "new_value": "updated",
});

// Get state
final state = stateManager.getModuleState<Map<String, dynamic>>("module_key");
```

#### API Communication
```dart
// Send GET request
final response = await apiModule.sendGetRequest("/endpoint");

// Send POST request
final response = await apiModule.sendPostRequest("/endpoint", {
  "key": "value",
});

// Send generic request
final response = await apiModule.sendRequest("/endpoint", 
  method: "PUT", 
  data: {"key": "value"}
);
```

#### Authentication
```dart
// Store tokens
await authManager.storeTokens(
  accessToken: "token",
  refreshToken: "refresh_token",
);

// Validate session
final status = await authManager.validateSessionOnStartup();

// Get current token
final token = await authManager.getCurrentValidToken();
```

### Common Issues

#### Module Not Found
- Check module registration in `ModuleRegistry`
- Verify dependencies are resolved
- Ensure proper initialization order

#### State Not Updating
- Verify state registration
- Check Provider setup
- Ensure proper state update calls

#### Authentication Errors
- Check token storage
- Verify interceptor setup
- Validate session state

#### API Communication Issues
- Check API URL configuration
- Verify network connectivity
- Validate request/response format

## Documentation Updates

### Adding New Components
1. Create component following established patterns
2. Add comprehensive documentation
3. Update this index
4. Include usage examples
5. Add troubleshooting information

### Updating Documentation
1. Update relevant documentation files
2. Update this index
3. Verify all links work
4. Test code examples
5. Review for accuracy

## Support and Resources

### Documentation Files
- [README.md](./README.md) - Main documentation
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Architecture details
- [MANAGERS.md](./MANAGERS.md) - Manager documentation
- [API_REFERENCE.md](./API_REFERENCE.md) - API reference
- [VALIDATED_EVENT_STATE_SYSTEM.md](./VALIDATED_EVENT_STATE_SYSTEM.md) - **NEW** Validated Event/State System
- [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment guide
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Troubleshooting
- [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) - **NEW** Logging System Documentation

### External Resources
- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Documentation](https://dart.dev/guides)
- [Provider Package](https://pub.dev/packages/provider)
- [go_router Package](https://pub.dev/packages/go_router)

### Development Tools
- Flutter SDK (>=3.2.3)
- Dart SDK (>=3.2.3)
- Android Studio / VS Code
- Git for version control

## Conclusion

This index provides a comprehensive guide to all components and documentation in the Flutter Base 05 project. Use this index to quickly locate specific information and understand the project structure.

For detailed information about specific components, refer to the individual documentation files listed above. For development questions, consult the troubleshooting guide or external resources. 