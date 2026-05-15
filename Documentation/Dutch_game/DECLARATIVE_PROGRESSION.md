# Declarative progression config (backend SSOT)

Rank hierarchy, wins→level→rank rules, **per-rank level spans** (`progression.levels_per_rank` map), rank matchmaking delta, rank→AI difficulty, and subscription tier ids are defined in one JSON file and served to clients via init APIs.

## Single source of truth

| Piece | Location |
|--------|----------|
| **Canonical JSON** | [`python_base_04/core/modules/dutch_game/config/progression_config.json`](../../python_base_04/core/modules/dutch_game/config/progression_config.json) |
| **Loader** | [`progression_catalog.py`](../../python_base_04/core/modules/dutch_game/progression_catalog.py) |

At Python import time the module normalizes the document and exposes `PROGRESSION_CONFIG_REVISION` (SHA-256 of canonical JSON).

**Ops overlays:** `DUTCH_PROGRESSION_PATH`, `DUTCH_PROGRESSION_JSON` (same pattern as consumables/table tiers). Restart Python after JSON changes.

## APIs

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /userauth/dutch/get-init-data` | JWT | User `data` + revision-gated `table_tiers`, `consumables_catalog`, `progression_config` |
| `GET /userauth/dutch/get-user-stats` | JWT | Deprecated alias → `get-init-data` |
| `POST /service/dutch/get-init-data` | Service key | Optional `user_id` + catalogs (Dart startup / join) |
| `POST /service/dutch/get-user-stats` | Service key | Deprecated alias |
| `GET /public/dutch/init-config` | Public | Declarative catalogs only (pre-login) |

**Revision query/body params:** `client_progression_config_revision` (with existing table tiers and consumables revision params).

When the client revision matches the server, the full `progression_config` body is omitted; the client keeps its cached copy.

## Flutter client cache

- [`progression_config_bootstrap.dart`](../../flutter_base_05/lib/modules/dutch_game/utils/progression_config_bootstrap.dart) — SharedPreferences `dutch_progression_config_revision` / `dutch_progression_config_doc_json`
- [`progression_config_store.dart`](../../flutter_base_05/lib/modules/dutch_game/utils/progression_config_store.dart) — in-memory rules for `RankMatcher` / `WinsLevelRankMatcher`
- Hydrate before each `getInitData()`; merge after response; public `fetchPublicInitConfig()` for leaderboard pre-login

## Dart game server

- [`progression_config_store.dart`](../../dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/progression_config_store.dart)
- `PythonApiClient.fetchInitConfig()` on WebSocket server startup; env fallback until fetch succeeds

## Per-rank level spans

`progression.levels_per_rank` is a map **rank id → user levels in that tier** before advancing (e.g. beginner levels 1–5, novice 6–10 when each span is 5). A legacy scalar int applies the same span to every rank.

## Per-user stats (not in JSON)

Mongo `users.modules.dutch_game`: `wins`, `level`, `rank`, etc. Returned in init `data` and updated by `update-game-stats`.
