"""
Single source of truth for Dutch coin SKUs (Google Play, App Store, Stripe web).
Data file: flutter_base_05/assets/dutch_coin_catalog.json (same path the Flutter app bundles).
Native UI rows: store_recommended_packages (legacy play_recommended_packages).
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Tuple

_CATALOG_FILENAME = "dutch_coin_catalog.json"


def _catalog_path_candidates() -> List[Path]:
    """SSOT file lives in flutter_base_05/assets; Docker image bundles a copy under /app/assets/."""
    app_root = Path(__file__).resolve().parents[1]
    repo_root = app_root.parent
    return [
        app_root / "assets" / _CATALOG_FILENAME,
        repo_root / "flutter_base_05" / "assets" / _CATALOG_FILENAME,
    ]


def _resolve_catalog_path() -> Path:
    for path in _catalog_path_candidates():
        if path.is_file():
            return path
    tried = ", ".join(str(p) for p in _catalog_path_candidates())
    raise FileNotFoundError(f"Coin catalog missing (tried: {tried})")


@lru_cache(maxsize=1)
def _raw_catalog() -> Dict[str, Any]:
    catalog_path = _resolve_catalog_path()
    with open(catalog_path, "r", encoding="utf-8") as f:
        return json.load(f)


def get_subscriber_coin_bonus_percent() -> int:
    """Percent extra coins for premium tier (e.g. 11 => +11% coins)."""
    raw = _raw_catalog()
    try:
        return max(0, int(raw.get("subscriber_coin_bonus_percent") or 0))
    except (TypeError, ValueError):
        return 0


def get_premium_subscription_config() -> Dict[str, Any]:
    """Premium subscription IDs for Play (SKU + base plans) and Apple (product IDs)."""
    raw = _raw_catalog()
    prem = raw.get("premium_subscription")
    if not isinstance(prem, dict):
        return {}
    product_id = str(prem.get("product_id") or "").strip()
    base_plans = prem.get("base_plans") if isinstance(prem.get("base_plans"), dict) else {}
    apple_ids = prem.get("apple_product_ids") if isinstance(prem.get("apple_product_ids"), dict) else {}
    return {
        "product_id": product_id,
        "base_plans": {
            "monthly": str(base_plans.get("monthly") or "").strip(),
            "yearly": str(base_plans.get("yearly") or "").strip(),
        },
        "apple_product_ids": {
            "monthly": str(apple_ids.get("monthly") or "").strip(),
            "yearly": str(apple_ids.get("yearly") or "").strip(),
        },
        "benefits_short": str(prem.get("benefits_short") or "").strip(),
    }


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


def _store_recommended_rows() -> List[Dict[str, Any]]:
    """Catalog rows for native store UI (Play + App Store). Prefers `store_recommended_packages`."""
    raw = _raw_catalog()
    rows = raw.get("store_recommended_packages")
    if not rows:
        rows = raw.get("play_recommended_packages") or []
    return rows if isinstance(rows, list) else []


def get_store_recommended_packages() -> List[Dict[str, Any]]:
    """Rows for native store UI: product_id, label, coins, description, optional priceLabel, optional isPopular."""
    out: List[Dict[str, Any]] = []
    products = get_in_app_product_coins()
    for row in _store_recommended_rows():
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


def get_play_recommended_packages() -> List[Dict[str, Any]]:
    """Deprecated alias for [get_store_recommended_packages]."""
    return get_store_recommended_packages()


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
