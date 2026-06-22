#!/bin/bash
# Flutter iOS IPA build for Dutch (App Store / TestFlight).
# Dart-define SSOT: repo-root `.env.dart.defines.prod`. Version bump: `.env.prod` (same as build_apk.sh).
# Upload: use Xcode Organizer (Distribute App) or Transporter — not automated here.
#
# Prerequisites: Xcode, CocoaPods, Apple Developer team signing (DEVELOPMENT_TEAM in ios project).
# Usage: ./playbooks/frontend/build_ipa.sh

set -e

echo "🍎 Building Flutter IPA for Dutch..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.prod"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.prod"
export DART_DEFINES_ENV FRONTEND_ENV REPO_ROOT

# shellcheck source=flutter_release_build_common.sh
source "$SCRIPT_DIR/flutter_release_build_common.sh"
flutter_release_init_paths

DART_DEF_JSON=""
trap 'restore_deck_config; rm -f "${DART_DEF_JSON:-}"' EXIT

if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — using pubspec version for build-name/number."
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/bump_app_version_prompt.sh"
bump_app_version_prompt

# shellcheck source=sync_pubspec_version.sh
source "$SCRIPT_DIR/sync_pubspec_version.sh"
resolve_release_version_and_build "${APP_VERSION:-1.0.0}"
write_app_version_to_env_files "$APP_VERSION"
echo "🔢 Using build-name=$APP_VERSION build-number=$BUILD_NUMBER"
sync_pubspec_version "$APP_VERSION" "$BUILD_NUMBER"

cd "$REPO_ROOT/flutter_base_05"

disable_logging_switch_for_release
set_production_deck_config

# shellcheck source=ios_admob_gad_app_id.sh
source "$SCRIPT_DIR/ios_admob_gad_app_id.sh"
ios_admob_gad_configure_from_env "$DART_DEFINES_ENV" "$REPO_ROOT/flutter_base_05/ios"

export DART_DEFINES_PLATFORM=ios
flutter_release_prepare_dart_defines "$DART_DEFINES_ENV"
flutter_release_validate_api_url "$DART_DEF_JSON"
flutter_dart_defines_print_summary build

echo "📝 Dart-define SSOT: $DART_DEFINES_ENV"
if ! grep -q '^APP_STORE_URL=' "$DART_DEFINES_ENV" 2>/dev/null; then
  echo "⚠️  APP_STORE_URL not set in $DART_DEFINES_ENV — iOS share links will be empty until you add:"
  echo "    APP_STORE_URL=https://apps.apple.com/app/idYOUR_NUMERIC_APP_ID"
fi

echo "📦 Running pod install..."
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
(cd ios && pod install)

flutter build ipa \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define-from-file="$DART_DEF_JSON"

IPA_PATH="$REPO_ROOT/flutter_base_05/build/ios/ipa/*.ipa"
echo ""
echo "✅ IPA build finished."
echo "   Output: $REPO_ROOT/flutter_base_05/build/ios/ipa/"
ls -lh "$REPO_ROOT/flutter_base_05/build/ios/ipa/" 2>/dev/null || true
echo ""
echo "📤 Next (manual): Xcode → Window → Organizer → Distribute App → App Store Connect"
echo "   Or install Apple Transporter and upload the .ipa from build/ios/ipa/"
echo "   See: Documentation/flutter_base_05/IOS_RELEASE_CHECKLIST.md"
