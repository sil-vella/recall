# Dutch game: initial peek state + card animation plan

**Status**: In Progress  
**Created**: 2026-04-29  
**Last Updated**: 2026-04-29

## Objective

1. Ensure **game state and UI** respect the **initial peek** phase so players can complete peek before normal turn flow (draw / first player) begins.
2. **Reintroduce card movement animation** in a **generic** way: motion anchored to **player areas** rather than per-slot card geometry, with a **jack swap** exception that stays **position- and id-specific**.

## Context (reported / desired behavior)

- **Initial peek bug**: Game info shows a loading spinner, then the flow jumps straight to **first player drawing** without letting users finish **init peek**. Likely **game state advancing** (or UI reacting to partial state) **before** peek completion is signaled or applied.
- **Animation direction**: Default paths should treat **draw pile** and **discard pile** as **fixed endpoints defined at game init** (not rediscovered each frame from arbitrary card widgets). Most moves animate **to/from the relevant player area**. **Jack swap** must resolve **real targets by card ids** at animation time so swapped cards follow the correct slots.

## Implementation steps

- [x] **Initial peek / game state**: Fix ordering so **state does not transition past “awaiting initial peek”** until peek is complete (client + server if applicable). Verify spinner → peek UI → only then allow draw / current-player turn. Trace: game info widget, Dutch game state machine / WebSocket payloads, and any optimistic UI that assumes “playing” too early. ✅ **Done**
- [ ] **Animation architecture (generic)**:
  - [ ] Define **player-area** anchors (layout-global or `GlobalKey`-backed rects) and animate cards **to/from those regions** for typical moves (hand, play from hand, etc.).
  - [ ] **Draw** and **discard**: register **predefined targets** once **on game init** (or first layout after init), not per-card slot discovery except where required.
  - [ ] **Jack swap (exception)**: keep **position-specific** motion; **resolve selected / swapped cards by id in real time** (lookup by id at animation start or each tick as needed) so the correct widgets are targeted even if layout shifts.

## Current progress

- **Initial peek / game state**: Completed — players get init peek before normal turn flow; ordering / WS / UI issues addressed.
- **Animation architecture**: Not started.

## Next steps

- Implement generic player-area card motion, draw/discard anchors at game init, and jack-swap id-based targeting (per unchecked items above).

## Files modified

- Init peek fix: see git history / touched files under `flutter_base_05/lib/modules/dutch_game/` and `dart_bkend_base_01/` as applicable (not enumerated here).

## Notes

- Prefer **id-based** card resolution for jack swap over index-only assumptions.
- If peek is enforced server-side, ensure the client does not **advance local phase** on an early partial snapshot.
