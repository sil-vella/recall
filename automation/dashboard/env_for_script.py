# dash Build child env per wfrun script profile
"""Build per-script child environment mirroring wfrun profile rules."""

from __future__ import annotations

import os
import re
from pathlib import Path

from script_discovery import ScriptEntry

_ENV_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        inner = value[1:-1]
        if value[0] == '"':
            inner = inner.replace('\\"', '"')
        return inner
    return value


def parse_dotenv(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}

    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].lstrip()
        match = _ENV_KEY_RE.match(line)
        if not match:
            continue
        key, val = match.group(1), _unquote(match.group(2))
        out[key] = val
    return out


def dart_defines_file_for_mode(root: Path, mode: str) -> Path:
    if mode == "prod":
        return root / ".env.dart.defines.prod"
    return root / ".env.dart.defines.local"


def env_for_script(entry: ScriptEntry, base_env: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(base_env or os.environ)
    root = Path(env.get("WFRUN_ROOT", "")).resolve()

    env["WFRUN_PROFILE"] = entry.profile
    if entry.profile == "frontend":
        defines_file = env.get("WFRUN_DART_DEFINES_FILE", "").strip()
        if not defines_file:
            defines_file = str(dart_defines_file_for_mode(root, env.get("WFRUN_MODE", "local")))
        env["WFRUN_DART_DEFINES_FILE"] = defines_file
        env.update(parse_dotenv(Path(defines_file)))

    return env


def cwd_for_script(base_env: dict[str, str] | None = None) -> str:
    env = base_env or os.environ
    caller = env.get("WFRUN_CALLER_DIR", "").strip()
    root = env.get("WFRUN_ROOT", "").strip()
    return caller or root or os.getcwd()
