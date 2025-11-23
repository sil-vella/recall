# Logging System Documentation

## Overview

The Flutter Base 05 application implements a sophisticated logging system that provides structured, configurable, and efficient logging throughout the application. The system supports multiple log levels, remote logging capabilities, and granular control over when logging occurs.

## Architecture

### Core Components

1. **Logger Class** (`lib/tools/logging/logger.dart`)
   - Centralized logging interface
   - Configurable log levels and output
   - Remote logging support via HTTP
   - Singleton pattern for consistent usage

2. **Configuration System** (`lib/utils/consts/config.dart`)
   - Environment-based logging configuration
   - Remote logging toggle
   - Platform-specific settings

3. **Logging Integration**
   - Automatic integration with all managers
   - Module-specific logging
   - Service-level logging
   - Screen and widget logging

## Logger Class

### Class Definition

```dart
class Logger {
  // Private constructor
  Logger._();

  // The single instance of Logger
  static final Logger _instance = Logger._();

  // Factory constructor to return the same instance
  factory Logger() {
    return _instance;
  }
}
```

### Key Features

- **Singleton Pattern**: Single instance across the application
- **Configurable Logging**: Respects `Config.loggerOn` setting
- **Remote Logging**: Optional HTTP-based remote logging
- **Log Levels**: Multiple log levels for different types of messages
- **Force Logging**: Override configuration for critical messages
- **Structured Logging**: Consistent log format across the application

## Logging Methods

### Basic Logging Methods

#### `void info(String message, {bool isOn = false})`
Logs an informational message.

**Parameters**:
- `message` (String): Message to log
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
final logger = Logger();
logger.info("User logged in successfully");
logger.info("Critical system event", isOn: true);
```

#### `void debug(String message, {bool isOn = false})`
Logs a debug message.

**Parameters**:
- `message` (String): Debug message to log
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
logger.debug("Processing user data");
logger.debug("Debug information", isOn: true);
```

#### `void warning(String message, {bool isOn = false})`
Logs a warning message.

**Parameters**:
- `message` (String): Warning message to log
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
logger.warning("API response took longer than expected");
logger.warning("Critical warning", isOn: true);
```

#### `void error(String message, {Object? error, StackTrace? stackTrace, bool isOn = false})`
Logs an error message with optional error details.

**Parameters**:
- `message` (String): Error message to log
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
try {
  // Some operation
} catch (e, stackTrace) {
  logger.error("Operation failed", error: e, stackTrace: stackTrace);
  logger.error("Critical error", error: e, isOn: true);
}
```

### Advanced Logging Methods

#### `void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false})`
General log method that respects configuration.

**Parameters**:
- `message` (String): Message to log
- `name` (String): Logger name (default: 'AppLogger')
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `level` (int): Log level (default: 0)
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
logger.log("Custom log message", level: 500, isOn: true);
```

#### `void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false})`
Forces a log message regardless of configuration.

**Parameters**:
- `message` (String): Message to log
- `name` (String): Logger name (default: 'AppLogger')
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `level` (int): Log level (default: 0)
- `isOn` (bool): Force logging regardless of configuration (default: false)

**Example**:
```dart
logger.forceLog("Critical system message", level: 1000);
```

## Configuration System

### Environment Configuration

The logging system uses environment-based configuration:

```dart
class Config {
  static const bool loggerOn = bool.fromEnvironment(
    'LOGGER_ON',
    defaultValue: true,
  );
  
  static const bool enableRemoteLogging = bool.fromEnvironment(
    'ENABLE_REMOTE_LOGGING',
    defaultValue: false,
  );
  
  static const String apiUrl = String.fromEnvironment(
    'API_URL_LOCAL',
    defaultValue: 'http://10.0.2.2:8081',
  );
}
```

### Configuration Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `LOGGER_ON` | Enable/disable logging | `true` |
| `ENABLE_REMOTE_LOGGING` | Enable remote logging | `false` |
| `API_URL_LOCAL` | API base URL for remote logging | `http://10.0.2.2:8081` |

### Build Configuration

```bash
# Enable logging
flutter run --dart-define=LOGGER_ON=true

# Disable logging
flutter run --dart-define=LOGGER_ON=false

# Enable remote logging
flutter run --dart-define=ENABLE_REMOTE_LOGGING=true

# Custom API URL for remote logging
flutter run --dart-define=API_URL_LOCAL=https://api.example.com
```

## Log Levels

### Level Hierarchy

The logging system uses numeric levels with the following hierarchy:

| Level | Name | Description | Usage |
|-------|------|-------------|-------|
| 500 | DEBUG | Debug information | Development debugging |
| 800 | INFO | Informational messages | General information |
| 900 | WARNING | Warning messages | Potential issues |
| 1000 | ERROR | Error messages | Errors and exceptions |

### Level Conversion

```dart
String _getLevelString(int level) {
  if (level >= 1000) return 'ERROR';
  if (level >= 900) return 'WARNING';
  if (level >= 800) return 'INFO';
  return 'DEBUG';
}
```

## Remote Logging

### HTTP-Based Remote Logging

The system supports sending logs to a remote server via HTTP POST requests:

```dart
void _sendToServer({required int level, required String message, Object? error, StackTrace? stack}) {
  try {
    final payload = <String, dynamic>{
      'message': message,
      'level': _getLevelString(level),
      'source': 'frontend',
      'platform': Config.platform,
      'buildMode': Config.buildMode,
      'timestamp': DateTime.now().toIso8601String(),
      if (error != null) 'error': error.toString(),
      if (stack != null) 'stack': stack.toString(),
    };

    // Send to server log endpoint - fire and forget
    _sendHttpLog(payload).catchError((e) {
      // Silently fail - don't want logging errors to break the app
    });
  } catch (e) {
    // Don't log errors from logging to avoid infinite loops
  }
}
```

### Remote Logging Payload

```json
{
  "message": "User logged in successfully",
  "level": "INFO",
  "source": "frontend",
  "platform": "android",
  "buildMode": "debug",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "error": "Optional error details",
  "stack": "Optional stack trace"
}
```

## Usage Patterns

### Basic Usage

```dart
class MyModule extends ModuleBase {
  static final Logger _logger = Logger();
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    _log.info("Module initialized");
  }
  
  void performOperation() {
    try {
      _log.debug("Starting operation");
      // Perform operation
      _log.info("Operation completed successfully");
    } catch (e, stackTrace) {
      _log.error("Operation failed", error: e, stackTrace: stackTrace);
    }
  }
}
```

### State-Aware Logging

```dart
class StateAwareWidget extends StatelessWidget {
  static final Logger _logger = Logger();
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState<Map<String, dynamic>>('module');
        final isEnabled = state?['isEnabled'] ?? false;
        
        _log.debug("Widget state changed: isEnabled=$isEnabled");
        
        return Container(
          color: isEnabled ? Colors.green : Colors.red,
          child: Text(isEnabled ? 'Enabled' : 'Disabled'),
        );
      },
    );
  }
}
```

### Critical Logging with Force Override

```dart
class CriticalSystem {
  static final Logger _logger = Logger();
  
  void handleCriticalEvent() {
    // This will log even if Config.loggerOn is false
    _log.info("Critical system event occurred", isOn: true);
    
    // This will always log regardless of configuration
    _log.forceLog("System shutdown initiated", level: 1000);
  }
}
```

### Error Handling with Logging

```dart
class ApiService {
  static final Logger _logger = Logger();
  
  Future<Map<String, dynamic>> fetchData() async {
    try {
      _log.debug("Starting API request");
      
      final response = await http.get(Uri.parse('${Config.apiUrl}/data'));
      
      if (response.statusCode == 200) {
        _log.info("API request successful");
        return jsonDecode(response.body);
      } else {
        _log.warning("API request failed with status: ${response.statusCode}");
        throw Exception('API request failed');
      }
    } catch (e, stackTrace) {
      _log.error("API request error", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
```

## Integration Examples

### Main Application Logging

```dart
class _MyAppState extends State<MyApp> {
  final Logger _logger = Logger();
  final bool _enableTestLog = true;
  
  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) {
      return;
    }
    
    setState(() {
      _isInitializing = true;
    });

    try {
      final appManager = Provider.of<AppManager>(context, listen: false);
      final navigationManager = Provider.of<NavigationManager>(context, listen: false);

      // Set up navigation callback first
      navigationManager.setNavigationCallback((route) {
        final router = navigationManager.router;
        router.go(route);
      });
      
      // Initialize the app and wait for completion
      if (!appManager.isInitialized) {
        await appManager.initializeApp(context);
      }

      // Trigger rebuild after initialization is complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        
        // Test log after app is fully loaded
        _logger.info('🚀 App fully loaded and initialized successfully!', isOn: _enableTestLog);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }
}
```

### Manager Logging

```dart
class StateManager with ChangeNotifier {
  static final Logger _logger = Logger();
  
  void registerModuleState(String moduleKey, Map<String, dynamic> initialState) {
    _moduleStates[moduleKey] = ModuleState(state: initialState);
    notifyListeners();
  }
  
  void updateModuleState(String moduleKey, Map<String, dynamic> newState, {bool force = false}) {
    if (!_moduleStates.containsKey(moduleKey) && !force) {
      return;
    }
    
    final currentState = _moduleStates[moduleKey]?.state ?? {};
    final mergedState = {...currentState, ...newState};
    _moduleStates[moduleKey] = ModuleState(state: mergedState);
    notifyListeners();
  }
}
```

### Service Logging

```dart
class SharedPrefManager extends ServicesBase {
  static final Logger _logger = Logger();
  
  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }
  
  Future<void> clear() async {
    await _prefs?.clear();
  }
}
```

## Best Practices

### 1. Logging Levels

- **DEBUG**: Use for detailed debugging information
- **INFO**: Use for general information about application flow
- **WARNING**: Use for potential issues that don't break functionality
- **ERROR**: Use for errors and exceptions that need attention

### 2. Performance Considerations

- Use `isOn: true` sparingly for critical messages only
- Avoid logging in tight loops or frequently called methods
- Use structured logging for better performance
- Consider the impact of remote logging on network usage

### 3. Error Handling

- Always include error objects and stack traces for errors
- Use meaningful error messages
- Don't log sensitive information
- Handle logging errors gracefully

### 4. Configuration Management

- Use environment variables for logging configuration
- Provide sensible defaults
- Allow runtime configuration changes where appropriate
- Document all configuration options

### 5. Remote Logging

- Use remote logging for production environments
- Implement proper error handling for network failures
- Consider log volume and storage costs
- Use structured logging for better analysis

## Troubleshooting

### Common Issues

1. **Logs not appearing**
   - Check `Config.loggerOn` setting
   - Verify logger initialization
   - Check for configuration overrides

2. **Remote logging not working**
   - Verify `Config.enableRemoteLogging` is true
   - Check API URL configuration
   - Verify network connectivity
   - Check server endpoint availability

3. **Performance issues**
   - Reduce log volume
   - Use appropriate log levels
   - Consider disabling remote logging in development
   - Optimize log message content

### Debug Tools

```dart
// Check logging configuration
print("Logger enabled: ${Config.loggerOn}");
print("Remote logging enabled: ${Config.enableRemoteLogging}");

// Test logging
final logger = Logger();
logger.info("Test message");
logger.info("Force test message", isOn: true);
```

## Security Considerations

### Sensitive Data

- Never log passwords, tokens, or sensitive user data
- Use placeholder values for sensitive information
- Implement log filtering for production environments
- Consider data retention policies

### Remote Logging Security

- Use HTTPS for remote logging endpoints
- Implement proper authentication
- Consider log encryption
- Monitor for security vulnerabilities

## Conclusion

The Flutter Base 05 logging system provides a comprehensive, configurable, and efficient logging solution for the application. It supports multiple log levels, remote logging capabilities, and granular control over when logging occurs.

Key benefits:

- **Structured Logging**: Consistent log format across the application
- **Configurable**: Environment-based configuration
- **Performance**: Efficient logging that doesn't impact app performance
- **Remote Support**: Optional remote logging for production environments
- **Force Override**: Ability to force critical logs regardless of configuration
- **Integration**: Seamless integration with all application components

For additional information about specific components or usage patterns, refer to the individual documentation files or the source code comments.
