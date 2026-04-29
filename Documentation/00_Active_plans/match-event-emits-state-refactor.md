# Match event emits and state updates — full refactor (zero duplicates)

**Status**: In Progress  
**Created**: 2026-04-28  
**Last Updated**: 2026-04-29

## Objective

Refactor how **match-scoped events** are emitted (client → server) and how **game/match state** is applied (server → client, and local/demo paths) so that:

1. There is **exactly one code path** per concern: emit validation, state merge, widget-slice sync, and deduplication.
2. **All duplicate** updates, signatures, merges, and `StateManager` writes are **removed** — no parallel “fast path” and “slow path,” no repeated extraction of the same fields (`turn_events`, `game_state`, slices), and no double-application of the same logical event.

## Problem statement (current pain)

- **Flutter client**: `dutch_event_handler_callbacks.dart` centralizes much WS handling but still chains multiple helpers (`_updateGameData`, `_updateGameInMap`, `_updateMainGameState`, `_syncWidgetStatesFromGameState`, incremental `changedProperties` branches, etc.). The same conceptual state (e.g. hands, discard, phase, `turn_events`) can be touched in more than one step per inbound event.
- **Deduplication** exists in places (e.g. event signatures / stale drops for `game_state_updated`) but **does not guarantee** a single writer to `dutch_game` module state or a single normalization pipeline — duplicates can still appear as redundant `updateModuleState` calls or slice rebuilds.
- **Dart backend** (`game_registry.dart`, `game_event_coordinator.dart`): broadcasting and validated updates both mention `turn_events` and payload shaping; risk of **duplicated extraction** or divergent broadcast shapes vs what the client validates.
- **Emit side**: `validated_event_emitter.dart` / `DutchGameEventEmitter` vs ad-hoc emits from screens — patterns should converge on **one emitter API** and one server contract.

## Guiding principles

| Principle | Meaning |
|-----------|---------|
| **Single reducer** | One function (or small composable set with no overlap) turns `(prevDutchGameState, inboundEvent)` → `nextState`. No second “sync slices” pass that repeats merge logic. |
| **Emit once** | One validated emit pipeline per user action; idempotency keys where the server supports them. |
| **Deduplicate at the edge** | At most one layer owns drop-if-duplicate / drop-if-stale (preferably right before the reducer). |
| **SSOT for slices** | `myHand`, `opponentsPanel`, `centerBoard`, etc. are **derived from** `games[gameId]` (or explicitly documented exceptions), not independently patched in multiple places. |

## Implementation steps

- [ ] **Inventory**: List every `StateManager().updateModuleState('dutch_game', …)` and every path that mutates `games` / slices / `turn_events` (Flutter: callbacks, manager, demo, practice; Dart: registry, coordinator; Python if any direct WS payloads).
- [ ] **Define canonical event model**: Document the minimal set of inbound event types and payloads for “match in progress” (e.g. `game_state_updated`, room lifecycle, errors). Map each to one reducer input shape.
- [ ] **Implement `DutchGameStateReducer` (name TBD)**: Pure(ish) merge: given previous module state + validated event payload → full next `dutch_game` map (or structured patch with a single `updateModuleState` at the end).
- [ ] **Collapse `_syncWidgetStatesFromGameState`**: Either fold into the reducer output or replace with pure derivation from `games[gameId].gameData` so it cannot drift from game_state.
- [ ] **Unify client emit**: Route all match actions through `ValidatedEventEmitter` / `DutchGameEventEmitter`; remove duplicate emit helpers from screens/modules.
- [ ] **Unify server broadcast**: One builder for `game_state_updated` (and siblings) including `turn_events` / `state_version`; remove duplicate root vs nested extraction in `game_registry` / validators.
- [ ] **Tests**: Unit tests for reducer (same event twice → identical state; stale version dropped; slice consistency). Integration smoke: one WS message → exactly one `updateModuleState` (optional: debug assert in tests).
- [ ] **Remove dead code**: Delete superseded helpers and duplicate signature builders after the single path is proven in dev.

## Current progress

- Implemented single-path server state emission via callback flow, including scoped private overlays (`myCardsToPeek`) in the same emit loop.
- Removed `StateQueueValidator` end-to-end (backend + frontend), including all queue usage and validator file deletions.
- Added backend micro-batching for rapid `onGameStateChanged` bursts so updates within one microtask are merged before apply/emit.
- Consolidated frontend `handleGameStateUpdated` to build one main patch and apply it once at the end of the handler.
- Fixed runtime regressions discovered in logs:
  - Python boolean literal fix (`false` -> `False`) in avatar upload utility.
  - Auto-complete null-cast guard hardening in game coordinator (skip invalid/null hand entries and missing ids safely).
- Confirmed from latest logs:
  - Prior hard crashes are no longer present.
  - `null` hand entries are intentional placeholders for index preservation and are treated as valid behavior.
- Implemented gameplay rebuild isolation groundwork on Flutter:
  - Added `DutchSliceBuilder` selector widget to rebuild only on slice deltas.
  - Switched major gameplay overlays and board/screen listeners from broad `StateManager` listeners to selector-based subscriptions.
  - Removed several whole-state spread writes in `UnifiedGameBoardWidget` (`{...currentState, ...}`) in favor of minimal patch updates.
  - Added explicit slice outputs/dependencies in `DutchGameStateUpdater` (`messagesSlice`, `instructionsSlice`, `actionTextSlice`, `matchLifecycle`) to support widget-owned subscriptions.

## Next steps

1. Continue narrowing `UnifiedGameBoardWidget` selectors to smaller section-specific payloads and remove remaining root-state reads in build paths.
2. Audit `*_acknowledged` event handling and keep only ack flows that impact UX/control-state.
3. Re-run validation scenarios and compare before/after event volume + state apply counts.

## Files modified

- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`
- `dart_bkend_base_01/lib/server/websocket_server.dart`
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart`
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart`
- `flutter_base_05/lib/modules/dutch_game/widgets/dutch_slice_builder.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/game_play_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/game_info_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/messages_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/action_text_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/widgets/instructions_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart`
- `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
- `python_base_04/core/modules/user_management_module/avatar_upload_utils.py`
- Deleted validator files:
  - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/state_queue_validator.dart`
  - `dart_bkend_base_01/lib/modules/dutch_game/utils/state_queue_validator.dart`
  - `flutter_base_05/lib/modules/dutch_game/backend_core/utils/state_queue_validator.dart`
  - `flutter_base_05/lib/modules/dutch_game/utils/state_queue_validator.dart`

## Notes

- **Practice mode** and **WebSocket ignore** rules (e.g. practice vs live `game_id`) must remain explicit inputs to the reducer, not parallel branches that copy-paste merge logic.
- **Animation removal** (prior work): `turn_events` may still be sent for analytics or future UI; the reducer should treat them as normal fields, not a second sync channel unless product requires otherwise.
- Respect **immutable core** rules: prefer new module files / reducers under `dutch_game/` over editing `lib/core/managers/*` unless the team explicitly approves moving `StateManager` usage behind a thin adapter.
