#!/usr/bin/env bash
# Shared Android device helpers (OnePlus default = VS Code launch.json local OnePlus).

android_default_oneplus_serial() {
  echo "84fbcf31"
}

get_device_label() {
  case "$1" in
    84fbcf31) echo "OnePlus device" ;;
    R3CWB0CS63D) echo "Samsung Galaxy S23 Ultra" ;;
    5dad288e7d91) echo "Xiaomi Redmi tablet" ;;
    NOTE58000000021664) echo "DOOGEE" ;;
    *) echo "Android device" ;;
  esac
}

resolve_device_id() {
  case "$1" in
    1|oneplus|OnePlus|ONEPLUS) echo "84fbcf31" ;;
    2|samsung|Samsung|SAMSUNG|s23|S23) echo "R3CWB0CS63D" ;;
    3|xiaomi|Xiaomi|XIAOMI|redmi|Redmi|REDMI) echo "5dad288e7d91" ;;
    4|doogee|Doogee|DOOGEE) echo "NOTE58000000021664" ;;
    *) echo "$1" ;;
  esac
}

find_adb() {
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  local sdk_adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
  if [ -x "$sdk_adb" ]; then
    echo "$sdk_adb"
    return 0
  fi
  echo "❌ adb not found." >&2
  return 1
}

android_ensure_adb_path() {
  local adb_pt="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools"
  export PATH="$adb_pt:$PATH"
}

android_assert_device_connected() {
  local serial="$1"
  local adb
  adb="$(find_adb)" || return 1
  if ! "$adb" devices | awk 'NR>1 && $2=="device" {print $1}' | grep -qx "$serial"; then
    echo "❌ Device $serial not connected. Run: $adb devices" >&2
    return 1
  fi
  return 0
}

prompt_for_device_selection() {
  echo "📲 Select target device:" >&2
  echo "   1) OnePlus (84fbcf31)" >&2
  echo "   2) Samsung Galaxy S23 Ultra (R3CWB0CS63D)" >&2
  echo "   3) Xiaomi Redmi tablet (5dad288e7d91)" >&2
  echo "   4) DOOGEE (NOTE58000000021664)" >&2
  local _tty=/dev/tty
  [ -r "$_tty" ] || _tty=/dev/stdin
  if ! read -r -t 10 -p "Enter choice [1/2/3/4] (default: 1): " device_choice < "$_tty"; then
    echo "" >&2
    device_choice="1"
  fi
  case "${device_choice:-1}" in
    1) echo "84fbcf31" ;;
    2) echo "R3CWB0CS63D" ;;
    3) echo "5dad288e7d91" ;;
    4) echo "NOTE58000000021664" ;;
    *)
      echo "⚠️  Invalid choice, using 1 (OnePlus)" >&2
      echo "84fbcf31"
      ;;
  esac
}
