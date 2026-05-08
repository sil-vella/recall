# Dutch consumables and cosmetics MVP

This document is the **implementation companion** for the MVP shop: catalog shape, pack media layout, API behavior, Flutter Customize screen, and how to add items or categories end-to-end.

---

## 1. Scope and item types

| `item_type`   | Meaning | Inventory effect |
|---------------|---------|-------------------|
| `booster`     | Single consumable win coin booster | `inventory.boosters.coin_booster_win_x1_5` += `quantity` or 1 |
| `booster_pack`| Bundle of boosters | Same counter += `quantity` (e.g. 5) |
| `card_back`   | Permanent cosmetic | `owned_card_backs` += `item_id` |
| `table_design`| Permanent cosmetic | `owned_table_designs` += `item_id` |

**Product rules**

- Cosmetics are **permanent unlocks**; boosters are **quantity-based**.
- Purchases spend `modules.dutch_game.coins`.
- One booster may be consumed per winning player per match (see `update_game_stats` / winner payload fields).
- Booster multiplier cap is **1.5x** for the MVP item.
- No gacha, odds, or pity in MVP.

**Pricing (current catalog defaults)**

- Booster single: `120` coins  
- Booster pack (×5): `540` coins  
- Card backs: `300`–`500` coins in sample catalog  
- Table designs: `500`–`1100` coins in sample catalog  

---

## 2. Catalog SSOT (revisioned backend document)

The shop catalog is now defined as a **declarative JSON document** and normalized by a backend catalog module:

- Source JSON: `python_base_04/core/modules/dutch_game/config/consumables_catalog.json`
- Catalog loader/normalizer/revision hash: `python_base_04/core/modules/dutch_game/consumables_catalog.py`

`api_endpoints.py` no longer owns a hardcoded shop list; it reads from the catalog module.

Each item row is normalized and exposed to clients through API envelopes/catalog routes. Typical fields:

| Field | Required | Notes |
|-------|----------|--------|
| `item_id` | Yes | Stable string; drives file paths for skins (see §3). |
| `item_type` | Yes | One of `booster`, `booster_pack`, `card_back`, `table_design`. |
| `category_group` | Recommended | e.g. `consumables`, `card_backs`, `table_designs`. |
| `category_theme` | Recommended | e.g. `core`, `fantasy`, `sports`. Section key = `group::theme` when both set. |
| `display_name` | Yes | Shown in Customize tiles. |
| `price_coins` | Yes | Integer. |
| `is_active` | Yes | Catalog inclusion. |
| `quantity` | For packs | e.g. `5` for `booster_pack`; defaults to `1` for `booster` when omitted. |
| `effects.grant.booster_key` | Consumables | Declarative grant target key for inventory boosters. |
| `effects.grant.quantity` | Consumables | Declarative quantity grant for consumables. |
| `asset_url_or_path` | Optional | Legacy / placeholder; **live card art** is resolved via §4 URLs from `item_id`. |

**Purchase support** (`purchase_item_service`): current supported `item_type` values are `booster`, `booster_pack`, `card_back`, `table_design`. Unknown types still fail with `Unsupported item_type`.

---

## 3. Naming convention: `item_id` → pack folder

### Card backs

- Pattern: `card_back_<pack_name>` (snake_case pack slug).  
- Example: `card_back_juventus` → pack folder **`juventus`**.

### Table designs

- Pattern: `table_design_<pack_name>`.  
- Example: `table_design_juventus` → pack folder **`juventus`**.

Python resolves paths with:

- Card: `sponsors/media/card_back/<pack_name>/card_back_<pack_name>.webp`  
- Table overlay: `sponsors/media/table_design/<pack_name>/table_design_overlay_<pack_name>.webp`  

(`pack_name` = substring after `card_back_` / `table_design_`, lowercased.)

---

## 4. Media on disk and public URLs

**Repo layout (local)**

- `sponsors/media/card_back/<pack>/card_back_<pack>.webp`  
- `sponsors/media/table_design/<pack>/table_design_overlay_<pack>.webp`  
- Fallbacks: `sponsors/media/card_back.webp`, `sponsors/media/table_logo.webp` (used when file missing).

**HTTP (Python)**

- Card backs: `GET .../sponsors/media/card_back.webp?skinId=<item_id>&gameId=...&v=...`  
  → `get_card_back_media()` maps `skinId` to the pack file under `sponsors/media/card_back/...`.  
- Table overlay: `GET .../sponsors/media/table_design_overlay.webp?skinId=<item_id>&gameId=...&v=...`  
  → `get_table_design_overlay_media()` maps to `sponsors/media/table_design/...`.

**Upload playbooks** (VPS paths mirror local structure)

- `playbooks/rop01/16_upload_card_back_packs.py` — `card_back/<pack>/card_back_<pack>.webp`  
- `playbooks/rop01/14_upload_table_design_overlays.py` — `table_design/<pack>/table_design_overlay_<pack>.webp`  

Always deploy **webp** (or ensure PNG fallback paths exist if you extend the server).

---

## 5. User / inventory shape

Under `users.modules.dutch_game`:

- `coins` — spent on purchase.  
- `inventory.boosters.coin_booster_win_x1_5` — integer count.  
- `inventory.cosmetics.owned_card_backs` — list of `item_id` strings.  
- `inventory.cosmetics.owned_table_designs` — list of `item_id` strings.  
- `inventory.cosmetics.equipped.card_back_id` — string (empty = default).  
- `inventory.cosmetics.equipped.table_design_id` — string (empty = default).  

---

## 6. API surface (authenticated paths used by Flutter)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/userauth/dutch/get-user-stats` | Returns user stats plus revision metadata (`table_tiers_revision`, `consumables_catalog_revision`), and conditionally returns full docs when client revisions are stale/missing. |
| POST | `/userauth/dutch/get-shop-catalog` | Legacy-compatible catalog route; returns `{ success, items, catalog_revision }` from canonical active catalog. |
| POST | `/userauth/dutch/get-inventory` | Returns `{ success, inventory }`. |
| POST | `/userauth/dutch/purchase-item` | Body `{ item_id }`; coin check + grant. |
| POST | `/userauth/dutch/equip-cosmetic` | Body `{ slot, cosmetic_id }`; `slot` is `card_back` or `table_design`; empty `cosmetic_id` clears. |

**Purchase response** (success): `new_coin_balance`, `granted_item`, `inventory_delta`, `tx_id`.

**Equip response**: `equipped` map.

**Winner / stats** (when applicable): rows may include `base_win_coins`, `booster_multiplier`, `bonus_from_booster`, `final_win_coins`.

---

## 7. Flutter: Customize screen (`DutchCustomizeScreen`)

**File:** `flutter_base_05/lib/modules/dutch_game/screens/shop/dutch_cosmetics_shop_screen.dart`

**Data**

- Catalog: `DutchGameHelpers.getShopCatalog()` (cache-first via consumables bootstrap; backend refresh when available)  
- Inventory: `DutchGameHelpers.fetchInventory()`  

**Section layout (top to bottom)**

1. **My Packs** — owned `card_back` and `table_design` items (purchased cosmetics only); no price row.  
2. **Shop sections** — grouped by `_sectionKey(item)`:
   - If `category_group` and `category_theme` are non-empty → key `group::theme` (e.g. `consumables::core`, `card_backs::fantasy`).  
   - Else falls back to `item_type`-derived keys for backwards compatibility.

**Shop section sort order** (`_sortShopSectionKeys`)

1. `consumables::core`  
2. Other `consumables::…` or bare `consumables`  
3. All `card_backs::…` (then `card_backs`)  
4. All `table_designs::…` (then `table_designs`)  
5. Any other keys (alphabetically within same rank)  

**UI / theme requirements**

- **Background:** `assets/images/backgrounds/main-screens-background.webp` (same as lobby-style Dutch screens).  
- **Section headers:** `AppColors.accentColor` strip, `AppTextStyles.headingSmall` with `AppColors.textOnAccent`.  
- **Tiles:** outer fill `AppColors.accentContrast` (aligned with default app bar contrast); **6px** inner padding; border `AppColors.borderDefault`, selected `AppColors.accentColor2` (thicker border).  
- **Title / price:** dark scrim only on those rows (`_kTextScrimFill`), not full-bleed over art.  
- **Primary actions:** `FilledButton` with `AppColors.accentColor` / `AppColors.textOnAccent`.  
- **Table mini-preview:** `FeltTextureWidget` + `DutchGamePlayTableStyles.forLevel(1)` for felt; overlay via `TableDesignStyleHelpers.buildOverlayUrl` at opacity **`0.22`** (must match `GamePlayScreen` overlay strength).  
- **Card back preview:** `CardWidget` face-down with the pack’s `item_id` as the logical skin context where applicable.

**Adding a new shop section order**  
If you introduce a new `category_group` that must appear in a fixed place (e.g. `limited_time`), extend `_sortShopSectionKeys` with an explicit rank before/after existing tiers.

---

## 8. Flutter: in-game rendering

### 8.1 Card backs (`CardWidget`)

**File:** `flutter_base_05/lib/modules/dutch_game/widgets/card_widget.dart`

- **Hands only:** callers pass `ownerCardBackId` for player hand cards; discard / default uses `forceDefaultBack` where required.  
- **Network URL:** `Config.apiUrl` + `/sponsors/media/card_back.webp?skinId=<id>&gameId=...&v=3` (see file for exact query).  
- **Practice rooms:** `gameId` prefix `practice_room_` forces local `assets/images/card_back.webp`.  
- **Per-pack polish:** `_cardBackBaseColor`, `_cardBackFrameBorderColor`, optional `ColorFiltered` modulate for specific ids (`card_back_ocean`, `card_back_ember`). **New packs** should add cases here (and optionally tint) so shop and table match.

**Opponent / state:** `card_back_id` on `game_state.players[]` is populated for the local user when equipping during a match so others can render your back (`unified_game_board_widget.dart`).

### 8.2 Table design

**Felt color:** Always from **room table tier** (`DutchGamePlayTableStyles.forLevel`), not from cosmetic id — see `dutch_game_play_table_style_mapping.dart`.

**Overlay + border**

**File:** `flutter_base_05/lib/modules/dutch_game/screens/game_play/utils/table_design_style_helpers.dart`

- `buildOverlayUrl` — builds `table_design_overlay.webp?skinId=...` when a design is equipped.  
- `outerBorderColorForDesign` / `outerBorderGlowForDesign` — switch on `table_design_*` for neon/royal; default casino border.  
- `isJuventusTableDesign` + `JuventusStripeBorderPainter` — special border treatment for Juventus.

**Game play overlay opacity:** keep shop preview opacity in sync (currently `0.22`).

---

## 9. Walkthrough: add a new **table design** pack

**Goal:** Sell and equip `table_design_forest` with a new overlay image.

### Step A — declarative catalog JSON

In `python_base_04/core/modules/dutch_game/config/consumables_catalog.json`, append to `items`:

```json
{
  "item_id": "table_design_forest",
  "item_type": "table_design",
  "category_group": "table_designs",
  "category_theme": "nature",
  "price_coins": 600,
  "display_name": "Table Design Forest",
  "is_active": true
}
```
`category_theme` can be any new theme string; section header becomes `Table designs - <Theme>`.

### Step B — Image asset

Create directory and file (names must match §3):

`sponsors/media/table_design/forest/table_design_overlay_forest.webp`

(`item_id` `table_design_forest` → pack folder **`forest`**.)

### Step C — Deploy media

Run (or adapt):

`python playbooks/rop01/14_upload_table_design_overlays.py --pack forest`

### Step D — Flutter styling (optional but recommended)

In `table_design_style_helpers.dart`, extend:

- `outerBorderColorForDesign` / `outerBorderGlowForDesign` if this pack needs a distinctive rim.  
- Add a custom painter hook (like Juventus) only if the product needs non-default geometry.

If you skip Step D, the pack still **works**: default border + overlay image at standard opacity.

### Step E — Tests / manual

- Purchase with a test user; confirm `owned_table_designs` contains `table_design_forest`.  
- Equip; confirm play table shows overlay and Customize “My Packs” lists the owned item.  
- No Python endpoint change is required for `purchase_item` / `equip` beyond catalog row **unless** you add a new `item_type`.

---

## 10. Walkthrough: add a new **card back** pack

**Goal:** `card_back_dragon` with custom art.

### Step A — Catalog row (`consumables_catalog.json`)

```json
{
  "item_id": "card_back_dragon",
  "item_type": "card_back",
  "category_group": "card_backs",
  "category_theme": "fantasy",
  "price_coins": 350,
  "display_name": "Card Back Dragon",
  "asset_url_or_path": "assets/images/card_back.webp",
  "is_active": true
}
```
`asset_url_or_path` is optional placeholder metadata for UI compatibility.

### Step B — File on disk

`sponsors/media/card_back/dragon/card_back_dragon.webp`

### Step C — Deploy

`python playbooks/rop01/16_upload_card_back_packs.py --pack dragon`

### Step D — Flutter `CardWidget`

In `card_widget.dart`, add branches for **`card_back_dragon`** in:

- `_cardBackBaseColor` — tile “shelf” color behind art.  
- `_cardBackFrameBorderColor` — thin inner frame around art.  
- Optionally add `ColorFiltered` like ember/ocean if the raw art needs a tone pass.

Without Step D, the back still loads from the network but uses **default** base/frame colors.

### Step E — Optional UX copy

If you show friendly names anywhere (e.g. debug HUD), update helpers such as `_friendlyCardBackLabel` in `unified_game_board_widget.dart`.

---

## 11. Walkthrough: new **consumable** line (same core theme)

Example: another booster variant **must** still use supported `item_type` values or you extend the backend item-type handler logic.

For a new **`booster_pack`** under the same UI block as existing boosters:

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

No image asset is required for MVP tiles (icon fallback in Customize). If you add a **new** `category_theme` under consumables, `_sortShopSectionKeys` currently places every `consumables::` **except** `consumables::core` in rank `1` (after core, before card backs). Adjust ranks if you need a different order.

---

## 12. Walkthrough: new **category** (group + theme) only

Example: premium card line `card_backs::premium_metal`.

1. Add catalog rows with `"category_group": "card_backs", "category_theme": "premium_metal"`.  
2. No backend code change — section header is derived in `_sectionLabel` (“Card backs - Premium metal”).  
3. Sorting: all `card_backs::*` stay together; alphabetical tie-break orders themes.  
4. If the **group** name changes (e.g. `card_backs_limited`), update `_sectionKey` / `_sortShopSectionKeys` if Flutter should still treat it as “card backs” block.

---

## 13. Runtime fallbacks (summary)

**Card back**

1. Equipped skin via `skinId` URL when `ownerCardBackId` set and not forced default.  
2. Default sponsor URL without `skinId` when empty.  
3. Asset / broken-image fallbacks inside `CardWidget`.

**Table**

1. Equipped overlay URL from `TableDesignStyleHelpers.buildOverlayUrl`.  
2. Missing file on server → logged warning and `table_logo` fallback in Python.  
3. Felt / spotlights always from table **tier**, not cosmetic.

---

## 14. Files checklist (quick reference)

| Concern | Location |
|---------|----------|
| Declarative consumables catalog JSON | `python_base_04/core/modules/dutch_game/config/consumables_catalog.json` |
| Catalog normalization + revision | `python_base_04/core/modules/dutch_game/consumables_catalog.py` |
| Catalog + purchase + media routes | `python_base_04/core/modules/dutch_game/api_endpoints.py` |
| Dutch module route registration | `python_base_04/core/modules/dutch_game/dutch_game_main.py` |
| Customize UI + section logic | `flutter_base_05/.../dutch_cosmetics_shop_screen.dart` |
| Shop / equip API client | `flutter_base_05/.../dutch_game_helpers.dart` |
| Catalog cache bootstrap (Flutter) | `flutter_base_05/.../consumables_catalog_bootstrap.dart` |
| Card back rendering | `flutter_base_05/.../card_widget.dart` |
| Table overlay URL + border helpers | `flutter_base_05/.../table_design_style_helpers.dart` |
| Table tier felt (not cosmetic) | `flutter_base_05/.../dutch_game_play_table_style_mapping.dart` |
| In-play board + `card_back_id` | `flutter_base_05/.../unified_game_board_widget.dart` |
| Upload automation | `playbooks/rop01/14_*.py`, `16_*.py` |

---

## 15. Catalog + shop update flow (detailed)

This section describes how catalog updates propagate from backend to app without requiring a Flutter release.

### 15.1 Cold start (no local cache)

1. Flutter starts Dutch stats flow (`DutchGameHelpers.getUserDutchGameData`).
2. `ConsumablesCatalogBootstrap.hydrateFromPrefsBeforeStats()` finds no stored doc/revision.
3. Flutter calls:
   - `GET /userauth/dutch/get-user-stats`
   - without `client_consumables_catalog_revision`.
4. Backend includes:
   - `consumables_catalog_revision`
   - full `consumables_catalog` document.
5. Flutter `mergeStatsEnvelope()` stores:
   - `dutch_consumables_catalog_revision`
   - `dutch_consumables_catalog_doc_json`.
6. Shop reads from cached doc (and can still refresh via `/get-shop-catalog`).

### 15.2 Warm start (cache hit, revision unchanged)

1. Flutter hydrates cached consumables doc + revision from SharedPreferences.
2. Flutter calls `get-user-stats` with:
   - `client_consumables_catalog_revision=<stored_revision>`.
3. Backend compares with canonical revision:
   - if equal, backend returns revision only (no full catalog payload).
4. Flutter keeps local cached catalog and avoids large payload transfer.

### 15.3 Warm start (cache hit, revision stale)

1. Backend catalog changes (JSON edited/deployed), producing a new catalog revision hash.
2. Client still sends old revision in `client_consumables_catalog_revision`.
3. Backend detects mismatch and returns:
   - new `consumables_catalog_revision`
   - full `consumables_catalog`.
4. Flutter merges envelope, replacing cached doc/revision.
5. Shop renders new catalog structure without app update.

### 15.4 Legacy refresh path (`/get-shop-catalog`)

`DutchGameHelpers.getShopCatalog()` keeps compatibility:

1. Read cached catalog first (`ConsumablesCatalogBootstrap.getCachedItems()`).
2. Try POST `/userauth/dutch/get-shop-catalog`.
3. On success:
   - use returned `items`
   - persist via `mergeCatalogItems(items, catalog_revision)`.
4. On failure:
   - return cached items.

This gives resilient UX while the revision envelope flow remains primary.

### 15.5 Backend add/remove flow example

#### Add a new item

1. Add item object in `consumables_catalog.json` under `items`.
2. Deploy backend.
3. On next stale-revision stats call, client receives new catalog doc.
4. Shop auto-renders item based on declarative fields (`item_type`, `category_group`, `category_theme`, `display_name`, `price_coins`).

#### Remove / deactivate an item

Preferred: set `"is_active": false` instead of deleting immediately.

1. Update catalog JSON.
2. Deploy backend.
3. New revision triggers doc refresh on clients.
4. Removed/deactivated item no longer appears in active shop listing.

### 15.6 Purchase update flow example

For `booster` / `booster_pack`:

1. User taps Buy in Customize.
2. Flutter sends `POST /userauth/dutch/purchase-item` with `item_id`.
3. Backend finds item in canonical catalog (`find_item(item_id)`).
4. Backend applies declarative grant:
   - `effects.grant.booster_key`
   - `effects.grant.quantity`
5. Backend decrements coins atomically and stores inventory/transaction.
6. Flutter refreshes user stats and inventory to reflect new balances/counts.

## 16. Booster rules (reminder)

- Primary win booster key is derived from catalog (fallback remains available), and multiplier stays in `api_endpoints.py`.  
- Inventory normalization ensures declared booster keys exist in inventory.  
- Consuming boosters on win is handled in the stats / game outcome pipeline (not duplicated here).

The current system keeps catalog SSOT in backend JSON + canonical Python module with revision hashing. A future DB-driven catalog can replace the JSON source while preserving the same revision envelope contract and Flutter cache bootstrap pattern.
