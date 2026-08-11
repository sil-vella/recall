#!/usr/bin/env bash
# dash Launch Chrome and mirror logs to global.log
# VS Code / Cursor launcher: load local env and run Chrome with global.log mirroring.
# Prefer `wfrun` interactively; this script loads the same env for IDE terminals.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_LOCAL="$REPO_ROOT/.env.local"
DART_DEFINES="$REPO_ROOT/.env.dart.defines.local"

if [[ ! -f "$ENV_LOCAL" ]]; then
  echo "❌ Missing $ENV_LOCAL — copy from .env.local.sample" >&2
  exit 1
fi
if [[ ! -f "$DART_DEFINES" ]]; then
  echo "❌ Missing $DART_DEFINES — copy from .env.dart.defines.local.sample" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_LOCAL"
# shellcheck source=/dev/null
source "$DART_DEFINES"
set +a

export WFRUN_ROOT="$REPO_ROOT"
export WFRUN_MODE="${WFRUN_MODE:-local}"
export WFRUN_PROFILE=frontend
export WFRUN_DART_DEFINES_FILE="$DART_DEFINES"

exec bash "$SCRIPT_DIR/launch_chrome.sh"
