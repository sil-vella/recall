#!/bin/bash
# Record Android device screen via adb, pull MP4 to repo recordings/ with a timestamped name.
#
# Usage:
#   ./playbooks/frontend/adb_screenrecord.sh [seconds] [device]
#   ./playbooks/frontend/adb_screenrecord.sh -i [device]     # until Ctrl+C
#   ./playbooks/frontend/adb_screenrecord.sh -h
#
# While flutter run is active, prefer run_flutter_oneplus_with_screenrecord.sh (V = toggle).
#
# Device: serial, or shortcut 1=OnePlus, 2=Samsung, 3=Xiaomi tablet, 4=DOOGEE
#         (same as launch_oneplus.sh). Override with ANDROID_DEVICE_ID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECORDINGS_DIR="$REPO_ROOT/recordings"
REMOTE_PATH="/sdcard/dutch_screenrecord_tmp.mp4"

DEFAULT_SECONDS=30
TIME_LIMIT=""
INTERACTIVE=false
SIZE="${SCREENRECORD_SIZE:-}"
BIT_RATE="${SCREENRECORD_BIT_RATE:-8000000}"
DEVICE_ARG=""

# shellcheck source=android_device_common.sh
source "$SCRIPT_DIR/android_device_common.sh"
# shellcheck source=android_screenrecord_lib.sh
source "$SCRIPT_DIR/android_screenrecord_lib.sh"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

parse_args() {
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage 0 ;;
      -i|--interactive) INTERACTIVE=true; shift ;;
      -*) echo "Unknown option: $1" >&2; usage 1 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  if [ "${#positional[@]}" -ge 1 ] && [[ "${positional[0]}" =~ ^[0-9]+$ ]]; then
    TIME_LIMIT="${positional[0]}"
    DEVICE_ARG="${positional[1]:-}"
  else
    TIME_LIMIT="$DEFAULT_SECONDS"
    DEVICE_ARG="${positional[0]:-}"
  fi
}

main() {
  parse_args "$@"

  android_ensure_adb_path
  ADB="$(find_adb)"
  export ADB REPO_ROOT RECORDINGS_DIR REMOTE_PATH SCREENRECORD_BIT_RATE
  export SCREENRECORD_SIZE="${SCREENRECORD_SIZE:-}"

  local raw_input="${ANDROID_DEVICE_ID:-${DEVICE_ARG:-}}"
  if [ -z "$raw_input" ]; then
    raw_input="$(prompt_for_device_selection)"
  fi
  local serial
  serial="$(resolve_device_id "$raw_input")"
  local label
  label="$(get_device_label "$serial")"
  android_assert_device_connected "$serial" || exit 1

  if [ "$INTERACTIVE" = true ]; then
    echo "🎬 Recording on $label ($serial) — press Ctrl+C to stop (no audio)." >&2
    echo "   Tip: use run_flutter_oneplus_with_screenrecord.sh and press V instead." >&2
    android_screenrecord_start "$serial" || exit 1
    trap 'android_screenrecord_stop "$serial"' INT TERM
    while android_screenrecord_is_active "$serial"; do
      sleep 1
    done
    return 0
  fi

  if [ "$TIME_LIMIT" -gt 180 ] 2>/dev/null; then
    echo "⚠️  adb screenrecord max is 180s; clamping to 180." >&2
    TIME_LIMIT=180
  fi
  echo "🎬 Recording ${TIME_LIMIT}s on $label ($serial) (no audio)..." >&2

  local ts out_file
  ts="$(date +%Y%m%d_%H%M%S)"
  out_file="$RECORDINGS_DIR/dutch_screen_${ts}.mp4"
  mkdir -p "$RECORDINGS_DIR"
  "$ADB" -s "$serial" shell rm -f "$REMOTE_PATH" 2>/dev/null || true

  local record_args=(--bit-rate "$BIT_RATE" --time-limit "$TIME_LIMIT")
  if [ -n "$SIZE" ]; then
    record_args+=(--size "$SIZE")
  fi
  "$ADB" -s "$serial" shell screenrecord "${record_args[@]}" "$REMOTE_PATH"
  "$ADB" -s "$serial" pull "$REMOTE_PATH" "$out_file"
  "$ADB" -s "$serial" shell rm -f "$REMOTE_PATH" 2>/dev/null || true
  echo "✅ Saved: $out_file"
}

main "$@"
