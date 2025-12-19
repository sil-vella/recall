#!/bin/bash

# Flutter Android debug launcher with Google Sign-In debugging
# Uses hot reload for fast iteration - no need to rebuild APKs!

set -e

echo "🚀 Launching Flutter app on Android device for local testing..."
echo "💡 This uses hot reload - changes apply instantly without rebuilding!"

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb not found. Please install Android SDK and add to PATH"
    exit 1
fi

# Check if any device is connected
echo "📱 Checking device connection..."
DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l | tr -d ' ')
if [ "$DEVICES" -eq 0 ]; then
    echo "❌ Error: No Android device found"
    echo "Available devices:"
    adb devices
    exit 1
fi

# Get device ID (use first connected device)
DEVICE_ID=$(adb devices | grep -v "List" | grep "device$" | head -1 | cut -f1)
echo "✅ Found Android device: $DEVICE_ID"

# Navigate to Flutter project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT/flutter_base_05"

# Determine backend target from first argument: 'local' (default) or 'vps'
BACKEND_TARGET="${1:-local}"

if [ "$BACKEND_TARGET" = "vps" ]; then
    API_URL="https://cleco.reignofplay.com"
    WS_URL="wss://cleco.reignofplay.com/ws"
    echo "🌐 Using VPS backend: API_URL=$API_URL, WS_URL=$WS_URL"
else
    # Local LAN IP for Python & Dart services
    API_URL="http://192.168.178.81:5001"
    WS_URL="ws://192.168.178.81:8080"
    echo "💻 Using LOCAL backend: API_URL=$API_URL, WS_URL=$WS_URL"
fi

# For local testing, we need to use the DEBUG OAuth client ID
# Since debug builds use debug keystore (SHA-1: 44:FF:5B:9F:...)
# You'll need to create a separate debug OAuth client in Google Cloud Console
# For now, we'll use the release client ID - if it fails, create a debug client
GOOGLE_CLIENT_ID_ANDROID="${GOOGLE_CLIENT_ID_ANDROID:-907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com}"

echo ""
echo "🔐 Google Sign-In Configuration:"
echo "   Android Client ID: $GOOGLE_CLIENT_ID_ANDROID"
echo "   ⚠️  Note: Debug builds use debug keystore"
echo "   If Google Sign-In fails, you may need a separate debug OAuth client"
echo ""

echo "🎯 Launching Flutter app with hot reload..."
echo "   Press 'r' to hot reload, 'R' to hot restart, 'q' to quit"
echo ""

# Launch Flutter with all necessary dart-define flags
flutter run \
    -d "$DEVICE_ID" \
    --dart-define=API_URL="$API_URL" \
    --dart-define=WS_URL="$WS_URL" \
    --dart-define=GOOGLE_CLIENT_ID_ANDROID="$GOOGLE_CLIENT_ID_ANDROID" \
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

echo ""
echo "✅ Flutter app session ended"
echo ""
echo "💡 Tips for Google Sign-In debugging:"
echo "   1. Check logs for 'LoginModule: Google Sign-In initialized'"
echo "   2. Look for the Client ID being used"
echo "   3. If you see error code 10, the SHA-1 doesn't match"
echo "   4. For debug builds, create a separate debug OAuth client with debug SHA-1"
