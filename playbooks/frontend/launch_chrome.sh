#!/bin/bash

# Flutter app launcher for Chrome web with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Firebase/sensitive vars from playbooks/frontend/.env
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

echo "🚀 Launching Flutter app on Chrome web with filtered Logger output..."

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" || cd flutter_base_05

# Set up log file to write to Python server log
SERVER_LOG_FILE="/Users/sil/Documents/Work/reignofplay/Dutch/app_dev/python_base_04/tools/logger/server.log"
echo "📝 Writing Logger output to: $SERVER_LOG_FILE"

# Launch Flutter app with Chrome web configuration
echo "🎯 Launching Flutter app with Chrome web configuration..."

# Determine backend target from first argument: 'local' (default) or 'vps'
BACKEND_TARGET="${1:-local}"

if [ "$BACKEND_TARGET" = "vps" ]; then
    API_URL="https://dutch.mt"
    WS_URL="wss://dutch.mt/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="http://localhost:5001"
    WS_URL="ws://localhost:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

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
            # Note: DutchGameStateUpdater logs are now written directly by the Logger class
            # This script-based logging is a fallback for logs that don't use direct file writing
            echo "[$timestamp] [$level] $message" >> "$SERVER_LOG_FILE"
            
            # Display to console with color coding
            echo -e "${color}[$timestamp] [$level] $message\033[0m"
        fi
    done
}

# Launch Flutter and filter output (Firebase/sensitive from .env via dart-define)
flutter run \
    -d chrome \
    --web-port=3002 \
    --web-hostname=localhost \
    --dart-define=API_URL="$API_URL" \
    --dart-define=WS_URL="$WS_URL" \
    --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
    --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
    --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
    --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
    --dart-define=ADMOBS_TOP_BANNER01="${ADMOBS_TOP_BANNER01:-ca-app-pub-3940256099942544/9214589741}" \
    --dart-define=ADMOBS_BOTTOM_BANNER01="${ADMOBS_BOTTOM_BANNER01:-ca-app-pub-3940256099942544/9214589741}" \
    --dart-define=ADMOBS_INTERSTITIAL01="${ADMOBS_INTERSTITIAL01:-ca-app-pub-3940256099942544/1033173712}" \
    --dart-define=ADMOBS_REWARDED01="${ADMOBS_REWARDED01:-ca-app-pub-3940256099942544/5224354917}" \
    --dart-define=STRIPE_PUBLISHABLE_KEY="${STRIPE_PUBLISHABLE_KEY:-}" \
    --dart-define=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}" \
    --dart-define=GOOGLE_CLIENT_ID_ANDROID="${GOOGLE_CLIENT_ID_ANDROID:-}" \
    --dart-define=FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:-}" \
    --dart-define=FIREBASE_WEB_APP_ID="${FIREBASE_WEB_APP_ID:-}" \
    --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID="${FIREBASE_WEB_MESSAGING_SENDER_ID:-}" \
    --dart-define=FIREBASE_WEB_PROJECT_ID="${FIREBASE_WEB_PROJECT_ID:-}" \
    --dart-define=FIREBASE_WEB_AUTH_DOMAIN="${FIREBASE_WEB_AUTH_DOMAIN:-}" \
    --dart-define=FIREBASE_WEB_STORAGE_BUCKET="${FIREBASE_WEB_STORAGE_BUCKET:-}" \
    --dart-define=FIREBASE_WEB_MEASUREMENT_ID="${FIREBASE_WEB_MEASUREMENT_ID:-}" \
    --dart-define=FIREBASE_ANDROID_API_KEY="${FIREBASE_ANDROID_API_KEY:-}" \
    --dart-define=FIREBASE_ANDROID_APP_ID="${FIREBASE_ANDROID_APP_ID:-}" \
    --dart-define=FIREBASE_ANDROID_MESSAGING_SENDER_ID="${FIREBASE_ANDROID_MESSAGING_SENDER_ID:-}" \
    --dart-define=FIREBASE_ANDROID_PROJECT_ID="${FIREBASE_ANDROID_PROJECT_ID:-}" \
    --dart-define=FIREBASE_ANDROID_STORAGE_BUCKET="${FIREBASE_ANDROID_STORAGE_BUCKET:-}" \
    --dart-define=FIREBASE_IOS_API_KEY="${FIREBASE_IOS_API_KEY:-}" \
    --dart-define=FIREBASE_IOS_APP_ID="${FIREBASE_IOS_APP_ID:-}" \
    --dart-define=FIREBASE_IOS_MESSAGING_SENDER_ID="${FIREBASE_IOS_MESSAGING_SENDER_ID:-}" \
    --dart-define=FIREBASE_IOS_PROJECT_ID="${FIREBASE_IOS_PROJECT_ID:-}" \
    --dart-define=FIREBASE_IOS_STORAGE_BUCKET="${FIREBASE_IOS_STORAGE_BUCKET:-}" \
    --dart-define=FIREBASE_IOS_BUNDLE_ID="${FIREBASE_IOS_BUNDLE_ID:-}" \
    --dart-define=FIREBASE_WINDOWS_API_KEY="${FIREBASE_WINDOWS_API_KEY:-}" \
    --dart-define=FIREBASE_WINDOWS_APP_ID="${FIREBASE_WINDOWS_APP_ID:-}" \
    --dart-define=FIREBASE_WINDOWS_MESSAGING_SENDER_ID="${FIREBASE_WINDOWS_MESSAGING_SENDER_ID:-}" \
    --dart-define=FIREBASE_WINDOWS_PROJECT_ID="${FIREBASE_WINDOWS_PROJECT_ID:-}" \
    --dart-define=FIREBASE_WINDOWS_AUTH_DOMAIN="${FIREBASE_WINDOWS_AUTH_DOMAIN:-}" \
    --dart-define=FIREBASE_WINDOWS_STORAGE_BUCKET="${FIREBASE_WINDOWS_STORAGE_BUCKET:-}" \
    --dart-define=FIREBASE_WINDOWS_MEASUREMENT_ID="${FIREBASE_WINDOWS_MEASUREMENT_ID:-}" \
    --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
    --dart-define=DEBUG_MODE=true \
    --dart-define=ENABLE_REMOTE_LOGGING=true 2>&1 | filter_logs

echo "✅ Flutter app launch completed"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

