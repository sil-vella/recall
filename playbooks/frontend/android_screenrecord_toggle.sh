#!/usr/bin/env bash
# Toggle screen record for one device (used from flutter PTY relay on V key).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"
# shellcheck source=android_screenrecord_lib.sh
source "$SCRIPT_DIR/android_screenrecord_lib.sh"

serial="${1:-$(android_default_oneplus_serial)}"
serial="$(resolve_device_id "$serial")"
android_ensure_adb_path
ADB="$(find_adb)"
export ADB REPO_ROOT RECORDINGS_DIR="$REPO_ROOT/recordings"
android_screenrecord_toggle "$serial"
