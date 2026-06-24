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
  if _android_screenrecord_remote_exists "$serial" "/sdcard/dutch_screenrecord_tmp.mp4"; then
    echo "/sdcard/dutch_screenrecord_tmp.mp4"
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
  # Fallback: playable MP4 should contain a moov atom near the end.
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
  "$adb" -s "$serial" shell rm -f "$REMOTE_PATH" /sdcard/dutch_screenrecord_tmp.mp4 2>/dev/null || true
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
  out_file="$RECORDINGS_DIR/dutch_screen_${ts}.mp4"

  "$adb" -s "$serial" shell rm -f "$REMOTE_PATH" /sdcard/dutch_screenrecord_tmp.mp4 2>/dev/null || true

  # Host-managed adb shell (Ctrl+C on host finalizes MP4). Device-side `screenrecord &` often
  # leaves files without a moov atom on OnePlus when stopped via pkill.
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
    "$adb" -s "$serial" shell rm -f "$pull_path" /sdcard/dutch_screenrecord_tmp.mp4 2>/dev/null || true
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
