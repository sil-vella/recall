#!/usr/bin/env bash
# dash Build dart-define args from wfrun env
# Emit one --dart-define=KEY=value per line from a dotenv-style file.
# Sourced by automation/frontend/*.sh; defines build_dart_defines_from_env.

_unquote_env_value() {
  local v="$1"
  local len=${#v}
  if (( len >= 2 )); then
    local first="${v:0:1}"
    local last="${v:len-1:1}"
    if [[ "$first" == '"' && "$last" == '"' ]]; then
      v="${v:1:len-2}"
      v="${v//\\\"/\"}"
      printf '%s' "$v"
      return
    fi
    if [[ "$first" == "'" && "$last" == "'" ]]; then
      printf '%s' "${v:1:len-2}"
      return
    fi
  fi
  printf '%s' "$v"
}

_parse_env_key_from_line() {
  local raw="$1"
  [[ "$raw" =~ ^[[:space:]]*# ]] && return 1
  [[ -z "${raw//[[:space:]]/}" ]] && return 1

  local line="$raw"
  line="${line#"${line%%[![:space:]]*}"}"
  if [[ "$line" == export\ * ]]; then
    line="${line#export }"
    line="${line#"${line%%[![:space:]]*}"}"
  fi

  if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
    return 1
  fi
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# Keys from dotenv file; values from the current shell (wfrun-exported env).
build_dart_defines_from_wfrun_env() {
  local keys_file="${1:-${WFRUN_DART_DEFINES_FILE:-}}"
  [[ -n "$keys_file" && -f "$keys_file" ]] || return 0

  local key val
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    key="$(_parse_env_key_from_line "$raw" || true)"
    [[ -n "$key" ]] || continue
    val="${!key-}"
    [[ -n "$val" ]] || continue
    printf '%s\n' "--dart-define=${key}=${val}"
  done < "$keys_file"
}

build_dart_defines_from_env() {
  local env_file="${1:-}"
  [[ -n "$env_file" && -f "$env_file" ]] || return 0

  local key val
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    key="$(_parse_env_key_from_line "$raw" || true)"
    [[ -n "$key" ]] || continue
    val="${!key-}"
    if [[ -z "$val" ]]; then
      if [[ ! "$raw" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        continue
      fi
      val="$(_unquote_env_value "${BASH_REMATCH[2]}")"
    fi
    [[ -n "$val" ]] || continue
    printf '%s\n' "--dart-define=${key}=${val}"
  done < "$env_file"
}
