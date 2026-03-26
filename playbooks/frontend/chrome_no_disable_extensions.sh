#!/usr/bin/env bash
# Flutter's Chrome launcher always adds --disable-extensions. This wrapper strips that
# flag so extensions (e.g. GA Debugger) work. Point CHROME_EXECUTABLE at this script.
#
# Override real binary if needed:
#   REAL_CHROME=/path/to/chrome CHROME_EXECUTABLE=.../chrome_no_disable_extensions.sh

set -euo pipefail

REAL_CHROME="${REAL_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--disable-extensions" ]]; then
    continue
  fi
  ARGS+=("$arg")
done

exec "$REAL_CHROME" "${ARGS[@]}"
