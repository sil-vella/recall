---
description:
globs: **/*.dart
alwaysApply: true
---

# Flutter Base 05 - AI Development Rules

## Overview

This document defines the rules and guidelines for AI-assisted development in the Flutter Base 05 project. All AI interactions must follow these architectural patterns, coding standards, and development practices.

## Core Architecture Principles

### 1. Manager-Based Architecture

**RULE**: Always use the established manager pattern for new functionality.

**PATTERN**: 
- Each domain of functionality must have a dedicated manager
- Managers extend `ChangeNotifier` for state management
- Managers are registered with `ServicesManager`
- Managers follow the single responsibility principle

**EXISTING MANAGERS**:
- `StateManager` - Global state management
- `AuthManager` - Authentication and session management  
- `ModuleManager` - Module lifecycle coordination
- `ServicesManager` - Service registration and management
- `NavigationManager` - Routing and navigation
- `AppManager` - Application lifecycle management
- `HooksManager` - Event hooks and callbacks
- `EventBus` - Event communication system

**RULE**: The current managers / base system shouldn't be modified, except for the module registry when new modules need to be added..

### 2. Module System

**RULE**: All features must be organized into modules that extend `ModuleBase`.

**PATTERN**:
```dart
class NewFeatureModule extends ModuleBase {
  NewFeatureModule() : super("new_feature_module", dependencies: ["required_module"]);
  
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
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': 'Module description'
    };
  }
}
```

### 3. Service Layer

**RULE**: Core functionality must be implemented as services that extend `ServicesBase`.

**PATTERN**:
```dart
class NewService extends ServicesBase {
  @override
  void initialize() {
    // Service initialization
  }
  
  @override
  void dispose() {
    // Service cleanup
  }
}
```

## State Management Rules

### 1. StateManager Usage

**RULE**: Always use `StateManager` for state management, never use other state management solutions.

**PATTERN**:
```dart
// Register module state
StateManager().registerModuleState("module_key", {
  "isLoading": false,
  "data": null,
  "error": null,
});

// Update state
StateManager().updateModuleState("module_key", {
  "data": newData,
  "isLoading": false,
});

// Retrieve state
final data = StateManager().getModuleState<Map<String, dynamic>>("module_key");
```

### 2. State Structure

**RULE**: Module states must follow consistent structure:
- `isLoading`: Boolean for loading states
- `data`: Main data payload
- `error`: Error information
- `timestamp`: Last update timestamp

## Authentication Rules

### 1. AuthManager Integration

**RULE**: All authentication-related functionality must use `AuthManager`.

**PATTERN**:
```dart
// Token management
await AuthManager().storeTokens(accessToken: token, refreshToken: refreshToken);
final token = await AuthManager().getCurrentValidToken();

// Session validation
final status = await AuthManager().validateSessionOnStartup();
AuthManager().handleAuthState(context, status);
```

### 2. API Authentication

**RULE**: All API requests must automatically include JWT tokens through `ConnectionsApiModule`.

**PATTERN**: Use the existing API module with automatic token injection:
```dart
final response = await ConnectionsApiModule().sendPostRequest('/endpoint', data);
```

## Module Development Rules

### 1. Module Structure

**RULE**: All modules must follow the established structure:

```
modules/
├── module_name/
│   ├── module_name_module.dart      # Main module class
│   ├── models/                      # Module-specific models
│   ├── services/                    # Module-specific services
│   ├── screens/                     # Module screens
│   ├── widgets/                     # Module widgets
│   └── utils/                       # Module utilities
```

### 2. Module Registration

**RULE**: All modules must be registered in `ModuleRegistry`.

**PATTERN**:
```dart
// In ModuleRegistry
moduleManager.registerModule(NewFeatureModule());
```

### 3. Module Dependencies

**RULE**: Modules must declare their dependencies explicitly.

**PATTERN**:
```dart
class NewModule extends ModuleBase {
  NewModule() : super("new_module", dependencies: ["auth_module", "api_module"]);
}
```

## API Development Rules

### 1. API Module Usage

**RULE**: All HTTP communication must go through `ConnectionsApiModule`.

**PATTERN**:
```dart
// GET request
final response = await ConnectionsApiModule().sendGetRequest('/endpoint');

// POST request
final response = await ConnectionsApiModule().sendPostRequest('/endpoint', data);

// PUT request
final response = await ConnectionsApiModule().sendPutRequest('/endpoint', data);

// DELETE request
final response = await ConnectionsApiModule().sendDeleteRequest('/endpoint');
```

### 2. Error Handling

**RULE**: All API calls must include proper error handling.

**PATTERN**:
```dart
try {
  final response = await ConnectionsApiModule().sendGetRequest('/endpoint');
  if (response['success']) {
    // Handle success
  } else {
    // Handle API error
  }
} catch (e) {
  // Handle network/connection error
  Logger().logError('API Error: $e');
}
```

## Navigation Rules

### 1. NavigationManager Usage

**RULE**: All navigation must use `NavigationManager` or `go_router`.

**PATTERN**:
```dart
// Navigate to screen
NavigationManager().navigateTo('/screen_path');

// Navigate with parameters
NavigationManager().navigateTo('/screen_path', parameters: {'id': '123'});
```

## Screen Organization Rules

### 1. Screen Structure

**RULE**: All screens must follow the established screen structure pattern.

**PATTERN**:
```dart
class MyScreen extends BaseScreen {
  const MyScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Screen Title';

  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends BaseScreenState<MyScreen> {
  // Managers
  final StateManager _stateManager = StateManager();
  
  @override
  void initState() {
    super.initState();
    // Initialize screen
  }

  @override
  void dispose() {
    // Cleanup resources
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<T>(
      stream: /* state stream */,
      builder: (context, snapshot) {
        return /* screen content */;
      },
    );
  }
}
```

### 2. Screen Directory Structure

**RULE**: Each screen must follow the established directory structure:

```
screens/
├── screen_name/                   # Screen module directory
│   ├── screen_name_screen.dart    # Main screen file
│   ├── services/                  # Screen-specific services
│   │   └── screen_service.dart
│   ├── widgets/                   # Screen-specific widgets
│   │   ├── widget_one.dart
│   │   └── widget_two.dart
│   ├── models/                    # Screen-specific models
│   │   └── screen_models.dart
│   └── utils/                     # Screen-specific utilities
│       └── screen_utils.dart
```

### 3. Screen Components

**RULE**: Screens must be organized into the following components:

1. **Main Screen Class**:
   - Extends `BaseScreen`
   - Implements `computeTitle`
   - Creates screen state

2. **Screen State Class**:
   - Extends `BaseScreenState`
   - Manages screen lifecycle
   - Implements `buildContent`

3. **Screen Widgets**:
   - Modular, reusable components
   - Follow widget naming convention
   - Include proper documentation

4. **Screen Services**:
   - Handle business logic
   - Manage API calls
   - Interface with managers

### 4. Screen Integration

**RULE**: Screens must properly integrate with the application architecture:

1. **State Management**:
```dart
// Register screen state
_stateManager.registerModuleState("screen_name", {
  "isLoading": false,
  "data": null,
  "error": null,
});

// Update state
_stateManager.updateModuleState("screen_name", newState);
```

2. **Manager Integration**:
```dart
// Initialize managers
final StateManager _stateManager = StateManager();
final WebSocketManager _wsManager = WebSocketManager.instance;

// Setup event listeners
_setupEventCallbacks();
```

3. **Error Handling**:
```dart
try {
  // Screen operations
} catch (e) {
  _showSnackBar('Operation failed: $e', isError: true);
}
```

## File Organization Rules

### 1. Directory Structure

**RULE**: Follow the established directory structure:

```
lib/
├── core/                           # Core application components
│   ├── managers/                   # All managers
│   ├── services/                   # Core services
│   ├── models/                     # Core models
│   └── 00_base/                   # Base classes
├── modules/                        # Feature modules
│   ├── module_name/                # Individual modules
│   │   ├── screens/               # Module screens
│   │   ├── widgets/               # Module widgets
│   │   ├── services/              # Module services
│   │   └── models/                # Module models
│   └── ...
├── screens/                        # Shared screens
├── models/                         # Shared models
├── services/                       # Shared services
├── tools/                          # Utility tools
├── utils/                          # Utility functions
└── main.dart                       # Application entry point
```

### 2. File Naming

**RULE**: Follow consistent naming conventions:
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/Functions: `camelCase`
- Constants: `SCREAMING_SNAKE_CASE`

## Code Quality Rules

### 1. Error Handling

**RULE**: All functions must include proper error handling.

**PATTERN**:
```dart
try {
  // Function logic
} catch (e) {
  Logger().logError('Error in function: $e');
  // Handle error appropriately
}
```

### 2. Logging

**RULE**: Use the built-in Logger for all logging.

**PATTERN**:
```dart
Logger().logInfo('Information message');
Logger().logWarning('Warning message');
Logger().logError('Error message');
Logger().logDebug('Debug message');
```

### 3. Documentation

**RULE**: All public APIs must include documentation.

**PATTERN**:
```dart
/// Brief description of the function
/// 
/// [param1] Description of parameter 1
/// [param2] Description of parameter 2
/// 
/// Returns a description of the return value
/// 
/// Example:
/// ```dart
/// final result = functionName(param1, param2);
/// ```
Future<void> functionName(String param1, int param2) async {
  // Implementation
}
```

## Security Rules

### 1. Sensitive Data

**RULE**: All sensitive data must be stored using `flutter_secure_storage`.

**PATTERN**:
```dart
// Store sensitive data
await SecureStorage().write(key: 'sensitive_key', value: 'sensitive_value');

// Retrieve sensitive data
final value = await SecureStorage().read(key: 'sensitive_key');
```

### 2. API Security

**RULE**: All API endpoints must be validated and sanitized.

**PATTERN**:
```dart
// Validate input
if (input == null || input.isEmpty) {
  throw ArgumentError('Input cannot be null or empty');
}

// Sanitize data before sending
final sanitizedData = sanitizeInput(data);
```

## Testing Rules

### 1. Test Structure

**RULE**: All new features must include tests.

**PATTERN**:
```
test/
├── unit/                          # Unit tests
├── widget/                        # Widget tests
└── integration/                   # Integration tests
```

### 2. Test Naming

**RULE**: Test files must be named `*_test.dart` and follow naming conventions.

**PATTERN**:
```dart
// test/unit/manager_test.dart
group('StateManager Tests', () {
  test('should register module state', () {
    // Test implementation
  });
});
```

## Performance Rules

### 1. Memory Management

**RULE**: All managers and modules must properly dispose of resources.

**PATTERN**:
```dart
@override
void dispose() {
  // Dispose of streams, controllers, etc.
  _streamController?.close();
  _timer?.cancel();
  super.dispose();
}
```

### 2. State Updates

**RULE**: Minimize unnecessary state updates and rebuilds.

**PATTERN**:
```dart
// Only update state when necessary
if (newData != currentData) {
  StateManager().updateModuleState("module_key", {"data": newData});
}
```

## Configuration Rules

### 1. Environment Configuration

**RULE**: Use the existing configuration system for environment-specific settings.

**PATTERN**:
```dart
// Use Config class for configuration
final apiUrl = Config.apiUrl;
final appName = Config.appName;
```

### 2. Feature Flags

**RULE**: Use the existing feature flag system for conditional features.

**PATTERN**:
```dart
if (Config.featureFlags['new_feature'] == true) {
  // Enable new feature
}
```

## AI Interaction Rules

### 1. Approval Process

**RULE**: Before creating any new manager, module, or service, ask the user for approval.

**PROCESS**:
1. Explain why the new component is needed
2. Describe its responsibilities and dependencies
3. Show how it fits into the existing architecture
4. Wait for user approval before implementation

### 2. Architecture Compliance

**RULE**: All code must follow the established architecture patterns.

**CHECKLIST**:
- [ ] Uses appropriate manager for functionality
- [ ] Follows module structure if applicable
- [ ] Uses StateManager for state management
- [ ] Includes proper error handling
- [ ] Uses built-in logging
- [ ] Follows naming conventions
- [ ] Includes documentation

### 3. Code Generation

**RULE**: When generating code, always include:
- Proper imports
- Error handling
- Logging statements
- Documentation comments
- Type safety

### 4. File Organization

**RULE**: When creating new files, place them in the appropriate directory:
- Managers → `lib/core/managers/`
- Modules → `lib/modules/`
- Services → `lib/core/services/` or `lib/services/`
- Models → `lib/core/models/` or `lib/models/`
- Screens → `lib/screens/`
- Widgets → `lib/widgets/` or module-specific `widgets/`

## Globs and Patterns

### 1. File Matching Patterns

**RULE**: Use these glob patterns for file operations:

```
# All Dart files
**/*.dart

# All manager files
lib/core/managers/*.dart

# All module files
lib/modules/**/*.dart

# All test files
test/**/*_test.dart

# All configuration files
**/*.yaml
**/*.json
**/*.xml
**/*.plist
**/*.gradle
```

### 2. Search Patterns

**RULE**: Use these patterns for searching specific components:

```
# Find all managers
class *Manager extends ChangeNotifier

# Find all modules
class *Module extends ModuleBase

# Find all services
class *Service extends ServicesBase

# Find all API calls
ConnectionsApiModule().send*Request

# Find all state updates
StateManager().updateModuleState
```

## Exception Handling

### 1. Custom Exceptions

**RULE**: Create custom exceptions for specific error cases.

**PATTERN**:
```dart
class ModuleException implements Exception {
  final String message;
  final String moduleKey;
  
  ModuleException(this.message, this.moduleKey);
  
  @override
  String toString() => 'ModuleException in $moduleKey: $message';
}
```

### 2. Exception Propagation

**RULE**: Properly propagate exceptions with context.

**PATTERN**:
```dart
try {
  // Operation
} catch (e) {
  Logger().logError('Operation failed: $e');
  rethrow; // Re-throw with context
}
```

## Documentation Requirements

### 1. Code Documentation

**RULE**: All public APIs must be documented.

**REQUIRED ELEMENTS**:
- Function/class purpose
- Parameter descriptions
- Return value descriptions
- Usage examples
- Error conditions

### 2. Architecture Documentation

**RULE**: New architectural components must be documented in the appropriate documentation files.

**FILES TO UPDATE**:
- `Documentation/flutter_base_05/ARCHITECTURE.md`
- `Documentation/flutter_base_05/MANAGERS.md`
- `Documentation/flutter_base_05/API_REFERENCE.md`

## Compliance Checklist

Before submitting any code, ensure compliance with:

- [ ] Manager-based architecture
- [ ] Module system usage
- [ ] StateManager for state management
- [ ] AuthManager for authentication
- [ ] Proper error handling
- [ ] Logging implementation
- [ ] Documentation included
- [ ] Tests written
- [ ] Security considerations
- [ ] Performance optimization
- [ ] File organization
- [ ] Naming conventions

## Summary

This MDC file defines the comprehensive rules for AI-assisted development in the Flutter Base 05 project. All AI interactions must follow these patterns, ask for approval before creating new architectural components, and maintain the established code quality and security standards.

The key principles are:
1. **Manager-based architecture** for all functionality
2. **Module system** for feature organization
3. **StateManager** for state management
4. **Proper error handling and logging**
5. **Security-first approach**
6. **Comprehensive documentation**
7. **Approval process for new components**

Follow these rules to maintain code quality, consistency, and architectural integrity.

---
description:
globs: **/*.py
alwaysApply: true
---
# Python Base 04 - AI Development Rules

## Overview

This document defines the rules and guidelines for AI-assisted development in the Python Base 04 project. All AI interactions must follow these architectural patterns, coding standards, and development practices.

## Core Architecture Principles

### 1. Manager-Based Architecture

**RULE**: Always use the established manager pattern for new functionality.

**PATTERN**: 
- Each domain of functionality must have a dedicated manager
- Managers follow the singleton pattern for consistent state
- Managers are integrated through the AppManager
- Managers follow the single responsibility principle
- All managers must implement health monitoring

**EXISTING MANAGERS**:
- `AppManager` - Application orchestrator and lifecycle management
- `StateManager` - Centralized state management with persistence
- `DatabaseManager` - Database operations and connection management
- `RedisManager` - Redis operations and caching management
- `JWTManager` - JWT token management and authentication
- `ApiKeyManager` - API key management and authentication
- `VaultManager` - HashiCorp Vault integration for secret management
- `RateLimiterManager` - Multi-level rate limiting and protection
- `ActionDiscoveryManager` - Dynamic action registration and execution
- `WebSocketManager` - WebSocket management and real-time communication
- `ModuleManager` - Module lifecycle and coordination
- `ServicesManager` - Service registration and management
- `HooksManager` - Event system and callbacks

**RULE**: The current managers / base system shouldn't be modified, except for the module registry when new modules need to be added..

### 2. Module System

**RULE**: All features must be organized into modules that extend `BaseModule`.

**PATTERN**:
```python
class NewFeatureModule(BaseModule):
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = ["required_module"]
        self.module_name = "new_feature_module"
    
    def initialize(self, app_manager):
        """Initialize the module"""
        self.app_manager = app_manager
        # Module initialization logic
    
    def register_routes(self):
        """Register module routes"""
        # Route registration logic
    
    def configure(self):
        """Configure module settings"""
        # Configuration logic
    
    def dispose(self):
        """Cleanup module resources"""
        # Cleanup logic
    
    def declare_dependencies(self) -> List[str]:
        """Declare module dependencies"""
        return self.dependencies
    
    def health_check(self) -> Dict[str, Any]:
        """Module health check"""
        return {
            "module": self.module_name,
            "status": "healthy" if self.app_manager else "not_initialized",
            "details": "Module description"
        }
```


### 3. Service Layer

**RULE**: Core functionality must be implemented as services that integrate with the ServicesManager.

**PATTERN**:
```python
class NewService:
    def __init__(self, app_manager):
        self.app_manager = app_manager
    
    def initialize(self):
        """Initialize the service"""
        # Service initialization
    
    def dispose(self):
        """Cleanup service resources"""
        # Service cleanup
    
    def health_check(self) -> Dict[str, Any]:
        """Service health check"""
        return {
            "service": self.__class__.__name__,
            "status": "healthy",
            "details": "Service description"
        }
```


## State Management Rules

### 1. StateManager Usage

**RULE**: Always use `StateManager` for state management, never use other state management solutions.

**PATTERN**:
```python
# Get state manager
state_manager = app_manager.get_state_manager()

# Register state
state_manager.register_state(
    state_id="module_state_key",
    state_type=StateType.SYSTEM,
    initial_data={"is_initialized": False, "data": None},
    allowed_transitions=["update", "delete", "activate"]
)

# Update state
state_manager.update_state(
    state_id="module_state_key",
    new_data={"is_initialized": True, "data": new_data},
    transition=StateTransition.UPDATE
)

# Get state
state = state_manager.get_state("module_state_key")
```

### 2. State Structure

**RULE**: States must follow consistent structure:
- `state_id`: Unique identifier for the state
- `state_type`: One of StateType enum values
- `data`: Main state payload
- `metadata`: Additional state information
- `timestamp`: Last update timestamp

## Authentication Rules

### 1. JWTManager Integration

**RULE**: All JWT token operations must use `JWTManager`.

**PATTERN**:
```python
# Get JWT manager
jwt_manager = app_manager.jwt_manager

# Create tokens
access_token = jwt_manager.create_access_token(
    user_id="user_123",
    additional_claims={"role": "user", "permissions": ["read", "write"]}
)
refresh_token = jwt_manager.create_refresh_token(user_id="user_123")

# Validate token
try:
    payload = jwt_manager.validate_token(access_token)
    user_id = payload["user_id"]
except Exception as e:
    # Handle validation error
    pass

# Refresh token
new_tokens = jwt_manager.refresh_token(refresh_token)
```

### 2. ApiKeyManager Integration

**RULE**: All API key operations must use `ApiKeyManager`.

**PATTERN**:
```python
# Get API key manager
api_key_manager = app_manager.api_key_manager

# Generate API key
api_key = api_key_manager.generate_api_key(
    user_id="user_123",
    permissions=["read", "write", "admin"]
)

# Validate API key
try:
    key_info = api_key_manager.validate_api_key(api_key)
    user_id = key_info["user_id"]
    permissions = key_info["permissions"]
except Exception as e:
    # Handle validation error
    pass
```

## Database Rules

### 1. DatabaseManager Usage

**RULE**: All database operations must go through `DatabaseManager`.

**PATTERN**:
```python
# Get database manager
db_manager = app_manager.get_db_manager(role="read_write")

# Check connection
if db_manager.check_connection():
    # Execute query
    result = db_manager.execute_query(
        "SELECT * FROM users WHERE id = %s",
        {"id": 123}
    )
    
    # Execute transaction
    operations = [
        {"type": "insert", "table": "users", "data": {"name": "John"}},
        {"type": "update", "table": "sessions", "data": {"user_id": 123}}
    ]
    success = db_manager.execute_transaction(operations)
```

### 2. Connection Management

**RULE**: Always use connection pooling and proper error handling.

**PATTERN**:
```python
try:
    # Database operation
    result = db_manager.execute_query(query, params)
except Exception as e:
    # Log error and handle gracefully
    custom_log(f"Database error: {e}", level="ERROR")
    # Implement fallback or retry logic
```

## Caching Rules

### 1. RedisManager Usage

**RULE**: All caching operations must use `RedisManager`.

**PATTERN**:
```python
# Get Redis manager
redis_manager = app_manager.get_redis_manager()

# Check connection
if redis_manager.ping():
    # Set value with TTL
    redis_manager.set("cache_key", {"data": "value"}, ttl=3600)
    
    # Get value
    cached_data = redis_manager.get("cache_key")
    
    # Publish message
    redis_manager.publish("channel_name", {"event": "data"})
```

### 2. Caching Strategy

**RULE**: Implement proper caching strategies:
- Use consistent cache key naming
- Set appropriate TTL for cached data
- Implement cache invalidation strategies
- Monitor cache memory usage

## Security Rules

### 1. VaultManager Integration

**RULE**: All sensitive data must be retrieved through `VaultManager`.

**PATTERN**:
```python
# Get Vault manager
vault_manager = app_manager.vault_manager

# Get secrets
try:
    db_password = vault_manager.get_secret_value("flask-app/mongodb", "root_password")
    jwt_secret = vault_manager.get_secret_value("flask-app/app", "secret_key")
except Exception as e:
    # Handle Vault errors
    custom_log(f"Vault error: {e}", level="ERROR")
```

### 2. Rate Limiting

**RULE**: All endpoints must implement rate limiting through `RateLimiterManager`.

**PATTERN**:
```python
# Get rate limiter manager
rate_limiter = app_manager.rate_limiter_manager

# Check rate limits
result = rate_limiter.check_rate_limit(['ip', 'user', 'api_key'])
if not result['allowed']:
    return jsonify({"error": "Rate limit exceeded"}), 429
```

## API Development Rules

### 1. Action Discovery

**RULE**: All API actions must be registered through `ActionDiscoveryManager`.

**PATTERN**:
```python
# Get action discovery manager
action_manager = app_manager.action_discovery_manager

# Discover actions
action_manager.discover_all_actions()

# Find and execute action
action_info = action_manager.find_action("action_name")
if action_info:
    args = {"param1": "value1", "param2": "value2"}
    result = action_manager.execute_action_logic(action_info, args)
```

### 2. Error Handling

**RULE**: All API endpoints must include comprehensive error handling.

**PATTERN**:
```python
@app.route('/api/endpoint', methods=['POST'])
def api_endpoint():
    try:
        # Validate input
        data = request.get_json()
        if not data:
            return jsonify({"error": "Invalid input"}), 400
        
        # Process request
        result = process_request(data)
        
        return jsonify({"success": True, "data": result})
        
    except ValidationError as e:
        return jsonify({"error": str(e)}), 400
    except DatabaseError as e:
        custom_log(f"Database error: {e}", level="ERROR")
        return jsonify({"error": "Internal server error"}), 500
    except Exception as e:
        custom_log(f"Unexpected error: {e}", level="ERROR")
        return jsonify({"error": "Internal server error"}), 500
```

## WebSocket Rules

### 1. WebSocketManager Usage

**RULE**: All WebSocket operations must use `WebSocketManager`.

**PATTERN**:
```python
# Get WebSocket manager
ws_manager = app_manager.get_websocket_manager()

# Initialize with Flask app
ws_manager.initialize(app)

# Emit to room
ws_manager.emit_to_room("room_name", "event_name", {"data": "value"})

# Join room
ws_manager.join_room("room_name", sid="socket_id")

# Get room info
room_info = ws_manager.get_room_info("room_name")
```

## File Organization Rules

### 1. Directory Structure

**RULE**: Follow the established directory structure:

```
python_base_04/
├── app.py                          # Flask application entry point
├── core/                           # Core application components
│   ├── managers/                   # All managers
│   │   ├── app_manager.py
│   │   ├── state_manager.py
│   │   ├── database_manager.py
│   │   ├── redis_manager.py
│   │   ├── jwt_manager.py
│   │   ├── api_key_manager.py
│   │   ├── vault_manager.py
│   │   ├── rate_limiter_manager.py
│   │   ├── action_discovery_manager.py
│   │   ├── websockets/
│   │   │   └── websocket_manager.py
│   │   ├── module_manager.py
│   │   ├── services_manager.py
│   │   └── hooks_manager.py
│   ├── modules/                    # Feature modules
│   │   ├── module_name/
│   │   │   ├── __init__.py
│   │   │   ├── module.py
│   │   │   ├── models.py
│   │   │   ├── services.py
│   │   │   └── utils.py
│   └── validators/                 # Input validation
├── static/                         # Static files
├── templates/                      # HTML templates
├── tools/                          # Utility tools
├── utils/                          # Utility functions
├── requirements.txt                # Python dependencies
├── Dockerfile                      # Container configuration
└── config.py                       # Configuration management
```

### 2. File Naming

**RULE**: Follow consistent naming conventions:
- Files: `snake_case.py`
- Classes: `PascalCase`
- Variables/Functions: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`

## Code Quality Rules

### 1. Error Handling

**RULE**: All functions must include proper error handling.

**PATTERN**:
```python
def function_name(param1, param2):
    try:
        # Function logic
        result = perform_operation(param1, param2)
        return result
    except SpecificException as e:
        custom_log(f"Specific error in function: {e}", level="ERROR")
        # Handle specific error
        raise
    except Exception as e:
        custom_log(f"Unexpected error in function: {e}", level="ERROR")
        # Handle general error
        raise
```

### 2. Logging

**RULE**: Use the built-in `custom_log` function for all logging.

**PATTERN**:
```python
from utils.logging_utils import custom_log

# Log different levels
custom_log("Information message", level="INFO")
custom_log("Warning message", level="WARNING")
custom_log("Error message", level="ERROR")
custom_log("Debug message", level="DEBUG")
```

### 3. Documentation

**RULE**: All public APIs must include documentation.

**PATTERN**:
```python
def function_name(param1: str, param2: int) -> Dict[str, Any]:
    """
    Brief description of the function.
    
    Args:
        param1 (str): Description of parameter 1
        param2 (int): Description of parameter 2
    
    Returns:
        Dict[str, Any]: Description of return value
    
    Raises:
        ValueError: When parameters are invalid
        DatabaseError: When database operation fails
    
    Example:
        >>> result = function_name("example", 123)
        >>> print(result)
        {'status': 'success'}
    """
    # Implementation
    pass
```

## Configuration Rules

### 1. Configuration Management

**RULE**: Use the existing `Config` class for all configuration.

**PATTERN**:
```python
from config import Config

# Use configuration values
debug_mode = Config.DEBUG
jwt_secret = Config.JWT_SECRET_KEY
database_url = Config.DATABASE_URL
```

### 2. Environment Variables

**RULE**: Use the established configuration priority:
1. Secret Files (Kubernetes secrets)
2. Vault (production secure source)
3. Environment Variables
4. Default Values

## Testing Rules

### 1. Test Structure

**RULE**: All new features must include tests.

**PATTERN**:
```
tests/
├── unit/                          # Unit tests
├── integration/                   # Integration tests
├── api/                          # API tests
└── performance/                  # Performance tests
```

### 2. Test Naming

**RULE**: Test files must be named `test_*.py` and follow naming conventions.

**PATTERN**:
```python
# tests/unit/test_manager.py
import unittest
from core.managers.state_manager import StateManager

class TestStateManager(unittest.TestCase):
    def test_register_state(self):
        """Test state registration"""
        # Test implementation
        pass
    
    def test_update_state(self):
        """Test state updates"""
        # Test implementation
        pass
```

## Performance Rules

### 1. Connection Management

**RULE**: Use connection pooling for database and Redis connections.

**PATTERN**:
```python
# Database connection pooling
db_manager = app_manager.get_db_manager(role="read_write")
# Connection is automatically pooled

# Redis connection pooling
redis_manager = app_manager.get_redis_manager()
# Connection is automatically pooled
```

### 2. Caching Strategy

**RULE**: Implement strategic caching for frequently accessed data.

**PATTERN**:
```python
# Cache frequently accessed data
cache_key = f"user:{user_id}:profile"
cached_profile = redis_manager.get(cache_key)

if not cached_profile:
    # Fetch from database
    profile = db_manager.execute_query("SELECT * FROM users WHERE id = %s", {"id": user_id})
    # Cache for 1 hour
    redis_manager.set(cache_key, profile, ttl=3600)
    cached_profile = profile
```

## Security Rules

### 1. Input Validation

**RULE**: All inputs must be validated and sanitized.

**PATTERN**:
```python
from core.validators import validate_input

def api_endpoint():
    data = request.get_json()
    
    # Validate input
    validation_result = validate_input(data, required_fields=["username", "email"])
    if not validation_result["valid"]:
        return jsonify({"error": validation_result["errors"]}), 400
    
    # Process validated data
    process_data(data)
```

### 2. SQL Injection Protection

**RULE**: Always use parameterized queries.

**PATTERN**:
```python
# Correct - parameterized query
result = db_manager.execute_query(
    "SELECT * FROM users WHERE id = %s AND status = %s",
    {"id": user_id, "status": "active"}
)

# Incorrect - string formatting (vulnerable to SQL injection)
# result = db_manager.execute_query(f"SELECT * FROM users WHERE id = {user_id}")
```

## AI Interaction Rules

### 1. Approval Process

**RULE**: Before creating any new manager, module, or service, ask the user for approval.

**PROCESS**:
1. Explain why the new component is needed
2. Describe its responsibilities and dependencies
3. Show how it fits into the existing architecture
4. Wait for user approval before implementation

### 2. Architecture Compliance

**RULE**: All code must follow the established architecture patterns.

**CHECKLIST**:
- [ ] Uses appropriate manager for functionality
- [ ] Follows module structure if applicable
- [ ] Uses StateManager for state management
- [ ] Includes proper error handling
- [ ] Uses built-in logging
- [ ] Follows naming conventions
- [ ] Includes documentation
- [ ] Implements security best practices

### 3. Code Generation

**RULE**: When generating code, always include:
- Proper imports
- Error handling
- Logging statements
- Documentation comments
- Type hints
- Security considerations

### 4. File Organization

**RULE**: When creating new files, place them in the appropriate directory:
- Managers → `core/managers/`
- Modules → `core/modules/`
- Services → `core/services/` or `services/`
- Models → `core/models/` or `models/`
- Validators → `core/validators/`
- Utils → `utils/`

## Globs and Patterns

### 1. File Matching Patterns

**RULE**: Use these glob patterns for file operations:

```
# All Python files
**/*.py

# All manager files
core/managers/*.py

# All module files
core/modules/**/*.py

# All test files
tests/**/test_*.py

# All configuration files
**/*.yaml
**/*.yml
**/*.json
**/*.env
**/*.ini
**/*.cfg
```

### 2. Search Patterns

**RULE**: Use these patterns for searching specific components:

```
# Find all managers
class *Manager:

# Find all modules
class *Module(BaseModule):

# Find all services
class *Service:

# Find all API endpoints
@app.route

# Find all database queries
db_manager.execute_query

# Find all Redis operations
redis_manager.get
redis_manager.set
```

## Exception Handling

### 1. Custom Exceptions

**RULE**: Create custom exceptions for specific error cases.

**PATTERN**:
```python
class ModuleException(Exception):
    def __init__(self, message: str, module_name: str):
        self.message = message
        self.module_name = module_name
        super().__init__(f"ModuleException in {module_name}: {message}")

class ValidationException(Exception):
    def __init__(self, message: str, field: str = None):
        self.message = message
        self.field = field
        super().__init__(f"Validation error{f' in {field}' if field else ''}: {message}")
```

### 2. Exception Propagation

**RULE**: Properly propagate exceptions with context.

**PATTERN**:
```python
try:
    # Operation
    result = perform_operation()
except Exception as e:
    custom_log(f"Operation failed: {e}", level="ERROR")
    # Re-raise with context
    raise ModuleException(f"Failed to perform operation: {e}", "module_name")
```

## Documentation Requirements

### 1. Code Documentation

**RULE**: All public APIs must be documented.

**REQUIRED ELEMENTS**:
- Function/class purpose
- Parameter descriptions
- Return value descriptions
- Usage examples
- Error conditions
- Type hints

### 2. Architecture Documentation

**RULE**: New architectural components must be documented in the appropriate documentation files.

**FILES TO UPDATE**:
- `Documentation/python_base_04/ARCHITECTURE.md`
- `Documentation/python_base_04/MANAGERS.md`
- `Documentation/python_base_04/API_REFERENCE.md`

## Compliance Checklist

Before submitting any code, ensure compliance with:

- [ ] Manager-based architecture
- [ ] Module system usage
- [ ] StateManager for state management
- [ ] Proper error handling
- [ ] Logging implementation
- [ ] Documentation included
- [ ] Tests written
- [ ] Security considerations
- [ ] Performance optimization
- [ ] File organization
- [ ] Naming conventions
- [ ] Type hints included
- [ ] Input validation
- [ ] SQL injection protection

## Summary

This MDC file defines the comprehensive rules for AI-assisted development in the Python Base 04 project. All AI interactions must follow these patterns, ask for approval before creating new architectural components, and maintain the established code quality and security standards.

The key principles are:
1. **Manager-based architecture** for all functionality
2. **Module system** for feature organization
3. **StateManager** for state management
4. **Proper error handling and logging**
5. **Security-first approach**
6. **Comprehensive documentation**
7. **Approval process for new components**
8. **Type hints and input validation**
9. **Performance optimization**
10. **Testing requirements**

Follow these rules to maintain code quality, consistency, and architectural integrity.