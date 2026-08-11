#!/usr/bin/env bash
# dash Mirror [dev] log lines to global.log
# Shared helpers for mirroring filtered dev log lines into repo-root global.log.

set -euo pipefail

_global_log_path() {
  local root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  printf '%s/global.log' "$root"
}

# Flutter: append when line contains I/flutter (or I flutter) and [dev]; dedupe consecutive matches.
filter_flutter_to_global_log() {
  local global_log prev line
  global_log="$(_global_log_path)"
  prev=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if [[ "$line" == *"I/flutter"* || "$line" == *"I flutter"* ]] && [[ "$line" == *"[dev]"* ]]; then
      if [[ "$line" != "$prev" ]]; then
        printf '%s\n' "$line" >>"$global_log"
        prev="$line"
      fi
    fi
  done
}

# Python / Dart (host or docker): append when line contains [dev].
filter_dev_lines_to_global_log() {
  local global_log line
  global_log="$(_global_log_path)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if [[ "$line" == *"[dev]"* ]]; then
      printf '%s\n' "$line" >>"$global_log"
    fi
  done
}
