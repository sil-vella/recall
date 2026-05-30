"""Unit tests for special-event media URL injection."""

import unittest

from core.modules.dutch_game import table_tiers_catalog as ttc


class TestEventMediaUrls(unittest.TestCase):
    def test_event_media_public_url(self):
        url = ttc._event_media_public_url(
            "https://api.example.com",
            "cards_night",
            "cards_night_background.webp",
        )
        self.assertEqual(
            url,
            "https://api.example.com/app_media/media/event_media/cards_night/cards_night_background.webp",
        )

    def test_build_client_payload_injects_shared_event_art_urls(self):
        doc = ttc.build_client_table_tiers_payload("https://api.example.com")
        events = doc.get("special_events") or []
        cards_night = next(e for e in events if e.get("id") == "cards_night")
        meta = cards_night["metadata"]
        self.assertNotIn("banner_image_file", meta)
        em = meta["end_match_modal"]
        self.assertIn("background_image_url", em)
        self.assertNotIn("background_image_file", em)
        bg_url = em["background_image_url"]
        self.assertTrue(bg_url.endswith("/event_media/cards_night/cards_night_background.webp"))
        self.assertEqual(meta.get("banner_image_url"), bg_url)
        style = cards_night["style"]
        self.assertIn("overlay_image_url", style)
        self.assertNotIn("overlay_image_file", style)
        overlay_url = style["overlay_image_url"]
        self.assertTrue(
            overlay_url.endswith("/event_media/cards_night/table_design_overlay_cards_night.webp")
        )

    def test_tier_back_graphic_still_table_tier_back(self):
        doc = ttc.build_client_table_tiers_payload("https://api.example.com")
        tier = next(t for t in doc["tiers"] if t.get("level") == 1)
        url = tier["style"]["back_graphic_url"]
        self.assertIn("/public/dutch/table-tier-back/", url)


if __name__ == "__main__":
    unittest.main()
