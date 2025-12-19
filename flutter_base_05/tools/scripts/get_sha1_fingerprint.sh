#!/bin/bash

# Script to get SHA-1 fingerprints for Android Google Sign-In configuration
# These fingerprints need to be registered in Firebase Console

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"
KEYSTORE_PROPERTIES="$PROJECT_ROOT/keystore.properties"

echo "🔐 Getting SHA-1 fingerprints for Google Sign-In configuration"
echo ""

# Check if keystore.properties exists
if [ ! -f "$KEYSTORE_PROPERTIES" ]; then
    echo "❌ Error: keystore.properties not found at $KEYSTORE_PROPERTIES"
    echo "   Please ensure your keystore configuration exists."
    exit 1
fi

# Read keystore properties
source "$KEYSTORE_PROPERTIES"

# Determine keystore path
if [ -f "$storeFile" ]; then
    KEYSTORE_PATH="$storeFile"
elif [ -f "$PROJECT_ROOT/$storeFile" ]; then
    KEYSTORE_PATH="$PROJECT_ROOT/$storeFile"
elif [ -f "$ANDROID_DIR/app/$storeFile" ]; then
    KEYSTORE_PATH="$ANDROID_DIR/app/$storeFile"
else
    echo "❌ Error: Keystore file not found: $storeFile"
    echo "   Searched in:"
    echo "     - $storeFile"
    echo "     - $PROJECT_ROOT/$storeFile"
    echo "     - $ANDROID_DIR/app/$storeFile"
    exit 1
fi

echo "📦 Keystore: $KEYSTORE_PATH"
echo "🔑 Key Alias: $keyAlias"
echo ""

# Get release keystore SHA-1
echo "🔍 Getting SHA-1 fingerprint from release keystore..."
RELEASE_SHA1=$(keytool -list -v -keystore "$KEYSTORE_PATH" -alias "$keyAlias" -storepass "$storePassword" -keypass "$keyPassword" 2>/dev/null | grep -A 1 "SHA1:" | grep -oE "[0-9A-F:]{59}" | head -1)

if [ -z "$RELEASE_SHA1" ]; then
    echo "❌ Error: Could not extract SHA-1 from release keystore"
    exit 1
fi

echo "✅ Release SHA-1: $RELEASE_SHA1"
echo ""

# Get debug keystore SHA-1 (usually in ~/.android/debug.keystore)
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"
if [ -f "$DEBUG_KEYSTORE" ]; then
    echo "🔍 Getting SHA-1 fingerprint from debug keystore..."
    DEBUG_SHA1=$(keytool -list -v -keystore "$DEBUG_KEYSTORE" -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep -A 1 "SHA1:" | grep -oE "[0-9A-F:]{59}" | head -1)
    
    if [ -n "$DEBUG_SHA1" ]; then
        echo "✅ Debug SHA-1: $DEBUG_SHA1"
        echo ""
    fi
else
    echo "⚠️  Debug keystore not found at $DEBUG_KEYSTORE"
    echo "   This is normal if you haven't built a debug APK yet."
    echo ""
fi

# Output summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 SHA-1 Fingerprints Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔴 RELEASE (Production APK):"
echo "   $RELEASE_SHA1"
echo ""
if [ -n "$DEBUG_SHA1" ]; then
    echo "🟡 DEBUG (Development APK):"
    echo "   $DEBUG_SHA1"
    echo ""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Next Steps:"
echo "   1. Go to Google Cloud Console: https://console.cloud.google.com"
echo "   2. Select your project → APIs & Services → Credentials"
echo "   3. Create OAuth 2.0 Client ID → Application type: Android"
echo "   4. Package name: com.reignofplay.cleco"
echo "   5. Add both SHA-1 fingerprints above to the Android OAuth client"
echo "   6. Copy the Android Client ID and set it as:"
echo "      - Environment variable: GOOGLE_CLIENT_ID_ANDROID"
echo "      - Or default in: lib/utils/consts/config.dart"
echo ""
