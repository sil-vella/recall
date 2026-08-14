# dash Facebook: fetch Page post engagement + insights
"""Read engagement and (when permitted) Insights for a Facebook Page post.

Uses FACEBOOK_PAGE_ACCESS_TOKEN. Engagement summaries usually work with
pages_read_engagement. Lifetime Insights need read_insights + ANALYZE on the Page.

Used by the wfrun dashboard Marketing tab — not a day-to-day wfrun menu runner.
"""

from __future__ import annotations

import json
import urllib.parse
from datetime import datetime, timezone
from typing import Any

from publish_common import env, err_result, http_json, ok_result

GRAPH = "https://graph.facebook.com/v21.0"

# Safe public-ish engagement on the object (works for feed/photo/video with Page token).
# Do NOT request `post_id` here — Graph returns (#100) on Post nodes (compound
# `{pageId}_{postId}` ids from published_posts). Photo/video-only ids resolve
# the feed post via a separate optional field fetch below.
_ENGAGEMENT_FIELDS = (
    "id,created_time,permalink_url,status_type,message,"
    "shares,"
    "comments.summary(true).limit(0),"
    "reactions.summary(true).limit(0),"
    "likes.summary(true).limit(0)"
)

# Lifetime Page-post Insights (requires read_insights). Requested in batches so one
# unavailable/deprecated metric does not fail the whole fetch. Prefer Graph titles
# when present; UI also has friendly labels.
#
# Includes legacy impression metrics (still on v21; Meta deprecates many unique-
# reach metrics around June 2026) plus replacements `post_total_media_view_unique`
# / `post_media_view`.
_INSIGHT_BATCHES: tuple[tuple[str, ...], ...] = (
    # Reach / media views (legacy post_impressions* removed — Graph v21+ returns
    # (#100) invalid metric; use media-view replacements).
    (
        "post_total_media_view_unique",
        "post_media_view",
    ),
    # Clicks, stories, reactions
    (
        "post_clicks",
        "post_clicks_by_type",
        "post_activity_by_action_type",
        "post_activity_by_action_type_unique",
        "post_reactions_by_type_total",
        "post_reactions_like_total",
        "post_reactions_love_total",
        "post_reactions_wow_total",
        "post_reactions_haha_total",
        "post_reactions_sorry_total",
        "post_reactions_anger_total",
    ),
    # Video (zeros / omitted for non-video posts)
    (
        "post_video_views",
        "post_video_views_unique",
        "post_video_views_organic",
        "post_video_views_organic_unique",
        "post_video_views_paid",
        "post_video_views_paid_unique",
        "post_video_views_autoplayed",
        "post_video_views_clicked_to_play",
        "post_video_views_15s",
        "post_video_avg_time_watched",
        "post_video_view_time",
        "post_video_view_time_organic",
        "post_video_complete_views_organic",
        "post_video_complete_views_organic_unique",
        "post_video_complete_views_paid",
        "post_video_complete_views_paid_unique",
        "post_video_complete_views_30s_unique",
        "post_video_complete_views_30s_autoplayed",
        "post_video_complete_views_30s_clicked_to_play",
        "post_video_complete_views_30s_organic",
        "post_video_complete_views_30s_paid",
        "post_video_length",
        "post_video_social_actions_count_unique",
        "post_video_views_by_distribution_type",
        "post_video_view_time_by_distribution_type",
    ),
)

_LIST_FIELDS = (
    # Lightweight list only — no engagement summaries. Metrics/Insights load on detail.
    "id,message,story,created_time,permalink_url,status_type"
)


def facebook_object_id_from_publish_result(fb_result: dict[str, Any] | None) -> str | None:
    """Extract Graph object id from a marketing publish result envelope."""
    if not isinstance(fb_result, dict) or not fb_result.get("ok"):
        return None
    data = fb_result.get("data") if isinstance(fb_result.get("data"), dict) else {}
    oid = str(data.get("id") or "").strip()
    return oid or None


def facebook_object_id_from_post(post: dict[str, Any]) -> str | None:
    publish = post.get("publish") if isinstance(post.get("publish"), dict) else {}
    results = publish.get("results") if isinstance(publish.get("results"), dict) else {}
    fb = results.get("facebook") if isinstance(results.get("facebook"), dict) else None
    return facebook_object_id_from_publish_result(fb)


def _summary_total(node: Any) -> int | None:
    if not isinstance(node, dict):
        return None
    summary = node.get("summary") if isinstance(node.get("summary"), dict) else {}
    total = summary.get("total_count")
    if total is None:
        return None
    try:
        return int(total)
    except (TypeError, ValueError):
        return None


def _shares_count(node: Any) -> int | None:
    if not isinstance(node, dict):
        return None
    count = node.get("count")
    if count is None:
        return None
    try:
        return int(count)
    except (TypeError, ValueError):
        return None


def _resolve_media_post_id(object_id: str, *, token: str) -> str | None:
    """Best-effort `post_id` for photo/video nodes (not valid on Post objects)."""
    qs = urllib.parse.urlencode({"fields": "post_id", "access_token": token})
    status, payload, _ = http_json(
        "GET", f"{GRAPH}/{urllib.parse.quote(object_id)}?{qs}", timeout=30
    )
    if status >= 400 or not isinstance(payload, dict) or payload.get("error"):
        return None
    pid = str(payload.get("post_id") or "").strip()
    return pid or None


def _insight_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    rows = payload.get("data") if isinstance(payload.get("data"), list) else []
    return [row for row in rows if isinstance(row, dict)]


def _insight_values(payload: dict[str, Any]) -> dict[str, Any]:
    """Flatten Graph insights `data[]` into name → latest value (or map)."""
    out: dict[str, Any] = {}
    for row in _insight_rows(payload):
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        values = row.get("values") if isinstance(row.get("values"), list) else []
        if not values:
            continue
        last = values[-1] if isinstance(values[-1], dict) else {}
        value = last.get("value")
        out[name] = value
    return out


def _insight_titles(payload: dict[str, Any]) -> dict[str, str]:
    """Map metric name → Graph `title` when present."""
    out: dict[str, str] = {}
    for row in _insight_rows(payload):
        name = str(row.get("name") or "").strip()
        title = str(row.get("title") or "").strip()
        if name and title:
            out[name] = title
    return out


def _fetch_insights_metric_batch(
    insights_target: str,
    *,
    token: str,
    metrics: tuple[str, ...],
) -> tuple[dict[str, Any], dict[str, str], str | None]:
    """Return (values, titles, error_message_or_none) for one metric CSV batch."""
    if not metrics:
        return {}, {}, None
    iqs = urllib.parse.urlencode(
        {
            "metric": ",".join(metrics),
            "period": "lifetime",
            "access_token": token,
        }
    )
    istatus, ipayload, _ = http_json(
        "GET",
        f"{GRAPH}/{urllib.parse.quote(insights_target)}/insights?{iqs}",
        timeout=60,
    )
    if istatus >= 400 or not isinstance(ipayload, dict) or ipayload.get("error"):
        err = ipayload.get("error") if isinstance(ipayload, dict) else {}
        if not isinstance(err, dict):
            err = {}
        msg = str(err.get("message") or json.dumps(ipayload)[:300])
        return {}, {}, msg
    return _insight_values(ipayload), _insight_titles(ipayload), None


def _is_insights_permission_error(message: str) -> bool:
    err_l = (message or "").lower()
    return "permission" in err_l or " (#200)" in message or "analyze" in err_l


def _fetch_insights_metrics_resilient(
    insights_target: str,
    *,
    token: str,
    metrics: tuple[str, ...],
    skipped: list[str],
) -> tuple[dict[str, Any], dict[str, str], str | None]:
    """Fetch metrics; on failure binary-split so one bad name does not drop the batch."""
    if not metrics:
        return {}, {}, None
    values, titles, err = _fetch_insights_metric_batch(
        insights_target, token=token, metrics=metrics
    )
    if err is None:
        return values, titles, None
    if _is_insights_permission_error(err):
        return {}, {}, err
    if len(metrics) == 1:
        skipped.append(metrics[0])
        return {}, {}, None
    mid = len(metrics) // 2
    left_v, left_t, left_err = _fetch_insights_metrics_resilient(
        insights_target, token=token, metrics=metrics[:mid], skipped=skipped
    )
    if left_err and _is_insights_permission_error(left_err):
        return left_v, left_t, left_err
    right_v, right_t, right_err = _fetch_insights_metrics_resilient(
        insights_target, token=token, metrics=metrics[mid:], skipped=skipped
    )
    if right_err and _is_insights_permission_error(right_err):
        merged_v = {**left_v, **right_v}
        merged_t = {**left_t, **right_t}
        return merged_v, merged_t, right_err
    return {**left_v, **right_v}, {**left_t, **right_t}, None


def _fetch_full_post_insights(
    insights_target: str,
    *,
    token: str,
) -> tuple[dict[str, Any], dict[str, str], list[str]]:
    """Fetch all insight batches; binary-split on unavailable metrics."""
    values: dict[str, Any] = {}
    titles: dict[str, str] = {}
    warnings: list[str] = []
    skipped: list[str] = []

    for batch in _INSIGHT_BATCHES:
        batch_values, batch_titles, err = _fetch_insights_metrics_resilient(
            insights_target, token=token, metrics=batch, skipped=skipped
        )
        values.update(batch_values)
        titles.update(batch_titles)
        if err and _is_insights_permission_error(err):
            warnings.append(
                "insights_unavailable — grant read_insights (and Page ANALYZE), "
                f"then re-mint the Page token. Graph: {err[:180]}"
            )
            return values, titles, warnings

    if not values:
        # Post /insights often returns HTTP 200 with data=[] when read_insights
        # is missing. Probe video_insights for a clear permission error.
        perm = _probe_read_insights_missing(insights_target, token=token)
        if perm:
            warnings.append(perm)
        elif skipped:
            warnings.append(
                "insights_empty — metrics not ready yet for this post "
                "(or Page ANALYZE / read_insights still missing after re-mint)"
            )
        else:
            warnings.append(
                "insights_empty — no Insights rows returned. Remint Page token "
                "with read_insights + Page ANALYZE, then retry."
            )
    elif skipped:
        sample = ", ".join(skipped[:6])
        more = f" (+{len(skipped) - 6} more)" if len(skipped) > 6 else ""
        warnings.append(
            f"insights_partial — skipped unavailable metrics: {sample}{more}"
        )

    return values, titles, warnings


def _probe_read_insights_missing(insights_target: str, *, token: str) -> str | None:
    """Return a clear warning when Graph confirms read_insights is missing."""
    # Prefer a video id from the post attachment when present (Reels / video posts).
    video_id = _attachment_video_id(insights_target, token=token)
    targets: list[tuple[str, str]] = []
    if video_id:
        targets.append((video_id, "video_insights"))
    targets.append((insights_target, "insights"))

    for oid, edge in targets:
        qs = urllib.parse.urlencode(
            {
                "metric": (
                    "total_video_views"
                    if edge == "video_insights"
                    else "post_clicks"
                ),
                "period": "lifetime",
                "access_token": token,
            }
        )
        status, payload, _ = http_json(
            "GET",
            f"{GRAPH}/{urllib.parse.quote(oid)}/{edge}?{qs}",
            timeout=45,
        )
        err = payload.get("error") if isinstance(payload, dict) else {}
        if not isinstance(err, dict):
            err = {}
        msg = str(err.get("message") or "")
        if status == 403 or "read_insights" in msg.lower() or err.get("code") == 200:
            return (
                "insights_unavailable — Page token is missing read_insights. "
                "Re-auth in Graph API Explorer with read_insights (and Page ANALYZE), "
                "resolve a new Page token, update FACEBOOK_PAGE_ACCESS_TOKEN. "
                "Note: fb_exchange_token / extend alone cannot add this permission."
            )
    return None


def _attachment_video_id(post_id: str, *, token: str) -> str | None:
    qs = urllib.parse.urlencode(
        {
            "fields": "attachments{media_type,target}",
            "access_token": token,
        }
    )
    status, payload, _ = http_json(
        "GET", f"{GRAPH}/{urllib.parse.quote(post_id)}?{qs}", timeout=30
    )
    if status >= 400 or not isinstance(payload, dict) or payload.get("error"):
        return None
    atts = payload.get("attachments") if isinstance(payload.get("attachments"), dict) else {}
    rows = atts.get("data") if isinstance(atts.get("data"), list) else []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if str(row.get("media_type") or "").lower() not in {"video", "reel"}:
            continue
        target = row.get("target") if isinstance(row.get("target"), dict) else {}
        vid = str(target.get("id") or "").strip()
        if vid:
            return vid
    return None


def fetch_facebook_post_metrics(
    object_id: str,
    *,
    page_token: str | None = None,
    page_id: str | None = None,
) -> dict[str, Any]:
    """Return engagement + full lifetime Insights for a Page post / photo / video id."""
    oid = (object_id or "").strip()
    if not oid:
        return err_result("facebook_object_id_required", "Facebook object id is required")

    token = (page_token or env("FACEBOOK_PAGE_ACCESS_TOKEN")).strip()
    page = (page_id or env("FACEBOOK_PAGE_ID")).strip()
    if not token:
        return err_result(
            "missing_facebook_credentials",
            "Need FACEBOOK_PAGE_ACCESS_TOKEN",
        )

    warnings: list[str] = []
    fetched_at = datetime.now(timezone.utc).isoformat()

    # 1) Object + engagement summaries
    qs = urllib.parse.urlencode(
        {"fields": _ENGAGEMENT_FIELDS, "access_token": token}
    )
    status, payload, _ = http_json(
        "GET", f"{GRAPH}/{urllib.parse.quote(oid)}?{qs}", timeout=45
    )
    if status >= 400 or payload.get("error"):
        err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        msg = str(err.get("message") or json.dumps(payload)[:400])
        code = "facebook_metrics_failed"
        if "permission" in msg.lower() or err.get("code") == 200:
            code = "facebook_metrics_permission"
        return err_result(code, f"HTTP {status}: {msg}")

    engagement = {
        "reactions": _summary_total(payload.get("reactions")),
        "likes": _summary_total(payload.get("likes")),
        "comments": _summary_total(payload.get("comments")),
        "shares": _shares_count(payload.get("shares")),
    }

    # Insights want a Page post id (`{page}_{post}`). Published posts already
    # have that shape. Bare photo/video object ids may expose `post_id` when
    # requested alone; otherwise fall back to `{page}_{oid}`.
    insights_target = oid
    if "_" not in oid:
        resolved = _resolve_media_post_id(oid, token=token)
        if resolved:
            insights_target = resolved
        elif page and oid.isdigit() and page.isdigit():
            insights_target = f"{page}_{oid}"

    permalink = str(payload.get("permalink_url") or "").strip() or None
    created_time = str(payload.get("created_time") or "").strip() or None

    # 2) Full Insights (optional — may fail without read_insights)
    insights, insight_titles, insight_warnings = _fetch_full_post_insights(
        insights_target, token=token
    )
    warnings.extend(insight_warnings)

    return ok_result(
        {
            "platform": "facebook",
            "object_id": oid,
            "insights_object_id": insights_target,
            "kind": str(payload.get("status_type") or "").strip() or None,
            "permalink_url": permalink,
            "created_time": created_time,
            "fetched_at": fetched_at,
            "engagement": engagement,
            "insights": insights or None,
            "insight_titles": insight_titles or None,
            "warnings": warnings,
        }
    )


def _preview_text(row: dict[str, Any], *, max_len: int = 140) -> str:
    for key in ("message", "story"):
        text = str(row.get(key) or "").strip()
        if text:
            if len(text) > max_len:
                return text[: max_len - 1].rstrip() + "…"
            return text
    return "(no text)"


def _list_item_from_row(row: dict[str, Any]) -> dict[str, Any]:
    oid = str(row.get("id") or "").strip()
    return {
        "id": oid,
        "platform": "facebook",
        "title": _preview_text(row),
        "created_time": str(row.get("created_time") or "").strip() or None,
        "permalink_url": str(row.get("permalink_url") or "").strip() or None,
        "kind": str(row.get("status_type") or "").strip() or None,
    }


def list_facebook_page_posts(
    *,
    limit: int = 5,
    after: str | None = None,
    page_token: str | None = None,
    page_id: str | None = None,
) -> dict[str, Any]:
    """List recent posts published by the Page (not visitor feed noise)."""
    token = (page_token or env("FACEBOOK_PAGE_ACCESS_TOKEN")).strip()
    page = (page_id or env("FACEBOOK_PAGE_ID")).strip()
    if not token or not page:
        return err_result(
            "missing_facebook_credentials",
            "Need FACEBOOK_PAGE_ID and FACEBOOK_PAGE_ACCESS_TOKEN",
        )

    try:
        lim = max(1, min(int(limit), 25))
    except (TypeError, ValueError):
        lim = 5

    params: dict[str, str] = {
        "fields": _LIST_FIELDS,
        "limit": str(lim),
        "access_token": token,
    }
    cursor = (after or "").strip()
    if cursor:
        params["after"] = cursor

    qs = urllib.parse.urlencode(params)
    # published_posts = Page-authored content; /feed also includes visitor posts.
    status, payload, _ = http_json(
        "GET",
        f"{GRAPH}/{urllib.parse.quote(page)}/published_posts?{qs}",
        timeout=60,
    )
    if status >= 400 or payload.get("error"):
        err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        msg = str(err.get("message") or json.dumps(payload)[:400])
        code = "facebook_list_failed"
        if "permission" in msg.lower() or err.get("code") == 200:
            code = "facebook_list_permission"
        return err_result(code, f"HTTP {status}: {msg}")

    rows = payload.get("data") if isinstance(payload.get("data"), list) else []
    items = [
        _list_item_from_row(row)
        for row in rows
        if isinstance(row, dict) and str(row.get("id") or "").strip()
    ]

    paging = payload.get("paging") if isinstance(payload.get("paging"), dict) else {}
    cursors = paging.get("cursors") if isinstance(paging.get("cursors"), dict) else {}
    next_after = str(cursors.get("after") or "").strip() or None
    has_more = bool(paging.get("next") and next_after)

    return ok_result(
        {
            "platform": "facebook",
            "page_id": page,
            "posts": items,
            "paging": {"after": next_after if has_more else None, "has_more": has_more},
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }
    )
