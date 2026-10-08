# Base screen back button

**Status**: Completed  
**Created**: 2026-10-07  
**Last Updated**: 2026-10-07

## Objective

Put a Back control under the top ad banner that returns to the screen the player came from, without turning every `go()` into a stacked `push()`.

## Implementation Steps

- [x] Back trail in `NavigationManager` (`shouldShowBack`, `goBack`)
- [x] `_BackUnderBanner` on `BaseScreen` under the top banner
- [x] Drawer taps go through `NavigationManager.navigateTo`

## Current Progress

Done. Home never shows Back. Match screens still pop the router stack. Other screens `go()` to the remembered location.

## Next Steps

None.

## Files Modified

- `flutter_base_05/lib/core/managers/navigation_manager.dart`
- `flutter_base_05/lib/core/00_base/screen_base.dart`
- `flutter_base_05/lib/core/00_base/drawer_base.dart`

## Notes

Trail cap is 16. Opening `/` clears it. Returning to a path already in the trail trims instead of stacking. Same-path query updates do not add a step. Task Manager sync skipped: env keys absent.

## Case study

n/a — navigation UX only; no game-logic change.
