#!/usr/bin/env python3
"""Write a JSON file for `flutter run|build --dart-define-from-file=FILE`.

Input is typically repo-root `.env.dart.defines.local` (dev) or `.env.dart.defines.prod`
(release). Parses KEY=value lines like playbooks/frontend/dart_defines_from_env.sh (comments,
optional single/double quotes on values). Avoids shell ARG_MAX when .env has many keys.

For `.env.dart.defines.local` (or BUILD_MODE=debug), **APP_VERSION** is taken from
`flutter_base_05/pubspec.yaml` so dart-defines match the installed PackageInfo version used
by global-broadcast update modals (`target_version` gate).

Platform-specific AdMob test ids (iOS vs Android demo units):
  export DART_DEFINES_PLATFORM=ios|android
  Optional in env file: ADMOB_IOS_USE_TEST_IDS=1|0 (prod iOS builds; default 1 when unset)
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from admob_test_ids import ANDROID_ADMOB_TEST, IOS_ADMOB_TEST

_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
_VERSION_LINE = re.compile(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$")


def _falsy(val: str | None) -> bool:
    return (val or "").strip().lower() in ("0", "false", "no", "off")


def _apply_admob_platform_test_ids(obj: dict[str, str], env_path: Path) -> None:
    platform = (os.environ.get("DART_DEFINES_PLATFORM") or obj.get("DART_DEFINES_PLATFORM") or "").strip().lower()
    if platform not in ("ios", "android"):
        return

    use_test = True
    if env_path.name == ".env.dart.defines.prod":
        if platform == "ios":
            raw = obj.get("ADMOB_IOS_USE_TEST_IDS")
            if raw is not None and _falsy(raw):
                use_test = False
        else:
            raw = obj.get("ADMOB_ANDROID_USE_TEST_IDS")
            if raw is not None and _falsy(raw):
                use_test = False
    # Local dev: always use Google demo units for the target platform.

    if not use_test:
        return

    mapping = IOS_ADMOB_TEST if platform == "ios" else ANDROID_ADMOB_TEST
    for key, value in mapping.items():
        obj[key] = value
    print(
        f"note: AdMob test ids applied for {platform} "
        f"({env_path.name}; iOS app id is also set in ios/Flutter/*.xcconfig)",
        file=sys.stderr,
    )


def parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    text = path.read_text(encoding="utf-8")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = _LINE.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        out[key] = val
    return out


def read_pubspec_version(repo_root: Path) -> tuple[str, str] | None:
    pubspec = repo_root / "flutter_base_05" / "pubspec.yaml"
    if not pubspec.is_file():
        return None
    for raw in pubspec.read_text(encoding="utf-8").splitlines():
        m = _VERSION_LINE.match(raw.strip())
        if m:
            name = m.group(1)
            build = m.group(2) or "1"
            return name, build
    return None


def _should_sync_app_version_from_pubspec(env_path: Path, obj: dict[str, str]) -> bool:
    if env_path.name == ".env.dart.defines.local":
        return True
    return (obj.get("BUILD_MODE") or "").strip().lower() == "debug"


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: env_for_flutter_dart_defines.py <input.env> <output.json>", file=sys.stderr)
        sys.exit(2)
    inp, outp = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    if not inp.is_file():
        print(f"error: env file not found: {inp}", file=sys.stderr)
        sys.exit(1)
    obj = parse_env(inp)
    repo_root = inp.parent

    _apply_admob_platform_test_ids(obj, inp)

    if _should_sync_app_version_from_pubspec(inp, obj):
        parsed = read_pubspec_version(repo_root)
        if parsed:
            pubspec_name, pubspec_build = parsed
            file_ver = (obj.get("APP_VERSION") or "").strip()
            obj["APP_VERSION"] = pubspec_name
            obj["PUBSPEC_BUILD_NUMBER"] = pubspec_build
            if file_ver and file_ver != pubspec_name:
                print(
                    f"note: {inp.name} APP_VERSION={file_ver} → pubspec {pubspec_name} "
                    f"(local dev SSOT; flutter run uses pubspec for PackageInfo)",
                    file=sys.stderr,
                )
        else:
            print("warning: could not read version from flutter_base_05/pubspec.yaml", file=sys.stderr)

    outp.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    main()
