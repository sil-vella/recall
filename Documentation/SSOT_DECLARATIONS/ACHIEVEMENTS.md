# Achievements (JSON declarative SSOT)

Achievements are loaded from **`config/achievements_config.json`** at Python import. Unlock **evaluation** still runs server-side in `update-game-stats`; unlock **state** is per-user in Mongo.

## Canonical JSON

| File |
|------|
| [`python_base_04/core/modules/dutch_game/config/achievements_config.json`](../../python_base_04/core/modules/dutch_game/config/achievements_config.json) |

## Loader and revision

| Python | Role |
|--------|------|
| [`achievements_catalog.py`](../../python_base_04/core/modules/dutch_game/achievements_catalog.py) | Normalized document, `ACHIEVEMENTS_CONFIG_REVISION`, `build_client_achievements_payload()`, `compute_new_unlocks()` |
| [`dutch_achievement_catalog.py`](../../python_base_04/core/modules/dutch_game/dutch_achievement_catalog.py) | Re-exports (backward-compatible import path) |

**Env overrides:** `DUTCH_ACHIEVEMENTS_PATH`, `DUTCH_ACHIEVEMENTS_JSON` (same pattern as progression/consumables).

## JSON shape (v1)

Each entry:

- `id` — stable string; must match `special_events[].metadata.rewards.achievement` in [`table_tiers.json`](../../python_base_04/core/modules/dutch_game/config/table_tiers.json) when used as an event reward.
- `title`, `description` — client-visible strings.
- `unlock` — rule object:
  - `{ "type": "win_streak", "min": <int> }` — unlock when post-match win streak ≥ `min`.
  - `{ "type": "event_win", "special_event_id": "<string>" }` — unlock when the player won the match **and** the Dart backend sends `special_event_id` on `update-game-stats` matching this id.

## Client sync

Flutter hydrates titles/descriptions via init / public init-config (`achievements_catalog_revision`, `achievements_catalog`), cached in SharedPreferences. See [INIT_DATA.md](./INIT_DATA.md).

**Presentation shim:** [`dutch_achievement_catalog.dart`](../../flutter_base_05/lib/modules/dutch_game/utils/dutch_achievement_catalog.dart) reads from `AchievementsCatalogStore` (not a second static list).

## Per-user state (Mongo)

```text
modules.dutch_game.achievements.unlocked.<achievement_id>
modules.dutch_game.win_streak_current / win_streak_best
```

Init `data` includes `achievements_unlocked_ids` (sorted list) — see [INIT_DATA.md](./INIT_DATA.md).

## Unlock flow

1. Match ends → Dart `updateGameStats` includes optional top-level `special_event_id` from room `game_state`.
2. `update-game-stats` runs `compute_new_unlocks(streak, already_unlocked, is_winner=..., special_event_id=...)`.
3. Client refreshes init / merges catalog when revision changes.

## Adding an achievement (checklist)

| Step | Action |
|------|--------|
| JSON | Add one object with `id`, `title`, `description`, `unlock`. |
| Events | For event wins: `unlock.type` = `event_win` and `table_tiers.json` `metadata.rewards.achievement` must equal the same achievement `id`; `special_event_id` must match the event’s stable id in `table_tiers` / `game_state`. |
| Server | Restart or redeploy Python so `achievements_catalog_revision` updates. |
| Client | Next authenticated init (or public init-config) with a stale stored revision fetches `achievements_catalog`—no app store release needed for copy. |

## Examples: new achievements

### Streak-based

Append to the `achievements` array in **`achievements_config.json`**:

```json
{
  "id": "win_streak_10",
  "title": "Unstoppable",
  "description": "Win 10 matches in a row.",
  "unlock": { "type": "win_streak", "min": 10 }
}
```

Restart Python. The next client init with a stale achievements revision receives the updated catalog.

### Special-event win

Use a stable **event id** that matches the room / `table_tiers` special event (and what Dart sends as `special_event_id` on `update-game-stats`), e.g. `spring_showdown`.

**1.** In **`achievements_config.json`**:

```json
{
  "id": "spring_showdown_winner",
  "title": "Spring Showdown champion",
  "description": "Won the Spring Showdown event.",
  "unlock": {
    "type": "event_win",
    "special_event_id": "spring_showdown"
  }
}
```

**2.** In **`table_tiers.json`**, for that event’s `metadata.rewards`, set:

```json
"achievement": "spring_showdown_winner"
```

(the same string as the achievement `id`.)

**3.** Restart Python. Unlock applies only when the player **wins** and the Dart backend sends `special_event_id` equal to `spring_showdown`.

## Adding a new unlock type

Shipped **v1** rules are only **`win_streak`** and **`event_win`**. To introduce another `unlock.type` (e.g. `total_wins`, login streak, owns-item), extend the stack in a coordinated way.

### 1. Define the JSON contract

Choose a stable `unlock.type` and required fields, e.g.:

```json
"unlock": { "type": "total_wins", "min": 100 }
```

Document the new type in this file and keep examples in sync with code.

### 2. Normalize in Python

In [`achievements_catalog.py`](../../python_base_04/core/modules/dutch_game/achievements_catalog.py), **`_normalize_achievement_entry`**:

- Recognize the new `type`
- Validate fields (`min`, enums, ids, etc.)
- Return a normalized `unlock` dict or `None` if invalid (skip the entry; do not crash import)

### 3. Evaluate in `compute_new_unlocks`

In the same module, **`compute_new_unlocks`**: add a branch for the new type.

Any data the rule needs (e.g. total wins after the match) must be passed as new keyword arguments. Today the signature includes `win_streak_after`, `already_unlocked`, `is_winner`, and `special_event_id`; extend it (e.g. `total_wins_after`) and thread those values from the caller.

### 4. Provide data at the right trigger

For match-scoped rules, update [`api_endpoints.py`](../../python_base_04/core/modules/dutch_game/api_endpoints.py) **`update_game_stats`**: after computing per-player stats (e.g. `new_wins`), call `compute_new_unlocks` with the extra arguments.

Rules that are **not** tied to a single match (e.g. daily login) need another code path that still writes `modules.dutch_game.achievements.unlocked.<id>`—either reuse `compute_new_unlocks` from there or share a small helper.

### 5. Flutter

Unlock logic stays server-side. Flutter changes are only needed for **presentation** beyond `title` / `description` (e.g. progress UI), not for the unlock itself.

### 6. Tests

Add cases in [`tests/unit/test_achievements_catalog.py`](../../python_base_04/tests/unit/test_achievements_catalog.py): rule satisfied → id appears; not satisfied → omitted; already unlocked → not duplicated.

## Full system doc

[../Dutch_game/ACHIEVEMENTS_SYSTEM.md](../Dutch_game/ACHIEVEMENTS_SYSTEM.md)
