import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'consts/config.dart';

/// Tagged debug output for local runs: terminal, `server.log` via launch-script pipe when present,
/// and `POST /log` → `python_base_04/tools/logger/server.log` when [Config.enableRemoteLogging] is true
/// (covers Android/device where there is no local pipe).
///
/// No-op when:
/// - not a debug VM build ([kDebugMode] is false in profile/release),
/// - `DEBUG_MODE` is false,
/// - `VERBOSE_DEV_LOGS` is false.
///
/// Example: `dbg('RevCat', 'offerings loaded: ${offerings?.all.length}');`
void dbg(
  String tag,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!kDebugMode) return;
  if (!Config.debugMode) return;
  if (!Config.verboseDevLogs) return;

  final buf = StringBuffer('[$tag] $message');
  if (error != null) {
    buf.write(' | $error');
  }
  final mainLine = buf.toString();
  debugPrint(mainLine);
  if (stackTrace != null) {
    debugPrint(stackTrace.toString());
  }
  if (Config.enableRemoteLogging) {
    final payload = stackTrace != null ? '$mainLine ${stackTrace.toString()}' : mainLine;
    unawaited(_postDbgToServerLog(payload));
  }
}

Future<void> _postDbgToServerLog(String message) async {
  try {
    final base = Config.apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/log');
    await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'message': message,
            'level': 'INFO',
            'source': 'dbg',
            'platform': defaultTargetPlatform.name,
            'buildMode': kDebugMode ? 'debug' : 'release',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 2));
  } catch (_) {}
}
