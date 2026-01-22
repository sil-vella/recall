# Logging System Documentation

## Overview

The Flutter Base 05 application implements a structured logging system that provides configurable and efficient logging throughout the application. The system supports multiple log levels, console output, and centralized log file writing via launch scripts.

## Architecture

### Core Components

1. **Logger Class** (`lib/tools/logging/logger.dart`)
   - Centralized logging interface
   - Configurable log levels and output
   - Prints to stdout/stderr (captured by launch scripts)
   - Singleton pattern for consistent usage
   - **Note**: Logger does NOT write directly to files - launch scripts handle file writing

2. **Launch Scripts** (`playbooks/frontend/launch_*.sh`)
   - Capture Flutter stdout/stderr output
   - Filter and format log messages
   - Write formatted logs to `server.log`
   - Support for Chrome web and Android devices

3. **Configuration System** (`lib/utils/consts/config.dart`)
   - Environment-based logging configuration
   - Platform-specific settings

4. **Logging Integration**
   - Automatic integration with all managers
   - Module-specific logging with `LOGGING_SWITCH` constants
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
- **Configurable Logging**: Respects `Config.loggerOn` setting and `isOn` parameter
- **Console Output**: Prints formatted logs to stdout/stderr
- **Log Levels**: Multiple log levels for different types of messages (DEBUG, INFO, WARNING, ERROR)
- **Conditional Logging**: Use `if (LOGGING_SWITCH)` pattern before log calls
- **Force Logging**: Override configuration for critical messages
- **Structured Logging**: Consistent log format: `[timestamp] [LEVEL] [AppLogger] message`
- **File Writing**: Handled by launch scripts, not the Logger class

## Logging Methods

### Basic Logging Methods

#### `void info(String message, {bool? isOn})`
Logs an informational message.

**Parameters**:
- `message` (String): Message to log
- `isOn` (bool?): Force logging if `true`, skip if `false`, use `Config.loggerOn` if `null` (default: null)

**Example**:
```dart
final logger = Logger();
logger.info("User logged in successfully"); // Uses Config.loggerOn
logger.info("Critical system event", isOn: true); // Always logs
logger.info("Debug info", isOn: false); // Never logs
```

#### `void debug(String message, {bool? isOn})`
Logs a debug message.

**Parameters**:
- `message` (String): Debug message to log
- `isOn` (bool?): Force logging if `true`, skip if `false`, use `Config.loggerOn` if `null` (default: null)

**Example**:
```dart
logger.debug("Processing user data"); // Uses Config.loggerOn
logger.debug("Debug information", isOn: true); // Always logs
```

#### `void warning(String message, {bool? isOn})`
Logs a warning message.

**Parameters**:
- `message` (String): Warning message to log
- `isOn` (bool?): Force logging if `true`, skip if `false`, use `Config.loggerOn` if `null` (default: null)

**Example**:
```dart
logger.warning("API response took longer than expected"); // Uses Config.loggerOn
logger.warning("Critical warning", isOn: true); // Always logs
```

#### `void error(String message, {Object? error, StackTrace? stackTrace, bool? isOn})`
Logs an error message with optional error details.

**Parameters**:
- `message` (String): Error message to log
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `isOn` (bool?): Force logging if `true`, skip if `false`, use `Config.loggerOn` if `null` (default: null)

**Example**:
```dart
try {
  // Some operation
} catch (e, stackTrace) {
  logger.error("Operation failed", error: e, stackTrace: stackTrace); // Uses Config.loggerOn
  logger.error("Critical error", error: e, isOn: true); // Always logs
}
```

### Advanced Logging Methods

#### `void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool? isOn})`
General log method that respects configuration.

**Parameters**:
- `message` (String): Message to log
- `name` (String): Logger name (default: 'AppLogger')
- `error` (Object?): Error object (optional)
- `stackTrace` (StackTrace?): Stack trace (optional)
- `level` (int): Log level (default: 0)
- `isOn` (bool?): Force logging if `true`, skip if `false`, use `Config.loggerOn` if `null` (default: null)

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

## File Logging via Launch Scripts

### How It Works

The Logger class prints formatted logs to stdout/stderr. Launch scripts capture this output and write it to `server.log`:

1. **Logger prints to stdout**: `[timestamp] [LEVEL] [AppLogger] message`
2. **Launch script captures output**: Scripts pipe Flutter output through `filter_logs()` function
3. **Script writes to file**: Formatted logs are appended to `python_base_04/tools/logger/server.log`

### Launch Scripts

#### Chrome Web (`playbooks/frontend/launch_chrome.sh`)
- Captures Flutter web output
- Filters logs matching pattern: `[.*] [.*] [AppLogger]`
- Writes to `server.log` without filtering (all logs included)
- Displays colored output in terminal

#### Android Device (`playbooks/frontend/launch_oneplus.sh`)
- Captures Flutter Android output via ADB
- Same filtering and writing logic as Chrome script
- Supports local and VPS backend configurations

### Log Format

The launch scripts expect logs in this format:
```
[timestamp] [LEVEL] [AppLogger] message
```

Example:
```
[2026-01-22T12:54:31.562] [INFO] [AppLogger] 🎬 DutchGameStateUpdater: Handler callback invoked with keys: [messages]
```

The scripts extract:
- **Timestamp**: First bracket group
- **Level**: Second bracket group (DEBUG, INFO, WARNING, ERROR)
- **Message**: Everything after `[AppLogger] `

And write to `server.log` as:
```
[timestamp] [LEVEL] message
```

### Viewing Logs

```bash
# View all logs
tail -f python_base_04/tools/logger/server.log

# Filter specific logs
tail -f python_base_04/tools/logger/server.log | grep "DutchGameStateUpdater"

# View last 100 lines
tail -n 100 python_base_04/tools/logger/server.log
```

## Usage Patterns

### Recommended Pattern: `if (LOGGING_SWITCH)`

The current codebase uses a pattern where modules define a `LOGGING_SWITCH` constant and wrap log calls:

```dart
class MyModule extends ModuleBase {
  static final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Enable/disable logging for this module
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    if (LOGGING_SWITCH) {
      _logger.info("Module initialized");
    }
  }
  
  void performOperation() {
    try {
      if (LOGGING_SWITCH) {
        _logger.debug("Starting operation");
      }
      // Perform operation
      if (LOGGING_SWITCH) {
        _logger.info("Operation completed successfully");
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error("Operation failed", error: e, stackTrace: stackTrace);
      }
    }
  }
}
```

**Benefits**:
- Module-level control over logging
- Easy to enable/disable logging for specific modules
- No need to pass `isOn` parameter to every log call
- Compile-time optimization (dead code elimination)

### Basic Usage (Alternative)

```dart
class MyModule extends ModuleBase {
  static final Logger _logger = Logger();
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    _logger.info("Module initialized"); // Uses Config.loggerOn
  }
  
  void performOperation() {
    try {
      _logger.debug("Starting operation");
      // Perform operation
      _logger.info("Operation completed successfully");
    } catch (e, stackTrace) {
      _logger.error("Operation failed", error: e, stackTrace: stackTrace);
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
  static const bool LOGGING_SWITCH = false;
  
  void handleCriticalEvent() {
    // Using LOGGING_SWITCH pattern
    if (LOGGING_SWITCH) {
      _logger.info("Critical system event occurred");
    }
    
    // Force log regardless of configuration
    _logger.forceLog("System shutdown initiated", level: 1000);
    
    // Or use isOn parameter
    _logger.info("Critical event", isOn: true); // Always logs
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

### 5. File Logging

- Logs are written to `server.log` via launch scripts
- Ensure launch scripts are running to capture logs
- Use `LOGGING_SWITCH` pattern for module-level control
- All logs appear in `server.log` when using launch scripts

## Troubleshooting

### Common Issues

1. **Logs not appearing**
   - Check `Config.loggerOn` setting
   - Verify logger initialization
   - Check for configuration overrides

2. **Logs not appearing in server.log**
   - Ensure you're using a launch script (`launch_chrome.sh` or `launch_oneplus.sh`)
   - Check that `LOGGING_SWITCH` is `true` in the module
   - Verify `Config.loggerOn` is `true` (if not using `isOn` parameter)
   - Check that logs match the expected format: `[timestamp] [LEVEL] [AppLogger] message`
   - Verify `server.log` file path is correct: `python_base_04/tools/logger/server.log`

3. **Performance issues**
   - Reduce log volume by setting `LOGGING_SWITCH = false` in modules
   - Use appropriate log levels
   - Use `if (LOGGING_SWITCH)` pattern for compile-time optimization
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

### File Logging Security

- `server.log` contains application logs - protect file permissions
- Consider log rotation to prevent large files
- Be aware that logs may contain sensitive information
- Review log content before sharing or committing

## Conclusion

The Flutter Base 05 logging system provides a comprehensive, configurable, and efficient logging solution for the application. It supports multiple log levels, console output, and centralized file logging via launch scripts.

Key benefits:

- **Structured Logging**: Consistent log format across the application
- **Configurable**: Environment-based configuration and module-level `LOGGING_SWITCH` constants
- **Performance**: Efficient logging with compile-time optimization via `if (LOGGING_SWITCH)` pattern
- **File Logging**: Centralized log file writing via launch scripts
- **Force Override**: Ability to force critical logs using `isOn: true` or `forceLog()`
- **Integration**: Seamless integration with all application components

### Current Architecture Summary

1. **Logger Class**: Prints formatted logs to stdout/stderr
2. **Launch Scripts**: Capture stdout, filter, and write to `server.log`
3. **Module Pattern**: Use `LOGGING_SWITCH` constant with `if (LOGGING_SWITCH)` before log calls
4. **Log Format**: `[timestamp] [LEVEL] [AppLogger] message`

For additional information about specific components or usage patterns, refer to the individual documentation files or the source code comments.
