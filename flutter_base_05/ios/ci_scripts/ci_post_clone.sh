#!/bin/bash
set -euo pipefail

echo "===> Xcode Cloud post-clone start"
echo "CI_WORKSPACE: ${CI_WORKSPACE:-"(not set)"}"
echo "PWD: $(pwd)"

# Derive paths from script location so this works even when CI_WORKSPACE is unset.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLUTTER_APP_DIR="$(cd "${IOS_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FLUTTER_APP_DIR}/.." && pwd)"

echo "SCRIPT_DIR: ${SCRIPT_DIR}"
echo "IOS_DIR: ${IOS_DIR}"
echo "FLUTTER_APP_DIR: ${FLUTTER_APP_DIR}"
echo "REPO_ROOT: ${REPO_ROOT}"

if [ ! -f "${FLUTTER_APP_DIR}/pubspec.yaml" ]; then
  echo "ERROR: pubspec.yaml not found at ${FLUTTER_APP_DIR}"
  exit 1
fi

cd "${FLUTTER_APP_DIR}"

# Ensure Flutter is available on the runner.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found; installing stable channel..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "${HOME}/flutter"
  export PATH="${HOME}/flutter/bin:${PATH}"
fi

flutter --version
flutter config --no-analytics
# Temporary compatibility: google_mobile_ads is CocoaPods-only while some plugins
# can switch to SPM in newer Flutter toolchains.
flutter config --no-enable-swift-package-manager
flutter pub get
flutter precache --ios

# Ensure iOS plugin registrant/symlinks are generated before CocoaPods resolution.
flutter build ios --config-only --no-codesign

# Keep Flutter-generated xcconfig aligned with Xcode CURRENT_PROJECT_VERSION (20042).
GENERATED_XCCONFIG="${FLUTTER_APP_DIR}/ios/Flutter/Generated.xcconfig"
if [ -f "${GENERATED_XCCONFIG}" ]; then
  sed -i '' 's/^FLUTTER_BUILD_NUMBER=.*/FLUTTER_BUILD_NUMBER=20042/' "${GENERATED_XCCONFIG}"
fi

cd ios
rm -rf Pods .symlinks

# Avoid hard-failing on transient CDN DNS issues.
# 1) Try plain pod install first (uses cached specs if available).
# 2) Retry with repo update using exponential backoff.
if pod install; then
  echo "pod install succeeded without repo update"
else
  echo "pod install failed; retrying with --repo-update"
  attempts=0
  max_attempts=4
  sleep_seconds=5
  until [ "$attempts" -ge "$max_attempts" ]; do
    if pod install --repo-update; then
      echo "pod install --repo-update succeeded"
      break
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo "ERROR: pod install failed after ${max_attempts} attempts"
      exit 1
    fi
    echo "Retry ${attempts}/${max_attempts} after ${sleep_seconds}s..."
    sleep "$sleep_seconds"
    sleep_seconds=$((sleep_seconds * 2))
  done
fi

echo "===> Post-clone complete"
