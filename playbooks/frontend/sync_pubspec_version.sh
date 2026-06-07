#!/usr/bin/env bash
# Sync release version across Flutter + iOS/Xcode:
#   - flutter_base_05/pubspec.yaml `version:`
#   - Runner MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.pbxproj
#   - FLUTTER_BUILD_NUMBER pin in ios/ci_scripts/ci_post_clone.sh
# BUILD_NUMBER uses the same formula as build_appbundle.sh / build_apk.sh:
#   major * 10000 + minor * 100 + patch
#
# Usage (after APP_VERSION / BUILD_NUMBER are set):
#   REPO_ROOT=... source "$SCRIPT_DIR/sync_pubspec_version.sh"
#   sync_pubspec_version
# Or: sync_pubspec_version "2.0.32" 20032

compute_build_number_from_version() {
  local ver="$1"
  local ma mi pa
  IFS='.' read -r ma mi pa <<< "$ver"
  ma=${ma:-0}
  mi=${mi:-0}
  pa=${pa:-0}
  if ! [[ "$ma" =~ ^[0-9]+$ ]]; then ma=0; fi
  if ! [[ "$mi" =~ ^[0-9]+$ ]]; then mi=0; fi
  if ! [[ "$pa" =~ ^[0-9]+$ ]]; then pa=0; fi
  echo $((ma * 10000 + mi * 100 + pa))
}

# Runner app target only (skips RunnerTests MARKETING_VERSION = 1.0).
sync_ios_xcode_version() {
  local app_version="${1:-${APP_VERSION:-}}"
  local build_number="${2:-${BUILD_NUMBER:-}}"
  local root="${REPO_ROOT:-}"

  if [ -z "$app_version" ] || [ -z "$build_number" ]; then
    echo "sync_ios_xcode_version: APP_VERSION and BUILD_NUMBER required" >&2
    return 1
  fi
  if [ -z "$root" ]; then
    echo "sync_ios_xcode_version: REPO_ROOT not set" >&2
    return 1
  fi

  local pbxproj="$root/flutter_base_05/ios/Runner.xcodeproj/project.pbxproj"
  if [ ! -f "$pbxproj" ]; then
    echo "sync_ios_xcode_version: missing $pbxproj" >&2
    return 1
  fi

  python3 - "$pbxproj" "$app_version" "$build_number" <<'PY'
import re
import sys
from pathlib import Path

pbx_path, marketing_version, build_number = sys.argv[1:4]
text = Path(pbx_path).read_text()

block_re = re.compile(
    r"(\t\t\w+ /\* \w+ \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};)",
    re.DOTALL,
)

def update_runner_block(block: str) -> str:
    if "INFOPLIST_FILE = Runner/Info.plist;" not in block:
        return block
    block = re.sub(
        r"\t\t\t\tMARKETING_VERSION = [^;]+;",
        f"\t\t\t\tMARKETING_VERSION = {marketing_version};",
        block,
    )
    block = re.sub(
        r"\t\t\t\tCURRENT_PROJECT_VERSION = [^;]+;",
        f"\t\t\t\tCURRENT_PROJECT_VERSION = {build_number};",
        block,
    )
    return block

updated = block_re.sub(lambda m: update_runner_block(m.group(1)), text)
Path(pbx_path).write_text(updated)
PY

  local ci_script="$root/flutter_base_05/ios/ci_scripts/ci_post_clone.sh"
  if [ -f "$ci_script" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' -E "s/CURRENT_PROJECT_VERSION \([0-9]+\)/CURRENT_PROJECT_VERSION (${build_number})/" "$ci_script"
      sed -i '' -E "s/FLUTTER_BUILD_NUMBER=[0-9]+/FLUTTER_BUILD_NUMBER=${build_number}/" "$ci_script"
    else
      sed -i -E "s/CURRENT_PROJECT_VERSION \([0-9]+\)/CURRENT_PROJECT_VERSION (${build_number})/" "$ci_script"
      sed -i -E "s/FLUTTER_BUILD_NUMBER=[0-9]+/FLUTTER_BUILD_NUMBER=${build_number}/" "$ci_script"
    fi
    echo "📝 Synced ci_post_clone.sh → FLUTTER_BUILD_NUMBER=${build_number}"
  fi

  echo "📝 Synced iOS Xcode → MARKETING_VERSION=${app_version}, CURRENT_PROJECT_VERSION=${build_number}"
}

sync_pubspec_version() {
  local app_version="${1:-${APP_VERSION:-}}"
  local build_number="${2:-${BUILD_NUMBER:-}}"
  local root="${REPO_ROOT:-}"

  if [ -z "$app_version" ]; then
    echo "sync_pubspec_version: APP_VERSION not set" >&2
    return 1
  fi
  if [ -z "$root" ]; then
    echo "sync_pubspec_version: REPO_ROOT not set" >&2
    return 1
  fi

  local pubspec="$root/flutter_base_05/pubspec.yaml"
  if [ ! -f "$pubspec" ]; then
    echo "sync_pubspec_version: missing $pubspec" >&2
    return 1
  fi

  if [ -z "$build_number" ]; then
    build_number="$(compute_build_number_from_version "$app_version")"
  fi

  local new_line="version: ${app_version}+${build_number}"
  if grep -q '^version:' "$pubspec" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^version:.*/${new_line}/" "$pubspec"
    else
      sed -i "s/^version:.*/${new_line}/" "$pubspec"
    fi
  else
    echo "$new_line" >> "$pubspec"
  fi

  echo "📝 Synced pubspec.yaml → ${app_version}+${build_number}"
  export BUILD_NUMBER="$build_number"

  sync_ios_xcode_version "$app_version" "$build_number"
}
