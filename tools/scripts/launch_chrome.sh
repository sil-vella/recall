#!/bin/bash

# Flutter app launcher for Chrome web with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

echo "🚀 Launching Flutter app on Chrome web with filtered Logger output..."

# Navigate to Flutter project directory
cd flutter_base_05

# Set up log file to write to Python server log
SERVER_LOG_FILE="/Users/sil/Documents/Work/reignofplay/Cleco/app_dev/python_base_04/tools/logger/server.log"
echo "📝 Writing Logger output to: $SERVER_LOG_FILE"

# Launch Flutter app with Chrome web configuration
echo "🎯 Launching Flutter app with Chrome web configuration..."

# Function to filter and display only Logger calls
filter_logs() {
    while IFS= read -r line; do
        # Check if this is a Logger call (contains timestamp, level, and AppLogger)
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
            
            # Determine color based on level
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
            
            # Write clean formatted log to Python server log file
            # Filter out ClecoGameStateUpdater debug/validation logs to reduce noise
            if ! echo "$message" | grep -qE "(ClecoGameStateUpdater|Validating field|validation successful|Rebuilding slice)"; then
                echo "[$timestamp] [$level] $message" >> "$SERVER_LOG_FILE"
            fi
            
            # Display to console with color coding
            echo -e "${color}[$timestamp] [$level] $message\033[0m"
        fi
    done
}

# Launch Flutter and filter output
flutter run \
    -d chrome \
    --web-port=3002 \
    --web-hostname=localhost \
    --dart-define=API_URL_LOCAL=http://localhost:5001 \
    --dart-define=API_URL=https://fmif.reignofplay.com \
    --dart-define=WS_URL_LOCAL=ws://localhost:8080 \
    --dart-define=WS_URL=wss://fmif.reignofplay.com \
    --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
    --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
    --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
    --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
    --dart-define=ADMOBS_TOP_BANNER01=ca-app-pub-3940256099942544/9214589741 \
    --dart-define=ADMOBS_BOTTOM_BANNER01=ca-app-pub-3940256099942544/9214589741 \
    --dart-define=ADMOBS_INTERSTITIAL01=ca-app-pub-3940256099942544/1033173712 \
    --dart-define=ADMOBS_REWARDED01=ca-app-pub-3940256099942544/5224354917 \
    --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_51MXUtTADcEzB4rlRqLVPRhD0Ti3SRZGyTEQ1crO6YoeGyEfWYBgDxouHygPawog6kKTLVWhxP6DbK1MtBylX2Z6G00JTtIRdgZ \
    --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
    --dart-define=DEBUG_MODE=true \
    --dart-define=ENABLE_REMOTE_LOGGING=true 2>&1 | filter_logs

echo "✅ Flutter app launch completed"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

