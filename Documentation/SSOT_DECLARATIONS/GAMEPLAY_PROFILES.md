# Gameplay profiles (SSOT)

**Canonical JSON:** [gameplay_profiles.json](../../python_base_04/core/modules/dutch_game/config/gameplay_profiles.json)

Reusable **rule presets** for Dutch matches. Special events reference a profile via `gameplay_profile_id` in [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json).

## Files

| Role | Path |
|------|------|
| **Canonical JSON** | `python_base_04/core/modules/dutch_game/config/gameplay_profiles.json` |
| **Loader** | `python_base_04/core/modules/dutch_game/gameplay_profiles_catalog.py` |
| **Dart WS mirror** | `dart_bkend_base_01/config/gameplay_profiles.json` |
| **Dart store** | `dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/gameplay_profiles_store.dart` |
| **Flutter bootstrap** | `flutter_base_05/lib/modules/dutch_game/utils/gameplay_profiles_bootstrap.dart` |

**Revision constant:** `gameplay_profiles_catalog.GAMEPLAY_PROFILES_REVISION`  
**Client payload keys:** `gameplay_profiles` / `gameplay_profiles_revision`

## Document shape

```json
{
  "schema_version": 1,
  "profiles": {
    "classic": {
      "id": "classic",
      "label": "Classic Dutch",
      "extends": null,
      "flags": { "clear_and_collect": false },
      "deal": { "cards_per_hand": 4, "initial_peek_count": 2 },
      "timers": {},
      "deck": { "source": "standard" },
      "scoring": { "red_king_points": 10 },
      "win_conditions": {
        "empty_hand": true,
        "lowest_points_after_dutch": true,
        "four_of_a_kind_collection": false
      }
    },
    "collector": {
      "id": "collector",
      "extends": "classic",
      "flags": { "clear_and_collect": true },
      "win_conditions": { "four_of_a_kind_collection": true }
    }
  }
}
```

### Profile fields (v1 primitives)

| Section | Keys | Effect |
|---------|------|--------|
| `flags` | `clear_and_collect`, `same_rank_out_of_turn`, `queen_peek`, `jack_swap`, `dutch_call`, `discard_take_allowed` | Rule guards in `dutch_game_round.dart` |
| `timers` | `drawing_card`, `playing_card`, `same_rank_window`, … | Merged into `game_state.timerConfig` at match start |
| `deck` | `source`: `standard` \| `demo` \| `testing` | Deck selection in `game_event_coordinator` |
| `deal` | `cards_per_hand`, `initial_peek_count` | Deal size at match start |
| `scoring` | `red_king_points` | Red king point value (hearts/diamonds) |
| `win_conditions` | `empty_hand`, `lowest_points_after_dutch`, `four_of_a_kind_collection` | Win path toggles |

`extends` merges parent → child (child overrides). Unknown keys are rejected at load time.

### Special event linkage

```json
{
  "id": "dutch_explorer",
  "gameplay_profile_id": "collector",
  "title": "Dutch Explorer",
  "coin_fee": 25
}
```

Omitted `gameplay_profile_id` defaults to `classic` (backward compatible).

## Runtime behavior

1. **Match start (Dart WS):** resolve profile from special event → snapshot in `game_state.gameplay_rules`, `match_class`, derived `isClearAndCollect`, merged `timerConfig`.
2. **Special-event matches:** server profile is authoritative; client `isClearAndCollect` in `start_match` is ignored when `special_event_id` is set.
3. **Mid-match:** catalog edits do not affect active games (snapshot at start).

## Hot reload

Included in `POST /service/dutch/reload-catalogs` and `playbooks/00_local/reload_dutch_catalogs.py`.

Ops:

1. Edit `gameplay_profiles.json` and/or `table_tiers.json` (`gameplay_profile_id` on events).
2. Sync `dart_bkend_base_01/config/*.json` mirrors.
3. Run `python3 playbooks/00_local/reload_dutch_catalogs.py`.
4. Restart Dart WS **or** rely on `fetchInitConfig()` + local file reload (`GameplayProfileResolver.reloadCatalogsFromDisk()` on WS).
5. Flutter refreshes via `get-init-data` when `client_gameplay_profiles_revision` is stale.

## Built-in profiles (v1)

| ID | Purpose |
|----|---------|
| `classic` | Default — no collection |
| `collector` | Clear and collect + four-of-a-kind win |
| `speed_classic` | Shorter turn timers |
| `no_powers` | Queens/Jacks without powers |
| `red_king_royale` | Red kings = 0 points |

## Related

- Special events economics / art: [TABLE_TIERS.md](./TABLE_TIERS.md)
- Hot reload ops: [CATALOG_ADDITION_AND_HOT_RELOAD.md](./CATALOG_ADDITION_AND_HOT_RELOAD.md)
- Init envelope: [INIT_DATA.md](./INIT_DATA.md)
