#!/usr/bin/env bash
# Read flutter_base_05/pubspec.yaml version into PUBSPEC_VERSION_NAME and PUBSPEC_BUILD_NUMBER.
# Usage: REPO_ROOT=... source read_pubspec_version.sh

read_pubspec_version() {
  local root="${REPO_ROOT:-}"
  if [ -z "$root" ]; then
    echo "read_pubspec_version: REPO_ROOT not set" >&2
    return 1
  fi
  local pubspec="$root/flutter_base_05/pubspec.yaml"
  if [ ! -f "$pubspec" ]; then
    echo "read_pubspec_version: missing $pubspec" >&2
    return 1
  fi
  local line
  line="$(grep -E '^version:' "$pubspec" | head -1 | sed 's/^version:[[:space:]]*//')"
  PUBSPEC_VERSION_NAME="${line%%+*}"
  if [[ "$line" == *"+"* ]]; then
    PUBSPEC_BUILD_NUMBER="${line#*+}"
  else
    PUBSPEC_BUILD_NUMBER="1"
  fi
  export PUBSPEC_VERSION_NAME PUBSPEC_BUILD_NUMBER
}
