#!/usr/bin/env python3
# dash AdMob OAuth: get refresh token (browser once)
"""One-time Desktop OAuth for AdMob API reporting.

Opens the system browser, exchanges the auth code for tokens, prints the
refresh token (and optionally writes ADMOB_REFRESH_TOKEN into the env file).
Then smoke-tests accounts.list.

Requires ADMOB_CLIENT_ID and ADMOB_CLIENT_SECRET (Desktop OAuth client) with
AdMob API enabled. Scope: admob.report.

Usage:
  wfrun → automation/revenue/admob_oauth_get_refresh_token.py
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.server
import json
import os
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

SCOPES = "https://www.googleapis.com/auth/admob.report"
AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URI = "https://oauth2.googleapis.com/token"
ACCOUNTS_URI = "https://admob.googleapis.com/v1/accounts"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — this script expects WFRUN_ROOT and WFRUN_MODE "
            "(so ADMOB_* come from .env.local / .env.prod).",
            file=sys.stderr,
        )
        sys.exit(1)
    return Path(root)


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _pkce_pair() -> tuple[str, str]:
    verifier = _b64url(secrets.token_bytes(32))
    challenge = _b64url(hashlib.sha256(verifier.encode("ascii")).digest())
    return verifier, challenge


def _upsert_env_key(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    lines = text.splitlines(keepends=True)
    prefix = f"{key}="
    replaced = False
    out: list[str] = []
    for line in lines:
        if line.startswith(prefix) or line.startswith(f"# {prefix}"):
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
        raise SystemExit(f"❌ Token endpoint HTTP {exc.code}: {body}") from exc


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
        raise SystemExit(f"❌ AdMob API HTTP {exc.code}: {body}") from exc


class _OAuthHandler(http.server.BaseHTTPRequestHandler):
    code: str | None = None
    error: str | None = None

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        if qs.get("error"):
            _OAuthHandler.error = qs["error"][0]
        elif qs.get("code"):
            _OAuthHandler.code = qs["code"][0]
        body = (
            b"<html><body><h1>AdMob auth complete</h1>"
            b"<p>You can close this tab and return to the terminal.</p>"
            b"</body></html>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run_browser_flow(client_id: str) -> tuple[str, str, str]:
    _OAuthHandler.code = None
    _OAuthHandler.error = None
    verifier, challenge = _pkce_pair()
    server = http.server.HTTPServer(("127.0.0.1", 0), _OAuthHandler)
    port = server.server_address[1]
    redirect_uri = f"http://127.0.0.1:{port}/"

    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": SCOPES,
        "access_type": "offline",
        "prompt": "consent",
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    auth_url = f"{AUTH_URI}?{urllib.parse.urlencode(params)}"

    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()

    print("Opening browser for Google / AdMob consent…")
    print(f"If it does not open, visit:\n{auth_url}\n")
    webbrowser.open(auth_url)

    thread.join(timeout=300)
    server.server_close()

    if _OAuthHandler.error:
        raise SystemExit(f"❌ OAuth error: {_OAuthHandler.error}")
    if not _OAuthHandler.code:
        raise SystemExit("❌ No authorization code received (timed out?).")
    return _OAuthHandler.code, verifier, redirect_uri


def _smoke_accounts(access_token: str) -> None:
    payload = _get_json(ACCOUNTS_URI, access_token)
    accounts = payload.get("account") or payload.get("accounts") or []
    if not accounts:
        print("⚠️  No AdMob accounts returned — check API enablement / consent.")
        return
    print("AdMob accounts:")
    for acc in accounts:
        if not isinstance(acc, dict):
            continue
        name = acc.get("name") or ""
        pub = acc.get("publisherId") or name
        currency = acc.get("currencyCode") or ""
        print(f"  {pub}  currency={currency}")
        if pub and not _env("ADMOB_PUBLISHER_ID"):
            print(f"  Hint: set ADMOB_PUBLISHER_ID={pub.replace('accounts/', '')}")


def main() -> None:
    parser = argparse.ArgumentParser(description="AdMob OAuth → refresh token")
    parser.add_argument(
        "--write-env",
        action="store_true",
        help="Write ADMOB_REFRESH_TOKEN to WFRUN_ENV_FILE without prompting",
    )
    parser.add_argument(
        "--no-write-env",
        action="store_true",
        help="Do not write env file",
    )
    args = parser.parse_args()
    _require_wfrun()

    client_id = _env("ADMOB_CLIENT_ID")
    client_secret = _env("ADMOB_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise SystemExit("❌ Set ADMOB_CLIENT_ID and ADMOB_CLIENT_SECRET first.")

    code, verifier, redirect_uri = _run_browser_flow(client_id)
    tokens = _post_form(
        TOKEN_URI,
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
        },
    )
    refresh = str(tokens.get("refresh_token") or "").strip()
    access = str(tokens.get("access_token") or "").strip()
    if not access:
        raise SystemExit(f"❌ No access_token in response: {tokens}")
    if not refresh:
        print(
            "⚠️  No refresh_token returned (Google often omits it if the app was "
            "already authorized). Revoke access at "
            "https://myaccount.google.com/permissions and re-run with prompt=consent."
        )
    else:
        print("Refresh token acquired.")
        print(f"  ADMOB_REFRESH_TOKEN={refresh[:8]}…{refresh[-4:]}")

    if refresh and not args.no_write_env:
        env_file = os.environ.get("WFRUN_ENV_FILE", "").strip()
        write = args.write_env
        if not write and env_file:
            ans = input(f"Write ADMOB_REFRESH_TOKEN to {env_file}? [Y/n] ").strip()
            write = ans == "" or ans.lower().startswith("y")
        if write and env_file:
            _upsert_env_key(Path(env_file), "ADMOB_REFRESH_TOKEN", refresh)
            print(f"Wrote ADMOB_REFRESH_TOKEN → {env_file}")
        elif write and not env_file:
            print("⚠️  WFRUN_ENV_FILE unset — not writing.")

    _smoke_accounts(access)
    print("Done.")


if __name__ == "__main__":
    main()
