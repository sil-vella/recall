#!/usr/bin/env python3
"""
Sample table-design overlay rim colors and sync declarative border_colors.

Updates:
  - python_base_04/core/modules/dutch_game/config/consumables_catalog.json (table_design items)
  - python_base_04/core/modules/dutch_game/config/table_tiers.json (special_events[].style)
  - dart_bkend_base_01/config/table_tiers.json (mirror)

Usage:
  python playbooks/rop01/sync_table_design_border_colors.py
  python playbooks/rop01/sync_table_design_border_colors.py --dry-run
"""

from __future__ import annotations

import argparse
import colorsys
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent
CONSUMABLES_PATH = (
    PROJECT_ROOT / "python_base_04" / "core" / "modules" / "dutch_game" / "config" / "consumables_catalog.json"
)
TABLE_TIERS_PATHS = [
    PROJECT_ROOT / "python_base_04" / "core" / "modules" / "dutch_game" / "config" / "table_tiers.json",
    PROJECT_ROOT / "dart_bkend_base_01" / "config" / "table_tiers.json",
]
SHOP_MEDIA = PROJECT_ROOT / "app_media" / "media" / "table_design"
EVENT_MEDIA = PROJECT_ROOT / "app_media" / "media" / "event_media"

STRIPE_SHOP = {"racing", "galaxy"}
STRIPE_EVENTS = {"the_challenger"}


def _rgb_to_hex(rgb: Tuple[int, int, int]) -> str:
    return f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"


def _border_pixels(path: Path, outer_pct: float = 0.12) -> List[Tuple[int, int, int]]:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    depth = int(min(w, h) * outer_pct)
    px = im.load()
    out: List[Tuple[int, int, int]] = []
    for y in range(h):
        for x in range(w):
            if min(x, y, w - 1 - x, h - 1 - y) < depth:
                out.append(px[x, y])
    return out


def _is_goldish(r: int, g: int, b: int) -> bool:
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return 0.08 <= h <= 0.18 and s >= 0.35 and v >= 0.35


def _pick_colors(samples: List[Tuple[int, int, int]], *, stripe: bool) -> Tuple[List[str], str]:
    q = Counter((r // 16 * 16 + 8, g // 16 * 16 + 8, b // 16 * 16 + 8) for r, g, b in samples)
    dark = q.most_common(1)[0][0]

    golds = [c for c in samples if _is_goldish(*c)]
    gold: Optional[Tuple[int, int, int]] = None
    if golds:
        gold = Counter((r // 16 * 16 + 8, g // 16 * 16 + 8, b // 16 * 16 + 8) for r, g, b in golds).most_common(1)[0][0]

    best: Optional[Tuple[int, int, int]] = None
    best_score = -1.0
    for r, g, b in samples:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if v < 0.15 or s < 0.25:
            continue
        score = s * v
        if score > best_score:
            best_score = score
            best = (r, g, b)

    if stripe:
        cols: List[Tuple[int, int, int]] = [dark]
        if gold is not None:
            cols.append(gold)
        elif best is not None and sum(abs(best[i] - dark[i]) for i in range(3)) > 80:
            cols.append(best)
        else:
            for c, _ in q.most_common(6):
                if sum(abs(c[i] - dark[i]) for i in range(3)) > 50:
                    cols.append(c)
                    break
        if len(cols) < 2:
            cols.append((255, 215, 0))
        return [_rgb_to_hex(c) for c in cols[:2]], "stripes"

    if gold is not None:
        return [_rgb_to_hex(gold)], "solid"
    if best is not None and sum(abs(best[i] - dark[i]) for i in range(3)) > 60:
        return [_rgb_to_hex(best)], "solid"
    return [_rgb_to_hex(dark)], "solid"


def _sample_shop() -> Dict[str, Tuple[List[str], str]]:
    out: Dict[str, Tuple[List[str], str]] = {}
    for overlay in sorted(SHOP_MEDIA.glob("*/table_design_overlay_*.webp")):
        pack = overlay.parent.name
        item_id = f"table_design_{pack}"
        colors, style = _pick_colors(_border_pixels(overlay), stripe=pack in STRIPE_SHOP)
        if pack == "racing":
            colors = ["#181818", "#FFD700"]
            style = "stripes"
        out[item_id] = (colors, style)
    return out


def _sample_events() -> Dict[str, Tuple[List[str], str]]:
    out: Dict[str, Tuple[List[str], str]] = {}
    for overlay in sorted(EVENT_MEDIA.glob("*/table_design_overlay_*.webp")):
        event_id = overlay.parent.name
        colors, style = _pick_colors(_border_pixels(overlay), stripe=event_id in STRIPE_EVENTS)
        if event_id == "the_challenger":
            colors = ["#204080", "#B02828"]
            style = "stripes"
        elif event_id == "dutch_fan":
            colors = ["#9020D0"]
        elif event_id == "dutch_hobbyist":
            colors = ["#485878"]
        elif event_id == "dutch_explorer":
            colors = ["#284868"]
        out[event_id] = (colors, style)
    return out


def _apply_consumables(path: Path, shop: Dict[str, Tuple[List[str], str]]) -> int:
    doc = json.loads(path.read_text(encoding="utf-8"))
    changed = 0
    for item in doc.get("items") or []:
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("item_id") or "")
        if item_id not in shop:
            continue
        colors, border_style = shop[item_id]
        style = item.setdefault("style", {})
        if not isinstance(style, dict):
            continue
        if style.get("border_style") != border_style or style.get("border_colors") != colors:
            style["border_style"] = border_style
            style["border_colors"] = colors
            changed += 1
    if changed:
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def _apply_table_tiers(path: Path, events: Dict[str, Tuple[List[str], str]]) -> int:
    doc = json.loads(path.read_text(encoding="utf-8"))
    changed = 0
    for ev in doc.get("special_events") or []:
        if not isinstance(ev, dict):
            continue
        eid = str(ev.get("id") or "")
        if eid not in events:
            continue
        colors, border_style = events[eid]
        style = ev.setdefault("style", {})
        if not isinstance(style, dict):
            continue
        if style.get("border_style") != border_style or style.get("border_colors") != colors:
            style["border_style"] = border_style
            style["border_colors"] = colors
            changed += 1
    if changed:
        doc["schema_version"] = max(int(doc.get("schema_version") or 1), 5)
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync table border colors from overlay art")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    shop = _sample_shop()
    events = _sample_events()

    print("Shop table_design border_colors:")
    for item_id, (colors, style) in sorted(shop.items()):
        print(f"  {item_id}: {style} {colors}")
    print("\nSpecial event border_colors:")
    for eid, (colors, style) in sorted(events.items()):
        print(f"  {eid}: {style} {colors}")

    if args.dry_run:
        return 0

    c1 = _apply_consumables(CONSUMABLES_PATH, shop)
    c2 = sum(_apply_table_tiers(p, events) for p in TABLE_TIERS_PATHS)
    print(f"\nUpdated consumables items: {c1}; table_tiers files: {c2}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
