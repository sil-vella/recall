# Leaderboard bundle load

**Status**: Completed  
**Created**: 2026-10-05  
**Last Updated**: 2026-10-05

## Objective

Make the live leaderboard and the mastery board open faster without changing the response shape or the wins sort. Show 100 rows, keep the signed-in player's own stats when they are outside that list, and hydrate from cache before the refresh.

## Implementation Steps

- [x] Cap the public bundle at 100 by default; still honor an explicit `max_entries` up to 10000
- [x] Look up usernames only for the capped rows, and attach the viewer's own period wins and mastery rank when they are outside the cap
- [x] Redis-cache the shared boards and drop that cache when match stats are written
- [x] Paint the last saved bundle on device, then replace it with the network response
- [x] Show 100 rows on the wins, mastery, and achievements screens

## Current Progress

The public bundle still returns `monthly`, `yearly`, `all_time`, `achievements`, `mastery`, and `viewer`. Omitting `max_entries` returns 100. A caller that sends `max_entries=80` (history) or a higher cap still gets that size. The wins sort is unchanged.

## Next Steps

None.

## Files Modified

- `python_base_04/core/modules/dutch_game/api_endpoints.py`
- `python_base_04/core/modules/dutch_game/utils/redis_read_cache.py`
- `python_base_04/tests/unit/test_leaderboard_bundle_cap.py`
- `flutter_base_05/lib/modules/dutch_game/utils/leaderboard_bundle_store.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/leaderboard/leaderboard_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/leaderboard/leaderboard_mastery_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/leaderboard/leaderboard_achievements_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/leaderboard/leaderboard_history_screen.dart`
- `Documentation/01_Active_Plans/case-study-dutch-card-game.html`

## Notes

Shared boards live in Redis under `leaderboard_bundle:` for `DUTCH_CACHE_LEADERBOARD_TTL` seconds (default 60). `update-game-stats` deletes that prefix. `viewer` is built on each request and is not cached, so a player outside the top 100 still gets their period wins and a mastery rank.

The app stores the last bundle in SharedPreferences per game-type scope. The first visit still waits on the network. Later visits paint the saved board immediately, then replace it when the refresh returns. A failed refresh keeps the saved board.

Task Manager sync skipped: `TASK_MANAGER_*` / `TM_*` keys are absent from `.env.local` and `.env.prod`.

## Case study

Technical game-systems bullet updated: 100-row boards, viewer outside the cap, Redis plus on-device hydrate.
