import 'dart:developer' as developer;
import '../../utils/consts/config.dart';
import 'package:flutter/foundation.dart';
// Conditional import: use web sink on web, IO sink otherwise
import 'log_sink_io.dart' if (dart.library.html) 'log_sink_web.dart';

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
  void log(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    if (Config.loggerOn) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
      // Also mirror to file (non-web platforms)
      LogSink.appendLine(_formatLine(level: level, name: name, message: message, error: error, stackTrace: stackTrace));
    }
  }

  /// Log an informational message
  void info(String message) => log(message, level: 800);

  /// Log a warning message
  void warning(String message) => log(message, level: 900);

  /// Log a debug message
  void debug(String message) => log(message, level: 500);

  /// Log an error message
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(message, level: 1000, error: error, stackTrace: stackTrace);

  /// Force log (logs regardless of `Config.loggerOn`)
  void forceLog(String message, {String name = 'AppLogger', Object? error, StackTrace? stackTrace, int level = 0}) {
    developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    LogSink.appendLine(_formatLine(level: level, name: name, message: message, error: error, stackTrace: stackTrace));
  }

  // ===== File logging =====
  static String? get logFilePath => LogSink.logFilePath;

  static String _formatLine({required int level, required String name, required String message, Object? error, StackTrace? stackTrace}) {
    final ts = DateTime.now().toIso8601String();
    final lvl = level >= 1000
        ? 'ERROR'
        : level >= 900
            ? 'WARN'
            : level >= 800
                ? 'INFO'
                : level >= 500
                    ? 'DEBUG'
                    : 'LOG';
    final errStr = error != null ? ' | error: ${error.toString()}' : '';
    final stStr = stackTrace != null ? ' | stack: ${stackTrace.toString()}' : '';
    return '$ts [$lvl] $name: $message$errStr$stStr\n';
  }

  // Initialization happens within platform sink as needed.
}