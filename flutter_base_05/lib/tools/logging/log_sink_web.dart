import 'dart:async';
import 'dart:html' as html;

class LogSink {
  static String? logFilePath; // not applicable on web, use localStorage key
  static const _key = 'app_log_buffer';
  static const _maxLen = 200000; // ~200KB cap to avoid bloat

  static Future<void> appendLine(String line) async {
    try {
      final prev = html.window.localStorage[_key] ?? '';
      final next = (prev + line);
      // Trim if too big
      final trimmed = next.length > _maxLen ? next.substring(next.length - _maxLen) : next;
      html.window.localStorage[_key] = trimmed;
    } catch (_) {}
  }

  static String getBuffer() => html.window.localStorage[_key] ?? '';
}


