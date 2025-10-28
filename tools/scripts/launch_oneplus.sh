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
SERVER_LOG_FILE="/Users/sil/Documents/Work/reignofplay/Recall/app_dev/python_base_04/tools/logger/server.log"
echo "📝 Writing Logger output to: $SERVER_LOG_FILE"

# Launch Flutter app with OnePlus device configuration
echo "🎯 Launching Flutter app with OnePlus configuration..."

# Function to filter and display only Logger calls
filter_logs() {
    while IFS= read -r line; do
        # Check if this is a Logger call (contains timestamp, level, and AppLogger)
        if echo "$line" | grep -q "\[.*\] \[.*\] \[AppLogger\]"; then
            # Extract and format the log entry
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Try to extract the log level and message
            if echo "$line" | grep -q "\[ERROR\]"; then
                level="ERROR"
                color="\033[31m"  # Red
            elif echo "$line" | grep -q "\[WARNING\]"; then
                level="WARNING"
                color="\033[33m"  # Yellow
            elif echo "$line" | grep -q "\[INFO\]"; then
                level="INFO"
                color="\033[32m"  # Green
            elif echo "$line" | grep -q "\[DEBUG\]"; then
                level="DEBUG"
                color="\033[36m"  # Cyan
            else
                level="LOG"
                color="\033[37m"  # White
            fi
            
            # Write formatted log to Python server log file
            # Filter out RecallGameStateUpdater debug/validation logs to reduce noise
            if ! echo "$line" | grep -qE "(RecallGameStateUpdater|Validating field|validation successful|Rebuilding slice)"; then
                echo "[$timestamp] [FLUTTER] [$level] $line" >> "$SERVER_LOG_FILE"
            fi
            
            # Display to console with color coding
            echo -e "${color}[$timestamp] [$level] $line\033[0m"
        fi
    done
}

# Launch Flutter and filter output
flutter run \
    -d 84fbcf31 \
    --dart-define=API_URL_LOCAL=http://192.168.178.81:5001 \
    --dart-define=API_URL=https://fmif.reignofplay.com \
    --dart-define=WS_URL_LOCAL=ws://192.168.178.81:8080 \
    --dart-define=WS_URL=wss://fmif.reignofplay.com \
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
    --dart-define=ENABLE_REMOTE_LOGGING=true 2>&1 | filter_logs

echo "✅ Flutter app launch completed"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view Flutter logs: tail -f $SERVER_LOG_FILE | grep FLUTTER"
