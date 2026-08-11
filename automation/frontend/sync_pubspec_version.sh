#!/usr/bin/env bash
# dash Sync pubspec version fields for release builds
# Version helpers for release builds — sourced by build_appbundle.sh only.

_sync_pubspec_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
  cd "$script_dir/../.." && pwd
}

_sync_pubspec_path() {
  local root="${REPO_ROOT:-$(_sync_pubspec_root)}"
  echo "$root/app_codebase/flutter_base_06/pubspec.yaml"
}

_sync_env_prod_path() {
  local root="${REPO_ROOT:-$(_sync_pubspec_root)}"
  echo "$root/.env.prod"
}

_sync_dart_defines_prod_path() {
  local root="${REPO_ROOT:-$(_sync_pubspec_root)}"
  echo "$root/.env.dart.defines.prod"
}

_sync_sed_inplace() {
  local file="$1"
  local pattern="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

_sync_set_env_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    _sync_sed_inplace "$file" "s/^${key}=.*/${key}=${value}/"
  else
    echo "${key}=${value}" >>"$file"
  fi
}

read_pubspec_version_parts() {
  local pubspec="$(_sync_pubspec_path)"
  local line name build
  if [[ ! -f "$pubspec" ]]; then
    echo "sync_pubspec_version: missing $pubspec" >&2
    return 1
  fi
  line="$(grep -E '^version:' "$pubspec" | head -1 | sed 's/^version:[[:space:]]*//')"
  name="${line%%+*}"
  if [[ "$line" == *"+"* ]]; then
    build="${line#*+}"
  else
    build="1"
  fi
  PUBSPEC_VERSION_NAME="$name"
  PUBSPEC_BUILD_NUMBER="$build"
  export PUBSPEC_VERSION_NAME PUBSPEC_BUILD_NUMBER
}

resolve_release_version_and_build() {
  local app_version="$1"
  local current_build=0
  read_pubspec_version_parts || true
  if [[ "${PUBSPEC_BUILD_NUMBER:-}" =~ ^[0-9]+$ ]]; then
    current_build="$PUBSPEC_BUILD_NUMBER"
  fi
  BUILD_NUMBER=$((current_build + 1))
  export BUILD_NUMBER APP_VERSION="$app_version"
}

sync_pubspec_version() {
  local app_version="$1"
  local build_number="$2"
  local pubspec="$(_sync_pubspec_path)"
  if [[ ! -f "$pubspec" ]]; then
    echo "sync_pubspec_version: missing $pubspec" >&2
    return 1
  fi
  _sync_sed_inplace "$pubspec" "s/^version:.*/version: ${app_version}+${build_number}/"
  echo "Updated pubspec.yaml → version: ${app_version}+${build_number}"
}

write_app_version_to_env_files() {
  local app_version="$1"
  local env_prod="$(_sync_env_prod_path)"
  local dart_defines="$(_sync_dart_defines_prod_path)"
  _sync_set_env_key "$env_prod" "APP_VERSION" "$app_version"
  _sync_set_env_key "$dart_defines" "APP_VERSION" "$app_version"
  echo "Mirrored APP_VERSION=$app_version to $env_prod and $dart_defines"
}
