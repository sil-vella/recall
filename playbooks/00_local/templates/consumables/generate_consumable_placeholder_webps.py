#!/usr/bin/env python3
"""
Generate flat-color placeholder WebPs for consumables catalog cosmetics.

Local dev copy (playbooks/00_local/templates/consumables/).
Outputs to repo app_media/media/ — same paths as production upload playbooks.

Reads: python_base_04/core/modules/dutch_game/config/consumables_catalog.json
Writes:
  app_media/media/card_back/<pack>/card_back_<pack>.webp
  app_media/media/table_design/<pack>/table_design_overlay_<pack>.webp
  app_media/media/card_back.webp (root fallback)
  app_media/media/table_logo.webp (root fallback)

Each image is a catalog-colored fill with centered "PLACEHOLDER" label.

Usage:
  python playbooks/00_local/templates/consumables/generate_consumable_placeholder_webps.py
  python playbooks/00_local/templates/consumables/generate_consumable_placeholder_webps.py --force
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent.parent
CATALOG_PATH = (
    PROJECT_ROOT
    / "python_base_04"
    / "core"
    / "modules"
    / "dutch_game"
    / "config"
    / "consumables_catalog.json"
)
MEDIA_ROOT = PROJECT_ROOT / "app_media" / "media"

CARD_SIZE = (512, 716)
TABLE_SIZE = (1024, 576)
TABLE_OVERLAY_ALPHA = 38  # ~15% on 0-255 scale
PLACEHOLDER_LABEL = "PLACEHOLDER"

_FONT_CANDIDATES = (
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def _parse_hex_color(value: Optional[str]) -> Optional[Tuple[int, int, int]]:
    if not value:
        return None
    v = value.strip()
    if v.startswith("#"):
        v = v[1:]
    if len(v) == 6:
        try:
            return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))
        except ValueError:
            return None
    return None


def _pack_from_item_id(item_id: str, prefix: str) -> Optional[str]:
    sid = item_id.strip()
    if not sid.startswith(prefix):
        return None
    pack = sid.replace(prefix, "", 1).strip().lower()
    return pack or None


def _load_catalog() -> List[Dict[str, Any]]:
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        doc = json.load(f)
    items = doc.get("items")
    if not isinstance(items, list):
        raise ValueError("catalog items must be a list")
    return [i for i in items if isinstance(i, dict)]


def _border_color(style: Dict[str, Any]) -> Optional[Tuple[int, int, int]]:
    colors = style.get("border_colors")
    if isinstance(colors, list) and colors:
        return _parse_hex_color(str(colors[0]))
    return None


def _card_color(style: Dict[str, Any]) -> Tuple[int, int, int]:
    c = _parse_hex_color(style.get("card_background_color"))
    if c:
        return c
    return (60, 60, 60)


def _luminance(rgb: Tuple[int, int, int]) -> float:
    r, g, b = rgb
    return 0.299 * r + 0.587 * g + 0.114 * b


def _text_color_for_bg(rgb: Tuple[int, int, int]) -> Tuple[int, int, int]:
    return (255, 255, 255) if _luminance(rgb) < 140 else (20, 20, 20)


def _load_font(size: int):
    from PIL import ImageFont

    for path in _FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _draw_placeholder_label(image, bg_rgb: Tuple[int, int, int]):
    from PIL import ImageDraw

    draw = ImageDraw.Draw(image)
    width, height = image.size
    font_size = max(18, min(width, height) // 12)
    font = _load_font(font_size)
    text = PLACEHOLDER_LABEL
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (width - text_w) // 2 - bbox[0]
    y = (height - text_h) // 2 - bbox[1]
    fill = _text_color_for_bg(bg_rgb)
    if image.mode == "RGBA":
        draw.text((x, y), text, fill=(*fill, 255), font=font)
    else:
        draw.text((x, y), text, fill=fill, font=font)
    return image


def _make_card_image(rgb: Tuple[int, int, int]):
    from PIL import Image

    img = Image.new("RGB", CARD_SIZE, rgb)
    return _draw_placeholder_label(img, rgb)


def _make_table_image(rgb: Tuple[int, int, int]):
    from PIL import Image

    img = Image.new("RGBA", TABLE_SIZE, (*rgb, TABLE_OVERLAY_ALPHA))
    return _draw_placeholder_label(img, rgb)


def _write_webp(path: Path, image, force: bool) -> bool:
    if path.exists() and not force:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="WEBP", quality=85)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate consumable placeholder WebPs")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing files",
    )
    args = parser.parse_args()

    try:
        from PIL import Image  # noqa: F401 — availability check
    except ImportError:
        print("Error: Pillow is required (pip install Pillow)", file=sys.stderr)
        return 1

    if not CATALOG_PATH.is_file():
        print(f"Error: catalog not found: {CATALOG_PATH}", file=sys.stderr)
        return 1

    items = _load_catalog()
    created = 0
    skipped = 0
    default_card_rgb = (78, 62, 46)
    default_table_rgb = (46, 128, 101)

    for item in items:
        item_id = str(item.get("item_id") or "").strip()
        item_type = str(item.get("item_type") or "").strip()
        style = item.get("style") if isinstance(item.get("style"), dict) else {}

        if item_type == "card_back":
            pack = _pack_from_item_id(item_id, "card_back_")
            if not pack:
                continue
            out = MEDIA_ROOT / "card_back" / pack / f"card_back_{pack}.webp"
            rgb = _card_color(style)
            img = _make_card_image(rgb)
            if _write_webp(out, img, args.force):
                created += 1
                print(f"  + {out.relative_to(PROJECT_ROOT)}")
            else:
                skipped += 1

        elif item_type == "table_design":
            pack = _pack_from_item_id(item_id, "table_design_")
            if not pack:
                continue
            out = MEDIA_ROOT / "table_design" / pack / f"table_design_overlay_{pack}.webp"
            rgb = _border_color(style) or default_table_rgb
            img = _make_table_image(rgb)
            if _write_webp(out, img, args.force):
                created += 1
                print(f"  + {out.relative_to(PROJECT_ROOT)}")
            else:
                skipped += 1

    for path, rgb, maker in (
        (MEDIA_ROOT / "card_back.webp", default_card_rgb, _make_card_image),
        (MEDIA_ROOT / "table_logo.webp", default_table_rgb, _make_table_image),
    ):
        img = maker(rgb)
        if _write_webp(path, img, args.force):
            created += 1
            print(f"  + {path.relative_to(PROJECT_ROOT)}")
        else:
            skipped += 1

    print(f"Done: {created} written, {skipped} skipped (use --force to overwrite)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
