#!/usr/bin/env bash
# Run Flutter: full stream to terminal; global.log only I/flutter … lines that contain [dev]
# (repo customlog / debugPrint). No duplicate adb logcat → global.log.
#
# Usage:
#   ./run_flutter_app_to_global_log.sh android <adb_serial>
#   ./run_flutter_app_to_global_log.sh chrome
#
# Dart-define SSOT: repo-root `.env.dart.defines.local` (see flutter_dart_defines_common.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG="$REPO_ROOT/global.log"
FLUTTER_DIR="$REPO_ROOT/flutter_base_05"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.local"

# shellcheck source=flutter_dart_defines_common.sh
source "$SCRIPT_DIR/flutter_dart_defines_common.sh"

export DUTCH_DEV_LOG="${DUTCH_DEV_LOG:-1}"

mode="${1:?usage: $0 android <serial>|chrome}"
shift || true

append_banner() {
  echo "---- run_flutter_app_to_global_log $1 $(date '+%Y-%m-%d %H:%M:%S') repo=$REPO_ROOT ----" >&2
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
  chrome)
    flutter run -d chrome \
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
  *)
    echo "usage: $0 android <adb_serial>|chrome" >&2
    exit 1
    ;;
esac
