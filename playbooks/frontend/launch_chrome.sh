#!/bin/bash

# Flutter app launcher for Chrome web with filtered Logger output only
# Shows only your custom Logger calls, filters out all system logs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env"

# Load env from repo root .env (APP_VERSION, Firebase, GOOGLE_CLIENT_ID, Stripe, AdMob, AdSense, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
  echo "✅ Loaded .env from: $FRONTEND_ENV"
  if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    GOOGLE_CLIENT_ID_PREVIEW="${GOOGLE_CLIENT_ID:0:40}..."
    echo "   GOOGLE_CLIENT_ID (for web): ${GOOGLE_CLIENT_ID_PREVIEW} (length=${#GOOGLE_CLIENT_ID})"
  else
    echo "   ❌ GOOGLE_CLIENT_ID is empty or unset — Google Sign-In will fail (401 invalid_client). Set it in $FRONTEND_ENV"
  fi
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — dart-defines (Firebase, Google Sign-In, etc.) will be empty."
  echo "   Create and fill the repo root .env file first."
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

# Build --dart-define from .env (all vars) then overrides and run-only extras
source "$SCRIPT_DIR/dart_defines_from_env.sh"
DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=( "$line" )
done < <(build_dart_defines_from_env "$FRONTEND_ENV")
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

# Diagnostic: verify GOOGLE_CLIENT_ID is in dart-defines (helps debug 401 invalid_client)
GOOGLE_IN_DEFINES=false
for arg in "${DART_DEFINE_ARGS[@]}"; do
  if [[ "$arg" == --dart-define=GOOGLE_CLIENT_ID=* ]]; then
    GOOGLE_IN_DEFINES=true
    VAL="${arg#--dart-define=GOOGLE_CLIENT_ID=}"
    VAL="${VAL%\"}"
    VAL="${VAL#\"}"
    echo "   Dart-define GOOGLE_CLIENT_ID: ${VAL:0:40}... (length=${#VAL})"
    break
  fi
done
if [ "$GOOGLE_IN_DEFINES" = false ]; then
  echo "   ❌ GOOGLE_CLIENT_ID not found in dart-defines — add GOOGLE_CLIENT_ID=... to $FRONTEND_ENV"
fi
echo "   Total dart-defines: ${#DART_DEFINE_ARGS[@]}"

# Launch Flutter and filter output
flutter run \
    -d chrome \
    --web-port=3002 \
    --web-hostname=localhost \
    "${DART_DEFINE_ARGS[@]}" 2>&1 | filter_logs

echo "✅ Flutter app launch completed"
echo "📝 Logger output written to: $SERVER_LOG_FILE"
echo "🔍 To view logs: tail -f $SERVER_LOG_FILE"

