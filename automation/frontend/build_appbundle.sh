#!/bin/bash
# dash Build Flutter release App Bundle (AAB)
# Flutter App Bundle (AAB) for dutch — env from wfrun (prod) only.
# Output: app_codebase/flutter_base_06/build/app/outputs/bundle/release/app-release.aab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${WFRUN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLUTTER_DIR="$REPO_ROOT/app_codebase/flutter_base_06"
OUTPUT_AAB="$FLUTTER_DIR/build/app/outputs/bundle/release/app-release.aab"

require_wfrun() {
  if [[ -z "${WFRUN_MODE:-}" || -z "${WFRUN_PROFILE:-}" ]]; then
    echo "Run via wfrun — this script expects exported env (WFRUN_MODE, WFRUN_PROFILE)." >&2
    exit 1
  fi
  if [[ "$WFRUN_PROFILE" != frontend ]]; then
    echo "WFRUN_PROFILE must be frontend (dart-defines env not loaded)." >&2
    exit 1
  fi
  if [[ "$WFRUN_MODE" != prod ]]; then
    echo "WFRUN_MODE must be prod for release AAB builds." >&2
    exit 1
  fi
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name must be set in ${WFRUN_DART_DEFINES_FILE:-.env.dart.defines.prod}" >&2
    exit 1
  fi
}

bump_app_version_patch() {
  local current="${APP_VERSION:-1.0.0}"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"
  major=${major:-0}
  minor=${minor:-0}
  patch=${patch:-0}
  if ! [[ "$major" =~ ^[0-9]+$ ]]; then major=0; fi
  if ! [[ "$minor" =~ ^[0-9]+$ ]]; then minor=0; fi
  if ! [[ "$patch" =~ ^[0-9]+$ ]]; then patch=0; fi
  patch=$((patch + 1))
  APP_VERSION="$major.$minor.$patch"
  export APP_VERSION
}

restore_pre_build() {
  bash "$SCRIPT_DIR/pre_build_config_adjust.sh" restore || true
}

require_wfrun

require_var ARCORI_API_REST_URL
require_var ARCORI_API_WS_URL
require_var ARCORI_DART_WS_URL

if [[ ! -d "$FLUTTER_DIR" ]]; then
  echo "Flutter project not found: $FLUTTER_DIR" >&2
  exit 1
fi

echo "Building Flutter App Bundle (AAB) for dutch..."
echo "wfrun ($WFRUN_MODE): API=$ARCORI_API_REST_URL"

bash "$SCRIPT_DIR/pre_build_config_adjust.sh" apply
trap restore_pre_build EXIT INT TERM HUP

CURRENT_VERSION="${APP_VERSION:-1.0.0}"
echo "Current APP_VERSION (from wfrun env): $CURRENT_VERSION"
bump_app_version_patch
echo "Version bumped: $CURRENT_VERSION → $APP_VERSION"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/sync_pubspec_version.sh"
resolve_release_version_and_build "$APP_VERSION"
write_app_version_to_env_files "$APP_VERSION"
sync_pubspec_version "$APP_VERSION" "$BUILD_NUMBER"
echo "Using APP_VERSION=$APP_VERSION BUILD_NUMBER=$BUILD_NUMBER"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/dart_defines_from_env.sh"
DART_DEFINE_ARGS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DART_DEFINE_ARGS+=("$line")
done < <(build_dart_defines_from_wfrun_env)

if [[ ${#DART_DEFINE_ARGS[@]} -eq 0 ]]; then
  echo "No dart-defines from ${WFRUN_DART_DEFINES_FILE:-.env.dart.defines.prod}" >&2
  exit 1
fi

echo "Dart-defines: ${#DART_DEFINE_ARGS[@]} key(s) from ${WFRUN_DART_DEFINES_FILE:-}"

cd "$FLUTTER_DIR"
flutter build appbundle \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  "${DART_DEFINE_ARGS[@]}"

if [[ -f "$OUTPUT_AAB" ]]; then
  echo "App Bundle build completed: $OUTPUT_AAB"
  ls -lh "$OUTPUT_AAB"
  echo "Upload to Play Console: Release → Create new release → Upload this AAB"
else
  echo "App Bundle build finished but $OUTPUT_AAB was not found." >&2
  exit 1
fi
