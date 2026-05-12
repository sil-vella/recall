# Declarative consumables & cosmetics catalog (backend SSOT)

This document explains how the **Dutch game consumables/cosmetics catalog** works on the Python backend: where it lives, how it is validated, how **revisions** reach Flutter, and **step-by-step examples** for adding, disabling, or removing shop items **without Flutter code changes** (for supported item types).

For implementation history and checklist status, see the active plan: [Documentation/00_Active_plans/declarative-consumables-backend-ssot.md](../00_Active_plans/declarative-consumables-backend-ssot.md).

---

## 1. What is the single source of truth?

| Piece | Location |
|--------|----------|
| **Canonical JSON file** | [`python_base_04/core/modules/dutch_game/config/consumables_catalog.json`](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json) |
| **Loader + normalization + revision** | [`python_base_04/core/modules/dutch_game/consumables_catalog.py`](../../python_base_04/core/modules/dutch_game/consumables_catalog.py) |

At **Python process import time**, the module:

1. Reads JSON (or an alternate path from env — see §6).
2. Optionally merges **`DUTCH_CONSUMABLES_JSON`** env overlay.
3. **Normalizes** every item (drops invalid rows, dedupes `item_id`, fills `grant` for boosters).
4. Computes **`CONSUMABLES_CATALOG_REVISION`**: SHA-256 of the **canonical** JSON (sorted keys, compact separators). Any catalog change changes this string.

**Important:** Changing the JSON file does **not** hot-reload inside a long-running process. **Restart the Flask/Python app** (or redeploy) so `consumables_catalog` is re-imported and revision/constants refresh.

---

## 2. Supported `item_type` values

Defined in code as `SUPPORTED_ITEM_TYPES`:

| `item_type` | Purpose |
|---------------|---------|
| `booster` | Single-use-style booster; purchase grants **`effects.grant`** → inventory key `booster_key`. |
| `booster_pack` | Bundle; same grant shape, usually `quantity` > 1. |
| `card_back` | Cosmetic; purchase adds `item_id` to `inventory.cosmetics.owned_card_backs`. |
| `table_design` | Cosmetic; purchase adds `item_id` to `inventory.cosmetics.owned_table_designs`. |

Any other `item_type` is **silently dropped** during normalization.

---

## 3. Normalization rules (why an item might “disappear”)

The loader builds the in-memory catalog from the `items` array. A row is **kept** only if **all** of the following hold:

- `item_id`: non-empty string, **unique** (first wins; duplicates skipped).
- `item_type`: one of the supported types above.
- `display_name`: non-empty string.
- `price_coins`: integer **≥ 0** (negative or non-integer → row skipped).

Optional fields preserved when valid:

- `is_active` — boolean, default **`true`**. Shop and `_find_catalog_item` use **active-only** lookups.
- `category_group`, `category_theme` — strings (UI grouping / filters).
- `asset_url_or_path` — hint for Flutter assets or URLs.
- `style` — object passed through for **card_back** / **table_design** (e.g. colors, `border_style`).

For **`booster`** and **`booster_pack`**:

- Normalized **`grant`** = `{ "booster_key": "<str>", "quantity": <int ≥ 1> }`.
- Keys resolved from `effects.grant`, or fallbacks on the row (`booster_key`, `grant_item_id`, `item_id`).
- If nothing valid, `booster_key` falls back to **`coin_booster_win_x1_5`** (`FALLBACK_WIN_BOOSTER_KEY`).

---

## 4. How the catalog reaches clients

### 4.1 `GET /userauth/dutch/get-user-stats`

Response always includes:

- `consumables_catalog_revision` — current revision string.

If the client query param `client_consumables_catalog_revision` is **missing or different**, the response also includes:

- `consumables_catalog` — full normalized document (`schema_version` + `items`).

Flutter caches revision + document (see `consumables_catalog_bootstrap.dart` and `DutchGameHelpers.getUserDutchGameData`).

### 4.2 `POST /userauth/dutch/get-shop-catalog`

Returns active items and `catalog_revision` from the same module (`get_catalog_items(active_only=True)`).

Shop UI may use cached catalog first, then this endpoint as fallback.

---

## 5. Inventory and purchases (backend behavior)

- **Boosters:** `modules.dutch_game.inventory.boosters` is a map **`booster_key` → count**. Keys present in inventory are driven by **`booster_inventory_keys()`** — every booster/booster_pack grant key in the catalog, plus the fallback win key.
- **Cosmetics:** `inventory.cosmetics.owned_card_backs` and `owned_table_designs` are lists of **`item_id`** strings.
- **Purchase:** `_find_catalog_item(item_id)` uses **`find_item(..., active_only=True)`**. Inactive or unknown IDs → purchase fails.

Win-flow booster consumption uses **`primary_win_booster_key()`** — first active **`booster`** item’s grant key, or fallback constant.

---

## 6. Overrides without editing the repo file (ops / staging)

| Env var | Effect |
|---------|--------|
| **`DUTCH_CONSUMABLES_PATH`** | Absolute or relative path to a **JSON file** to load instead of the default `config/consumables_catalog.json`. |
| **`DUTCH_CONSUMABLES_JSON`** | Inline JSON: if it is an **object** with `"items"` array, **replaces** the document’s `items` (and optional `schema_version`). If it is a **list**, replaces `items` with that list. Invalid JSON is ignored. |

Same **restart** requirement applies: env is read when the process loads the module.

---

## 7. Examples: add a consumable / cosmetic

### 7.1 Add a new **booster** (single purchase = 1 grant)

Edit `config/consumables_catalog.json` and append to `items` (comma after the previous item):

```json
{
  "item_id": "coin_booster_win_x2",
  "item_type": "booster",
  "category_group": "consumables",
  "category_theme": "core",
  "price_coins": 200,
  "display_name": "Win Coin Booster x2",
  "is_active": true,
  "effects": {
    "grant": {
      "booster_key": "coin_booster_win_x2",
      "quantity": 1
    }
  }
}
```

**After restart:** revision changes; clients with stale revision receive full `consumables_catalog`. Inventory normalization will include `coin_booster_win_x2` in the boosters map (starting at 0).

**Note:** Win multiplier logic in `api_endpoints.py` may still be tied to the **primary** booster key unless you extend game rules — this entry is mainly for **shop grant / inventory key** consistency. Coordinate with whoever owns win math before advertising x2 wins.

### 7.2 Add a **booster pack** (grant quantity 10)

```json
{
  "item_id": "coin_booster_win_x1_5_pack10",
  "item_type": "booster_pack",
  "category_group": "consumables",
  "category_theme": "core",
  "price_coins": 1000,
  "display_name": "Win Coin Booster x1.5 (x10)",
  "quantity": 10,
  "is_active": true,
  "effects": {
    "grant": {
      "booster_key": "coin_booster_win_x1_5",
      "quantity": 10
    }
  }
}
```

Top-level `"quantity": 10` is optional metadata; the grant quantity drives purchase deltas.

### 7.3 Add a **card back** with declarative colors

```json
{
  "item_id": "card_back_forest",
  "item_type": "card_back",
  "category_group": "card_backs",
  "category_theme": "nature",
  "price_coins": 320,
  "display_name": "Card Back Forest",
  "asset_url_or_path": "assets/images/card_back.webp",
  "is_active": true,
  "style": {
    "card_background_color": "#1B4D2F",
    "frame_border_color": "#D4AF37"
  }
}
```

Flutter resolves colors from cached catalog `style` when present (see `card_widget.dart` and related helpers).

### 7.4 Add a **table design** (solid border)

```json
{
  "item_id": "table_design_sunset",
  "item_type": "table_design",
  "category_group": "table_designs",
  "category_theme": "warm",
  "price_coins": 600,
  "display_name": "Table Design Sunset",
  "is_active": true,
  "style": {
    "border_style": "solid",
    "border_colors": ["#E85D3D"]
  }
}
```

### 7.5 Add a **table design** (stripes — up to two colors)

```json
{
  "item_id": "table_design_racing",
  "item_type": "table_design",
  "category_group": "table_designs",
  "category_theme": "sports",
  "price_coins": 950,
  "display_name": "Table Design Racing",
  "is_active": true,
  "style": {
    "border_style": "stripes",
    "border_colors": ["#000000", "#FFD700"]
  }
}
```

---

## 8. Examples: “remove” or hide from shop

There is **no separate delete API** for catalog rows — the catalog is the JSON file (plus env overlay).

### 8.1 Soft-remove (recommended): set `is_active` to `false`

```json
"item_id": "card_back_dragon",
"item_type": "card_back",
...
"is_active": false
```

Effects:

- **Shop / purchase:** `_find_catalog_item` uses `active_only=True` → item **cannot be purchased**.
- **Existing owners:** rows already in `owned_card_backs` stay in Mongo until you migrate or strip them separately (not done by catalog alone).

### 8.2 Hard-remove: delete the object from the `items` array

Remove the entire `{ ... }` block for that `item_id`. After restart:

- Revision updates; clients refresh catalog.
- **`booster_inventory_keys()`** no longer includes removed booster keys — `_normalize_inventory` will still read stored counts but new defaults won’t list that key (behavior: effectively 0 for missing keys in normalization loop).

For cosmetics, removing from catalog does **not** remove ownership from user documents.

### 8.3 Temporary overlay (no git edit)

Start the process with:

```bash
export DUTCH_CONSUMABLES_JSON='{"schema_version":1,"items":[ ... ]}'
```

Or replace only items with a JSON **array** of items. Useful for staging experiments; production usually prefers committed JSON + deploy.

---

## 9. Quick validation checklist

After editing the catalog:

1. **JSON syntax** — valid UTF-8 JSON (trailing commas are invalid).
2. **Unique `item_id`** — duplicates are dropped silently.
3. **Restart** Python app.
4. Call **`GET /userauth/dutch/get-user-stats`** without `client_consumables_catalog_revision` (or with an old one) and confirm `consumables_catalog_revision` and optional `consumables_catalog.items` length.
5. **Purchase** — `POST /userauth/dutch/purchase-item` with `item_id` for an active row; confirm inventory delta in user doc.

---

## 10. File reference

| Path | Role |
|------|------|
| `python_base_04/core/modules/dutch_game/config/consumables_catalog.json` | Default catalog data. |
| `python_base_04/core/modules/dutch_game/consumables_catalog.py` | Load, normalize, revision, `find_item`, `get_catalog_items`, booster helpers. |
| `python_base_04/core/modules/dutch_game/api_endpoints.py` | `get_user_stats` envelope, `get_shop_catalog`, purchase/grant paths, inventory normalization. |
| `flutter_base_05/lib/modules/dutch_game/utils/consumables_catalog_bootstrap.dart` | Client cache + revision handshake. |
| `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart` | Stats fetch merges consumables envelope. |

This is the full picture for **declarative backend** catalog edits: edit JSON (or env), restart, rely on **revision** for clients to pick up changes.
