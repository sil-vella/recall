#!/usr/bin/env python3
# dash TikTok Sandbox: private Direct Post smoke test
"""Upload a local video via Content Posting Direct Post (FILE_UPLOAD).

Unaudited / Sandbox clients must post SELF_ONLY and the TikTok account must
usually be private (see unaudited_client_can_only_post_to_private_accounts).

Flow: refresh access token → creator_info → video/init → PUT chunks → status poll.

Video path: --video or env TIKTOK_SMOKE_VIDEO (needed because wfrun has no args prompt).

Usage:
  wfrun → automation/marketing/tiktok_post_video_smoke.py
  # with TIKTOK_SMOKE_VIDEO=/path/to.mp4 in .env.local
"""

from __future__ import annotations

import argparse
import json
import math
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

TOKEN_URI = "https://open.tiktokapis.com/v2/oauth/token/"
CREATOR_INFO_URI = "https://open.tiktokapis.com/v2/post/publish/creator_info/query/"
VIDEO_INIT_URI = "https://open.tiktokapis.com/v2/post/publish/video/init/"
STATUS_URI = "https://open.tiktokapis.com/v2/post/publish/status/fetch/"

MIN_MULTI_CHUNK = 5 * 1024 * 1024
MAX_SINGLE_CHUNK = 64 * 1024 * 1024
DEFAULT_CHUNK = 10 * 1024 * 1024


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


def _http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
    form: dict[str, str] | None = None,
) -> tuple[int, dict]:
    hdrs = dict(headers or {})
    data = body
    if form is not None:
        data = urllib.parse.urlencode(form).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/x-www-form-urlencoded")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            payload = json.loads(raw) if raw else {}
            return resp.status, payload
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"error": {"code": "http_error", "message": raw}}
        return exc.code, payload


def _tiktok_ok(payload: dict) -> bool:
    err = payload.get("error") or {}
    return (err.get("code") or "ok") == "ok"


def _refresh_access_token(
    client_key: str, client_secret: str, refresh_token: str
) -> tuple[str, str]:
    status, payload = _http_json(
        "POST",
        TOKEN_URI,
        form={
            "client_key": client_key,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
        headers={"Cache-Control": "no-cache"},
    )
    if "data" in payload and isinstance(payload["data"], dict):
        payload = {**payload, **payload["data"]}
    access = (payload.get("access_token") or "").strip()
    new_refresh = (payload.get("refresh_token") or refresh_token).strip()
    if status >= 400 or not access:
        raise SystemExit(f"❌ Token refresh failed HTTP {status}: {payload!r}")
    return access, new_refresh


def _creator_info(access_token: str) -> dict:
    status, payload = _http_json(
        "POST",
        CREATOR_INFO_URI,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
        },
        body=b"{}",
    )
    if status >= 400 or not _tiktok_ok(payload):
        raise SystemExit(f"❌ creator_info failed HTTP {status}: {payload!r}")
    return payload.get("data") or {}


def _chunk_plan(video_size: int) -> tuple[int, int]:
    """Return (chunk_size, total_chunk_count)."""
    if video_size <= 0:
        raise SystemExit("❌ Video file is empty.")
    if video_size < MIN_MULTI_CHUNK or video_size <= MAX_SINGLE_CHUNK:
        return video_size, 1
    chunk_size = DEFAULT_CHUNK
    # floor(size/chunk) but last chunk absorbs remainder → count = ceil
    total = math.ceil(video_size / chunk_size)
    return chunk_size, total


def _init_upload(
    access_token: str,
    *,
    title: str,
    privacy_level: str,
    video_size: int,
    chunk_size: int,
    total_chunk_count: int,
    disable_comment: bool,
    disable_duet: bool,
    disable_stitch: bool,
) -> tuple[str, str]:
    body = {
        "post_info": {
            "title": title,
            "privacy_level": privacy_level,
            "disable_comment": disable_comment,
            "disable_duet": disable_duet,
            "disable_stitch": disable_stitch,
        },
        "source_info": {
            "source": "FILE_UPLOAD",
            "video_size": video_size,
            "chunk_size": chunk_size,
            "total_chunk_count": total_chunk_count,
        },
    }
    status, payload = _http_json(
        "POST",
        VIDEO_INIT_URI,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
        },
        body=json.dumps(body).encode("utf-8"),
    )
    if status >= 400 or not _tiktok_ok(payload):
        err = (payload.get("error") or {}).get("code") or ""
        hint = ""
        if err == "unaudited_client_can_only_post_to_private_accounts":
            hint = (
                "\nHint: set the TikTok account to Private (Settings → Privacy), "
                "then retry. Unaudited clients cannot post to public accounts."
            )
        raise SystemExit(f"❌ video/init failed HTTP {status}: {payload!r}{hint}")
    data = payload.get("data") or {}
    publish_id = (data.get("publish_id") or "").strip()
    upload_url = (data.get("upload_url") or "").strip()
    if not publish_id or not upload_url:
        raise SystemExit(f"❌ video/init missing publish_id/upload_url: {payload!r}")
    return publish_id, upload_url


def _content_type(path: Path) -> str:
    guessed, _ = mimetypes.guess_type(path.name)
    if guessed in {"video/mp4", "video/quicktime", "video/webm"}:
        return guessed
    return "video/mp4"


def _upload_file(
    upload_url: str,
    path: Path,
    *,
    video_size: int,
    chunk_size: int,
    total_chunk_count: int,
) -> None:
    ctype = _content_type(path)
    with path.open("rb") as fh:
        offset = 0
        for i in range(total_chunk_count):
            to_read = min(chunk_size, video_size - offset)
            if i == total_chunk_count - 1:
                to_read = video_size - offset
            chunk = fh.read(to_read)
            if len(chunk) != to_read:
                raise SystemExit("❌ Short read while uploading video.")
            first = offset
            last = offset + len(chunk) - 1
            req = urllib.request.Request(
                upload_url,
                data=chunk,
                method="PUT",
                headers={
                    "Content-Type": ctype,
                    "Content-Length": str(len(chunk)),
                    "Content-Range": f"bytes {first}-{last}/{video_size}",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=300) as resp:
                    code = resp.status
            except urllib.error.HTTPError as exc:
                body = exc.read().decode("utf-8", errors="replace")
                raise SystemExit(
                    f"❌ Upload chunk {i + 1}/{total_chunk_count} "
                    f"HTTP {exc.code}: {body}"
                ) from exc
            print(f"  uploaded chunk {i + 1}/{total_chunk_count} → HTTP {code}")
            offset = last + 1
    if offset != video_size:
        raise SystemExit("❌ Upload finished with size mismatch.")


def _poll_status(access_token: str, publish_id: str, *, timeout_s: int = 180) -> dict:
    deadline = time.time() + timeout_s
    last: dict = {}
    while time.time() < deadline:
        status, payload = _http_json(
            "POST",
            STATUS_URI,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json; charset=UTF-8",
            },
            body=json.dumps({"publish_id": publish_id}).encode("utf-8"),
        )
        if status >= 400 or not _tiktok_ok(payload):
            raise SystemExit(f"❌ status/fetch failed HTTP {status}: {payload!r}")
        last = payload.get("data") or {}
        st = last.get("status") or ""
        print(f"  status: {st}")
        if st in {"PUBLISH_COMPLETE", "FAILED", "SEND_TO_USER_INBOX"}:
            return last
        time.sleep(3)
    raise SystemExit(f"❌ Timed out waiting for publish status. Last: {last!r}")


def main() -> int:
    from publish_common import add_write_env_flags, resolve_write_env

    parser = argparse.ArgumentParser(
        description="TikTok Direct Post smoke test (private / SELF_ONLY).",
    )
    parser.add_argument(
        "--video",
        default="",
        help="Path to local .mp4/.mov/.webm (or set TIKTOK_SMOKE_VIDEO in env)",
    )
    parser.add_argument(
        "--title",
        default="ReignOfPlay API smoke test (private)",
        help="Caption / title for the post",
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

    video_arg = (args.video or _env("TIKTOK_SMOKE_VIDEO")).strip()
    if not video_arg:
        print(
            "❌ Pass --video /path/to.mp4 or set TIKTOK_SMOKE_VIDEO in .env.local "
            "(wfrun does not prompt for script args).",
            file=sys.stderr,
        )
        return 1

    video_path = Path(video_arg).expanduser().resolve()
    if not video_path.is_file():
        print(f"❌ Video not found: {video_path}", file=sys.stderr)
        return 1

    video_size = video_path.stat().st_size
    chunk_size, total_chunks = _chunk_plan(video_size)
    print(f"Video: {video_path.name} ({video_size} bytes, {total_chunks} chunk(s))")

    access, new_refresh = _refresh_access_token(client_key, client_secret, refresh_token)
    if new_refresh != refresh_token:
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

    info = _creator_info(access)
    nick = info.get("creator_nickname") or info.get("creator_username") or "?"
    options = list(info.get("privacy_level_options") or [])
    print(f"Creator: {nick}")
    print(f"privacy_level_options: {options}")
    if "SELF_ONLY" not in options:
        raise SystemExit(
            "❌ SELF_ONLY not in privacy_level_options — cannot smoke-test "
            "unaudited Direct Post. Check account privacy settings."
        )
    privacy = "SELF_ONLY"

    publish_id, upload_url = _init_upload(
        access,
        title=args.title,
        privacy_level=privacy,
        video_size=video_size,
        chunk_size=chunk_size,
        total_chunk_count=total_chunks,
        disable_comment=bool(info.get("comment_disabled")),
        disable_duet=bool(info.get("duet_disabled")),
        disable_stitch=bool(info.get("stitch_disabled")),
    )
    print(f"publish_id: {publish_id}")
    print("Uploading…")
    _upload_file(
        upload_url,
        video_path,
        video_size=video_size,
        chunk_size=chunk_size,
        total_chunk_count=total_chunks,
    )
    print("Polling status…")
    final = _poll_status(access, publish_id)
    st = final.get("status")
    if st == "PUBLISH_COMPLETE":
        print("✅ PUBLISH_COMPLETE — check TikTok (private / Only you).")
        return 0
    if st == "FAILED":
        raise SystemExit(f"❌ Publish FAILED: {final!r}")
    print(f"⚠️  Finished with status={st}: {final!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
