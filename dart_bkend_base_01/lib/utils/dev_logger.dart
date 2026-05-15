import 'dart:io';

/// Single-call dev logging; no-op unless `DUTCH_DEV_LOG` is `1` / `true` / `yes`.
bool _enabled() {
  final v = Platform.environment['DUTCH_DEV_LOG']?.toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}

/// Writes `[dev] message` to stderr when enabled; otherwise no-op.
void customlog(String message) {
  if (!_enabled()) return;
  stderr.writeln('[dev] $message');
}
