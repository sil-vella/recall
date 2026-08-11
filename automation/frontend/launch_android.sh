#!/bin/bash
# dash Run Flutter dutch on Android
# Flutter dutch (flutter_base_06) on Android — env from wfrun only.
#
# Usage:
#   wfrun → launch_android.sh
#   launch_android.sh [adb_serial|1|oneplus]
#
# Screen-record mode (V key) is enabled by launch_android_with_screenrecord.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"
SCREENRECORD_MODE="${LAUNCH_ANDROID_SCREENRECORD:-0}"

REMOTE_PATH="${REMOTE_PATH:-/data/local/tmp/wf_screenrecord_tmp.mp4}"
SCREENRECORD_BIT_RATE="${SCREENRECORD_BIT_RATE:-8000000}"

# --- wfrun / env ---

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

warn_loopback_urls() {
  local api="$ARCORI_API_REST_URL"
  local api_ws="$ARCORI_API_WS_URL"
  local dart_ws="$ARCORI_DART_WS_URL"
  if [[ "$api" == *localhost* || "$api" == *127.0.0.1* ]]; then
    echo "   ⚠️  ARCORI_API_REST_URL is loopback — use LAN IP for physical devices" >&2
  fi
  if [[ "$api" == *10.0.2.2* ]]; then
    echo "   ⚠️  ARCORI_API_REST_URL uses 10.0.2.2 (emulator only)" >&2
  fi
  if [[ "$api_ws" == *localhost* || "$api_ws" == *127.0.0.1* ]]; then
    echo "   ⚠️  ARCORI_API_WS_URL is loopback — use LAN IP for physical devices" >&2
  fi
  if [[ "$dart_ws" == *localhost* || "$dart_ws" == *127.0.0.1* ]]; then
    echo "   ⚠️  ARCORI_DART_WS_URL is loopback — use LAN IP for physical devices" >&2
  fi
}

# --- device / adb ---

get_device_label() {
  case "$1" in
    84fbcf31) echo "OnePlus device" ;;
    *) echo "Android device" ;;
  esac
}

resolve_device_id() {
  case "$1" in
    1|oneplus|OnePlus|ONEPLUS) echo "84fbcf31" ;;
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

prompt_oneplus_device() {
  echo "📲 Select target device:" >&2
  echo "   1) OnePlus (84fbcf31)" >&2
  local _tty=/dev/tty
  [[ -r "$_tty" ]] || _tty=/dev/stdin
  local choice=""
  if ! read -r -t 10 -p "Enter choice [1] (default: 1): " choice < "$_tty"; then
    echo "" >&2
    choice="1"
  fi
  case "${choice:-1}" in
    1|oneplus|OnePlus|ONEPLUS|"") echo "84fbcf31" ;;
    *)
      echo "⚠️  Invalid choice, using 1 (OnePlus)" >&2
      echo "84fbcf31"
      ;;
  esac
}

# --- screenrecord (adb) ---

_android_rec_state_file() {
  local serial="$1"
  echo "${TMPDIR:-/tmp}/wf_screenrecord_${serial}.state"
}

android_screenrecord_is_active() {
  local serial="$1"
  if ! _android_screenrecord_read_state "$serial"; then
    return 1
  fi
  if [ -n "${HOST_PID:-}" ] && kill -0 "$HOST_PID" 2>/dev/null; then
    return 0
  fi
  _android_screenrecord_device_running "$serial"
}

_android_screenrecord_remote_exists() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local path="$2"
  "$adb" -s "$serial" shell "[ -f '$path' ]" >/dev/null 2>&1
}

_android_screenrecord_resolve_remote_path() {
  local serial="$1"
  if _android_screenrecord_remote_exists "$serial" "$REMOTE_PATH"; then
    echo "$REMOTE_PATH"
    return 0
  fi
  if _android_screenrecord_remote_exists "$serial" "/sdcard/wf_screenrecord_tmp.mp4"; then
    echo "/sdcard/wf_screenrecord_tmp.mp4"
    return 0
  fi
  return 1
}

_android_screenrecord_remote_size() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local path="$2"
  local raw
  raw="$("$adb" -s "$serial" shell "wc -c < '$path' 2>/dev/null" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "0"
  fi
}

_android_screenrecord_wait_remote_stable() {
  local serial="$1"
  local path="$2"
  local prev_size="-1"
  local stable=0
  local i=0
  while [ "$i" -lt 48 ]; do
    if ! _android_screenrecord_remote_exists "$serial" "$path"; then
      sleep 0.25
      i=$((i + 1))
      continue
    fi
    local size
    size="$(_android_screenrecord_remote_size "$serial" "$path")"
    if [ "$size" -gt 0 ] && [ "$size" = "$prev_size" ]; then
      stable=$((stable + 1))
      if [ "$stable" -ge 4 ]; then
        return 0
      fi
    else
      stable=0
      prev_size="$size"
    fi
    sleep 0.25
    i=$((i + 1))
  done
  return 1
}

_android_screenrecord_local_playable() {
  local file="$1"
  [ -f "$file" ] || return 1
  [ "$(wc -c <"$file" | tr -d ' ')" -gt 4096 ] || return 1
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" >/dev/null 2>&1
    return $?
  fi
  strings "$file" 2>/dev/null | grep -q moov
}

_android_screenrecord_read_state() {
  local serial="$1"
  local state_file
  state_file="$(_android_rec_state_file "$serial")"
  OUT_FILE=""
  HOST_PID=""
  if [ ! -f "$state_file" ]; then
    return 1
  fi
  IFS='|' read -r _serial OUT_FILE HOST_PID <"$state_file" || true
  [ -n "$OUT_FILE" ]
}

_android_screenrecord_write_state() {
  local serial="$1"
  local out_file="$2"
  local host_pid="$3"
  local state_file
  state_file="$(_android_rec_state_file "$serial")"
  printf '%s|%s|%s\n' "$serial" "$out_file" "$host_pid" >"$state_file"
}

_android_screenrecord_stop_host_shell() {
  local host_pid="$1"
  [ -n "$host_pid" ] || return 1
  if ! kill -0 "$host_pid" 2>/dev/null; then
    return 0
  fi
  kill -INT "$host_pid" 2>/dev/null || kill -2 "$host_pid" 2>/dev/null || true
  local w=0
  while kill -0 "$host_pid" 2>/dev/null && [ "$w" -lt 24 ]; do
    sleep 0.25
    w=$((w + 1))
  done
  if kill -0 "$host_pid" 2>/dev/null; then
    kill -TERM "$host_pid" 2>/dev/null || true
    sleep 0.5
    kill -KILL "$host_pid" 2>/dev/null || true
  fi
  return 0
}

_android_screenrecord_device_running() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local pid
  pid="$("$adb" -s "$serial" shell pidof screenrecord 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  [ -n "$pid" ] && [ "$pid" != "0" ]
}

_android_screenrecord_signal_device_stop() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  "$adb" -s "$serial" shell "pid=\$(pidof screenrecord 2>/dev/null | awk '{print \$1}'); if [ -n \"\$pid\" ]; then kill -INT \$pid; fi" 2>/dev/null || true
  "$adb" -s "$serial" shell pkill -INT screenrecord 2>/dev/null || true
  "$adb" -s "$serial" shell pkill -l 2 screenrecord 2>/dev/null || true
}

_android_screenrecord_clear_stale() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local host_pid=""
  if _android_screenrecord_read_state "$serial"; then
    host_pid="$HOST_PID"
  fi
  if [ -n "$host_pid" ]; then
    _android_screenrecord_stop_host_shell "$host_pid" || true
  fi
  rm -f "$(_android_rec_state_file "$serial")"
  if _android_screenrecord_device_running "$serial"; then
    echo "⚠️  Clearing stale screenrecord on device…" >&2
    _android_screenrecord_signal_device_stop "$serial"
    sleep 1
  fi
  "$adb" -s "$serial" shell rm -f "$REMOTE_PATH" /sdcard/wf_screenrecord_tmp.mp4 2>/dev/null || true
}

android_screenrecord_start() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"

  if android_screenrecord_is_active "$serial"; then
    echo "⚠️  Screen record already running on $serial (press V again to stop)." >&2
    return 0
  fi

  _android_screenrecord_clear_stale "$serial"

  local ts out_file
  ts="$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$RECORDINGS_DIR"
  out_file="$RECORDINGS_DIR/wf_screen_${ts}.mp4"

  "$adb" -s "$serial" shell rm -f "$REMOTE_PATH" /sdcard/wf_screenrecord_tmp.mp4 2>/dev/null || true

  if [ -n "${SCREENRECORD_SIZE:-}" ]; then
    "$adb" -s "$serial" shell screenrecord --time-limit 180 --bit-rate "$SCREENRECORD_BIT_RATE" \
      --size "$SCREENRECORD_SIZE" "$REMOTE_PATH" &
  else
    "$adb" -s "$serial" shell screenrecord --time-limit 180 --bit-rate "$SCREENRECORD_BIT_RATE" \
      "$REMOTE_PATH" &
  fi
  local host_pid=$!

  local ok=0
  local i=0
  while [ "$i" -lt 25 ]; do
    if _android_screenrecord_device_running "$serial"; then
      ok=1
      break
    fi
    sleep 0.2
    i=$((i + 1))
  done

  if [ "$ok" != 1 ]; then
    _android_screenrecord_stop_host_shell "$host_pid" || true
    echo "❌ screenrecord did not start on $serial (try: adb -s $serial shell pidof screenrecord)" >&2
    return 1
  fi

  _android_screenrecord_write_state "$serial" "$out_file" "$host_pid"
  echo "🎬 Recording started (max 180s, no audio). Press V again to stop → $out_file" >&2
}

android_screenrecord_stop() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"

  if ! _android_screenrecord_read_state "$serial"; then
    echo "⚠️  No active screen record on $serial (press V to start)." >&2
    return 0
  fi

  local out_file="$OUT_FILE"
  local host_pid="$HOST_PID"
  rm -f "$(_android_rec_state_file "$serial")"

  echo "⏹️  Stopping screen record..." >&2
  if [ -n "$host_pid" ]; then
    _android_screenrecord_stop_host_shell "$host_pid"
  fi
  _android_screenrecord_signal_device_stop "$serial"

  local waited=0
  while { [ -n "$host_pid" ] && kill -0 "$host_pid" 2>/dev/null; } \
    || _android_screenrecord_device_running "$serial"; do
    if [ "$waited" -ge 24 ]; then
      break
    fi
    sleep 0.25
    waited=$((waited + 1))
  done

  sleep 1

  local pull_path=""
  if ! pull_path="$(_android_screenrecord_resolve_remote_path "$serial")"; then
    echo "❌ No recording file on device after stop." >&2
    return 1
  fi
  _android_screenrecord_wait_remote_stable "$serial" "$pull_path" || true

  local tmp_pull="${out_file}.pulling"
  rm -f "$tmp_pull"
  if ! "$adb" -s "$serial" pull "$pull_path" "$tmp_pull"; then
    echo "❌ Failed to pull recording to $out_file" >&2
    rm -f "$tmp_pull"
    return 1
  fi
  mv -f "$tmp_pull" "$out_file"

  if ! _android_screenrecord_local_playable "$out_file"; then
    echo "❌ Recording file is not playable (missing MP4 metadata)." >&2
    echo "   Try again; if this persists, run: adb -s $serial shell screenrecord --time-limit 10 $REMOTE_PATH" >&2
    rm -f "$out_file"
    "$adb" -s "$serial" shell rm -f "$pull_path" /sdcard/wf_screenrecord_tmp.mp4 2>/dev/null || true
    return 1
  fi

  "$adb" -s "$serial" shell rm -f "$pull_path" /sdcard/wf_screenrecord_tmp.mp4 2>/dev/null || true
  echo "✅ Saved: $out_file" >&2
}

android_screenrecord_toggle() {
  local serial="$1"
  if android_screenrecord_is_active "$serial"; then
    android_screenrecord_stop "$serial"
  else
    android_screenrecord_start "$serial"
  fi
}

# --- flutter run ---

ANDROID_PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.reignofplay.dutch}"
FIREBASE_DEBUG_PROP_SET=0

is_firebase_switch_truthy() {
  local v
  v="$(echo "${FIREBASE_SWITCH:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$v" in true|1|yes) return 0 ;; *) return 1 ;; esac
}

dart_define_firebase_enabled() {
  local arg
  for arg in "${DART_DEFINE_ARGS[@]}"; do
    case "$arg" in
      --dart-define=FIREBASE_SWITCH=true|--dart-define=FIREBASE_SWITCH=1|--dart-define=FIREBASE_SWITCH=yes)
        return 0
        ;;
    esac
  done
  return 1
}

android_enable_firebase_debug_view() {
  if ! dart_define_firebase_enabled && ! is_firebase_switch_truthy; then
    echo "ℹ️  Firebase DebugView adb setprop skipped (FIREBASE_SWITCH not enabled in dart-defines)" >&2
    return 0
  fi
  if "$ADB" -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app "$ANDROID_PACKAGE_NAME" 2>/dev/null; then
    FIREBASE_DEBUG_PROP_SET=1
    echo "📊 Firebase DebugView enabled for $ANDROID_PACKAGE_NAME (adb setprop)" >&2
  else
    echo "⚠️  Could not set Firebase DebugView property on $DEVICE_ID" >&2
  fi
}

android_disable_firebase_debug_view() {
  if [[ "$FIREBASE_DEBUG_PROP_SET" != 1 ]]; then
    return 0
  fi
  "$ADB" -s "$DEVICE_ID" shell setprop debug.firebase.analytics.app .none. 2>/dev/null || true
}

cleanup_on_exit() {
  android_disable_firebase_debug_view
  if [[ "$SCREENRECORD_MODE" == 1 ]] && android_screenrecord_is_active "$DEVICE_ID" 2>/dev/null; then
    echo "⏹️  Stopping active screen record before exit…" >&2
    android_screenrecord_stop "$DEVICE_ID" || true
  fi
}

run_flutter_android_plain() {
  flutter run \
    -d "$DEVICE_ID" \
    "${DART_DEFINE_ARGS[@]}" \
    2>&1 | filter_flutter_to_global_log
  return "${PIPESTATUS[0]}"
}

run_flutter_android_with_screenrecord() {
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
    -d "$DEVICE_ID" \
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
      V|v)
        android_screenrecord_toggle "$DEVICE_ID"
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

run_flutter_android() {
  if [[ "$SCREENRECORD_MODE" == 1 ]]; then
    run_flutter_android_with_screenrecord
  else
    run_flutter_android_plain
  fi
}

# --- main ---

require_wfrun

require_var ARCORI_API_REST_URL
require_var ARCORI_API_WS_URL
require_var ARCORI_DART_WS_URL

android_ensure_adb_path

if [[ -n "${1:-}" ]]; then
  DEVICE_ID="$(resolve_device_id "$1")"
else
  DEVICE_ID="$(prompt_oneplus_device)"
fi
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
android_assert_device_connected "$DEVICE_ID" || exit 1

ADB="$(find_adb)"
export ADB REPO_ROOT RECORDINGS_DIR="$REPO_ROOT/assets/recordings"
trap cleanup_on_exit EXIT INT TERM HUP

if [[ ! -d "$FLUTTER_DIR" ]]; then
  echo "❌ Flutter project not found: $FLUTTER_DIR"
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/dart_defines_from_env.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/global_log_filter.sh"

DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=("$line")
done < <(build_dart_defines_from_wfrun_env)

android_enable_firebase_debug_view

echo "📱 wfrun ($WFRUN_MODE): API=$ARCORI_API_REST_URL  Dart WS=$ARCORI_DART_WS_URL  API WS=$ARCORI_API_WS_URL"
echo "📱 device=$DEVICE_LABEL ($DEVICE_ID)"
if [[ "$SCREENRECORD_MODE" == 1 ]]; then
  echo "📱 recordings → $RECORDINGS_DIR/"
fi
warn_loopback_urls
echo "🎯 flutter run -d $DEVICE_ID (project: $FLUTTER_DIR)"
if [[ "$SCREENRECORD_MODE" == 1 ]]; then
  echo "⌨️  Press V during flutter run to start/stop screen record"
fi

cd "$FLUTTER_DIR"
run_flutter_android
exit $?
