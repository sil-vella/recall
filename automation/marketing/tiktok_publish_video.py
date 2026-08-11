#!/usr/bin/env python3
# dash TikTok: Direct Post publish
"""Upload a local video via TikTok Content Posting Direct Post (FILE_UPLOAD).

Caption = title + newline + description (optional hashtags appended).
Unaudited / Sandbox clients typically must use SELF_ONLY + private account.

Usage:
  wfrun → automation/marketing/tiktok_publish_video.py \\
    --video /path/to.mp4 --title "Title" --description "Desc"
"""

from __future__ import annotations

import argparse
import json
import math
import mimetypes
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

from publish_common import (
    append_hashtags,
    env,
    err_result,
    http_json,
    merge_caption,
    ok_result,
    require_wfrun,
)

TOKEN_URI = "https://open.tiktokapis.com/v2/oauth/token/"
CREATOR_INFO_URI = "https://open.tiktokapis.com/v2/post/publish/creator_info/query/"
VIDEO_INIT_URI = "https://open.tiktokapis.com/v2/post/publish/video/init/"
STATUS_URI = "https://open.tiktokapis.com/v2/post/publish/status/fetch/"

MIN_MULTI_CHUNK = 5 * 1024 * 1024
MAX_SINGLE_CHUNK = 64 * 1024 * 1024
DEFAULT_CHUNK = 10 * 1024 * 1024


def _tiktok_ok(payload: dict) -> bool:
    err = payload.get("error") or {}
    return (err.get("code") or "ok") == "ok"


def _refresh_access_token() -> str:
    client_key = env("TIKTOK_CLIENT_KEY")
    client_secret = env("TIKTOK_CLIENT_SECRET")
    refresh_token = env("TIKTOK_REFRESH_TOKEN")
    if not client_key or not client_secret or not refresh_token:
        raise RuntimeError(
            "missing_tiktok_credentials — set TIKTOK_CLIENT_KEY, "
            "TIKTOK_CLIENT_SECRET, TIKTOK_REFRESH_TOKEN"
        )
    status, payload, _ = http_json(
        "POST",
        TOKEN_URI,
        form={
            "client_key": client_key,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
        headers={"Cache-Control": "no-cache"},
        timeout=60,
    )
    if "data" in payload and isinstance(payload["data"], dict):
        payload = {**payload, **payload["data"]}
    access = str(payload.get("access_token") or "").strip()
    if status >= 400 or not access:
        raise RuntimeError(f"tiktok_token_refresh_failed: {payload!r}")
    return access


def _creator_info(access_token: str) -> dict:
    status, payload, _ = http_json(
        "POST",
        CREATOR_INFO_URI,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
        },
        body=b"{}",
        timeout=60,
    )
    if status >= 400 or not _tiktok_ok(payload):
        raise RuntimeError(f"tiktok_creator_info_failed: {payload!r}")
    return payload.get("data") or {}


def _chunk_plan(video_size: int) -> tuple[int, int]:
    if video_size <= 0:
        raise RuntimeError("tiktok_media_empty")
    if video_size < MIN_MULTI_CHUNK or video_size <= MAX_SINGLE_CHUNK:
        return video_size, 1
    chunk_size = DEFAULT_CHUNK
    total = math.ceil(video_size / chunk_size)
    return chunk_size, total


def _content_type(path: Path) -> str:
    guessed, _ = mimetypes.guess_type(path.name)
    if guessed in {"video/mp4", "video/quicktime", "video/webm"}:
        return guessed
    return "video/mp4"


def publish_tiktok_video(
    *,
    title: str,
    description: str = "",
    hashtags: list[str] | None = None,
    video_path: str | Path,
    privacy_level: str = "SELF_ONLY",
    disable_comment: bool = False,
    disable_duet: bool = False,
    disable_stitch: bool = False,
) -> dict[str, Any]:
    path = Path(video_path).expanduser().resolve()
    if not path.is_file():
        return err_result("tiktok_media_missing", f"Video not found: {path}")

    caption = append_hashtags(merge_caption(title, description), hashtags)
    # TikTok caption/title limit is tight; keep first 2200 chars
    caption = caption[:2200]

    try:
        access = _refresh_access_token()
        info = _creator_info(access)
    except RuntimeError as exc:
        msg = str(exc)
        code = "missing_tiktok_credentials"
        if "token_refresh" in msg:
            code = "tiktok_reauth_required"
        return err_result(code, msg)

    options = list(info.get("privacy_level_options") or [])
    privacy = (privacy_level or "SELF_ONLY").strip()
    if privacy not in options and options:
        if "SELF_ONLY" in options:
            privacy = "SELF_ONLY"
        else:
            return err_result(
                "tiktok_privacy_unavailable",
                f"Requested {privacy_level!r} not in {options}",
            )

    video_size = path.stat().st_size
    try:
        chunk_size, total_chunks = _chunk_plan(video_size)
    except RuntimeError as exc:
        return err_result("tiktok_media_empty", str(exc))

    init_body = {
        "post_info": {
            "title": caption or "Untitled",
            "privacy_level": privacy,
            "disable_comment": bool(disable_comment or info.get("comment_disabled")),
            "disable_duet": bool(disable_duet or info.get("duet_disabled")),
            "disable_stitch": bool(disable_stitch or info.get("stitch_disabled")),
        },
        "source_info": {
            "source": "FILE_UPLOAD",
            "video_size": video_size,
            "chunk_size": chunk_size,
            "total_chunk_count": total_chunks,
        },
    }
    status, payload, _ = http_json(
        "POST",
        VIDEO_INIT_URI,
        headers={
            "Authorization": f"Bearer {access}",
            "Content-Type": "application/json; charset=UTF-8",
        },
        body=json.dumps(init_body).encode("utf-8"),
        timeout=120,
    )
    if status >= 400 or not _tiktok_ok(payload):
        err = (payload.get("error") or {}).get("code") or ""
        hint = ""
        if err == "unaudited_client_can_only_post_to_private_accounts":
            hint = " (set TikTok account to Private for Sandbox/unaudited)"
        return err_result(
            "tiktok_publish_failed",
            f"video/init HTTP {status}: {payload!r}{hint}",
        )
    data = payload.get("data") or {}
    publish_id = str(data.get("publish_id") or "").strip()
    upload_url = str(data.get("upload_url") or "").strip()
    if not publish_id or not upload_url:
        return err_result("tiktok_publish_failed", f"init missing ids: {payload!r}")

    ctype = _content_type(path)
    try:
        with path.open("rb") as fh:
            offset = 0
            for i in range(total_chunks):
                to_read = min(chunk_size, video_size - offset)
                if i == total_chunks - 1:
                    to_read = video_size - offset
                chunk = fh.read(to_read)
                if len(chunk) != to_read:
                    return err_result("tiktok_publish_failed", "Short read while uploading")
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
                        _ = resp.status
                except Exception as exc:  # noqa: BLE001
                    return err_result(
                        "tiktok_publish_failed",
                        f"Upload chunk {i + 1}/{total_chunks}: {exc}",
                    )
                offset = last + 1
    except OSError as exc:
        return err_result("tiktok_publish_failed", str(exc))

    deadline = time.time() + 180
    last: dict = {}
    while time.time() < deadline:
        st_code, st_payload, _ = http_json(
            "POST",
            STATUS_URI,
            headers={
                "Authorization": f"Bearer {access}",
                "Content-Type": "application/json; charset=UTF-8",
            },
            body=json.dumps({"publish_id": publish_id}).encode("utf-8"),
            timeout=60,
        )
        if st_code >= 400 or not _tiktok_ok(st_payload):
            return err_result(
                "tiktok_publish_failed",
                f"status/fetch HTTP {st_code}: {st_payload!r}",
            )
        last = st_payload.get("data") or {}
        st = last.get("status") or ""
        if st == "PUBLISH_COMPLETE":
            return ok_result(
                {
                    "platform": "tiktok",
                    "publish_id": publish_id,
                    "status": st,
                }
            )
        if st in {"FAILED", "SEND_TO_USER_INBOX"}:
            return err_result(
                "tiktok_publish_failed",
                f"status={st}: {last!r}",
            )
        time.sleep(3)
    return err_result("tiktok_publish_failed", f"Timed out; last={last!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish a video to TikTok.")
    parser.add_argument("--video", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--description", default="")
    parser.add_argument("--privacy", default="SELF_ONLY")
    parser.add_argument("--hashtags", default="")
    parser.add_argument("--disable-comment", action="store_true")
    parser.add_argument("--disable-duet", action="store_true")
    parser.add_argument("--disable-stitch", action="store_true")
    args = parser.parse_args()
    try:
        require_wfrun()
    except RuntimeError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    tags = [t.strip() for t in args.hashtags.split(",") if t.strip()]
    result = publish_tiktok_video(
        title=args.title,
        description=args.description,
        hashtags=tags,
        video_path=args.video,
        privacy_level=args.privacy,
        disable_comment=args.disable_comment,
        disable_duet=args.disable_duet,
        disable_stitch=args.disable_stitch,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
