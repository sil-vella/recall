# Achievements (code-synced SSOT — not JSON declarative)

Achievements are **not** loaded from `config/*.json`. They are declared in **parallel code catalogs** that must stay aligned. Unlock state is **per user** in Mongo.

## Declaration files (keep in sync)

| Stack | Path |
|-------|------|
| Python | [`python_base_04/core/modules/dutch_game/dutch_achievement_catalog.py`](../../python_base_04/core/modules/dutch_game/dutch_achievement_catalog.py) |
| Flutter | [`flutter_base_05/lib/modules/dutch_game/utils/dutch_achievement_catalog.dart`](../../flutter_base_05/lib/modules/dutch_game/utils/dutch_achievement_catalog.dart) |

Each entry defines `id`, `title`, `description`, and unlock rules evaluated on the server after matches.

## Per-user state (Mongo)

```text
modules.dutch_game.achievements.unlocked.<achievement_id>
modules.dutch_game.win_streak_current / win_streak_best
```

Init `data` includes `achievements_unlocked_ids` (sorted list) via `get-init-data` — see [INIT_DATA.md](./INIT_DATA.md).

## Unlock flow

1. Match ends → `update-game-stats`
2. Server runs `compute_new_unlocks()` against catalog + streak/wins
3. Client refreshes init / listens for promotion events

## Adding an achievement

1. Add definition in **both** Python and Flutter catalog files (same `id`).
2. Deploy **both** backend and app (or accept mismatch until next release).
3. No revision-sync mechanism — unlike [PROGRESSION.md](./PROGRESSION.md), [CONSUMABLES.md](./CONSUMABLES.md), [TABLE_TIERS.md](./TABLE_TIERS.md).

## Full system doc

[../Dutch_game/ACHIEVEMENTS_SYSTEM.md](../Dutch_game/ACHIEVEMENTS_SYSTEM.md)
