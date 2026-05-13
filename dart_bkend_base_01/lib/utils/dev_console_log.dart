import 'dart:io';

import 'package:logging/logging.dart';

/// Routes [Logger] records to stdout with a `[dart_ws]` prefix for external filters.
void ensureDevConsoleLogging() {
  Logger.root.level = Level.FINE;
  hierarchicalLoggingEnabled = true;
  Logger.root.onRecord.listen((LogRecord record) {
    stdout.writeln(
      '[dart_ws] ${record.level.name} ${record.loggerName}: ${record.message}',
    );
  });
}

/// Runs [emit] only when [switchOn] is true (lazy log construction).
void devLog(bool switchOn, void Function() emit) {
  if (switchOn) emit();
}
