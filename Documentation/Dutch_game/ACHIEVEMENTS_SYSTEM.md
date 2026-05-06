# Dutch Achievements System

This document describes how the Dutch achievements system works across Python backend and Flutter client: catalog definition, unlock evaluation, persistence model, API exposure, UI rendering, and celebration modal sequencing.

## Scope

- Achievement unlock logic is computed server-side at match-stat update time.
- Achievement state is persisted under the user document in `modules.dutch_game`.
- Client reads a normalized list of unlocked IDs from user stats endpoints.
- Client maps IDs to local title/description metadata for list UI and fullscreen celebrations.

---

## Architecture Overview

### Backend (source of truth)

- Catalog and unlock utilities:
  - `python_base_04/core/modules/dutch_game/dutch_achievement_catalog.py`
- Match-end stat update and persistence:
  - `python_base_04/core/modules/dutch_game/api_endpoints.py` (`update_game_stats`)
- Route registration:
  - `python_base_04/core/modules/dutch_game/dutch_game_main.py`

### Flutter (presentation)

- Local display catalog (must mirror backend IDs):
  - `flutter_base_05/lib/modules/dutch_game/utils/dutch_achievement_catalog.dart`
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

In `dutch_achievement_catalog.py`, achievements are declared as ordered entries:

- `win_streak_2` (`min_win_streak = 2`)
- `win_streak_5` (`min_win_streak = 5`)

The catalog order is meaningful because unlock scanning is performed end-to-end in that order during stats updates.

## Unlock evaluation

During `update_game_stats` in `api_endpoints.py`:

1. Read current streak from stored `modules.dutch_game.win_streak_current`.
2. Compute next streak:
   - winner -> `current + 1`
   - non-winner -> `0`
3. Read already unlocked IDs from `modules.dutch_game.achievements.unlocked`.
4. Compute newly unlocked IDs by comparing streak against catalog thresholds and skipping already-unlocked entries.
5. Persist streak fields and any newly unlocked achievements in one update operation.

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

`DutchGameHelpers.fetchAndUpdateUserDutchGameData()`:

1. Calls `GET /userauth/dutch/get-user-stats`.
2. Extracts `data` payload.
3. Stores it in Dutch module state as `userStats`.

`DutchGameHelpers.getUserDutchGameStats()` then provides read access to this cached `userStats`.

## Achievements screen

`AchievementsScreen`:

- Loads fresh user stats through `fetchAndUpdateUserDutchGameData()`.
- Reads unlocked IDs from `userStats['achievements_unlocked_ids']`.
- Renders streak summary card (`win_streak_current`, `win_streak_best`).
- Renders all entries from local `DutchAchievementCatalog.all`.
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

## Catalog Synchronization Requirement

IDs must remain synchronized between:

- Python catalog: `dutch_achievement_catalog.py`
- Flutter catalog: `dutch_achievement_catalog.dart`

If an ID exists only on one side:

- Backend-only ID: unlock persists and appears in `achievements_unlocked_ids`, but client may show fallback title/description in celebration flow.
- Flutter-only ID: displayed as lockable UI item but never unlocks from backend data.

Recommended rule: treat backend as source of truth; update Flutter catalog in same change when backend catalog changes.

---

## Adding a New Achievement

## Backend

1. Add `AchievementDef` entry in `python_base_04/.../dutch_achievement_catalog.py`.
2. Ensure threshold logic is representable by existing fields or extend evaluator logic.
3. Keep ID stable (never rename in-place once shipped unless migration is planned).

## Flutter

1. Add matching `id/title/description` to `flutter_base_05/.../dutch_achievement_catalog.dart`.
2. Verify `AchievementsScreen` renders correctly (locked/unlocked states).
3. Verify match-end celebration resolves title/description by ID and displays expected text.

## Validation checklist

- Win/loss path updates `win_streak_current` correctly.
- Threshold crossing adds expected ID under `achievements.unlocked`.
- `achievements_unlocked_ids` includes new ID via stats endpoint.
- Achievements list shows unlocked tile state.
- Celebration appears once and in expected modal order.

---

## Known Behaviors and Constraints

- Unlock checks run during match stat updates, not continuously mid-game.
- Streak achievements depend on persisted streak continuity; non-win resets streak to zero.
- Achievement diff-based modal display requires a trustworthy pre-refresh `achievements_unlocked_ids` field in local stats snapshot.
- The current system is additive-only for unlocks (no lock-back/removal logic).

---

## Related Docs

- `Documentation/Dutch_game/NOTIFICATION_SYSTEM.md`
- `Documentation/Dutch_game/PLAYER_PROFILE_DATA.md`
- `Documentation/Dutch_game/STATE_MANAGEMENT.md`
