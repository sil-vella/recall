#!/bin/bash
# dash Run Flutter dutch on iOS Simulator
# Flutter dutch (flutter_base_06) on iOS Simulator — env from wfrun only.
#
# Usage:
#   wfrun → launch_ios.sh
#   launch_ios.sh [sim_udid|1]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"
IOS_DEFAULT_SIM_UDID="${IOS_DEFAULT_SIM_UDID:-8E4C2275-C301-428F-A6F9-E076FDA87A41}"

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

ios_default_sim_udid() {
  echo "$IOS_DEFAULT_SIM_UDID"
}

resolve_device_id() {
  case "$1" in
    1|sim|Sim|SIM|ios|iOS|simulator|Simulator) ios_default_sim_udid ;;
    *) echo "$1" ;;
  esac
}

get_device_label() {
  local udid="$1"
  local line
  line="$(xcrun simctl list devices available 2>/dev/null | grep "$udid" | head -1 || true)"
  if [[ "$line" =~ ^[[:space:]]*(.+)[[:space:]]+\([0-9A-Fa-f-]+\) ]]; then
    echo "${BASH_REMATCH[1]:-iOS Simulator}"
    return 0
  fi
  if [[ "$udid" == "$IOS_DEFAULT_SIM_UDID" ]]; then
    echo "Xcode iOS Simulator"
  else
    echo "iOS Simulator"
  fi
}

ios_assert_sim_available() {
  local udid="$1"
  if ! xcrun simctl list devices available 2>/dev/null | grep -q "$udid"; then
    echo "❌ Simulator $udid not found. Run: xcrun simctl list devices available" >&2
    return 1
  fi
  return 0
}

ios_sim_state() {
  local udid="$1"
  local line
  line="$(xcrun simctl list devices 2>/dev/null | grep "$udid" | head -1 || true)"
  if [[ "$line" == *"(Booted)"* ]]; then
    echo "Booted"
  elif [[ "$line" == *"(Shutdown)"* ]]; then
    echo "Shutdown"
  elif [[ -n "$line" ]]; then
    echo "Other"
  else
    echo "Unknown"
  fi
}

ios_wait_sim_booted() {
  local udid="$1"
  local max_wait="${2:-60}"
  local elapsed=0
  while (( elapsed < max_wait )); do
    if [[ "$(ios_sim_state "$udid")" == "Booted" ]]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

ios_ensure_sim_booted() {
  local udid="$1"
  local state
  state="$(ios_sim_state "$udid")"

  if [[ "$state" == "Booted" ]]; then
    echo "📱 Simulator already running (${udid})"
    return 0
  fi

  echo "📱 Simulator not running — launching ${udid}..."
  if ! xcrun simctl boot "$udid" 2>/dev/null; then
    # Already booting/booted from another process is OK if we reach Booted soon.
    if [[ "$(ios_sim_state "$udid")" != "Booted" ]]; then
      echo "⚠️  simctl boot returned non-zero (may already be starting)" >&2
    fi
  fi
  open -a Simulator 2>/dev/null || true

  echo "📱 Waiting for boot to be confirmed…"
  if ! ios_wait_sim_booted "$udid" 60; then
    echo "❌ Simulator did not reach Booted state within 60s" >&2
    exit 1
  fi
  echo "✅ Simulator boot confirmed"
  echo "📱 Waiting 30s for simulator to settle before flutter run…"
  sleep 30
}

ios_assert_flutter_sees_device() {
  local udid="$1"
  if flutter devices 2>/dev/null | grep -q "$udid"; then
    echo "✅ flutter devices lists $udid"
    return 0
  fi
  echo "⚠️  flutter devices does not list $udid yet (continuing anyway)" >&2
  return 0
}

prompt_ios_sim_device() {
  echo "📲 Select target device:" >&2
  echo "   1) Xcode iOS Simulator ($IOS_DEFAULT_SIM_UDID)" >&2
  local _tty=/dev/tty
  [[ -r "$_tty" ]] || _tty=/dev/stdin
  local choice=""
  if ! read -r -t 10 -p "Enter choice [1] (default: 1): " choice < "$_tty"; then
    echo "" >&2
    choice="1"
  fi
  case "${choice:-1}" in
    1|sim|Sim|SIM|ios|iOS|simulator|Simulator|"") ios_default_sim_udid ;;
    *)
      echo "⚠️  Invalid choice, using 1 (Xcode iOS Simulator)" >&2
      ios_default_sim_udid
      ;;
  esac
}

require_wfrun

require_var ARCORI_API_REST_URL
require_var ARCORI_API_WS_URL
require_var ARCORI_DART_WS_URL

if [[ -n "${1:-}" ]]; then
  DEVICE_ID="$(resolve_device_id "$1")"
else
  DEVICE_ID="$(prompt_ios_sim_device)"
fi
DEVICE_LABEL="$(get_device_label "$DEVICE_ID")"
ios_assert_sim_available "$DEVICE_ID" || exit 1
ios_ensure_sim_booted "$DEVICE_ID"
ios_assert_flutter_sees_device "$DEVICE_ID"

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

echo "📱 wfrun ($WFRUN_MODE): API=$ARCORI_API_REST_URL  Dart WS=$ARCORI_DART_WS_URL  API WS=$ARCORI_API_WS_URL"
echo "📱 device=$DEVICE_LABEL ($DEVICE_ID)"
echo "ℹ️  iOS Simulator uses Mac loopback — 127.0.0.1 / localhost in dart-defines is OK"
echo "🎯 flutter run -d $DEVICE_ID (project: $FLUTTER_DIR)"

cd "$FLUTTER_DIR"
flutter run \
  -d "$DEVICE_ID" \
  "${DART_DEFINE_ARGS[@]}" \
  2>&1 | filter_flutter_to_global_log

exit "${PIPESTATUS[0]}"
