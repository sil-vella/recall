import unittest

from core.modules.dutch_game import api_endpoints


class TestDutchConsumablesMvp(unittest.TestCase):
    def test_normalize_inventory_defaults(self):
        inv = api_endpoints._normalize_inventory(None)
        self.assertEqual(inv["boosters"][api_endpoints.BOOSTER_ITEM_ID], 0)
        self.assertEqual(inv["cosmetics"]["owned_card_backs"], [])
        self.assertEqual(inv["cosmetics"]["owned_table_designs"], [])

    def test_find_catalog_item(self):
        item = api_endpoints._find_catalog_item(api_endpoints.BOOSTER_ITEM_ID)
        self.assertIsNotNone(item)
        self.assertEqual(item["item_type"], "booster")

    def test_compute_boosted_win_amount(self):
        final_total, multiplier, bonus = api_endpoints._compute_boosted_win_amount(100, has_booster=True)
        self.assertEqual(final_total, 150)
        self.assertEqual(multiplier, 1.5)
        self.assertEqual(bonus, 50)

    def test_compute_boosted_win_amount_without_booster(self):
        final_total, multiplier, bonus = api_endpoints._compute_boosted_win_amount(100, has_booster=False)
        self.assertEqual(final_total, 100)
        self.assertEqual(multiplier, 1.0)
        self.assertEqual(bonus, 0)


if __name__ == "__main__":
    unittest.main()

