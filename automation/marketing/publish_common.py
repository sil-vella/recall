#!/usr/bin/env python3
"""Shared helpers for Marketing publish runners (FB / YT / TT)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

import argparse


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    env_file = os.environ.get("WFRUN_ENV_FILE", "").strip()
    if not env_file:
        return ""
    path = Path(env_file)
    if not path.is_file():
        return ""
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            if key.strip() != name:
                continue
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            return val.strip()
    except OSError:
        return ""
    return ""


def require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        raise RuntimeError(
            "Run via wfrun — expects WFRUN_ROOT and WFRUN_MODE "
            "(platform credentials from .env.local / .env.prod)."
        )
    return Path(root)


def prompt_yes_no(message: str, *, default_yes: bool = True) -> bool:
    """Interactive Y/n (or y/N). EOF → no."""
    suffix = " [Y/n] " if default_yes else " [y/N] "
    try:
        answer = input(f"{message}{suffix}").strip().lower()
    except EOFError:
        return False
    if answer == "":
        return default_yes
    return answer in {"y", "yes"}


def resolve_write_env(
    key_label: str,
    *,
    write_flag: bool = False,
    no_write_flag: bool = False,
    default_yes: bool = True,
) -> bool:
    """Honor --write-env / --no-write-env, else prompt (wfrun has no script-arg UI)."""
    if write_flag:
        return True
    if no_write_flag:
        return False
    env_file = env("WFRUN_ENV_FILE") or "(WFRUN_ENV_FILE unset)"
    return prompt_yes_no(
        f"Write {key_label} to {env_file}?",
        default_yes=default_yes,
    )


def add_write_env_flags(parser: argparse.ArgumentParser) -> None:
    """Add mutually exclusive --write-env / --no-write-env to an ArgumentParser."""
    write_group = parser.add_mutually_exclusive_group()
    write_group.add_argument(
        "--write-env",
        action="store_true",
        help="Write token(s) into WFRUN_ENV_FILE (skip prompt).",
    )
    write_group.add_argument(
        "--no-write-env",
        action="store_true",
        help="Do not write env (skip prompt).",
    )


def merge_caption(title: str, description: str) -> str:
    """Facebook / TikTok single field: title, then description, newline-separated."""
    t = (title or "").strip()
    d = (description or "").strip()
    if t and d:
        return f"{t}\n{d}"
    return t or d


def append_hashtags(caption: str, hashtags: list[str] | None) -> str:
    tags = []
    for raw in hashtags or []:
        h = str(raw).strip()
        if not h:
            continue
        if not h.startswith("#"):
            h = f"#{h}"
        tags.append(h)
    if not tags:
        return caption
    tag_line = " ".join(tags)
    base = (caption or "").rstrip()
    if not base:
        return tag_line
    return f"{base}\n\n{tag_line}"


def local_datetime_to_unix(value: str) -> int:
    dt = datetime.fromisoformat(value.strip())
    return int(dt.timestamp())


def local_datetime_to_rfc3339(value: str) -> str:
    dt = datetime.fromisoformat(value.strip())
    if dt.tzinfo is None:
        dt = dt.astimezone()
    return dt.isoformat()


def ok_result(data: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"ok": True, "data": data or {}}


def err_result(code: str, message: str) -> dict[str, Any]:
    return {"ok": False, "error": {"code": code, "message": message}}


def http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
    form: dict[str, str] | None = None,
    timeout: int = 120,
) -> tuple[int, dict[str, Any], dict[str, str]]:
    hdrs = dict(headers or {})
    data = body
    if form is not None:
        data = urllib.parse.urlencode(form).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/x-www-form-urlencoded")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            payload = json.loads(raw) if raw else {}
            resp_headers = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, payload if isinstance(payload, dict) else {}, resp_headers
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"error": {"code": "http_error", "message": raw}}
        if not isinstance(payload, dict):
            payload = {"error": {"code": "http_error", "message": raw}}
        resp_headers = {k.lower(): v for k, v in exc.headers.items()} if exc.headers else {}
        return exc.code, payload, resp_headers
