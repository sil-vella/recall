#!/bin/bash

# Flutter app launcher for Android devices. Merges flutter run stdout/stderr and mirrors
# every line to python_base_04/tools/logger/server.log (see Documentation/debug/AGENT_DEBUG_LOGS.md).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.local"

# Load env from repo root .env.local (APP_VERSION, Firebase, GOOGLE_CLIENT_ID, Stripe, AdMob, AdSense, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — dart-defines (Firebase, Google Sign-In, etc.) will be empty."
fi

# Known device labels (extend this list when adding new phones)
get_device_label() {
    case "$1" in
        84fbcf31) echo "OnePlus device" ;;
        R3CWB0CS63D) echo "Samsung Galaxy S23 Ultra" ;;
        5dad288e7d91) echo "Xiaomi Redmi tablet" ;;
        NOTE58000000021664) echo "DOOGEE" ;;
        *) echo "Android device" ;;
    esac
}

# Resolve numeric shortcut/device alias into a concrete adb serial
resolve_device_id() {
    case "$1" in
        1|oneplus|OnePlus|ONEPLUS) echo "84fbcf31" ;;
        2|samsung|Samsung|SAMSUNG|s23|S23) echo "R3CWB0CS63D" ;;
        3|xiaomi|Xiaomi|XIAOMI|redmi|Redmi|REDMI) echo "5dad288e7d91" ;;
        4|doogee|Doogee|DOOGEE) echo "NOTE58000000021664" ;;
        *) echo "$1" ;;
    esac
}

prompt_for_device_selection() {
    echo "📲 Select target device:" >&2
    echo "   1) OnePlus (84fbcf31)" >&2
    echo "   2) Samsung Galaxy S23 Ultra (R3CWB0CS63D)" >&2
    echo "   3) Xiaomi Redmi tablet (5dad288e7d91)" >&2
    echo "   4) DOOGEE (NOTE58000000021664)" >&2
    # Read from controlling terminal when stdin is not a TTY (e.g. piped launch).
    local _tty=/dev/tty
    [ -r "$_tty" ] || _tty=/dev/stdin
    if ! read -r -t 10 -p "Enter choice [1/2/3/4] (default: 1, auto after 10s): " device_choice < "$_tty"; then
        echo "" >&2
        echo "⏱️  No selection within 10s — using 1 (OnePlus)." >&2
        device_choice="1"
    fi
    case "${device_choice:-1}" in
        1) echo "84fbcf31" ;;
        2) echo "R3CWB0CS63D" ;;
        3) echo "5dad288e7d91" ;;
        4) echo "NOTE58000000021664" ;;
        *)
            echo "⚠️  Invalid choice '${device_choice}', using default: 1 (OnePlus)" >&2
            echo "84fbcf31"
            ;;
    esac
}

# Args:
#   $1 = optional legacy: `local` or `vps` (ignored for dart-defines; set API_URL/WS_URL in .env.local).
#        If used, device id is $2 (or ANDROID_DEVICE_ID / interactive prompt).
#   Otherwise $1 = device id/serial/shortcut. Shortcuts: 1=OnePlus, 2=Samsung, 3=Xiaomi tablet, 4=DOOGEE
# You can also set ANDROID_DEVICE_ID env var to override.
# Interactive prompt: if device not set, choose within 10s or default to 1 (OnePlus).
if [[ "${1:-}" == "local" || "${1:-}" == "vps" ]]; then
  _legacy_backend="$1"
  shift
  echo "ℹ️  First arg '${_legacy_backend}' is legacy (URLs/API are only from $FRONTEND_ENV); using device from \$2 or prompt." >&2
fi
RAW_DEVICE_INPUT="${ANDROID_DEVICE_ID:-$1}"
if [ -z "$RAW_DEVICE_INPUT" ]; then
    DEVICE_ID="$(prompt_for_device_selection)"
else
    DEVICE_ID="$(resolve_device_id "$RAW_DEVICE_INPUT")"
fi
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
ANDROID_APP_ID="com.reignofplay.dutch"
FIREBASE_DEBUGVIEW_ENABLED=false

SERVER_LOG_FILE="$REPO_ROOT/python_base_04/tools/logger/server.log"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/agent_server_log_helpers.sh"
ensure_server_log_dir_and_maybe_rotate
LOG_DIR=$(dirname "$SERVER_LOG_FILE")
if [ ! -w "$LOG_DIR" ]; then
    echo "❌ Error: Log directory is not writable: $LOG_DIR"
    exit 1
fi

echo_and_server_log "🚀 Launching Flutter app on $DEVICE_LABEL ($DEVICE_ID) (flutter run → server.log for debugging)..."

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb not found. Please install Android SDK and add to PATH"
    exit 1
fi

# Check if device is connected
echo_and_server_log "📱 Checking device connection..."
adb devices | grep -q "$DEVICE_ID"
if [ $? -ne 0 ]; then
    echo "❌ Error: $DEVICE_LABEL ($DEVICE_ID) not found"
    echo "Available devices:"
    adb devices
    exit 1
fi

echo_and_server_log "✅ $DEVICE_LABEL ($DEVICE_ID) is connected"

# Enable Firebase Analytics DebugView for this app on this device.
# This makes local events appear quickly in Firebase DebugView.
echo_and_server_log "🧪 Enabling Firebase Analytics DebugView for $ANDROID_APP_ID on $DEVICE_LABEL..."
if adb -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app "$ANDROID_APP_ID"; then
    FIREBASE_DEBUGVIEW_ENABLED=true
    echo_and_server_log "✅ Firebase DebugView enabled"
else
    echo_and_server_log "⚠️  Could not enable Firebase DebugView (continuing without it)"
fi

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" 2>/dev/null || cd flutter_base_05

echo_and_server_log "📝 Flutter script + flutter run → $SERVER_LOG_FILE ([LAUNCH] = this script, [FLUTTER] = tool stream)"

# Launch Flutter app with selected device configuration
echo_and_server_log "🎯 Launching Flutter app for $DEVICE_LABEL..."

echo_and_server_log "📝 Dart-define SSOT: $FRONTEND_ENV (no script-side --dart-define overrides)"

# Same pipeline as launch_chrome.sh (flutter tool merged streams after sed strip, not raw adb logcat).
filter_logs() {
    while IFS= read -r line; do
        local ts
        ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '%s [FLUTTER] %s\n' "$ts" "$line" >> "$SERVER_LOG_FILE"
        append_agent_json_server_log "$ts" "flutter" "INFO" "$line"
        printf '%s\n' "$line"
    done
}

CLEANUP_DONE=false
DART_DEF_JSON=""

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    [ -n "${DART_DEF_JSON:-}" ] && rm -f "$DART_DEF_JSON"
    if [ "$FIREBASE_DEBUGVIEW_ENABLED" = true ]; then
        echo "🧪 Disabling Firebase Analytics DebugView for $ANDROID_APP_ID..."
        adb -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app .none. >/dev/null 2>&1 || true
    fi
    echo "✅ Cleanup completed"
}

trap cleanup EXIT INT TERM HUP

# Dart-define SSOT: .env.local → temp JSON (avoids shell ARG_MAX with dozens of --dart-define args).
if ! command -v python3 &>/dev/null; then
  echo_and_server_log "❌ python3 not found — required for --dart-define-from-file"
  exit 1
fi
DART_DEF_JSON="$(mktemp "${TMPDIR:-/tmp}/flutter-dart-defines.XXXXXX.json")" || exit 1
python3 "$SCRIPT_DIR/env_for_flutter_dart_defines.py" "$FRONTEND_ENV" "$DART_DEF_JSON" || exit 1
export DART_DEF_JSON
KEYCOUNT="$(python3 -c 'import json,os; print(len(json.load(open(os.environ["DART_DEF_JSON"],encoding="utf-8"))))')"
echo_and_server_log "   Dart-define-from-file: $KEYCOUNT keys → $DART_DEF_JSON"

echo_and_server_log "⏳ Starting flutter run (first Gradle build may take 1–2 min with little output)…"

# Mirror launch_chrome.sh: filter_logs on merged flutter output (strip date prefix on matching lines first).
flutter run \
    -d "$DEVICE_ID" \
    --dart-define-from-file="$DART_DEF_JSON" \
    2>&1 | sed -E '/\[[0-9]{4}-[0-9]{2}-[0-9]{2}T/s/^[^[]*//' | filter_logs

FLUTTER_EXIT_CODE=${PIPESTATUS[0]}

cleanup

echo_and_server_log "✅ Flutter app launch completed (exit code: $FLUTTER_EXIT_CODE)"
echo_and_server_log "📝 Flutter run log: $SERVER_LOG_FILE"
echo_and_server_log "🔍 To view logs: tail -f $SERVER_LOG_FILE"

exit $FLUTTER_EXIT_CODE
