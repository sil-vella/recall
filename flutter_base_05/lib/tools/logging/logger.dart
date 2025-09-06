import 'dart:developer' as developer;
import 'dart:convert';
import 'package:http/http.dart' as http;
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
    if (Config.loggerOn || isOn) {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    }
    if (Config.enableRemoteLogging) {
      _sendToServer(level: level, message: message, error: error, stack: stackTrace);
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
    developer.log(message, name: name, error: error, stackTrace: stackTrace, level: level);
    if (Config.enableRemoteLogging) {
      _sendToServer(level: level, message: message, error: error, stack: stackTrace);
    }
  }

  /// Send log to server via HTTP
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

      // Debug: Log that we're sending to server
      developer.log('Sending log to server: ${payload['message']}', name: 'Logger');

      // Send to server log endpoint - fire and forget
      _sendHttpLog(payload).catchError((e) {
        // Silently fail - don't want logging errors to break the app
        developer.log('HTTP log send failed: $e', name: 'Logger');
      });
    } catch (e) {
      // Don't log errors from logging to avoid infinite loops
      developer.log('Failed to send log to server: $e', name: 'Logger');
    }
  }

  /// Convert level number to string
  String _getLevelString(int level) {
    if (level >= 1000) return 'ERROR';
    if (level >= 900) return 'WARNING';
    if (level >= 800) return 'INFO';
    return 'DEBUG';
  }

  /// Send log via HTTP POST
  Future<void> _sendHttpLog(Map<String, dynamic> payload) async {
    try {
      developer.log('HTTP log: Sending to ${Config.apiUrl}/log', name: 'Logger');
      final response = await http.post(
        Uri.parse('${Config.apiUrl}/log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        developer.log('HTTP log: Sent successfully', name: 'Logger');
      } else {
        developer.log('HTTP log: Failed with status ${response.statusCode}', name: 'Logger');
      }
    } catch (e) {
      // Silently fail - don't want logging errors to break the app
      developer.log('HTTP log: Failed to send: $e', name: 'Logger');
    }
  }
}