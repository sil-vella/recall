import 'dart:developer' as developer;
import '../../utils/consts/config.dart';

typedef LogSinkFn = void Function(Map<String, dynamic> payload);

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
    }
    if (Config.enableRemoteLogging) {
      _emitToSinks(level: level, message: message, error: error, stack: stackTrace);
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
    if (Config.enableRemoteLogging) {
      _emitToSinks(level: level, message: message, error: error, stack: stackTrace);
    }
  }

  // ===== Remote sink plumbing =====
  static final List<LogSinkFn> _sinks = <LogSinkFn>[];
  static int _emittedInWindow = 0;
  static DateTime _windowStart = DateTime.fromMillisecondsSinceEpoch(0);

  static void registerSink(LogSinkFn sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  static void unregisterSink(LogSinkFn sink) {
    _sinks.remove(sink);
  }

  void _emitToSinks({required int level, required String message, Object? error, StackTrace? stack}) {
    // Basic throttle: max 10 messages/sec
    final now = DateTime.now();
    if (now.difference(_windowStart).inMilliseconds > 1000) {
      _windowStart = now;
      _emittedInWindow = 0;
    }
    if (_emittedInWindow >= 10) return;
    _emittedInWindow++;

    final payload = <String, dynamic>{
      'source': 'frontend',
      'ts': now.toIso8601String(),
      'level': level,
      'message': message,
      if (error != null) 'error': error.toString(),
      if (stack != null) 'stack': stack.toString(),
      'platform': Config.platform,
      'buildMode': Config.buildMode,
      'appVersion': Config.appVersion,
    };
    for (final sink in List<LogSinkFn>.from(_sinks)) {
      try { sink(payload); } catch (_) {}
    }
  }
}