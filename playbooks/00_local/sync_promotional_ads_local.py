#!/usr/bin/env python3
"""
Local promotional ads sync (same logic as playbooks/rop01/15_upload_promotional_bundle.py,
without SSH).

Reads:
  - sponsors/promotional_ads.yaml  (repo root)
  - sponsors/media/*  (images/videos; card_back.png and table_logo.png are excluded from the adverts copy)

Writes a static site layout under playbooks/00_local/sponsors_static/:
  sponsors/promotional_ads.json
  sponsors/adverts/<files>

Use this with a simple HTTP server so Flutter can load the same URLs as production:
  GET ${API_URL}/sponsors/promotional_ads.json
  GET ${API_URL}/sponsors/adverts/<filename>

Requires: PyYAML (pip install pyyaml)

Example:
  python3 playbooks/00_local/sync_promotional_ads_local.py
  cd playbooks/00_local/sponsors_static && python3 -m http.server 8765

Then run the app with API_URL pointing at that server, e.g.:
  --dart-define=API_URL=http://127.0.0.1:8765

Environment:
  LOCAL_SPONSORS_OUT  Override output directory (default: playbooks/00_local/sponsors_static)
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent

LOCAL_YAML = PROJECT_ROOT / "sponsors" / "promotional_ads.yaml"
LOCAL_MEDIA_DIR = PROJECT_ROOT / "sponsors" / "media"

MEDIA_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".mp4", ".webm"}
EXCLUDE_FROM_PROMO_BUNDLE = frozenset({"card_back.png", "table_logo.png"})

DEFAULT_OUT = SCRIPT_DIR / "sponsors_static"


class Colors:
    BLUE = "\033[0;34m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RED = "\033[0;31m"
    NC = "\033[0m"


def yaml_to_json_payload(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    data = yaml.safe_load(text)
    if not isinstance(data, dict):
        raise ValueError("promotional_ads.yaml root must be a mapping")
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync promotional ads to a local static tree for testing.")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help=f"Output root (site root for http.server). Default: {DEFAULT_OUT}",
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Skip confirmation prompt",
    )
    args = parser.parse_args()

    out_root: Path = args.out if args.out is not None else Path(
        os.environ.get("LOCAL_SPONSORS_OUT", str(DEFAULT_OUT))
    ).resolve()

    sponsors_dir = out_root / "sponsors"
    json_path = sponsors_dir / "promotional_ads.json"
    adverts_dir = sponsors_dir / "adverts"

    print(f"{Colors.BLUE}=== Local promotional ads sync ==={Colors.NC}\n")

    if not LOCAL_YAML.is_file():
        print(f"{Colors.RED}Error: Missing {LOCAL_YAML}{Colors.NC}")
        sys.exit(1)

    try:
        payload = yaml_to_json_payload(LOCAL_YAML)
    except Exception as e:
        print(f"{Colors.RED}Error parsing YAML: {e}{Colors.NC}")
        sys.exit(1)

    if "version" not in payload:
        payload["version"] = 1

    media_files = list_media_files(LOCAL_MEDIA_DIR)

    print(f"{Colors.BLUE}Source YAML:{Colors.NC} {LOCAL_YAML}")
    print(f"{Colors.BLUE}Media:{Colors.NC} {len(media_files)} file(s) from {LOCAL_MEDIA_DIR} (excl. card_back/table_logo)")
    print(f"{Colors.BLUE}Output root:{Colors.NC} {out_root}")
    print(f"{Colors.BLUE}Manifest file:{Colors.NC} {json_path}")
    print()

    if not args.yes:
        if sys.stdin.isatty():
            if input("Proceed? (y/n): ").strip().lower() != "y":
                print(f"{Colors.YELLOW}Cancelled.{Colors.NC}")
                sys.exit(0)
        else:
            print(f"{Colors.RED}Non-interactive shell: re-run with -y{Colors.NC}", file=sys.stderr)
            sys.exit(1)

    sponsors_dir.mkdir(parents=True, exist_ok=True)
    adverts_dir.mkdir(parents=True, exist_ok=True)

    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{Colors.GREEN}✓ Wrote {json_path}{Colors.NC}")

    # Replace adverts dir contents
    for child in adverts_dir.iterdir():
        if child.is_file():
            child.unlink()
    for f in media_files:
        shutil.copy2(f, adverts_dir / f.name)
    if media_files:
        print(f"{Colors.GREEN}✓ Copied {len(media_files)} file(s) to {adverts_dir}{Colors.NC}")
    else:
        print(
            f"{Colors.YELLOW}No media files copied (empty {LOCAL_MEDIA_DIR} or only card_back/table_logo).{Colors.NC}"
        )

    print(f"\n{Colors.GREEN}=== Done ==={Colors.NC}")
    print()
    print("Serve the output root, then point Flutter API_URL at it:")
    print()
    print(f"  {Colors.BLUE}cd {out_root}{Colors.NC}")
    print(f"  {Colors.BLUE}python3 -m http.server 8765{Colors.NC}")
    print()
    print("  Example: --dart-define=API_URL=http://127.0.0.1:8765")
    print()
    print("  Manifest URL: http://127.0.0.1:8765/sponsors/promotional_ads.json")


if __name__ == "__main__":
    main()
