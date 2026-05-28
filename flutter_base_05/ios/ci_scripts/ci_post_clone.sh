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
flutter pub get
flutter precache --ios

# Ensure iOS plugin registrant/symlinks are generated before CocoaPods resolution.
flutter build ios --config-only --no-codesign

cd ios
rm -rf Pods .symlinks
pod install --repo-update

echo "===> Post-clone complete"
