#!/usr/bin/env python3
# dash YouTube OAuth: get refresh token (browser once)
"""One-time Desktop OAuth for YouTube Data API v3.

Opens the system browser, exchanges the auth code for tokens, prints the
refresh token (and optionally writes YOUTUBE_REFRESH_TOKEN into the env file).
Then smoke-tests channels.list?mine=true.

Requires YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET (Desktop OAuth client).
Run via wfrun so .env.local / .env.prod is loaded.

Usage:
  wfrun → automation/marketing/youtube_oauth_get_refresh_token.py
  # After browser consent, prompts: write YOUTUBE_REFRESH_TOKEN to env? [Y/n]
  # Or non-interactive: … --write-env / --no-write-env

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

# upload + force-ssl (playlistItems.insert / fuller channel manage); openid/email = consent identity
SCOPES = (
    "https://www.googleapis.com/auth/youtube.upload "
    "https://www.googleapis.com/auth/youtube.force-ssl "
    "openid email"
)
AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URI = "https://oauth2.googleapis.com/token"
CHANNELS_URI = "https://www.googleapis.com/youtube/v3/channels"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — this script expects WFRUN_ROOT and WFRUN_MODE "
            "(so YOUTUBE_* come from .env.local / .env.prod).",
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
        raise SystemExit(f"❌ YouTube API HTTP {exc.code}: {body}") from exc


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
            b"<html><body><h1>YouTube auth complete</h1>"
            b"<p>You can close this tab and return to the terminal.</p>"
            b"</body></html>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run_browser_flow(client_id: str) -> tuple[str, str, str]:
    """Return (authorization_code, code_verifier, redirect_uri)."""
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

    print("Opening browser for Google consent…")
    print(f"If it does not open, visit:\n{auth_url}\n")
    webbrowser.open(auth_url)

    thread.join(timeout=300)
    server.server_close()

    if _OAuthHandler.error:
        raise SystemExit(f"❌ OAuth error: {_OAuthHandler.error}")
    if not _OAuthHandler.code:
        raise SystemExit("❌ No authorization code received (timed out?).")
    return _OAuthHandler.code, verifier, redirect_uri


TOKEN_INFO_URI = "https://oauth2.googleapis.com/tokeninfo"


def _token_info(access_token: str) -> dict:
    url = f"{TOKEN_INFO_URI}?{urllib.parse.urlencode({'access_token': access_token})}"
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"⚠️  tokeninfo HTTP {exc.code}: {body}")
        return {}


def _smoke_channel(access_token: str) -> None:
    info = _token_info(access_token)
    email = (info.get("email") or "").strip()
    sub = (info.get("sub") or "").strip()
    scope = (info.get("scope") or "").strip()
    if email or sub or scope:
        print("Auth identity:")
        if email:
            print(f"  email: {email}")
        if sub:
            print(f"  sub:   {sub}")
        if scope:
            print(f"  scope: {scope}")

    url = f"{CHANNELS_URI}?{urllib.parse.urlencode({'part': 'snippet', 'mine': 'true'})}"
    payload = _get_json(url, access_token)
    items = payload.get("items") or []
    if not items:
        print(
            "⚠️  Access token works, but channels.list?mine=true returned no channel.\n"
            "    That Google account has no YouTube channel (or you consented as the wrong account).\n"
            "    Fix:\n"
            "    1) In an incognito window, open https://www.youtube.com/account and sign in as the\n"
            "       channel owner — confirm a channel exists (YouTube Studio shows it).\n"
            "    2) Cloud Console → Audience → test users must include that same email.\n"
            "    3) Re-run this script; on the Google account picker choose that owner account\n"
            "       (not a different personal Gmail)."
        )
        return
    snippet = items[0].get("snippet") or {}
    title = snippet.get("title") or "(no title)"
    channel_id = items[0].get("id") or "(no id)"
    print(f"✅ Channel OK: {title} ({channel_id})")
    print(f"Optional env: YOUTUBE_CHANNEL_ID={channel_id}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Get a YouTube refresh token via Desktop OAuth (browser once).",
    )
    from publish_common import add_write_env_flags, resolve_write_env

    add_write_env_flags(parser)
    args = parser.parse_args()
    _require_wfrun()

    client_id = _env("YOUTUBE_CLIENT_ID")
    client_secret = _env("YOUTUBE_CLIENT_SECRET")
    if not client_id or not client_secret:
        print(
            "❌ Set YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET "
            "(Desktop OAuth client) in the wfrun env file.",
            file=sys.stderr,
        )
        return 1

    code, verifier, redirect_uri = _run_browser_flow(client_id)
    token_payload = _post_form(
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

    access_token = (token_payload.get("access_token") or "").strip()
    refresh_token = (token_payload.get("refresh_token") or "").strip()
    if not access_token:
        raise SystemExit(f"❌ No access_token in response: {token_payload!r}")
    if not refresh_token:
        raise SystemExit(
            "❌ No refresh_token returned. Re-run with a Desktop client, "
            "ensure access_type=offline / prompt=consent, and revoke prior "
            "app access at https://myaccount.google.com/permissions if needed."
        )

    print("\n——— save this (do not commit) ———")
    print(f"YOUTUBE_REFRESH_TOKEN={refresh_token}")
    print("———————————————————————————————\n")

    write_env = resolve_write_env(
        "YOUTUBE_REFRESH_TOKEN",
        write_flag=args.write_env,
        no_write_flag=args.no_write_env,
    )
    if write_env:
        env_file = _env("WFRUN_ENV_FILE")
        if not env_file:
            print("❌ WFRUN_ENV_FILE not set — cannot write env.", file=sys.stderr)
            return 1
        path = Path(env_file)
        _upsert_env_key(path, "YOUTUBE_REFRESH_TOKEN", refresh_token)
        print(f"Wrote YOUTUBE_REFRESH_TOKEN → {path}")
    else:
        print("Skipped writing env — paste the token into .env.local manually if needed.")

    _smoke_channel(access_token)
    print("Done. Access tokens expire ~1h; scripts should refresh via the refresh token.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
