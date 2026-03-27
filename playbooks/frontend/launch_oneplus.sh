#!/bin/bash

# Flutter app launcher with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

# Note: We'll use process groups for cleanup but won't enable full job control
# as it can interfere with VS Code's terminal handling

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
        *) echo "Android device" ;;
    esac
}

# Resolve numeric shortcut/device alias into a concrete adb serial
resolve_device_id() {
    case "$1" in
        1|oneplus|OnePlus|ONEPLUS) echo "84fbcf31" ;;
        2|samsung|Samsung|SAMSUNG|s23|S23) echo "R3CWB0CS63D" ;;
        3|xiaomi|Xiaomi|XIAOMI|redmi|Redmi|REDMI) echo "5dad288e7d91" ;;
        *) echo "$1" ;;
    esac
}

prompt_for_device_selection() {
    echo "📲 Select target device:" >&2
    echo "   1) OnePlus (84fbcf31)" >&2
    echo "   2) Samsung Galaxy S23 Ultra (R3CWB0CS63D)" >&2
    echo "   3) Xiaomi Redmi tablet (5dad288e7d91)" >&2
    # Read from controlling terminal when stdin is not a TTY (e.g. piped launch).
    local _tty=/dev/tty
    [ -r "$_tty" ] || _tty=/dev/stdin
    if ! read -r -t 10 -p "Enter choice [1/2/3] (default: 1, auto after 10s): " device_choice < "$_tty"; then
        echo "" >&2
        echo "⏱️  No selection within 10s — using 1 (OnePlus)." >&2
        device_choice="1"
    fi
    case "${device_choice:-1}" in
        1) echo "84fbcf31" ;;
        2) echo "R3CWB0CS63D" ;;
        3) echo "5dad288e7d91" ;;
        *)
            echo "⚠️  Invalid choice '${device_choice}', using default: 1 (OnePlus)" >&2
            echo "84fbcf31"
            ;;
    esac
}

# Args:
#   $1 = backend target: local (default) or vps
#   $2 = Android device id/serial/shortcut (optional)
#        Shortcuts: 1=OnePlus, 2=Samsung, 3=Xiaomi Redmi tablet
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

echo "🚀 Launching Flutter app on $DEVICE_LABEL ($DEVICE_ID) with filtered Logger output..."

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
SERVER_LOG_FILE="/Users/sil/Documents/Work/reignofplay/Dutch/app_dev/python_base_04/tools/logger/server.log"
echo "📝 Writing Logger output to: $SERVER_LOG_FILE (do not redirect script stdout to this file)"

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
    API_URL="https://dutch.mt"
    WS_URL="wss://dutch.mt/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Function to strip ANSI escape codes from a string
# Handles both \x1b[NNm and standalone [NNm (logcat/pipe often drops ESC)
strip_ansi() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\[[0-9;]*m//g'
}

# Function to filter and display only Logger calls
# Only accepts lines that match the exact AppLogger format from start (rejects merged/junk lines)
# Writes only plain text to file and stdout so redirecting/tee to server.log never adds ANSI or junk
filter_logs() {
    # Track last logged message to avoid duplicates
    last_logged=""
    # Strict pattern: [ISO timestamp] [LEVEL] [AppLogger] message (no leading garbage)
    STRICT_PATTERN='^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+)\] \[(INFO|DEBUG|WARNING|ERROR)\] \[AppLogger\] (.*)$'
    # Reject lines that still look like ANSI SGR remnants (e.g. [37m, [0m) so we never pass them through
    ANSI_REMNANT='\[[0-9;]+m'

    while IFS= read -r line; do
        # Strip any remaining ANSI (pipeline sed should have done it; fallback if not)
        line=$(strip_ansi "$line" 2>/dev/null || echo "$line" | sed 's/\[[0-9;]*m//g')
        # Reject lines that still contain ANSI remnants (unstriped codes)
        [[ "$line" =~ $ANSI_REMNANT ]] && continue
        # Require exact match from start of line so we never write malformed or merged lines
        if [[ "$line" =~ $STRICT_PATTERN ]]; then
            timestamp="${BASH_REMATCH[1]}"
            level="${BASH_REMATCH[2]}"
            message="${BASH_REMATCH[3]}"
            [ -z "$message" ] && continue
            log_entry="[$timestamp] [$level] $message"
            if [ "$log_entry" = "$last_logged" ]; then
                continue
            fi
            last_logged="$log_entry"
            echo "$log_entry" >> "$SERVER_LOG_FILE"
            # Plain stdout only: no ANSI, so redirect/tee to server.log never adds colored garbage
            echo "$log_entry"
        fi
    done
}

# Clear logcat buffer to start fresh
echo "🧹 Clearing logcat buffer..."
adb -s "$DEVICE_ID" logcat -c

# Start adb logcat in background to capture Android logs
# Filter for Flutter/Dart tags and AppLogger messages
# logcat default format: I/flutter ( PID): MESSAGE
# Flutter Logger prints: [timestamp] [LEVEL] [AppLogger] message
# The MESSAGE part contains the Flutter log format, so we extract it
echo "📱 Starting logcat capture for AppLogger messages..."

# Store PIDs for cleanup
LOG_PID=""
LOG_PGID=""
ADB_LOGCAT_PIDS=""
CLEANUP_DONE=false

# Function to cleanup all logcat processes
cleanup() {
    # Prevent multiple cleanup calls
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    
    echo "🛑 Stopping logcat capture and cleaning up..."

    # Disable Firebase Analytics DebugView when script exits.
    if [ "$FIREBASE_DEBUGVIEW_ENABLED" = true ]; then
        echo "🧪 Disabling Firebase Analytics DebugView for $ANDROID_APP_ID..."
        adb -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app .none. >/dev/null 2>&1 || true
    fi
    
    # Kill the background logcat pipeline process and its children
    if [ ! -z "$LOG_PID" ]; then
        # Kill the process and all its children
        pkill -P $LOG_PID 2>/dev/null || true
        kill -TERM $LOG_PID 2>/dev/null || true
        sleep 0.3
        # Force kill if still running
        pkill -9 -P $LOG_PID 2>/dev/null || true
        kill -KILL $LOG_PID 2>/dev/null || true
    fi
    
    # Kill process group if we have it
    if [ ! -z "$LOG_PGID" ] && [ "$LOG_PGID" != "0" ]; then
        kill -TERM -$LOG_PGID 2>/dev/null || true
        sleep 0.3
        kill -KILL -$LOG_PGID 2>/dev/null || true
    fi
    
    # Kill any orphaned adb logcat processes for this device
    ADB_LOGCAT_PIDS=$(pgrep -f "adb.*$DEVICE_ID.*logcat" 2>/dev/null || true)
    if [ ! -z "$ADB_LOGCAT_PIDS" ]; then
        echo "🧹 Killing orphaned adb logcat processes: $ADB_LOGCAT_PIDS"
        for pid in $ADB_LOGCAT_PIDS; do
            kill -TERM $pid 2>/dev/null || true
        done
        sleep 0.3
        for pid in $ADB_LOGCAT_PIDS; do
            kill -KILL $pid 2>/dev/null || true
        done
    fi
    
    # Also kill any adb logcat processes that might be writing to our log file
    ADB_LOGCAT_PIDS=$(pgrep -f "logcat.*flutter.*dart" 2>/dev/null || true)
    if [ ! -z "$ADB_LOGCAT_PIDS" ]; then
        for pid in $ADB_LOGCAT_PIDS; do
            kill -TERM $pid 2>/dev/null || true
        done
        sleep 0.3
        for pid in $ADB_LOGCAT_PIDS; do
            kill -KILL $pid 2>/dev/null || true
        done
    fi
    
    # Kill any grep/sed processes that might be part of our pipeline
    PIPELINE_PIDS=$(pgrep -f "grep.*AppLogger|sed.*AppLogger" 2>/dev/null || true)
    if [ ! -z "$PIPELINE_PIDS" ]; then
        for pid in $PIPELINE_PIDS; do
            kill -TERM $pid 2>/dev/null || true
        done
        sleep 0.3
        for pid in $PIPELINE_PIDS; do
            kill -KILL $pid 2>/dev/null || true
        done
    fi
    
    echo "✅ Cleanup completed"
}

# Set up trap to cleanup on exit
trap cleanup EXIT INT TERM HUP

# Export so the background subshell pipeline (adb logcat | ... | filter_logs) can write to server.log
export SERVER_LOG_FILE
export -f strip_ansi filter_logs 2>/dev/null || true

# Strip ANSI in pipeline (no reliance on exported functions). SGR: ESC[NNm or [NNm (logcat may drop ESC)
# Use printf for ESC so macOS sed gets a literal escape character. Strip leading [NNm so broken lines recover.
ANSI_STRIP_SED="s/$(printf '\033')\[[0-9;]*[a-zA-Z]//g; s/\[[0-9;]*m//g; s/^\[[0-9;]*m//g"

# Start logcat in a new process group
(
    # Create new process group
    set -m
    # Capture Flutter and Dart logs, suppress other tags
    # Strip ANSI in pipeline first so filter_logs never sees SGR codes (logcat/pipe can drop ESC)
    # Then grep for AppLogger lines, trim logcat prefix, filter and write clean lines only
    adb -s "$DEVICE_ID" logcat flutter:I dart:I *:S 2>&1 | \
    sed -E "$ANSI_STRIP_SED" | \
    grep "\[.*\] \[.*\] \[AppLogger\]" | \
    sed -E 's/^[^[]*//' | \
    filter_logs
) &
LOG_PID=$!

# Get the process group ID
LOG_PGID=$(ps -o pgid= -p $LOG_PID 2>/dev/null | tr -d ' ' || echo "")

# Give logcat a moment to start
sleep 1

# Test that logcat is working by checking if we can see any flutter logs
echo "🔍 Testing logcat capture (waiting 2 seconds)..."
sleep 2
if ! kill -0 $LOG_PID 2>/dev/null; then
    echo "⚠️  Warning: Logcat process may have exited early"
fi

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

# Launch Flutter app (logs will be captured via logcat)
flutter run \
    -d "$DEVICE_ID" \
    "${DART_DEFINE_ARGS[@]}"

FLUTTER_EXIT_CODE=$?

# Cleanup will happen automatically via trap, but ensure it runs
cleanup

echo "✅ Flutter app launch completed (exit code: $FLUTTER_EXIT_CODE)"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

exit $FLUTTER_EXIT_CODE
