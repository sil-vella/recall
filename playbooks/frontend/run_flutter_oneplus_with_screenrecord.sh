#!/usr/bin/env bash
# OnePlus local dev launch — same as VS Code "Dutch: Flutter (OnePlus) — .env.dart.defines.local"
# plus V key (like R for hot restart) to toggle adb screenrecord while flutter run is active.
#
# VS Code equivalent:
#   run_flutter_app_to_global_log.sh android 84fbcf31
#
# Usage:
#   ./playbooks/frontend/run_flutter_oneplus_with_screenrecord.sh
#   ./playbooks/frontend/run_flutter_oneplus_with_screenrecord.sh <adb_serial>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG="$REPO_ROOT/global.log"
FLUTTER_DIR="$REPO_ROOT/flutter_base_05"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.local"
DEVICE_ID="${1:-84fbcf31}"

# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"
# shellcheck source=android_screenrecord_lib.sh
source "$SCRIPT_DIR/android_screenrecord_lib.sh"
# shellcheck source=flutter_dart_defines_common.sh
source "$SCRIPT_DIR/flutter_dart_defines_common.sh"

export DUTCH_DEV_LOG="${DUTCH_DEV_LOG:-1}"
export REPO_ROOT

android_ensure_adb_path
DEVICE_ID="$(resolve_device_id "$DEVICE_ID")"
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
android_assert_device_connected "$DEVICE_ID" || exit 1

append_banner() {
  echo "---- run_flutter_oneplus_with_screenrecord $1 $(date '+%Y-%m-%d %H:%M:%S') device=$DEVICE_ID ----" >&2
}

flutter_dart_defines_require_python || exit 1
flutter_dart_defines_prepare "$DART_DEFINES_ENV" || exit 1
ADB="$(find_adb)"
export ADB REPO_ROOT RECORDINGS_DIR="$REPO_ROOT/recordings"

cleanup_on_exit() {
  rm -f "${DART_DEF_JSON:-}"
  if android_screenrecord_is_active "$DEVICE_ID" 2>/dev/null; then
    echo "⏹️  Stopping active screen record before exit…" >&2
    android_screenrecord_stop "$DEVICE_ID" || true
  fi
}
trap cleanup_on_exit EXIT INT TERM HUP

# shellcheck source=read_pubspec_version.sh
source "$SCRIPT_DIR/read_pubspec_version.sh"
read_pubspec_version || exit 1

append_banner "start"
flutter_dart_defines_print_summary android
echo "   device=$DEVICE_LABEL ($DEVICE_ID)" >&2
echo "   pubspec versionName=$PUBSPEC_VERSION_NAME build-number=$PUBSPEC_BUILD_NUMBER" >&2
echo "   Press V during flutter run to start/stop screen record → $REPO_ROOT/recordings/" >&2

cd "$FLUTTER_DIR"

python3 "$SCRIPT_DIR/flutter_run_android_interactive.py" \
  --device "$DEVICE_ID" \
  --dart-define-from-file "$DART_DEF_JSON" \
  --cwd "$FLUTTER_DIR" 2>&1 | awk -v logf="$LOG" '
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
