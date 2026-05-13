import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Routes [Logger] records to stdout with a `[flutter]` prefix for external filters.
void ensureDevConsoleLogging() {
  if (kReleaseMode) return;
  Logger.root.level = Level.FINE;
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen((LogRecord record) {
    // ignore: avoid_print
    print(
      '[flutter] ${record.level.name} ${record.loggerName}: ${record.message}',
    );
  });
}

/// Runs [emit] only when [switchOn] is true (lazy log construction).
void devLog(bool switchOn, void Function() emit) {
  if (switchOn) emit();
}
