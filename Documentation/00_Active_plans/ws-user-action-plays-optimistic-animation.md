# WS mode: optimistic action plays for user players

**Status**: In Progress  
**Created**: 2026-04-26  
**Last Updated**: 2026-04-26

## Objective

Refactor how **the local user’s** action plays are handled in **WebSocket-driven** Dutch game mode so the UI feels immediate and responsive.

**Today (typical flow):** the client waits for a **server-driven state update** delivered over WS before starting the associated **animation** and reflecting the new game state.

**Target flow:**

1. On user intent (e.g. play / swap / power action), the **front end** immediately:
   - starts the **animation** for that action, and
   - applies a **direct / optimistic** local state change that matches what we expect the server to confirm.
2. When the **WS state update** arrives, the client **verifies** (reconcile) optimistic state against authoritative payload:
   - if they match → no extra visual jump (or minimal cleanup);
   - if they diverge → **authoritative state wins**; correct visuals and cancel or complete animations as needed.

This is specifically about **user-initiated** plays in WS mode; other players’ actions may still be driven primarily by incoming WS events unless we later extend the same pattern.

## Implementation steps

- [ ] Map current path: where user actions enqueue animation vs where WS `game_state` (or equivalent) triggers animation — document call order and race cases.
- [ ] Define an **optimistic patch** shape (or reuse existing reducers) so local state updates mirror server rules for the actions we support first (narrow scope, then expand).
- [ ] Wire **user action** handler: fire animation + optimistic state **before** awaiting WS; tag optimistic revision / sequence id if the protocol provides one.
- [ ] On WS update: **diff or compare** against optimistic snapshot; resolve conflicts and clear optimistic flags.
- [ ] Edge cases: duplicate events, reconnect mid-animation, out-of-order messages, server rejection — define behavior and tests.
- [ ] Regression pass: hot-seat / non-WS paths unchanged unless explicitly unified.

## Current progress

- Plan drafted; no code changes yet.

## Next steps

1. Inventory Dutch game WS handlers and animation queue (Flutter `game_play` + any shared models).
2. Prototype one action type end-to-end with optimistic + verify.
3. Add reconciliation tests (unit or integration) for match and mismatch.

## Files modified

- _(none yet — update as implementation proceeds)_

## Notes

- **Authoritative source** remains server state over WS; optimistic updates are **UX only** until verified.
- Consider **sequence numbers** or monotonic `state_version` from the backend if available to detect stale or duplicate updates.
- If server can **reject** an action, the UI must revert optimistic changes cleanly (snackbar / animation rollback per existing patterns).
- Reference: `Documentation/Dutch_game/ANIMATION_SYSTEM.md` and WS game-state handling in the Dutch module — align with documented animation ordering where possible.
