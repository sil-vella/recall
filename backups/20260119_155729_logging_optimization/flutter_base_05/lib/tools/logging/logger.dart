import 'dart:developer' as developer;
import '../../utils/consts/config.dart';

class Logger {
  // Private constructor
  Logger._();

  // The single instance of Logger
  static final Logger _instance = Logger._();

  // Factory constructor to return the same instance
  factory Logger() {
    return _instance;
  }

  /// General log method that respects `Config.loggerOn` and `isOn` parameter
  /// When `isOn` is explicitly provided, it takes precedence over `Config.loggerOn`
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool? isOn}) {
    // If isOn is explicitly false, don't log (takes precedence over Config.loggerOn)
    if (isOn == false) {
      return;
    }
    
    // If isOn is explicitly true, always log
    if (isOn == true) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
      final timestamp = DateTime.now().toIso8601String();
      final levelStr = _getLevelString(level);
      print('[$timestamp] [$levelStr] [$name] $message');
      if (error != null) {
        print('[$timestamp] [ERROR] [$name] Error: $error');
      }
      return;
    }
    
    // If isOn is not provided (null), use Config.loggerOn
    if (Config.loggerOn) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
      final timestamp = DateTime.now().toIso8601String();
      final levelStr = _getLevelString(level);
      print('[$timestamp] [$levelStr] [$name] $message');
      if (error != null) {
        print('[$timestamp] [ERROR] [$name] Error: $error');
      }
    }
  }

  /// Log an informational message
  void info(String message, {bool? isOn}) {
    log(message, level: 800, isOn: isOn);
  }

  /// Log a warning message
  void warning(String message, {bool? isOn}) {
    log(message, level: 900, isOn: isOn);
  }

  /// Log a debug message
  void debug(String message, {bool? isOn}) {
    log(message, level: 500, isOn: isOn);
  }

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace, bool? isOn}) {
    log(message, level: 1000, error: error, stackTrace: stackTrace, isOn: isOn);
  }

  /// Force log (logs regardless of `Config.loggerOn` and `isOn`)
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    
    // Also print to console for debugging
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = _getLevelString(level);
    print('[$timestamp] [$levelStr] [$name] $message');
    if (error != null) {
      print('[$timestamp] [ERROR] [$name] Error: $error');
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