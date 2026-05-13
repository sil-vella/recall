#!/bin/bash

# Flutter App Bundle (AAB) build script
# Builds an Android App Bundle for Dutch. Dart-define input: repo-root `.env.dart.defines.prod`.
# Shell still sources `.env.prod` for APP_VERSION / auto-bump. Output is for Play Store upload; no VPS upload.

set -e

echo "🚀 Building Flutter App Bundle (AAB) for Dutch..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.prod"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.prod"
export DART_DEFINES_ENV

# Flutter assets: set testing_mode=false and predefined_hands enabled=false for production build (restored on exit)
# Backups go to /tmp so they are not bundled into build output
DECK_CONFIG_PATH="$REPO_ROOT/flutter_base_05/assets/deck_config.yaml"
PREDEFINED_HANDS_PATH="$REPO_ROOT/flutter_base_05/assets/predefined_hands.yaml"
DECK_BACKUP_DIR="${TMPDIR:-/tmp}/dutch_build_deck_$$"
restore_deck_config() {
  if [ -d "$DECK_BACKUP_DIR" ]; then
    echo "" && echo "🃏 Restoring deck config files..."
    if [ -f "$DECK_BACKUP_DIR/deck_config.yaml" ]; then cp "$DECK_BACKUP_DIR/deck_config.yaml" "$DECK_CONFIG_PATH" && echo "  ✓ Restored deck_config.yaml"; fi
    if [ -f "$DECK_BACKUP_DIR/predefined_hands.yaml" ]; then cp "$DECK_BACKUP_DIR/predefined_hands.yaml" "$PREDEFINED_HANDS_PATH" && echo "  ✓ Restored predefined_hands.yaml"; fi
    rm -rf "$DECK_BACKUP_DIR"
    echo "✅ Deck config restored" && echo ""
  fi
}
set_production_deck_config() {
  echo ""
  echo "🃏 Setting production deck config (testing_mode=false, predefined_hands enabled=false)..."
  mkdir -p "$DECK_BACKUP_DIR"
  if [ -f "$DECK_CONFIG_PATH" ]; then
    cp "$DECK_CONFIG_PATH" "$DECK_BACKUP_DIR/deck_config.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    else
      sed -i 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    fi
    echo "  ✓ deck_config.yaml: testing_mode → false"
  fi
  if [ -f "$PREDEFINED_HANDS_PATH" ]; then
    cp "$PREDEFINED_HANDS_PATH" "$DECK_BACKUP_DIR/predefined_hands.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    else
      sed -i 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    fi
    echo "  ✓ predefined_hands.yaml: enabled → false"
  fi
  echo "✅ Production deck config set"
  echo ""
}
DART_DEF_JSON=""
trap 'restore_deck_config; rm -f "${DART_DEF_JSON:-}"' EXIT

# Load env from repo root .env.prod (APP_VERSION, Firebase, GOOGLE_CLIENT_ID, Stripe, AdMob, AdSense, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — APP_VERSION auto-bump may use defaults only (dart-defines use $DART_DEFINES_ENV)."
fi
CURRENT_VERSION="${APP_VERSION:-2.0.0}"

echo ""
echo "📦 Current version (APP_VERSION from .env.prod): $CURRENT_VERSION"

# Auto-bump patch version for each bundle build
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}
if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi
PATCH=$((PATCH + 1))
APP_VERSION="$MAJOR.$MINOR.$PATCH"

# Write bumped version to .env.prod (APP_VERSION=) and mirror to .env.dart.defines.prod when present
ENV_FILE="$FRONTEND_ENV"
if [ -f "$ENV_FILE" ] && grep -q '^APP_VERSION=' "$ENV_FILE" 2>/dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$APP_VERSION/" "$ENV_FILE"
  else
    sed -i "s/^APP_VERSION=.*/APP_VERSION=$APP_VERSION/" "$ENV_FILE"
  fi
else
  echo "APP_VERSION=$APP_VERSION" >> "$ENV_FILE"
fi
if [ -f "$DART_DEFINES_ENV" ]; then
  if grep -q '^APP_VERSION=' "$DART_DEFINES_ENV" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$APP_VERSION/" "$DART_DEFINES_ENV"
    else
      sed -i "s/^APP_VERSION=.*/APP_VERSION=$APP_VERSION/" "$DART_DEFINES_ENV"
    fi
  else
    echo "APP_VERSION=$APP_VERSION" >> "$DART_DEFINES_ENV"
  fi
  echo "📝 Mirrored APP_VERSION to $DART_DEFINES_ENV"
fi
echo "✅ Version bumped: $CURRENT_VERSION → $APP_VERSION"
echo "📝 Updated APP_VERSION in $ENV_FILE"
echo ""
echo "📦 Building with APP_VERSION=$APP_VERSION"
echo "ℹ️  AdMob: set ADMOBS_* and ADMOB_APPLICATION_ID in .env.dart.defines.prod (dart-define; see Documentation/flutter_base_05/ADMOB_NATIVE_SETUP.md). Optional fallback: android/local.properties admob.application_id"

# Derive a numeric build number from APP_VERSION (e.g. 2.1.0 -> 20100)
IFS='.' read -r APP_MAJOR APP_MINOR APP_PATCH <<< "$APP_VERSION"
APP_MAJOR=${APP_MAJOR:-0}
APP_MINOR=${APP_MINOR:-0}
APP_PATCH=${APP_PATCH:-0}
if ! [[ "$APP_MAJOR" =~ ^[0-9]+$ ]]; then APP_MAJOR=0; fi
if ! [[ "$APP_MINOR" =~ ^[0-9]+$ ]]; then APP_MINOR=0; fi
if ! [[ "$APP_PATCH" =~ ^[0-9]+$ ]]; then APP_PATCH=0; fi
BUILD_NUMBER=$((APP_MAJOR * 10000 + APP_MINOR * 100 + APP_PATCH))
echo "🔢 Using BUILD_NUMBER=$BUILD_NUMBER"

# Navigate to Flutter project directory
cd "$REPO_ROOT/flutter_base_05"

# Disable LOGGING_SWITCH in all Dart files before build
echo ""
echo "🔇 Disabling LOGGING_SWITCH in Flutter sources..."
FLUTTER_DIR="$REPO_ROOT/flutter_base_05"
REPLACED_FILES=0
REPLACED_OCCURRENCES=0

# Predefined variable value to avoid accidentally replacing other 'true' values
logging_switch_variable_value="true"

while IFS= read -r -d '' dart_file; do
    # Check if file contains LOGGING_SWITCH = false pattern
    if grep -q "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "static const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null; then
        # Count occurrences before replacement
        OCCURRENCES=$(grep -o "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')
        OCCURRENCES=$((OCCURRENCES + $(grep -o "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')))
        OCCURRENCES=$((OCCURRENCES + $(grep -o "static const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" | wc -l | tr -d ' ')))

        # Use sed for in-place replacement (works on both macOS and Linux)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
            sed -i '' "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
            sed -i '' "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
        else
            sed -i "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
            sed -i "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
            sed -i "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
        fi

        REPLACED_OCCURRENCES=$((REPLACED_OCCURRENCES + OCCURRENCES))
        REPLACED_FILES=$((REPLACED_FILES + 1))
        REL_PATH="${dart_file#$FLUTTER_DIR/}"
        echo "  ✓ Updated $REL_PATH ($OCCURRENCES occurrence(s))"
    fi
done < <(find "$FLUTTER_DIR" -name "*.dart" -type f -print0)

if [ "$REPLACED_FILES" -eq 0 ]; then
    echo "  ℹ️  No LOGGING_SWITCH = ${logging_switch_variable_value} found in Flutter sources (already disabled or not present)."
else
    echo "  ✅ Disabled LOGGING_SWITCH in $REPLACED_OCCURRENCES place(s) across $REPLACED_FILES file(s)"
fi
echo ""

set_production_deck_config

# Build --dart-define-from-file from .env.dart.defines.prod
echo "📝 Dart-define file: $DART_DEFINES_ENV → --dart-define-from-file"
if [ ! -f "$DART_DEFINES_ENV" ]; then
  echo "❌ Missing dart-define file: $DART_DEFINES_ENV"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found — required for env_for_flutter_dart_defines.py"
  exit 1
fi
DART_DEF_JSON="$(mktemp "${TMPDIR:-/tmp}/flutter-dart-defines.XXXXXX.json")" || exit 1
python3 "$SCRIPT_DIR/env_for_flutter_dart_defines.py" "$DART_DEFINES_ENV" "$DART_DEF_JSON" || exit 1

# Build the release App Bundle (AAB) for Play Store
flutter build appbundle \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define-from-file="$DART_DEF_JSON"

OUTPUT_AAB="$REPO_ROOT/flutter_base_05/build/app/outputs/bundle/release/app-release.aab"

if [ -f "$OUTPUT_AAB" ]; then
  echo "✅ App Bundle build completed: $OUTPUT_AAB"
  ls -lh "$OUTPUT_AAB"
  echo ""
  echo "📤 Upload to Play Console: Release → Create new release → Upload this AAB"
else
  echo "❌ App Bundle build finished but $OUTPUT_AAB was not found. Check Flutter build output above."
  exit 1
fi
