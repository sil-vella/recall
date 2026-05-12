#!/usr/bin/env bash
# Build --dart-define arguments from .env file(s).
#
# **SSOT:** Repo-root `.env.local` (device/web dev) and `.env.prod` (release builds) hold every
# `KEY=value` that becomes `--dart-define=KEY=value`. Launch/build scripts must not append
# duplicate defines for the same keys — set API_URL, WS_URL, JWT_*, AdMob, DEBUG_MODE, etc.
# in the appropriate env file.
#
# Source this file and call build_dart_defines_from_env with path(s) to .env.
# Output: one --dart-define=KEY="VALUE" per line (safe to read into an array).
#
# For large .env files, prefer `python3 playbooks/frontend/env_for_flutter_dart_defines.py`
# plus `flutter … --dart-define-from-file=…` so the shell does not hit ARG_MAX.
# Usage:
#   source "$SCRIPT_DIR/dart_defines_from_env.sh"
#   while IFS= read -r line; do [[ -n "$line" ]] && DART_DEFINE_ARGS+=( "$line" ); done < <(build_dart_defines_from_env "$REPO_ROOT/.env.local")
#   flutter build web "${DART_DEFINE_ARGS[@]}"

build_dart_defines_from_env() {
  local env_file
  for env_file in "$@"; do
    [[ ! -f "$env_file" ]] && continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Trim and skip empty / comment
      line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      # Match KEY=VALUE (key: valid identifier; value: rest, may contain =)
      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # Strip optional surrounding single/double quotes from value
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        # Escape double quotes in value for safe shell use
        value_escaped="${value//\"/\\\"}"
        printf '%s\n' "--dart-define=${key}=\"${value_escaped}\""
      fi
    done < "$env_file"
  done
}
