# Flutter client logging (legacy removed)

The Flutter app (`flutter_base_05`) **no longer** includes:

- `lib/tools/logging/logger.dart` (singleton `Logger`)
- `Config.loggerOn`
- Per-file `LOGGING_SWITCH` plus `_logger` / `Logger()` usage across the client

Launch scripts under `playbooks/frontend/` may still capture **stdout/stderr** from `flutter run`; that is separate from any in-app logging API.

When a replacement logging strategy is chosen (e.g. `package:logging`, `talker`, or targeted `dart:developer` usage behind `kDebugMode`), document it here and in [API_REFERENCE.md](API_REFERENCE.md).
