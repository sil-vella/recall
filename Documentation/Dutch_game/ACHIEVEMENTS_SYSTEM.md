# Dutch Achievements System

This document describes how the Dutch achievements system works across Python backend and Flutter client: catalog definition, unlock evaluation, persistence model, API exposure, UI rendering, and celebration modal sequencing.

## Scope

- Achievement unlock logic is computed server-side at match-stat update time.
- Achievement state is persisted under the user document in `modules.dutch_game`.
- Client reads a normalized list of unlocked IDs from user stats endpoints.
- Client maps IDs to title/description from **`AchievementsCatalogStore`**, populated by revision-gated **`achievements_catalog`** on init (see `Documentation/SSOT_DECLARATIONS/INIT_DATA.md`).

---

## Architecture Overview

### Backend (source of truth)

- Declarative JSON + catalog loader (revision, client payload, unlock evaluation):
  - `python_base_04/core/modules/dutch_game/config/achievements_config.json`
  - `python_base_04/core/modules/dutch_game/achievements_catalog.py`
- Thin re-export (optional imports):
  - `python_base_04/core/modules/dutch_game/dutch_achievement_catalog.py`
- Match-end stat update and persistence:
  - `python_base_04/core/modules/dutch_game/api_endpoints.py` (`update_game_stats`)
- Route registration:
  - `python_base_04/core/modules/dutch_game/dutch_game_main.py`

### Flutter (presentation)

- Hydrated display catalog (from init `achievements_catalog` JSON):
  - `flutter_base_05/lib/modules/dutch_game/utils/achievements_catalog_store.dart`
  - `flutter_base_05/lib/modules/dutch_game/utils/achievements_catalog_bootstrap.dart`
  - `flutter_base_05/lib/modules/dutch_game/utils/dutch_achievement_catalog.dart` (facade: `all`, `displayTitle`)
- Achievements screen:
  - `flutter_base_05/lib/modules/dutch_game/screens/achievements/achievements_screen.dart`
- Match-end celebration orchestration:
  - `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart`
- Fullscreen achievement celebration UI:
  - `flutter_base_05/lib/modules/dutch_game/screens/promotion/dutch_achievement_celebration_screen.dart`
- Shared burst/lottie visual:
  - `flutter_base_05/lib/modules/dutch_game/screens/promotion/widgets/dutch_promotion_burst.dart`

---

## Backend Catalog and Rules

## Catalog definition

Achievements are declared in **`achievements_config.json`** and normalized at import by **`achievements_catalog.py`**.

Supported unlock types (v1):

- **`win_streak`** — `unlock.min` threshold compared to post-match win streak.
- **`event_win`** — requires `is_winner`, and request body `special_event_id` (from Dart `game_state`) matching `unlock.special_event_id`.

Catalog order is preserved; `compute_new_unlocks` scans entries in JSON array order.

## Unlock evaluation

During `update_game_stats` in `api_endpoints.py`:

1. Read current streak from stored `modules.dutch_game.win_streak_current`.
2. Compute next streak:
   - winner -> `current + 1`
   - non-winner -> `0`
3. Read already unlocked IDs from `modules.dutch_game.achievements.unlocked`.
4. Compute newly unlocked IDs via `compute_new_unlocks(..., is_winner=..., special_event_id=...)` (streak + optional event win).
5. Persist streak fields and any newly unlocked achievements in one update operation.

**Event matches:** the Dart WebSocket server sends top-level `special_event_id` on `POST /service/dutch/update-game-stats` (from `game_state.special_event_id`) so `event_win` achievements unlock for human winners.

## Persistence format

Achievements are stored as a map under:

- `modules.dutch_game.achievements.unlocked.<achievement_id>`

Each unlocked achievement currently stores:

- `unlocked_at` (timestamp)

Example shape:

```json
{
  "modules": {
    "dutch_game": {
      "win_streak_current": 5,
      "win_streak_best": 7,
      "achievements": {
        "unlocked": {
          "win_streak_2": { "unlocked_at": "..." },
          "win_streak_5": { "unlocked_at": "..." }
        }
      }
    }
  }
}
```

---

## API Contract

## Routes

Registered in `dutch_game_main.py`:

- JWT endpoint: `GET /userauth/dutch/get-user-stats`
- Service endpoint: `POST /service/dutch/get-user-stats`
- Match stat updater (service): `POST /service/dutch/update-game-stats`

## Achievement-related fields returned in stats

Both user stats endpoints include:

- `win_streak_current`
- `win_streak_best`
- `achievements_unlocked_ids` (sorted list of unlocked IDs)

The list is derived server-side from the persisted unlocked map via `achievements_unlocked_ids_sorted(...)`.

---

## Flutter Data Flow

## Fetch/update local state

`DutchGameHelpers.fetchAndUpdateInitData()` (alias `fetchAndUpdateUserDutchGameData`):

1. Calls `GET /userauth/dutch/get-init-data` (with revision query params).
2. Merges declarative envelopes (including `achievements_catalog`) into prefs + stores.
3. Stores `data` in Dutch module state as `userStats`.

`DutchGameHelpers.getUserDutchGameStats()` then provides read access to this cached `userStats`.

## Achievements screen

`AchievementsScreen`:

- Loads fresh user stats through `fetchAndUpdateUserDutchGameData()`.
- Reads unlocked IDs from `userStats['achievements_unlocked_ids']`.
- Renders streak summary card (`win_streak_current`, `win_streak_best`).
- Renders all entries from `DutchAchievementCatalog.all` (backed by `AchievementsCatalogStore`).
- Marks each entry unlocked/locked based on membership in unlocked ID set.

---

## Match-End Celebration Flow

The celebration orchestration lives in `dutch_event_handler_callbacks.dart`.

After game end:

1. Winner standings message/modal is created.
2. If current user is a winner, fullscreen `You Won` celebration is pushed.
3. User stats are refreshed from API.
4. Newly unlocked achievements are computed by diffing:
   - IDs before refresh
   - IDs after refresh
5. New achievements are shown as fullscreen modals (sequential).
6. Promotion modals are shown next (sequential):
   - level-up first
   - rank-up second

Current intended ordering when multiple celebratory surfaces are present:

1. `You Won`
2. Achievement celebration(s)
3. Level Up
4. Rank Up

Duplicate suppression uses signatures in callback state to reduce repeated pushes from duplicate websocket/state events.

---

## Catalog Synchronization

Titles/descriptions and rule definitions are **revision-synced** from the server JSON (`achievements_config.json` / `achievements_catalog` payload). Unlockable IDs are still only those evaluated in Python at `update-game-stats`.

IDs for **event rewards** should match `special_events[].metadata.rewards.achievement` in `table_tiers.json`.

---

## Adding a New Achievement

## Backend

1. Add an entry to `python_base_04/.../config/achievements_config.json` (`id`, `title`, `description`, `unlock`).
2. For special events, set `unlock.type` to `event_win` and `special_event_id` to the event’s stable id; align `table_tiers.json` reward `achievement` with the same `id`.
3. Restart/redeploy Python so `achievements_catalog_revision` changes.

## Flutter

1. No code change required for titles/descriptions when the client receives a fresh `achievements_catalog` (stale revision on next init).
2. Verify `AchievementsScreen` and celebration flows after deploy.

## Validation checklist

- Win/loss path updates `win_streak_current` correctly.
- Threshold crossing adds expected ID under `achievements.unlocked`.
- `achievements_unlocked_ids` includes new ID via stats endpoint.
- Achievements list shows unlocked tile state.
- Celebration appears once and in expected modal order.

**Worked examples (streak + event) and how to add a new `unlock.type`:** [../SSOT_DECLARATIONS/ACHIEVEMENTS.md](../SSOT_DECLARATIONS/ACHIEVEMENTS.md).

---

## Known Behaviors and Constraints

- Unlock checks run during match stat updates, not continuously mid-game.
- Streak achievements depend on persisted streak continuity; non-win resets streak to zero.
- Achievement diff-based modal display requires a trustworthy pre-refresh `achievements_unlocked_ids` field in local stats snapshot.
- The current system is additive-only for unlocks (no lock-back/removal logic).

---

## Related Docs

- `Documentation/SSOT_DECLARATIONS/ACHIEVEMENTS.md` — JSON SSOT, examples, new unlock types
- `Documentation/Dutch_game/NOTIFICATION_SYSTEM.md`
- `Documentation/Dutch_game/PLAYER_PROFILE_DATA.md`
- `Documentation/Dutch_game/STATE_MANAGEMENT.md`
