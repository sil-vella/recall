#!/usr/bin/env bash
# Set ios/Flutter/{Debug,Release}.xcconfig GAD_APPLICATION_ID for test vs production.
# iOS app id is native-only (Info.plist); dart-define ADMOB_APPLICATION_ID is for Android Gradle.

set -euo pipefail

_IOS_ADMOB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IOS_ADMOB_TEST_APP_ID="$(python3 -c "import sys; sys.path.insert(0, '$_IOS_ADMOB_SCRIPT_DIR'); from admob_test_ids import IOS_ADMOB_TEST; print(IOS_ADMOB_TEST['ADMOB_APPLICATION_ID'])")"
_IOS_ADMOB_PROD_APP_ID="$(python3 -c "import sys; sys.path.insert(0, '$_IOS_ADMOB_SCRIPT_DIR'); from admob_test_ids import IOS_ADMOB_PROD_APP_ID; print(IOS_ADMOB_PROD_APP_ID)")"

ios_admob_gad_set_xcconfig() {
  local flutter_ios_dir="$1"
  local use_test="$2"
  local app_id
  if [ "$use_test" = "1" ]; then
    app_id="$_IOS_ADMOB_TEST_APP_ID"
  else
    app_id="$_IOS_ADMOB_PROD_APP_ID"
  fi
  for cfg in Debug Release; do
    local path="$flutter_ios_dir/Flutter/${cfg}.xcconfig"
    if [ ! -f "$path" ]; then
      echo "ios_admob_gad_set_xcconfig: missing $path" >&2
      return 1
    fi
    if grep -q '^GAD_APPLICATION_ID=' "$path"; then
      sed -i.bak "s|^GAD_APPLICATION_ID=.*|GAD_APPLICATION_ID=${app_id}|" "$path"
      rm -f "${path}.bak"
    else
      printf '\nGAD_APPLICATION_ID=%s\n' "$app_id" >>"$path"
    fi
  done
  echo "ℹ️  iOS GAD_APPLICATION_ID → ${app_id} (test=${use_test})"
}

# Args: env_file path (e.g. .env.dart.defines.prod). Default ADMOB_IOS_USE_TEST_IDS=1 when unset.
ios_admob_gad_configure_from_env() {
  local env_file="$1"
  local flutter_ios_dir="$2"
  local use_test="1"
  if [ -f "$env_file" ]; then
    local raw
    raw="$(grep -E '^ADMOB_IOS_USE_TEST_IDS=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\"'" || true)"
    case "$(echo "$raw" | tr '[:upper:]' '[:lower:]')" in
      0|false|no|off) use_test="0" ;;
      *) use_test="1" ;;
    esac
  fi
  ios_admob_gad_set_xcconfig "$flutter_ios_dir" "$use_test"
}
