#!/bin/bash
set -euo pipefail

echo "===> Xcode Cloud post-clone start"
echo "CI_WORKSPACE: ${CI_WORKSPACE:-"(not set)"}"
echo "PWD: $(pwd)"

# Xcode Cloud usually sets CI_WORKSPACE; fall back to current dir.
REPO_ROOT="${CI_WORKSPACE:-$(pwd)}"
cd "${REPO_ROOT}"

if [ ! -d "flutter_base_05" ]; then
  echo "ERROR: flutter_base_05 directory not found at ${REPO_ROOT}"
  exit 1
fi

cd flutter_base_05

# Ensure Flutter is available on the runner.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found; installing stable channel..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "${HOME}/flutter"
  export PATH="${HOME}/flutter/bin:${PATH}"
fi

flutter --version
flutter config --no-analytics
flutter pub get

cd ios
pod install --repo-update

echo "===> Post-clone complete"
