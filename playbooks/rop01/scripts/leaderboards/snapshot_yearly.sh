#!/usr/bin/env bash
# Calls Flask service to record yearly wins snapshot (cron: Jan 1 00:05 UTC).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${DIR}/env.sh"
curl -sS -X POST "${FLASK_BASE_URL%/}/service/dutch/snapshot-wins-leaderboard" \
  -H "Content-Type: application/json" \
  -H "X-Service-Key: ${DART_BACKEND_SERVICE_KEY}" \
  -d '{"leaderboard_type":"yearly"}'
echo
