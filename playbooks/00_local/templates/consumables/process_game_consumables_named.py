#!/usr/bin/env python3
"""
Process app_media/game_consumables_named/*.png into catalog media paths.

- Trim transparent / uniform border padding
- Card backs -> app_media/media/card_back/<pack>/card_back_<pack>.webp (512x716)
- Table designs -> rotate 90° CCW, then
  app_media/media/table_design/<pack>/table_design_overlay_<pack>.webp (576x1024)

Usage:
  python playbooks/00_local/templates/consumables/process_game_consumables_named.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Optional, Tuple

from PIL import Image, ImageOps

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent.parent
SRC_DIR = PROJECT_ROOT / "app_media" / "game_consumables_named"
MEDIA_ROOT = PROJECT_ROOT / "app_media" / "media"
CATALOG_PATH = (
    PROJECT_ROOT
    / "python_base_04"
    / "core"
    / "modules"
    / "dutch_game"
    / "config"
    / "consumables_catalog.json"
)

CARD_SIZE = (512, 716)
TABLE_SIZE = (576, 1024)  # portrait (TABLE_SIZE landscape rotated 90°)


def _pack_from_item_id(item_id: str, prefix: str) -> Optional[str]:
    sid = item_id.strip()
    if not sid.startswith(prefix):
        return None
    pack = sid[len(prefix) :].strip().lower()
    return pack or None


def _corner_bg_rgb(im: Image.Image) -> Tuple[int, int, int]:
    im_rgb = im.convert("RGB")
    w, h = im_rgb.size
    corners = [
        im_rgb.getpixel((0, 0)),
        im_rgb.getpixel((w - 1, 0)),
        im_rgb.getpixel((0, h - 1)),
        im_rgb.getpixel((w - 1, h - 1)),
    ]
    return tuple(sum(c[i] for c in corners) // 4 for i in range(3))  # type: ignore[return-value]


def _similar(c1: Tuple[int, ...], c2: Tuple[int, ...], tolerance: int) -> bool:
    if len(c1) < 3 or len(c2) < 3:
        return False
    return all(abs(int(c1[i]) - int(c2[i])) <= tolerance for i in range(3))


def trim_padding(im: Image.Image, *, tolerance: int = 24, alpha_threshold: int = 8) -> Image.Image:
    """Crop empty alpha and near-uniform border (sampled from corners)."""
    rgba = im.convert("RGBA")
    w, h = rgba.size
    alpha = rgba.split()[3]
    alpha_bbox = alpha.point(lambda p: 255 if p > alpha_threshold else 0).getbbox()
    if alpha_bbox:
        rgba = rgba.crop(alpha_bbox)
        w, h = rgba.size

    bg = _corner_bg_rgb(rgba)
    px = rgba.load()

    top = 0
    while top < h and all(_similar(px[x, top][:3], bg, tolerance) for x in range(w)):
        top += 1
    bottom = h - 1
    while bottom >= top and all(_similar(px[x, bottom][:3], bg, tolerance) for x in range(w)):
        bottom -= 1
    left = 0
    while left < w and all(_similar(px[left, y][:3], bg, tolerance) for y in range(top, bottom + 1)):
        left += 1
    right = w - 1
    while right >= left and all(_similar(px[right, y][:3], bg, tolerance) for y in range(top, bottom + 1)):
        right -= 1

    if right > left and bottom > top:
        rgba = rgba.crop((left, top, right + 1, bottom + 1))
    return rgba


def fit_to_size(im: Image.Image, size: Tuple[int, int]) -> Image.Image:
    return ImageOps.fit(im, size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def save_webp(im: Image.Image, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    rgb = im.convert("RGB")
    rgb.save(dest, format="WEBP", quality=88, method=6)


def main() -> int:
    if not SRC_DIR.is_dir():
        print(f"Missing source dir: {SRC_DIR}", file=sys.stderr)
        return 1

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    card_ids = [i["item_id"] for i in catalog["items"] if i.get("item_type") == "card_back"]
    table_ids = [i["item_id"] for i in catalog["items"] if i.get("item_type") == "table_design"]

    processed = 0
    skipped = []

    for item_id in card_ids:
        pack = _pack_from_item_id(item_id, "card_back_")
        if not pack:
            continue
        src = SRC_DIR / f"{item_id}.png"
        if not src.is_file():
            skipped.append(str(src.name))
            continue
        im = Image.open(src)
        im = trim_padding(im)
        im = fit_to_size(im, CARD_SIZE)
        dest = MEDIA_ROOT / "card_back" / pack / f"card_back_{pack}.webp"
        save_webp(im, dest)
        print(f"card_back  {item_id} -> {dest.relative_to(PROJECT_ROOT)} ({im.size[0]}x{im.size[1]})")
        processed += 1

    for item_id in table_ids:
        pack = _pack_from_item_id(item_id, "table_design_")
        if not pack:
            continue
        src = SRC_DIR / f"{item_id}.png"
        if not src.is_file():
            skipped.append(str(src.name))
            continue
        im = Image.open(src)
        im = trim_padding(im)
        im = im.rotate(90, expand=True)  # landscape -> portrait
        im = fit_to_size(im, TABLE_SIZE)
        dest = MEDIA_ROOT / "table_design" / pack / f"table_design_overlay_{pack}.webp"
        save_webp(im, dest)
        print(f"table      {item_id} -> {dest.relative_to(PROJECT_ROOT)} ({im.size[0]}x{im.size[1]})")
        processed += 1

    if skipped:
        print(f"\nSkipped (no source PNG): {', '.join(skipped)}", file=sys.stderr)
    print(f"\nDone: {processed} file(s) written under {MEDIA_ROOT.relative_to(PROJECT_ROOT)}")
    return 0 if processed > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
