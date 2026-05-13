#!/bin/bash

# Flutter Web build script
# Builds a web release for Dutch and uploads to VPS
# The web app will be served from dutch.reignofplay.com
# To deploy to a subdir (e.g. dutch.reignofplay.com/example): DEPLOY_SUBDIR=example ./build_web.sh vps
#   (Build the Flutter app with base-href /example/ when targeting the subdir.)
# Dart-define input: repo-root `.env.dart.defines.prod`. Shell sources `.env.prod` for bump / deploy.

set -e

echo "🚀 Building Flutter Web for Dutch..."

# Resolve repository root (two levels up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_ENV="$REPO_ROOT/.env.prod"
DART_DEFINES_ENV="$REPO_ROOT/.env.dart.defines.prod"
export DART_DEFINES_ENV

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
DART_DEF_JSON=""
trap 'restore_deck_config; rm -f "${DART_DEF_JSON:-}"' EXIT

# Post-build deploy: `vps` (default) uploads to VPS; `local` skips. API_URL/WS_URL: from .env.dart.defines.prod.
BACKEND_TARGET="${1:-vps}"
if [ "$BACKEND_TARGET" = "local" ]; then
  echo "📤 Skipping VPS deploy (arg: local). API_URL/WS_URL come from $DART_DEFINES_ENV."
else
  echo "📤 After build: VPS deploy enabled (arg: vps). API_URL/WS_URL come from $DART_DEFINES_ENV."
fi

# Load env from repo root .env.prod (APP_VERSION bump, deploy-related vars, etc.)
if [ -f "$FRONTEND_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$FRONTEND_ENV"
  set +a
else
  echo "⚠️  Warning: $FRONTEND_ENV not found — APP_VERSION bump and deploy-related shell vars may be missing (dart-defines use $DART_DEFINES_ENV)."
fi

# APP_VERSION SSOT: .env.prod; interactive patch bump shared with build_apk.sh
# shellcheck source=/dev/null
source "$SCRIPT_DIR/bump_app_version_prompt.sh"
bump_app_version_prompt

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
echo "ℹ️  ADMOBS_* in .env.dart.defines.prod are for native builds; web skips AdMob. See Documentation/flutter_base_05/ADMOB_NATIVE_SETUP.md"

# Build the web release
echo "🌐 Building Flutter web release..."
flutter build web \
  --release \
  --build-name="$APP_VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define-from-file="$DART_DEF_JSON"

OUTPUT_DIR="$REPO_ROOT/flutter_base_05/build/web"

if [ -d "$OUTPUT_DIR" ] && [ -f "$OUTPUT_DIR/index.html" ]; then
  echo "✅ Web build completed: $OUTPUT_DIR"
  INDEX_HTML="$OUTPUT_DIR/index.html"

  # Cache-bust: add ?v=$APP_VERSION so entry shell + bootstrap + linked shell assets get new URLs each release.
  # (Flutter's service worker still hashes main.dart.js/canvaskit/assets; this fixes stale index.html/bootstrap.)
  # Production nginx should serve index.html with Cache-Control: no-cache so the HTML revalidates (configure on server).
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"site.webmanifest\"|href=\"site.webmanifest?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"manifest.json\"|href=\"manifest.json?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"favicon.png\"|href=\"favicon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"favicon-96x96.png\"|href=\"favicon-96x96.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"favicon.svg\"|href=\"favicon.svg?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"favicon.ico\"|href=\"favicon.ico?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"apple-touch-icon.png\"|href=\"apple-touch-icon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i '' "s|href=\"icons/Icon-192.png\"|href=\"icons/Icon-192.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
  else
    sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"site.webmanifest\"|href=\"site.webmanifest?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"manifest.json\"|href=\"manifest.json?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"favicon.png\"|href=\"favicon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"favicon-96x96.png\"|href=\"favicon-96x96.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"favicon.svg\"|href=\"favicon.svg?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"favicon.ico\"|href=\"favicon.ico?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"apple-touch-icon.png\"|href=\"apple-touch-icon.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
    sed -i "s|href=\"icons/Icon-192.png\"|href=\"icons/Icon-192.png?v=$APP_VERSION\"|g" "$INDEX_HTML"
  fi
  echo "🔖 Cache-bust: added ?v=$APP_VERSION to index.html (bootstrap, site.webmanifest, favicons, icons)"

  # Mandatory reload: inject no-cache meta tags so browsers and proxies don't serve a cached index.html.
  # Together with Nginx sending Cache-Control: no-cache for index.html, this encourages a fresh load on each visit.
  if grep -q "<head>" "$INDEX_HTML" && ! grep -q "Cache-Control.*no-cache" "$INDEX_HTML"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's|<head>|<head><meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"><meta http-equiv="Pragma" content="no-cache"><meta http-equiv="Expires" content="0">|' "$INDEX_HTML"
    else
      sed -i 's|<head>|<head><meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"><meta http-equiv="Pragma" content="no-cache"><meta http-equiv="Expires" content="0">|' "$INDEX_HTML"
    fi
    echo "🔒 No-cache meta tags added to index.html (mandatory reload on login/visit)"
  fi
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
    # Copy to subdir (e.g. dutch.reignofplay.com/example) or to main web root
    DEPLOY_SUBDIR="${DEPLOY_SUBDIR:-}"
    if [ -n "$DEPLOY_SUBDIR" ]; then
      DEPLOY_DEST="$REMOTE_WEB_ROOT/$DEPLOY_SUBDIR"
      echo "📋 Deploying to subdir: $DEPLOY_DEST"
      sudo mkdir -p "$DEPLOY_DEST"
      sudo rm -rf "$DEPLOY_DEST"/* 2>/dev/null || true
      sudo cp -r "$REMOTE_TMP_DIR"/* "$DEPLOY_DEST/"
    else
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
        ! -name "example" \
        ! -name "register" \
        ! -name ".well-known" \
        -exec rm -rf {} + 2>/dev/null || true

      echo "📋 Installing new web build..."
      sudo cp -r "$REMOTE_TMP_DIR"/* "$REMOTE_WEB_ROOT/"
    fi
    
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
  if [ -n "${DEPLOY_SUBDIR:-}" ]; then
    echo "✅ Web build uploaded to VPS: $REMOTE_WEB_ROOT/$DEPLOY_SUBDIR"
    echo "🔗 Web app URL: https://dutch.reignofplay.com/$DEPLOY_SUBDIR"
  else
    echo "✅ Web build uploaded and installed to VPS: $REMOTE_WEB_ROOT"
    echo "🔗 Web app URL: https://dutch.reignofplay.com"
  fi
  echo "📊 Version: $APP_VERSION"
  echo ""
  echo "🎉 Deployment complete! The Flutter web app is now live."
fi
