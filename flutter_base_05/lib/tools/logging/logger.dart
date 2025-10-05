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

  /// General log method that respects `Config.loggerOn`
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false}) {
    // Early return if logging is disabled and not forced
    if (!Config.loggerOn && !isOn) {
      return;
    }
    
    if (Config.loggerOn || isOn) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
      
      // Also print to console for debugging (always in debug builds)
      final timestamp = DateTime.now().toIso8601String();
      final levelStr = _getLevelString(level);
      print('[$timestamp] [$levelStr] [$name] $message');
      if (error != null) {
        print('[$timestamp] [ERROR] [$name] Error: $error');
      }
    }
  }

  /// Log an informational message
  void info(String message, {bool isOn = false}) {
    if (!Config.loggerOn && !isOn) return;
    log(message, level: 800, isOn: isOn);
  }

  /// Log a warning message
  void warning(String message, {bool isOn = false}) {
    if (!Config.loggerOn && !isOn) return;
    log(message, level: 900, isOn: isOn);
  }

  /// Log a debug message
  void debug(String message, {bool isOn = false}) {
    if (!Config.loggerOn && !isOn) return;
    log(message, level: 500, isOn: isOn);
  }

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace, bool isOn = false}) {
    if (!Config.loggerOn && !isOn) return;
    log(message, level: 1000, error: error, stackTrace: stackTrace, isOn: isOn);
  }

  /// Force log (logs regardless of `Config.loggerOn`)
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool isOn = false}) {
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