# Init data API — delivering declarative catalogs + user stats

Authenticated clients load **user stats** and **revision-gated declarative catalogs** in one round trip. Pre-login clients use a smaller public endpoint for catalogs only.

## Endpoints

| Endpoint | Auth | Body |
|----------|------|------|
| `GET /userauth/dutch/get-init-data` | JWT | Query: revision params |
| `GET /userauth/dutch/get-user-stats` | JWT | Deprecated alias → same handler |
| `POST /service/dutch/get-init-data` | Service key | JSON: optional `user_id`, revision fields |
| `POST /service/dutch/get-user-stats` | Service key | Deprecated alias |
| `GET /public/dutch/init-config` | None | Query: revision params (no user `data`) |

**Implementation:** `python_base_04/core/modules/dutch_game/api_endpoints.py` — `get_init_data`, `get_init_data_service`, `get_public_init_config`, `_attach_declarative_catalogs`.

## Response shape (JWT init)

Always present:

| Field | Content |
|-------|---------|
| `success` | `true` |
| `data` | User stats from `users.modules.dutch_game` (wins, level, rank, coins, inventory, streaks, subscription_tier, …) |
| `user_id`, `timestamp` | Metadata |
| `table_tiers_revision` | Current server hash |
| `consumables_catalog_revision` | Current server hash |
| `progression_config_revision` | Current server hash |
| `achievements_catalog_revision` | Current server hash |
| `global_broadcast_messages` | Rank-filtered broadcasts (not declarative) |

Present **only when client revision is missing or stale**:

| Field | Doc | Canonical JSON |
|-------|-----|----------------|
| `table_tiers` | [TABLE_TIERS.md](./TABLE_TIERS.md) | [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json) |
| `consumables_catalog` | [CONSUMABLES.md](./CONSUMABLES.md) | [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json) |
| `progression_config` | [PROGRESSION.md](./PROGRESSION.md) | [progression_config.json](../../python_base_04/core/modules/dutch_game/config/progression_config.json) |
| `achievements_catalog` | [ACHIEVEMENTS.md](./ACHIEVEMENTS.md) | [achievements_config.json](../../python_base_04/core/modules/dutch_game/config/achievements_config.json) |

## Client revision query parameters

| Param | Catalog |
|-------|---------|
| `client_table_tiers_revision` | Table tiers + special events |
| `client_consumables_catalog_revision` | Consumables / cosmetics shop |
| `client_progression_config_revision` | Progression rules |
| `client_achievements_catalog_revision` | Achievements metadata + unlock rule definitions (client receives full doc for UI; unlocks still server-evaluated) |

Service `POST` uses the same names in the JSON body.

## Flutter flow

1. **Before request** — hydrate each bootstrap from SharedPreferences:
   - `TableTiersBootstrap.hydrateFromPrefsBeforeStats()`
   - `ConsumablesCatalogBootstrap.hydrateFromPrefsBeforeStats()`
   - `ProgressionConfigBootstrap.hydrateFromPrefsBeforeStats()`
   - `AchievementsCatalogBootstrap.hydrateFromPrefsBeforeStats()`
2. **Request** — `DutchGameHelpers.getInitData()` → `GET /userauth/dutch/get-init-data?...`
3. **After response** — merge envelopes into prefs + in-memory stores; read `data` → `StateManager` `userStats`
4. **Convenience** — `fetchAndUpdateInitData()` (alias: deprecated `fetchAndUpdateUserDutchGameData`)

**Pre-login:** `fetchPublicInitConfig()` → `GET /public/dutch/init-config` (progression + optional table tiers + achievements metadata; no user stats).

| Bootstrap | Prefs keys |
|-----------|------------|
| Table tiers | `dutch_table_tiers_revision`, `dutch_table_tiers_doc_json` |
| Consumables | `dutch_consumables_catalog_revision`, `dutch_consumables_catalog_doc_json` |
| Progression | `dutch_progression_config_revision`, `dutch_progression_config_doc_json` |
| Achievements | `dutch_achievements_catalog_revision`, `dutch_achievements_catalog_doc_json` |

## Dart game server

- Startup: `PythonApiClient.fetchInitConfig()` → `POST /service/dutch/get-init-data` (no `user_id`)
- Join checks: same endpoint with `user_id` for coins / tier / inventory
- Stores: `ProgressionConfigStore` (+ env fallback until fetch succeeds)

## Shop catalog fallback

`POST /userauth/dutch/get-shop-catalog` still returns active consumables items + `catalog_revision` if the shop UI needs a refresh without full init. Prefer init cache when possible.
