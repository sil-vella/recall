#!/usr/bin/env bash
# dash Print wfrun env vars for smoke-check
# Smoke-check: wfrun should export base + dart-defines env for automation/frontend/* scripts.

set -euo pipefail

echo "WFRUN_MODE=${WFRUN_MODE:-}"
echo "WFRUN_PROFILE=${WFRUN_PROFILE:-}"
echo "WFRUN_ENV_FILE=${WFRUN_ENV_FILE:-}"
echo "WFRUN_DART_DEFINES_FILE=${WFRUN_DART_DEFINES_FILE:-}"
echo "JWT_SECRET=${JWT_SECRET:+<set>}"
echo "ARCORI_API_REST_URL=${ARCORI_API_REST_URL:-}"
echo "ARCORI_API_WS_URL=${ARCORI_API_WS_URL:-}"
echo "ARCORI_DART_WS_URL=${ARCORI_DART_WS_URL:-}"
echo "FLUTTER_WEB_PORT=${FLUTTER_WEB_PORT:-}"
echo "FLUTTER_WEB_HOSTNAME=${FLUTTER_WEB_HOSTNAME:-}"
