# Dutch game: initial peek state + card animation plan

**Status**: In Progress  
**Created**: 2026-04-29  
**Last Updated**: 2026-04-30

## Objective

1. Ensure **game state and UI** respect the **initial peek** phase so players can complete peek before normal turn flow (draw / first player) begins.
2. **Reintroduce card movement animation** in a **generic** way: motion anchored to **player areas** rather than per-slot card geometry, with a **jack swap** exception that stays **position- and id-specific**.

## Context (reported / desired behavior)

- **Initial peek bug**: Game info shows a loading spinner, then the flow jumps straight to **first player drawing** without letting users finish **init peek**. Likely **game state advancing** (or UI reacting to partial state) **before** peek completion is signaled or applied.
- **Animation direction**: Default paths should treat **draw pile** and **discard pile** as **fixed endpoints defined at game init** (not rediscovered each frame from arbitrary card widgets). Most moves animate **to/from the relevant player area**. **Jack swap** must resolve **real targets by card ids** at animation time so swapped cards follow the correct slots.

## Implementation steps

- [x] **Initial peek / game state**: Fix ordering so **state does not transition past “awaiting initial peek”** until peek is complete (client + server if applicable). Verify spinner → peek UI → only then allow draw / current-player turn. Trace: game info widget, Dutch game state machine / WebSocket payloads, and any optimistic UI that assumes “playing” too early. ✅ **Done**
- [x] **`game_animation` SSOT (emit only, all actions)**:
  - [x] Dart backend + mirrored `flutter_base_05` round: **`emitGameAnimation`** before the matching state push; payload: `action_type`, optional `source`, `cards[]` (`owner_id`, `hand_index`, optional `card`; queen peek uses `hand_index: -1` when the target is `drawnCard` only), optional `context` (e.g. queen/jack).
  - [x] Actions covered: **`draw`** (deck/discard privacy as before), **`play_card`** + **`reposition`** when drawn card moves), **`same_rank_play`**, **`collect_from_discard`**, **`jack_swap`**, **`queen_peek`** (id-only card on room emit; full card still STEP 2 for peeker).
  - [x] Flutter: `game_animation` in event validator + **`handleGameAnimation`** log (incl. `context` keys). `turn_events` unchanged for backward compatibility.
- [ ] **Animation architecture (generic)** — *drive from `game_animation` + state, not only `turn_events`*:
  - [ ] Define **player-area** anchors (layout-global or `GlobalKey`-backed rects) and animate cards **to/from those regions** for typical moves (hand, play from hand, etc.).
  - [ ] **Draw** and **discard**: register **predefined targets** once **on game init** (or first layout after init), not per-card slot discovery except where required.
  - [ ] **Jack swap (exception)**: keep **position-specific** motion; **resolve selected / swapped cards by id in real time** (lookup by id at animation start or each tick as needed) so the correct widgets are targeted even if layout shifts.

## Current progress

- **Initial peek / game state**: Completed — players get init peek before normal turn flow; ordering / WS / UI issues addressed.
- **`game_animation` pipeline**: Completed — server emits per action before state; client receives and logs. Spot-check in `python_base_04/tools/logger/server.log` showed **`draw`**, **`play_card`**, **`reposition`**, **`same_rank_play`** for a normal match; **`collect_from_discard`**, **`jack_swap`**, **`queen_peek`**, discard **`draw`** require a session that exercises those paths.
- **Animation architecture (motion)**: Not started — next work is **actual anims** using the new emit data (anchors + motion keyed off `action_type` / `cards` / `context`).

## Next steps

1. **Actual anims from the new emit data**: subscribe in Flutter (or central coordinator) to `game_animation` / merged state order; map `action_type` to motion presets; use `cards` + `context` for endpoints and jack/queen special cases; keep piles anchored at game init per plan above.
2. Optionally tighten logging or add a short subsection under `Documentation/Dutch_game/PLAYER_ACTIONS_FLOW.md` for the WS contract.

## Files modified

- Init peek fix: see git history / touched files under `flutter_base_05/lib/modules/dutch_game/` and `dart_bkend_base_01/` as applicable (not enumerated here).
- **`game_animation`**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`, `.../shared_logic/game_state_callback.dart`, `.../services/game_registry.dart`; mirrors under `flutter_base_05/lib/modules/dutch_game/backend_core/`; Flutter listener: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_listener_validator.dart`, `dutch_event_handler_callbacks.dart`, `dutch_event_manager.dart`, `practice/practice_mode_bridge.dart`.

## Notes

- Prefer **id-based** card resolution for jack swap over index-only assumptions.
- If peek is enforced server-side, ensure the client does not **advance local phase** on an early partial snapshot.
- **`game_animation`** arrives **before** the matching `game_state_updated` (and for queen, before STEP 1 broadcast); client anim layer should assume that ordering.
