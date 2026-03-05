#!/bin/bash
# Start a local HTTP server to view flowcharts (Documentation/00_FlowCharts).
# Required so the Mermaid script loads and diagrams render; file:// often blocks it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLOWCHARTS_PORT="${FLOWCHARTS_PORT:-8765}"
HOST="${HOST:-127.0.0.1}"

INDEX_URL="http://${HOST}:${FLOWCHARTS_PORT}/Documentation/00_FlowCharts/index.html"

echo "Flowcharts server"
echo "  Root: $APP_ROOT"
echo "  Port: $FLOWCHARTS_PORT"
echo "  Open: $INDEX_URL"
echo ""
echo "Press Ctrl+C to stop."
echo ""

cd "$APP_ROOT"
python3 -m http.server "$FLOWCHARTS_PORT" --bind "$HOST" &
SERVER_PID=$!
sleep 1
OPENED=0
if command -v open >/dev/null 2>&1; then
  open "$INDEX_URL" 2>/dev/null && OPENED=1
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$INDEX_URL" 2>/dev/null && OPENED=1
fi
if [ "$OPENED" -ne 1 ]; then
  echo "  → Open in browser: $INDEX_URL"
fi
wait $SERVER_PID
