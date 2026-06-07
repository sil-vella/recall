#!/usr/bin/env bash
# Sync release version across Flutter + iOS/Xcode Cloud:
#   - flutter_base_05/pubspec.yaml `version:`
#   - Runner MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.pbxproj
#   - FLUTTER_BUILD_NUMBER pin in ios/ci_scripts/ci_post_clone.sh
#   - ios/xcode_cloud_build_number.txt (ASC / Xcode Cloud floor)
# BUILD_NUMBER uses major * 10000 + minor * 100 + patch unless the iOS floor is
# ahead (Xcode Cloud auto-increment); then resolve_release_version_and_build bumps
# APP_VERSION + BUILD_NUMBER to stay above the floor.
#
# Usage (after APP_VERSION / BUILD_NUMBER are set):
#   REPO_ROOT=... source "$SCRIPT_DIR/sync_pubspec_version.sh"
#   resolve_release_version_and_build "$APP_VERSION"
#   sync_pubspec_version "$APP_VERSION" "$BUILD_NUMBER"
# Or: sync_pubspec_version "2.0.32" 20032

XCODE_CLOUD_BUILD_NUMBER_FILE="flutter_base_05/ios/xcode_cloud_build_number.txt"

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

version_string_from_build_number() {
  local build_number="$1"
  if ! [[ "$build_number" =~ ^[0-9]+$ ]]; then
    echo "version_string_from_build_number: invalid build number: $build_number" >&2
    return 1
  fi
  local ma mi pa
  ma=$((build_number / 10000))
  mi=$(((build_number % 10000) / 100))
  pa=$((build_number % 100))
  echo "${ma}.${mi}.${pa}"
}

read_ios_runner_build_number() {
  local root="${REPO_ROOT:-}"
  local pbxproj="$root/flutter_base_05/ios/Runner.xcodeproj/project.pbxproj"
  if [ ! -f "$pbxproj" ]; then
    echo 0
    return 0
  fi
  python3 - "$pbxproj" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
block_re = re.compile(
    r"\t\t\w+ /\* \w+ \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};",
    re.DOTALL,
)
versions = []
for block in block_re.findall(text):
    if "INFOPLIST_FILE = Runner/Info.plist;" not in block:
        continue
    match = re.search(r"\t\t\t\tCURRENT_PROJECT_VERSION = (\d+);", block)
    if match:
        versions.append(int(match.group(1)))
print(max(versions) if versions else 0)
PY
}

read_xcode_cloud_build_floor() {
  local root="${REPO_ROOT:-}"
  local floor=0
  local floor_file="$root/${XCODE_CLOUD_BUILD_NUMBER_FILE}"
  if [ -f "$floor_file" ]; then
    floor=$(tr -d '[:space:]' < "$floor_file")
    if ! [[ "$floor" =~ ^[0-9]+$ ]]; then
      floor=0
    fi
  fi
  local pbx_floor
  pbx_floor=$(read_ios_runner_build_number)
  if [[ "$pbx_floor" =~ ^[0-9]+$ ]] && [ "$pbx_floor" -gt "$floor" ]; then
    floor=$pbx_floor
  fi
  echo "$floor"
}

write_xcode_cloud_build_floor() {
  local build_number="$1"
  local root="${REPO_ROOT:-}"
  if [ -z "$root" ] || ! [[ "$build_number" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  local floor_file="$root/${XCODE_CLOUD_BUILD_NUMBER_FILE}"
  mkdir -p "$(dirname "$floor_file")"
  printf '%s\n' "$build_number" > "$floor_file"
}

# Keep APP_VERSION + BUILD_NUMBER above ios/xcode_cloud_build_number.txt (ASC floor).
resolve_release_version_and_build() {
  local app_version="${1:-${APP_VERSION:-}}"
  if [ -z "$app_version" ]; then
    echo "resolve_release_version_and_build: APP_VERSION not set" >&2
    return 1
  fi

  local formula build_number floor
  formula=$(compute_build_number_from_version "$app_version")
  floor=$(read_xcode_cloud_build_floor)
  build_number=$formula

  if [ "$formula" -le "$floor" ]; then
    build_number=$((floor + 1))
    app_version=$(version_string_from_build_number "$build_number")
    echo "🍎 Xcode Cloud floor ${floor} — aligned release to APP_VERSION=${app_version} BUILD_NUMBER=${build_number}"
  fi

  export APP_VERSION="$app_version"
  export BUILD_NUMBER="$build_number"
}

write_app_version_to_env_files() {
  local app_version="$1"
  local env_file="${2:-${FRONTEND_ENV:-}}"
  local dart_file="${3:-${DART_DEFINES_ENV:-}}"

  if [ -z "$env_file" ]; then
    return 0
  fi

  if [ -f "$env_file" ] && grep -q '^APP_VERSION=' "$env_file" 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$app_version/" "$env_file"
    else
      sed -i "s/^APP_VERSION=.*/APP_VERSION=$app_version/" "$env_file"
    fi
  else
    echo "APP_VERSION=$app_version" >> "$env_file"
  fi

  if [ -n "$dart_file" ] && [ -f "$dart_file" ]; then
    if grep -q '^APP_VERSION=' "$dart_file" 2>/dev/null; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^APP_VERSION=.*/APP_VERSION=$app_version/" "$dart_file"
      else
        sed -i "s/^APP_VERSION=.*/APP_VERSION=$app_version/" "$dart_file"
      fi
    else
      echo "APP_VERSION=$app_version" >> "$dart_file"
    fi
  fi
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

  write_xcode_cloud_build_floor "$build_number"
  echo "📝 Synced iOS Xcode → MARKETING_VERSION=${app_version}, CURRENT_PROJECT_VERSION=${build_number}"
  echo "📝 Synced xcode_cloud_build_number.txt → ${build_number}"
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
