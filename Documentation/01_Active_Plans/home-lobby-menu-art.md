# Home and lobby menu art

**Status**: Completed  
**Created**: 2026-10-07  
**Last Updated**: 2026-10-07

## Objective

Use the new menu tiles on the home carousel and the lobby accordion. Store them as WebP.

## Implementation Steps

- [x] Convert the seven PNGs to 768px WebP and drop the PNGs from the asset folder
- [x] Home buttons show the tile image (label is already in the art)
- [x] Lobby Join Random and Practice headers use the Quick Join and Practice tiles

## Current Progress

Home: Play Dutch, Demo, Leaderboard, Customize, Account. Lobby accordion: Quick Join (`quick-join.webp`) and Practice (`practice.webp`). Section ids stay `Join Random` and `Practice` so existing lobby deep links still open the same sections.

## Next Steps

None.

## Files Modified

- `flutter_base_05/assets/images/icons/*.webp`
- `flutter_base_05/lib/modules/dutch_game/managers/feature_contracts.dart`
- `flutter_base_05/lib/core/widgets/feature_slot.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/home_screen/features/home_screen_features.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/collapsible_section_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart`

## Notes

Source PNGs were 1254×1254 RGB, about 1.5MB each, with misspelled filenames. WebP files are 768×768 at quality 82, about 25KB each. The old `play-icon.svg` and `learn-icon.svg` remain in the folder and are no longer used by the home buttons.

Task Manager sync skipped: `TASK_MANAGER_*` / `TM_*` keys are absent.

## Case study

n/a — visual assets only; no game-logic or architecture change.
