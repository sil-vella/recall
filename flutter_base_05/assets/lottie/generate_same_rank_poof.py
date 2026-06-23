#!/usr/bin/env python3
"""Regenerate assets/lottie/same_rank_poof.lottie from the Dutch card asset."""

from __future__ import annotations

import base64
import json
import math
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "images" / "dutch_card_icon.png"
OUT = ROOT / "same_rank_poof.lottie"
BUILD = ROOT / "_build_same_rank_poof"

W, H = 256, 256
CARD_W, CARD_H = 150, 150
CX, CY = W / 2, H / 2
ANCHOR = [CARD_W / 2, CARD_H / 2, 0]
FR = 30
IP = 0
OP = 60


def hold(val, t=0):
    return {
        "i": {"x": [0.667], "y": [1]},
        "o": {"x": [0.333], "y": [0]},
        "t": t,
        "s": val,
    }


def vec3(x, y, z=0):
    return [x, y, z]


def shake_pos_kf():
    offsets = [
        (0, 0), (2, -3), (-4, 2), (5, -2), (-3, 3), (4, -1), (-2, 2), (3, -2),
        (-1, 1), (2, -1), (-1, 0), (1, 0), (0, 0), (0, 0), (0, 0),
    ]
    return {"a": 1, "k": [hold(vec3(CX + ox, CY + oy, 0), i) for i, (ox, oy) in enumerate(offsets)]}


def shake_rot_kf():
    rots = [0, 2.5, -3, 2, -2.5, 1.5, -1, 0.8, -0.5, 0.3, 0, 0, 0, 0, 0]
    return {"a": 1, "k": [hold([r, 0, 0], i) for i, r in enumerate(rots)]}


def card_scale_kf():
    return {
        "a": 1,
        "k": [
            hold([100, 100, 100], 0),
            hold([100, 100, 100], 14),
            hold([108, 108, 100], 18),
            hold([0, 0, 100], 32),
            hold([0, 0, 100], 60),
        ],
    }


def card_opacity_kf():
    return {
        "a": 1,
        "k": [
            hold([100], 0),
            hold([100], 16),
            hold([100], 20),
            hold([0], 34),
            hold([0], 60),
        ],
    }


def shape_transform():
    return {
        "ty": "tr",
        "p": {"a": 0, "k": [0, 0]},
        "a": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": [100, 100]},
        "r": {"a": 0, "k": 0},
        "o": {"a": 0, "k": 100},
        "sk": {"a": 0, "k": 0},
        "sa": {"a": 0, "k": 0},
    }


def fill_item(color, opacity=100):
    return {
        "ty": "fl",
        "c": {"a": 0, "k": color},
        "o": {"a": 0, "k": opacity},
        "r": 1,
        "bm": 0,
    }


def smoke_wisp_layer(
    index: int,
    *,
    angle_deg: float,
    delay: int,
    origin_offset: tuple[float, float],
    size_w: float,
    size_h: float,
    drift: float,
    peak_opacity: float,
    color: list[float],
    shape: str = "el",
    round_r: float = 0,
    rot: float = 0,
    scale_end: tuple[float, float] | None = None,
    duration: int = 24,
):
    """Single asymmetric smoke wisp — irregular size, drift, and fade."""
    rad = math.radians(angle_deg)
    ox, oy = origin_offset
    start_x = CX + ox
    start_y = CY + oy
    dx = math.cos(rad) * drift
    dy = math.sin(rad) * drift
    start_t = 16 + delay
    mid_t = start_t + int(duration * 0.35)
    end_t = start_t + duration
    end_sx, end_sy = scale_end or (size_w * 2.4, size_h * 2.1)

    if shape == "rc":
        geom = {
            "ty": "rc",
            "p": {"a": 0, "k": [0, 0]},
            "s": {"a": 0, "k": [size_w, size_h]},
            "r": {"a": 0, "k": round_r},
        }
    else:
        geom = {
            "ty": "el",
            "p": {"a": 0, "k": [0, 0]},
            "s": {"a": 0, "k": [size_w, size_h]},
        }

    return {
        "ddd": 0,
        "ind": 20 + index,
        "ty": 4,
        "nm": f"Smoke Wisp {index}",
        "sr": 1,
        "ks": {
            "o": {
                "a": 1,
                "k": [
                    hold([0], 0),
                    hold([0], start_t),
                    hold([peak_opacity], start_t + 1),
                    hold([peak_opacity * 0.72], mid_t),
                    hold([peak_opacity * 0.25], mid_t + 6),
                    hold([0], end_t),
                    hold([0], 60),
                ],
            },
            "r": {"a": 0, "k": [rot, 0, 0]},
            "p": {
                "a": 1,
                "k": [
                    hold(vec3(start_x, start_y, 0), 0),
                    hold(vec3(start_x, start_y, 0), start_t),
                    hold(vec3(start_x + dx * 0.22, start_y + dy * 0.22), start_t + 3),
                    hold(vec3(start_x + dx * 0.62, start_y + dy * 0.62), mid_t),
                    hold(vec3(start_x + dx, start_y + dy), end_t),
                    hold(vec3(start_x + dx, start_y + dy), 60),
                ],
            },
            "a": {"a": 0, "k": [0, 0, 0]},
            "s": {
                "a": 1,
                "k": [
                    hold([28, 22, 100], 0),
                    hold([28, 22, 100], start_t),
                    hold([end_sx * 0.55, end_sy * 0.5, 100], mid_t),
                    hold([end_sx, end_sy, 100], end_t),
                    hold([end_sx, end_sy, 100], 60),
                ],
            },
        },
        "ao": 0,
        "shapes": [
            {
                "ty": "gr",
                "it": [geom, fill_item(color), shape_transform()],
                "nm": "Wisp",
                "np": 2,
                "cix": 2,
                "bm": 0,
            }
        ],
        "ip": 0,
        "op": 60,
        "st": 0,
        "bm": 0,
    }


def smoke_core_layer():
    """Dense central puff — slightly off-center, not a perfect circle."""
    return smoke_wisp_layer(
        0,
        angle_deg=292,
        delay=0,
        origin_offset=(-4, 2),
        size_w=58,
        size_h=42,
        drift=12,
        peak_opacity=88,
        color=[0.97, 0.97, 0.97, 1],
        rot=-18,
        scale_end=(95, 72),
        duration=18,
    )


def smoke_specs():
    """Asymmetric burst: mostly up/left, a few side wisps, no radial symmetry."""
    white = [1, 1, 1, 1]
    gray = [0.82, 0.82, 0.84, 1]
    pale = [0.9, 0.9, 0.92, 1]
    return [
        # index, angle, delay, (ox,oy), w, h, drift, peak_op, color, shape, round, rot, duration
        (1, 278, 0, (-8, 6), 46, 28, 34, 78, white, "rc", 14, -24, 26),
        (2, 312, 1, (6, 4), 38, 52, 28, 65, pale, "el", 0, 12, 22),
        (3, 255, 2, (-12, -2), 52, 30, 22, 58, gray, "rc", 10, -35, 24),
        (4, 334, 0, (10, -4), 34, 44, 31, 70, white, "el", 0, 28, 23),
        (5, 290, 3, (-2, 8), 62, 36, 38, 82, white, "rc", 18, -8, 28),
        (6, 228, 2, (-16, 10), 28, 18, 19, 45, gray, "rc", 8, -42, 20),
        (7, 350, 4, (14, 6), 24, 36, 26, 52, pale, "el", 0, 40, 21),
        (8, 198, 5, (-6, 14), 30, 22, 16, 38, gray, "rc", 6, -55, 18),
        (9, 305, 1, (2, -6), 20, 14, 42, 48, white, "rc", 5, 15, 25),
        (10, 268, 3, (-10, -8), 18, 26, 20, 42, pale, "el", 0, -20, 19),
        (11, 325, 5, (8, 12), 16, 22, 30, 35, gray, "el", 0, 33, 17),
    ]


def build_smoke_layers():
    layers = [smoke_core_layer()]
    for spec in smoke_specs():
        idx, ang, delay, off, w, h, drift, peak, color, shape, rnd, rot, dur = spec
        layers.append(
            smoke_wisp_layer(
                idx,
                angle_deg=ang,
                delay=delay,
                origin_offset=off,
                size_w=w,
                size_h=h,
                drift=drift,
                peak_opacity=peak,
                color=color,
                shape=shape,
                round_r=rnd,
                rot=rot,
                duration=dur,
            )
        )
    return layers


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Missing source image: {SRC}")

    b64 = base64.b64encode(SRC.read_bytes()).decode("ascii")
    card_layer = {
        "ddd": 0,
        "ind": 1,
        "ty": 2,
        "nm": "Dutch Card",
        "refId": "image_0",
        "sr": 1,
        "ks": {
            "o": card_opacity_kf(),
            "r": shake_rot_kf(),
            "p": shake_pos_kf(),
            "a": {"a": 0, "k": ANCHOR},
            "s": card_scale_kf(),
        },
        "ao": 0,
        "ip": 0,
        "op": 60,
        "st": 0,
        "bm": 0,
    }

    composition = {
        "v": "5.7.4",
        "fr": FR,
        "ip": IP,
        "op": OP,
        "w": W,
        "h": H,
        "nm": "Same Rank Poof",
        "ddd": 0,
        "assets": [
            {
                "id": "image_0",
                "w": CARD_W,
                "h": CARD_H,
                "u": "",
                "p": f"data:image/png;base64,{b64}",
                "e": 1,
            }
        ],
        "layers": [card_layer] + build_smoke_layers(),
        "markers": [],
    }

    anim_path = BUILD / "a" / "Main Scene.json"
    anim_path.parent.mkdir(parents=True, exist_ok=True)
    anim_path.write_text(json.dumps(composition, separators=(",", ":")))
    manifest_path = BUILD / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "version": "2",
                "generator": "@dotlottie/dotlottie-js@1.6.2",
                "animations": [{"id": "Main Scene"}],
            },
            separators=(",", ":"),
        )
    )

    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(anim_path, "a/Main Scene.json")
        zf.write(manifest_path, "manifest.json")

    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
