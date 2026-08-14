#!/usr/bin/env python3
# dash Open wf_template automation dashboard in browser
"""wfrun dashboard — browser GUI alternative to the wfrun CLI script menu."""

from __future__ import annotations

import asyncio
import json
import os
import re
import subprocess
import sys
import time
import uuid
import webbrowser
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path

try:
    from aiohttp import ClientSession, ClientTimeout, WSMsgType, web
except ImportError:
    print(
        "❌ Missing dependency: aiohttp\n"
        "   Install once: pip install -r automation/dashboard/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)

from env_for_script import cwd_for_script, env_for_script
from pty_runner import PtyRunner
from run_log import LOGS_DIR, RunLog, log_path_for_script
from docs_discovery import (
    discover_case_studies,
    discover_docs,
    read_doc,
)
from script_discovery import build_command, discover_scripts, resolve_script

SCRIPT_DIR = Path(__file__).resolve().parent
STATIC_DIR = SCRIPT_DIR / "static"
MARKETING_DATA_DIR = SCRIPT_DIR / "data"
MARKETING_MEDIA_DIR = MARKETING_DATA_DIR / "media"
MARKETING_POSTS_FILE = MARKETING_DATA_DIR / "marketing_posts.json"
MARKETING_SCRIPTS_DIR = SCRIPT_DIR.parent / "marketing"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
# Large enough for Shorts / TikTok clips uploaded through the Marketing tab
MARKETING_CLIENT_MAX_SIZE = 512 * 1024 * 1024
# Same-origin path prefix so the Task Manager iframe shares the dashboard origin
# (cross-site cookies break PHP session + CSRF login inside the iframe).
TM_PROXY_PREFIX = "/tm"
_TM_ABS_ATTR_RE = re.compile(
    rb'(?i)(\b(?:href|src|action|formaction|data-src|poster)\s*=\s*[\'"])/(?!tm/)'
)
_TM_CSS_URL_RE = re.compile(rb"""(?i)(url\(\s*['"]?)/(?!tm/)""")
_TM_PROXY_TIMEOUT = ClientTimeout(total=120)

if str(MARKETING_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(MARKETING_SCRIPTS_DIR))


def _marketing_posts_path() -> Path:
    MARKETING_DATA_DIR.mkdir(parents=True, exist_ok=True)
    return MARKETING_POSTS_FILE


def _read_marketing_posts() -> list[dict[str, object]]:
    path = _marketing_posts_path()
    if not path.is_file():
        return []
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(raw, dict):
        return []
    posts = raw.get("posts")
    if not isinstance(posts, list):
        return []
    return [p for p in posts if isinstance(p, dict)]


def _write_marketing_posts(posts: list[dict[str, object]]) -> None:
    path = _marketing_posts_path()
    payload = {"posts": posts}
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


async def handle_marketing_posts_get(_request: web.Request) -> web.Response:
    posts = await asyncio.to_thread(_read_marketing_posts)
    # List endpoint returns light summaries; full payload stays on each post
    summaries = []
    for post in posts:
        summaries.append(
            {
                "id": post.get("id"),
                "title": post.get("title") or "(untitled)",
                "platforms": post.get("platforms") or [],
                "created_at": post.get("created_at"),
                "updated_at": post.get("updated_at"),
                "publish_ok": (
                    (post.get("publish") or {}).get("ok")
                    if isinstance(post.get("publish"), dict)
                    else None
                ),
            }
        )
    return web.json_response({"ok": True, "posts": summaries})


async def handle_marketing_post_get(request: web.Request) -> web.Response:
    post_id = request.match_info.get("post_id", "").strip()
    posts = await asyncio.to_thread(_read_marketing_posts)
    for post in posts:
        if str(post.get("id")) == post_id:
            return web.json_response({"ok": True, "post": post})
    return web.json_response({"ok": False, "error": "not_found"}, status=404)


def _safe_media_filename(name: str) -> str:
    base = Path(name or "upload.bin").name
    cleaned = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in base)
    return cleaned[:120] or "upload.bin"



async def handle_marketing_post_metrics_facebook(request: web.Request) -> web.Response:
    """Live Facebook engagement + Insights for a saved Marketing post."""
    post_id = request.match_info.get("post_id", "").strip()
    posts = await asyncio.to_thread(_read_marketing_posts)
    post: dict[str, object] | None = None
    for item in posts:
        if str(item.get("id")) == post_id:
            post = item
            break
    if post is None:
        return web.json_response(
            {
                "ok": False,
                "error": {"code": "not_found", "message": "Post not found"},
            },
            status=404,
        )

    from facebook_post_metrics import (
        facebook_object_id_from_post,
        fetch_facebook_post_metrics,
    )

    object_id = facebook_object_id_from_post(post)
    if not object_id:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "facebook_not_published",
                    "message": "No successful Facebook publish id on this post",
                },
            },
            status=400,
        )

    result = await asyncio.to_thread(fetch_facebook_post_metrics, object_id)
    if not result.get("ok"):
        err = result.get("error") if isinstance(result.get("error"), dict) else {}
        code = str(err.get("code") or "facebook_metrics_failed")
        status = 400
        if code == "missing_facebook_credentials":
            status = 400
        elif code == "facebook_metrics_permission":
            status = 403
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": code,
                    "message": str(err.get("message") or "Facebook metrics failed"),
                },
            },
            status=status,
        )
    return web.json_response({"ok": True, "metrics": result.get("data") or {}})


def _marketing_metrics_error_response(result: dict[str, object]) -> web.Response:
    err = result.get("error") if isinstance(result.get("error"), dict) else {}
    code = str(err.get("code") or "facebook_metrics_failed")
    status = 403 if code.endswith("_permission") else 400
    return web.json_response(
        {
            "ok": False,
            "error": {
                "code": code,
                "message": str(err.get("message") or "Request failed"),
            },
        },
        status=status,
    )


async def handle_marketing_metrics_facebook(request: web.Request) -> web.Response:
    """Live Facebook metrics by Graph object id (platform-posts browser)."""
    object_id = (request.query.get("object_id") or "").strip()
    if not object_id:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "object_id_required",
                    "message": "Query param object_id is required",
                },
            },
            status=400,
        )
    from facebook_post_metrics import fetch_facebook_post_metrics

    result = await asyncio.to_thread(fetch_facebook_post_metrics, object_id)
    if not result.get("ok"):
        return _marketing_metrics_error_response(result)
    return web.json_response({"ok": True, "metrics": result.get("data") or {}})


async def handle_marketing_metrics_youtube(request: web.Request) -> web.Response:
    """Live YouTube statistics by video id (platform-posts browser)."""
    object_id = (request.query.get("object_id") or "").strip()
    if not object_id:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "object_id_required",
                    "message": "Query param object_id is required",
                },
            },
            status=400,
        )
    from youtube_post_metrics import fetch_youtube_video_metrics

    result = await asyncio.to_thread(fetch_youtube_video_metrics, object_id)
    if not result.get("ok"):
        return _marketing_metrics_error_response(result)
    return web.json_response({"ok": True, "metrics": result.get("data") or {}})


async def handle_marketing_post_metrics_youtube(request: web.Request) -> web.Response:
    """Live YouTube statistics for a saved Marketing post."""
    post_id = request.match_info.get("post_id", "").strip()
    posts = await asyncio.to_thread(_read_marketing_posts)
    post: dict[str, object] | None = None
    for item in posts:
        if str(item.get("id")) == post_id:
            post = item
            break
    if post is None:
        return web.json_response(
            {
                "ok": False,
                "error": {"code": "not_found", "message": "Post not found"},
            },
            status=404,
        )

    from youtube_post_metrics import (
        fetch_youtube_video_metrics,
        youtube_video_id_from_post,
    )

    video_id = youtube_video_id_from_post(post)
    if not video_id:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "youtube_not_published",
                    "message": "No successful YouTube publish id on this post",
                },
            },
            status=400,
        )

    result = await asyncio.to_thread(fetch_youtube_video_metrics, video_id)
    if not result.get("ok"):
        return _marketing_metrics_error_response(result)
    return web.json_response({"ok": True, "metrics": result.get("data") or {}})


async def handle_marketing_platform_posts(request: web.Request) -> web.Response:
    """List remote posts for a platform (Facebook / YouTube; TikTok later)."""
    platform = (request.query.get("platform") or "facebook").strip().lower()
    limit_raw = (request.query.get("limit") or "5").strip()
    after = (request.query.get("after") or "").strip() or None
    try:
        limit = int(limit_raw)
    except ValueError:
        limit = 5
    limit = max(1, min(limit, 25))

    if platform == "facebook":
        from facebook_post_metrics import list_facebook_page_posts

        result = await asyncio.to_thread(
            list_facebook_page_posts, limit=limit, after=after
        )
        if not result.get("ok"):
            return _marketing_metrics_error_response(result)
        return web.json_response({"ok": True, **(result.get("data") or {})})

    if platform == "youtube":
        from youtube_post_metrics import list_youtube_channel_videos

        result = await asyncio.to_thread(
            list_youtube_channel_videos, limit=limit, page_token=after
        )
        if not result.get("ok"):
            return _marketing_metrics_error_response(result)
        return web.json_response({"ok": True, **(result.get("data") or {})})

    if platform == "tiktok":
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "platform_not_implemented",
                    "message": "tiktok platform posts browser is not wired yet",
                },
            },
            status=501,
        )

    return web.json_response(
        {
            "ok": False,
            "error": {
                "code": "unknown_platform",
                "message": f"Unknown platform: {platform}",
            },
        },
        status=400,
    )


def _safe_media_filename(name: str) -> str:
    base = Path(name or "upload.bin").name
    cleaned = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in base)
    return cleaned[:120] or "upload.bin"


async def _parse_marketing_post_request(
    request: web.Request,
) -> tuple[dict[str, object] | None, _MarketingUpload | None, web.Response | None]:
    """Return (body, media_upload, error_response)."""
    content_type = (request.content_type or "").lower()
    if "multipart/form-data" in content_type:
        reader = await request.multipart()
        body: dict[str, object] | None = None
        media_upload: _MarketingUpload | None = None
        while True:
            part = await reader.next()
            if part is None:
                break
            if part.name == "payload":
                raw = await part.text()
                try:
                    parsed = json.loads(raw)
                except json.JSONDecodeError:
                    return None, None, web.json_response(
                        {
                            "ok": False,
                            "error": {
                                "code": "invalid_json",
                                "message": "payload must be JSON",
                            },
                        },
                        status=400,
                    )
                if not isinstance(parsed, dict):
                    return None, None, web.json_response(
                        {
                            "ok": False,
                            "error": {
                                "code": "invalid_json",
                                "message": "payload must be an object",
                            },
                        },
                        status=400,
                    )
                body = parsed
            elif part.name == "media" and getattr(part, "filename", None):
                media_bytes = await part.read(decode=False)
                media_upload = _MarketingUpload(
                    filename=str(part.filename or "upload.bin"),
                    content_type=str(part.headers.get("Content-Type") or ""),
                    data=media_bytes,
                )
        if body is None:
            return None, None, web.json_response(
                {
                    "ok": False,
                    "error": {
                        "code": "invalid_json",
                        "message": "multipart requires payload field",
                    },
                },
                status=400,
            )
        return body, media_upload, None

    try:
        body_obj = await request.json()
    except json.JSONDecodeError:
        return None, None, web.json_response(
            {
                "ok": False,
                "error": {"code": "invalid_json", "message": "invalid JSON body"},
            },
            status=400,
        )
    if not isinstance(body_obj, dict):
        return None, None, web.json_response(
            {
                "ok": False,
                "error": {"code": "invalid_json", "message": "body must be an object"},
            },
            status=400,
        )
    return body_obj, None, None


@dataclass
class _MarketingUpload:
    filename: str
    content_type: str
    data: bytes


def _save_marketing_media(post_id: str, upload: _MarketingUpload) -> dict[str, object]:
    dest_dir = MARKETING_MEDIA_DIR / post_id
    dest_dir.mkdir(parents=True, exist_ok=True)
    filename = _safe_media_filename(upload.filename)
    dest = dest_dir / filename
    dest.write_bytes(upload.data)
    return {
        "name": filename,
        "type": upload.content_type,
        "size": len(upload.data),
        "path": str(dest),
    }


def _publish_selected_platforms(
    post: dict[str, object],
) -> dict[str, object]:
    """Publish only platforms listed on the post. Never posts to unchecked ones."""
    from facebook_publish_post import publish_facebook_post
    from tiktok_publish_video import publish_tiktok_video
    from youtube_publish_video import publish_youtube_video

    platforms = [
        str(p).strip().lower()
        for p in (post.get("platforms") or [])
        if str(p).strip()
    ]
    title = str(post.get("title") or "")
    description = str(post.get("description") or "")
    hashtags = post.get("hashtags") if isinstance(post.get("hashtags"), list) else []
    hashtag_strs = [str(h) for h in hashtags]
    media = post.get("media") if isinstance(post.get("media"), dict) else {}
    media_path = str(media.get("path") or "").strip() or None

    results: dict[str, object] = {}

    if "facebook" in platforms:
        fb = post.get("facebook") if isinstance(post.get("facebook"), dict) else {}
        link = ""
        if str(fb.get("post_type") or "") == "link":
            link = str(fb.get("link") or "").strip()
        schedule_at = None
        if str(fb.get("publish_mode") or "") == "schedule":
            schedule_at = str(fb.get("schedule_at") or "").strip() or None
        page = str(fb.get("page") or "").strip() or None
        results["facebook"] = publish_facebook_post(
            title=title,
            description=description,
            hashtags=hashtag_strs,
            link=link,
            schedule_at=schedule_at,
            page_id=page,
            media_path=media_path,
        )

    if "youtube" in platforms:
        yt = post.get("youtube") if isinstance(post.get("youtube"), dict) else {}
        if not media_path:
            results["youtube"] = {
                "ok": False,
                "error": {
                    "code": "youtube_media_required",
                    "message": "YouTube publish requires a video file",
                },
            }
        else:
            results["youtube"] = publish_youtube_video(
                title=title,
                description=description,
                video_path=media_path,
                privacy=str(yt.get("privacy") or "private"),
                category_id=str(yt.get("category_id") or "").strip() or None,
                tags=[str(t) for t in (yt.get("tags") or hashtag_strs)],
                publish_at=str(yt.get("publish_at") or "").strip() or None,
                playlist_id=str(yt.get("playlist_id") or "").strip() or None,
            )

    if "tiktok" in platforms:
        tt = post.get("tiktok") if isinstance(post.get("tiktok"), dict) else {}
        if not media_path:
            results["tiktok"] = {
                "ok": False,
                "error": {
                    "code": "tiktok_media_required",
                    "message": "TikTok publish requires a video file",
                },
            }
        else:
            results["tiktok"] = publish_tiktok_video(
                title=title,
                description=description,
                hashtags=hashtag_strs,
                video_path=media_path,
                privacy_level=str(tt.get("privacy_level") or "SELF_ONLY"),
                disable_comment=bool(tt.get("disable_comment")),
                disable_duet=bool(tt.get("disable_duet")),
                disable_stitch=bool(tt.get("disable_stitch")),
            )

    return results


async def handle_marketing_posts_create(request: web.Request) -> web.Response:
    body, media_upload, err = await _parse_marketing_post_request(request)
    if err is not None:
        return err
    assert body is not None

    title = str(body.get("title") or "").strip()
    if not title:
        return web.json_response(
            {
                "ok": False,
                "error": {"code": "title_required", "message": "Title is required"},
            },
            status=400,
        )

    platforms_raw = body.get("platforms") if isinstance(body.get("platforms"), list) else []
    platforms = [str(p).strip().lower() for p in platforms_raw if str(p).strip()]
    if not platforms:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "platforms_required",
                    "message": "Select at least one platform",
                },
            },
            status=400,
        )

    needs_media = any(p in {"youtube", "tiktok"} for p in platforms)
    if needs_media and media_upload is None:
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "media_required",
                    "message": "YouTube/TikTok require an image/video file",
                },
            },
            status=400,
        )

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    post_id = str(uuid.uuid4())
    media_meta: dict[str, object] | None = None
    if media_upload is not None and isinstance(media_upload, _MarketingUpload):
        media_meta = await asyncio.to_thread(_save_marketing_media, post_id, media_upload)
    elif isinstance(body.get("media"), dict):
        media_meta = body.get("media")  # type: ignore[assignment]

    post: dict[str, object] = {
        "id": post_id,
        "created_at": now,
        "updated_at": now,
        "title": title,
        "description": str(body.get("description") or ""),
        "platforms": platforms,
        "hashtags": body.get("hashtags") if isinstance(body.get("hashtags"), list) else [],
        "media": media_meta,
        "facebook": body.get("facebook") if isinstance(body.get("facebook"), dict) else None,
        "youtube": body.get("youtube") if isinstance(body.get("youtube"), dict) else None,
        "tiktok": body.get("tiktok") if isinstance(body.get("tiktok"), dict) else None,
        "payload": body,
        "publish": None,
    }

    def _append() -> dict[str, object]:
        posts = _read_marketing_posts()
        posts.insert(0, post)
        _write_marketing_posts(posts)
        return post

    saved = await asyncio.to_thread(_append)

    publish_results = await asyncio.to_thread(_publish_selected_platforms, saved)
    all_ok = bool(publish_results) and all(
        isinstance(v, dict) and v.get("ok") for v in publish_results.values()
    )
    publish_block = {
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ok": all_ok,
        "results": publish_results,
    }

    def _update_publish() -> dict[str, object]:
        posts = _read_marketing_posts()
        for item in posts:
            if str(item.get("id")) == post_id:
                item["publish"] = publish_block
                item["updated_at"] = publish_block["at"]
                _write_marketing_posts(posts)
                return item
        saved["publish"] = publish_block
        return saved

    updated = await asyncio.to_thread(_update_publish)
    status = 201 if all_ok else 207
    return web.json_response(
        {
            "ok": all_ok,
            "post": updated,
            "publish": publish_block,
            "error": None
            if all_ok
            else {
                "code": "publish_partial_or_failed",
                "message": "One or more selected platforms failed to publish",
            },
        },
        status=status,
    )


def _youtube_refresh_access_token() -> str:
    """Return a short-lived access token from env refresh credentials."""
    import urllib.error
    import urllib.parse
    import urllib.request

    client_id = _env_from_wfrun_file("YOUTUBE_CLIENT_ID")
    client_secret = _env_from_wfrun_file("YOUTUBE_CLIENT_SECRET")
    refresh_token = _env_from_wfrun_file("YOUTUBE_REFRESH_TOKEN")
    if not client_id or not client_secret or not refresh_token:
        raise RuntimeError(
            "missing_youtube_credentials — set YOUTUBE_CLIENT_ID, "
            "YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN"
        )
    data = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"youtube_token_refresh_failed: {body}") from exc
    access = (payload.get("access_token") or "").strip()
    if not access:
        raise RuntimeError("youtube_token_refresh_failed: no access_token")
    return access


def _youtube_list_playlists(access_token: str) -> list[dict[str, str]]:
    import urllib.error
    import urllib.parse
    import urllib.request

    items_out: list[dict[str, str]] = []
    page_token = ""
    while True:
        params: dict[str, str] = {
            "part": "snippet,contentDetails",
            "mine": "true",
            "maxResults": "50",
        }
        if page_token:
            params["pageToken"] = page_token
        url = (
            "https://www.googleapis.com/youtube/v3/playlists?"
            + urllib.parse.urlencode(params)
        )
        req = urllib.request.Request(
            url,
            headers={"Authorization": f"Bearer {access_token}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"youtube_playlists_failed: {body}") from exc
        for item in payload.get("items") or []:
            if not isinstance(item, dict):
                continue
            pid = str(item.get("id") or "").strip()
            snippet = item.get("snippet") if isinstance(item.get("snippet"), dict) else {}
            title = str(snippet.get("title") or pid).strip() or pid
            if pid:
                items_out.append({"id": pid, "title": title})
        page_token = str(payload.get("nextPageToken") or "").strip()
        if not page_token:
            break
    return items_out


async def handle_marketing_youtube_playlists(_request: web.Request) -> web.Response:
    def _run() -> list[dict[str, str]]:
        token = _youtube_refresh_access_token()
        return _youtube_list_playlists(token)

    try:
        playlists = await asyncio.to_thread(_run)
    except RuntimeError as exc:
        msg = str(exc)
        code = "youtube_playlists_error"
        if msg.startswith("missing_youtube_credentials"):
            code = "missing_youtube_credentials"
        elif "invalid_grant" in msg or "token_refresh_failed" in msg:
            code = "youtube_reauth_required"
        return web.json_response(
            {"ok": False, "error": {"code": code, "message": msg}},
            status=400,
        )
    except Exception as exc:  # noqa: BLE001 — boundary JSON for dashboard
        return web.json_response(
            {
                "ok": False,
                "error": {
                    "code": "youtube_playlists_error",
                    "message": str(exc),
                },
            },
            status=500,
        )
    return web.json_response({"ok": True, "data": {"playlists": playlists}})


def require_wfrun() -> Path:
    root = os.environ.get("WFRUN_ROOT", "").strip()
    mode = os.environ.get("WFRUN_MODE", "").strip()
    env_file = os.environ.get("WFRUN_ENV_FILE", "").strip()
    if not root or not mode or not env_file:
        print(
            "❌ Run via wfrun — this script expects WFRUN_ROOT, WFRUN_MODE, WFRUN_ENV_FILE.",
            file=sys.stderr,
        )
        sys.exit(1)
    return Path(root)


@dataclass
class ScriptSession:
    script_id: str
    runner: PtyRunner
    run_log: RunLog
    log_path: Path


def _rel_log_path(log_path: Path, root: Path) -> str:
    try:
        return log_path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(log_path)


class SessionManager:
    """One PTY session per script id — multiple scripts can run concurrently."""

    def __init__(self) -> None:
        self._sessions: dict[str, ScriptSession] = {}
        self._lock = asyncio.Lock()

    async def stop_session(self, session: ScriptSession) -> None:
        async with self._lock:
            current = self._sessions.get(session.script_id)
            if current is not session:
                return
            self._sessions.pop(session.script_id, None)
        await session.runner.terminate()
        session.run_log.close(exit_code=None)

    async def stop(self, script_id: str) -> None:
        async with self._lock:
            session = self._sessions.pop(script_id, None)
        if session is None:
            return
        await session.runner.terminate()
        session.run_log.close(exit_code=None)

    async def start(
        self,
        entry_id: str,
        root: Path,
        cols: int,
        rows: int,
        send_json: Callable[[dict[str, object]], Awaitable[None]],
        send_bytes: Callable[[bytes], Awaitable[None]],
    ) -> tuple[ScriptSession, Path]:
        await self.stop(entry_id)

        catalog = discover_scripts(root)
        entry = resolve_script(root, entry_id, catalog)
        cmd = build_command(entry.path)
        child_env = env_for_script(entry)
        cwd = cwd_for_script()
        mode = os.environ.get("WFRUN_MODE", "local")

        log_path = log_path_for_script(entry.id)
        log_rel = _rel_log_path(log_path, root)
        run_log = RunLog(log_path, entry.id, cmd, mode)
        runner = PtyRunner(cmd, child_env, cwd, cols=cols, rows=rows)
        session = ScriptSession(
            script_id=entry.id,
            runner=runner,
            run_log=run_log,
            log_path=log_path,
        )

        async def on_output(data: bytes) -> None:
            run_log.write(data)
            await send_bytes(data)

        async def on_exit(code: int) -> None:
            run_log.close(exit_code=code)
            await send_json(
                {"type": "exit", "code": code, "log_file": log_rel}
            )
            async with self._lock:
                if self._sessions.get(entry.id) is session:
                    self._sessions.pop(entry.id, None)

        async with self._lock:
            self._sessions[entry.id] = session

        runner.start(on_output, on_exit)
        print(f"📝 Logging: {log_rel}")
        await send_json(
            {
                "type": "started",
                "script": entry.id,
                "log_file": log_rel,
            }
        )
        return session, log_path


def _dashboard_url(host: str, port: int) -> str:
    return f"http://{host}:{port}/"


async def handle_index(_request: web.Request) -> web.Response:
    return web.FileResponse(STATIC_DIR / "index.html")


def _env_from_wfrun_file(key: str) -> str:
    """Prefer process env; fall back to WFRUN_ENV_FILE key=value lines."""
    value = os.environ.get(key, "").strip()
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
            name, _, val = line.partition("=")
            if name.strip() != key:
                continue
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            return val.strip()
    except OSError:
        return ""
    return ""


def _task_manager_base_url() -> str:
    """Origin for Task Manager (no trailing slash). Prefer TASK_MANAGER_BASE_URL."""
    base = _env_from_wfrun_file("TASK_MANAGER_BASE_URL").rstrip("/")
    if base:
        return base
    # Legacy host:port (pre-domain deploy)
    host = _env_from_wfrun_file("TASK_MANAGER_HOST")
    port = _env_from_wfrun_file("TASK_MANAGER_PORT")
    if host and port:
        return f"http://{host}:{port}"
    if host:
        return f"http://{host}"
    return ""


def _task_manager_embed_path() -> str:
    slug = _env_from_wfrun_file("TASK_MANAGER_SLUG")
    if not _task_manager_base_url() or not slug:
        return ""
    return f"{TM_PROXY_PREFIX}/content/label.php?slug={slug}&embed=1"


def _task_manager_url(request: web.Request | None = None) -> str:
    """Dashboard same-origin embed URL (via /tm proxy), not the remote origin."""
    path = _task_manager_embed_path()
    if not path:
        return ""
    if request is not None:
        return f"{request.url.scheme}://{request.host}{path}"
    host = os.environ.get("WFRUN_DASHBOARD_HOST", DEFAULT_HOST).strip() or DEFAULT_HOST
    port = int(os.environ.get("WFRUN_DASHBOARD_PORT", str(DEFAULT_PORT)))
    return f"http://{host}:{port}{path}"


def _rewrite_tm_set_cookie(value: str) -> str:
    parts: list[str] = []
    saw_path = False
    for raw in value.split(";"):
        part = raw.strip()
        if not part:
            continue
        lower = part.lower()
        if lower.startswith("domain="):
            continue
        if lower.startswith("path="):
            parts.append(f"Path={TM_PROXY_PREFIX}")
            saw_path = True
            continue
        if lower == "secure":
            continue
        parts.append(part)
    if not saw_path:
        parts.append(f"Path={TM_PROXY_PREFIX}")
    return "; ".join(parts)


def _rewrite_tm_location(location: str, remote_base: str) -> str:
    if location.startswith(remote_base):
        location = location[len(remote_base) :] or "/"
    if location.startswith("//"):
        return location
    if location.startswith("/") and not location.startswith(f"{TM_PROXY_PREFIX}/"):
        if location == TM_PROXY_PREFIX:
            return location
        return f"{TM_PROXY_PREFIX}{location}"
    return location


def _rewrite_tm_body(body: bytes, remote_base: str) -> bytes:
    remote = remote_base.encode("ascii", errors="ignore")
    if remote:
        body = body.replace(remote + b"/", (TM_PROXY_PREFIX + "/").encode("ascii"))
        body = body.replace(remote, TM_PROXY_PREFIX.encode("ascii"))
    body = _TM_ABS_ATTR_RE.sub(rb"\1" + (TM_PROXY_PREFIX + "/").encode("ascii"), body)
    body = _TM_CSS_URL_RE.sub(rb"\1" + (TM_PROXY_PREFIX + "/").encode("ascii"), body)
    # Avoid accidental /tm/tm/ if upstream already used the prefix string
    doubled = (TM_PROXY_PREFIX + TM_PROXY_PREFIX + "/").encode("ascii")
    body = body.replace(doubled, (TM_PROXY_PREFIX + "/").encode("ascii"))
    return body


async def handle_tm_proxy(request: web.Request) -> web.StreamResponse:
    remote_base = _task_manager_base_url()
    if not remote_base:
        return web.Response(text="Task Manager not configured", status=503)

    path = request.match_info.get("path", "").lstrip("/")
    target = f"{remote_base}/{path}" if path else f"{remote_base}/"
    if request.query_string:
        target = f"{target}?{request.query_string}"

    fwd_headers: dict[str, str] = {}
    for key, value in request.headers.items():
        lower = key.lower()
        if lower in {
            "host",
            "content-length",
            "connection",
            "transfer-encoding",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "te",
            "trailers",
            "upgrade",
        }:
            continue
        fwd_headers[key] = value

    body_in = await request.read()
    session: ClientSession = request.app["tm_http"]
    try:
        async with session.request(
            request.method,
            target,
            headers=fwd_headers,
            data=body_in if body_in else None,
            allow_redirects=False,
        ) as upstream:
            raw = await upstream.read()
            content_type = upstream.headers.get("Content-Type", "")
            if any(
                token in content_type
                for token in ("text/html", "text/css", "javascript", "json")
            ):
                raw = _rewrite_tm_body(raw, remote_base)

            out = web.Response(body=raw, status=upstream.status)
            for key, value in upstream.headers.items():
                lower = key.lower()
                if lower in {
                    "transfer-encoding",
                    "content-encoding",
                    "content-length",
                    "connection",
                    "x-frame-options",
                }:
                    continue
                if lower == "set-cookie":
                    out.headers.add("Set-Cookie", _rewrite_tm_set_cookie(value))
                    continue
                if lower == "location":
                    out.headers[key] = _rewrite_tm_location(value, remote_base)
                    continue
                if lower == "content-security-policy":
                    continue
                out.headers[key] = value
            out.headers["Content-Security-Policy"] = "frame-ancestors *"
            return out
    except Exception as exc:  # noqa: BLE001 — surface upstream failures to the iframe
        return web.Response(
            text=f"Task Manager proxy error: {exc}",
            status=502,
            content_type="text/plain",
        )


async def handle_session(request: web.Request) -> web.Response:
    env_file = os.environ.get("WFRUN_ENV_FILE", "")
    base = _task_manager_base_url()
    slug = _env_from_wfrun_file("TASK_MANAGER_SLUG")
    task_manager_url = _task_manager_url(request)
    repo_brand = _env_from_wfrun_file("REPO_BRAND")
    return web.json_response(
        {
            "mode": os.environ.get("WFRUN_MODE", ""),
            "profile": os.environ.get("WFRUN_PROFILE", "backend"),
            "root": os.environ.get("WFRUN_ROOT", ""),
            "env_file": env_file,
            "env_file_name": Path(env_file).name if env_file else "",
            "repo_brand": repo_brand,
            "task_manager_base_url": base,
            "task_manager_slug": slug,
            "task_manager_url": task_manager_url,
        }
    )


def _open_path_in_editor(path: Path) -> None:
    path_str = str(path)
    if sys.platform == "darwin":
        subprocess.Popen(["open", "-e", path_str], close_fds=True)
        return
    if sys.platform.startswith("linux"):
        subprocess.Popen(["xdg-open", path_str], close_fds=True)
        return
    os.startfile(path_str)  # type: ignore[attr-defined]


async def handle_open_env_file(_request: web.Request) -> web.Response:
    env_file = os.environ.get("WFRUN_ENV_FILE", "").strip()
    path = Path(env_file)
    if not env_file or not path.is_file():
        return web.json_response({"ok": False, "error": "Env file not found"}, status=404)

    try:
        await asyncio.to_thread(_open_path_in_editor, path)
    except OSError as exc:
        return web.json_response({"ok": False, "error": str(exc)}, status=500)

    return web.json_response({"ok": True, "path": str(path)})



async def handle_docs(request: web.Request) -> web.Response:
    root: Path = request.app["root"]
    entries = discover_docs(root)
    return web.json_response({"ok": True, "docs": [e.to_dict() for e in entries]})


async def handle_case_studies(request: web.Request) -> web.Response:
    root: Path = request.app["root"]
    entries = discover_case_studies(root)
    return web.json_response(
        {"ok": True, "docs": [e.to_dict() for e in entries]}
    )


async def handle_doc_content(request: web.Request) -> web.Response:
    root: Path = request.app["root"]
    rel = (request.query.get("path") or "").strip()
    if not rel:
        return web.json_response(
            {
                "ok": False,
                "error": {"code": "path_required", "message": "Missing path"},
            },
            status=400,
        )
    doc = read_doc(root, rel)
    if doc is None:
        return web.json_response(
            {
                "ok": False,
                "error": {"code": "not_found", "message": "Document not found"},
            },
            status=404,
        )
    return web.json_response({"ok": True, "doc": doc})


async def handle_scripts(request: web.Request) -> web.Response:
    root: Path = request.app["root"]
    entries = discover_scripts(root)
    return web.json_response([entry.to_dict() for entry in entries])


async def handle_ws_run(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse(autoclose=True, autoping=True, heartbeat=30)
    await ws.prepare(request)

    root: Path = request.app["root"]
    manager: SessionManager = request.app["session_manager"]
    script_id = request.query.get("script", "").strip()
    cols = int(request.query.get("cols", "80"))
    rows = int(request.query.get("rows", "24"))

    if not script_id:
        await ws.send_json({"type": "error", "message": "Missing script query parameter"})
        await ws.close()
        return ws

    async def send_json(payload: dict[str, object]) -> None:
        if not ws.closed:
            await ws.send_json(payload)

    async def send_bytes(data: bytes) -> None:
        if not ws.closed:
            await ws.send_bytes(data)

    session: ScriptSession | None = None
    try:
        session, _log_path = await manager.start(
            script_id, root, cols, rows, send_json, send_bytes
        )
    except ValueError as exc:
        await send_json({"type": "error", "message": str(exc)})
        await ws.close()
        return ws

    runner = session.runner

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    payload = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue
                msg_type = payload.get("type")
                if msg_type == "input":
                    data = payload.get("data", "")
                    if isinstance(data, str):
                        runner.write_input(data.encode("utf-8"))
                elif msg_type == "resize":
                    c = int(payload.get("cols", cols))
                    r = int(payload.get("rows", rows))
                    runner.resize(c, r)
            elif msg.type == WSMsgType.BINARY:
                runner.write_input(msg.data)
            elif msg.type in {WSMsgType.CLOSE, WSMsgType.ERROR}:
                break
    finally:
        await manager.stop_session(session)

    return ws


def create_app(root: Path) -> web.Application:
    app = web.Application(client_max_size=MARKETING_CLIENT_MAX_SIZE)
    app["root"] = root
    app["session_manager"] = SessionManager()

    async def _open_tm_http(application: web.Application) -> None:
        application["tm_http"] = ClientSession(timeout=_TM_PROXY_TIMEOUT)

    async def _close_tm_http(application: web.Application) -> None:
        session = application.get("tm_http")
        if session is not None and not session.closed:
            await session.close()

    app.on_startup.append(_open_tm_http)
    app.on_cleanup.append(_close_tm_http)

    app.router.add_get("/", handle_index)
    app.router.add_get("/api/session", handle_session)
    app.router.add_post("/api/open-env-file", handle_open_env_file)
    app.router.add_get("/api/scripts", handle_scripts)
    app.router.add_get("/api/docs", handle_docs)
    app.router.add_get("/api/case-studies", handle_case_studies)
    app.router.add_get("/api/docs/content", handle_doc_content)
    app.router.add_get("/api/marketing/posts", handle_marketing_posts_get)
    app.router.add_post("/api/marketing/posts", handle_marketing_posts_create)
    app.router.add_get("/api/marketing/platform-posts", handle_marketing_platform_posts)
    app.router.add_get(
        "/api/marketing/metrics/facebook",
        handle_marketing_metrics_facebook,
    )
    app.router.add_get(
        "/api/marketing/metrics/youtube",
        handle_marketing_metrics_youtube,
    )
    app.router.add_get("/api/marketing/posts/{post_id}", handle_marketing_post_get)
    app.router.add_get(
        "/api/marketing/posts/{post_id}/metrics/facebook",
        handle_marketing_post_metrics_facebook,
    )
    app.router.add_get(
        "/api/marketing/posts/{post_id}/metrics/youtube",
        handle_marketing_post_metrics_youtube,
    )
    app.router.add_get(
        "/api/marketing/youtube/playlists",
        handle_marketing_youtube_playlists,
    )
    app.router.add_route("*", TM_PROXY_PREFIX, handle_tm_proxy)
    app.router.add_route("*", TM_PROXY_PREFIX + "/{path:.*}", handle_tm_proxy)
    app.router.add_get("/ws/run", handle_ws_run)
    app.router.add_static("/static/", STATIC_DIR, show_index=False)
    return app


def main() -> None:
    root = require_wfrun()
    host = os.environ.get("WFRUN_DASHBOARD_HOST", DEFAULT_HOST).strip() or DEFAULT_HOST
    port = int(os.environ.get("WFRUN_DASHBOARD_PORT", str(DEFAULT_PORT)))

    if host not in {"127.0.0.1", "localhost"}:
        print(f"⚠️  Binding to {host} — dashboard is intended for localhost use only.")

    url = _dashboard_url(host, port)
    mode = os.environ.get("WFRUN_MODE", "local")

    print(f"🖥️  wfrun dashboard ({mode})")
    print(f"   {url}")
    tm_url = _task_manager_url()
    if tm_url:
        print(f"   Task Manager: {tm_url}")
    else:
        print(
            "   Task Manager: unset "
            "(need TASK_MANAGER_BASE_URL + TASK_MANAGER_SLUG in .env.local or .env.prod)"
        )
    print(f"   Logs: {LOGS_DIR}")
    print("   CLI wfrun remains available — this GUI is an alternative.")
    print("   Press Ctrl+C here to stop the server.")

    try:
        webbrowser.open(url)
    except OSError:
        pass

    app = create_app(root)
    web.run_app(app, host=host, port=port, print=None)


if __name__ == "__main__":
    main()
