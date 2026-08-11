#!/usr/bin/env python3
# dash rop01 cron: post next Hostinger marketing video to FB/YT/TT
"""Cron social auto-post (runs on rop01; excluded from wfrun dashboard).

Reads Hostinger queue via SSH alias mixta_mt:
  ~/rop01/marketing/<product>/videos/video_***/
  ~/rop01/marketing/logs/<YYYYMMDDTHHMMSS>_<product>.log

Rotation:
  - Newest rotation log filename → last product; pick next product (wrap).
  - Empty videos/ → write empty_queue log, advance to next product (same run).
  - Publish failure → no rotation log, no delete (retry same product next cron).
  - Full success → delete remote video_***, write success log, prune to last 3 logs.

Media: latest 00renders/render_00*.mp4. Caption from post_data.json
(defaults: all three platforms; title falls back to video folder name).

Usage (on rop01):
  # load product env first, or:
  python3 automation/marketing/cron_social_auto_post.py --env-file /path/to/.env.prod
  python3 automation/marketing/cron_social_auto_post.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

# Allow running as a file path (sys.path[0] = this dir)
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from facebook_publish_post import publish_facebook_post
from publish_common import env
from tiktok_publish_video import publish_tiktok_video
from youtube_publish_video import publish_youtube_video

SSH_HOST_DEFAULT = "mixta_mt"
REMOTE_MARKETING_DEFAULT = "/home/u877877481/rop01/marketing"

# video_008 or video_008(would_u_play_joker) — sort key = digits after video_
VIDEO_RE = re.compile(r"^video_(\d+)(.*)$")
RENDER_RE = re.compile(r"^render_(\d+)\.mp4$", re.I)
LOG_NAME_RE = re.compile(r"^(\d{8}T\d{6})_([A-Za-z0-9_-]+)\.log$")
PRODUCT_RE = re.compile(r"^[A-Za-z0-9_-]+$")

DEFAULT_PLATFORMS = ("facebook", "youtube", "tiktok")

# Set by main() so failure helpers know dry-run / context
_DRY_RUN = False
_ALERT_SENT = False


def _load_env_file(path: Path) -> None:
    """Load KEY=VAL into os.environ (does not override existing non-empty)."""
    if not path.is_file():
        raise FileNotFoundError(f"env file not found: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        if key and not os.environ.get(key, "").strip():
            os.environ[key] = val


def _fail_mail_to() -> str:
    return (
        env("MARKETING_FAIL_MAIL_TO")
        or os.environ.get("MARKETING_FAIL_MAIL_TO", "")
        or env("BACKUP_FAIL_MAIL_TO")
        or os.environ.get("BACKUP_FAIL_MAIL_TO", "")
    ).strip()


def _alerts_enabled() -> bool:
    raw = (
        env("MARKETING_ALERT_ENABLED")
        or os.environ.get("MARKETING_ALERT_ENABLED", "1")
    ).strip().lower()
    return raw not in {"0", "false", "no", "off"}


def _send_failure_alert(subject: str, body: str) -> None:
    """SMTP failure mail — same shape as /opt/backups/scripts/alert_email.sh."""
    global _ALERT_SENT
    if _DRY_RUN:
        print(f"[dry-run] would email subject={subject!r}")
        return
    if _ALERT_SENT:
        return
    if not _alerts_enabled():
        print("alerts disabled (MARKETING_ALERT_ENABLED=0)", file=sys.stderr)
        return

    host = (env("MAIL_SMTP_HOST") or os.environ.get("MAIL_SMTP_HOST", "")).strip()
    port_s = (env("MAIL_SMTP_PORT") or os.environ.get("MAIL_SMTP_PORT", "465")).strip()
    encrypt = (
        env("MAIL_SMTP_ENCRYPT") or os.environ.get("MAIL_SMTP_ENCRYPT", "ssl")
    ).strip().lower() or "ssl"
    user = (env("MAIL_SMTP_USER") or os.environ.get("MAIL_SMTP_USER", "")).strip()
    password = env("MAIL_SMTP_PASSWORD") or os.environ.get("MAIL_SMTP_PASSWORD", "")
    mail_from = (env("MAIL_FROM") or os.environ.get("MAIL_FROM", "")).strip()
    from_name = (
        env("MAIL_FROM_NAME") or os.environ.get("MAIL_FROM_NAME", "") or "ReignOfPlay"
    ).strip()
    mail_to = _fail_mail_to()

    missing = [
        name
        for name, val in [
            ("MAIL_SMTP_HOST", host),
            ("MAIL_SMTP_PORT", port_s),
            ("MAIL_SMTP_USER", user),
            ("MAIL_SMTP_PASSWORD", password),
            ("MAIL_FROM", mail_from),
            ("MARKETING_FAIL_MAIL_TO/BACKUP_FAIL_MAIL_TO", mail_to),
        ]
        if not val
    ]
    if missing:
        print(
            f"WARN alert not sent — missing {', '.join(missing)}",
            file=sys.stderr,
        )
        return

    try:
        import smtplib
        import ssl
        from email.message import EmailMessage

        port = int(port_s)
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = f"{from_name} <{mail_from}>" if from_name else mail_from
        msg["To"] = mail_to
        msg.set_content(body or subject)

        if encrypt == "ssl":
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, context=context) as smtp:
                smtp.login(user, password)
                smtp.send_message(msg)
        elif encrypt in {"tls", "starttls"}:
            context = ssl.create_default_context()
            with smtplib.SMTP(host, port) as smtp:
                smtp.starttls(context=context)
                smtp.login(user, password)
                smtp.send_message(msg)
        else:
            print(f"WARN unsupported MAIL_SMTP_ENCRYPT={encrypt}", file=sys.stderr)
            return
        _ALERT_SENT = True
        print(f"alert emailed to {mail_to} subject={subject!r}")
    except Exception as exc:  # noqa: BLE001 — never mask original failure
        print(f"WARN alert email failed: {exc}", file=sys.stderr)


def _ssh_host() -> str:
    return (env("MARKETING_SSH_HOST") or os.environ.get("MARKETING_SSH_HOST") or SSH_HOST_DEFAULT).strip()


def _remote_root() -> str:
    return (
        env("MARKETING_REMOTE_ROOT")
        or os.environ.get("MARKETING_REMOTE_ROOT")
        or REMOTE_MARKETING_DEFAULT
    ).rstrip("/")


def _ssh(remote_cmd: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=30",
            _ssh_host(),
            remote_cmd,
        ],
        check=check,
        text=True,
        capture_output=True,
    )


def _die(msg: str, code: int = 1) -> None:
    print(f"ERROR {msg}", file=sys.stderr)
    _send_failure_alert("rop01 marketing FAILED", msg)
    raise SystemExit(code)


def _video_index(name: str) -> int | None:
    m = VIDEO_RE.match(name)
    return int(m.group(1)) if m else None


def _render_index(name: str) -> int | None:
    m = RENDER_RE.match(name)
    return int(m.group(1)) if m else None


def _now_stamp() -> str:
    return datetime.now().strftime("%Y%m%dT%H%M%S")


def _list_products() -> list[str]:
    root = _remote_root()
    proc = _ssh(f"mkdir -p {root}/logs; ls -1 {root}", check=False)
    if proc.returncode != 0:
        _die(f"list products failed: {(proc.stderr or proc.stdout or '').strip()}")
    out: list[str] = []
    for line in (proc.stdout or "").splitlines():
        name = line.strip()
        if not name or name == "logs":
            continue
        if PRODUCT_RE.fullmatch(name):
            out.append(name)
    out.sort()
    return out


def _list_rotation_logs() -> list[tuple[str, str, str]]:
    """Return [(filename, stamp, product), ...] newest first."""
    root = _remote_root()
    proc = _ssh(f"ls -1t {root}/logs 2>/dev/null", check=False)
    rows: list[tuple[str, str, str]] = []
    for line in (proc.stdout or "").splitlines():
        name = line.strip()
        m = LOG_NAME_RE.match(name)
        if not m:
            continue
        rows.append((name, m.group(1), m.group(2)))
    return rows


def _last_product_from_logs() -> str | None:
    logs = _list_rotation_logs()
    return logs[0][2] if logs else None


def _next_product(products: list[str], last: str | None) -> str | None:
    if not products:
        return None
    if last is None or last not in products:
        return products[0]
    idx = products.index(last)
    return products[(idx + 1) % len(products)]


def _list_remote_videos(product: str) -> list[str]:
    path = f"{_remote_root()}/{product}/videos"
    proc = _ssh(
        f"mkdir -p {shlex.quote(path)}; ls -1 {shlex.quote(path)}",
        check=False,
    )
    if proc.returncode != 0:
        _die(f"list videos failed for {product}: {(proc.stderr or '').strip()}")
    found: list[tuple[int, str]] = []
    for line in (proc.stdout or "").splitlines():
        name = line.strip()
        idx = _video_index(name)
        if idx is not None:
            found.append((idx, name))
    found.sort(key=lambda t: (t[0], t[1]))
    return [n for _, n in found]


def _write_remote_log(product: str, body: str, *, dry_run: bool) -> str:
    stamp = _now_stamp()
    name = f"{stamp}_{product}.log"
    remote_path = f"{_remote_root()}/logs/{name}"
    if dry_run:
        print(f"[dry-run] would write log {remote_path}")
        print(body)
        return name
    # Prefer stdin → remote file (avoid shell-quoting body)
    proc = subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=30",
            _ssh_host(),
            f"cat > {remote_path}",
        ],
        input=body if body.endswith("\n") else body + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        _die(f"write log failed: {(proc.stderr or proc.stdout or '').strip()}")
    return name


def _prune_logs(*, dry_run: bool, keep: int = 3) -> None:
    logs = _list_rotation_logs()  # newest first
    drop = logs[keep:]
    if not drop:
        return
    root = _remote_root()
    for name, _, _ in drop:
        remote = f"{root}/logs/{name}"
        if dry_run:
            print(f"[dry-run] would prune {remote}")
            continue
        proc = _ssh(f"rm -f {remote}", check=False)
        if proc.returncode != 0:
            print(f"WARN prune failed {name}: {(proc.stderr or '').strip()}", file=sys.stderr)


def _delete_remote_video(product: str, video_name: str, *, dry_run: bool) -> None:
    remote = f"{_remote_root()}/{product}/videos/{video_name}"
    if dry_run:
        print(f"[dry-run] would delete {remote}")
        return
    proc = _ssh(f"rm -rf -- {shlex.quote(remote)}", check=False)
    if proc.returncode != 0:
        _die(f"delete failed {remote}: {(proc.stderr or '').strip()}")


def _pull_video_dir(product: str, video_name: str, dest_parent: Path) -> Path:
    """Pull remote video_* (suffix allowed) into dest_parent/video_*; return local path."""
    remote_parent = f"{_remote_root()}/{product}/videos"
    local = dest_parent / video_name
    local.mkdir(parents=True, exist_ok=True)
    host = _ssh_host()
    # tar|ssh so names with () are safe
    ssh_proc = subprocess.Popen(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=30",
            host,
            f"tar -C {shlex.quote(remote_parent)} -cf - {shlex.quote(video_name)}",
        ],
        stdout=subprocess.PIPE,
    )
    assert ssh_proc.stdout is not None
    tar_proc = subprocess.run(
        ["tar", "-C", str(dest_parent), "-xf", "-"],
        stdin=ssh_proc.stdout,
        capture_output=True,
        text=True,
    )
    ssh_proc.stdout.close()
    ssh_rc = ssh_proc.wait()
    if ssh_rc != 0 or tar_proc.returncode != 0:
        err = (tar_proc.stderr or tar_proc.stdout or "").strip()
        _die(f"pull failed {video_name}: {err or ssh_rc or tar_proc.returncode}")
    if not local.is_dir():
        _die(f"pull missing local dir: {local}")
    return local


def _pick_latest_render(video_dir: Path) -> Path:
    renders = video_dir / "00renders"
    if not renders.is_dir():
        _die(f"missing 00renders/ in {video_dir}")
    found: list[tuple[int, Path]] = []
    for p in renders.iterdir():
        if not p.is_file():
            continue
        idx = _render_index(p.name)
        if idx is not None:
            found.append((idx, p))
    if not found:
        _die(f"no render_00*.mp4 in {renders}")
    found.sort(key=lambda t: t[0])
    return found[-1][1]


def _load_post_data(video_dir: Path) -> dict[str, Any]:
    path = video_dir / "post_data.json"
    if not path.is_file():
        _die(f"missing post_data.json in {video_dir}")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _die(f"invalid post_data.json: {exc}")
    if not isinstance(raw, dict):
        _die("post_data.json must be a JSON object")
    return raw


def _normalize_post(post: dict[str, Any], video_name: str) -> dict[str, Any]:
    platforms_raw = post.get("platforms")
    if isinstance(platforms_raw, list) and platforms_raw:
        platforms = [str(p).strip().lower() for p in platforms_raw if str(p).strip()]
    else:
        platforms = list(DEFAULT_PLATFORMS)
    title = str(post.get("title") or "").strip() or video_name
    description = str(post.get("description") or "")
    hashtags = post.get("hashtags") if isinstance(post.get("hashtags"), list) else []
    return {
        "platforms": platforms,
        "title": title,
        "description": description,
        "hashtags": [str(h) for h in hashtags],
        "facebook": post.get("facebook") if isinstance(post.get("facebook"), dict) else {},
        "youtube": post.get("youtube") if isinstance(post.get("youtube"), dict) else {},
        "tiktok": post.get("tiktok") if isinstance(post.get("tiktok"), dict) else {},
    }


def _result_ok(result: dict[str, Any]) -> bool:
    return bool(result.get("ok"))


def _publish_all(
    post: dict[str, Any],
    media_path: Path,
    *,
    dry_run: bool,
) -> dict[str, Any]:
    platforms = post["platforms"]
    title = post["title"]
    description = post["description"]
    hashtags = post["hashtags"]
    results: dict[str, Any] = {}

    if dry_run:
        for p in platforms:
            results[p] = {
                "ok": True,
                "data": {"platform": p, "dry_run": True, "media": str(media_path)},
            }
        return results

    if "facebook" in platforms:
        fb = post["facebook"]
        link = ""
        if str(fb.get("post_type") or "") == "link":
            link = str(fb.get("link") or "").strip()
        schedule_at = None
        if str(fb.get("publish_mode") or "") == "schedule":
            schedule_at = str(fb.get("schedule_at") or "").strip() or None
        results["facebook"] = publish_facebook_post(
            title=title,
            description=description,
            hashtags=hashtags,
            link=link,
            schedule_at=schedule_at,
            page_id=str(fb.get("page") or "").strip() or None,
            media_path=media_path,
        )

    if "youtube" in platforms:
        yt = post["youtube"]
        results["youtube"] = publish_youtube_video(
            title=title,
            description=description,
            video_path=media_path,
            privacy=str(yt.get("privacy") or "private"),
            category_id=str(yt.get("category_id") or "").strip() or None,
            tags=[str(t) for t in (yt.get("tags") or hashtags)],
            publish_at=str(yt.get("publish_at") or "").strip() or None,
            playlist_id=str(yt.get("playlist_id") or "").strip() or None,
        )

    if "tiktok" in platforms:
        tt = post["tiktok"]
        results["tiktok"] = publish_tiktok_video(
            title=title,
            description=description,
            hashtags=hashtags,
            video_path=media_path,
            privacy_level=str(tt.get("privacy_level") or "SELF_ONLY"),
            disable_comment=bool(tt.get("disable_comment")),
            disable_duet=bool(tt.get("disable_duet")),
            disable_stitch=bool(tt.get("disable_stitch")),
        )

    return results


def _format_log_body(
    *,
    status: str,
    product: str,
    video: str = "",
    render: str = "",
    note: str = "",
    results: dict[str, Any] | None = None,
) -> str:
    lines = [
        f"status={status}",
        f"product={product}",
        f"video={video}",
        f"render={render}",
        f"when={datetime.now().isoformat(timespec='seconds')}",
    ]
    if note:
        lines.append(f"note={note}")
    if results:
        platforms = ",".join(results.keys())
        lines.append(f"platforms={platforms}")
        for name, res in results.items():
            ok = _result_ok(res) if isinstance(res, dict) else False
            lines.append(f"{name}_ok={str(ok).lower()}")
            if isinstance(res, dict):
                data = res.get("data") if isinstance(res.get("data"), dict) else {}
                rid = data.get("id") or data.get("publish_id") or ""
                if rid:
                    lines.append(f"{name}_id={rid}")
                url = data.get("url") or ""
                if url:
                    lines.append(f"{name}_url={url}")
                if not ok:
                    err = res.get("error") if isinstance(res.get("error"), dict) else {}
                    code = err.get("code") or ""
                    msg = err.get("message") or ""
                    if code:
                        lines.append(f"{name}_error_code={code}")
                    if msg:
                        lines.append(f"{name}_error={msg}")
    return "\n".join(lines) + "\n"


def _try_product(product: str, *, dry_run: bool) -> str:
    """
    Returns:
      'posted' | 'empty' | 'failed'
    """
    print(f"== product {product} ==")
    videos = _list_remote_videos(product)
    if not videos:
        print(f"no video_*** for {product} — empty_queue, advance")
        body = _format_log_body(
            status="empty_queue",
            product=product,
            note="no video_*** dirs",
        )
        _write_remote_log(product, body, dry_run=dry_run)
        _prune_logs(dry_run=dry_run)
        return "empty"

    video_name = videos[0]
    print(f"selected {video_name} (of {len(videos)})")

    with tempfile.TemporaryDirectory(prefix="mkt_cron_") as tmp:
        tmp_path = Path(tmp)
        local_video = _pull_video_dir(product, video_name, tmp_path)
        post_raw = _load_post_data(local_video)
        post = _normalize_post(post_raw, video_name)
        render_path = _pick_latest_render(local_video)
        print(f"render {render_path.name}")
        print(f"platforms {','.join(post['platforms'])}")
        print(f"title {post['title']!r}")

        results = _publish_all(post, render_path, dry_run=dry_run)
        for name, res in results.items():
            ok = _result_ok(res) if isinstance(res, dict) else False
            print(f"  {name}: {'ok' if ok else 'FAIL'} {res}")

        all_ok = bool(results) and all(
            _result_ok(r) for r in results.values() if isinstance(r, dict)
        )
        if not all_ok:
            print("publish incomplete — no rotation, no delete")
            detail_lines = [
                f"product={product}",
                f"video={video_name}",
                f"render={render_path.name}",
                f"title={post['title']!r}",
                "",
                "platform results:",
            ]
            for name, res in results.items():
                detail_lines.append(f"  {name}: {res}")
            _send_failure_alert(
                "rop01 marketing FAILED",
                "\n".join(detail_lines),
            )
            return "failed"

        body = _format_log_body(
            status="success",
            product=product,
            video=video_name,
            render=render_path.name,
            results=results,
        )
        _write_remote_log(product, body, dry_run=dry_run)
        _delete_remote_video(product, video_name, dry_run=dry_run)
        _prune_logs(dry_run=dry_run)
        print(f"success — deleted {video_name}, wrote rotation log")
        return "posted"


def main() -> int:
    global _DRY_RUN, _ALERT_SENT
    parser = argparse.ArgumentParser(description="rop01 cron social auto-post")
    parser.add_argument(
        "--env-file",
        help="Load KEY=VAL into env if not already set (e.g. .env.prod on rop01)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Pull/select only; skip API publish, remote delete, and log writes",
    )
    parser.add_argument(
        "--product",
        help="Force a single product (skip rotation); still respects empty→no post",
    )
    args = parser.parse_args()
    _DRY_RUN = bool(args.dry_run)
    _ALERT_SENT = False

    if args.env_file:
        _load_env_file(Path(args.env_file).expanduser())
        os.environ.setdefault("WFRUN_ENV_FILE", str(Path(args.env_file).expanduser()))

    # Help publish_common.env() find secrets when WFRUN_ENV_FILE unset but env loaded
    if not env("FACEBOOK_PAGE_ACCESS_TOKEN") and not os.environ.get(
        "FACEBOOK_PAGE_ACCESS_TOKEN"
    ):
        print(
            "WARN social tokens not visible in env — pass --env-file or export creds",
            file=sys.stderr,
        )

    try:
        products = _list_products()
        if not products:
            print("no product dirs under marketing/ (excluding logs)")
            return 0

        print(f"products: {', '.join(products)}")
        print(f"ssh: {_ssh_host()}  root: {_remote_root()}")

        if args.product:
            if args.product not in products:
                _die(f"unknown product {args.product!r}; have {products}")
            outcome = _try_product(args.product, dry_run=args.dry_run)
            return 0 if outcome != "failed" else 2

        last = _last_product_from_logs()
        print(f"last product from logs: {last or '(none)'}")

        # Walk products starting after last; stop after one successful post.
        # Empty queues write a log and continue; publish failure aborts (no advance).
        start = _next_product(products, last)
        if start is None:
            return 0
        order: list[str] = []
        i = products.index(start)
        for _ in range(len(products)):
            order.append(products[i])
            i = (i + 1) % len(products)

        for product in order:
            outcome = _try_product(product, dry_run=args.dry_run)
            if outcome == "posted":
                return 0
            if outcome == "failed":
                return 2
            # empty → continue
        print("all products empty this run")
        return 0
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        _send_failure_alert("rop01 marketing FAILED", f"unhandled error: {exc}")
        raise


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        err = exc.stderr if isinstance(exc.stderr, str) else ""
        _die(f"command failed: {err or exc}")
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        raise SystemExit(130)
