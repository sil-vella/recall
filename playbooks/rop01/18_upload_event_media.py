#!/usr/bin/env python3
"""
Upload special-event media from:
  app_media/media/event_media/<event_id>/*

to:
  /var/www/dutch.reignofplay.com/app_media/media/event_media/<event_id>/*

Usage:
  python playbooks/rop01/18_upload_event_media.py --all
  python playbooks/rop01/18_upload_event_media.py --event cards_night
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import List


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"


SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent

VPS_SSH_TARGET = os.environ.get("VPS_SSH_TARGET", "rop01_user@65.181.125.135")
VPS_SSH_KEY = os.environ.get("VPS_SSH_KEY", os.path.expanduser("~/.ssh/rop01_key"))

LOCAL_BASE_DIR = PROJECT_ROOT / "app_media" / "media" / "event_media"
REMOTE_BASE_DIR = "/var/www/dutch.reignofplay.com/app_media/media/event_media"


def check_ssh_key() -> bool:
    key_path = Path(VPS_SSH_KEY)
    if not key_path.exists():
        print(f"{Colors.RED}Error: SSH key not found at {VPS_SSH_KEY}{Colors.NC}")
        return False
    return True


def find_event_files(event: str | None, upload_all: bool) -> List[Path]:
    if not LOCAL_BASE_DIR.exists():
        return []

    if upload_all:
        return sorted(p for p in LOCAL_BASE_DIR.glob("*/*") if p.is_file())

    if not event:
        return []

    event_id = event.strip().lower()
    event_dir = LOCAL_BASE_DIR / event_id
    if not event_dir.is_dir():
        return []
    return sorted(p for p in event_dir.iterdir() if p.is_file())


def upload_file(local_file: Path) -> bool:
    rel = local_file.relative_to(LOCAL_BASE_DIR)
    remote_file = f"{REMOTE_BASE_DIR}/{rel.as_posix()}"
    remote_dir = os.path.dirname(remote_file)
    remote_tmp = f"/tmp/{local_file.name}"

    print(f"{Colors.BLUE}Uploading:{Colors.NC} {local_file}")
    print(f"{Colors.BLUE}Remote:{Colors.NC} {remote_file}")

    scp_cmd = ["scp", "-i", VPS_SSH_KEY, str(local_file), f"{VPS_SSH_TARGET}:{remote_tmp}"]
    try:
        subprocess.run(scp_cmd, check=True)
    except Exception as e:
        print(f"{Colors.RED}✗ SCP failed: {e}{Colors.NC}")
        return False

    ssh_cmd = [
        "ssh",
        "-i",
        VPS_SSH_KEY,
        VPS_SSH_TARGET,
        (
            f"sudo mkdir -p {remote_dir} && "
            f"sudo mv {remote_tmp} {remote_file} && "
            f"sudo chown www-data:www-data {remote_file} && "
            f"sudo chmod 644 {remote_file}"
        ),
    ]
    try:
        subprocess.run(ssh_cmd, check=True)
    except Exception as e:
        print(f"{Colors.RED}✗ SSH move failed: {e}{Colors.NC}")
        return False

    print(f"{Colors.GREEN}✓ Uploaded {rel.as_posix()}{Colors.NC}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload Dutch special-event media packs")
    parser.add_argument("--all", action="store_true", help="Upload all files under event_media/")
    parser.add_argument("--event", type=str, help="Upload one event id directory (e.g. cards_night)")
    args = parser.parse_args()

    if not args.all and not args.event:
        parser.error("Specify --all or --event <id>")

    if not check_ssh_key():
        return 1

    files = find_event_files(args.event, args.all)
    if not files:
        print(f"{Colors.YELLOW}No event media files found under {LOCAL_BASE_DIR}{Colors.NC}")
        return 1

    print(f"{Colors.BLUE}=== Event Media Upload ==={Colors.NC}")
    ok = 0
    for f in files:
        if upload_file(f):
            ok += 1

    print(f"\n{Colors.GREEN}Done: {ok}/{len(files)} uploaded{Colors.NC}")
    return 0 if ok == len(files) else 1


if __name__ == "__main__":
    sys.exit(main())
