# Agent-accessible debug logs

Stable paths under the repo root so humans and Cursor agents can `Read` or `tail -f` without hunting integrated terminals.

## Log files

| Path | Source | Contents |
|------|--------|----------|
| `python_base_04/tools/logger/server.log` | Flutter via [`playbooks/frontend/launch_chrome.sh`](../../playbooks/frontend/launch_chrome.sh) and [`launch_oneplus.sh`](../../playbooks/frontend/launch_oneplus.sh) | Every merged `flutter run` line, prefixed with UTC time and `[FLUTTER]` (agent/human debug sink). |
| `python_base_04/tools/logger/backend.debug.log` | Flask debug only ([`python_base_04/app.debug.py`](../../python_base_04/app.debug.py)) | Werkzeug and root Python `logging` when `AGENT_BACKEND_LOG=1`. Not written by Flutter scripts. |
| `dart_bkend_base_01/tools/logger/dart_ws.debug.log` | [`dart_bkend_base_01/app.debug.dart`](../../dart_bkend_base_01/app.debug.dart) | Dart WebSocket dev server: startup line and errors. |

## Environment variables (repo root `.env.local`)

| Variable | Effect |
|----------|--------|
| `AGENT_LOG_JSON` | If `1`, `true`, or `yes`: each mirrored `[FLUTTER]` line also appends one **NDJSON** object to `server.log` (extra line) for machine parsing. |
| `AGENT_LOG_MAX_MB` | Optional positive number (e.g. `5`). Before Flutter launch scripts append, if `server.log` exceeds this size (MiB), it is truncated to avoid huge agent reads. |
| `AGENT_BACKEND_LOG` | If `1`, `true`, or `yes`: Flask `app.debug.py` attaches a file handler to `backend.debug.log`. |
| `CLEAR_SERVER_LOG_ON_FLASK_START` | Default `1` (clear allowed). Set to `0`, `false`, or `no` to **skip** truncating `server.log` when Flask debug starts—use when Flutter is already logging to the same file and you do not want history wiped. |

## Flask vs Flutter on `server.log`

[`app.debug.py`](../../python_base_04/app.debug.py) can clear or create `server.log` on startup when clearing is allowed. Starting Flask after Flutter may truncate shared Flutter tail history. Use `CLEAR_SERVER_LOG_ON_FLASK_START=0` when running both and preserving `server.log`.

## VS Code

- Flutter: use launch configs that run `playbooks/frontend/launch_*.sh` (loads `.env.local` and dart-defines).
- Tasks: **Run Task → Tail server.log** or **Tail backend.debug.log** (see [`.vscode/tasks.json`](../../.vscode/tasks.json)).

## Quick commands (from repo root)

```bash
tail -f python_base_04/tools/logger/server.log
tail -f python_base_04/tools/logger/backend.debug.log
tail -f dart_bkend_base_01/tools/logger/dart_ws.debug.log
```
