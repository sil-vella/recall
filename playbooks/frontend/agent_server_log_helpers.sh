# Shared helpers for launch_chrome.sh / launch_oneplus.sh.
# Requires: SERVER_LOG_FILE set to absolute path of server.log

# Append one human line (shared with Python/Dart loggers). Optional second arg = tag (default LAUNCH).
append_server_log_line() {
  local msg="$1"
  local tag="${2:-LAUNCH}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$(dirname "$SERVER_LOG_FILE")"
  printf '%s [%s] %s\n' "$ts" "$tag" "$msg" >> "$SERVER_LOG_FILE"
  append_agent_json_server_log "$ts" "$tag" "INFO" "$msg"
}

echo_and_server_log() {
  echo "$1"
  append_server_log_line "$1" "${2:-LAUNCH}"
}

# Creates log dir. Truncation when over AGENT_LOG_MAX_MB is opt-in only (AGENT_LOG_TRUNCATE_ON_MAX_MB=1)
# so the shared log stays append-only by default.
ensure_server_log_dir_and_maybe_rotate() {
  local d
  d=$(dirname "$SERVER_LOG_FILE")
  mkdir -p "$d"
  case "${AGENT_LOG_TRUNCATE_ON_MAX_MB:-0}" in 1|true|yes|TRUE|YES) ;; *) return 0;; esac
  local max_mb="${AGENT_LOG_MAX_MB:-}"
  if [ -z "$max_mb" ] || [ ! -f "$SERVER_LOG_FILE" ]; then
    return 0
  fi
  local bytes max_bytes
  bytes=$(wc -c < "$SERVER_LOG_FILE" 2>/dev/null | tr -d ' \n' || echo 0)
  max_bytes=$(( max_mb * 1024 * 1024 ))
  if [ "${bytes:-0}" -gt "$max_bytes" ] 2>/dev/null; then
    : > "$SERVER_LOG_FILE"
    echo "📝 Truncated server.log (exceeded ${max_mb} MiB; AGENT_LOG_MAX_MB + AGENT_LOG_TRUNCATE_ON_MAX_MB=1)" >&2
  fi
}

# Appends one NDJSON line to SERVER_LOG_FILE when AGENT_LOG_JSON is enabled.
append_agent_json_server_log() {
  case "${AGENT_LOG_JSON:-}" in 1|true|yes|TRUE|YES) ;; *) return 0;; esac
  local ts="$1"
  local src="$2"
  local lvl="$3"
  local msg="$4"
  printf '%s' "$msg" | python3 -c "import json,sys; ts,src,lvl=sys.argv[1:4]; msg=sys.stdin.read(); print(json.dumps({'ts':ts,'source':src,'level':lvl,'msg':msg},ensure_ascii=False))" "$ts" "$src" "$lvl" >> "$SERVER_LOG_FILE"
}
