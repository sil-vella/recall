/// Single-call dev logging for Flutter.
///
/// **VM (Android, iOS, desktop):** on when `DUTCH_DEV_LOG` is set at compile time
/// (`--dart-define=DUTCH_DEV_LOG=1` — added by `run_flutter_app_to_global_log.sh` /
/// `launch_*.sh`) **or** at runtime on the host (`Platform.environment`, e.g. desktop).
/// Uses [debugPrint] so device logs show in logcat / `flutter run | tee` → `global.log`.
///
/// **Web:** compile-time flag as above, else falls back to [kDebugMode].

import 'dev_logger_web.dart' if (dart.library.io) 'dev_logger_io.dart' as _impl;

/// Writes `[dev] message` when the stack-specific gate allows; otherwise no-op.
void customlog(String message) => _impl.customlog(message);
