#!/usr/bin/env bash
# Shared release prep for IPA, AAB, and Xcode Cloud iOS builds.
# Source after REPO_ROOT and SCRIPT_DIR (playbooks/frontend) are set.
#
#   source "$SCRIPT_DIR/flutter_release_build_common.sh"
#   flutter_release_init_paths
#   set_production_deck_config
#   disable_logging_switch_for_release
#   flutter_release_prepare_dart_defines "$REPO_ROOT/.env.dart.defines.prod"
#   flutter_release_validate_api_url "$DART_DEF_JSON"

_FLUTTER_RELEASE_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

flutter_release_init_paths() {
  local root="${REPO_ROOT:-}"
  if [ -z "$root" ]; then
    echo "flutter_release_init_paths: REPO_ROOT not set" >&2
    return 1
  fi
  DECK_CONFIG_PATH="$root/flutter_base_05/assets/deck_config.yaml"
  PREDEFINED_HANDS_PATH="$root/flutter_base_05/assets/predefined_hands.yaml"
  DECK_BACKUP_DIR="${DECK_BACKUP_DIR:-${TMPDIR:-/tmp}/dutch_build_deck_$$}"
  FLUTTER_DIR="$root/flutter_base_05"
}

restore_deck_config() {
  if [ -d "${DECK_BACKUP_DIR:-}" ]; then
    echo "" && echo "🃏 Restoring deck config files..."
    if [ -f "$DECK_BACKUP_DIR/deck_config.yaml" ]; then
      cp "$DECK_BACKUP_DIR/deck_config.yaml" "$DECK_CONFIG_PATH"
    fi
    if [ -f "$DECK_BACKUP_DIR/predefined_hands.yaml" ]; then
      cp "$DECK_BACKUP_DIR/predefined_hands.yaml" "$PREDEFINED_HANDS_PATH"
    fi
    rm -rf "$DECK_BACKUP_DIR"
    echo ""
  fi
}

set_production_deck_config() {
  flutter_release_init_paths || return 1
  echo ""
  echo "🃏 Setting production deck config..."
  mkdir -p "$DECK_BACKUP_DIR"
  if [ -f "$DECK_CONFIG_PATH" ]; then
    cp "$DECK_CONFIG_PATH" "$DECK_BACKUP_DIR/deck_config.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    else
      sed -i 's/\(testing_mode:[[:space:]]*\)true/\1false/' "$DECK_CONFIG_PATH"
    fi
  fi
  if [ -f "$PREDEFINED_HANDS_PATH" ]; then
    cp "$PREDEFINED_HANDS_PATH" "$DECK_BACKUP_DIR/predefined_hands.yaml"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    else
      sed -i 's/\(enabled:[[:space:]]*\)true/\1false/' "$PREDEFINED_HANDS_PATH"
    fi
  fi
  echo ""
}

disable_logging_switch_for_release() {
  flutter_release_init_paths || return 1
  echo "🔇 Disabling LOGGING_SWITCH in Flutter sources..."
  local logging_switch_variable_value="true"
  local replaced_files=0
  while IFS= read -r -d '' dart_file; do
    if grep -q "LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null || \
       grep -q "static const bool LOGGING_SWITCH = ${logging_switch_variable_value}" "$dart_file" 2>/dev/null; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
        sed -i '' "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
        sed -i '' "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
      else
        sed -i "s/LOGGING_SWITCH = ${logging_switch_variable_value}/LOGGING_SWITCH = false/g" "$dart_file"
        sed -i "s/const bool LOGGING_SWITCH = ${logging_switch_variable_value}/const bool LOGGING_SWITCH = false/g" "$dart_file"
        sed -i "s/static const bool LOGGING_SWITCH = ${logging_switch_variable_value}/static const bool LOGGING_SWITCH = false/g" "$dart_file"
      fi
      replaced_files=$((replaced_files + 1))
    fi
  done < <(find "$FLUTTER_DIR" -name "*.dart" -type f -print0)
  if [ "$replaced_files" -eq 0 ]; then
    echo "  ℹ️  No LOGGING_SWITCH = true found (already disabled or not present)."
  else
    echo "  ✅ Disabled LOGGING_SWITCH in $replaced_files file(s)"
  fi
  echo ""
}

flutter_release_prepare_dart_defines() {
  local env_file="${1:-}"
  if [ -z "$env_file" ]; then
    echo "flutter_release_prepare_dart_defines: env file path required" >&2
    return 1
  fi
  # shellcheck source=flutter_dart_defines_common.sh
  source "$_FLUTTER_RELEASE_COMMON_DIR/flutter_dart_defines_common.sh"
  flutter_dart_defines_require_python || return 1
  flutter_dart_defines_prepare "$env_file" || return 1
  export DART_DEF_JSON
}

flutter_release_validate_api_url() {
  local json_file="${1:-${DART_DEF_JSON:-}}"
  if [ -z "$json_file" ] || [ ! -f "$json_file" ]; then
    echo "❌ flutter_release_validate_api_url: dart-define JSON not found" >&2
    return 1
  fi
  python3 - "$json_file" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
api = (data.get("API_URL") or "").strip().lower()
if not api:
    print("❌ API_URL is missing from dart-defines — release build would use emulator defaults", file=sys.stderr)
    sys.exit(1)
bad = ("10.0.2.2", "localhost", "127.0.0.1")
for token in bad:
    if token in api:
        print(
            f"❌ API_URL={data.get('API_URL')!r} is not a production endpoint "
            f"(contains {token})",
            file=sys.stderr,
        )
        sys.exit(1)
print(f"✅ API_URL validated: {data.get('API_URL')}")
PY
}

flutter_release_assert_generated_dart_defines() {
  local generated_xcconfig="${1:-}"
  if [ -z "$generated_xcconfig" ] || [ ! -f "$generated_xcconfig" ]; then
    echo "❌ flutter_release_assert_generated_dart_defines: Generated.xcconfig not found" >&2
    return 1
  fi
  python3 - "$generated_xcconfig" <<'PY'
import base64
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r"^DART_DEFINES=(.*)$", text, re.M)
if not m or not m.group(1).strip():
    print("❌ Generated.xcconfig DART_DEFINES is empty", file=sys.stderr)
    sys.exit(1)
found_api = False
for part in m.group(1).split(","):
    part = part.strip()
    if not part:
        continue
    try:
        decoded = base64.b64decode(part).decode("utf-8")
    except Exception:
        continue
    if decoded.startswith("API_URL="):
        found_api = True
        print(f"✅ Generated.xcconfig includes {decoded.split('=', 1)[0]}")
        break
if not found_api:
    print("❌ Generated.xcconfig DART_DEFINES does not include API_URL", file=sys.stderr)
    sys.exit(1)
PY
}

read_pubspec_app_version() {
  local root="${REPO_ROOT:-}"
  local pubspec="$root/flutter_base_05/pubspec.yaml"
  if [ ! -f "$pubspec" ]; then
    echo "read_pubspec_app_version: pubspec not found: $pubspec" >&2
    return 1
  fi
  python3 - "$pubspec" <<'PY'
import re
import sys
from pathlib import Path

for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    m = re.match(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$", raw.strip())
    if m:
        print(m.group(1))
        break
else:
    raise SystemExit("version line not found in pubspec.yaml")
PY
}
