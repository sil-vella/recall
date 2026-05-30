"""Unit tests for in-process catalog hot reload (no Flask restart)."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from core.modules.dutch_game import consumables_catalog as cc
from core.modules.dutch_game import table_tiers_catalog as ttc
from core.modules.dutch_game import catalog_hot_reload
from core.modules.user_management_module import tier_rank_level_matcher as trm
from core.modules.dutch_game import wins_level_rank_matcher as wlm


class TestCatalogHotReload(unittest.TestCase):
    def test_table_tiers_reload_updates_revision_and_aliases(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "table_tiers.json"
            doc_v1 = {
                "schema_version": 1,
                "tiers": [
                    {
                        "level": 1,
                        "title": "Hot Reload Home",
                        "coin_fee": 11,
                        "min_user_level": 1,
                        "style": {"felt_hex": "#111111"},
                    }
                ],
                "special_events": [],
            }
            path.write_text(json.dumps(doc_v1), encoding="utf-8")

            with mock.patch.object(ttc, "load_raw_document", side_effect=lambda: json.loads(path.read_text())):
                first = ttc.reload_from_disk()
                self.assertTrue(first["revision"])
                self.assertEqual(ttc.LEVEL_TO_COIN_FEE.get(1), 11)
                self.assertEqual(trm.LEVEL_TO_COIN_FEE.get(1), 11)
                rev1 = ttc.TABLE_TIERS_REVISION

                doc_v2 = dict(doc_v1)
                doc_v2["tiers"] = [dict(doc_v1["tiers"][0], coin_fee=22, title="Hot Reload Home v2")]
                path.write_text(json.dumps(doc_v2), encoding="utf-8")
                second = ttc.reload_from_disk()

                self.assertNotEqual(rev1, ttc.TABLE_TIERS_REVISION)
                self.assertTrue(second["reloaded"])
                self.assertEqual(ttc.LEVEL_TO_COIN_FEE.get(1), 22)
                self.assertEqual(trm.LEVEL_TO_COIN_FEE.get(1), 22)
                self.assertEqual(wlm.TABLE_LEVEL_MIN, 1)
                self.assertEqual(wlm.TABLE_LEVEL_MAX, 1)

    def test_consumables_reload_updates_item_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "consumables.json"
            doc_v1 = {
                "schema_version": 1,
                "items": [
                    {
                        "item_id": "table_design_test_pack",
                        "item_type": "table_design",
                        "price_coins": 100,
                        "display_name": "Test",
                        "is_active": True,
                        "style": {"border_style": "solid", "border_colors": ["#AABBCC"]},
                    }
                ],
            }
            path.write_text(json.dumps(doc_v1), encoding="utf-8")

            with mock.patch.object(cc, "_load_raw_document", side_effect=lambda: json.loads(path.read_text())):
                cc.reload_from_disk()
                self.assertIsNotNone(cc.find_item("table_design_test_pack"))
                rev1 = cc.CONSUMABLES_CATALOG_REVISION

                doc_v2 = dict(doc_v1)
                doc_v2["items"] = [dict(doc_v1["items"][0], price_coins=200)]
                path.write_text(json.dumps(doc_v2), encoding="utf-8")
                cc.reload_from_disk()

                self.assertNotEqual(rev1, cc.CONSUMABLES_CATALOG_REVISION)
                item = cc.find_item("table_design_test_pack")
                self.assertIsNotNone(item)
                self.assertEqual(item["price_coins"], 200)

    def test_reload_all_catalogs_combined(self):
        result = catalog_hot_reload.reload_all_catalogs()
        self.assertTrue(result["success"])
        self.assertIn("table_tiers", result)
        self.assertIn("consumables_catalog", result)


if __name__ == "__main__":
    unittest.main()
