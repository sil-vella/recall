#!/usr/bin/env bash
# dash Apply or restore release build config tweaks
# Repo-specific source tweaks before release builds (restored after build).
# Usage: pre_build_config_adjust.sh apply | restore

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"
STATE_FILE="${TMPDIR:-/tmp}/wf_pre_build_state_$(printf '%s' "$REPO_ROOT" | cksum | awk '{print $1}')"

_logging_switch_value="true"

_pre_build_state_read() {
  [[ -f "$STATE_FILE" ]] || return 1
  # shellcheck source=/dev/null
  source "$STATE_FILE"
  [[ -n "${PRE_BUILD_BACKUP_DIR:-}" ]]
}

_pre_build_state_write() {
  printf 'PRE_BUILD_BACKUP_DIR=%q\n' "$1" >"$STATE_FILE"
}

_pre_build_state_clear() {
  rm -f "$STATE_FILE"
}

_disable_logging_switch() {
  local flutter_dir="$1"
  local backup_dir="$2"
  local replaced_files=0
  local replaced_occurrences=0
  local dart_file occurrences rel_path n

  _grep_count() {
    local pattern="$1"
    local file="$2"
    n=$(grep -o "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' ') || n=0
    echo "${n:-0}"
  }

  echo "Disabling LOGGING_SWITCH in Flutter sources..."
  mkdir -p "$backup_dir"

  while IFS= read -r -d '' dart_file; do
    if ! grep -q "LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file" 2>/dev/null && \
       ! grep -q "const bool LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file" 2>/dev/null && \
       ! grep -q "static const bool LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file" 2>/dev/null; then
      continue
    fi

    occurrences=0
    occurrences=$((occurrences + $(_grep_count "LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file")))
    occurrences=$((occurrences + $(_grep_count "const bool LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file")))
    occurrences=$((occurrences + $(_grep_count "static const bool LOGGING_SWITCH = ${_logging_switch_value}" "$dart_file")))

    rel_path="${dart_file#$flutter_dir/}"
    mkdir -p "$backup_dir/$(dirname "$rel_path")"
    cp "$dart_file" "$backup_dir/$rel_path"

    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/LOGGING_SWITCH = ${_logging_switch_value}/LOGGING_SWITCH = false/g" "$dart_file"
      sed -i '' "s/const bool LOGGING_SWITCH = ${_logging_switch_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
      sed -i '' "s/static const bool LOGGING_SWITCH = ${_logging_switch_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
    else
      sed -i "s/LOGGING_SWITCH = ${_logging_switch_value}/LOGGING_SWITCH = false/g" "$dart_file"
      sed -i "s/const bool LOGGING_SWITCH = ${_logging_switch_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
      sed -i "s/static const bool LOGGING_SWITCH = ${_logging_switch_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
    fi

    replaced_files=$((replaced_files + 1))
    replaced_occurrences=$((replaced_occurrences + occurrences))
    echo "  Updated $rel_path ($occurrences occurrence(s))"
  done < <(find "$flutter_dir" -name "*.dart" -type f -print0)

  if [ "$replaced_files" -eq 0 ]; then
    echo "  No LOGGING_SWITCH = ${_logging_switch_value} found (already disabled or not present)."
  else
    echo "  Disabled LOGGING_SWITCH in $replaced_occurrences place(s) across $replaced_files file(s)"
  fi
}

_pre_build_apply() {
  if [[ ! -d "$FLUTTER_DIR" ]]; then
    echo "pre_build_config_adjust: Flutter project not found: $FLUTTER_DIR" >&2
    exit 1
  fi

  local backup_dir="${TMPDIR:-/tmp}/wf_pre_build_backup_$$"
  _disable_logging_switch "$FLUTTER_DIR" "$backup_dir"

  # --- repo-specific pre-build tweaks ---
  # Add other release-only source mutations here (with backup under $backup_dir).

  _pre_build_state_write "$backup_dir"
  echo "pre_build_config_adjust: apply complete (backup: $backup_dir)"
}

_pre_build_restore() {
  if ! _pre_build_state_read; then
    return 0
  fi

  if [[ ! -d "$PRE_BUILD_BACKUP_DIR" ]]; then
    _pre_build_state_clear
    return 0
  fi

  echo "Restoring pre-build source files..."
  while IFS= read -r -d '' backed; do
    local rel="${backed#$PRE_BUILD_BACKUP_DIR/}"
    local dest="$FLUTTER_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$backed" "$dest"
    echo "  Restored $rel"
  done < <(find "$PRE_BUILD_BACKUP_DIR" -type f -print0)

  rm -rf "$PRE_BUILD_BACKUP_DIR"
  _pre_build_state_clear
  echo "pre_build_config_adjust: restore complete"
}

case "${1:-}" in
  apply) _pre_build_apply ;;
  restore) _pre_build_restore ;;
  *)
    echo "Usage: $0 apply|restore" >&2
    exit 1
    ;;
esac
