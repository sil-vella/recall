#!/bin/bash

# Flutter app launcher with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

# Note: We'll use process groups for cleanup but won't enable full job control
# as it can interfere with VS Code's terminal handling

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Firebase/sensitive vars from playbooks/frontend/.env
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

echo "🚀 Launching Flutter app on OnePlus device (84fbcf31) with filtered Logger output..."

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb not found. Please install Android SDK and add to PATH"
    exit 1
fi

# Check if device is connected
echo "📱 Checking device connection..."
adb devices | grep -q "84fbcf31"
if [ $? -ne 0 ]; then
    echo "❌ Error: OnePlus device (84fbcf31) not found"
    echo "Available devices:"
    adb devices
    exit 1
fi

echo "✅ OnePlus device (84fbcf31) is connected"

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" 2>/dev/null || cd flutter_base_05

# Set up log file to write to Python server log
SERVER_LOG_FILE="/Users/sil/Documents/Work/reignofplay/Dutch/app_dev/python_base_04/tools/logger/server.log"
echo "📝 Writing Logger output to: $SERVER_LOG_FILE"

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

# Clear log file at start of each run to avoid continuation from previous runs
echo "🧹 Clearing previous log entries..."
> "$SERVER_LOG_FILE"
echo "✅ Log file cleared, starting fresh session"

# Launch Flutter app with OnePlus device configuration
echo "🎯 Launching Flutter app with OnePlus configuration..."

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
strip_ansi() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

# Function to filter and display only Logger calls
filter_logs() {
    # Track last logged message to avoid duplicates
    last_logged=""
    
    while IFS= read -r line; do
        # Strip any ANSI escape codes from the input line first
        line=$(strip_ansi "$line")
        
        # Check if this is a Logger call (contains timestamp, level, and AppLogger)
        # Android logcat format: MM-DD HH:MM:SS.mmm  PID  TID  TAG  MESSAGE
        # Flutter logs may come in different formats, so we check for AppLogger pattern
        if echo "$line" | grep -q "\[.*\] \[.*\] \[AppLogger\]"; then
            # Extract original timestamp, level, and message from Flutter log
            # Format: [timestamp] [LEVEL] [AppLogger] message
            # Extract timestamp (first bracket group)
            timestamp=$(echo "$line" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
            
            # Extract level (second bracket group)
            level=$(echo "$line" | sed -n 's/^\[[^]]*\] \[\([^]]*\)\].*/\1/p')
            
            # Extract message (everything after [AppLogger] )
            message=$(echo "$line" | sed -n 's/^\[[^]]*\] \[[^]]*\] \[AppLogger\] //p')
            
            # Skip if timestamp or level extraction failed (empty values)
            if [ -z "$timestamp" ] || [ -z "$level" ]; then
                continue
            fi
            
            # Skip if message is empty (nothing to log)
            if [ -z "$message" ]; then
                continue
            fi
            
            # Create a unique log entry identifier to avoid duplicates
            log_entry="[$timestamp] [$level] $message"
            
            # Skip if this is the same as the last logged entry (avoid duplicates)
            if [ "$log_entry" = "$last_logged" ]; then
                continue
            fi
            last_logged="$log_entry"
            
            # Determine color based on level (for console display only)
            case "$level" in
                ERROR)
                    color="\033[31m"  # Red
                    ;;
                WARNING)
                    color="\033[33m"  # Yellow
                    ;;
                INFO)
                    color="\033[32m"  # Green
                    ;;
                DEBUG)
                    color="\033[36m"  # Cyan
                    ;;
                *)
                    color="\033[37m"  # White
                    ;;
            esac
            
            # Write clean formatted log to Python server log file (NO ANSI codes)
            # Note: DutchGameStateUpdater logs are now written directly by the Logger class
            # This script-based logging is a fallback for logs that don't use direct file writing
            echo "$log_entry" >> "$SERVER_LOG_FILE"
            
            # Display to console with color coding (ANSI codes only for terminal)
            echo -e "${color}$log_entry\033[0m"
        fi
    done
}

# Clear logcat buffer to start fresh
echo "🧹 Clearing logcat buffer..."
adb -s 84fbcf31 logcat -c

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
    ADB_LOGCAT_PIDS=$(pgrep -f "adb.*84fbcf31.*logcat" 2>/dev/null || true)
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

# Start logcat in a new process group
(
    # Create new process group
    set -m
    # Capture Flutter and Dart logs, suppress other tags
    # Extract message part which contains: [timestamp] [LEVEL] [AppLogger] message
    # logcat format: I/flutter ( PID): [timestamp] [LEVEL] [AppLogger] message
    # We need to extract everything starting from the first [
    # Note: ANSI codes will be stripped in filter_logs function
    adb -s 84fbcf31 logcat flutter:I dart:I *:S 2>&1 | \
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
done < <(build_dart_defines_from_env "$SCRIPT_DIR/.env")
DART_DEFINE_ARGS+=( --dart-define=API_URL="$API_URL" --dart-define=WS_URL="$WS_URL" )
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
    -d 84fbcf31 \
    "${DART_DEFINE_ARGS[@]}"

FLUTTER_EXIT_CODE=$?

# Cleanup will happen automatically via trap, but ensure it runs
cleanup

echo "✅ Flutter app launch completed (exit code: $FLUTTER_EXIT_CODE)"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

exit $FLUTTER_EXIT_CODE
