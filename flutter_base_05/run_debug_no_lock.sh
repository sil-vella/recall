#!/bin/bash

# Flutter debug run script with screen lock prevention
# This script runs Flutter in debug mode with additional flags to prevent screen lock

echo "Starting Flutter app in debug mode with screen lock prevention..."

# Run Flutter with debug flags
flutter run \
  --debug \
  --hot \
  --dart-define=FLUTTER_KEEP_SCREEN_ON=true \
  --dart-define=DEBUG_MODE=true

echo "App started in debug mode. Screen lock is disabled." 