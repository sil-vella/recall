#!/bin/bash
# dash Run Flutter dutch on Android
# Flutter dutch (flutter_base_06) on Android — env from wfrun only.
#
# Usage:
#   wfrun → launch_android.sh
#   launch_android.sh [adb_serial|1|oneplus|2|note58|doogee]
#
# During flutter run: V starts/stops adb screen record, X saves a screenshot.
# Both files go to automation/frontend/launch_android_assets/.
# After X, saying yes saves 3 Play Console images: phone, 7-inch tablet, 10-inch tablet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"

REMOTE_PATH="${REMOTE_PATH:-/data/local/tmp/wf_screenrecord_tmp.mp4}"
SCREENRECORD_BIT_RATE="${SCREENRECORD_BIT_RATE:-8000000}"
SCREENSHOTS_DIR="$REPO_ROOT/automation/frontend/launch_android_assets"
RECORDINGS_DIR="$SCREENSHOTS_DIR"
# Play Console store screenshots, 24-bit PNG (no alpha).
# Phone: 9:16 or 16:9, each side 320–3840 (1080×1920 meets the featuring minimum).
# 7-inch and 10-inch tablets: 9:16 or 16:9, each side 1080–7680.
PHONE_SHOT_PORTRAIT_W=1080
PHONE_SHOT_PORTRAIT_H=1920
PHONE_SHOT_LANDSCAPE_W=1920
PHONE_SHOT_LANDSCAPE_H=1080
TABLET7_SHOT_PORTRAIT_W=1080
TABLET7_SHOT_PORTRAIT_H=1920
TABLET7_SHOT_LANDSCAPE_W=1920
TABLET7_SHOT_LANDSCAPE_H=1080
TABLET10_SHOT_PORTRAIT_W=1440
TABLET10_SHOT_PORTRAIT_H=2560
TABLET10_SHOT_LANDSCAPE_W=2560
TABLET10_SHOT_LANDSCAPE_H=1440

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
    NOTE58000000021664) echo "DOOGEE Note 58" ;;
    *) echo "Android device" ;;
  esac
}

resolve_device_id() {
  case "$1" in
    1|oneplus|OnePlus|ONEPLUS) echo "84fbcf31" ;;
    2|note58|Note58|NOTE58|doogee|Doogee|DOOGEE) echo "NOTE58000000021664" ;;
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

prompt_android_device() {
  echo "📲 Select target device:" >&2
  echo "   1) OnePlus (84fbcf31)" >&2
  echo "   2) DOOGEE Note 58 (NOTE58000000021664)" >&2
  local _tty=/dev/tty
  [[ -r "$_tty" ]] || _tty=/dev/stdin
  local choice=""
  if ! read -r -t 10 -p "Enter choice [1] (default: 1): " choice < "$_tty"; then
    echo "" >&2
    choice="1"
  fi
  case "${choice:-1}" in
    1|oneplus|OnePlus|ONEPLUS|"") echo "84fbcf31" ;;
    2|note58|Note58|NOTE58|doogee|Doogee|DOOGEE) echo "NOTE58000000021664" ;;
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

# --- screenshot (adb screencap) ---

_android_screenshot_is_png() {
  local file="$1"
  local magic
  [ -s "$file" ] || return 1
  magic="$(od -An -tx1 -N 4 "$file" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
  [ "$magic" = "89504e47" ]
}

android_screenshot() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local now ts out_file
  now="$(date +%s)"
  if [ "${_screenshot_last:-0}" -gt 0 ] && [ $((now - _screenshot_last)) -lt 1 ]; then
    return 0
  fi
  _screenshot_last=$now

  ts="$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$SCREENSHOTS_DIR"
  out_file="$SCREENSHOTS_DIR/wf_shot_${ts}.png"
  echo "📸 Capturing screenshot…" >&2
  # flutter run already holds an adb shell for logcat. Another `adb shell`
  # (screencap to a device file, then pull) drops that session's VM-service
  # forward. Flutter then prints "Lost connection to device" and exits 0,
  # and this script follows it out as soon as the Play images are written.
  # exec-out is a raw command with stdin closed, so the debug session stays up.
  if ! "$adb" -s "$serial" exec-out screencap -p >"$out_file" </dev/null 2>/dev/null; then
    echo "❌ Screenshot failed on $serial" >&2
    rm -f "$out_file"
    return 1
  fi
  if ! _android_screenshot_is_png "$out_file"; then
    echo "❌ Screenshot file is not a PNG" >&2
    rm -f "$out_file"
    return 1
  fi
  echo "✅ Saved: $out_file" >&2
  android_screenshot_offer_tablet_copy "$out_file" || true
  return 0
}

_android_screenshot_px() {
  local file="$1"
  local key="$2"
  sips -g "$key" "$file" 2>/dev/null | awk -v k="$key:" '$1 == k { print $2; exit }'
}

android_screenshot_fit_copy() {
  local src="$1"
  local tw="$2"
  local th="$3"
  local out="$4"
  local label="$5"
  local w h scaled_w scaled_h tmp jpg
  w="$(_android_screenshot_px "$src" pixelWidth)"
  h="$(_android_screenshot_px "$src" pixelHeight)"
  if ! [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && "$w" -gt 0 && "$h" -gt 0 ]]; then
    echo "❌ Could not read screenshot size for $label" >&2
    return 1
  fi
  if [ $((w * th)) -gt $((h * tw)) ]; then
    scaled_h=$th
    scaled_w=$((w * th / h))
    [ "$scaled_w" -lt "$tw" ] && scaled_w=$tw
  else
    scaled_w=$tw
    scaled_h=$((h * tw / w))
    [ "$scaled_h" -lt "$th" ] && scaled_h=$th
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/wf_shot_fit.XXXXXX.png")"
  jpg="$(mktemp "${TMPDIR:-/tmp}/wf_shot_fit.XXXXXX.jpg")"
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp" "$jpg"
    echo "❌ Could not copy screenshot for $label" >&2
    return 1
  fi
  if ! sips -z "$scaled_h" "$scaled_w" "$tmp" >/dev/null \
    || ! sips --cropToHeightWidth "$th" "$tw" "$tmp" >/dev/null \
    || ! sips -s format jpeg -s formatOptions 100 "$tmp" --out "$jpg" >/dev/null \
    || ! sips -s format png "$jpg" --out "$out" >/dev/null; then
    rm -f "$tmp" "$jpg" "$out"
    echo "❌ Failed to build $label screenshot" >&2
    return 1
  fi
  rm -f "$tmp" "$jpg"
  echo "✅ $label (${tw}×${th}): $out" >&2
}

android_screenshot_save_console_set() {
  local src="$1"
  local pw="$2"
  local ph="$3"
  local t7w="$4"
  local t7h="$5"
  local t10w="$6"
  local t10h="$7"
  local base phone t7 t10
  base="${src%.png}"
  phone="${base}_phone.png"
  t7="${base}_tablet7.png"
  t10="${base}_tablet10.png"
  if android_screenshot_fit_copy "$src" "$pw" "$ph" "$phone" "Phone" \
    && android_screenshot_fit_copy "$src" "$t7w" "$t7h" "$t7" "7-inch tablet" \
    && android_screenshot_fit_copy "$src" "$t10w" "$t10h" "$t10" "10-inch tablet"; then
    rm -f "$src"
    echo "✅ Play Console set saved: phone, 7-inch tablet, 10-inch tablet" >&2
    return 0
  fi
  rm -f "$phone" "$t7" "$t10"
  echo "⚠️  Kept the original snap because a store-listing copy failed: $src" >&2
  return 1
}

android_screenshot_offer_tablet_copy() {
  local src="$1"
  local w h pw ph t7w t7h t10w t10h answer
  if [[ ! -r /dev/tty ]]; then
    return 0
  fi
  if ! command -v sips >/dev/null 2>&1; then
    echo "⚠️  sips not available — skipped Play Console copies" >&2
    return 0
  fi
  w="$(_android_screenshot_px "$src" pixelWidth)"
  h="$(_android_screenshot_px "$src" pixelHeight)"
  if ! [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && "$w" -gt 0 && "$h" -gt 0 ]]; then
    echo "⚠️  Could not read screenshot size — skipped Play Console copies" >&2
    return 0
  fi
  if [ "$h" -ge "$w" ]; then
    pw=$PHONE_SHOT_PORTRAIT_W
    ph=$PHONE_SHOT_PORTRAIT_H
    t7w=$TABLET7_SHOT_PORTRAIT_W
    t7h=$TABLET7_SHOT_PORTRAIT_H
    t10w=$TABLET10_SHOT_PORTRAIT_W
    t10h=$TABLET10_SHOT_PORTRAIT_H
  else
    pw=$PHONE_SHOT_LANDSCAPE_W
    ph=$PHONE_SHOT_LANDSCAPE_H
    t7w=$TABLET7_SHOT_LANDSCAPE_W
    t7h=$TABLET7_SHOT_LANDSCAPE_H
    t10w=$TABLET10_SHOT_LANDSCAPE_W
    t10h=$TABLET10_SHOT_LANDSCAPE_H
  fi
  echo "Align this snap to Play Console sizes and save 3 images? [y/N]" >&2
  echo "  phone ${pw}×${ph}  |  7-inch tablet ${t7w}×${t7h}  |  10-inch tablet ${t10w}×${t10h}" >&2
  stty echo < /dev/tty 2>/dev/null || true
  if ! IFS= read -r -n 1 answer < /dev/tty; then
    stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null || true
    return 0
  fi
  printf '\n' >&2
  stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null || true
  case "$answer" in
    y|Y) android_screenshot_save_console_set "$src" "$pw" "$ph" "$t7w" "$t7h" "$t10w" "$t10h" || true ;;
  esac
  # Image work must not end flutter run. A non-zero sips status, or bash -e
  # treating that status as fatal, was dropping the session after the 3 files.
  return 0
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
  if [[ "${_CLEANUP_DONE:-0}" == 1 ]]; then
    return 0
  fi
  _CLEANUP_DONE=1
  android_disable_firebase_debug_view
  if android_screenrecord_is_active "$DEVICE_ID" 2>/dev/null; then
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

_key_fifo=""
_key_fifo_out=""
_key_tty_settings=""

restore_key_tty() {
  rm -f "$_key_fifo" "$_key_fifo_out"
  if [[ -n "${_key_tty_settings:-}" ]]; then
    stty "$_key_tty_settings" < /dev/tty 2>/dev/null || true
  else
    stty sane < /dev/tty 2>/dev/null || true
  fi
  _key_tty_settings=""
}

on_key_runner_signal() {
  local code="${1:-130}"
  restore_key_tty
  cleanup_on_exit
  exit "$code"
}

run_flutter_android_with_keys() {
  local pid filter_pid key flutter_exit
  _key_fifo="$(mktemp -u "${TMPDIR:-/tmp}/flutter_stdin.XXXXXX")"
  _key_fifo_out="$(mktemp -u "${TMPDIR:-/tmp}/flutter_stdout.XXXXXX")"
  mkfifo "$_key_fifo"
  mkfifo "$_key_fifo_out"

  trap 'restore_key_tty; cleanup_on_exit' EXIT
  trap 'on_key_runner_signal 130' INT
  trap 'on_key_runner_signal 143' TERM
  trap 'on_key_runner_signal 129' HUP

  flutter run \
    -d "$DEVICE_ID" \
    "${DART_DEFINE_ARGS[@]}" \
    < "$_key_fifo" >"$_key_fifo_out" 2>&1 &
  pid=$!

  filter_flutter_to_global_log <"$_key_fifo_out" &
  filter_pid=$!

  exec 3>"$_key_fifo"

  _key_tty_settings="$(stty -g < /dev/tty)"
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
      X|x)
        # Subshell so a failure inside screenshot/sips cannot tear down this
        # shell. Close only this copy of the flutter stdin fifo, and drop
        # traps so a subshell exit cannot restore the tty or remove the fifos.
        (
          trap - EXIT INT TERM HUP 2>/dev/null || true
          exec 3>&-
          set +e
          android_screenshot "$DEVICE_ID"
        ) || true
        stty -echo -icanon min 1 time 0 < /dev/tty 2>/dev/null || true
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
  if [[ -r /dev/tty ]]; then
    run_flutter_android_with_keys
  else
    echo "⚠️  No terminal — screenshot (X) and screen record (V) keys are unavailable." >&2
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
  DEVICE_ID="$(prompt_android_device)"
fi
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
android_assert_device_connected "$DEVICE_ID" || exit 1

ADB="$(find_adb)"
export ADB REPO_ROOT RECORDINGS_DIR
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
mkdir -p "$SCREENSHOTS_DIR"
echo "📱 recordings and screenshots → $SCREENSHOTS_DIR/"
warn_loopback_urls
echo "🎯 flutter run -d $DEVICE_ID (project: $FLUTTER_DIR)"
if [[ -r /dev/tty ]]; then
  echo "⌨️  Press X during flutter run to screenshot the device"
  echo "⌨️  Press V during flutter run to start/stop screen record"
fi

cd "$FLUTTER_DIR"
run_flutter_android
exit $?
