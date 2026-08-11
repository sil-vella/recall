#!/usr/bin/env python3
# dash YouTube: upload video (+ optional playlist)
"""Upload a local video via YouTube Data API v3 (resumable).

Title and description stay separate. Optional playlist_id → playlistItems.insert
(needs youtube.force-ssl on the refresh token).

Usage:
  wfrun → automation/marketing/youtube_publish_video.py \\
    --video /path/to.mp4 --title "Title" --description "Desc"
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from publish_common import (
    env,
    err_result,
    http_json,
    local_datetime_to_rfc3339,
    ok_result,
    require_wfrun,
)

TOKEN_URI = "https://oauth2.googleapis.com/token"
UPLOAD_URI = "https://www.googleapis.com/upload/youtube/v3/videos"
VIDEOS_URI = "https://www.googleapis.com/youtube/v3/videos"
PLAYLIST_ITEMS_URI = "https://www.googleapis.com/youtube/v3/playlistItems"
CHUNK = 8 * 1024 * 1024  # 8 MiB (multiple of 256 KiB)


def _refresh_access_token() -> str:
    client_id = env("YOUTUBE_CLIENT_ID")
    client_secret = env("YOUTUBE_CLIENT_SECRET")
    refresh_token = env("YOUTUBE_REFRESH_TOKEN")
    if not client_id or not client_secret or not refresh_token:
        raise RuntimeError(
            "missing_youtube_credentials — set YOUTUBE_CLIENT_ID, "
            "YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN"
        )
    status, payload, _ = http_json(
        "POST",
        TOKEN_URI,
        form={
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
        timeout=60,
    )
    access = str(payload.get("access_token") or "").strip()
    if status >= 400 or not access:
        raise RuntimeError(f"youtube_token_refresh_failed: {payload!r}")
    return access


def _content_type(path: Path) -> str:
    guessed, _ = mimetypes.guess_type(path.name)
    if guessed and guessed.startswith("video/"):
        return guessed
    return "video/mp4"


def _start_resumable(
    access_token: str,
    *,
    title: str,
    description: str,
    tags: list[str],
    category_id: str,
    privacy: str,
    publish_at: str | None,
    video_size: int,
    content_type: str,
) -> str:
    status_body: dict[str, Any] = {
        "privacyStatus": privacy,
        "selfDeclaredMadeForKids": False,
    }
    if publish_at:
        status_body["privacyStatus"] = "private"
        status_body["publishAt"] = local_datetime_to_rfc3339(publish_at)

    meta = {
        "snippet": {
            "title": title[:100] or "Untitled",
            "description": description or "",
            "tags": tags,
            "categoryId": category_id or env("YOUTUBE_CATEGORY_ID") or "22",
        },
        "status": status_body,
    }
    params = urllib.parse.urlencode(
        {"uploadType": "resumable", "part": "snippet,status"}
    )
    url = f"{UPLOAD_URI}?{params}"
    body = json.dumps(meta).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Length": str(video_size),
            "X-Upload-Content-Type": content_type,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            location = resp.headers.get("Location") or resp.headers.get("location")
    except Exception as exc:  # noqa: BLE001 — map to publish error
        raise RuntimeError(f"youtube_upload_init_failed: {exc}") from exc
    if not location:
        raise RuntimeError("youtube_upload_init_failed: missing Location header")
    return location


def _put_chunks(upload_url: str, path: Path, video_size: int, content_type: str) -> dict:
    with path.open("rb") as fh:
        offset = 0
        while offset < video_size:
            chunk = fh.read(CHUNK)
            if not chunk:
                break
            end = offset + len(chunk) - 1
            req = urllib.request.Request(
                upload_url,
                data=chunk,
                method="PUT",
                headers={
                    "Content-Type": content_type,
                    "Content-Length": str(len(chunk)),
                    "Content-Range": f"bytes {offset}-{end}/{video_size}",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=600) as resp:
                    raw = resp.read().decode("utf-8")
                    if resp.status in {200, 201} and raw:
                        return json.loads(raw)
            except urllib.error.HTTPError as exc:
                # 308 Resume Incomplete is expected between chunks
                if exc.code == 308:
                    offset = end + 1
                    continue
                body = exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"youtube_upload_chunk_failed HTTP {exc.code}: {body}"
                ) from exc
            offset = end + 1
    raise RuntimeError("youtube_upload_failed: no final video resource")


def _add_to_playlist(access_token: str, playlist_id: str, video_id: str) -> dict[str, Any]:
    body = {
        "snippet": {
            "playlistId": playlist_id,
            "resourceId": {"kind": "youtube#video", "videoId": video_id},
        }
    }
    url = f"{PLAYLIST_ITEMS_URI}?part=snippet"
    status, payload, _ = http_json(
        "POST",
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        body=json.dumps(body).encode("utf-8"),
        timeout=60,
    )
    if status >= 400 or payload.get("error"):
        return err_result(
            "youtube_playlist_failed",
            f"playlistItems.insert failed HTTP {status}: {payload!r}",
        )
    return ok_result({"playlist_item_id": str(payload.get("id") or "")})


def publish_youtube_video(
    *,
    title: str,
    description: str = "",
    video_path: str | Path,
    privacy: str = "private",
    category_id: str | None = None,
    tags: list[str] | None = None,
    publish_at: str | None = None,
    playlist_id: str | None = None,
) -> dict[str, Any]:
    path = Path(video_path).expanduser().resolve()
    if not path.is_file():
        return err_result("youtube_media_missing", f"Video not found: {path}")

    # Prefer explicit arg, then env (e.g. 20 = Gaming), else People & Blogs
    resolved_category = (
        (category_id or "").strip()
        or env("YOUTUBE_CATEGORY_ID")
        or "22"
    )

    try:
        access = _refresh_access_token()
    except RuntimeError as exc:
        msg = str(exc)
        code = "missing_youtube_credentials"
        if "token_refresh" in msg or "invalid_grant" in msg:
            code = "youtube_reauth_required"
        return err_result(code, msg)

    video_size = path.stat().st_size
    content_type = _content_type(path)
    clean_tags = [str(t).lstrip("#").strip() for t in (tags or []) if str(t).strip()]

    try:
        upload_url = _start_resumable(
            access,
            title=title,
            description=description or "",
            tags=clean_tags,
            category_id=resolved_category,
            privacy=privacy or "private",
            publish_at=publish_at,
            video_size=video_size,
            content_type=content_type,
        )
        video = _put_chunks(upload_url, path, video_size, content_type)
    except RuntimeError as exc:
        return err_result("youtube_publish_failed", str(exc))
    except Exception as exc:  # noqa: BLE001
        return err_result("youtube_publish_failed", str(exc))

    video_id = str(video.get("id") or "").strip()
    if not video_id:
        return err_result("youtube_publish_failed", f"No video id in response: {video!r}")

    out: dict[str, Any] = {
        "platform": "youtube",
        "id": video_id,
        "url": f"https://www.youtube.com/watch?v={video_id}",
    }
    if playlist_id:
        pl = _add_to_playlist(access, playlist_id.strip(), video_id)
        out["playlist"] = pl
        if not pl.get("ok"):
            # Video uploaded; playlist add failed (often missing force-ssl)
            return {
                "ok": True,
                "data": out,
                "warning": (pl.get("error") or {}).get("message")
                or "playlist add failed",
            }
    return ok_result(out)


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload a video to YouTube.")
    parser.add_argument("--video", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--description", default="")
    parser.add_argument("--privacy", default="private")
    parser.add_argument(
        "--category-id",
        default="",
        help="YouTube category id (default: env YOUTUBE_CATEGORY_ID or 22)",
    )
    parser.add_argument("--tags", default="", help="Comma-separated tags")
    parser.add_argument("--publish-at", default="")
    parser.add_argument("--playlist-id", default="")
    args = parser.parse_args()
    try:
        require_wfrun()
    except RuntimeError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    tags = [t.strip() for t in args.tags.split(",") if t.strip()]
    result = publish_youtube_video(
        title=args.title,
        description=args.description,
        video_path=args.video,
        privacy=args.privacy,
        category_id=args.category_id or None,
        tags=tags,
        publish_at=args.publish_at or None,
        playlist_id=args.playlist_id or None,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
