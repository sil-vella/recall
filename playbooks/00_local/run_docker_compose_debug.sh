#!/usr/bin/env bash
# Local dev: MongoDB, Redis, Prometheus, Grafana via docker-compose.debug.yml.
#
# Compose interpolates ${MONGODB_ROOT_PASSWORD}, ${MONGODB_PASSWORD}, and
# ${REDIS_PASSWORD} from --env-file (not from env_file: alone). This script
# always passes repo-root .env.local for both substitution and container env.
#
# Usage:
#   playbooks/00_local/run_docker_compose_debug.sh              # up -d (default)
#   playbooks/00_local/run_docker_compose_debug.sh down
#   playbooks/00_local/run_docker_compose_debug.sh ps
#   playbooks/00_local/run_docker_compose_debug.sh logs -f dutch_grafana
#   playbooks/00_local/run_docker_compose_debug.sh up -d dutch_prometheus dutch_grafana
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCAL_ENV="$REPO_ROOT/.env.local"
COMPOSE_FILE="$REPO_ROOT/docker-compose.debug.yml"

if [ ! -f "$LOCAL_ENV" ]; then
  echo "Error: $LOCAL_ENV not found (required for MongoDB/Redis passwords)." >&2
  exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: $COMPOSE_FILE not found." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found in PATH." >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  set -- up -d
fi

cd "$REPO_ROOT"
exec docker compose --env-file "$LOCAL_ENV" -f "$COMPOSE_FILE" "$@"
