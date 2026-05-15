# Consumables & cosmetics catalog (SSOT)

**Canonical JSON:** [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json)

Shop catalog for **boosters**, **booster packs**, **card backs**, and **table designs**. Purchases and inventory keys are validated against this document on the server.

## Files

| Role | Path |
|------|------|
| **Canonical JSON** | [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json) |
| **Loader** | [`python_base_04/core/modules/dutch_game/consumables_catalog.py`](../../python_base_04/core/modules/dutch_game/consumables_catalog.py) |
| **API / purchases** | [`api_endpoints.py`](../../python_base_04/core/modules/dutch_game/api_endpoints.py) |

**Revision constant:** `consumables_catalog.CONSUMABLES_CATALOG_REVISION`  
**Client payload key:** `consumables_catalog` / `consumables_catalog_revision`

## Document shape

```json
{
  "schema_version": 1,
  "items": [
    {
      "item_id": "coin_booster_win_x1_5",
      "item_type": "booster",
      "display_name": "...",
      "price_coins": 120,
      "is_active": true,
      "category_group": "consumables",
      "category_theme": "core",
      "effects": {
        "grant": { "booster_key": "coin_booster_win_x1_5", "quantity": 1 }
      }
    }
  ]
}
```

## Supported `item_type` values

| `item_type` | Grant / effect |
|-------------|----------------|
| `booster` | `inventory.boosters[booster_key]` += quantity |
| `booster_pack` | Same; typically `quantity` > 1 |
| `card_back` | `inventory.cosmetics.owned_card_backs` += `item_id` |
| `table_design` | `inventory.cosmetics.owned_table_designs` += `item_id` |

Other types are **dropped** at normalization.

## Normalization (row kept when)

- `item_id` — unique non-empty string (first wins)
- `item_type` — supported type
- `display_name` — non-empty
- `price_coins` — integer ≥ 0

Optional: `is_active` (default `true`), `category_group`, `category_theme`, `asset_url_or_path`, `style` (cosmetics UI).

Boosters: normalized `grant` from `effects.grant` or row fallbacks; default booster key `coin_booster_win_x1_5` if invalid.

## How clients receive the catalog

Primary path: [INIT_DATA.md](./INIT_DATA.md) — `consumables_catalog` when `client_consumables_catalog_revision` is stale.

| Endpoint | Use |
|----------|-----|
| `GET /userauth/dutch/get-init-data` | Main (cached on device) |
| `POST /userauth/dutch/get-shop-catalog` | Shop refresh fallback |

## Flutter cache

| File | Role |
|------|------|
| `consumables_catalog_bootstrap.dart` | Prefs: `dutch_consumables_catalog_revision`, `dutch_consumables_catalog_doc_json` |
| `getCachedItems()`, `getCachedItemById()` | Shop / UI reads |

## Inventory (per user, Mongo)

```text
modules.dutch_game.inventory.boosters          → { booster_key: count }
modules.dutch_game.inventory.cosmetics       → owned_card_backs[], owned_table_designs[]
```

`booster_inventory_keys()` includes every grant key from the catalog plus the fallback win key.

Win flow uses `primary_win_booster_key()` from first active booster in catalog.

## Ops overrides

| Env var | Effect |
|---------|--------|
| `DUTCH_CONSUMABLES_PATH` | Alternate JSON file |
| `DUTCH_CONSUMABLES_JSON` | Replace / merge `items` (and optional `schema_version`) |

Restart Python after changes.

## Extended guide

Step-by-step add/disable items and troubleshooting: [../Consumables/DECLARATIVE_CATALOG.md](../Consumables/DECLARATIVE_CATALOG.md).
