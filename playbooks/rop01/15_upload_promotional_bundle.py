#!/usr/bin/env python3
"""
Upload promotional ads manifest + media to the VPS (nginx /sponsors/ tree).

Reads the source manifest from sponsors/promotional_ads.yaml at repo root (YAML),
converts to JSON, uploads to:
  /var/www/dutch.reignofplay.com/sponsors/promotional_ads.json

Uploads image/video files from sponsors/media/ to:
  /var/www/dutch.reignofplay.com/sponsors/adverts/

Only files with common media extensions are copied (.png, .jpg, .jpeg, .gif, .webp, .mp4, .webm).
card_back.png and table_logo.png in that folder are skipped (use 12_/13_ upload scripts for those).

Requires: PyYAML (pip install pyyaml)

After changing ads or media locally, run this script to refresh production without an app release.
Optionally bump the client-side query version in PromotionalAdsConfigLoader if browsers cache aggressively.

Environment:
  VPS_SSH_TARGET  (default: rop01_user@65.181.125.135)
  VPS_SSH_KEY     (default: ~/.ssh/rop01_key)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent

VPS_SSH_TARGET = os.environ.get('VPS_SSH_TARGET', 'rop01_user@65.181.125.135')
VPS_SSH_KEY = os.environ.get('VPS_SSH_KEY', os.path.expanduser('~/.ssh/rop01_key'))

REMOTE_ROOT = '/var/www/dutch.reignofplay.com/sponsors'
REMOTE_JSON = f'{REMOTE_ROOT}/promotional_ads.json'
REMOTE_ADVERTS = f'{REMOTE_ROOT}/adverts'
REMOTE_TMP_JSON = '/tmp/promotional_ads.json'
REMOTE_TMP_ADVERTS_DIR = '/tmp/promotional_adverts_upload'

LOCAL_YAML = PROJECT_ROOT / 'sponsors' / 'promotional_ads.yaml'
LOCAL_MEDIA_DIR = PROJECT_ROOT / 'sponsors' / 'media'

MEDIA_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4', '.webm'}
# These are uploaded separately to sponsors/media/ via 12_ and 13_ scripts.
EXCLUDE_FROM_PROMO_BUNDLE = frozenset({'card_back.png', 'table_logo.png'})


def check_ssh_key() -> bool:
    key_path = Path(VPS_SSH_KEY)
    if not key_path.exists():
        print(f"{Colors.RED}Error: SSH key not found at {VPS_SSH_KEY}{Colors.NC}")
        print(f"{Colors.YELLOW}Please run 01_setup_ssh_key.sh first.{Colors.NC}")
        return False
    return True


def yaml_to_json_payload(path: Path) -> dict:
    text = path.read_text(encoding='utf-8')
    data = yaml.safe_load(text)
    if not isinstance(data, dict):
        raise ValueError('promotional_ads.yaml root must be a mapping')
    return data


def list_media_files(media_dir: Path) -> list[Path]:
    if not media_dir.is_dir():
        return []
    out: list[Path] = []
    for p in sorted(media_dir.iterdir()):
        if not p.is_file() or p.suffix.lower() not in MEDIA_EXTENSIONS:
            continue
        if p.name.lower() in {n.lower() for n in EXCLUDE_FROM_PROMO_BUNDLE}:
            continue
        out.append(p)
    return out


def confirm(prompt: str) -> bool:
    if sys.stdin.isatty():
        return input(prompt).strip().lower() == 'y'
    print("Non-interactive mode: Auto-confirming...")
    return True


def scp_to_tmp(local: Path, remote_tmp: str) -> None:
    subprocess.run(
        ['scp', '-i', VPS_SSH_KEY, str(local), f'{VPS_SSH_TARGET}:{remote_tmp}'],
        check=True,
    )


def run_ssh(remote_cmd: str) -> None:
    subprocess.run(
        ['ssh', '-i', VPS_SSH_KEY, VPS_SSH_TARGET, remote_cmd],
        check=True,
    )


def main() -> None:
    print(f"{Colors.BLUE}=== Promotional ads bundle upload ==={Colors.NC}\n")

    if not check_ssh_key():
        sys.exit(1)

    if not LOCAL_YAML.is_file():
        print(f"{Colors.RED}Error: Missing {LOCAL_YAML}{Colors.NC}")
        sys.exit(1)

    try:
        payload = yaml_to_json_payload(LOCAL_YAML)
    except Exception as e:
        print(f"{Colors.RED}Error parsing YAML: {e}{Colors.NC}")
        sys.exit(1)

    # Optional version for cache semantics (Flutter can read top-level "version")
    if 'version' not in payload:
        payload['version'] = 1

    media_files = list_media_files(LOCAL_MEDIA_DIR)
    print(f"{Colors.BLUE}Source YAML:{Colors.NC} {LOCAL_YAML}")
    print(f"{Colors.BLUE}Media files:{Colors.NC} {len(media_files)} under {LOCAL_MEDIA_DIR} (excl. card_back/table_logo)")
    print(f"{Colors.BLUE}Remote JSON:{Colors.NC} {REMOTE_JSON}")
    print(f"{Colors.BLUE}Remote adverts:{Colors.NC} {REMOTE_ADVERTS}")
    print(f"{Colors.BLUE}Expected manifest URL:{Colors.NC} https://dutch.mt/sponsors/promotional_ads.json")
    print()

    if not confirm("Proceed with upload? (y/n): "):
        print(f"{Colors.YELLOW}Cancelled.{Colors.NC}")
        sys.exit(0)

    # Write JSON to temp file locally, upload, move on server
    tmp_json_local = Path('/tmp/promotional_ads_bundle.json')
    tmp_json_local.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )

    print(f"\n{Colors.BLUE}Uploading promotional_ads.json...{Colors.NC}")
    try:
        scp_to_tmp(tmp_json_local, REMOTE_TMP_JSON)
        run_ssh(
            f'sudo mkdir -p {REMOTE_ROOT} && '
            f'sudo mv {REMOTE_TMP_JSON} {REMOTE_JSON} && '
            f'sudo chown www-data:www-data {REMOTE_JSON} && '
            f'sudo chmod 644 {REMOTE_JSON}'
        )
        print(f"{Colors.GREEN}✓ Manifest installed{Colors.NC}")
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}✗ Manifest upload failed: {e}{Colors.NC}")
        sys.exit(1)
    finally:
        try:
            tmp_json_local.unlink(missing_ok=True)
        except OSError:
            pass

    # Upload media: stage under /tmp on VPS, then copy into web root
    if media_files:
        print(f"\n{Colors.BLUE}Uploading advert media...{Colors.NC}")
        try:
            run_ssh(f'mkdir -p {REMOTE_TMP_ADVERTS_DIR} && rm -rf {REMOTE_TMP_ADVERTS_DIR}/*')
            for f in media_files:
                dest = f'{REMOTE_TMP_ADVERTS_DIR}/{f.name}'
                subprocess.run(
                    ['scp', '-i', VPS_SSH_KEY, str(f), f'{VPS_SSH_TARGET}:{dest}'],
                    check=True,
                )
            run_ssh(
                f'sudo rm -rf {REMOTE_ADVERTS} && sudo mkdir -p {REMOTE_ADVERTS} && '
                f'sudo cp {REMOTE_TMP_ADVERTS_DIR}/* {REMOTE_ADVERTS}/ && '
                f'sudo chown -R www-data:www-data {REMOTE_ADVERTS} && '
                f'sudo find {REMOTE_ADVERTS} -type f -exec chmod 644 {{}} \\; && '
                f'rm -rf {REMOTE_TMP_ADVERTS_DIR}'
            )
            print(f"{Colors.GREEN}✓ Uploaded {len(media_files)} media file(s){Colors.NC}")
        except subprocess.CalledProcessError as e:
            print(f"{Colors.RED}✗ Media upload failed: {e}{Colors.NC}")
            sys.exit(1)
    else:
        print(
            f"{Colors.YELLOW}No promotional media to upload under {LOCAL_MEDIA_DIR} "
            f"(missing/empty, or only card_back/table_logo).{Colors.NC}"
        )

    print(f"\n{Colors.GREEN}=== Done ==={Colors.NC}")
    print(f"Manifest: https://dutch.mt/sponsors/promotional_ads.json")
    print(f"Example media: https://dutch.mt/sponsors/adverts/<filename>")


if __name__ == '__main__':
    main()
