# Player match mastery

**Status**: Completed  
**Created**: 2026-10-05  
**Last Updated**: 2026-10-08

## Objective

Give every player a lifetime mastery score from how light their finish was, show it on the existing wins leaderboard, and add a mastery board. Wins → level → rank stays the ranking formula.

## Implementation Steps

- [x] `match_mastery_delta` and `$inc modules.dutch_game.mastery` on every stats update
- [x] Lifetime mastery on period leaderboard rows without changing the wins sort
- [x] Mastery board in the leaderboard bundle and `/dutch/leaderboard/mastery`
- [x] Unit tests and case-study note

## Current Progress

Match end adds mastery for every player already written by `update-game-stats`. The wins leaderboard still sorts by wins, then period points, then average win time, and each entry also shows lifetime mastery. The main leaderboard has a Wins | Mastery mode bar. The game-ended modal shows the local player’s mastery delta for that finish (client formula mirrored from `mastery.py`) with the MasteryStars Lottie at home size (48).

## Next Steps

None. Past matches are not backfilled; mastery starts at 0 until the next finished match.

## Files Modified

- `python_base_04/core/modules/dutch_game/mastery.py`
- `python_base_04/core/modules/dutch_game/api_endpoints.py`
- `python_base_04/tests/unit/test_mastery.py`
- `flutter_base_05/lib/modules/dutch_game/screens/leaderboard/leaderboard_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/dutch_game_main.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/match_mastery_delta.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/messages_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/widgets/ui_kit/dutch_mastery_mark.dart`
- `Documentation/01_Active_Plans/case-study-dutch-card-game.html`

## Notes

Formula: integer half of `(40 - points) * 10 + (4 - cards)`, caps 40 and 4. Both jokers are `0` points and `2` cards and award 252, 50 above an empty hand (202). One queen and one 10 are the same finish (151). The stored `points` counter is still winner end-points only and is not mastery.

The mastery board is loaded with the wins bundle. That load is capped at 100 and cached; see `leaderboard-bundle-load.md`.

Task Manager sync skipped: those env keys are absent from `.env.local` and `.env.prod`.

Local backfill applied 2026-10-05, then adjusted the same day for leftover cards. Seed is `(404 * wins - 10 * points - min_cards) // 2`. `min_cards` is 0 when lifetime points are 0, otherwise the fewest cards that can total those points (at most 10 each, at most 4 per win). First pass seeded 478 users. Card adjustment rewrote 6 users who had a points total above 0. Script: `playbooks/00_local/backfill_mastery_from_wins_points.py`.

## Case study

Technical game-systems bullet and overview “what players feel” bullet in `case-study-dutch-card-game.html`.

## Task Manager

skipped — `TASK_MANAGER_BASE_URL`, `TASK_MANAGER_SLUG`, `TM_USERNAME`, and `TM_PASSWORD` are not set in `.env.local` or `.env.prod`.
