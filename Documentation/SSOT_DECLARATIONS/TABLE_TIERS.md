# Table tiers & special events (SSOT)

**Canonical JSON:** [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json)

Defines **room table tiers** (lobby `game_level`: title, coin fee, min user level, felt/style, back graphics) and optional **special event** match presets. This is **not** the same as user progression **level** in `modules.dutch_game.level` — see [PROGRESSION.md](./PROGRESSION.md).

## Files

| Role | Path |
|------|------|
| **Canonical JSON** | [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json) |
| **Loader** | [`python_base_04/core/modules/dutch_game/table_tiers_catalog.py`](../../python_base_04/core/modules/dutch_game/table_tiers_catalog.py) |
| **Python maps** | `LEVEL_TO_TITLE`, `LEVEL_TO_COIN_FEE`, `LEVEL_TO_MIN_USER_LEVEL`, `LEVEL_ORDER` via `tier_rank_level_matcher` |

**Revision constant:** `table_tiers_catalog.TABLE_TIERS_REVISION`  
**Client payload key:** `table_tiers` / `table_tiers_revision`

## Document shape

```json
{
  "schema_version": 1,
  "tiers": [
    {
      "level": 1,
      "title": "Home Table",
      "coin_fee": 25,
      "min_user_level": 1,
      "style": {
        "felt_hex": "#4E8065",
        "spotlight_hex": "#FFD4A3",
        "back_graphic_file": "home-table-backgraphic_002.webp"
      }
    }
  ],
  "special_events": [
    {
      "id": "event_id",
      "title": "...",
      "metadata": { "rewards": { } }
    }
  ]
}
```

### `tiers[]` (standard tables 1–4)

| Field | Meaning |
|-------|---------|
| `level` | Room `game_level` id (integer). |
| `title` | Display name (lobby UI). |
| `coin_fee` | Entry cost per player when match is coin-based. |
| `min_user_level` | Minimum **user progression level** required to join (gates with `WinsLevelRankMatcher`). |
| `style` | `felt_hex`, `spotlight_hex`, optional `back_graphic_file` / URLs after server resolves public base. |

### `special_events[]`

Distinct string `id` (not a table level). Used for special-match presets: metadata, rewards placeholder, optional banner/video/audio asset filenames resolved to URLs on the server for client download.

## Server behavior

- Builds client payload with `build_client_table_tiers_payload(public_base)` — adds `back_graphic_url` etc.
- Serves static back graphics: `GET /public/dutch/table-tier-back/<filename>`
- Join/create room: coin fee and `min_user_level` from catalog maps

## How clients receive the catalog

Primary path: [INIT_DATA.md](./INIT_DATA.md) — `table_tiers` when `client_table_tiers_revision` is stale.

Public init may also include table tiers for pre-login UI: `GET /public/dutch/init-config`.

## Flutter cache

| File | Role |
|------|------|
| `table_tiers_bootstrap.dart` | Prefs: `dutch_table_tiers_revision`, `dutch_table_tiers_doc_json` |
| `level_matcher.dart` | `applyTableTiersDocument()`, bundled minimal fallback, graphic download cache |

Downloads table back graphics to app support dir keyed by revision (non-web).

## Ops overrides

| Env var | Effect |
|---------|--------|
| `DUTCH_TABLES_JSON` | Per-level overlay merge into `tiers` (legacy shape: `"1": { title, coin_fee, min_user_level }`) |

Restart Python after JSON changes.

## Related

- User progression gates: [PROGRESSION.md](./PROGRESSION.md) (`min_user_level` vs user level from wins)
- Coin deduct / pot: [../Dutch_game/COIN_AVAILABILITY_ADD_DEDUCT_LOGIC.md](../Dutch_game/COIN_AVAILABILITY_ADD_DEDUCT_LOGIC.md)
