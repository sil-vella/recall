# Progression declaration (SSOT)

**Canonical JSON:** [progression_config.json](../../python_base_04/core/modules/dutch_game/config/progression_config.json)

Defines **global rules** for competitive rank, user progression level (from wins), rank matchmaking, AI difficulty mapping, and subscription tier identifiers. Does **not** store a player’s current wins/level/rank — that is Mongo per-user data.

## Files

| Role | Path |
|------|------|
| **Canonical JSON** | [progression_config.json](../../python_base_04/core/modules/dutch_game/config/progression_config.json) |
| **Loader** | [`python_base_04/core/modules/dutch_game/progression_catalog.py`](../../python_base_04/core/modules/dutch_game/progression_catalog.py) |
| **Wins → level → rank** | [`wins_level_rank_matcher.py`](../../python_base_04/core/modules/dutch_game/wins_level_rank_matcher.py) |
| **Rank / tier helpers** | [`tier_rank_level_matcher.py`](../../python_base_04/core/modules/user_management_module/tier_rank_level_matcher.py) |

**Revision constant:** `progression_catalog.PROGRESSION_CONFIG_REVISION`  
**Client payload key:** `progression_config` / `progression_config_revision`

## Schema overview

```json
{
  "schema_version": 2,
  "progression": {
    "user_level_min": 1,
    "max_user_level": 55,
    "wins_for_max_user_level": 2000,
    "wins_per_level_steps": [10, 10, "… 54 integers …", 73],
    "levels_per_rank": {
      "beginner": 5,
      "novice": 5,
      "...": "..."
    }
  },
  "rank_hierarchy": ["beginner", "novice", "..."],
  "rank_matchmaking": { "max_rank_delta": 1 },
  "rank_to_difficulty": { "beginner": "easy", "..." },
  "subscription_tiers": ["promotional", "regular", "premium"],
  "defaults": {
    "rank": "beginner",
    "user_level": 1,
    "subscription_tier": "promotional"
  }
}
```

Client payloads also include derived `cumulative_wins_for_user_level` (min wins per level 1…max).

### `progression`

| Field | Meaning |
|-------|---------|
| `user_level_min` | Floor for user progression level (default 1). |
| `max_user_level` | Derived from sum of `levels_per_rank` spans (55 with default ranks). |
| `wins_for_max_user_level` | Target lifetime wins to reach `max_user_level` (default **2000**). |
| `wins_per_level_steps` | **54 integers**: wins required for each +1 user level after level 1 (level 2…55). Early steps are smaller (faster beginner progress); later steps increase. Default bands: **10×9**, **18×9**, **28×9**, **40×9**, **55×9**, **71×8+73** (sum **2000**). |
| `wins_per_user_level` | **Legacy fallback only** when `wins_per_level_steps` is missing/invalid (`level = 1 + wins // step`). |
| `levels_per_rank` | **Map** `rank_id → user levels in that tier` before advancing to the next rank. Legacy **scalar** int applies the same span to every rank in `rank_hierarchy`. |

**Wins → user level:** walk cumulative sum of `wins_per_level_steps`; highest level whose threshold ≤ lifetime wins. Example defaults: level **2 @ 10** wins, level **10 @ 90**, level **46 @ 1359** (enter **legend**), level **55 @ 2000**.

**Rank from user level:** walk ranks in order; user level falls in the first tier whose cumulative span contains it; overflow stays on **legend**.

Example (all spans 5): user levels 1–5 → beginner, 6–10 → novice, 11–15 → apprentice.

### `rank_hierarchy`

Ordered list, lowest to highest. Used for matchmaking ±`max_rank_delta`, leaderboard filters, and rank index.

### `rank_matchmaking`

| Field | Meaning |
|-------|---------|
| `max_rank_delta` | Max index distance for compatible rooms / comp player filter (default 1). |

### `rank_to_difficulty`

Maps rank id → YAML AI difficulty: `easy` | `medium` | `hard` | `expert`.

### `subscription_tiers`

Valid `modules.dutch_game.subscription_tier` values for coin economy (promotional skips per-user coin moves when match requires coins).

## Ops overrides

| Env var | Effect |
|---------|--------|
| `DUTCH_PROGRESSION_PATH` | Alternate JSON file path |
| `DUTCH_PROGRESSION_JSON` | Inline JSON overlay (merged into document) |
| `DUTCH_RANK_HIERARCHY` | Fallback comma list if `rank_hierarchy` missing in JSON |
| `DUTCH_WINS_PER_USER_LEVEL`, `DUTCH_LEVELS_PER_RANK`, `DUTCH_USER_LEVEL_MIN` | Fallbacks when not in JSON |

Restart Python after changes.

## Client integration

| Stack | Store / bootstrap |
|-------|-------------------|
| Flutter | `progression_config_bootstrap.dart`, `progression_config_store.dart` → `RankMatcher`, `WinsLevelRankMatcher` |
| Dart WS | `progression_config_store.dart` → same matchers |

Hydration: [INIT_DATA.md](./INIT_DATA.md).

## Per-user stats (not in this JSON)

| Field | Source |
|-------|--------|
| `wins`, `level`, `rank` | `users.modules.dutch_game` |
| Updated after matches | `POST /service/dutch/update-game-stats` |

Server derives target level/rank from wins on write using `WinsLevelRankMatcher`; stored rank does not demote from wins alone.

## Changing progression

1. Edit [progression_config.json](../../python_base_04/core/modules/dutch_game/config/progression_config.json) (or env overlay).
2. Restart Python backend.
3. Clients pick up new rules on next init when `progression_config_revision` changes (full doc in response once).

## Tests

`python_base_04/tests/unit/test_progression_catalog.py`
