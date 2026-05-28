#!/bin/sh
set -euo pipefail

echo "===> Xcode Cloud post-clone start"
echo "CI_WORKSPACE: ${CI_WORKSPACE:-"(not set)"}"

cd "${CI_WORKSPACE}"
cd flutter_base_05

flutter --version
flutter config --no-analytics
flutter pub get

cd ios
pod install --repo-update

echo "===> Post-clone complete"
