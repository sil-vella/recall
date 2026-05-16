#!/usr/bin/env bash
# Run Dart WS: full stream to terminal; global.log only lines starting with [dev] (dev_logger).
#
# Env SSOT for service-to-service auth: repo-root .env.local (same as run_python_app_to_global_log.sh).
# Without sourcing it, DART_BACKEND_SERVICE_KEY is empty → Python /service/auth/validate rejects → WS auth never completes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG="$REPO_ROOT/global.log"
LOCAL_ENV="$REPO_ROOT/.env.local"

export DUTCH_DEV_LOG="${DUTCH_DEV_LOG:-1}"

if [ -f "$LOCAL_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$LOCAL_ENV"
  set +a
else
  echo "⚠️  Warning: $LOCAL_ENV not found — Dart WS will not send X-Service-Key (Python validate will fail if auth enabled)." >&2
fi

cd "$REPO_ROOT/dart_bkend_base_01"
echo "---- run_dart_ws_to_global_log start $(date '+%Y-%m-%d %H:%M:%S') cwd=$(pwd) ----" >&2
if [ -n "${DART_BACKEND_SERVICE_KEY:-}" ]; then
  echo "   DART_BACKEND_SERVICE_KEY: set (${#DART_BACKEND_SERVICE_KEY} chars)" >&2
else
  echo "   DART_BACKEND_SERVICE_KEY: MISSING (check .env.local)" >&2
fi
if [ -n "${PYTHON_API_URL:-}" ]; then
  echo "   PYTHON_API_URL=$PYTHON_API_URL" >&2
else
  echo "   PYTHON_API_URL=(default http://127.0.0.1:5001 in app.debug.dart)" >&2
fi

dart run app.debug.dart 2>&1 | awk -v logf="$LOG" '
  { print }
  $0 ~ /^\[dev\]/ { print >> logf; fflush(logf) }
'
exit "${PIPESTATUS[0]}"
