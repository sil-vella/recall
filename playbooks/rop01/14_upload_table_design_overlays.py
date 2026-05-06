#!/usr/bin/env python3
"""
Upload table design overlays from:
  sponsors/media/table_design/<pack_name>/table_design_overlay_<pack_name>.webp

to:
  /var/www/dutch.reignofplay.com/sponsors/media/table_design/<pack_name>/table_design_overlay_<pack_name>.webp

Usage:
  python playbooks/rop01/14_upload_table_design_overlays.py --all
  python playbooks/rop01/14_upload_table_design_overlays.py --pack juventus
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

LOCAL_BASE_DIR = PROJECT_ROOT / "sponsors" / "media" / "table_design"
REMOTE_BASE_DIR = "/var/www/dutch.reignofplay.com/sponsors/media/table_design"


def check_ssh_key() -> bool:
    key_path = Path(VPS_SSH_KEY)
    if not key_path.exists():
        print(f"{Colors.RED}Error: SSH key not found at {VPS_SSH_KEY}{Colors.NC}")
        return False
    return True


def find_pack_files(pack: str | None, upload_all: bool) -> List[Path]:
    if not LOCAL_BASE_DIR.exists():
        return []

    if upload_all:
        files = sorted(LOCAL_BASE_DIR.glob("*/table_design_overlay_*.webp"))
        return [f for f in files if f.is_file()]

    if not pack:
        return []

    pack_name = pack.strip().lower()
    expected = LOCAL_BASE_DIR / pack_name / f"table_design_overlay_{pack_name}.webp"
    return [expected] if expected.is_file() else []


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
        print(f"{Colors.GREEN}✓ Uploaded{Colors.NC} {rel.as_posix()}")
        return True
    except Exception as e:
        print(f"{Colors.RED}✗ Remote move/permission failed: {e}{Colors.NC}")
        return False


def parse_args():
    parser = argparse.ArgumentParser(description="Upload table design overlay webp files")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--all", action="store_true", help="Upload all packs found under sponsors/media/table_design")
    group.add_argument("--pack", type=str, help="Upload one pack, e.g. juventus")
    return parser.parse_args()


def main():
    args = parse_args()

    print(f"{Colors.BLUE}=== Table Design Overlay Upload ==={Colors.NC}")
    print(f"Local base:  {LOCAL_BASE_DIR}")
    print(f"Remote base: {REMOTE_BASE_DIR}")

    if not check_ssh_key():
        sys.exit(1)

    files = find_pack_files(pack=args.pack, upload_all=args.all)
    if not files:
        print(f"{Colors.RED}No matching overlay files found.{Colors.NC}")
        sys.exit(1)

    if sys.stdin.isatty():
        response = input(f"Upload {len(files)} file(s)? (y/n): ").strip().lower()
        if response != "y":
            print(f"{Colors.YELLOW}Cancelled.{Colors.NC}")
            sys.exit(0)

    ok = True
    for f in files:
        ok = upload_file(f) and ok

    if not ok:
        sys.exit(1)
    print(f"{Colors.GREEN}All uploads completed.{Colors.NC}")


if __name__ == "__main__":
    main()
