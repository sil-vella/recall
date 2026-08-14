# dash YouTube: list channel videos + fetch statistics
"""List recent channel uploads and fetch per-video statistics (YouTube Data API v3).

Uses YOUTUBE_CLIENT_ID / YOUTUBE_CLIENT_SECRET / YOUTUBE_REFRESH_TOKEN (same as publish).
Optional YOUTUBE_CHANNEL_ID to pin the Brand channel.

List is lightweight (no statistics). Metrics load only for a selected video id.

Used by the wfrun dashboard Marketing tab — not a day-to-day wfrun menu runner.
"""

from __future__ import annotations

import json
import urllib.parse
from datetime import datetime, timezone
from typing import Any

from publish_common import env, err_result, http_json, ok_result

TOKEN_URI = "https://oauth2.googleapis.com/token"
CHANNELS_URI = "https://www.googleapis.com/youtube/v3/channels"
PLAYLIST_ITEMS_URI = "https://www.googleapis.com/youtube/v3/playlistItems"
VIDEOS_URI = "https://www.googleapis.com/youtube/v3/videos"


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
    if status >= 400 or not isinstance(payload, dict):
        raise RuntimeError(f"youtube_token_refresh_failed: {payload!r}")
    access = str(payload.get("access_token") or "").strip()
    if not access:
        raise RuntimeError("youtube_token_refresh_failed: no access_token")
    return access


def _auth_headers(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


def _api_get(url: str, access_token: str) -> tuple[int, dict[str, Any]]:
    status, payload, _ = http_json(
        "GET", url, headers=_auth_headers(access_token), timeout=60
    )
    if not isinstance(payload, dict):
        payload = {"error": {"message": str(payload)[:300]}}
    return status, payload


def _yt_error(payload: dict[str, Any], *, default_code: str) -> dict[str, Any]:
    err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
    message = str(err.get("message") or json.dumps(payload)[:400])
    code = default_code
    lower = message.lower()
    if "invalid_grant" in lower or "deleted_client" in lower:
        code = "youtube_reauth_required"
    elif _status_is_auth(err):
        code = "youtube_reauth_required"
    return err_result(code, message)


def _status_is_auth(err: dict[str, Any]) -> bool:
    status = str(err.get("status") or "").upper()
    reason = ""
    errors = err.get("errors") if isinstance(err.get("errors"), list) else []
    if errors and isinstance(errors[0], dict):
        reason = str(errors[0].get("reason") or "")
    return status in {"UNAUTHENTICATED", "PERMISSION_DENIED"} or reason in {
        "authError",
        "insufficientPermissions",
        "forbidden",
    }


def youtube_video_id_from_publish_result(yt_result: dict[str, Any] | None) -> str | None:
    if not isinstance(yt_result, dict) or not yt_result.get("ok"):
        return None
    data = yt_result.get("data") if isinstance(yt_result.get("data"), dict) else {}
    vid = str(data.get("id") or data.get("video_id") or "").strip()
    return vid or None


def youtube_video_id_from_post(post: dict[str, Any]) -> str | None:
    publish = post.get("publish") if isinstance(post.get("publish"), dict) else {}
    results = publish.get("results") if isinstance(publish.get("results"), dict) else {}
    yt = results.get("youtube") if isinstance(results.get("youtube"), dict) else None
    return youtube_video_id_from_publish_result(yt)


def _resolve_uploads_playlist_id(access_token: str) -> tuple[str | None, str | None, dict[str, Any] | None]:
    """Return (uploads_playlist_id, channel_id, error_result)."""
    channel_id = env("YOUTUBE_CHANNEL_ID").strip()
    params: dict[str, str] = {"part": "contentDetails,snippet"}
    if channel_id:
        params["id"] = channel_id
    else:
        params["mine"] = "true"
    url = f"{CHANNELS_URI}?{urllib.parse.urlencode(params)}"
    status, payload = _api_get(url, access_token)
    if status >= 400 or payload.get("error"):
        return None, None, _yt_error(payload, default_code="youtube_channel_failed")
    items = payload.get("items") if isinstance(payload.get("items"), list) else []
    if not items or not isinstance(items[0], dict):
        return None, None, err_result(
            "youtube_channel_missing",
            "No YouTube channel returned — re-auth as Brand Account "
            "(youtube_oauth_get_refresh_token.py).",
        )
    item = items[0]
    cid = str(item.get("id") or "").strip() or None
    details = item.get("contentDetails") if isinstance(item.get("contentDetails"), dict) else {}
    related = (
        details.get("relatedPlaylists")
        if isinstance(details.get("relatedPlaylists"), dict)
        else {}
    )
    uploads = str(related.get("uploads") or "").strip() or None
    if not uploads:
        return None, cid, err_result(
            "youtube_uploads_playlist_missing",
            "Channel has no uploads playlist id",
        )
    return uploads, cid, None


def _preview_title(snippet: dict[str, Any], *, max_len: int = 140) -> str:
    title = str(snippet.get("title") or "").strip()
    if not title:
        return "(untitled)"
    if len(title) > max_len:
        return title[: max_len - 1].rstrip() + "…"
    return title


def list_youtube_channel_videos(
    *,
    limit: int = 5,
    page_token: str | None = None,
) -> dict[str, Any]:
    """List recent uploads (lightweight — no statistics)."""
    try:
        access = _refresh_access_token()
    except RuntimeError as exc:
        msg = str(exc)
        code = "missing_youtube_credentials"
        if "invalid_grant" in msg.lower() or "reauth" in msg.lower():
            code = "youtube_reauth_required"
        return err_result(code, msg)

    try:
        lim = max(1, min(int(limit), 25))
    except (TypeError, ValueError):
        lim = 5

    uploads, channel_id, err = _resolve_uploads_playlist_id(access)
    if err is not None:
        return err
    assert uploads is not None

    params: dict[str, str] = {
        "part": "snippet,contentDetails",
        "playlistId": uploads,
        "maxResults": str(lim),
    }
    cursor = (page_token or "").strip()
    if cursor:
        params["pageToken"] = cursor

    url = f"{PLAYLIST_ITEMS_URI}?{urllib.parse.urlencode(params)}"
    status, payload = _api_get(url, access)
    if status >= 400 or payload.get("error"):
        return _yt_error(payload, default_code="youtube_list_failed")

    rows = payload.get("items") if isinstance(payload.get("items"), list) else []
    posts: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        snippet = row.get("snippet") if isinstance(row.get("snippet"), dict) else {}
        content = (
            row.get("contentDetails")
            if isinstance(row.get("contentDetails"), dict)
            else {}
        )
        vid = str(content.get("videoId") or "").strip()
        if not vid:
            resource = (
                snippet.get("resourceId")
                if isinstance(snippet.get("resourceId"), dict)
                else {}
            )
            vid = str(resource.get("videoId") or "").strip()
        if not vid:
            continue
        published = str(
            content.get("videoPublishedAt")
            or snippet.get("publishedAt")
            or ""
        ).strip() or None
        posts.append(
            {
                "id": vid,
                "platform": "youtube",
                "title": _preview_title(snippet),
                "created_time": published,
                "permalink_url": f"https://www.youtube.com/watch?v={vid}",
                "kind": "video",
            }
        )

    next_token = str(payload.get("nextPageToken") or "").strip() or None
    return ok_result(
        {
            "platform": "youtube",
            "channel_id": channel_id,
            "posts": posts,
            "paging": {
                "after": next_token,
                "has_more": bool(next_token),
            },
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }
    )


def _int_or_none(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def fetch_youtube_video_metrics(video_id: str) -> dict[str, Any]:
    """Return snippet + statistics for one video id (detail screen)."""
    vid = (video_id or "").strip()
    if not vid:
        return err_result("youtube_video_id_required", "YouTube video id is required")

    try:
        access = _refresh_access_token()
    except RuntimeError as exc:
        msg = str(exc)
        code = "missing_youtube_credentials"
        if "invalid_grant" in msg.lower():
            code = "youtube_reauth_required"
        return err_result(code, msg)

    params = {
        "part": "snippet,statistics,contentDetails,status",
        "id": vid,
    }
    url = f"{VIDEOS_URI}?{urllib.parse.urlencode(params)}"
    status, payload = _api_get(url, access)
    if status >= 400 or payload.get("error"):
        return _yt_error(payload, default_code="youtube_metrics_failed")

    items = payload.get("items") if isinstance(payload.get("items"), list) else []
    if not items or not isinstance(items[0], dict):
        return err_result(
            "youtube_video_not_found",
            f"No video found for id {vid}",
        )

    item = items[0]
    snippet = item.get("snippet") if isinstance(item.get("snippet"), dict) else {}
    stats = item.get("statistics") if isinstance(item.get("statistics"), dict) else {}
    details = (
        item.get("contentDetails")
        if isinstance(item.get("contentDetails"), dict)
        else {}
    )
    st = item.get("status") if isinstance(item.get("status"), dict) else {}

    engagement = {
        "views": _int_or_none(stats.get("viewCount")),
        "likes": _int_or_none(stats.get("likeCount")),
        "comments": _int_or_none(stats.get("commentCount")),
        "favorites": _int_or_none(stats.get("favoriteCount")),
    }
    insights = {
        "viewCount": engagement["views"],
        "likeCount": engagement["likes"],
        "commentCount": engagement["comments"],
        "favoriteCount": engagement["favorites"],
        "duration": str(details.get("duration") or "").strip() or None,
        "definition": str(details.get("definition") or "").strip() or None,
        "privacyStatus": str(st.get("privacyStatus") or "").strip() or None,
        "madeForKids": st.get("madeForKids"),
        "publishedAt": str(snippet.get("publishedAt") or "").strip() or None,
        "channelTitle": str(snippet.get("channelTitle") or "").strip() or None,
        "categoryId": str(snippet.get("categoryId") or "").strip() or None,
    }
    # Drop nulls for cleaner UI
    insights = {k: v for k, v in insights.items() if v is not None}

    return ok_result(
        {
            "platform": "youtube",
            "object_id": vid,
            "kind": "video",
            "title": _preview_title(snippet),
            "permalink_url": f"https://www.youtube.com/watch?v={vid}",
            "created_time": str(snippet.get("publishedAt") or "").strip() or None,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
            "engagement": engagement,
            "insights": insights,
            "warnings": [],
        }
    )
