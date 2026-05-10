#!/bin/bash

# Flutter app launcher with filtered Logger output by default.
# Set FLUTTER_SERVER_LOG_ALL=1 (or true) in the environment or .env.local to also append
# every other Flutter stdout line to server.log as [FLUTTER_RAW] (Gradle/tool noise still stderr-only).

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
#   $1 = backend target: local (default) or vps
#   $2 = Android device id/serial/shortcut (optional)
#        Shortcuts: 1=OnePlus, 2=Samsung, 3=Xiaomi Redmi tablet, 4=DOOGEE (doogee/DOOGEE)
# You can also set ANDROID_DEVICE_ID env var to override.
# Interactive prompt: if neither is set, choose within 10s or default to 1 (OnePlus).
RAW_DEVICE_INPUT="${ANDROID_DEVICE_ID:-$2}"
if [ -z "$RAW_DEVICE_INPUT" ]; then
    DEVICE_ID="$(prompt_for_device_selection)"
else
    DEVICE_ID="$(resolve_device_id "$RAW_DEVICE_INPUT")"
fi
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
ANDROID_APP_ID="com.reignofplay.dutch"
FIREBASE_DEBUGVIEW_ENABLED=false

if [ "${FLUTTER_SERVER_LOG_ALL:-}" = "1" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "true" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "yes" ]; then
    echo "🚀 Launching Flutter app on $DEVICE_LABEL ($DEVICE_ID) — Logger + full stdout → server.log (FLUTTER_SERVER_LOG_ALL)..."
else
    echo "🚀 Launching Flutter app on $DEVICE_LABEL ($DEVICE_ID) with filtered Logger output..."
fi

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb not found. Please install Android SDK and add to PATH"
    exit 1
fi

# Check if device is connected
echo "📱 Checking device connection..."
adb devices | grep -q "$DEVICE_ID"
if [ $? -ne 0 ]; then
    echo "❌ Error: $DEVICE_LABEL ($DEVICE_ID) not found"
    echo "Available devices:"
    adb devices
    exit 1
fi

echo "✅ $DEVICE_LABEL ($DEVICE_ID) is connected"

# Enable Firebase Analytics DebugView for this app on this device.
# This makes local events appear quickly in Firebase DebugView.
echo "🧪 Enabling Firebase Analytics DebugView for $ANDROID_APP_ID on $DEVICE_LABEL..."
if adb -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app "$ANDROID_APP_ID"; then
    FIREBASE_DEBUGVIEW_ENABLED=true
    echo "✅ Firebase DebugView enabled"
else
    echo "⚠️  Could not enable Firebase DebugView (continuing without it)"
fi

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" 2>/dev/null || cd flutter_base_05

# Set up log file to write to Python server log
SERVER_LOG_FILE="$REPO_ROOT/python_base_04/tools/logger/server.log"
if [ "${FLUTTER_SERVER_LOG_ALL:-}" = "1" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "true" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "yes" ]; then
    echo "📝 Writing AppLogger lines + all other Flutter stdout to: $SERVER_LOG_FILE (FLUTTER_SERVER_LOG_ALL; do not redirect script stdout here)"
else
    echo "📝 Writing Logger output to: $SERVER_LOG_FILE (do not redirect script stdout to this file)"
fi

# Ensure log file directory exists and is writable
LOG_DIR=$(dirname "$SERVER_LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    echo "⚠️  Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi
if [ ! -w "$LOG_DIR" ]; then
    echo "❌ Error: Log directory is not writable: $LOG_DIR"
    exit 1
fi

# Launch Flutter app with selected device configuration
echo "🎯 Launching Flutter app for $DEVICE_LABEL..."

# Determine backend target from first argument: 'local' (default) or 'vps'
BACKEND_TARGET="${1:-local}"

if [ "$BACKEND_TARGET" = "vps" ]; then
    API_URL="https://dutch.reignofplay.com"
    WS_URL="wss://dutch.reignofplay.com/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Same Logger → server.log pipeline as launch_chrome.sh (flutter tool stdout, not adb logcat).
filter_logs() {
    while IFS= read -r line; do
        if echo "$line" | grep -q "\[.*\] \[.*\] \[AppLogger\]"; then
            timestamp=$(echo "$line" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
            level=$(echo "$line" | sed -n 's/^\[[^]]*\] \[\([^]]*\)\].*/\1/p')
            message=$(echo "$line" | sed -n 's/^\[[^]]*\] \[[^]]*\] \[AppLogger\] //p')
            if [ -z "$timestamp" ] || [ -z "$level" ]; then
                continue
            fi
            if [ -z "$message" ]; then
                continue
            fi
            case "$level" in
                ERROR) color="\033[31m" ;;
                WARNING) color="\033[33m" ;;
                INFO) color="\033[32m" ;;
                DEBUG) color="\033[36m" ;;
                *) color="\033[37m" ;;
            esac
            echo "[$timestamp] [$level] $message" >> "$SERVER_LOG_FILE"
            echo -e "${color}[$timestamp] [$level] $message\033[0m"
        else
            echo "$line" >&2
            if [ "${FLUTTER_SERVER_LOG_ALL:-}" = "1" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "true" ] || [ "${FLUTTER_SERVER_LOG_ALL:-}" = "yes" ]; then
                printf '%s [FLUTTER_RAW] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$line" >> "$SERVER_LOG_FILE"
            fi
        fi
    done
}

CLEANUP_DONE=false

cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    if [ "$FIREBASE_DEBUGVIEW_ENABLED" = true ]; then
        echo "🧪 Disabling Firebase Analytics DebugView for $ANDROID_APP_ID..."
        adb -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app .none. >/dev/null 2>&1 || true
    fi
    echo "✅ Cleanup completed"
}

trap cleanup EXIT INT TERM HUP

# Build --dart-define from .env (all vars) then overrides and run-only extras
source "$SCRIPT_DIR/dart_defines_from_env.sh"
DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=( "$line" )
done < <(build_dart_defines_from_env "$FRONTEND_ENV")
DART_DEFINE_ARGS+=( --dart-define=API_URL="$API_URL" --dart-define=WS_URL="$WS_URL" )
# Ensure Firebase runtime toggle is always present (defaults to true when missing).
DART_DEFINE_ARGS+=( --dart-define=FIREBASE_SWITCH="${FIREBASE_SWITCH:-true}" )
DART_DEFINE_ARGS+=( \
  --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
  --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
  --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
  --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
  --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
  --dart-define=DEBUG_MODE=true \
  --dart-define=ENABLE_REMOTE_LOGGING=true \
)

# Same diagnostics idea as launch_chrome.sh (GOOGLE_CLIENT_ID): RevenueCat Play Store key must be in dart-defines.
RC_GOOGLE_IN_DEFINES=false
for arg in "${DART_DEFINE_ARGS[@]}"; do
  if [[ "$arg" == --dart-define=REVENUECAT_GOOGLE_API_KEY=* ]]; then
    RC_GOOGLE_IN_DEFINES=true
    VAL="${arg#--dart-define=REVENUECAT_GOOGLE_API_KEY=}"
    VAL="${VAL%\"}"
    VAL="${VAL#\"}"
    echo "   Dart-define REVENUECAT_GOOGLE_API_KEY: prefix=${VAL:0:8}… (length=${#VAL})"
    break
  fi
done
if [ "$RC_GOOGLE_IN_DEFINES" = false ]; then
  echo "   ❌ REVENUECAT_GOOGLE_API_KEY not in dart-defines — set REVENUECAT_GOOGLE_API_KEY in $FRONTEND_ENV (Android IAP)."
fi
echo "   Total dart-defines: ${#DART_DEFINE_ARGS[@]}"

# Logger lines mirror launch_chrome.sh: same filter_logs on flutter stdout (strip tool prefix first).
flutter run \
    -d "$DEVICE_ID" \
    "${DART_DEFINE_ARGS[@]}" 2>&1 | sed -E '/\[[0-9]{4}-[0-9]{2}-[0-9]{2}T/s/^[^[]*//' | filter_logs

FLUTTER_EXIT_CODE=${PIPESTATUS[0]}

cleanup

echo "✅ Flutter app launch completed (exit code: $FLUTTER_EXIT_CODE)"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

exit $FLUTTER_EXIT_CODE
