#!/bin/bash
# dash Run Flutter on Android with screen recording
# Flutter dutch on Android with V-key adb screenrecord.
# Delegates to launch_android.sh with screen-record mode enabled.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LAUNCH_ANDROID_SCREENRECORD=1
exec bash "$SCRIPT_DIR/launch_android.sh" "$@"
