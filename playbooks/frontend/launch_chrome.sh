#!/bin/bash

# Flutter app launcher for Chrome web.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.local"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.local"

# Load repo-root .env.local for shell / tooling (e.g. GOOGLE_CLIENT_ID checks). Dart compile-time keys: .env.dart.defines.local.
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/agent_server_log_helpers.sh"
ensure_server_log_dir_and_maybe_rotate

if [ -f "$FRONTEND_ENV" ]; then
  echo_and_server_log "✅ Loaded .env.local from: $FRONTEND_ENV"
  if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    GOOGLE_CLIENT_ID_PREVIEW="${GOOGLE_CLIENT_ID:0:40}..."
    echo_and_server_log "   GOOGLE_CLIENT_ID (for web): ${GOOGLE_CLIENT_ID_PREVIEW} (length=${#GOOGLE_CLIENT_ID})"
  else
    echo_and_server_log "   ❌ GOOGLE_CLIENT_ID is empty or unset — Google Sign-In will fail (401 invalid_client). Set it in $FRONTEND_ENV"
  fi
else
  echo_and_server_log "⚠️  Warning: $FRONTEND_ENV not found — shell-sourced vars (e.g. tooling-only keys) unavailable. Flutter dart-defines: $DART_DEFINES_ENV"
  echo_and_server_log "   Create $FRONTEND_ENV if you still need a separate shell env file."
fi

echo_and_server_log "🚀 Launching Flutter app on Chrome web…"
echo_and_server_log "ℹ️  Firebase Analytics DebugView:"
echo_and_server_log "   • Android: use adb debug mode (see Firebase DebugView docs)."
echo_and_server_log "   • Web: install the Google Analytics Debugger extension in THIS Chrome profile, enable it, reload the app."
echo_and_server_log "     https://chrome.google.com/webstore/detail/google-analytics-debugger/jnkmfdileelhofjcijamephohjechhna"
echo_and_server_log "     (This script uses a dedicated user-data-dir so you install the extension once in the Flutter Chrome window.)"

# Navigate to Flutter project directory
cd "$SCRIPT_DIR/../../flutter_base_05" || cd flutter_base_05

echo_and_server_log "🎯 Launching Flutter app with Chrome web configuration..."

echo_and_server_log "📝 Dart-define SSOT: $DART_DEFINES_ENV (API_URL, WS_URL, JWT_*, …; no script overrides)"

filter_logs() {
    while IFS= read -r line; do
        printf '%s\n' "$line"
    done
}

# shellcheck source=flutter_dart_defines_common.sh
source "$SCRIPT_DIR/flutter_dart_defines_common.sh"
flutter_dart_defines_require_python || exit 1
flutter_dart_defines_prepare "$DART_DEFINES_ENV" || exit 1
trap 'rm -f "${DART_DEF_JSON:-}"' EXIT INT TERM HUP
flutter_dart_defines_print_summary chrome

# Diagnostic: GOOGLE_CLIENT_ID (helps debug 401 invalid_client)
GOOGLE_CHECK="$(python3 -c '
import json, os
p = os.environ["DART_DEF_JSON"]
v = (json.load(open(p, encoding="utf-8")).get("GOOGLE_CLIENT_ID") or "")
print(len(v))
print(v[:40] if v else "")
' 2>/dev/null)" || GOOGLE_CHECK=""
GOOGLE_LEN="$(echo "$GOOGLE_CHECK" | sed -n '1p')"
GOOGLE_PRE="$(echo "$GOOGLE_CHECK" | sed -n '2p')"
if [[ "$GOOGLE_LEN" =~ ^[0-9]+$ ]] && [ "$GOOGLE_LEN" -gt 0 ]; then
  echo_and_server_log "   GOOGLE_CLIENT_ID (for web): ${GOOGLE_PRE}... (length=$GOOGLE_LEN)"
else
  echo_and_server_log "   ❌ GOOGLE_CLIENT_ID missing or empty in dart-define file — set in $DART_DEFINES_ENV"
fi

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

echo_and_server_log "⏳ Starting flutter run (compile may take 1–2 min with little output)…"

# Launch Flutter and filter output
flutter run \
    -d chrome \
    --dart-define=DUTCH_DEV_LOG=1 \
    --web-port=3002 \
    --web-hostname=localhost \
    --web-browser-flag="--user-data-dir=$CHROME_USER_DATA_DIR" \
    --web-browser-flag="--profile-directory=$CHROME_PROFILE_DIR" \
    --dart-define-from-file="$DART_DEF_JSON" \
    2>&1 | filter_logs

echo_and_server_log "✅ Flutter app launch completed"
