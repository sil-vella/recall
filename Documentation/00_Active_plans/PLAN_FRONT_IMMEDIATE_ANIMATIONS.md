# Plan: Front-Immediate Animations (Less Invasive)

**Status:** Proposal only — no code changes.  
**Scope:** Improve perceived speed by making the UI feel immediate for the current user’s actions, then confirm with backend. No batching; backend handling unchanged.

---

## 1. Where the “slow” feeling comes from

From **ANIMATION_SYSTEM.md** and the codebase:

1. **Backend round-trip**  
   User taps play → `PlayerAction.execute()` → `ValidatedEventEmitter.emit('play_card', …)` → WebSocket → Dart backend processes → backend broadcasts `game_state_updated` → client receives → `handleGameStateUpdated` updates `StateManager` → **only then** does the UI react.

2. **Animation-driven display**  
   `UnifiedGameBoardWidget` listens to `StateManager`. On any state change it runs `_onStateChanged` → `_processStateUpdate(currentState)`. That:
   - Collects all `player['action']` entries from the new state
   - Runs **one animation per action** sequentially (e.g. `play_card` = 1000 ms `moveWithEmptySlot`)
   - Uses `_prevStateCache` so the board shows **old** state during the animation; when the animation completes it calls `_updatePrevStateCache()` so the board “catches up”

3. **Durations** (from `animations.dart`)  
   - `play_card` / `same_rank`: **1000 ms**  
   - `drawn_card` / `collect_from_discard`: **1000 ms**  
   - `flashCard` (peek): **1000 ms**  
   - `compoundSameRankReject`: **2000 ms**

So the user sees: **tap → wait (RTT + backend work) → 1 s animation → board updated**. The main visible lag is the animation phase (and optionally RTT). Backend handling is acceptable; the doc explicitly avoids batching/debounce.

---

## 2. Principle: “Mostly front immediate, then confirm with backend”

- **Do not** change how often we send or receive state (no batching, no debounce).
- **Do** make the **current user’s** actions feel instant: update what they see locally as soon as they act, then reconcile when the real `game_state_updated` arrives.
- **Do** keep animations for **other** players (and for confirmations / corrections) so the game stays readable.

Concretely:

- When the **local user** plays a card (or same-rank, draw, etc.):
  - Update local state (or a small “pending” layer) **immediately** so the card appears to move / disappear / appear on discard without waiting for the server.
  - Optionally run a **short** or **no** animation for that action (e.g. 150–300 ms or 0 ms).
  - Send the same `play_card` (etc.) event to the backend as today.
  - When `game_state_updated` arrives with the server’s truth:
    - If it matches the optimistic update: mark it confirmed, no need to re-animate (existing duplicate detection via `Animations.isActionProcessed` / `_activeAnimations`).
    - If it differs (e.g. invalid play, same_rank_reject): reconcile (show server state, optionally run correction animation like `same_rank_reject`).

- For **other** players’ actions:
  - Keep current behaviour: wait for `game_state_updated`, then run the existing 1000 ms (or configurable) animations so everyone sees the same “movie”.

---

## 3. Suggested approaches (by invasiveness)

### Option A — Shorten durations only (minimal)

- **Change:** In `animations.dart`, reduce `getAnimationDuration` for the main types, e.g.:
  - `moveCard` / `moveWithEmptySlot`: 1000 ms → **400–500 ms** (or make configurable).
  - `flashCard`: 1000 ms → **500 ms**.
- **Pros:** One place to edit; no new flows; same logic, faster.
- **Cons:** Still “wait for backend then animate”; no true “instant” for own actions.

### Option B — Optimistic “pending” state + confirm on `game_state_updated` (recommended direction)

- **Idea:** When the user commits an action (play card, same-rank, draw, etc.):
  1. **Immediately** push a small “pending action” into state or a dedicated store (e.g. `pendingPlay: { cardId, fromIndex, gameId }`). The UI layer that draws **my hand** and **discard** reads this and:
     - Removes the card from hand (or marks it “in flight”).
     - Optionally shows the card on discard or in a short “moving” animation (e.g. 200–300 ms).
  2. Send the same event to the backend as today.
  3. When `game_state_updated` arrives:
     - If the backend state includes the same logical action (e.g. same card played), treat it as confirmation: clear `pendingPlay`, and **do not** run the full 1000 ms animation for that action (skip or mark as already processed for the current user’s action).
     - If the backend rejects or sends something different (e.g. `same_rank_reject`), clear pending and apply server state; run the existing rejection animation.

- **Where to hook:**
  - **Emit side:** Right after (or inside) `PlayerAction.execute()` for `playCard` / `playSameRank` / `drawCard` / etc., before or in parallel with `_eventEmitter.emit(...)`, call a small helper that sets `pendingPlay` (or equivalent) in state or in a store the board reads.
  - **Receive side:** In `handleGameStateUpdated` (or in `_processStateUpdate` when building the action list), when the acting player is the current user and the action matches the pending one, mark that action as “already applied optimistically” so the animation layer skips it (or runs a 0 ms / very short “sync” animation).
- **Data:** Pending state should hold at least: `gameId`, `actionType` (e.g. `play_card`), `cardId` and/or `cardIndex`, `playerId` (current user). So when the server says “player X played card Y”, we can match and clear.

- **Pros:** User sees immediate feedback; backend and rest of flow unchanged; other players still get full animations.
- **Cons:** Need a clear place for “pending” state, and to avoid double animation when server confirms (duplicate detection already helps; we’d extend it for “optimistic already shown”).

### Option C — Optimistic state merge (no separate “pending” layer)

- **Idea:** Same as B, but instead of a separate `pendingPlay`, we **merge** the intended outcome into the state we show for the current game (e.g. remove card from my hand, add to discard) in a “pending” slice that `_getPrevStateDutchGame()` (or the reader used by the board) prefers over server state until the next `game_state_updated`. When server state arrives, replace with server state and, if the action is for the current user, skip the corresponding animation.
- **Pros:** Reuses existing “prev_state” / display state notion.
- **Cons:** More risk of subtle bugs (what if server is late or reorders); need to be careful with overwriting and with phase/status (e.g. same_rank window).

### Option D — “Instant” animation for own actions only

- **Idea:** No optimistic state; when `_processStateUpdate` runs and the action is for the **current user** (compare `actionPlayerId` to `getCurrentUserId()`), use a much shorter duration (e.g. 150 ms) or `Duration.zero` for that one animation. Other players keep 1000 ms.
- **Pros:** Very small change: in `_triggerAnimation` (or in the place that gets duration from `Animations.getAnimationDuration`), pass “isCurrentUser” and choose duration accordingly.
- **Cons:** User still waits for RTT + backend before anything moves; only the animation after the fact is shorter.

---

## 4. Recommendation

- **Short term (minimal):** **Option A** — reduce durations in `animations.dart` (e.g. 500 ms for move types). Improves feel with almost no risk.
- **Next step (better UX):** **Option B** — add a small “pending action” (or optimistic) layer for the current user’s play/same-rank/draw; update UI immediately; on `game_state_updated`, confirm and skip re-animation for that action, or reconcile on reject. Keeps backend and batching/debounce untouched.
- Option D can be added on top of B (short or zero duration for “confirm” animations when server echoes the same action).

---

## 5. Implementation notes (for Option B)

- **Pending store:** Either a new key in `StateManager` (e.g. `dutch_game.pendingLocalAction`) or a dedicated stream/store that `UnifiedGameBoardWidget` (and any hand/discard slice) subscribes to. Structure: `{ gameId, actionType, cardId?, cardIndex?, playerId, timestamp }`.
- **Who sets pending:** In the flow that calls `PlayerAction(…).execute()` for play_card / same_rank / draw_card, right before or after `execute()`, set the pending action from the same payload (game_id, card_id, etc.).
- **Who clears pending:** In `handleGameStateUpdated` or at the start of `_processStateUpdate`, when we have a matching server action for the current user, clear pending and mark that action so the animation is skipped (e.g. call `Animations.markActionAsProcessed` for the server’s action name so the loop skips it, or skip adding it to `allActions` for the current user’s confirmed action).
- **Display:** The widget that builds “my hand” and “discard” (or the logic that feeds `_getPrevStateDutchGame`) must consider pending: if there is a pending play_card for the current game, remove that card from my hand and add it to discard in the displayed state until the next state update clears it.
- **Rejection:** If server sends `same_rank_reject` or invalidates the play, clear pending and apply server state; run the existing compound animation for reject so the user sees the card come back.

---

## 6. Files to touch (reference only; no changes in this doc)

- **Option A:** `flutter_base_05/lib/modules/dutch_game/screens/game_play/functionality/animations.dart` — `getAnimationDuration`.
- **Option B:**  
  - `PlayerAction` / call site of `execute()` for play_card, same_rank, draw_card — set pending.  
  - `dutch_event_handler_callbacks.dart` or `unified_game_board_widget.dart` — clear pending and skip animation when server confirms.  
  - State or store for pending (e.g. `StateManager` or a small `PendingActionNotifier`).  
  - Board/hand/discard builder — read pending and merge into displayed state for current user.  
- **Option D:** `unified_game_board_widget.dart` — `_triggerAnimation` or the code that resolves duration; pass `isCurrentUser` and use shorter/zero duration.

---

## 7. Summary

- **Problem:** Perceived slowness is mostly from (1) waiting for backend and (2) long animations (e.g. 1 s) after state arrives.
- **Approach:** Keep backend and message flow as-is. Make the UI **front-immediate** for the current user: show their action right away (optional short animation), then confirm with backend and skip or shorten the “confirm” animation. Other players still get full animations.
- **Least invasive:** Option A (shorter durations). **Best UX:** Option B (optimistic pending + confirm). Option D can complement B by making the confirm step instant or very short.
