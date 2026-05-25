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
export DART_DEFINES_ENV

DECK_CONFIG_PATH="$REPO_ROOT/flutter_base_05/assets/deck_config.yaml"
PREDEFINED_HANDS_PATH="$REPO_ROOT/flutter_base_05/assets/predefined_hands.yaml"
DECK_BACKUP_DIR="${TMPDIR:-/tmp}/dutch_build_deck_$$"
restore_deck_config() {
  if [ -d "$DECK_BACKUP_DIR" ]; then
    echo "" && echo "🃏 Restoring deck config files..."
    if [ -f "$DECK_BACKUP_DIR/deck_config.yaml" ]; then cp "$DECK_BACKUP_DIR/deck_config.yaml" "$DECK_CONFIG_PATH"; fi
    if [ -f "$DECK_BACKUP_DIR/predefined_hands.yaml" ]; then cp "$DECK_BACKUP_DIR/predefined_hands.yaml" "$PREDEFINED_HANDS_PATH"; fi
    rm -rf "$DECK_BACKUP_DIR"
    echo ""
  fi
}
set_production_deck_config() {
  echo ""
  echo "🃏 Setting production deck config..."
  mkdir -p "$DECK_BACKUP_DIR"
  if [ -f "$DECK_CONFIG_PATH" ]; then
    cp "$DECK_CONFIG_PATH" "$DECK_BACKUP_DIR/deck_config.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    else
      sed -i 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    fi
  fi
  if [ -f "$PREDEFINED_HANDS_PATH" ]; then
    cp "$PREDEFINED_HANDS_PATH" "$DECK_BACKUP_DIR/predefined_hands.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    else
      sed -i 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    fi
  fi
  echo ""
}
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

IFS='.' read -r APP_MAJOR APP_MINOR APP_PATCH <<< "${APP_VERSION:-1.0.0}"
APP_MAJOR=${APP_MAJOR:-0}
APP_MINOR=${APP_MINOR:-0}
APP_PATCH=${APP_PATCH:-0}
if ! [[ "$APP_MAJOR" =~ ^[0-9]+$ ]]; then APP_MAJOR=0; fi
if ! [[ "$APP_MINOR" =~ ^[0-9]+$ ]]; then APP_MINOR=0; fi
if ! [[ "$APP_PATCH" =~ ^[0-9]+$ ]]; then APP_PATCH=0; fi
BUILD_NUMBER=$((APP_MAJOR * 10000 + APP_MINOR * 100 + APP_PATCH))
echo "🔢 Using build-name=$APP_VERSION build-number=$BUILD_NUMBER"

cd "$REPO_ROOT/flutter_base_05"

# Disable LOGGING_SWITCH for release (same as build_apk.sh)
echo "🔇 Disabling LOGGING_SWITCH in Flutter sources..."
FLUTTER_DIR="$REPO_ROOT/flutter_base_05"
logging_switch_variable_value="true"
while IFS= read -r -d '' dart_file; do
  if grep -q "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
     grep -q "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
      sed -i '' "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
    else
      sed -i "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
      sed -i "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
    fi
  fi
done < <(find "$FLUTTER_DIR" -name "*.dart" -type f -print0)
echo ""

set_production_deck_config

if [ ! -f "$DART_DEFINES_ENV" ]; then
  echo "❌ Missing dart-define file: $DART_DEFINES_ENV"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found"
  exit 1
fi
DART_DEF_JSON="$(mktemp "${TMPDIR:-/tmp}/flutter-dart-defines.XXXXXX.json")" || exit 1
python3 "$SCRIPT_DIR/env_for_flutter_dart_defines.py" "$DART_DEFINES_ENV" "$DART_DEF_JSON" || exit 1

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
