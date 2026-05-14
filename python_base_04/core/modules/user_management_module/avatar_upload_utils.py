"""
Validate and normalize profile avatar uploads (security: size, extension, MIME, magic bytes, Pillow).
"""
from __future__ import annotations

import io
import os
import re
from typing import Optional, Tuple


# Allowed client filename extensions (case-insensitive).
ALLOWED_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".webp"})

# Stored file name pattern (opaque id + .webp).
STORED_NAME_RE = re.compile(r"^[a-f0-9]{32}\.webp$")


def allowed_upload_extension(filename: Optional[str]) -> bool:
    if not filename or not filename.strip():
        return False
    base = os.path.basename(filename.strip())
    lower = base.lower()
    dot = lower.rfind(".")
    if dot < 0:
        return False
    ext = lower[dot:]
    return ext in ALLOWED_EXTENSIONS


def declared_mime_allowed(content_type: Optional[str]) -> bool:
    if not content_type:
        return False
    ct = content_type.split(";")[0].strip().lower()
    return ct in ("image/jpeg", "image/jpg", "image/png", "image/webp")


def detect_format_from_magic(data: bytes) -> Optional[str]:
    """Return 'jpeg', 'png', 'webp', or None if signature does not match."""
    if len(data) < 12:
        return None
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    # WebP: RIFF....WEBP
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def mime_matches_magic(declared_mime: Optional[str], magic_format: str) -> bool:
    if not declared_mime:
        return False
    ct = declared_mime.split(";")[0].strip().lower()
    if magic_format == "jpeg":
        return ct in ("image/jpeg", "image/jpg")
    if magic_format == "png":
        return ct == "image/png"
    if magic_format == "webp":
        return ct == "image/webp"
    return False


def read_upload_bytes(stream, max_bytes: int) -> Tuple[Optional[bytes], Optional[str]]:
    """
    Read at most max_bytes + 1 from stream. If more than max_bytes, return (None, error).
    """
    if max_bytes < 1:
        return None, "invalid_max_bytes"
    buf = bytearray()
    chunk_size = min(65536, max_bytes + 1)
    while len(buf) <= max_bytes:
        chunk = stream.read(chunk_size)
        if not chunk:
            break
        buf.extend(chunk)
        if len(buf) > max_bytes:
            return None, "file_too_large"
    if not buf:
        return None, "empty_file"
    return bytes(buf), None


def process_avatar_image(
    data: bytes,
    *,
    max_edge_px: int,
    max_dimension_px: int,
    max_image_pixels: int,
) -> Tuple[Optional[bytes], Optional[str]]:
    """
    Decode with Pillow, enforce dimensions, strip metadata, re-encode WebP.
    Returns (webp_bytes, None) or (None, error_code).
    """
    try:
        from PIL import Image, ImageOps
    except ImportError:
        return None, "pillow_unavailable"

    fmt = detect_format_from_magic(data)
    if fmt is None:
        return None, "invalid_image_signature"

    old_max = getattr(Image, "MAX_IMAGE_PIXELS", None)
    try:
        Image.MAX_IMAGE_PIXELS = max_image_pixels
        img = Image.open(io.BytesIO(data))
        img.load()
        w, h = img.size
        if w > max_dimension_px or h > max_dimension_px:
            return None, "dimensions_too_large"
        img = ImageOps.exif_transpose(img)
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGBA") if "A" in img.getbands() else img.convert("RGB")
        img.thumbnail((max_edge_px, max_edge_px), Image.Resampling.LANCZOS)
        out = io.BytesIO()
        # WebP; no EXIF in fresh encode
        img.save(out, format="WEBP", quality=85, method=4)
        out_bytes = out.getvalue()
        return out_bytes, None
    except Exception as ex:
        return None, "image_decode_failed"
    finally:
        if old_max is not None:
            Image.MAX_IMAGE_PIXELS = old_max


def safe_join_under_root(root: str, filename: str) -> Optional[str]:
    """Resolve path under root; return None if traversal or invalid name."""
    if not STORED_NAME_RE.match(filename):
        return None
    root_real = os.path.realpath(root)
    candidate = os.path.realpath(os.path.join(root_real, filename))
    if not candidate.startswith(root_real + os.sep) and candidate != root_real:
        return None
    return candidate
