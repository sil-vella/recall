import 'dart:io';

import 'package:logging/logging.dart';

String _wfTimestamp() {
  final d = DateTime.now();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p2(d.month)}-${p2(d.day)} ${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';
}

void _wfAppendGlobal(String line) {
  final g = Platform.environment['WFGLOBALOG_GLOBAL_LOG'];
  final src = Platform.environment['WFGLOBALOG_SOURCE'];
  if (g == null || g.isEmpty || src == null || src.isEmpty) return;
  try {
    File(g).writeAsStringSync(
      '${_wfTimestamp()} [$src] $line\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// Routes [Logger] records to stdout with a `[dart_ws]` prefix for external filters.
void ensureDevConsoleLogging() {
  Logger.root.level = Level.FINE;
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen((LogRecord record) {
    final line =
        '[dart_ws] ${record.level.name} ${record.loggerName}: ${record.message}';
    stdout.writeln(line);
    final cap = Platform.environment['WFGLOBALOG_CAPTURE_FILE'];
    if (cap != null && cap.isNotEmpty) {
      try {
        File(cap).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }
    _wfAppendGlobal(line);
  });
}

/// Runs [emit] only when [switchOn] is true (lazy log construction).
void devLog(bool switchOn, void Function() emit) {
  if (switchOn) emit();
}
