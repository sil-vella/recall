#!/usr/bin/env python3
# dash TikTok: refresh access token from refresh token
"""Mint a ~24h TikTok access token from TIKTOK_REFRESH_TOKEN.

Does not store access_token in env. Smoke-tests /v2/user/info/.
If TikTok rotates refresh_token, optionally --write-env.

Usage:
  wfrun → automation/marketing/tiktok_refresh_access_token.py
  # If TikTok rotates refresh_token, prompts to write it (default Yes)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

TOKEN_URI = "https://open.tiktokapis.com/v2/oauth/token/"
USER_INFO_URI = "https://open.tiktokapis.com/v2/user/info/"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — expects WFRUN_ROOT and WFRUN_MODE "
            "(TIKTOK_* from .env.local / .env.prod).",
            file=sys.stderr,
        )
        sys.exit(1)
    return Path(root)


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _upsert_env_key(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    lines = text.splitlines(keepends=True)
    prefix = f"{key}="
    replaced = False
    out: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        if (
            line.startswith(prefix)
            or stripped.startswith(f"# {prefix}")
            or stripped.startswith(f"#{prefix}")
        ):
            out.append(f"{key}={value}\n")
            replaced = True
        else:
            out.append(line if line.endswith("\n") else line + "\n")
    if not replaced:
        if out and not out[-1].endswith("\n"):
            out[-1] = out[-1] + "\n"
        if out and out[-1].strip():
            out.append("\n")
        out.append(f"{key}={value}\n")
    path.write_text("".join(out), encoding="utf-8")


def _post_form(fields: dict[str, str]) -> dict:
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(
        TOKEN_URI,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Cache-Control": "no-cache",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(
            f"❌ Token refresh HTTP {exc.code}: {body}\n"
            "   Re-run tiktok_oauth_get_refresh_token.py if refresh was revoked."
        ) from exc


def _smoke_user(access_token: str) -> None:
    fields = "open_id,display_name"
    url = f"{USER_INFO_URI}?{urllib.parse.urlencode({'fields': fields})}"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {access_token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"❌ user/info HTTP {exc.code}: {body}") from exc
    err = payload.get("error") or {}
    if err.get("code") and err.get("code") != "ok":
        raise SystemExit(f"❌ user/info error: {payload!r}")
    user = ((payload.get("data") or {}).get("user")) or {}
    print(
        f"✅ User OK: {user.get('display_name') or '?'} "
        f"(open_id={user.get('open_id') or '?'})"
    )


def main() -> int:
    from publish_common import add_write_env_flags, resolve_write_env

    parser = argparse.ArgumentParser(
        description="Refresh TikTok access token from stored refresh token.",
    )
    add_write_env_flags(parser)
    args = parser.parse_args()
    _require_wfrun()

    client_key = _env("TIKTOK_CLIENT_KEY")
    client_secret = _env("TIKTOK_CLIENT_SECRET")
    refresh_token = _env("TIKTOK_REFRESH_TOKEN")
    if not client_key or not client_secret or not refresh_token:
        print(
            "❌ Need TIKTOK_CLIENT_KEY, TIKTOK_CLIENT_SECRET, TIKTOK_REFRESH_TOKEN.",
            file=sys.stderr,
        )
        return 1

    payload = _post_form(
        {
            "client_key": client_key,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        }
    )
    if "data" in payload and isinstance(payload["data"], dict):
        payload = {**payload, **payload["data"]}

    access = (payload.get("access_token") or "").strip()
    expires_in = payload.get("expires_in")
    new_refresh = (payload.get("refresh_token") or "").strip()
    if payload.get("error") and not access:
        raise SystemExit(f"❌ Token error: {payload!r}")
    if not access:
        raise SystemExit(f"❌ No access_token: {payload!r}")

    print(f"✅ Access token refreshed (len={len(access)}, expires_in={expires_in}s)")

    if new_refresh and new_refresh != refresh_token:
        print("TikTok returned a new refresh_token.")
        write_env = resolve_write_env(
            "rotated TIKTOK_REFRESH_TOKEN",
            write_flag=args.write_env,
            no_write_flag=args.no_write_env,
        )
        if write_env:
            env_file = _env("WFRUN_ENV_FILE")
            if not env_file:
                print("❌ WFRUN_ENV_FILE not set — cannot write env.", file=sys.stderr)
                return 1
            _upsert_env_key(Path(env_file), "TIKTOK_REFRESH_TOKEN", new_refresh)
            print(f"Wrote rotated TIKTOK_REFRESH_TOKEN → {env_file}")
        else:
            print("Skipped writing rotated refresh token.")

    _smoke_user(access)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
