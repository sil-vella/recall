"""Unit tests for profile avatar upload validation helpers."""
import io
import os
import sys
import unittest

# Ensure python_base_04 is on path when run as `python tools/tests/test_avatar_upload_utils.py`
_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from PIL import Image

from core.modules.user_management_module import avatar_upload_utils as avu


def _tiny_png_bytes() -> bytes:
    img = Image.new("RGB", (8, 8), color=(120, 40, 200))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _tiny_jpeg_bytes() -> bytes:
    img = Image.new("RGB", (8, 8), color=(10, 100, 50))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


class TestAvatarUploadUtils(unittest.TestCase):
    def test_allowed_extension(self):
        self.assertTrue(avu.allowed_upload_extension("photo.JPEG"))
        self.assertTrue(avu.allowed_upload_extension("x.webp"))
        self.assertFalse(avu.allowed_upload_extension("x.png.exe"))
        self.assertFalse(avu.allowed_upload_extension("x.gif"))
        self.assertFalse(avu.allowed_upload_extension(""))

    def test_declared_mime(self):
        self.assertTrue(avu.declared_mime_allowed("image/jpeg"))
        self.assertTrue(avu.declared_mime_allowed("image/png; charset=binary"))
        self.assertTrue(avu.declared_mime_allowed("image/webp"))
        self.assertFalse(avu.declared_mime_allowed("image/gif"))
        self.assertFalse(avu.declared_mime_allowed("application/octet-stream"))

    def test_magic_png_jpeg(self):
        png = _tiny_png_bytes()
        self.assertEqual(avu.detect_format_from_magic(png), "png")
        jpg = _tiny_jpeg_bytes()
        self.assertEqual(avu.detect_format_from_magic(jpg), "jpeg")

    def test_mime_matches_magic(self):
        png = _tiny_png_bytes()
        self.assertTrue(avu.mime_matches_magic("image/png", avu.detect_format_from_magic(png)))
        jpg = _tiny_jpeg_bytes()
        self.assertTrue(avu.mime_matches_magic("image/jpeg", avu.detect_format_from_magic(jpg)))
        self.assertFalse(avu.mime_matches_magic("image/png", "jpeg"))

    def test_read_upload_bytes_limit(self):
        stream = io.BytesIO(b"x" * 100)
        data, err = avu.read_upload_bytes(stream, max_bytes=50)
        self.assertIsNone(data)
        self.assertEqual(err, "file_too_large")

        stream2 = io.BytesIO(b"abc")
        data2, err2 = avu.read_upload_bytes(stream2, max_bytes=50)
        self.assertEqual(data2, b"abc")
        self.assertIsNone(err2)

    def test_process_avatar_image_png(self):
        png = _tiny_png_bytes()
        webp, err = avu.process_avatar_image(
            png,
            max_edge_px=256,
            max_dimension_px=4096,
            max_image_pixels=20_000_000,
        )
        self.assertIsNone(err)
        self.assertIsNotNone(webp)
        self.assertGreater(len(webp), 10)
        self.assertEqual(avu.detect_format_from_magic(webp), "webp")

    def test_process_rejects_bad_signature(self):
        webp, err = avu.process_avatar_image(
            b"not an image at all" * 5,
            max_edge_px=256,
            max_dimension_px=4096,
            max_image_pixels=20_000_000,
        )
        self.assertIsNone(webp)
        self.assertEqual(err, "invalid_image_signature")

    def test_safe_join_under_root(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            name = "a" * 32 + ".webp"
            path = os.path.join(tmp, name)
            with open(path, "wb") as f:
                f.write(b"x")
            resolved = avu.safe_join_under_root(tmp, name)
            self.assertTrue(resolved.endswith(name))
            self.assertIsNone(avu.safe_join_under_root(tmp, "../etc/passwd"))
            self.assertIsNone(avu.safe_join_under_root(tmp, "bad.webp"))


if __name__ == "__main__":
    unittest.main()
