#!/usr/bin/env python3
# dash Facebook: publish Page feed / link post
"""Publish a text (or link) post to FACEBOOK_PAGE_ID via Graph API.

Caption = title + newline + description (optional hashtags appended).

Usage:
  wfrun → automation/marketing/facebook_publish_post.py --title "Hi" --description "Body"
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
from pathlib import Path
from typing import Any

from publish_common import (
    append_hashtags,
    env,
    err_result,
    http_json,
    local_datetime_to_unix,
    merge_caption,
    ok_result,
    require_wfrun,
)

GRAPH = "https://graph.facebook.com/v21.0"


def publish_facebook_post(
    *,
    title: str,
    description: str = "",
    hashtags: list[str] | None = None,
    link: str = "",
    schedule_at: str | None = None,
    page_id: str | None = None,
    page_token: str | None = None,
    media_path: str | Path | None = None,
) -> dict[str, Any]:
    """Post to Page feed (or photos/videos if media_path is set)."""
    page_id = (page_id or env("FACEBOOK_PAGE_ID")).strip()
    page_token = (page_token or env("FACEBOOK_PAGE_ACCESS_TOKEN")).strip()
    if not page_id or not page_token:
        return err_result(
            "missing_facebook_credentials",
            "Need FACEBOOK_PAGE_ID and FACEBOOK_PAGE_ACCESS_TOKEN",
        )

    message = append_hashtags(merge_caption(title, description), hashtags)
    if not message and not link and not media_path:
        return err_result("facebook_empty_post", "Facebook post needs message, link, or media")

    form: dict[str, str] = {"access_token": page_token}
    if message:
        form["message"] = message
    if link:
        form["link"] = link.strip()

    if schedule_at:
        try:
            form["published"] = "false"
            form["scheduled_publish_time"] = str(local_datetime_to_unix(schedule_at))
        except ValueError as exc:
            return err_result("facebook_bad_schedule", f"Invalid schedule_at: {exc}")

    path = Path(media_path).expanduser().resolve() if media_path else None
    if path is not None:
        if not path.is_file():
            return err_result("facebook_media_missing", f"Media not found: {path}")
        # Prefer photo/video endpoints when a file is attached
        suffix = path.suffix.lower()
        if suffix in {".mp4", ".mov", ".avi", ".mkv", ".webm"}:
            return _publish_video(page_id, page_token, path, message, schedule_at)
        return _publish_photo(page_id, page_token, path, message, schedule_at)

    url = f"{GRAPH}/{urllib.parse.quote(page_id)}/feed"
    status, payload, _ = http_json("POST", url, form=form, timeout=60)
    if status >= 400 or payload.get("error"):
        err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        msg = err.get("message") or json.dumps(payload)[:400]
        return err_result("facebook_publish_failed", f"HTTP {status}: {msg}")
    post_id = str(payload.get("id") or "").strip()
    return ok_result({"platform": "facebook", "id": post_id, "kind": "feed"})


def _multipart_body(
    fields: dict[str, str], file_field: str, path: Path, content_type: str
) -> tuple[bytes, str]:
    boundary = "----wfMarketingBoundary7MA4YWxkTrZu0gW"
    lines: list[bytes] = []
    for key, value in fields.items():
        lines.append(f"--{boundary}\r\n".encode())
        lines.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        lines.append(value.encode("utf-8") + b"\r\n")
    lines.append(f"--{boundary}\r\n".encode())
    lines.append(
        (
            f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{path.name}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
    )
    lines.append(path.read_bytes())
    lines.append(b"\r\n")
    lines.append(f"--{boundary}--\r\n".encode())
    return b"".join(lines), f"multipart/form-data; boundary={boundary}"


def _publish_photo(
    page_id: str,
    page_token: str,
    path: Path,
    message: str,
    schedule_at: str | None,
) -> dict[str, Any]:
    fields: dict[str, str] = {"access_token": page_token}
    if message:
        fields["caption"] = message
    if schedule_at:
        try:
            fields["published"] = "false"
            fields["scheduled_publish_time"] = str(local_datetime_to_unix(schedule_at))
        except ValueError as exc:
            return err_result("facebook_bad_schedule", f"Invalid schedule_at: {exc}")
    body, ctype = _multipart_body(fields, "source", path, "image/jpeg")
    url = f"{GRAPH}/{urllib.parse.quote(page_id)}/photos"
    status, payload, _ = http_json(
        "POST",
        url,
        headers={"Content-Type": ctype},
        body=body,
        timeout=180,
    )
    if status >= 400 or payload.get("error"):
        err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        msg = err.get("message") or json.dumps(payload)[:400]
        return err_result("facebook_publish_failed", f"HTTP {status}: {msg}")
    return ok_result(
        {
            "platform": "facebook",
            "id": str(payload.get("id") or payload.get("post_id") or ""),
            "kind": "photo",
        }
    )


def _publish_video(
    page_id: str,
    page_token: str,
    path: Path,
    message: str,
    schedule_at: str | None,
) -> dict[str, Any]:
    fields: dict[str, str] = {"access_token": page_token}
    if message:
        fields["description"] = message
    if schedule_at:
        try:
            fields["published"] = "false"
            fields["scheduled_publish_time"] = str(local_datetime_to_unix(schedule_at))
        except ValueError as exc:
            return err_result("facebook_bad_schedule", f"Invalid schedule_at: {exc}")
    body, ctype = _multipart_body(fields, "source", path, "video/mp4")
    url = f"{GRAPH}/{urllib.parse.quote(page_id)}/videos"
    status, payload, _ = http_json(
        "POST",
        url,
        headers={"Content-Type": ctype},
        body=body,
        timeout=600,
    )
    if status >= 400 or payload.get("error"):
        err = payload.get("error") if isinstance(payload.get("error"), dict) else {}
        msg = err.get("message") or json.dumps(payload)[:400]
        return err_result("facebook_publish_failed", f"HTTP {status}: {msg}")
    return ok_result(
        {
            "platform": "facebook",
            "id": str(payload.get("id") or ""),
            "kind": "video",
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish a Facebook Page post.")
    parser.add_argument("--title", required=True)
    parser.add_argument("--description", default="")
    parser.add_argument("--link", default="")
    parser.add_argument("--schedule-at", default="")
    parser.add_argument("--media", default="")
    parser.add_argument("--hashtags", default="", help="Comma-separated hashtags")
    args = parser.parse_args()
    try:
        require_wfrun()
    except RuntimeError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    tags = [t.strip() for t in args.hashtags.split(",") if t.strip()]
    result = publish_facebook_post(
        title=args.title,
        description=args.description,
        hashtags=tags,
        link=args.link,
        schedule_at=args.schedule_at or None,
        media_path=args.media or None,
    )
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
