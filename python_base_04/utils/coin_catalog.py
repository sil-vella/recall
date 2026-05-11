"""
Single source of truth for Dutch coin SKUs (future native store product ids + Stripe web packages).
Data file: flutter_base_05/assets/dutch_coin_catalog.json (same path the Flutter app bundles).
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Tuple

_CATALOG_PATH = Path(__file__).resolve().parents[2] / "flutter_base_05" / "assets" / "dutch_coin_catalog.json"


@lru_cache(maxsize=1)
def _raw_catalog() -> Dict[str, Any]:
    if not _CATALOG_PATH.is_file():
        raise FileNotFoundError(f"Coin catalog missing: {_CATALOG_PATH}")
    with open(_CATALOG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def get_in_app_product_coins() -> Dict[str, int]:
    """Native store product id -> coin amount (key `in_app_products` in JSON; legacy `revenuecat_products` supported)."""
    raw = _raw_catalog()
    data = raw.get("in_app_products") or raw.get("revenuecat_products") or {}
    return {str(k): int(v) for k, v in data.items() if int(v) > 0}


def _coin_pack_description(coins: int, row: Dict[str, Any]) -> str:
    if row.get("description"):
        return str(row["description"]).strip()
    tpl = str((_raw_catalog().get("coin_pack_description_template") or "")).strip()
    if tpl and "{coins}" in tpl:
        return tpl.replace("{coins}", str(int(coins)))
    return f"Adds {int(coins)} coins to your balance. Coins are used for table fees and in-game purchases."


def get_play_recommended_packages() -> List[Dict[str, Any]]:
    """Rows for Google Play store UI: product_id, label, coins, description, optional priceLabel, optional isPopular."""
    out: List[Dict[str, Any]] = []
    products = get_in_app_product_coins()
    for row in _raw_catalog().get("play_recommended_packages") or []:
        pid = str(row.get("product_id") or "").strip()
        if not pid or pid not in products:
            continue
        coins = int(products[pid])
        desc = _coin_pack_description(coins, row)
        out.append(
            {
                "product_id": pid,
                "label": str(row.get("label") or pid),
                "coins": coins,
                "description": desc,
                "priceLabel": str(row.get("priceLabel") or ""),
                "isPopular": bool(row.get("isPopular")),
            }
        )
    return out


def get_stripe_package_rows(config_module: Any) -> Tuple[Dict[str, Any], ...]:
    """
    Build rows like legacy _coin_package_rows: key, label, coins, price_id from Config.
    config_module: utils.config.config.Config (passed to avoid circular import at load time).
    """
    rows: List[Dict[str, Any]] = []
    for row in _raw_catalog().get("stripe_packages") or []:
        env_key = (row.get("stripe_price_env") or "").strip()
        price_raw = ""
        if env_key and hasattr(config_module, env_key):
            price_raw = getattr(config_module, env_key) or ""
        price_id = (str(price_raw).strip() or None) if price_raw else None
        c = int(row["coins"])
        rows.append(
            {
                "key": row["key"],
                "label": row["label"],
                "coins": c,
                "description": _coin_pack_description(c, row),
                "price_id": price_id,
            }
        )
    return tuple(rows)
