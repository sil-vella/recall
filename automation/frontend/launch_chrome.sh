#!/bin/bash
# dash Run Flutter dutch on Chrome
# Flutter dutch (flutter_base_06) on Chrome — env from wfrun only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"

require_wfrun() {
  if [[ -z "${WFRUN_MODE:-}" || -z "${WFRUN_PROFILE:-}" ]]; then
    echo "❌ Run via wfrun — this script expects exported env (WFRUN_MODE, WFRUN_PROFILE)."
    exit 1
  fi
  if [[ "$WFRUN_PROFILE" != frontend ]]; then
    echo "❌ WFRUN_PROFILE must be frontend (dart-defines env not loaded)."
    exit 1
  fi
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "❌ $name must be set in ${WFRUN_DART_DEFINES_FILE:-.env.dart.defines.*}"
    exit 1
  fi
}

require_wfrun

require_var ARCORI_API_REST_URL
require_var ARCORI_API_WS_URL
require_var ARCORI_DART_WS_URL
require_var FLUTTER_WEB_PORT
require_var FLUTTER_WEB_HOSTNAME

echo "🌐 wfrun ($WFRUN_MODE): API=$ARCORI_API_REST_URL  Dart WS=$ARCORI_DART_WS_URL  API WS=$ARCORI_API_WS_URL"
echo "🌐 Flutter web: $FLUTTER_WEB_HOSTNAME:$FLUTTER_WEB_PORT"

if [[ ! -d "$FLUTTER_DIR" ]]; then
  echo "❌ Flutter project not found: $FLUTTER_DIR"
  exit 1
fi
cd "$FLUTTER_DIR"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/dart_defines_from_env.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/global_log_filter.sh"
DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=("$line")
done < <(build_dart_defines_from_wfrun_env)

# Web dev never sends GA4 (native-only in this template).
DART_DEFINE_ARGS+=("--dart-define=FIREBASE_SWITCH=false")

chmod +x "$SCRIPT_DIR/chrome_no_disable_extensions.sh" 2>/dev/null || true
export CHROME_EXECUTABLE="$SCRIPT_DIR/chrome_no_disable_extensions.sh"

CHROME_USER_DATA_DIR="${CHROME_USER_DATA_DIR:-$HOME/.flutter_chrome_profile_Dutch}"
echo "🌐 Chrome user-data-dir: $CHROME_USER_DATA_DIR"
echo "🎯 flutter run -d chrome (project: $FLUTTER_DIR)"
echo "⌨️  Shift+R (or r) — hot reload  |  Flutter default R is hot restart; remapped here"

# Forward terminal keys to flutter; remap R/r → r (hot reload, not hot restart).
run_flutter_with_shift_r_reload() {
  local fifo fifo_out pid filter_pid tty_settings key flutter_exit
  fifo="$(mktemp -u "${TMPDIR:-/tmp}/flutter_stdin.XXXXXX")"
  fifo_out="$(mktemp -u "${TMPDIR:-/tmp}/flutter_stdout.XXXXXX")"
  mkfifo "$fifo"
  mkfifo "$fifo_out"

  restore_tty() {
    rm -f "$fifo" "$fifo_out"
    if [[ -n "${tty_settings:-}" ]]; then
      stty "$tty_settings" < /dev/tty 2>/dev/null || true
    else
      stty sane < /dev/tty 2>/dev/null || true
    fi
  }
  trap restore_tty EXIT INT TERM

  flutter run \
    -d chrome \
    --web-port="$FLUTTER_WEB_PORT" \
    --web-hostname="$FLUTTER_WEB_HOSTNAME" \
    --web-browser-flag="--user-data-dir=$CHROME_USER_DATA_DIR" \
    "${DART_DEFINE_ARGS[@]}" \
    < "$fifo" >"$fifo_out" 2>&1 &
  pid=$!

  filter_flutter_to_global_log <"$fifo_out" &
  filter_pid=$!

  exec 3>"$fifo"

  tty_settings="$(stty -g < /dev/tty)"
  stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null || true

  set +e
  while kill -0 "$pid" 2>/dev/null; do
    if ! IFS= read -r -n 1 key < /dev/tty 2>/dev/null; then
      sleep 0.05
      continue
    fi
    case "$key" in
      $'\x03')
        kill "$pid" 2>/dev/null || true
        break
        ;;
      R|r)
        printf 'r' >&3
        ;;
      *)
        printf '%s' "$key" >&3
        ;;
    esac
  done
  set -e

  wait "$pid" 2>/dev/null || true
  flutter_exit=$?
  wait "$filter_pid" 2>/dev/null || true
  return "$flutter_exit"
}

run_flutter_with_shift_r_reload
