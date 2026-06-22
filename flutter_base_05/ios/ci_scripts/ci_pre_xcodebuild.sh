#!/bin/bash
set -euo pipefail

echo "===> Xcode Cloud pre-xcodebuild start"
echo "CI_WORKSPACE: ${CI_WORKSPACE:-"(not set)"}"
echo "PWD: $(pwd)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLUTTER_APP_DIR="$(cd "${IOS_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FLUTTER_APP_DIR}/.." && pwd)"
PLAYBOOKS_FRONTEND="$REPO_ROOT/playbooks/frontend"

export REPO_ROOT FLUTTER_APP_DIR IOS_DIR

if [ ! -f "${FLUTTER_APP_DIR}/pubspec.yaml" ]; then
  echo "ERROR: pubspec.yaml not found at ${FLUTTER_APP_DIR}"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${HOME}/flutter/bin:${PATH}"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not found on PATH"
  exit 1
fi

# shellcheck source=/dev/null
source "$PLAYBOOKS_FRONTEND/xcode_cloud_materialize_env.sh"
xcode_cloud_materialize_env

# shellcheck source=/dev/null
source "$PLAYBOOKS_FRONTEND/flutter_release_build_common.sh"
flutter_release_init_paths

DART_DEF_JSON=""
trap 'restore_deck_config; rm -f "${DART_DEF_JSON:-}"' EXIT

if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
fi

APP_VERSION="$(read_pubspec_app_version)"
export APP_VERSION
echo "📦 pubspec APP_VERSION=$APP_VERSION"

# shellcheck source=/dev/null
source "$PLAYBOOKS_FRONTEND/sync_pubspec_version.sh"
resolve_release_version_and_build "$APP_VERSION"
write_app_version_to_env_files "$APP_VERSION"
echo "🔢 Using build-name=$APP_VERSION build-number=$BUILD_NUMBER"
sync_pubspec_version "$APP_VERSION" "$BUILD_NUMBER"

set_production_deck_config
disable_logging_switch_for_release

# shellcheck source=ios_admob_gad_app_id.sh
source "$PLAYBOOKS_FRONTEND/ios_admob_gad_app_id.sh"
ios_admob_gad_configure_from_env "$DART_DEFINES_ENV" "$FLUTTER_APP_DIR/ios"

export DART_DEFINES_PLATFORM=ios
flutter_release_prepare_dart_defines "$DART_DEFINES_ENV"
flutter_release_validate_api_url "$DART_DEF_JSON"
flutter_dart_defines_print_summary build

cd "$FLUTTER_APP_DIR"
flutter build ios --config-only --no-codesign \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define-from-file="$DART_DEF_JSON"

GENERATED_XCCONFIG="${FLUTTER_APP_DIR}/ios/Flutter/Generated.xcconfig"
flutter_release_assert_generated_dart_defines "$GENERATED_XCCONFIG"

echo "===> Pre-xcodebuild complete (dart-defines baked into Generated.xcconfig)"
