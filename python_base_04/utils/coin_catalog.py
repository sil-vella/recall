"""
Single source of truth for Dutch coin SKUs (native RevenueCat product ids + Stripe web packages).
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


def get_revenuecat_product_coins() -> Dict[str, int]:
    """Play/App Store product id -> coin amount."""
    data = _raw_catalog().get("revenuecat_products") or {}
    return {str(k): int(v) for k, v in data.items() if int(v) > 0}


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
        rows.append(
            {
                "key": row["key"],
                "label": row["label"],
                "coins": int(row["coins"]),
                "price_id": price_id,
            }
        )
    return tuple(rows)
