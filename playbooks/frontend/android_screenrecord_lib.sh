#!/usr/bin/env bash
# adb screenrecord start/stop/toggle (sourced by adb_screenrecord.sh and toggle helper).

: "${RECORDINGS_DIR:=$REPO_ROOT/recordings}"
# /data/local/tmp is reliable for adb pull on physical devices (OnePlus, etc.)
: "${REMOTE_PATH:=/data/local/tmp/dutch_screenrecord_tmp.mp4}"
: "${SCREENRECORD_BIT_RATE:=8000000}"

_android_rec_state_file() {
  local serial="$1"
  echo "${TMPDIR:-/tmp}/dutch_screenrecord_${serial}.state"
}

android_screenrecord_is_active() {
  local serial="$1"
  local state_file
  state_file="$(_android_rec_state_file "$serial")"
  [ -f "$state_file" ] && [ -n "$(cat "$state_file" 2>/dev/null)" ]
}

_android_screenrecord_remote_exists() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local path="$2"
  "$adb" -s "$serial" shell "[ -f '$path' ]" >/dev/null 2>&1
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
  if android_screenrecord_is_active "$serial"; then
    return 0
  fi
  if _android_screenrecord_device_running "$serial"; then
    echo "⚠️  Clearing stale screenrecord on device…" >&2
    _android_screenrecord_signal_device_stop "$serial"
    sleep 1
  fi
  "$adb" -s "$serial" shell rm -f "$REMOTE_PATH" /sdcard/dutch_screenrecord_tmp.mp4 2>/dev/null || true
}

android_screenrecord_start() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local state_file
  state_file="$(_android_rec_state_file "$serial")"

  if android_screenrecord_is_active "$serial"; then
    echo "⚠️  Screen record already running on $serial (press V again to stop)." >&2
    return 0
  fi

  _android_screenrecord_clear_stale "$serial"

  local ts out_file
  ts="$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$RECORDINGS_DIR"
  out_file="$RECORDINGS_DIR/dutch_screen_${ts}.mp4"

  local size_opt=""
  if [ -n "${SCREENRECORD_SIZE:-}" ]; then
    size_opt="--size ${SCREENRECORD_SIZE}"
  fi

  # Run on device in background — do not rely on a long-lived host `adb shell` (breaks on early kill).
  if ! "$adb" -s "$serial" shell "rm -f '$REMOTE_PATH'; screenrecord --time-limit 180 --bit-rate $SCREENRECORD_BIT_RATE $size_opt '$REMOTE_PATH' </dev/null >/dev/null 2>&1 &"; then
    echo "❌ adb failed to start screenrecord on $serial" >&2
    return 1
  fi

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
    echo "❌ screenrecord did not start on $serial (try: adb -s $serial shell pidof screenrecord)" >&2
    return 1
  fi

  printf '%s|%s\n' "$serial" "$out_file" >"$state_file"
  echo "🎬 Recording started (max 180s, no audio). Press V again to stop → $out_file" >&2
}

android_screenrecord_stop() {
  local serial="$1"
  local adb="${ADB:-$(find_adb)}"
  local state_file
  state_file="$(_android_rec_state_file "$serial")"

  if ! android_screenrecord_is_active "$serial"; then
    echo "⚠️  No active screen record on $serial (press V to start)." >&2
    return 0
  fi

  IFS='|' read -r _serial out_file <"$state_file"
  rm -f "$state_file"

  echo "⏹️  Stopping screen record..." >&2
  _android_screenrecord_signal_device_stop "$serial"

  local waited=0
  while _android_screenrecord_device_running "$serial" && [ "$waited" -lt 30 ]; do
    sleep 0.5
    waited=$((waited + 1))
  done

  local pull_path=""
  local i=0
  while [ "$i" -lt 40 ]; do
    if _android_screenrecord_remote_exists "$serial" "$REMOTE_PATH"; then
      pull_path="$REMOTE_PATH"
      break
    fi
    if _android_screenrecord_remote_exists "$serial" "/sdcard/dutch_screenrecord_tmp.mp4"; then
      pull_path="/sdcard/dutch_screenrecord_tmp.mp4"
      break
    fi
    sleep 0.25
    i=$((i + 1))
  done

  if [ -z "$pull_path" ]; then
    echo "❌ No recording file on device after stop." >&2
    echo "   Tip: press V to start, wait a few seconds, then V to stop." >&2
    return 1
  fi

  if ! "$adb" -s "$serial" pull "$pull_path" "$out_file"; then
    echo "❌ Failed to pull recording to $out_file" >&2
    return 1
  fi
  "$adb" -s "$serial" shell rm -f "$pull_path" /sdcard/dutch_screenrecord_tmp.mp4 2>/dev/null || true
  echo "✅ Saved: $out_file" >&2
  if command -v open >/dev/null 2>&1; then
    echo "   open \"$out_file\"" >&2
  fi
}

android_screenrecord_toggle() {
  local serial="$1"
  if android_screenrecord_is_active "$serial"; then
    android_screenrecord_stop "$serial"
  else
    android_screenrecord_start "$serial"
  fi
}
