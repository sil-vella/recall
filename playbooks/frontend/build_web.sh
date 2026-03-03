#!/bin/bash

# Flutter Web build script
# Builds a web release for Dutch and uploads to VPS
# The web app will be served from dutch.mt

set -e

echo "🚀 Building Flutter Web for Dutch..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Flutter assets: set testing_mode=false and predefined_hands enabled=false for production build (restored on exit)
# Backups go to /tmp so they are not bundled into build/web
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

# Determine backend target from first argument: 'local' or 'vps' (default: vps for production)
BACKEND_TARGET="${1:-vps}"

if [ "$BACKEND_TARGET" = "local" ]; then
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    API_URL="https://dutch.mt"
    WS_URL="wss://dutch.mt/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# App version and Firebase/sensitive vars: from playbooks/frontend/.env then repo .env
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi
APP_VERSION="${APP_VERSION:-2.0.0}"
echo "📦 Using version: $APP_VERSION (from APP_VERSION env / .env)"
echo "ℹ️  Web apps update automatically on the server - no version bump needed"

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

# Build the web release (Firebase/sensitive from .env via dart-define)
echo "🌐 Building Flutter web release..."
flutter build web \
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
  --dart-define=ADMOBS_TOP_BANNER01="${ADMOBS_TOP_BANNER01:-ca-app-pub-3940256099942544/9214589741}" \
  --dart-define=ADMOBS_BOTTOM_BANNER01="${ADMOBS_BOTTOM_BANNER01:-ca-app-pub-3940256099942544/9214589741}" \
  --dart-define=ADMOBS_INTERSTITIAL01="${ADMOBS_INTERSTITIAL01:-ca-app-pub-3940256099942544/1033173712}" \
  --dart-define=ADMOBS_REWARDED01="${ADMOBS_REWARDED01:-ca-app-pub-3940256099942544/5224354917}" \
  --dart-define=STRIPE_PUBLISHABLE_KEY="${STRIPE_PUBLISHABLE_KEY:-}" \
  --dart-define=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}" \
  --dart-define=GOOGLE_CLIENT_ID_ANDROID="${GOOGLE_CLIENT_ID_ANDROID:-}" \
  --dart-define=FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:-}" \
  --dart-define=FIREBASE_WEB_APP_ID="${FIREBASE_WEB_APP_ID:-}" \
  --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID="${FIREBASE_WEB_MESSAGING_SENDER_ID:-}" \
  --dart-define=FIREBASE_WEB_PROJECT_ID="${FIREBASE_WEB_PROJECT_ID:-}" \
  --dart-define=FIREBASE_WEB_AUTH_DOMAIN="${FIREBASE_WEB_AUTH_DOMAIN:-}" \
  --dart-define=FIREBASE_WEB_STORAGE_BUCKET="${FIREBASE_WEB_STORAGE_BUCKET:-}" \
  --dart-define=FIREBASE_WEB_MEASUREMENT_ID="${FIREBASE_WEB_MEASUREMENT_ID:-}" \
  --dart-define=FIREBASE_ANDROID_API_KEY="${FIREBASE_ANDROID_API_KEY:-}" \
  --dart-define=FIREBASE_ANDROID_APP_ID="${FIREBASE_ANDROID_APP_ID:-}" \
  --dart-define=FIREBASE_ANDROID_MESSAGING_SENDER_ID="${FIREBASE_ANDROID_MESSAGING_SENDER_ID:-}" \
  --dart-define=FIREBASE_ANDROID_PROJECT_ID="${FIREBASE_ANDROID_PROJECT_ID:-}" \
  --dart-define=FIREBASE_ANDROID_STORAGE_BUCKET="${FIREBASE_ANDROID_STORAGE_BUCKET:-}" \
  --dart-define=FIREBASE_IOS_API_KEY="${FIREBASE_IOS_API_KEY:-}" \
  --dart-define=FIREBASE_IOS_APP_ID="${FIREBASE_IOS_APP_ID:-}" \
  --dart-define=FIREBASE_IOS_MESSAGING_SENDER_ID="${FIREBASE_IOS_MESSAGING_SENDER_ID:-}" \
  --dart-define=FIREBASE_IOS_PROJECT_ID="${FIREBASE_IOS_PROJECT_ID:-}" \
  --dart-define=FIREBASE_IOS_STORAGE_BUCKET="${FIREBASE_IOS_STORAGE_BUCKET:-}" \
  --dart-define=FIREBASE_IOS_BUNDLE_ID="${FIREBASE_IOS_BUNDLE_ID:-}" \
  --dart-define=FIREBASE_WINDOWS_API_KEY="${FIREBASE_WINDOWS_API_KEY:-}" \
  --dart-define=FIREBASE_WINDOWS_APP_ID="${FIREBASE_WINDOWS_APP_ID:-}" \
  --dart-define=FIREBASE_WINDOWS_MESSAGING_SENDER_ID="${FIREBASE_WINDOWS_MESSAGING_SENDER_ID:-}" \
  --dart-define=FIREBASE_WINDOWS_PROJECT_ID="${FIREBASE_WINDOWS_PROJECT_ID:-}" \
  --dart-define=FIREBASE_WINDOWS_AUTH_DOMAIN="${FIREBASE_WINDOWS_AUTH_DOMAIN:-}" \
  --dart-define=FIREBASE_WINDOWS_STORAGE_BUCKET="${FIREBASE_WINDOWS_STORAGE_BUCKET:-}" \
  --dart-define=FIREBASE_WINDOWS_MEASUREMENT_ID="${FIREBASE_WINDOWS_MEASUREMENT_ID:-}" \
  --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
  --dart-define=DEBUG_MODE=true \
  --dart-define=ENABLE_REMOTE_LOGGING=true

OUTPUT_DIR="$REPO_ROOT/flutter_base_05/build/web"

if [ -d "$OUTPUT_DIR" ] && [ -f "$OUTPUT_DIR/index.html" ]; then
  echo "✅ Web build completed: $OUTPUT_DIR"
  # Cache-bust: add version query string so browsers load fresh script/manifest instead of cache.
  # For best results the web server should send Cache-Control: no-cache (or max-age=0) for index.html.
  INDEX_HTML="$OUTPUT_DIR/index.html"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"manifest.json\"|href=\"manifest.json?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"favicon.png\"|href=\"favicon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"icons/Icon-192.png\"|href=\"icons/Icon-192.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
  else
    sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"manifest.json\"|href=\"manifest.json?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"favicon.png\"|href=\"favicon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"icons/Icon-192.png\"|href=\"icons/Icon-192.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
  fi
  echo "🔖 Cache-bust: added ?v=$APP_VERSION to index.html script and manifest URLs"
  echo "📊 Build size:"
  du -sh "$OUTPUT_DIR"
  echo ""
  # Remove any .bak files from build output so they are not uploaded
  BAK_COUNT=$(find "$OUTPUT_DIR" -name "*.bak" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BAK_COUNT" -gt 0 ]; then
    find "$OUTPUT_DIR" -name "*.bak" -type f -delete
    echo "🧹 Removed $BAK_COUNT .bak file(s) from build output"
  fi
  echo "📁 Key files:"
  ls -lh "$OUTPUT_DIR" | head -10
else
  echo "❌ Web build finished but $OUTPUT_DIR/index.html was not found. Check Flutter build output above."
  exit 1
fi

# If building for VPS backend, upload web build to VPS
if [ "$BACKEND_TARGET" = "vps" ]; then
  # Default to non-root app user; override with VPS_SSH_TARGET if needed
  VPS_SSH_TARGET="${VPS_SSH_TARGET:-rop01_user@65.181.125.135}"
  # SSH key to use for uploads (defaults to same key as inventory.ini / 01_setup_ssh_key.sh)
  VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/rop01_key}"
  REMOTE_WEB_ROOT="/var/www/dutch.reignofplay.com"
  REMOTE_TMP_DIR="/tmp/dutch-web-$APP_VERSION-$$"

  echo ""
  echo "🌐 Uploading web build to VPS ($VPS_SSH_TARGET)..."
  echo "📂 Remote path: $REMOTE_WEB_ROOT"
  echo "📦 Temporary staging: $REMOTE_TMP_DIR"

  # Create temporary directory on VPS (owned by remote user)
  REMOTE_USER=$(echo "$VPS_SSH_TARGET" | cut -d'@' -f1)
  ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" "sudo mkdir -p '$REMOTE_TMP_DIR' && sudo chown -R $REMOTE_USER:$REMOTE_USER '$REMOTE_TMP_DIR'"

  # Upload all web build files to temporary directory
  echo "📤 Uploading files..."
  rsync -avz --progress \
    -e "ssh -i $VPS_SSH_KEY" \
    "$OUTPUT_DIR/" \
    "$VPS_SSH_TARGET:$REMOTE_TMP_DIR/"

  # Move files to web root with proper permissions
  echo "📦 Installing files to web root..."
  ssh -i "$VPS_SSH_KEY" "$VPS_SSH_TARGET" <<EOF
    # Backup existing web files (if any) to a timestamped backup
    if [ -d "$REMOTE_WEB_ROOT" ] && [ "\$(ls -A $REMOTE_WEB_ROOT 2>/dev/null)" ]; then
      BACKUP_DIR="/tmp/dutch-web-backup-\$(date +%Y%m%d-%H%M%S)"
      echo "💾 Backing up existing files to: \$BACKUP_DIR"
      sudo mkdir -p "\$BACKUP_DIR"
      sudo cp -r "$REMOTE_WEB_ROOT"/* "\$BACKUP_DIR/" 2>/dev/null || true
      echo "✅ Backup created: \$BACKUP_DIR"
    fi

    # Remove old web files (except static directories that should be preserved)
    echo "🧹 Cleaning web root (preserving static directories)..."
    sudo find "$REMOTE_WEB_ROOT" -mindepth 1 -maxdepth 1 \
      ! -name "sponsors" \
      ! -name "sim_players" \
      ! -name "downloads" \
      ! -name ".well-known" \
      -exec rm -rf {} + 2>/dev/null || true

    # Copy new files to web root
    echo "📋 Installing new web build..."
    sudo cp -r "$REMOTE_TMP_DIR"/* "$REMOTE_WEB_ROOT/"
    
    # Set proper ownership and permissions
    echo "🔐 Setting permissions..."
    sudo chown -R www-data:www-data "$REMOTE_WEB_ROOT"
    sudo find "$REMOTE_WEB_ROOT" -type f -exec chmod 644 {} \;
    sudo find "$REMOTE_WEB_ROOT" -type d -exec chmod 755 {} \;
    
    # Clean up temporary directory
    sudo rm -rf "$REMOTE_TMP_DIR"
    
    echo "✅ Web build installed successfully!"
EOF

  echo ""
  echo "✅ Web build uploaded and installed to VPS: $REMOTE_WEB_ROOT"
  echo "🔗 Web app URL: https://dutch.mt"
  echo "📊 Version: $APP_VERSION"
  echo ""
  echo "🎉 Deployment complete! The Flutter web app is now live."
fi
