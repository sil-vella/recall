#!/bin/bash

# Flutter APK build script
# Builds an Android APK for Cleco with the same dart-define envs
# used by the OnePlus launcher script, targeting either LOCAL or VPS backend.

set -e

echo "🚀 Building Flutter APK for Cleco..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Determine backend target from first argument: 'local' or 'vps' (default: vps for distribution)
BACKEND_TARGET="${1:-vps}"

if [ "$BACKEND_TARGET" = "local" ]; then
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="https://cleco.reignofplay.com"
    WS_URL="wss://cleco.reignofplay.com/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# Determine app version from Python backend secrets (keeps APK and /public/check-updates in sync)
APP_VERSION_FILE="$REPO_ROOT/python_base_04/secrets/app_version"
if [ -f "$APP_VERSION_FILE" ]; then
  APP_VERSION="$(tr -d '\r\n' < "$APP_VERSION_FILE")"
else
  APP_VERSION="2.0.0"
fi

if [ -z "$APP_VERSION" ]; then
  APP_VERSION="2.0.0"
fi

echo "📦 Using APP_VERSION=$APP_VERSION"

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
  REMOTE_DOWNLOAD_ROOT="/var/www/cleco.reignofplay.com/downloads"
  REMOTE_VERSION_DIR="$REMOTE_DOWNLOAD_ROOT/v$APP_VERSION"
  REMOTE_APK_PATH="$REMOTE_VERSION_DIR/app.apk"
  REMOTE_TMP_APK="/tmp/cleco-app-$APP_VERSION.apk"

  echo "🌐 Uploading APK to VPS ($VPS_SSH_TARGET)..."
  echo "📂 Remote path: $REMOTE_APK_PATH"

  # Upload APK to a temporary location, then move into place with sudo
  scp -i "$VPS_SSH_KEY" "$OUTPUT_APK" "$VPS_SSH_TARGET":"$REMOTE_TMP_APK"
  ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" "sudo mkdir -p '$REMOTE_VERSION_DIR' && sudo mv '$REMOTE_TMP_APK' '$REMOTE_APK_PATH' && sudo chown www-data:www-data '$REMOTE_APK_PATH' && sudo chmod 644 '$REMOTE_APK_PATH'"

  echo "✅ APK uploaded to VPS: $REMOTE_APK_PATH"
  echo "🔗 Expected download URL: https://cleco.reignofplay.com/downloads/v$APP_VERSION/app.apk"

  # Update mobile_release.json manifest on the VPS so Flask can serve
  # correct version info without needing a restart.
  REMOTE_SECRETS_DIR="/opt/apps/reignofplay/cleco/secrets"
  REMOTE_MANIFEST_PATH="$REMOTE_SECRETS_DIR/mobile_release.json"
  REMOTE_TMP_MANIFEST="/tmp/mobile_release.json"

  # Allow overriding minimum supported version via environment variable if needed
  MIN_SUPPORTED_VERSION="${MIN_SUPPORTED_VERSION:-$APP_VERSION}"

  echo "📝 Updating mobile_release.json manifest on VPS..."
  TMP_MANIFEST="$(mktemp)"
  cat > "$TMP_MANIFEST" <<EOF
{
  "latest_version": "$APP_VERSION",
  "min_supported_version": "$MIN_SUPPORTED_VERSION"
}
EOF

  scp -i "$VPS_SSH_KEY" "$TMP_MANIFEST" "$VPS_SSH_TARGET":"$REMOTE_TMP_MANIFEST"
  ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" "sudo mkdir -p '$REMOTE_SECRETS_DIR' && sudo mv '$REMOTE_TMP_MANIFEST' '$REMOTE_MANIFEST_PATH' && sudo chown root:root '$REMOTE_MANIFEST_PATH' && sudo chmod 644 '$REMOTE_MANIFEST_PATH'"
  rm -f "$TMP_MANIFEST"

  echo "✅ mobile_release.json updated on VPS: $REMOTE_MANIFEST_PATH"
fi

