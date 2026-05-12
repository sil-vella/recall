#!/usr/bin/env python3
"""Write a JSON file for `flutter run|build --dart-define-from-file=FILE`.

Parses KEY=value lines like playbooks/frontend/dart_defines_from_env.sh (comments,
optional single/double quotes on values). Avoids shell ARG_MAX when .env has many keys.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


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


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: env_for_flutter_dart_defines.py <input.env> <output.json>", file=sys.stderr)
        sys.exit(2)
    inp, outp = Path(sys.argv[1]), Path(sys.argv[2])
    if not inp.is_file():
        print(f"error: env file not found: {inp}", file=sys.stderr)
        sys.exit(1)
    obj = parse_env(inp)
    outp.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    main()
