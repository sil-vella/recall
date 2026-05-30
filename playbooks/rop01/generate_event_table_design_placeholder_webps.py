#!/usr/bin/env python3
"""
Generate placeholder special-event table design overlays.

Reads: python_base_04/core/modules/dutch_game/config/table_tiers.json
Writes (when style.overlay_image_file is set):
  app_media/media/event_media/<event_id>/table_design_overlay_<event_id>.webp

Naming matches shop table designs: table_design/<pack>/table_design_overlay_<pack>.webp

Usage:
  python playbooks/rop01/generate_event_table_design_placeholder_webps.py
  python playbooks/rop01/generate_event_table_design_placeholder_webps.py --force
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent
CATALOG_PATH = (
    PROJECT_ROOT
    / "python_base_04"
    / "core"
    / "modules"
    / "dutch_game"
    / "config"
    / "table_tiers.json"
)
MEDIA_ROOT = PROJECT_ROOT / "app_media" / "media" / "event_media"

TABLE_SIZE = (1024, 576)
TABLE_OVERLAY_ALPHA = 38
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


def _draw_placeholder_label(image, bg_rgb: Tuple[int, int, int], event_id: str):
    from PIL import ImageDraw

    draw = ImageDraw.Draw(image)
    width, height = image.size
    font_size = max(16, min(width, height) // 14)
    font = _load_font(font_size)
    text = f"{PLACEHOLDER_LABEL}\n{event_id}"
    bbox = draw.multiline_textbbox((0, 0), text, font=font, align="center")
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (width - text_w) // 2 - bbox[0]
    y = (height - text_h) // 2 - bbox[1]
    fill = _text_color_for_bg(bg_rgb)
    if image.mode == "RGBA":
        draw.multiline_text((x, y), text, fill=(*fill, 255), font=font, align="center")
    else:
        draw.multiline_text((x, y), text, fill=fill, font=font, align="center")
    return image


def _make_table_image(rgb: Tuple[int, int, int], event_id: str):
    from PIL import Image

    img = Image.new("RGBA", TABLE_SIZE, (*rgb, TABLE_OVERLAY_ALPHA))
    return _draw_placeholder_label(img, rgb, event_id)


def _write_webp(path: Path, image, force: bool) -> bool:
    if path.exists() and not force:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="WEBP", quality=85)
    return True


def _load_catalog() -> Dict[str, Any]:
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate special-event table design placeholder WebPs")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    args = parser.parse_args()

    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        print("Error: Pillow is required (pip install Pillow)", file=sys.stderr)
        return 1

    if not CATALOG_PATH.is_file():
        print(f"Error: catalog not found: {CATALOG_PATH}", file=sys.stderr)
        return 1

    doc = _load_catalog()
    events = doc.get("special_events") or []
    created = 0
    skipped = 0
    default_rgb = (46, 128, 101)

    for ev in events:
        if not isinstance(ev, dict):
            continue
        event_id = str(ev.get("id") or "").strip()
        style = ev.get("style") if isinstance(ev.get("style"), dict) else {}
        fn = str(style.get("overlay_image_file") or "").strip()
        if not event_id or not fn:
            continue
        expected = f"table_design_overlay_{event_id}.webp"
        if fn != expected:
            print(f"Warning: {event_id} overlay_image_file={fn!r} (expected {expected!r})")
        out = MEDIA_ROOT / event_id / fn
        felt = _parse_hex_color(style.get("felt_hex")) or default_rgb
        img = _make_table_image(felt, event_id)
        if _write_webp(out, img, force=args.force):
            created += 1
            print(f"Wrote {out.relative_to(PROJECT_ROOT)}")
        else:
            skipped += 1

    print(f"Done: created={created} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
