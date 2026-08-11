#!/usr/bin/env python3
# dash Upload local campaign video_* dirs to Hostinger marketing queue
"""Sync local marketing campaign videos → Hostinger product queue.

Reads REPO_BRAND + MARKETING_LOCAL_DIR from env (via wfrun).

1. Collect local campaign_***/video_* folders that are not yet _uploaded
2. Confirm, upload via SSH (alias mixta_mt) → ~/rop01/marketing/<REPO_BRAND>/videos/
   Only **00renders/** and **post_data.json** (no source/, Premiere projects, etc.)
3. Rename each local folder to …_uploaded

Usage:
  wfrun → automation/marketing/upload_queue_to_hostinger.py
"""

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

from publish_common import env, prompt_yes_no, require_wfrun

SSH_HOST = "mixta_mt"
REMOTE_MARKETING = "/home/u877877481/rop01/marketing"

# video_008 or video_008(would_u_play_joker) — index = digits after video_
VIDEO_RE = re.compile(r"^video_(\d+)(.*)$")
CAMPAIGN_RE = re.compile(r"^campaign_(\d+)$")
UPLOADED_SUFFIX = "_uploaded"

RENDERS_DIRNAME = "00renders"
POST_DATA_NAME = "post_data.json"
RENDER_GLOB = "render_00*.mp4"


def _die(msg: str, code: int = 1) -> None:
    print(f"❌ {msg}", file=sys.stderr)
    raise SystemExit(code)


def _ssh(remote_cmd: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", SSH_HOST, remote_cmd],
        check=check,
        text=True,
        capture_output=True,
    )


def _video_index(name: str) -> int | None:
    """Numeric index for queue ordering. Skips already-uploaded local folders."""
    if name.endswith(UPLOADED_SUFFIX):
        return None
    m = VIDEO_RE.match(name)
    return int(m.group(1)) if m else None


def _campaign_index(name: str) -> int | None:
    m = CAMPAIGN_RE.match(name)
    return int(m.group(1)) if m else None


def _mark_local_uploaded(local_video: Path) -> Path:
    """Rename local folder to …_uploaded after a successful Hostinger put."""
    if local_video.name.endswith(UPLOADED_SUFFIX):
        return local_video
    dest = local_video.with_name(local_video.name + UPLOADED_SUFFIX)
    if dest.exists():
        _die(f"cannot mark uploaded — already exists: {dest}")
    local_video.rename(dest)
    print(f"  local renamed → {dest.name}")
    return dest


def _sorted_video_dirs(parent: Path) -> list[Path]:
    found: list[tuple[int, Path]] = []
    if not parent.is_dir():
        return []
    for child in parent.iterdir():
        if not child.is_dir():
            continue
        idx = _video_index(child.name)
        if idx is not None:
            found.append((idx, child))
    found.sort(key=lambda t: t[0])
    return [p for _, p in found]


def _sorted_campaign_dirs(root: Path) -> list[Path]:
    found: list[tuple[int, Path]] = []
    if not root.is_dir():
        return []
    for child in root.iterdir():
        if not child.is_dir():
            continue
        idx = _campaign_index(child.name)
        if idx is not None:
            found.append((idx, child))
    found.sort(key=lambda t: t[0])
    return [p for _, p in found]


def _pending_campaign_videos(root: Path) -> list[tuple[Path, Path]]:
    """Ordered (campaign_dir, video_dir) pending upload (no _uploaded)."""
    slots: list[tuple[Path, Path]] = []
    for campaign in _sorted_campaign_dirs(root):
        for video in _sorted_video_dirs(campaign):
            slots.append((campaign, video))
    return slots


def _queue_members(local_video: Path) -> tuple[Path, Path]:
    """Return (renders_dir, post_data_json); die if publish payload incomplete."""
    renders = local_video / RENDERS_DIRNAME
    post_data = local_video / POST_DATA_NAME
    if not renders.is_dir():
        _die(f"missing {RENDERS_DIRNAME}/ in {local_video}")
    renders_mp4 = sorted(renders.glob(RENDER_GLOB))
    if not renders_mp4:
        _die(f"no {RENDER_GLOB} under {renders}")
    if not post_data.is_file():
        _die(f"missing {POST_DATA_NAME} in {local_video}")
    return renders, post_data


def _upload_video_dir(local_video: Path, product: str) -> None:
    """Upload only 00renders/ + post_data.json into remote videos/<video_name>/."""
    _queue_members(local_video)

    remote_dest = f"{REMOTE_MARKETING}/{product}/videos"
    remote_video = f"{remote_dest}/{local_video.name}"
    _ssh(f"mkdir -p {shlex.quote(remote_dest)}", check=True)
    # Replace any prior partial/full tree for this video name
    _ssh(f"rm -rf {shlex.quote(remote_video)}", check=False)
    _ssh(f"mkdir -p {shlex.quote(remote_video)}", check=True)

    members = [
        f"{local_video.name}/{RENDERS_DIRNAME}",
        f"{local_video.name}/{POST_DATA_NAME}",
    ]
    print(
        f"↑ {local_video.parent.name}/{local_video.name} "
        f"[{RENDERS_DIRNAME}/ + {POST_DATA_NAME}] → {remote_video}/"
    )
    tar = subprocess.Popen(
        ["tar", "-C", str(local_video.parent), "-cf", "-", *members],
        stdout=subprocess.PIPE,
    )
    assert tar.stdout is not None
    remote = subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=20",
            SSH_HOST,
            f"tar -C {shlex.quote(remote_dest)} -xf -",
        ],
        stdin=tar.stdout,
        capture_output=True,
        text=True,
    )
    tar.stdout.close()
    tar_rc = tar.wait()
    if tar_rc != 0 or remote.returncode != 0:
        err = (remote.stderr or remote.stdout or "").strip()
        _die(f"upload failed for {local_video.name}: {err or remote.returncode or tar_rc}")


def main() -> int:
    require_wfrun()

    product = env("REPO_BRAND") or os.environ.get("REPO_BRAND", "").strip()
    local_root_s = env("MARKETING_LOCAL_DIR") or os.environ.get("MARKETING_LOCAL_DIR", "").strip()
    if not product:
        _die("REPO_BRAND is empty — set it in .env.local")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", product):
        _die(f"REPO_BRAND must be a safe folder name [A-Za-z0-9_-]+, got: {product!r}")
    if not local_root_s:
        _die("MARKETING_LOCAL_DIR is empty — set it in .env.local")

    local_root = Path(local_root_s).expanduser()
    if not local_root.is_dir():
        _die(f"MARKETING_LOCAL_DIR is not a directory: {local_root}")

    print(f"Product (REPO_BRAND): {product}")
    print(f"Local marketing dir:  {local_root}")
    print(f"Remote queue:         {SSH_HOST}:{REMOTE_MARKETING}/{product}/videos/")
    print(f"Upload payload:       {RENDERS_DIRNAME}/ + {POST_DATA_NAME} only")
    print()

    to_upload = _pending_campaign_videos(local_root)
    if not to_upload:
        print("Nothing to upload (no pending local video_* without _uploaded).")
        return 0

    print(f"Will upload {len(to_upload)} pending dir(s):")
    print()
    for c, v in to_upload:
        renders, post_data = _queue_members(v)
        n_renders = len(sorted(renders.glob(RENDER_GLOB)))
        print(f"  - {c.name}/{v.name}  ({n_renders} render(s), {post_data.name})")
    print()

    if not prompt_yes_no("Upload these folders to Hostinger?", default_yes=True):
        print("Cancelled.")
        return 0

    _ssh(f"mkdir -p {REMOTE_MARKETING}/{product}/videos {REMOTE_MARKETING}/logs", check=True)

    for _c, v in to_upload:
        if not v.is_dir():
            _die(f"missing local dir: {v}")
        _upload_video_dir(v, product)
        _mark_local_uploaded(v)

    print()
    print(f"✅ Uploaded {len(to_upload)} video dir(s) for product {product}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        err = ""
        if isinstance(exc.stderr, str):
            err = exc.stderr.strip()
        _die(f"command failed: {err or exc}")
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        raise SystemExit(130)
