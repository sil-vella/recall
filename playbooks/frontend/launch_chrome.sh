#!/bin/bash

# Flutter app launcher for Chrome web. Merges flutter run stdout/stderr and mirrors every
# line to python_base_04/tools/logger/server.log for agent/human debugging (see Documentation/debug/AGENT_DEBUG_LOGS.md).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.local"

# Load env from repo root .env.local (APP_VERSION, Firebase, GOOGLE_CLIENT_ID, Stripe, AdMob, AdSense, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
fi

SERVER_LOG_FILE="$REPO_ROOT/python_base_04/tools/logger/server.log"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/agent_server_log_helpers.sh"
ensure_server_log_dir_and_maybe_rotate
LOG_DIR=$(dirname "$SERVER_LOG_FILE")
if [ ! -w "$LOG_DIR" ]; then
    echo "❌ Error: Log directory is not writable: $LOG_DIR"
    exit 1
fi

if [ -f "$FRONTEND_ENV" ]; then
  echo_and_server_log "✅ Loaded .env.local from: $FRONTEND_ENV"
  if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    GOOGLE_CLIENT_ID_PREVIEW="${GOOGLE_CLIENT_ID:0:40}..."
    echo_and_server_log "   GOOGLE_CLIENT_ID (for web): ${GOOGLE_CLIENT_ID_PREVIEW} (length=${#GOOGLE_CLIENT_ID})"
  else
    echo_and_server_log "   ❌ GOOGLE_CLIENT_ID is empty or unset — Google Sign-In will fail (401 invalid_client). Set it in $FRONTEND_ENV"
  fi
else
  echo_and_server_log "⚠️  Warning: $FRONTEND_ENV not found — dart-defines (Firebase, Google Sign-In, etc.) will be empty."
  echo_and_server_log "   Create and fill the repo root .env.local file first."
fi

echo_and_server_log "🚀 Launching Flutter app on Chrome web (flutter run → server.log for debugging)..."
echo_and_server_log "ℹ️  Firebase Analytics DebugView:"
echo_and_server_log "   • Android: use adb debug mode (see Firebase DebugView docs)."
echo_and_server_log "   • Web: install the Google Analytics Debugger extension in THIS Chrome profile, enable it, reload the app."
echo_and_server_log "     https://chrome.google.com/webstore/detail/google-analytics-debugger/jnkmfdileelhofjcijamephohjechhna"
echo_and_server_log "     (This script uses a dedicated user-data-dir so you install the extension once in the Flutter Chrome window.)"

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" || cd flutter_base_05

echo_and_server_log "📝 Flutter script + flutter run → $SERVER_LOG_FILE ([LAUNCH] = this script, [FLUTTER] = tool stream)"

# Launch Flutter app with Chrome web configuration
echo_and_server_log "🎯 Launching Flutter app with Chrome web configuration..."

# Determine backend target from first argument: 'local' (default) or 'vps'
BACKEND_TARGET="${1:-local}"

if [ "$BACKEND_TARGET" = "vps" ]; then
    API_URL="https://dutch.reignofplay.com"
    WS_URL="wss://dutch.reignofplay.com/ws"
    echo_and_server_log "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="http://localhost:5001"
    WS_URL="ws://localhost:8080"
    echo_and_server_log "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Mirror merged flutter run output to server.log; echo same lines to the terminal (stdout).
filter_logs() {
    while IFS= read -r line; do
        local ts
        ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '%s [FLUTTER] %s\n' "$ts" "$line" >> "$SERVER_LOG_FILE"
        append_agent_json_server_log "$ts" "flutter" "INFO" "$line"
        printf '%s\n' "$line"
    done
}

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

# Diagnostic: verify GOOGLE_CLIENT_ID is in dart-defines (helps debug 401 invalid_client)
GOOGLE_IN_DEFINES=false
for arg in "${DART_DEFINE_ARGS[@]}"; do
  if [[ "$arg" == --dart-define=GOOGLE_CLIENT_ID=* ]]; then
    GOOGLE_IN_DEFINES=true
    VAL="${arg#--dart-define=GOOGLE_CLIENT_ID=}"
    VAL="${VAL%\"}"
    VAL="${VAL#\"}"
    echo_and_server_log "   Dart-define GOOGLE_CLIENT_ID: ${VAL:0:40}... (length=${#VAL})"
    break
  fi
done
if [ "$GOOGLE_IN_DEFINES" = false ]; then
  echo_and_server_log "   ❌ GOOGLE_CLIENT_ID not found in dart-defines — add GOOGLE_CLIENT_ID=... to $FRONTEND_ENV"
fi
echo_and_server_log "   Total dart-defines: ${#DART_DEFINE_ARGS[@]}"

# Default: do NOT quit your normal Chrome — Flutter uses a separate user-data-dir
# (~/.flutter_chrome_profile by default), so profile lock / second-instance issues
# should not affect everyday Chrome windows.
# If you point CHROME_USER_DATA_DIR at your main Chrome profile while Chrome is
# already open, you may get a blank page; set LAUNCH_CHROME_QUIT_CHROME_FIRST=1
# to restore the old "quit all Chrome, wait, then launch" behavior.
if [ "${LAUNCH_CHROME_QUIT_CHROME_FIRST:-0}" = "1" ]; then
  echo_and_server_log "🛑 Quitting Google Chrome (all windows) (LAUNCH_CHROME_QUIT_CHROME_FIRST=1)..."
  osascript -e 'quit app "Google Chrome"' 2>/dev/null || true
  for _ in $(seq 1 20); do
    if ! pgrep -qf "/Applications/Google Chrome.app" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  if pgrep -qf "/Applications/Google Chrome.app" 2>/dev/null; then
    echo_and_server_log "⚠️  Chrome still running — force closing..."
    pkill -9 -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" 2>/dev/null || true
    sleep 1
  fi
  echo_and_server_log "⏳ Waiting 5s before launch..."
  sleep 5
else
  echo_and_server_log "ℹ️  Leaving existing Chrome windows open (dedicated Flutter profile). Set LAUNCH_CHROME_QUIT_CHROME_FIRST=1 if you need the old quit-all-Chrome step."
fi

# Use a wrapper so Flutter's default --disable-extensions is removed (extensions work).
export CHROME_EXECUTABLE="$SCRIPT_DIR/chrome_no_disable_extensions.sh"

# Chrome profile for Flutter web:
# - Default: a dedicated user-data dir (~/.flutter_chrome_profile) so it does NOT conflict
#   with your normal Chrome window. Sharing the system Chrome profile while Chrome is
#   already open often yields a blank white page (profile lock / second instance).
# - Install extensions (e.g. GA Debugger) once in the window Flutter opens; they persist
#   in that folder.
# - To use your main Chrome profile: quit other Chrome first, or use
#   LAUNCH_CHROME_QUIT_CHROME_FIRST=1, e.g.
#   CHROME_USER_DATA_DIR="$HOME/Library/Application Support/Google/Chrome" CHROME_PROFILE_DIR=Default LAUNCH_CHROME_QUIT_CHROME_FIRST=1 ./launch_chrome.sh
CHROME_USER_DATA_DIR="${CHROME_USER_DATA_DIR:-$HOME/.flutter_chrome_profile}"
CHROME_PROFILE_DIR="${CHROME_PROFILE_DIR:-Default}"
echo_and_server_log "🌐 Chrome user-data-dir: $CHROME_USER_DATA_DIR (profile: $CHROME_PROFILE_DIR)"
echo_and_server_log "🔍 DebugView (web): after the app loads, enable GA Debugger on this tab and refresh — then pick this device in Firebase DebugView’s device selector."

# Launch Flutter and filter output
flutter run \
    -d chrome \
    --web-port=3002 \
    --web-hostname=localhost \
    --web-browser-flag="--user-data-dir=$CHROME_USER_DATA_DIR" \
    --web-browser-flag="--profile-directory=$CHROME_PROFILE_DIR" \
    "${DART_DEFINE_ARGS[@]}" 2>&1 | filter_logs

echo_and_server_log "✅ Flutter app launch completed"
echo_and_server_log "📝 Flutter run log: $SERVER_LOG_FILE"
echo_and_server_log "🔍 To view logs: tail -f $SERVER_LOG_FILE"

