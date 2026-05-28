#!/usr/bin/env bash
# Run Flutter: full stream to terminal; global.log only I/flutter … lines that contain [dev]
# (repo customlog / debugPrint). No duplicate adb logcat → global.log.
#
# Usage:
#   ./run_flutter_app_to_global_log.sh android <adb_serial>
#   ./run_flutter_app_to_global_log.sh ios <simulator_or_device_id>
#   ./run_flutter_app_to_global_log.sh chrome
#   ./run_flutter_app_to_global_log.sh --prod chrome   # .env.dart.defines.prod (release URLs / AdMob)
#
# Dart-define SSOT: `.env.dart.defines.local` (default) or `.env.dart.defines.prod` with --prod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG="$REPO_ROOT/global.log"
FLUTTER_DIR="$REPO_ROOT/flutter_base_05"

if [[ "${1:-}" == "--prod" ]]; then
  shift
  DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.prod"
  echo "⚠️  Production dart-defines: $DART_DEFINES_ENV (live API/WS/AdMob — same as release builds)" >&2
else
  DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.local"
fi

# shellcheck source=flutter_dart_defines_common.sh
source "$SCRIPT_DIR/flutter_dart_defines_common.sh"

export DUTCH_DEV_LOG="${DUTCH_DEV_LOG:-1}"

mode="${1:?usage: $0 android <serial>|ios <device_id>|chrome}"
shift || true

append_banner() {
  echo "---- run_flutter_app_to_global_log $1 $(date '+%Y-%m-%d %H:%M:%S') repo=$REPO_ROOT ----" >&2
}

# Boot an iOS simulator when [device_id] matches simctl; wait until Flutter lists it.
ios_ensure_device_ready() {
  local device_id="$1"

  if ! command -v xcrun &>/dev/null; then
    echo "xcrun not found — install Xcode command line tools." >&2
    exit 1
  fi

  local sim_line=""
  sim_line="$(xcrun simctl list devices available 2>/dev/null | grep -F "$device_id" | head -1 || true)"
  if [[ -z "$sim_line" ]]; then
    # Physical device or unknown id — flutter run --device-timeout waits for attach.
    return 0
  fi

  local udid="$device_id"
  if [[ "$sim_line" =~ \(([0-9A-Fa-f-]{36})\) ]]; then
    udid="${BASH_REMATCH[1]}"
  fi

  local boot_state=""
  boot_state="$(xcrun simctl list devices 2>/dev/null | grep -F "$udid" | grep -oE '(Booted|Shutdown)' | head -1 || true)"
  if [[ "$boot_state" != "Booted" ]]; then
    echo "Booting iOS simulator ($udid)..." >&2
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    echo "Waiting for simulator to finish booting..." >&2
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    open -a Simulator --args -CurrentDeviceUDID "$udid" >/dev/null 2>&1 \
      || open -a Simulator >/dev/null 2>&1 \
      || true
  fi
}

flutter_dart_defines_require_python || exit 1
flutter_dart_defines_prepare "$DART_DEFINES_ENV" || exit 1
cleanup_json() { rm -f "${DART_DEF_JSON:-}"; }
trap cleanup_json EXIT INT TERM HUP

cd "$FLUTTER_DIR"

append_banner "start mode=$mode"
flutter_dart_defines_print_summary "$mode"

case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
  android)
    serial="${1:?usage: $0 android <adb_serial>}"
    adb_pt="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools"
    export PATH="$adb_pt:$PATH"
    if ! command -v adb &>/dev/null; then
      echo "adb not found (set ANDROID_HOME or install platform-tools)." >&2
      exit 1
    fi
    flutter run -d "$serial" \
      --dart-define=DUTCH_DEV_LOG=1 \
      --dart-define-from-file="$DART_DEF_JSON" 2>&1 | awk -v logf="$LOG" '
      {
        print
        if (($0 ~ /I\/flutter/ || $0 ~ /I flutter/) && $0 ~ /\[dev\]/) {
          if ($0 != prev) {
            print >> logf
            fflush(logf)
            prev = $0
          }
        }
      }
    '
    exit "${PIPESTATUS[0]}"
    ;;
  ios)
    device_id="${1:?usage: $0 ios <simulator_or_device_id>}"
    ios_ensure_device_ready "$device_id"
    flutter run -d "$device_id" \
      --device-timeout=90 \
      --dart-define=DUTCH_DEV_LOG=1 \
      --dart-define-from-file="$DART_DEF_JSON" 2>&1 | awk -v logf="$LOG" '
      {
        print
        if (($0 ~ /I\/flutter/ || $0 ~ /I flutter/) && $0 ~ /\[dev\]/) {
          if ($0 != prev) {
            print >> logf
            fflush(logf)
            prev = $0
          }
        }
      }
    '
    exit "${PIPESTATUS[0]}"
    ;;
  chrome)
    # Web: no Firebase (no FIREBASE_WEB_* / no web SDK config). Native devices keep FIREBASE_SWITCH from env file.
    # Fixed host/port (matches launch_chrome.sh) — avoids random ports and profile conflicts.
    export CHROME_EXECUTABLE="${CHROME_EXECUTABLE:-$SCRIPT_DIR/chrome_no_disable_extensions.sh}"
    chrome_user_data="${CHROME_USER_DATA_DIR:-$HOME/.flutter_chrome_profile}"
    chrome_profile="${CHROME_PROFILE_DIR:-Default}"
    echo "Chrome: http://localhost:3002 (user-data-dir=$chrome_user_data, Firebase off)" >&2
    flutter run -d chrome \
      --dart-define=DUTCH_DEV_LOG=1 \
      --dart-define=FIREBASE_SWITCH=false \
      --web-port=3002 \
      --web-hostname=localhost \
      --web-browser-flag="--user-data-dir=$chrome_user_data" \
      --web-browser-flag="--profile-directory=$chrome_profile" \
      --dart-define-from-file="$DART_DEF_JSON" 2>&1 | awk -v logf="$LOG" '
      {
        print
        # Web: logs often lack the Android "I/flutter" prefix; match any [dev] line.
        if ($0 ~ /\[dev\]/) {
          if ($0 != prev) {
            print >> logf
            fflush(logf)
            prev = $0
          }
        }
      }
    '
    exit "${PIPESTATUS[0]}"
    ;;
  *)
    echo "usage: $0 [--prod] android <adb_serial>|ios <device_id>|chrome" >&2
    exit 1
    ;;
esac
