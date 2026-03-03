#!/bin/bash
# Generates flutter_base_05/macos/Runner/GoogleService-Info.plist from playbooks/frontend/.env
# so Firebase credentials are not hardcoded in the repo. Run from repo root or playbooks/frontend.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLIST_PATH="$REPO_ROOT/flutter_base_05/macos/Runner/GoogleService-Info.plist"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "❌ Missing $SCRIPT_DIR/.env — copy .env.example to .env and set FIREBASE_IOS_* (and GCM_SENDER_ID) values."
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"
set +a

# GCM_SENDER_ID is the same as messagingSenderId (e.g. 851791240618)
GCM_SENDER_ID="${FIREBASE_IOS_MESSAGING_SENDER_ID:-${GCM_SENDER_ID}}"

cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>${FIREBASE_IOS_API_KEY:-}</string>
	<key>GCM_SENDER_ID</key>
	<string>${GCM_SENDER_ID:-}</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>${FIREBASE_IOS_BUNDLE_ID:-}</string>
	<key>PROJECT_ID</key>
	<string>${FIREBASE_IOS_PROJECT_ID:-}</string>
	<key>STORAGE_BUCKET</key>
	<string>${FIREBASE_IOS_STORAGE_BUCKET:-}</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
	<key>IS_APPINVITE_ENABLED</key>
	<true></true>
	<key>IS_GCM_ENABLED</key>
	<true></true>
	<key>IS_SIGNIN_ENABLED</key>
	<true></true>
	<key>GOOGLE_APP_ID</key>
	<string>${FIREBASE_IOS_APP_ID:-}</string>
</dict>
</plist>
EOF
echo "✅ Wrote $PLIST_PATH from .env"
