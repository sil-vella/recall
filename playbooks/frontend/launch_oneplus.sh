#!/bin/bash

# Flutter app launcher with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

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
cd flutter_base_05

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
    API_URL="https://dutch.reignofplay.com"
    WS_URL="wss://dutch.reignofplay.com/ws"
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
LOG_PID=""
(
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

# Trap to cleanup logcat process on exit
cleanup() {
    if [ ! -z "$LOG_PID" ]; then
        echo "🛑 Stopping logcat capture..."
        kill $LOG_PID 2>/dev/null || true
        wait $LOG_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Give logcat a moment to start
sleep 1

# Test that logcat is working by checking if we can see any flutter logs
echo "🔍 Testing logcat capture (waiting 2 seconds)..."
sleep 2
if ! kill -0 $LOG_PID 2>/dev/null; then
    echo "⚠️  Warning: Logcat process may have exited early"
fi

# Launch Flutter app (logs will be captured via logcat)
flutter run \
    -d 84fbcf31 \
    --dart-define=API_URL="$API_URL" \
    --dart-define=WS_URL="$WS_URL" \
    --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
    --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
    --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
    --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
    --dart-define=ADMOBS_TOP_BANNER01=ca-app-pub-3940256099942544/9214589741 \
    --dart-define=ADMOBS_BOTTOM_BANNER01=ca-app-pub-3940256099942544/9214589741 \
    --dart-define=ADMOBS_INTERSTITIAL01=ca-app-pub-3940256099942544/1033173712 \
    --dart-define=ADMOBS_REWARDED01=ca-app-pub-3940256099942544/5224354917 \
    --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_51MXUtTADcEzB4rlRqLVPRhD0Ti3SRZGyTEQ1crO6YoeGyEfWYBgDxouHygPawog6kKTLVWHxP6DbK1MtBylX2Z6G00JTtIRdgZ \
    --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
    --dart-define=DEBUG_MODE=true \
    --dart-define=ENABLE_REMOTE_LOGGING=true

# Cleanup will happen automatically via trap

echo "✅ Flutter app launch completed"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"
