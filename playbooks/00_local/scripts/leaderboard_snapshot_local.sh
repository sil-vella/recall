#!/usr/bin/env bash
# Local-only: POST to Flask snapshot-wins-leaderboard (same as VPS monthly/yearly cron).
# Run anytime Flask is up on localhost (default http://127.0.0.1:5001).
#
# Usage:
#   ./leaderboard_snapshot_local.sh monthly
#   ./leaderboard_snapshot_local.sh yearly
#   ./leaderboard_snapshot_local.sh monthly 2026-02    # optional explicit period_key
#
# Env overrides:
#   FLASK_BASE_URL   (default http://127.0.0.1:5001)
#   DART_BACKEND_SERVICE_KEY  (else read from repo .env.local)
#   APP_DEV_ROOT     (default: repo root inferred from this script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DEV_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ROOT="${APP_DEV_ROOT}"

LB_TYPE="${1:-}"
PERIOD_KEY="${2:-}"

usage() {
  echo "Usage: $0 <monthly|yearly> [period_key]" >&2
  echo "Example: $0 monthly" >&2
  echo "Example: $0 monthly 2026-02" >&2
  exit 1
}

case "${LB_TYPE}" in
  monthly|yearly) ;;
  *) usage ;;
esac

ENV_FILE="${LEADERBOARD_ENV_FILE:-${ROOT}/.env.local}"
if [[ -z "${DART_BACKEND_SERVICE_KEY:-}" ]] && [[ -f "${ENV_FILE}" ]]; then
  DART_BACKEND_SERVICE_KEY="$(grep '^DART_BACKEND_SERVICE_KEY=' "${ENV_FILE}" | cut -d= -f2- | tr -d \"\'\')"
fi

if [[ -z "${DART_BACKEND_SERVICE_KEY:-}" ]]; then
  echo "error: set DART_BACKEND_SERVICE_KEY or add it to ${ENV_FILE}" >&2
  exit 1
fi

FLASK_BASE_URL="${FLASK_BASE_URL:-http://127.0.0.1:5001}"
BASE="${FLASK_BASE_URL%/}"

if [[ -n "${PERIOD_KEY}" ]]; then
  BODY="{\"leaderboard_type\":\"${LB_TYPE}\",\"period_key\":\"${PERIOD_KEY}\"}"
else
  BODY="{\"leaderboard_type\":\"${LB_TYPE}\"}"
fi

echo "POST ${BASE}/service/dutch/snapshot-wins-leaderboard (${LB_TYPE}${PERIOD_KEY:+, period_key=${PERIOD_KEY}})"
curl -sS -X POST "${BASE}/service/dutch/snapshot-wins-leaderboard" \
  -H "Content-Type: application/json" \
  -H "X-Service-Key: ${DART_BACKEND_SERVICE_KEY}" \
  -d "${BODY}"
echo
