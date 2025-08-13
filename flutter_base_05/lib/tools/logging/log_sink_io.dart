import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogSink {
  static IOSink? _sink;
  static String? logFilePath;
  static bool _initializing = false;

  static Future<void> _ensureInitialized() async {
    if (_sink != null || _initializing) return;
    _initializing = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/app.log');
      logFilePath = file.path;
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      _sink = file.openWrite(mode: FileMode.append);
    } finally {
      _initializing = false;
    }
  }

  static Future<void> appendLine(String line) async {
    if (_sink == null) {
      await _ensureInitialized();
    }
    try {
      _sink?.write(line);
      await _sink?.flush();
    } catch (_) {}
  }
}


