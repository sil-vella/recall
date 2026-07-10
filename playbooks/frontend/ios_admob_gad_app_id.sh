#!/usr/bin/env bash
# Set ios/Flutter/{Debug,Release}.xcconfig GAD_APPLICATION_ID to production Dutch AdMob app id.
# iOS app id is native-only (Info.plist); dart-define ADMOB_APPLICATION_ID is for Android Gradle.
# Unit ids are server SSOT (.env.local|.prod → init-config); always use prod app id on device.

set -euo pipefail

_IOS_ADMOB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IOS_ADMOB_PROD_APP_ID="$(python3 -c "import sys; sys.path.insert(0, '$_IOS_ADMOB_SCRIPT_DIR'); from admob_test_ids import IOS_ADMOB_PROD_APP_ID; print(IOS_ADMOB_PROD_APP_ID)")"

ios_admob_gad_set_xcconfig() {
  local flutter_ios_dir="$1"
  local app_id="$_IOS_ADMOB_PROD_APP_ID"
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
  echo "ℹ️  iOS GAD_APPLICATION_ID → ${app_id} (production)"
}

# Args: env_file (ignored; kept for call-site compatibility), flutter_ios_dir
ios_admob_gad_configure_from_env() {
  local _env_file="$1"
  local flutter_ios_dir="$2"
  ios_admob_gad_set_xcconfig "$flutter_ios_dir"
}
