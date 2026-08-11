#!/usr/bin/env bash
# dash Chrome wrapper that keeps extensions enabled
# Flutter passes CHROME_EXECUTABLE a path to Chrome plus flags including
# --disable-extensions. Re-exec Chrome without that flag so extensions work.
set -euo pipefail

if [[ "${OSTYPE:-}" == darwin* ]]; then
  CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
else
  CHROME_BIN="${CHROME_BIN:-}"
  if [[ -z "$CHROME_BIN" ]]; then
    CHROME_BIN="$(command -v google-chrome 2>/dev/null || true)"
  fi
  if [[ -z "$CHROME_BIN" ]]; then
    CHROME_BIN="$(command -v chromium 2>/dev/null || true)"
  fi
  if [[ -z "$CHROME_BIN" || ! -x "$CHROME_BIN" ]]; then
    echo "chrome_no_disable_extensions.sh: set CHROME_BIN to your Chrome/Chromium binary." >&2
    exit 1
  fi
fi

if [[ ! -x "$CHROME_BIN" ]]; then
  echo "chrome_no_disable_extensions.sh: not executable: $CHROME_BIN" >&2
  exit 1
fi

filtered=()
for arg in "$@"; do
  if [[ "$arg" == "--disable-extensions" ]]; then
    continue
  fi
  filtered+=("$arg")
done

exec "$CHROME_BIN" "${filtered[@]}"
