#!/usr/bin/env python3
# dash Facebook: validate / extend Page access token
"""Validate FACEBOOK_PAGE_ACCESS_TOKEN (debug_token + Page smoke).

Optional --extend: exchange via grant_type=fb_exchange_token, then resolve a
Page token for FACEBOOK_PAGE_ID and optionally --write-env.

Never prints full tokens unless --print-token.

Usage:
  wfrun → automation/marketing/facebook_validate_page_token.py
  # Prompts: extend/renew? then write FACEBOOK_PAGE_ACCESS_TOKEN? (if new)
  # Or non-interactive: … --extend --write-env
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

GRAPH = "https://graph.facebook.com/v21.0"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — expects WFRUN_ROOT and WFRUN_MODE "
            "(FACEBOOK_* from .env.local / .env.prod).",
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


def _get_json(url: str) -> dict:
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"❌ Graph HTTP {exc.code}: {body}") from exc


def _app_access_token(app_id: str, app_secret: str) -> str:
    return f"{app_id}|{app_secret}"


def _debug_token(input_token: str, app_token: str) -> dict:
    qs = urllib.parse.urlencode(
        {"input_token": input_token, "access_token": app_token}
    )
    payload = _get_json(f"{GRAPH}/debug_token?{qs}")
    data = payload.get("data") or {}
    if not data:
        raise SystemExit(f"❌ debug_token empty: {payload!r}")
    return data


def _fmt_expiry(data: dict) -> str:
    expires_at = data.get("expires_at")
    data_access = data.get("data_access_expires_at")
    parts: list[str] = []
    if expires_at == 0:
        parts.append("expires_at=never(0)")
    elif expires_at:
        parts.append(
            f"expires_at={expires_at} ({time.strftime('%Y-%m-%d', time.gmtime(int(expires_at)))} UTC)"
        )
    else:
        parts.append("expires_at=?")
    if data_access:
        parts.append(
            f"data_access_expires_at={data_access} "
            f"({time.strftime('%Y-%m-%d', time.gmtime(int(data_access)))} UTC)"
        )
    return ", ".join(parts)


def _print_debug(label: str, data: dict) -> None:
    scopes = data.get("scopes") or data.get("granular_scopes") or []
    if isinstance(scopes, list) and scopes and isinstance(scopes[0], dict):
        scopes = [s.get("scope") for s in scopes if isinstance(s, dict)]
    print(f"{label}:")
    print(f"  valid:      {data.get('is_valid')}")
    print(f"  type:       {data.get('type')}")
    print(f"  app_id:     {data.get('app_id')}")
    print(f"  profile_id: {data.get('profile_id') or data.get('user_id')}")
    print(f"  expiry:     {_fmt_expiry(data)}")
    if scopes:
        print(f"  scopes:     {', '.join(str(s) for s in scopes)}")
    err = data.get("error")
    if err:
        print(f"  error:      {err}")


def _smoke_page(page_id: str, page_token: str) -> None:
    qs = urllib.parse.urlencode(
        {"fields": "id,name", "access_token": page_token}
    )
    payload = _get_json(f"{GRAPH}/{page_id}?{qs}")
    if payload.get("error"):
        raise SystemExit(
            f"❌ Page smoke failed — re-auth required. Graph error: {payload['error']!r}"
        )
    name = payload.get("name") or "?"
    pid = payload.get("id") or "?"
    print(f"✅ Page OK: {name} ({pid})")


def _exchange_token(app_id: str, app_secret: str, token: str) -> str:
    qs = urllib.parse.urlencode(
        {
            "grant_type": "fb_exchange_token",
            "client_id": app_id,
            "client_secret": app_secret,
            "fb_exchange_token": token,
        }
    )
    payload = _get_json(f"{GRAPH}/oauth/access_token?{qs}")
    if payload.get("error"):
        raise SystemExit(f"❌ fb_exchange_token failed: {payload['error']!r}")
    new_token = (payload.get("access_token") or "").strip()
    if not new_token:
        raise SystemExit(f"❌ No access_token from exchange: {payload!r}")
    expires_in = payload.get("expires_in")
    print(f"✅ Exchange OK (len={len(new_token)}, expires_in={expires_in})")
    return new_token


def _page_token_from_user(page_id: str, user_or_page_token: str) -> str | None:
    """If token is User-type, fetch Page access_token; if already Page, return it."""
    qs = urllib.parse.urlencode(
        {"fields": "id,name,access_token", "access_token": user_or_page_token}
    )
    payload = _get_json(f"{GRAPH}/{page_id}?{qs}")
    if payload.get("error"):
        return None
    page_tok = (payload.get("access_token") or "").strip()
    return page_tok or None


def main() -> int:
    from publish_common import (
        add_write_env_flags,
        prompt_yes_no,
        resolve_write_env,
    )

    parser = argparse.ArgumentParser(
        description="Validate / optionally extend Facebook Page access token.",
    )
    extend_group = parser.add_mutually_exclusive_group()
    extend_group.add_argument(
        "--extend",
        action="store_true",
        help="Run fb_exchange_token (skip prompt).",
    )
    extend_group.add_argument(
        "--no-extend",
        action="store_true",
        help="Validate only (skip prompt).",
    )
    add_write_env_flags(parser)
    parser.add_argument(
        "--print-token",
        action="store_true",
        help="Print the (new) Page token once (sensitive).",
    )
    args = parser.parse_args()
    _require_wfrun()

    app_id = _env("FACEBOOK_APP_ID")
    app_secret = _env("FACEBOOK_APP_SECRET")
    page_id = _env("FACEBOOK_PAGE_ID")
    page_token = _env("FACEBOOK_PAGE_ACCESS_TOKEN")
    # Optional: short-lived or long-lived User token to exchange first
    user_token = _env("FACEBOOK_USER_ACCESS_TOKEN")

    if not app_id or not app_secret:
        print("❌ Need FACEBOOK_APP_ID and FACEBOOK_APP_SECRET.", file=sys.stderr)
        return 1
    if not page_id:
        print("❌ Need FACEBOOK_PAGE_ID.", file=sys.stderr)
        return 1

    do_extend = args.extend
    if not args.extend and not args.no_extend:
        do_extend = prompt_yes_no(
            "Extend / renew Page token via fb_exchange_token?",
            default_yes=False,
        )

    if not page_token and not (do_extend and user_token):
        print(
            "❌ Need FACEBOOK_PAGE_ACCESS_TOKEN "
            "(or FACEBOOK_USER_ACCESS_TOKEN with extend).",
            file=sys.stderr,
        )
        return 1

    app_token = _app_access_token(app_id, app_secret)

    if page_token:
        print("——— current Page token ———")
        data = _debug_token(page_token, app_token)
        _print_debug("debug_token", data)
        if not data.get("is_valid"):
            print(
                "❌ Token invalid — re-auth required "
                "(Graph Explorer → Page token → Extend → update .env.local)."
            )
            return 1
        tok_type = (data.get("type") or "").lower()
        if tok_type and tok_type != "page":
            print(
                f"⚠️  Token type is {data.get('type')!r}, expected Page. "
                "Publishing may fail until you use a Page token."
            )
        profile = str(data.get("profile_id") or data.get("user_id") or "")
        if profile and profile != page_id:
            print(
                f"⚠️  profile_id {profile} != FACEBOOK_PAGE_ID {page_id}"
            )
        _smoke_page(page_id, page_token)

    if not do_extend:
        print("Done (validate only).")
        return 0

    print("——— extend ———")
    source = user_token or page_token
    if user_token:
        print("Exchanging FACEBOOK_USER_ACCESS_TOKEN…")
    else:
        print("Exchanging FACEBOOK_PAGE_ACCESS_TOKEN…")

    exchanged = _exchange_token(app_id, app_secret, source)
    exchanged_debug = _debug_token(exchanged, app_token)
    _print_debug("exchanged", exchanged_debug)

    final_page = exchanged
    if (exchanged_debug.get("type") or "").lower() != "page":
        resolved = _page_token_from_user(page_id, exchanged)
        if not resolved:
            print(
                "⚠️  Exchange produced a non-Page token and could not resolve "
                f"Page {page_id} access_token. Keep using existing Page token, "
                "or mint via Explorer: GET /{{page-id}}?fields=access_token."
            )
            return 1
        final_page = resolved
        print("Resolved Page access_token from exchanged User token.")
        page_debug = _debug_token(final_page, app_token)
        _print_debug("page_token", page_debug)
        if not page_debug.get("is_valid"):
            print("❌ Resolved Page token is invalid.")
            return 1

    _smoke_page(page_id, final_page)

    if args.print_token:
        print(f"FACEBOOK_PAGE_ACCESS_TOKEN={final_page}")

    if final_page != page_token:
        write_env = resolve_write_env(
            "FACEBOOK_PAGE_ACCESS_TOKEN",
            write_flag=args.write_env,
            no_write_flag=args.no_write_env,
        )
        if write_env:
            env_file = _env("WFRUN_ENV_FILE")
            if not env_file:
                print("❌ WFRUN_ENV_FILE not set — cannot write env.", file=sys.stderr)
                return 1
            _upsert_env_key(Path(env_file), "FACEBOOK_PAGE_ACCESS_TOKEN", final_page)
            print(f"Wrote FACEBOOK_PAGE_ACCESS_TOKEN → {env_file}")
        else:
            print("Skipped writing env — paste the new Page token manually if needed.")
    else:
        print("Page token unchanged — env not rewritten.")

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
