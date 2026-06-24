#!/usr/bin/env python3
"""Regenerate assets/lottie/final_round_call.lottie (clock shake + logo spin + text)."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
CLOCK_SRC = ROOT / "images" / "final_round_clock.png"
LOGO_SRC = ROOT / "images" / "final_round_logo.png"
OUT = ROOT / "final_round_call.lottie"
BUILD = ROOT / "_build_final_round_call"

W, H = 256, 256
CX, CY = W / 2, H / 2 + 4
# White face centre in clock art (~130×150); logo sits slightly below composition centre.
LOGO_CY_OFFSET = 6
# Max logo dimension to sit inside the white circle (diameter ≈96px).
LOGO_FACE_MAX_PX = 76
FR = 30
IP = 0
OP = 90

# Ease handles for Lottie segments.
EASE_IN_OUT = {"i": {"x": [0.42], "y": [0]}, "o": {"x": [0.58], "y": [1]}}
EASE_OUT = {"i": {"x": [0.667], "y": [1]}, "o": {"x": [0.333], "y": [0]}}


def hold(val, t=0):
    return {"t": t, "s": val}


def vec3(x, y, z=0):
    return [x, y, z]


def load_rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def prepare_text_image() -> Image.Image:
    text_img = Image.new("RGBA", (220, 72), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_img)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 34)
    except OSError:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 32)
        except OSError:
            font = ImageFont.load_default()
    text = "Final Round"
    bbox = text_draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    text_draw.text(
        ((220 - tw) / 2 - bbox[0], (72 - th) / 2 - bbox[1]),
        text,
        fill=(245, 83, 51, 255),
        font=font,
    )
    return text_img


def shake_pos_kf(y_offset: float = 0):
    """Position shake only — no rotation on the clock."""
    offsets = [
        (0, 0), (3, -2), (-4, 3), (5, -3), (-3, 2), (4, -2), (-2, 3), (3, -1),
        (-2, 1), (2, -1), (-1, 0), (1, 0), (0, 0), (0, 0), (0, 0), (0, 0),
        (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0),
    ]
    base_y = CY + y_offset
    kfs = [hold(vec3(CX + ox, base_y + oy, 0), i) for i, (ox, oy) in enumerate(offsets)]
    kfs.append(hold(vec3(CX, base_y, 0), 40))
    kfs.append(hold(vec3(CX, base_y, 0), OP))
    return {"a": 1, "k": kfs}


def logo_scale_percent(logo_w: int, logo_h: int) -> float:
    """Scale logo so it fits inside the clock's white face."""
    max_dim = max(logo_w, logo_h)
    return round((LOGO_FACE_MAX_PX / max_dim) * 100, 2)


def clock_logo_fade_opacity_kf():
    """Ease-out fade for clock and logo together."""
    return {
        "a": 1,
        "k": [
            hold(100, 0),
            hold(100, 41),
            {**hold(0, 58), **EASE_OUT},
            hold(0, OP),
        ],
    }


def logo_rotation_kf():
    """Ease-in / ease-out spin — faster rotation, clock does not rotate."""
    return {
        "a": 1,
        "k": [
            hold(0, 0),
            hold(0, 6),
            {**hold(720, 38), **EASE_IN_OUT},
            {**hold(810, 56), **EASE_OUT},
            hold(810, OP),
        ],
    }


def text_opacity_kf():
    """Visible before clock/logo fade completes."""
    return {
        "a": 1,
        "k": [
            hold(0, 0),
            hold(0, 34),
            {**hold(100, 40), **EASE_IN_OUT},
            hold(100, OP),
        ],
    }


def text_scale_kf():
    return {
        "a": 1,
        "k": [
            hold([88, 88, 100], 0),
            hold([88, 88, 100], 34),
            {**hold([100, 100, 100], 42), **EASE_IN_OUT},
            hold([100, 100, 100], OP),
        ],
    }


def image_layer(index: int, name: str, ref_id: str, anchor: list[float], ks: dict):
    return {
        "ddd": 0,
        "ind": index,
        "ty": 2,
        "nm": name,
        "refId": ref_id,
        "sr": 1,
        "ks": ks,
        "ao": 0,
        "ip": 0,
        "op": OP,
        "st": 0,
        "bm": 0,
    }


def main() -> None:
    if not CLOCK_SRC.exists() or not LOGO_SRC.exists():
        raise SystemExit(f"Missing clock/logo images under {ROOT / 'images'}")

    clock_img = load_rgba(CLOCK_SRC)
    logo_img = load_rgba(LOGO_SRC)
    text_img = prepare_text_image()
    text_img_path = BUILD / "images" / "final_round_text.png"
    text_img_path.parent.mkdir(parents=True, exist_ok=True)
    text_img.save(text_img_path, format="PNG")

    clock_w, clock_h = clock_img.size
    logo_w, logo_h = logo_img.size
    text_w, text_h = text_img.size
    logo_scale = logo_scale_percent(logo_w, logo_h)

    clock_shake = shake_pos_kf()
    logo_shake = shake_pos_kf(y_offset=LOGO_CY_OFFSET)
    fade_opacity = clock_logo_fade_opacity_kf()

    clock_ks = {
        "o": fade_opacity,
        "r": {"a": 0, "k": 0},
        "p": clock_shake,
        "a": {"a": 0, "k": [clock_w / 2, clock_h / 2, 0]},
        "s": {"a": 0, "k": [100, 100, 100]},
    }

    logo_ks = {
        "o": fade_opacity,
        "r": logo_rotation_kf(),
        "p": logo_shake,
        "a": {"a": 0, "k": [logo_w / 2, logo_h / 2, 0]},
        "s": {"a": 0, "k": [logo_scale, logo_scale, 100]},
    }

    text_ks = {
        "o": text_opacity_kf(),
        "r": {"a": 0, "k": 0},
        "p": {"a": 0, "k": vec3(CX, CY, 0)},
        "a": {"a": 0, "k": [text_w / 2, text_h / 2, 0]},
        "s": text_scale_kf(),
    }

    assets = [
        {
            "id": "image_clock",
            "w": clock_w,
            "h": clock_h,
            "u": "images/",
            "p": "final_round_clock.png",
            "e": 0,
        },
        {
            "id": "image_logo",
            "w": logo_w,
            "h": logo_h,
            "u": "images/",
            "p": "final_round_logo.png",
            "e": 0,
        },
        {
            "id": "image_text",
            "w": text_w,
            "h": text_h,
            "u": "images/",
            "p": "final_round_text.png",
            "e": 0,
        },
    ]

    # Lottie: last layer in the list is drawn on top.
    layers = [
        image_layer(1, "Clock", "image_clock", [clock_w / 2, clock_h / 2, 0], clock_ks),
        image_layer(2, "Logo", "image_logo", [logo_w / 2, logo_h / 2, 0], logo_ks),
        image_layer(3, "Final Round Text", "image_text", [text_w / 2, text_h / 2, 0], text_ks),
    ]

    composition = {
        "v": "5.7.4",
        "fr": FR,
        "ip": IP,
        "op": OP,
        "w": W,
        "h": H,
        "nm": "Final Round Call",
        "ddd": 0,
        "assets": assets,
        "layers": layers,
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
        zf.write(CLOCK_SRC, "images/final_round_clock.png")
        zf.write(LOGO_SRC, "images/final_round_logo.png")
        zf.write(text_img_path, "images/final_round_text.png")

    print(f"Wrote {OUT} (logo scale {logo_scale}%)")


if __name__ == "__main__":
    main()
