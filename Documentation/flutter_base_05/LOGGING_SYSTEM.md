# Flutter / Dart / Python dev logging

## In-app (console)

- **Flutter**: [`lib/utils/dev_console_log.dart`](../../flutter_base_05/lib/utils/dev_console_log.dart) — `ensureDevConsoleLogging()` in `main.dart` (non-release); `package:logging` with `[flutter]` line prefix.
- **Dart WS**: [`dart_bkend_base_01/lib/utils/dev_console_log.dart`](../../dart_bkend_base_01/lib/utils/dev_console_log.dart) — `ensureDevConsoleLogging()` in `app.debug.dart`; `[dart_ws]` prefix.
- **Python**: [`python_base_04/tools/dev_logging.py`](../../python_base_04/tools/dev_logging.py) — `configure_dev_logging()` from `app.py` / `app.debug.py`; `[python]` prefix. Optional `APP_LOG_LEVEL` env (`INFO`, `DEBUG`, …).

Use per-file **`LOGGING_SWITCH`** (Dart: `const bool`; Python: module `bool`) with **`devLog(...)`** so release build scripts can disable traces.

## Optional: `global.log` at repo root

- Aggregated file: **`app_dev/global.log`** (covered by `.gitignore` `*.log`).
- Shell mirror: **`/Users/sil/Documents/Work/00Utilities/scripts/00_workflow/shell_commands/wfgloballog`** — see `00_workflow/README.md`.
- **VS Code**: [`.vscode/launch.json`](../../.vscode/launch.json) — **Chrome**; Android targets match `playbooks/frontend/launch_oneplus.sh` serials: **OnePlus** `84fbcf31`, **Samsung S23 Ultra** `R3CWB0CS63D`, **Xiaomi Redmi tablet** `5dad288e7d91`, **DOOGEE** `NOTE58000000021664`. Each Android config uses `--dart-define-from-file` from `.env.local` via `flutterDartDefinesJson` and a matching `preFlutter*` / `wfgloballogStop*` pair in [`.vscode/tasks.json`](../../.vscode/tasks.json). For Firebase DebugView on device, use the same `adb … setprop debug.firebase.analytics.app` step as in `launch_oneplus.sh`.
- **Capture**: lines reach `global.log` only after they are appended to the session **capture file** (under `~/.cache/app_dev_global_logs/`). For full terminal mirroring, wrap the process with `tee -a "$(wfgloballog path ...)"`; the stock Flutter F5 path alone does not tee unless you add a task-based run.
