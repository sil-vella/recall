#!/usr/bin/env python3
"""Shared helpers for 06/07 build scripts: versioned tags + .env.prod upsert."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent
ENV_PROD = PROJECT_ROOT / ".env.prod"


def upsert_env_prod_key(env_prod_path: Path, key: str, value: str) -> None:
    """
    Replace KEY=... in .env.prod or append a tagged section at EOF.
    Preserves all other lines (including comments and quoting style on other keys).
    """
    key = key.strip()
    value = value.strip()
    if not key or not value:
        raise ValueError("key and value must be non-empty")

    if env_prod_path.is_file():
        text = env_prod_path.read_text(encoding="utf-8")
    else:
        text = ""

    lines = text.splitlines(keepends=True)
    new_line = f"{key}={value}\n"
    key_pattern = re.compile(rf"^{re.escape(key)}\s*=")

    out: list[str] = []
    replaced = False
    for line in lines:
        body = line.rstrip("\n\r")
        if key_pattern.match(body):
            out.append(new_line)
            replaced = True
        else:
            out.append(line)

    if not replaced:
        if out and not out[-1].endswith("\n"):
            out.append("\n")
        if out and not out[-1].endswith("\n\n"):
            out.append("\n")
        out.append("# Docker image tags (updated by 06/07 build scripts)\n")
        out.append(new_line)

    env_prod_path.write_text("".join(out), encoding="utf-8")


def git_short_sha(project_root: Path | None = None) -> str:
    root = project_root or PROJECT_ROOT
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            cwd=str(root),
            check=False,
        )
        if result.returncode == 0:
            sha = (result.stdout or "").strip()
            if sha:
                return sha
    except OSError:
        pass
    return "unknown"


def resolve_versioned_image_tag(*, env: os._Environ[str] | None = None) -> str:
    """{APP_VERSION}-{git_sha} unless IMAGE_TAG is set explicitly."""
    en = env if env is not None else os.environ
    explicit = (en.get("IMAGE_TAG") or "").strip()
    if explicit:
        return explicit
    app_version = (en.get("APP_VERSION") or "2.0.0").strip() or "2.0.0"
    return f"{app_version}-{git_short_sha()}"


def record_image_tag_in_env_prod(key: str, tag: str) -> None:
    if not ENV_PROD.is_file():
        print(f"Warning: missing {ENV_PROD}; skipped {key} upsert", file=sys.stderr)
        return
    upsert_env_prod_key(ENV_PROD, key, tag)
