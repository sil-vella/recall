import 'dart:async';
import 'dart:io';

class Logger {
  // Private constructor
  Logger._();

  // The single instance of Logger
  static final Logger _instance = Logger._();

  // Factory constructor to return the same instance
  factory Logger() {
    return _instance;
  }

  // Logging switch for this module (like Python LOGGING_SWITCH)
  static const bool CUSTOM_LOGGING_ENABLED = true; // Enabled for debugging

  // Log file path - same as Python server log
  static const String _logFileName = '/Users/sil/Documents/Work/reignofplay/Dutch/app_dev/python_base_04/tools/logger/server.log';
  late File _logFile;
  bool _initialized = false;

  /// Initialize the logger with log file
  void initialize() {
    if (_initialized) return;

    try {
      _logFile = File(_logFileName);
      _initialized = true;

      // Log initialization (deferred so init returns immediately)
      info('🚀 Logger initialized - logging to $_logFileName', isOn: true);
    } catch (e) {
      print('❌ Failed to initialize logger: $e');
    }
  }

  /// General log method. I/O runs in a microtask so call flow is not blocked.
  void log(String message, {
    String name = 'Logger',
    Object? error,
    StackTrace? stackTrace,
    int level = 0,
    bool isOn = false,
  }) {
    if (!CUSTOM_LOGGING_ENABLED && !isOn) return;

    final timestamp = DateTime.now().toIso8601String();
    final levelStr = _getLevelString(level);
    final logEntry = '[$timestamp] [$levelStr] [$name] $message';
    final errorEntry = error != null ? '[$timestamp] [ERROR] [$name] Error: $error' : null;
    final doPrint = isOn || level >= 800;

    scheduleMicrotask(() {
      if (doPrint) {
        print(logEntry);
        if (errorEntry != null) print(errorEntry);
      }
      _writeToFile(logEntry);
      if (errorEntry != null) _writeToFile(errorEntry);
    });
  }

  /// Log an informational message
  void info(String message, {bool isOn = false}) {
    log(message, level: 800, isOn: isOn);
  }

  /// Log a warning message
  void warning(String message, {bool isOn = false}) {
    log(message, level: 900, isOn: isOn);
  }

  /// Log a debug message
  void debug(String message, {bool isOn = false}) {
    log(message, level: 500, isOn: isOn);
  }

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace, bool isOn = true}) {
    log(message, level: 1000, error: error, stackTrace: stackTrace, isOn: isOn);
  }

  /// Log connection events
  void connection(String message, {bool isOn = true}) {
    log(message, name: 'Connection', level: 800, isOn: isOn);
  }

  /// Log WebSocket events
  void websocket(String message, {bool isOn = true}) {
    log(message, name: 'WebSocket', level: 800, isOn: isOn);
  }

  /// Log authentication events
  void auth(String message, {bool isOn = true}) {
    log(message, name: 'Auth', level: 800, isOn: isOn);
  }

  /// Log game events
  void game(String message, {bool isOn = true}) {
    log(message, name: 'Game', level: 800, isOn: isOn);
  }

  /// Log room events
  void room(String message, {bool isOn = true}) {
    log(message, name: 'Room', level: 800, isOn: isOn);
  }

  /// Write to log file
  void _writeToFile(String message) {
    if (!_initialized) return;
    
    try {
      // Format: [timestamp] [DART] [level] message (same format as Flutter logs)
      final timestamp = DateTime.now().toIso8601String();
      final formattedMessage = message.replaceFirst('[', '[$timestamp] [DART] [');
      _logFile.writeAsStringSync('$formattedMessage\n', mode: FileMode.append);
    } catch (e) {
      print('❌ Failed to write to log file: $e');
    }
  }

  /// Convert level number to string
  String _getLevelString(int level) {
    if (level >= 1000) return 'ERROR';
    if (level >= 900) return 'WARNING';
    if (level >= 800) return 'INFO';
    return 'DEBUG';
  }

  /// Get log file path
  String get logFilePath => _logFileName;

  /// Check if logger is initialized
  bool get isInitialized => _initialized;
}
