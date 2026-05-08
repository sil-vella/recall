# Declarative Consumables Backend SSOT

**Status**: In Progress  
**Created**: 2026-05-08  
**Last Updated**: 2026-05-08

## Objective
Make Dutch consumables and cosmetics backend-declarative with revision-based delivery and Flutter-side cached bootstrap, aligned with the existing table tiers and special events pattern.

## Implementation Steps
- [x] Add declarative backend catalog module + JSON source.
- [x] Replace hardcoded shop catalog usage with catalog module lookups.
- [x] Add consumables revision handshake in `get-user-stats`.
- [x] Add Flutter consumables bootstrap cache utility (prefs revision + doc).
- [x] Wire revision query + envelope merge into Dutch stats fetch.
- [x] Make shop catalog helper cache-first with backend refresh fallback.
- [ ] Run broader functional validation on live flows (purchase/equip/win-consume).
- [x] Add declarative cosmetic style fields (card background color, table border colors, border style) and wire Flutter renderers.

## Current Progress
- Backend SSOT now lives in `consumables_catalog.py` backed by `config/consumables_catalog.json`.
- `api_endpoints.py` now serves active catalog items from the new module and includes:
  - `consumables_catalog_revision`
  - conditional `consumables_catalog` payload when client revision is stale/missing.
- Purchase logic for boosters/booster packs now uses declarative grant mapping from catalog entries.
- Flutter now caches consumables catalog doc/revision and includes `client_consumables_catalog_revision` in initial stats fetch.
- Shop data path now prefers cached catalog and falls back to `/get-shop-catalog`, then re-caches.
- Added declarative style metadata in consumables catalog:
  - Card backs: `style.card_background_color`, `style.frame_border_color`.
  - Table designs: `style.border_style` (`solid`/`stripes`) and `style.border_colors` (up to 2).
- Flutter now resolves card back colors and table border styling from cached catalog styles; legacy ID-based switches remain fallback behavior.
- Stripe painter keeps Juventus stripe width/pattern as the standard when `border_style` is `stripes`.

## Next Steps
- Execute live end-to-end checks:
  - cold start (no cache)
  - warm start (matching revision)
  - stale revision refresh
  - visual validation for catalog-driven colors/styles (card background + table stripe/solid borders)
  - purchase/equip compatibility
  - booster consume path parity
- If all checks pass, mark this plan completed.

## Files Modified
- `python_base_04/core/modules/dutch_game/config/consumables_catalog.json`
- `python_base_04/core/modules/dutch_game/consumables_catalog.py`
- `python_base_04/core/modules/dutch_game/api_endpoints.py`
- `flutter_base_05/lib/modules/dutch_game/utils/consumables_catalog_bootstrap.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
- `flutter_base_05/lib/modules/dutch_game/widgets/card_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/utils/table_design_style_helpers.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/game_play_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/shop/dutch_cosmetics_shop_screen.dart`

## Notes
- Inventory schema remains backward compatible (`inventory.boosters`, `inventory.cosmetics`) to avoid migration risk.
- Declared booster grant keys allow backend-only item add/remove for the supported item types without Flutter updates.
