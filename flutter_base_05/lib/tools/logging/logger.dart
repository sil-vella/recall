import 'dart:async';
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

  /// Whether to log (caller decides). Actual I/O runs in a microtask so call flow is not blocked.
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0, bool? isOn}) {
    if (isOn == false) return;
    final shouldLog = isOn == true || (isOn != false && Config.loggerOn);
    if (!shouldLog) return;

    // Defer I/O to next microtask so we never block the current synchronous flow
    scheduleMicrotask(() {
      _doLog(message, name: name, error: error, stackTrace: stackTrace, level: level);
    });
  }

  /// Performs the actual log I/O. Called from a microtask.
  static void _doLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = _getLevelString(level);
    print('[$timestamp] [$levelStr] [$name] $message');
    if (error != null) {
      print('[$timestamp] [ERROR] [$name] Error: $error');
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

  /// Force log (logs regardless of `Config.loggerOn` and `isOn`). I/O deferred to microtask.
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    scheduleMicrotask(() {
      _doLog(message, name: name, error: error, stackTrace: stackTrace, level: level);
    });
  }

  /// Convert level number to string
  static String _getLevelString(int level) {
    if (level >= 1000) return 'ERROR';
    if (level >= 900) return 'WARNING';
    if (level >= 800) return 'INFO';
    return 'DEBUG';
  }
}