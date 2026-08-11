#!/usr/bin/env python3
# dash TikTok OAuth: get refresh token (browser once)
"""One-time Desktop Login Kit OAuth for TikTok (Sandbox or Production).

Opens the system browser, exchanges the auth code for tokens, prints refresh
token + open_id (and optionally writes them into the env file). Then smoke-tests
GET /v2/user/info/.

Requires TIKTOK_CLIENT_KEY and TIKTOK_CLIENT_SECRET.
Redirect URI must exactly match Login Kit config (default below).
TikTok Desktop PKCE uses hex(SHA256(verifier)), not Google-style base64url.

Usage:
  wfrun → automation/marketing/tiktok_oauth_get_refresh_token.py
  # After browser consent, prompts to write TIKTOK_* into env (default Yes)
  # Or non-interactive: … --write-env / --no-write-env
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import secrets
import string
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

# Comma-separated per TikTok Login Kit docs
DEFAULT_SCOPES = "user.info.basic,video.publish"
DEFAULT_REDIRECT_URI = "http://127.0.0.1:8765/callback/"
AUTH_URI = "https://www.tiktok.com/v2/auth/authorize/"
TOKEN_URI = "https://open.tiktokapis.com/v2/oauth/token/"
USER_INFO_URI = "https://open.tiktokapis.com/v2/user/info/"


def _require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    if not root or not mode:
        print(
            "❌ Run via wfrun — this script expects WFRUN_ROOT and WFRUN_MODE "
            "(so TIKTOK_* come from .env.local / .env.prod).",
            file=sys.stderr,
        )
        sys.exit(1)
    return Path(root)


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _pkce_pair() -> tuple[str, str]:
    alphabet = string.ascii_letters + string.digits + "-._~"
    verifier = "".join(secrets.choice(alphabet) for _ in range(64))
    # TikTok Desktop: hex encoding of SHA256(code_verifier), method S256
    challenge = hashlib.sha256(verifier.encode("ascii")).hexdigest()
    return verifier, challenge


def _upsert_env_key(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    lines = text.splitlines(keepends=True)
    prefix = f"{key}="
    replaced = False
    out: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        if line.startswith(prefix) or stripped.startswith(f"# {prefix}") or stripped.startswith(
            f"#{prefix}"
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
        raise SystemExit(f"❌ Token endpoint HTTP {exc.code}: {body}") from exc


class _OAuthHandler(http.server.BaseHTTPRequestHandler):
    code: str | None = None
    error: str | None = None
    error_description: str | None = None
    state_expected: str = ""
    state_got: str | None = None

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        _OAuthHandler.state_got = (qs.get("state") or [None])[0]
        if qs.get("error"):
            _OAuthHandler.error = qs["error"][0]
            _OAuthHandler.error_description = (qs.get("error_description") or [""])[0]
        elif qs.get("code"):
            # TikTok may URL-encode the code
            _OAuthHandler.code = urllib.parse.unquote(qs["code"][0])
        body = (
            b"<html><body><h1>TikTok auth complete</h1>"
            b"<p>You can close this tab and return to the terminal.</p>"
            b"</body></html>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run_browser_flow(
    client_key: str,
    redirect_uri: str,
    scopes: str,
) -> tuple[str, str]:
    """Return (authorization_code, code_verifier)."""
    _OAuthHandler.code = None
    _OAuthHandler.error = None
    _OAuthHandler.error_description = None
    _OAuthHandler.state_got = None

    parsed = urlparse(redirect_uri)
    host = parsed.hostname or "127.0.0.1"
    if host not in {"127.0.0.1", "localhost"}:
        raise SystemExit(
            f"❌ Desktop redirect_uri host must be 127.0.0.1 or localhost, got {host!r}"
        )
    if not parsed.port:
        raise SystemExit(
            "❌ Redirect URI must include an explicit port "
            f"(TikTok Desktop requirement). Got: {redirect_uri}"
        )
    path = parsed.path or "/"
    if not path.endswith("/"):
        # Accept either; callback path matching is best-effort
        pass

    verifier, challenge = _pkce_pair()
    state = secrets.token_urlsafe(24)
    _OAuthHandler.state_expected = state

    bind_host = "127.0.0.1" if host in {"127.0.0.1", "localhost"} else host
    server = http.server.HTTPServer((bind_host, parsed.port), _OAuthHandler)

    params = {
        "client_key": client_key,
        "scope": scopes,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    auth_url = f"{AUTH_URI}?{urllib.parse.urlencode(params)}"

    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()

    print("Opening browser for TikTok consent…")
    print(f"Redirect URI (must match Login Kit exactly):\n  {redirect_uri}")
    print(f"If the browser does not open, visit:\n{auth_url}\n")
    import webbrowser

    webbrowser.open(auth_url)

    thread.join(timeout=300)
    server.server_close()

    if _OAuthHandler.error:
        detail = _OAuthHandler.error_description or ""
        raise SystemExit(f"❌ OAuth error: {_OAuthHandler.error} {detail}".strip())
    if _OAuthHandler.state_got != state:
        raise SystemExit("❌ OAuth state mismatch (possible CSRF / wrong callback).")
    if not _OAuthHandler.code:
        raise SystemExit("❌ No authorization code received (timed out?).")
    return _OAuthHandler.code, verifier


def _smoke_user(access_token: str) -> None:
    fields = "open_id,union_id,avatar_url,display_name"
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

    err = (payload.get("error") or {}) if isinstance(payload, dict) else {}
    if err.get("code") and err.get("code") != "ok":
        raise SystemExit(f"❌ user/info error: {payload!r}")

    user = ((payload.get("data") or {}).get("user")) or {}
    display = user.get("display_name") or "(no display_name)"
    open_id = user.get("open_id") or "(no open_id)"
    print(f"✅ User OK: {display} (open_id={open_id})")


def main() -> int:
    from publish_common import add_write_env_flags, resolve_write_env

    parser = argparse.ArgumentParser(
        description="Get a TikTok refresh token via Desktop Login Kit (browser once).",
    )
    add_write_env_flags(parser)
    parser.add_argument(
        "--scopes",
        default="",
        help=f"Comma-separated scopes (default: env TIKTOK_SCOPES or {DEFAULT_SCOPES}).",
    )
    args = parser.parse_args()
    _require_wfrun()

    client_key = _env("TIKTOK_CLIENT_KEY")
    client_secret = _env("TIKTOK_CLIENT_SECRET")
    redirect_uri = _env("TIKTOK_REDIRECT_URI") or DEFAULT_REDIRECT_URI
    scopes = (args.scopes or _env("TIKTOK_SCOPES") or DEFAULT_SCOPES).replace(" ", "")

    if not client_key or not client_secret:
        print(
            "❌ Set TIKTOK_CLIENT_KEY and TIKTOK_CLIENT_SECRET "
            "(Sandbox or Production credentials) in the wfrun env file.",
            file=sys.stderr,
        )
        return 1

    code, verifier = _run_browser_flow(client_key, redirect_uri, scopes)
    token_payload = _post_form(
        TOKEN_URI,
        {
            "client_key": client_key,
            "client_secret": client_secret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
            "code_verifier": verifier,
        },
    )

    # TikTok sometimes nests under data; usually flat on token endpoint
    if "data" in token_payload and isinstance(token_payload["data"], dict):
        token_payload = {**token_payload, **token_payload["data"]}

    access_token = (token_payload.get("access_token") or "").strip()
    refresh_token = (token_payload.get("refresh_token") or "").strip()
    open_id = (token_payload.get("open_id") or "").strip()
    granted = (token_payload.get("scope") or "").strip()

    if token_payload.get("error") and not access_token:
        raise SystemExit(f"❌ Token error: {token_payload!r}")
    if not access_token:
        raise SystemExit(f"❌ No access_token in response: {token_payload!r}")
    if not refresh_token:
        raise SystemExit(
            "❌ No refresh_token returned. Confirm Login Kit Desktop + scopes, "
            "and that the Sandbox target user completed consent."
        )

    print("\n——— save this (do not commit) ———")
    print(f"TIKTOK_REFRESH_TOKEN={refresh_token}")
    if open_id:
        print(f"TIKTOK_OPEN_ID={open_id}")
    if granted:
        print(f"# granted scopes: {granted}")
    print("———————————————————————————————\n")

    write_env = resolve_write_env(
        "TIKTOK_REFRESH_TOKEN / OPEN_ID",
        write_flag=args.write_env,
        no_write_flag=args.no_write_env,
    )
    if write_env:
        env_file = _env("WFRUN_ENV_FILE")
        if not env_file:
            print("❌ WFRUN_ENV_FILE not set — cannot write env.", file=sys.stderr)
            return 1
        path = Path(env_file)
        _upsert_env_key(path, "TIKTOK_REFRESH_TOKEN", refresh_token)
        if open_id:
            _upsert_env_key(path, "TIKTOK_OPEN_ID", open_id)
        _upsert_env_key(path, "TIKTOK_REDIRECT_URI", redirect_uri)
        print(f"Wrote TIKTOK_REFRESH_TOKEN / OPEN_ID → {path}")
    else:
        print("Skipped writing env — paste tokens into .env.local manually if needed.")

    _smoke_user(access_token)
    print(
        "Done. Access tokens expire ~24h; refresh tokens ~365d "
        "(save a new refresh_token if TikTok rotates it on refresh)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
