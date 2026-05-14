#!/usr/bin/env bash
# Run Flask debug: full stream to terminal; global.log only lines starting with [dev] (dev_logger).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG="$REPO_ROOT/global.log"

export DUTCH_DEV_LOG="${DUTCH_DEV_LOG:-1}"

cd "$REPO_ROOT/python_base_04"
echo "---- run_python_app_to_global_log start $(date '+%Y-%m-%d %H:%M:%S') cwd=$(pwd) ----" >&2

python3 app.debug.py 2>&1 | awk -v logf="$LOG" '
  { print }
  $0 ~ /^\[dev\]/ { print >> logf; fflush(logf) }
'
exit "${PIPESTATUS[0]}"
