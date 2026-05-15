#!/usr/bin/env bash
# Shared helpers: repo .env.dart.defines.local (dev) or .env.dart.defines.prod (release build)
# → temp JSON for `flutter run|build --dart-define-from-file=…`.

_FLUTTER_DART_DEFINES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_flutter_dart_defines_log() {
  if declare -f echo_and_server_log &>/dev/null; then
    echo_and_server_log "$@"
  else
    echo "$@" >&2
  fi
}

flutter_dart_defines_require_python() {
  if ! command -v python3 &>/dev/null; then
    _flutter_dart_defines_log "❌ python3 not found — required for --dart-define-from-file"
    return 1
  fi
}

# Args: path to .env.dart.defines.local or .env.dart.defines.prod
# Sets: DART_DEFINES_ENV, DART_DEF_JSON (exported). Caller must rm DART_DEF_JSON on exit.
flutter_dart_defines_prepare() {
  local env_file="$1"
  DART_DEFINES_ENV="$env_file"
  if [ ! -f "$DART_DEFINES_ENV" ]; then
    _flutter_dart_defines_log "❌ Missing dart-define file: $DART_DEFINES_ENV"
    return 1
  fi
  DART_DEF_JSON="$(mktemp "${TMPDIR:-/tmp}/flutter-dart-defines.XXXXXX.json")" || return 1
  python3 "$_FLUTTER_DART_DEFINES_SCRIPT_DIR/env_for_flutter_dart_defines.py" \
    "$DART_DEFINES_ENV" "$DART_DEF_JSON" || return 1
  export DART_DEFINES_ENV DART_DEF_JSON
}

# Optional arg: android | chrome | build (warnings for loopback on device)
flutter_dart_defines_print_summary() {
  local mode="${1:-}"
  if [ -z "${DART_DEF_JSON:-}" ] || [ ! -f "$DART_DEF_JSON" ]; then
    return 0
  fi
  local keycount
  keycount="$(python3 -c 'import json,os; print(len(json.load(open(os.environ["DART_DEF_JSON"],encoding="utf-8"))))' 2>/dev/null)" || keycount="?"
  _flutter_dart_defines_log "   Dart-define SSOT: $DART_DEFINES_ENV"
  _flutter_dart_defines_log "   Dart-define-from-file: ${keycount} keys → $DART_DEF_JSON"
  while IFS= read -r line; do
    [ -n "$line" ] && _flutter_dart_defines_log "$line"
  done < <(FLUTTER_DART_DEFINES_MODE="$mode" python3 - <<'PY'
import json
import os

p = os.environ.get("DART_DEF_JSON")
if not p:
    raise SystemExit(0)
d = json.load(open(p, encoding="utf-8"))
mode = os.environ.get("FLUTTER_DART_DEFINES_MODE", "")
for k in ("API_URL", "WS_URL", "BUILD_MODE", "APP_VERSION", "APP_PLATFORM"):
    print(f"   {k}={d.get(k, '')}")
api = (d.get("API_URL") or "").lower()
ws = (d.get("WS_URL") or "").lower()
if mode == "android":
    if "localhost" in api or "127.0.0.1" in api:
        print("   ⚠️  API_URL is loopback — a physical phone cannot reach your Mac via localhost; set LAN IP in .env.dart.defines.local")
    if "10.0.2.2" in api:
        print("   ⚠️  API_URL uses 10.0.2.2 (Android emulator host alias only); use LAN IP for real devices")
    if "localhost" in ws or "127.0.0.1" in ws:
        print("   ⚠️  WS_URL is loopback — use ws://<LAN-IP>:8080 for physical devices")
PY
)
}
