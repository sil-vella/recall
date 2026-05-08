"""
Declarative Dutch consumables/cosmetics catalog.

Single source of truth:
  - config/consumables_catalog.json
  - optional env override via DUTCH_CONSUMABLES_JSON
"""

from __future__ import annotations

import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

_CONFIG_DIR = Path(__file__).resolve().parent / "config"
_DEFAULT_JSON_PATH = _CONFIG_DIR / "consumables_catalog.json"

SUPPORTED_ITEM_TYPES: Set[str] = {"booster", "booster_pack", "card_back", "table_design"}
FALLBACK_WIN_BOOSTER_KEY = "coin_booster_win_x1_5"


def _read_json_file(path: Path) -> Optional[Dict[str, Any]]:
    try:
        if path.is_file():
            with open(path, "r", encoding="utf-8") as f:
                raw = json.load(f)
                if isinstance(raw, dict):
                    return raw
    except Exception:
        pass
    return None


def _merge_env_overlay(doc: Dict[str, Any]) -> Dict[str, Any]:
    raw = (os.getenv("DUTCH_CONSUMABLES_JSON") or "").strip()
    if not raw:
        return doc
    try:
        overlay = json.loads(raw)
    except Exception:
        return doc
    if isinstance(overlay, dict):
        out = deepcopy(doc)
        if isinstance(overlay.get("items"), list):
            out["items"] = overlay["items"]
        if "schema_version" in overlay:
            out["schema_version"] = overlay["schema_version"]
        return out
    if isinstance(overlay, list):
        out = deepcopy(doc)
        out["items"] = overlay
        return out
    return doc


def _normalize_grant(item: Dict[str, Any]) -> Dict[str, Any]:
    effects = item.get("effects") if isinstance(item.get("effects"), dict) else {}
    grant = effects.get("grant") if isinstance(effects.get("grant"), dict) else {}

    booster_key = str(
        grant.get("booster_key")
        or item.get("booster_key")
        or item.get("grant_item_id")
        or item.get("item_id")
    ).strip()
    if not booster_key:
        booster_key = FALLBACK_WIN_BOOSTER_KEY

    qty_raw = grant.get("quantity", item.get("quantity", 1))
    try:
        quantity = int(qty_raw)
    except Exception:
        quantity = 1
    quantity = max(1, quantity)

    return {"booster_key": booster_key, "quantity": quantity}


def _normalize_document(doc: Dict[str, Any]) -> Dict[str, Any]:
    schema_version = int(doc.get("schema_version") or 1)
    raw_items = doc.get("items")
    if not isinstance(raw_items, list):
        return {"schema_version": schema_version, "items": []}

    out: List[Dict[str, Any]] = []
    seen: Set[str] = set()
    for raw in raw_items:
        if not isinstance(raw, dict):
            continue
        item_id = str(raw.get("item_id") or "").strip()
        item_type = str(raw.get("item_type") or "").strip()
        display_name = str(raw.get("display_name") or "").strip()
        if not item_id or not display_name or item_type not in SUPPORTED_ITEM_TYPES:
            continue
        if item_id in seen:
            continue
        seen.add(item_id)

        price_raw = raw.get("price_coins", 0)
        try:
            price_coins = int(price_raw)
        except Exception:
            continue
        if price_coins < 0:
            continue

        row: Dict[str, Any] = {
            "item_id": item_id,
            "item_type": item_type,
            "display_name": display_name,
            "price_coins": price_coins,
            "is_active": bool(raw.get("is_active", True)),
            "category_group": str(raw.get("category_group") or "").strip(),
            "category_theme": str(raw.get("category_theme") or "").strip(),
        }

        asset_hint = str(raw.get("asset_url_or_path") or "").strip()
        if asset_hint:
            row["asset_url_or_path"] = asset_hint

        style = raw.get("style")
        if isinstance(style, dict):
            row["style"] = deepcopy(style)

        if item_type in ("booster", "booster_pack"):
            row["grant"] = _normalize_grant(raw)
            if "effects" in raw and isinstance(raw["effects"], dict):
                row["effects"] = deepcopy(raw["effects"])
            if "quantity" in raw:
                try:
                    row["quantity"] = max(1, int(raw.get("quantity") or 1))
                except Exception:
                    row["quantity"] = row["grant"]["quantity"]

        out.append(row)

    return {"schema_version": schema_version, "items": out}


def _compute_revision(canonical: Dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def _load_raw_document() -> Dict[str, Any]:
    path_env = (os.getenv("DUTCH_CONSUMABLES_PATH") or "").strip()
    path = Path(path_env) if path_env else _DEFAULT_JSON_PATH
    doc = _read_json_file(path)
    if doc is None:
        doc = _read_json_file(_DEFAULT_JSON_PATH) or {"schema_version": 1, "items": []}
    return _merge_env_overlay(doc)


_CANONICAL_DOC = _normalize_document(_load_raw_document())
CONSUMABLES_CATALOG_DOCUMENT: Dict[str, Any] = _CANONICAL_DOC
CONSUMABLES_CATALOG_REVISION: str = _compute_revision(_CANONICAL_DOC)
CONSUMABLES_CATALOG_ITEMS: List[Dict[str, Any]] = list(_CANONICAL_DOC.get("items") or [])
ITEM_BY_ID: Dict[str, Dict[str, Any]] = {i["item_id"]: i for i in CONSUMABLES_CATALOG_ITEMS if isinstance(i, dict)}


def build_client_consumables_payload() -> Dict[str, Any]:
    return deepcopy(CONSUMABLES_CATALOG_DOCUMENT)


def get_catalog_items(*, active_only: bool = False) -> List[Dict[str, Any]]:
    if not active_only:
        return [deepcopy(i) for i in CONSUMABLES_CATALOG_ITEMS]
    return [deepcopy(i) for i in CONSUMABLES_CATALOG_ITEMS if i.get("is_active") is True]


def find_item(item_id: str, *, active_only: bool = True) -> Optional[Dict[str, Any]]:
    item = ITEM_BY_ID.get((item_id or "").strip())
    if not item:
        return None
    if active_only and item.get("is_active") is not True:
        return None
    return deepcopy(item)


def booster_inventory_keys() -> Set[str]:
    keys: Set[str] = set()
    for item in CONSUMABLES_CATALOG_ITEMS:
        if not isinstance(item, dict):
            continue
        if item.get("item_type") not in ("booster", "booster_pack"):
            continue
        grant = item.get("grant") if isinstance(item.get("grant"), dict) else {}
        key = str(grant.get("booster_key") or "").strip()
        if key:
            keys.add(key)
    keys.add(FALLBACK_WIN_BOOSTER_KEY)
    return keys


def primary_win_booster_key() -> str:
    for item in CONSUMABLES_CATALOG_ITEMS:
        if not isinstance(item, dict):
            continue
        if item.get("item_type") != "booster":
            continue
        grant = item.get("grant") if isinstance(item.get("grant"), dict) else {}
        key = str(grant.get("booster_key") or "").strip()
        if key:
            return key
        item_id = str(item.get("item_id") or "").strip()
        if item_id:
            return item_id
    return FALLBACK_WIN_BOOSTER_KEY
