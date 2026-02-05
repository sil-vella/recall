#!/bin/bash

# Flutter APK build script
# Builds an Android APK for Dutch with the same dart-define envs
# used by the OnePlus launcher script, targeting either LOCAL or VPS backend.

set -e

echo "🚀 Building Flutter APK for Dutch..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
trap restore_deck_config EXIT

# Determine backend target from first argument: 'local' or 'vps' (default: vps for distribution)
BACKEND_TARGET="${1:-vps}"

if [ "$BACKEND_TARGET" = "local" ]; then
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="https://dutch.reignofplay.com"
    WS_URL="wss://dutch.reignofplay.com/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Determine app version from Python backend secrets (keeps APK and /public/check-updates in sync)
APP_VERSION_FILE="$REPO_ROOT/python_base_04/secrets/app_version"

# Prompt user if they want to bump the version
if [ -f "$APP_VERSION_FILE" ]; then
  CURRENT_VERSION="$(tr -d '\r\n' < "$APP_VERSION_FILE")"
else
  CURRENT_VERSION="2.0.0"
fi

if [ -z "$CURRENT_VERSION" ]; then
  CURRENT_VERSION="2.0.0"
fi

echo ""
echo "📦 Current version in secrets: $CURRENT_VERSION"
echo ""
read -p "🤔 Bump version number? (y/n) [n]: " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Parse current version
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  MAJOR=${MAJOR:-0}
  MINOR=${MINOR:-0}
  PATCH=${PATCH:-0}
  
  # Validate numbers
  if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
  if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
  if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi
  
  # Increment patch version
  PATCH=$((PATCH + 1))
  NEW_VERSION="$MAJOR.$MINOR.$PATCH"
  
  # Write new version to file
  echo "$NEW_VERSION" > "$APP_VERSION_FILE"
  echo "✅ Version bumped: $CURRENT_VERSION → $NEW_VERSION"
  echo "📝 Updated $APP_VERSION_FILE"
  APP_VERSION="$NEW_VERSION"
else
  APP_VERSION="$CURRENT_VERSION"
  echo "ℹ️  Using existing version: $APP_VERSION"
fi

echo "📦 Building with APP_VERSION=$APP_VERSION"

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

# Build the release APK
flutter build apk \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define=API_URL="$API_URL" \
  --dart-define=WS_URL="$WS_URL" \
  --dart-define=APP_VERSION="$APP_VERSION" \
  --dart-define=JWT_ACCESS_TOKEN_EXPIRES=3600 \
  --dart-define=JWT_REFRESH_TOKEN_EXPIRES=604800 \
  --dart-define=JWT_TOKEN_REFRESH_COOLDOWN=300 \
  --dart-define=JWT_TOKEN_REFRESH_INTERVAL=3600 \
  --dart-define=ADMOBS_TOP_BANNER01=ca-app-pub-3940256099942544/9214589741 \
  --dart-define=ADMOBS_BOTTOM_BANNER01=ca-app-pub-3940256099942544/9214589741 \
  --dart-define=ADMOBS_INTERSTITIAL01=ca-app-pub-3940256099942544/1033173712 \
  --dart-define=ADMOBS_REWARDED01=ca-app-pub-3940256099942544/5224354917 \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_51MXUtTADcEzB4rlRqLVPRhD0Ti3SRZGyTEQ1crO6YoeGyEfWYBgDxouHygPawog6kKTLVWhxP6DbK1MtBylX2Z6G00JTtIRdgZ \
  --dart-define=GOOGLE_CLIENT_ID=907176907209-q53b29haj3t690ol7kbtqrqo0hkt9ku7.apps.googleusercontent.com \
  --dart-define=GOOGLE_CLIENT_ID_ANDROID=907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com \
  --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
  --dart-define=DEBUG_MODE=true \
  --dart-define=ENABLE_REMOTE_LOGGING=true

OUTPUT_APK="$REPO_ROOT/flutter_base_05/build/app/outputs/flutter-apk/app-release.apk"

if [ -f "$OUTPUT_APK" ]; then
  echo "✅ APK build completed: $OUTPUT_APK"
  ls -lh "$OUTPUT_APK"
else
  echo "❌ APK build finished but $OUTPUT_APK was not found. Check Flutter build output above."
  exit 1
fi

# If building for VPS backend, upload APK to VPS downloads directory
if [ "$BACKEND_TARGET" = "vps" ]; then
  # Default to non-root app user; override with VPS_SSH_TARGET if needed
  VPS_SSH_TARGET="${VPS_SSH_TARGET:-rop01_user@65.181.125.135}"
  # SSH key to use for uploads (defaults to same key as inventory.ini / 01_setup_ssh_key.sh)
  VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/rop01_key}"
  REMOTE_DOWNLOAD_ROOT="/var/www/dutch.reignofplay.com/downloads"
  REMOTE_VERSION_DIR="$REMOTE_DOWNLOAD_ROOT/v$APP_VERSION"
  REMOTE_APK_PATH="$REMOTE_VERSION_DIR/app.apk"
  REMOTE_TMP_APK="/tmp/dutch-app-$APP_VERSION.apk"
  REMOTE_SECRETS_DIR="/opt/apps/reignofplay/dutch/secrets"
  REMOTE_MANIFEST_PATH="$REMOTE_SECRETS_DIR/mobile_release.json"
  REMOTE_TMP_MANIFEST="/tmp/mobile_release.json"

  log_remaining_vps_tasks() {
    echo ""
    echo "❌ VPS upload failed. REMAINING TASKS (run manually if needed):"
    echo "  [1] Create version dir and upload APK:"
    echo "      scp -i $VPS_SSH_KEY $OUTPUT_APK $VPS_SSH_TARGET:$REMOTE_TMP_APK"
    echo "      ssh -i $VPS_SSH_KEY $VPS_SSH_TARGET \"sudo mkdir -p $REMOTE_VERSION_DIR && sudo mv $REMOTE_TMP_APK $REMOTE_APK_PATH && sudo chown www-data:www-data $REMOTE_APK_PATH && sudo chmod 644 $REMOTE_APK_PATH\""
    echo "  [2] Update mobile_release.json on VPS:"
    echo "      (create JSON with latest_version and min_supported_version: $APP_VERSION)"
    echo "      scp to $VPS_SSH_TARGET:$REMOTE_TMP_MANIFEST"
    echo "      ssh -i $VPS_SSH_KEY $VPS_SSH_TARGET \"sudo mkdir -p $REMOTE_SECRETS_DIR && sudo mv $REMOTE_TMP_MANIFEST $REMOTE_MANIFEST_PATH && sudo chown root:root $REMOTE_MANIFEST_PATH && sudo chmod 644 $REMOTE_MANIFEST_PATH\""
    echo ""
  }

  echo "🌐 Uploading APK to VPS ($VPS_SSH_TARGET)..."
  echo "📂 Remote path: $REMOTE_APK_PATH"

  echo "  Step 1/3: Uploading APK to temporary location on VPS..."
  if ! scp -i "$VPS_SSH_KEY" "$OUTPUT_APK" "$VPS_SSH_TARGET":"$REMOTE_TMP_APK"; then
    echo "❌ Step 1/3 failed: scp APK to $REMOTE_TMP_APK"
    log_remaining_vps_tasks
    exit 1
  fi

  echo "  Step 2/3: Creating version dir and moving APK into place..."
  if ! ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" "sudo mkdir -p '$REMOTE_VERSION_DIR' && sudo mv '$REMOTE_TMP_APK' '$REMOTE_APK_PATH' && sudo chown www-data:www-data '$REMOTE_APK_PATH' && sudo chmod 644 '$REMOTE_APK_PATH'"; then
    echo "❌ Step 2/3 failed: mkdir/mv APK to $REMOTE_APK_PATH"
    log_remaining_vps_tasks
    exit 1
  fi

  echo "✅ APK uploaded to VPS: $REMOTE_APK_PATH"
  echo "🔗 Expected download URL: https://dutch.reignofplay.com/downloads/v$APP_VERSION/app.apk"

  # Update mobile_release.json manifest on the VPS so Flask can serve
  # correct version info without needing a restart.
  MIN_SUPPORTED_VERSION="${MIN_SUPPORTED_VERSION:-$APP_VERSION}"

  echo "  Step 3/3: Updating mobile_release.json manifest on VPS..."
  TMP_MANIFEST="$(mktemp)"
  cat > "$TMP_MANIFEST" <<EOF
{
  "latest_version": "$APP_VERSION",
  "min_supported_version": "$MIN_SUPPORTED_VERSION"
}
EOF

  if ! scp -i "$VPS_SSH_KEY" "$TMP_MANIFEST" "$VPS_SSH_TARGET":"$REMOTE_TMP_MANIFEST"; then
    rm -f "$TMP_MANIFEST"
    echo "❌ Step 3/3 failed: scp manifest to $REMOTE_TMP_MANIFEST"
    log_remaining_vps_tasks
    exit 1
  fi
  if ! ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" "sudo mkdir -p '$REMOTE_SECRETS_DIR' && sudo mv '$REMOTE_TMP_MANIFEST' '$REMOTE_MANIFEST_PATH' && sudo chown root:root '$REMOTE_MANIFEST_PATH' && sudo chmod 644 '$REMOTE_MANIFEST_PATH'"; then
    rm -f "$TMP_MANIFEST"
    echo "❌ Step 3/3 failed: mv manifest to $REMOTE_MANIFEST_PATH"
    log_remaining_vps_tasks
    exit 1
  fi
  rm -f "$TMP_MANIFEST"

  echo "✅ mobile_release.json updated on VPS: $REMOTE_MANIFEST_PATH"
fi

