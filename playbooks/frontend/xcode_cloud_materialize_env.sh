#!/usr/bin/env bash
# Materialize repo-root prod env files on Xcode Cloud from workflow secrets.
# Call after REPO_ROOT is set.
#
# Local dry-run: place .env.dart.defines.prod on disk and skip secrets.
# Xcode Cloud: set workflow secret DUTCH_DART_DEFINES_PROD_B64 (required).
# Optional: DUTCH_ENV_PROD_B64 → .env.prod

xcode_cloud_materialize_env() {
  local root="${REPO_ROOT:-}"
  if [ -z "$root" ]; then
    echo "xcode_cloud_materialize_env: REPO_ROOT not set" >&2
    return 1
  fi

  local dart_env="$root/.env.dart.defines.prod"
  local frontend_env="$root/.env.prod"

  if [ -f "$dart_env" ]; then
    echo "📝 Using existing $dart_env"
  elif [ -n "${DUTCH_DART_DEFINES_PROD_B64:-}" ]; then
    echo "📝 Decoding DUTCH_DART_DEFINES_PROD_B64 → $dart_env"
    printf '%s' "$DUTCH_DART_DEFINES_PROD_B64" | base64 -d >"$dart_env"
  else
    echo "❌ Missing $dart_env and DUTCH_DART_DEFINES_PROD_B64 workflow secret." >&2
    echo "   Add secret in App Store Connect → Xcode Cloud → Workflow → Environment." >&2
    echo "   Generate: base64 -i .env.dart.defines.prod | pbcopy" >&2
    return 1
  fi

  if [ ! -s "$dart_env" ]; then
    echo "❌ $dart_env is empty after materialize" >&2
    return 1
  fi

  if [ -f "$frontend_env" ]; then
    echo "📝 Using existing $frontend_env"
  elif [ -n "${DUTCH_ENV_PROD_B64:-}" ]; then
    echo "📝 Decoding DUTCH_ENV_PROD_B64 → $frontend_env"
    printf '%s' "$DUTCH_ENV_PROD_B64" | base64 -d >"$frontend_env"
  else
    echo "ℹ️  No $frontend_env (optional); version will come from pubspec.yaml"
  fi

  export DART_DEFINES_ENV="$dart_env"
  export FRONTEND_ENV="$frontend_env"
}
