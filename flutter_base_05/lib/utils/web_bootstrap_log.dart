import 'package:flutter/foundation.dart' show kIsWeb;

import 'dev_logger.dart';

/// Chrome / web cold-start tracing (VS Code `run_flutter_app_to_global_log.sh chrome`).
/// File-level switch stays on so [customlog] reaches `global.log` via DUTCH_DEV_LOG.
const bool LOGGING_SWITCH = false;

/// Logs `WebBootstrap: …` when [kIsWeb] and [LOGGING_SWITCH].
void webBootstrapLog(String message) {
  if (!kIsWeb) return;
  if (LOGGING_SWITCH) {
    customlog('WebBootstrap: $message');
  }
}
