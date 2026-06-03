#!/usr/bin/env bash
# Sync flutter_base_05/pubspec.yaml `version:` with APP_VERSION and BUILD_NUMBER.
# BUILD_NUMBER uses the same formula as build_appbundle.sh / build_apk.sh:
#   major * 10000 + minor * 100 + patch
#
# Usage (after APP_VERSION / BUILD_NUMBER are set):
#   REPO_ROOT=... source "$SCRIPT_DIR/sync_pubspec_version.sh"
#   sync_pubspec_version
# Or: sync_pubspec_version "2.0.32" 20032

compute_build_number_from_version() {
  local ver="$1"
  local ma mi pa
  IFS='.' read -r ma mi pa <<< "$ver"
  ma=${ma:-0}
  mi=${mi:-0}
  pa=${pa:-0}
  if ! [[ "$ma" =~ ^[0-9]+$ ]]; then ma=0; fi
  if ! [[ "$mi" =~ ^[0-9]+$ ]]; then mi=0; fi
  if ! [[ "$pa" =~ ^[0-9]+$ ]]; then pa=0; fi
  echo $((ma * 10000 + mi * 100 + pa))
}

sync_pubspec_version() {
  local app_version="${1:-${APP_VERSION:-}}"
  local build_number="${2:-${BUILD_NUMBER:-}}"
  local root="${REPO_ROOT:-}"

  if [ -z "$app_version" ]; then
    echo "sync_pubspec_version: APP_VERSION not set" >&2
    return 1
  fi
  if [ -z "$root" ]; then
    echo "sync_pubspec_version: REPO_ROOT not set" >&2
    return 1
  fi

  local pubspec="$root/flutter_base_05/pubspec.yaml"
  if [ ! -f "$pubspec" ]; then
    echo "sync_pubspec_version: missing $pubspec" >&2
    return 1
  fi

  if [ -z "$build_number" ]; then
    build_number="$(compute_build_number_from_version "$app_version")"
  fi

  local new_line="version: ${app_version}+${build_number}"
  if grep -q '^version:' "$pubspec" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^version:.*/${new_line}/" "$pubspec"
    else
      sed -i "s/^version:.*/${new_line}/" "$pubspec"
    fi
  else
    echo "$new_line" >> "$pubspec"
  fi

  echo "📝 Synced pubspec.yaml → ${app_version}+${build_number}"
  export BUILD_NUMBER="$build_number"
}
