"""Unit tests for gameplay_profiles declarative catalog."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from core.modules.dutch_game import gameplay_profiles_catalog as gpc


class TestGameplayProfilesCatalog(unittest.TestCase):
    def test_extends_merge_collector(self):
        profile = gpc.resolve_profile("collector")
        self.assertTrue(profile["flags"]["clear_and_collect"])
        self.assertTrue(profile["win_conditions"]["four_of_a_kind_collection"])
        self.assertEqual(profile["deal"]["cards_per_hand"], 4)

    def test_speed_classic_timers(self):
        profile = gpc.resolve_profile("speed_classic")
        self.assertEqual(profile["timers"]["playing_card"], 8)
        self.assertFalse(profile["flags"]["clear_and_collect"])

    def test_reload_updates_revision(self):
        original_doc = gpc.load_raw_document()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "gameplay_profiles.json"
                doc_v1 = {
                    "schema_version": 1,
                    "profiles": {
                        "classic": {
                            "id": "classic",
                            "label": "Classic",
                            "flags": {"clear_and_collect": False},
                        }
                    },
                }
                path.write_text(json.dumps(doc_v1), encoding="utf-8")

                with mock.patch.object(gpc, "load_raw_document", side_effect=lambda: json.loads(path.read_text())), \
                     mock.patch("core.modules.dutch_game.table_tiers_catalog.validate_special_event_profile_refs"):
                    first = gpc.reload_from_disk()
                    rev1 = gpc.GAMEPLAY_PROFILES_REVISION
                    self.assertEqual(first["profile_count"], 1)

                    doc_v2 = dict(doc_v1)
                    doc_v2["profiles"] = dict(doc_v1["profiles"])
                    doc_v2["profiles"]["speed_classic"] = {
                        "id": "speed_classic",
                        "label": "Speed",
                        "extends": "classic",
                        "timers": {"playing_card": 5},
                    }
                    path.write_text(json.dumps(doc_v2), encoding="utf-8")
                    second = gpc.reload_from_disk()

                    self.assertNotEqual(rev1, gpc.GAMEPLAY_PROFILES_REVISION)
                    self.assertTrue(second["reloaded"])
                    self.assertEqual(gpc.resolve_profile("speed_classic")["timers"]["playing_card"], 5)
        finally:
            with mock.patch.object(gpc, "load_raw_document", return_value=original_doc):
                gpc.reload_from_disk()

    def test_unknown_profile_raises(self):
        with self.assertRaises(gpc.GameplayProfileCatalogError):
            gpc.resolve_profile("does_not_exist")


if __name__ == "__main__":
    unittest.main()
