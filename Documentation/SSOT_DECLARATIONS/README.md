# Dutch declarative SSOT declarations

This folder documents every **server-authoritative declarative catalog** for the Dutch game: where it lives, how it is loaded, how clients cache it, and how to change it without app releases (where supported).

## JSON catalogs (Python `config/` + revision sync)

| Document | Declares | Canonical JSON |
|----------|----------|----------------|
| [PROGRESSION.md](./PROGRESSION.md) | Rank hierarchy, wins→level→rank, matchmaking, rank→AI difficulty, subscription tier ids | [progression_config.json](../../python_base_04/core/modules/dutch_game/config/progression_config.json) |
| [CONSUMABLES.md](./CONSUMABLES.md) | Shop items: boosters, booster packs, card backs, table designs | [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json) |
| [TABLE_TIERS.md](./TABLE_TIERS.md) | Room table tiers (fees, titles, styles) and special-event presets | [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json) |
| [ACHIEVEMENTS.md](./ACHIEVEMENTS.md) | Achievement ids, titles, descriptions, unlock rules (win streak, event win) | [achievements_config.json](../../python_base_04/core/modules/dutch_game/config/achievements_config.json) |

## How catalogs reach clients

See [INIT_DATA.md](./INIT_DATA.md) for the unified **`get-init-data`** envelope, revision query params, SharedPreferences caching, and public pre-login config.

## Related

| Document | Notes |
|----------|--------|
| [../Consumables/DECLARATIVE_CATALOG.md](../Consumables/DECLARATIVE_CATALOG.md) | Extended consumables ops guide (examples, troubleshooting). |
| [../Dutch_game/CONSUMABLES_COSMETICS_MVP.md](../Dutch_game/CONSUMABLES_COSMETICS_MVP.md) | MVP product / API overview. |

## Common rules (all JSON catalogs)

1. **Loader runs at Python import** — edit JSON → **restart** Flask/Python (or redeploy) so revision hashes refresh.
2. **Revision** — SHA-256 of canonical normalized JSON; exposed as `*_revision` on init responses.
3. **Client gate** — full document sent only when `client_*_revision` is missing or stale; otherwise client reuses **SharedPreferences** cache (Flutter) or in-memory cache (Dart WS).
4. **Env overlays** — each catalog documents its own `DUTCH_*_PATH` / `DUTCH_*_JSON` vars for staging without committing JSON.

## Per-user data (not declarative)

Mongo `users.modules.dutch_game` holds **instance** data: `wins`, `level`, `rank`, `coins`, `inventory`, streaks, etc. Returned in init `data` and updated by `update-game-stats`. Declarative catalogs only define **rules** and **shop/tier definitions**, not a player’s current values.
