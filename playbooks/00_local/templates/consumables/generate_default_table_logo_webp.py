#!/usr/bin/env python3
"""Build bundled default table overlay: flutter_base_05/assets/images/table_logo.webp

Source: assets/images/logo_icon.webp
Output: 1024x576 RGBA WebP (same size as shop table_design overlays)
  - Logo fits within 60% of canvas, centered
  - Logo recolored black at 25% opacity
"""

from __future__ import annotations

from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent.parent
FLUTTER_ASSETS = PROJECT_ROOT / "flutter_base_05" / "assets" / "images"
SRC = FLUTTER_ASSETS / "logo_icon.webp"
OUT = FLUTTER_ASSETS / "table_logo.webp"

TABLE_SIZE = (1024, 576)
LOGO_MAX_FRAC = 0.60
LOGO_OPACITY = 0.25


def main() -> int:
    try:
        from PIL import Image
    except ImportError:
        print("Error: Pillow required (pip install Pillow)", flush=True)
        return 1

    if not SRC.is_file():
        print(f"Error: missing {SRC}", flush=True)
        return 1

    src = Image.open(SRC).convert("RGBA")
    px = src.load()
    for y in range(src.height):
        for x in range(src.width):
            _, _, _, a = px[x, y]
            if a:
                px[x, y] = (0, 0, 0, a)

    max_w = int(TABLE_SIZE[0] * LOGO_MAX_FRAC)
    max_h = int(TABLE_SIZE[1] * LOGO_MAX_FRAC)
    logo = src.copy()
    logo.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)

    r, g, b, a = logo.split()
    a = a.point(lambda p: int(p * LOGO_OPACITY))
    logo = Image.merge("RGBA", (r, g, b, a))

    canvas = Image.new("RGBA", TABLE_SIZE, (0, 0, 0, 0))
    ox = (TABLE_SIZE[0] - logo.width) // 2
    oy = (TABLE_SIZE[1] - logo.height) // 2
    canvas.alpha_composite(logo, (ox, oy))
    canvas.save(OUT, format="WEBP", quality=90)
    print(f"Wrote {OUT} ({TABLE_SIZE[0]}x{TABLE_SIZE[1]}) logo={logo.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
