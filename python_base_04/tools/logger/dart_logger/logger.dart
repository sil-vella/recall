import 'dart:developer' as developer;
import 'dart:io';

class Logger {
  // Private constructor
  Logger._();

  // The single instance of Logger
  static final Logger _instance = Logger._();
  
  // Path to server.log file (from dart_services directory: ../../../../../tools/logger/server.log)
  static const String _serverLogPath = '../../../../../tools/logger/server.log';

  // Factory constructor to return the same instance
  factory Logger() {
    return _instance;
  }

  /// General log method that respects `Config.loggerOn`
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false}) {
    if (isOn) {
      // Log to developer console
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
      
      // Also log to server.log file with [DART] indicator
      _writeToServerLog(message, level, error, stackTrace);
    }
  }

  /// Log an informational message
  void info(String message, {bool isOn = false}) => log(message, level: 800, isOn: isOn);

  /// Log a warning message
  void warning(String message, {bool isOn = false}) => log(message, level: 900, isOn: isOn);

  /// Log a debug message
  void debug(String message, {bool isOn = false}) => log(message, level: 500, isOn: isOn);

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace, bool isOn = false}) =>
      log(message, level: 1000, error: error, stackTrace: stackTrace, isOn: isOn);

  /// Force log (logs regardless of `Config.loggerOn`)
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false}) {
    // Always log to developer console
    developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    
    // Always log to server.log file with [DART] indicator
    _writeToServerLog(message, level, error, stackTrace);
  }

  /// Write log entry to server.log file with [DART] indicator
  void _writeToServerLog(String message, int level, Object? error, StackTrace? stackTrace) {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final levelString = _getLevelString(level);
      
      // Format message similar to Python custom_log format
      String logEntry = '[$timestamp] - DART - $levelString - $message';
      
      // Add error information if present
      if (error != null) {
        logEntry += ' | Error: $error';
      }
      
      // Add stack trace if present (first few lines only)
      if (stackTrace != null) {
        final stackLines = stackTrace.toString().split('\n');
        final relevantStack = stackLines.take(3).join(' | ');
        logEntry += ' | Stack: $relevantStack';
      }
      
      // Append to server.log file
      final file = File(_serverLogPath);
      file.writeAsStringSync('$logEntry\n', mode: FileMode.append);
      
    } catch (e) {
      // If file writing fails, at least log to console
      developer.log('Failed to write to server.log: $e', name: 'Logger', level: 1000);
    }
  }

  /// Convert level number to string
  String _getLevelString(int level) {
    if (level >= 1000) return 'ERROR';
    if (level >= 900) return 'WARNING';
    if (level >= 800) return 'INFO';
    return 'DEBUG';
  }
}