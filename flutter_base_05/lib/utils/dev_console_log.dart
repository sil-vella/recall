import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'log_capture_mirror_stub.dart'
    if (dart.library.io) 'log_capture_mirror_io.dart' as log_capture;

/// Routes [Logger] records to stdout with a `[flutter]` prefix for external filters.
void ensureDevConsoleLogging() {
  if (kReleaseMode) return;
  Logger.root.level = Level.FINE;
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen((LogRecord record) {
    final line =
        '[flutter] ${record.level.name} ${record.loggerName}: ${record.message}';
    // ignore: avoid_print
    print(line);
    log_capture.mirrorLogLineToCapture(line);
  });
}

/// Runs [emit] only when [switchOn] is true (lazy log construction).
void devLog(bool switchOn, void Function() emit) {
  if (switchOn) emit();
}
