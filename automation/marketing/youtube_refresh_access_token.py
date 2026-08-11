#!/usr/bin/env python3
# dash YouTube: refresh access token from refresh token
"""Mint a short-lived YouTube access token from YOUTUBE_REFRESH_TOKEN.

Does not store the access token in env (expires ~1h). Smoke-tests the channel.
If Google returns a rotated refresh_token, optionally --write-env.

Usage:
  wfrun → automation/marketing/youtube_refresh_access_token.py
  # If Google rotates refresh_token, prompts to write it (default Yes)
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

TOKEN_URI = "https://oauth2.googleapis.com/token"
CHANNELS_URI = "https://www.googleapis.com/youtube/v3/channels"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — expects WFRUN_ROOT and WFRUN_MODE "
            "(YOUTUBE_* from .env.local / .env.prod).",
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


def _post_form(url: str, fields: dict[str, str]) -> dict:
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(
            f"❌ Token refresh HTTP {exc.code}: {body}\n"
            "   If invalid_grant: re-run youtube_oauth_get_refresh_token.py "
            "(Brand Account consent)."
        ) from exc


def _get_json(url: str, access_token: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {access_token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"❌ YouTube API HTTP {exc.code}: {body}") from exc


def _smoke_channel(access_token: str, channel_id: str) -> None:
    if channel_id:
        params = {"part": "snippet", "id": channel_id}
    else:
        params = {"part": "snippet", "mine": "true"}
    url = f"{CHANNELS_URI}?{urllib.parse.urlencode(params)}"
    payload = _get_json(url, access_token)
    items = payload.get("items") or []
    if not items:
        raise SystemExit(
            "❌ Access token works but no channel returned. "
            "Re-auth as Brand Account (youtube_oauth_get_refresh_token.py)."
        )
    snippet = items[0].get("snippet") or {}
    title = snippet.get("title") or "(no title)"
    cid = items[0].get("id") or "(no id)"
    print(f"✅ Channel OK: {title} ({cid})")


def main() -> int:
    from publish_common import add_write_env_flags, resolve_write_env

    parser = argparse.ArgumentParser(
        description="Refresh YouTube access token from stored refresh token.",
    )
    add_write_env_flags(parser)
    parser.add_argument(
        "--print-access-token",
        action="store_true",
        help="Print access_token once (sensitive — avoid in shared logs).",
    )
    args = parser.parse_args()
    _require_wfrun()

    client_id = _env("YOUTUBE_CLIENT_ID")
    client_secret = _env("YOUTUBE_CLIENT_SECRET")
    refresh_token = _env("YOUTUBE_REFRESH_TOKEN")
    channel_id = _env("YOUTUBE_CHANNEL_ID")
    if not client_id or not client_secret or not refresh_token:
        print(
            "❌ Need YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN.",
            file=sys.stderr,
        )
        return 1

    payload = _post_form(
        TOKEN_URI,
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
    )
    access = (payload.get("access_token") or "").strip()
    expires_in = payload.get("expires_in")
    new_refresh = (payload.get("refresh_token") or "").strip()
    if not access:
        raise SystemExit(f"❌ No access_token in response: {payload!r}")

    print(f"✅ Access token refreshed (len={len(access)}, expires_in={expires_in}s)")
    if args.print_access_token:
        print(f"YOUTUBE_ACCESS_TOKEN={access}")

    if new_refresh and new_refresh != refresh_token:
        print("Google returned a new refresh_token.")
        write_env = resolve_write_env(
            "rotated YOUTUBE_REFRESH_TOKEN",
            write_flag=args.write_env,
            no_write_flag=args.no_write_env,
        )
        if write_env:
            env_file = _env("WFRUN_ENV_FILE")
            if not env_file:
                print("❌ WFRUN_ENV_FILE not set — cannot write env.", file=sys.stderr)
                return 1
            _upsert_env_key(Path(env_file), "YOUTUBE_REFRESH_TOKEN", new_refresh)
            print(f"Wrote rotated YOUTUBE_REFRESH_TOKEN → {env_file}")
        else:
            print("Skipped writing rotated refresh token.")

    _smoke_channel(access, channel_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
