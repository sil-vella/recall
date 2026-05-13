#!/usr/bin/env bash
# Interactive patch bump for APP_VERSION in FRONTEND_ENV (repo root .env.prod).
# When DART_DEFINES_ENV is set (e.g. .env.dart.defines.prod), mirrors APP_VERSION there so
# `env_for_flutter_dart_defines.py` and `--build-name` stay aligned.
# Sourced by build_apk.sh and build_web.sh after FRONTEND_ENV is loaded and `set +a`.
#
#   source "$SCRIPT_DIR/bump_app_version_prompt.sh"
#   bump_app_version_prompt

bump_app_version_prompt() {
  local env_file="${FRONTEND_ENV:-}"
  if [ -z "$env_file" ]; then
    echo "⚠️  bump_app_version_prompt: FRONTEND_ENV not set" >&2
    return 1
  fi

  local current="${APP_VERSION:-2.0.0}"

  echo ""
  echo "📦 Current version (APP_VERSION from $(basename "$env_file")): $current"
  echo ""
  read -p "🤔 Bump version number? (y/n) [n]: " -n 1 -r
  echo ""

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$current"
    MAJOR=${MAJOR:-0}
    MINOR=${MINOR:-0}
    PATCH=${PATCH:-0}
    if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then MAJOR=0; fi
    if ! [[ "$MINOR" =~ ^[0-9]+$ ]]; then MINOR=0; fi
    if ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then PATCH=0; fi
    PATCH=$((PATCH + 1))
    local NEW_VERSION="$MAJOR.$MINOR.$PATCH"

    if [ -f "$env_file" ] && grep -q '^APP_VERSION=' "$env_file" 2>/dev/null; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$NEW_VERSION/" "$env_file"
      else
        sed -i "s/^APP_VERSION=.*/APP_VERSION=$NEW_VERSION/" "$env_file"
      fi
    else
      echo "APP_VERSION=$NEW_VERSION" >> "$env_file"
    fi
    echo "✅ Version bumped: $current → $NEW_VERSION"
    echo "📝 Updated APP_VERSION in $env_file"
    local dart_file="${DART_DEFINES_ENV:-}"
    if [ -n "$dart_file" ] && [ -f "$dart_file" ]; then
      if grep -q '^APP_VERSION=' "$dart_file" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
          sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$NEW_VERSION/" "$dart_file"
        else
          sed -i "s/^APP_VERSION=.*/APP_VERSION=$NEW_VERSION/" "$dart_file"
        fi
      else
        echo "APP_VERSION=$NEW_VERSION" >> "$dart_file"
      fi
      echo "📝 Mirrored APP_VERSION to $dart_file"
    fi
    APP_VERSION="$NEW_VERSION"
  else
    APP_VERSION="$current"
    echo "ℹ️  Using existing version: $APP_VERSION"
  fi

  echo "📦 Building with APP_VERSION=$APP_VERSION"
}
