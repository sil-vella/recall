# Special-Card Fail/Skip Flow – Jack Swap, Queen Peek, Same Rank, Wrong Same Rank

This document describes what happens when special-card actions **fail**, are **skipped**, or **time out**, and how the acting/target player and timers are reset before the game continues. Scope: Dutch game module in `dart_bkend_base_01` and `flutter_base_05`.

---

## 1. Jack swap – fail / skip / timeout

### 1.1 Where fail/skip/timeout is detected

| Scenario | Where detected | Location |
|----------|----------------|----------|
| **Computer: missed (miss chance)** | `_handleComputerActionWithYAML` → `decision['missed'] == true` | `dutch_game_round.dart` ~1184–1197 |
| **Computer: decline (use: false)** | Same, `decision['use'] == false` | ~1225–1235 |
| **Computer: handleJackSwap returns false** | Same, after `handleJackSwap(...)` | ~1214–1223 |
| **Human: invalid payload (missing fields)** | Coordinator before calling round | `game_event_coordinator.dart` ~206–226 |
| **Human: invalid selection (e.g. cards not in hand)** | `handleJackSwap` returns `false` (validation inside round) | `dutch_game_round.dart` ~3569, 3588, 3604, 3610 |
| **Timeout** | `_onSpecialCardTimerExpired()` | `dutch_game_round.dart` ~5601–5677 |

### 1.2 Flow after fail/skip (computer)

- **Missed or decline (use: false)**  
  - Player status set to `waiting`: `_updatePlayerStatusInGamesMap('waiting', playerId: playerId)`.  
  - Player removed from special-card list: `_specialCardPlayers.removeAt(0)`, then `_specialCardData.clear()` if empty.  
  - State broadcast: `_stateCallback.onGameStateChanged({'games': ...})`.  
  - Next step: `_processNextSpecialCard()` (next special card or end window).  
  - **Timer:** Computer path does not start the 10s special-card timer (only human does in `_processNextSpecialCard`). So no timer to cancel for computer skip/miss.

- **handleJackSwap returned false (e.g. invalid targets)**  
  - Same as above: if `_specialCardPlayers[0]` is this player, remove them, clear `_specialCardData` if empty, broadcast, then `_processNextSpecialCard()`.

So for **computer**: the failing/skipping player is always removed from `_specialCardPlayers`, status set to `waiting`, and flow continues with `_processNextSpecialCard()`.

### 1.3 Flow after fail (human)

- **Coordinator validation fail (missing fields)**  
  - Coordinator sends `jack_swap_error` to session; **does not** call `round.handleJackSwap()`.  
  - **Round state is unchanged:** player remains at front of `_specialCardPlayers`, and the 10s special-card timer (if already started) keeps running.  
  - So the only way to clear the human from “in jack swap” is **timer expiry** (see below).  
  - **Asymmetry:** On coordinator validation fail, the round never removes the player or calls `_processNextSpecialCard()`.

- **handleJackSwap called but returns false** (e.g. invalid players, cards not in hands, exception)  
  - Coordinator only `await round.handleJackSwap(...)` and does not check the return value or call any cleanup on the round.  
  - **Inside round:** `handleJackSwap` has no “on failure” branch that removes the current player or calls `_processNextSpecialCard()`. That logic exists only in the computer branch in `_handleComputerActionWithYAML`.  
  - So again, the human stays in `_specialCardPlayers` and the special-card timer keeps running until **timer expiry**.

### 1.4 Flow on timeout (human or computer)

- **`_onSpecialCardTimerExpired()`** (~5601–5677):  
  - If `_isEndingSpecialCardsWindow` is true, returns immediately (no double cleanup).  
  - For the current player (front of `_specialCardPlayers`):  
    - Clears `cardsToPeek` (and for `dutch_user`, `myCardsToPeek`).  
    - Sets status to `waiting`: `_updatePlayerStatusInGamesMap('waiting', playerId: playerId)`.  
    - Removes that entry: `_specialCardPlayers.removeAt(0)`, and if list empty, `_specialCardData.clear()`.  
  - **Timer:** This is the expiry callback of `_specialCardTimer`; the timer is not explicitly cancelled here (it has already fired).  
  - After a 2s delay, calls `_processNextSpecialCard()`.

So on **timeout**, the acting player is fully reset (status, peek data, removed from list), and the next special card or end of window is processed.

### 1.5 Timer cancellation (Jack swap)

- **Cancelled when Jack swap completes successfully:**  
  `_specialCardTimer?.cancel()` in `handleJackSwap` (~3758).  
- **Cancelled when special cards window ends:**  
  `_specialCardTimer?.cancel()` in `_endSpecialCardsWindow()` (~5752).  
- **Not cancelled** when human Jack swap **fails** (invalid payload or `handleJackSwap` returns false): the round never removes the player or calls `_processNextSpecialCard()`, so the 10s timer (if started) runs until expiry.

### 1.6 Flutter UI reset (Jack swap)

- **When status changes from `jack_swap` to `waiting`** (`unified_game_board_widget.dart` ~3533–3556):  
  - `selectedCardIndex` and `myHand.selectedIndex` set to -1.  
  - `PlayerAction.resetJackSwapSelections()` is called (clears first/second card and player IDs).  
- So the “failed/skipped” player is **only** fully reset in the UI when the backend has set their status to `waiting` (e.g. after timeout or after computer skip/fail in round).  
- **jack_swap_error:** Server sends `jack_swap_error` on coordinator validation fail. The client has `handleDutchError` for `dutch_error` (sets `actionError` for UI). If `jack_swap_error` is not mapped to the same handler, the user may not see the error message; in any case, **Flutter does not call `resetJackSwapSelections()` on `jack_swap_error`** — only on status change to `waiting`. So selections can remain until timeout and status update.

**Summary (Jack swap):**  
- Computer: fail/skip always removes player, sets waiting, advances via `_processNextSpecialCard()`; no special-card timer for computer.  
- Human: on validation fail or `handleJackSwap` false, round does **not** remove player or cancel timer; only timeout clears the player and then Flutter resets UI when status becomes `waiting`.

---

## 2. Queen peek – fail / skip / timeout

### 2.1 Where fail/skip/timeout is detected

| Scenario | Where detected | Location |
|----------|----------------|----------|
| **Computer: missed** | `decision['missed'] == true` | `dutch_game_round.dart` ~1241–1255 |
| **Computer: decline (use: false)** | `decision['use'] == false` | ~1277–1288 |
| **Computer: handleQueenPeek returns false** | After `handleQueenPeek(...)` | ~1265–1275 |
| **Human: invalid payload** | Coordinator (e.g. missing cardId/ownerId) – no round call | `game_event_coordinator.dart` ~171–189 |
| **Human: handleQueenPeek returns false** | Inside round (e.g. target/peeking player not found, game ended) | `dutch_game_round.dart` ~3828, 3848, 3869, 3882, 4041 |
| **Timeout** | `_onSpecialCardTimerExpired()` | ~5601–5677 |

### 2.2 Flow after fail/skip (computer)

- Same pattern as Jack swap:  
  - Status → `waiting`, remove from `_specialCardPlayers`, clear `_specialCardData` if empty, broadcast, then `_processNextSpecialCard()`.

### 2.3 Flow after fail (human)

- Coordinator does not use the return value of `handleQueenPeek()`.  
- **Round:** `handleQueenPeek` has no branch that, on failure, removes the current player or calls `_processNextSpecialCard()`. So when it returns `false`, the human remains in `_specialCardPlayers` and the special-card timer (if started) keeps running.  
- Clear path is again **timer expiry** → `_onSpecialCardTimerExpired()` → status `waiting`, remove from list, clear `cardsToPeek`/`myCardsToPeek`, then `_processNextSpecialCard()`.

### 2.4 Timer cancellation (Queen peek)

- **On success:** `_specialCardTimer?.cancel()` in `handleQueenPeek` (~4022); then peeking-phase timer is started; when it expires, `_onPeekingPhaseTimerExpired()` advances (set waiting, remove from list, `_processNextSpecialCard()`).  
- **On fail:** Round does not cancel `_specialCardTimer`; expiry clears the player as above.

### 2.5 Flutter reset (Queen peek)

- When status changes away from `queen_peek` (e.g. to `waiting`), the same pattern as other statuses applies.  
- Timer expiry clears `cardsToPeek` and (for `dutch_user`) `myCardsToPeek` in the round, and Flutter reflects the updated state.

**Summary (Queen peek):**  
- Computer: fail/skip removes player, sets waiting, `_processNextSpecialCard()`.  
- Human: on `handleQueenPeek` false, round does not remove player or cancel timer; timeout clears and advances.

---

## 3. Same rank – fail / skip / timeout

### 3.1 Where fail/skip/timeout is detected

| Scenario | Where detected | Location |
|----------|----------------|----------|
| **Computer: missed (miss chance)** | `decision['missed'] == true` | `dutch_game_round.dart` ~1148–1153 |
| **Computer: no play (play: false)** | `decision['play'] == false` | ~1175–1178 |
| **Computer: invalid cardId or handleSameRankPlay false** | After `handleSameRankPlay` or missing cardId | ~1158–1173 |
| **Human: timeout** | Same-rank window timer expiry → `_endSameRankWindow()` | ~4227–4228, 4240 |
| **Human: no play** | Same; window ends when timer fires | |

### 3.2 Flow after fail/skip (computer)

- In all cases: `_moveToNextPlayer()` is called.  
- **No** removal from a “special card” list (same rank is a separate window).  
- The same-rank **window** is still open; the **next** player in rotation may still be in `same_rank_window` and the same-rank timer keeps running until `_endSameRankWindow()`.

### 3.3 Flow when same rank window ends (timeout or all done)

- **`_endSameRankWindow()`** (~4240):  
  - All players set to `waiting`: `_updatePlayerStatusInGamesMap('waiting', playerId: null)`.  
  - `gamePhase` set to `player_turn`.  
  - Then: `_checkComputerPlayerSameRankPlays`, `_checkComputerPlayerCollectionFromDiscard`, then `_handleSpecialCardsWindow()`.  
- **Timer:** `_sameRankTimer` is not cancelled in the “same rank fail/skip” paths; it is cancelled when the timer callback runs (`_endSameRankWindow`) or in game-end cleanup (~4864).

So the player who “missed” or declined same rank is only reset to `waiting` when **the whole same rank window ends** (timer or natural flow), not immediately on their skip.

### 3.4 Flutter reset (same rank)

- When `gamePhase` and player status are updated (e.g. all to `waiting` and phase to `player_turn`), UI updates from state.  
- No separate “same rank pending action” store in the round; the window is driven by phase and timer.

**Summary (same rank):**  
- Fail/skip → `_moveToNextPlayer()`; same-rank timer continues; all players set to `waiting` only when `_endSameRankWindow()` runs.

---

## 4. Wrong same rank (penalty applied)

### 4.1 Where wrong same rank is detected

- **Round:** `handleSameRankPlay` → `_validateSameRankPlay(gameState, cardRank)` is false (~3200–3208).  
- Then: wrong-rank branch adds `same_rank_reject_*` action (card to discard then back to hand), applies penalty (draw from draw pile, add to hand), adds `drawn_card_*` action for the penalty card.

### 4.2 Flow after wrong same rank (penalty applied)

- **Round** (~3208–3343):  
  - `same_rank_reject` and `drawn_card` actions queued for UI.  
  - Player status set to `waiting`: `_updatePlayerStatusInGamesMap('waiting', playerId: playerId, gamesMap: currentGames)`.  
  - State broadcast with updated hand and draw pile.  
  - **Returns `true`** (penalty was applied successfully).  
- **Same-rank timer:** **Not** cancelled. The same-rank window is still open for other players; `_sameRankTimer` keeps running until it expires and `_endSameRankWindow()` is called.  
- So the **acting** player (who played the wrong rank) is reset to `waiting` and gets the penalty card; the **window** continues for others until the single shared timer ends.

### 4.3 Who gets control next

- No immediate “next player” call in the wrong-rank branch.  
- Current player is set to `waiting`; the **same rank window** is still in effect (other players can still play same rank).  
- When `_sameRankTimer` expires, `_endSameRankWindow()` runs → all to `waiting`, then `_handleSpecialCardsWindow()` → eventually `_moveToNextPlayer()` from normal flow.  
- So: wrong-rank player is reset (status, hand updated); turn order and “who is next” are determined by the shared same-rank window end, then special cards, then normal turn.

### 4.4 Flutter (wrong same rank)

- UI plays `same_rank_reject` then `drawn_card` animations from the action queue.  
- State update carries the new hand and `waiting` status, so the acting player’s UI reflects “no longer in same-rank action” and the new card.

**Summary (wrong same rank):**  
- Acting player is set to `waiting` and gets penalty; same-rank timer is **not** cancelled; window continues for others until timer expiry, then `_endSameRankWindow()` and normal progression.

---

## 5. Reference – key symbols and files

| What | Where |
|------|--------|
| Special card timer | `_specialCardTimer` – started in `_processNextSpecialCard`, cancelled on success in `handleJackSwap` / `handleQueenPeek`, and in `_endSpecialCardsWindow` |
| Same rank timer | `_sameRankTimer` – started in `_startSameRankTimer`, cancelled in game-end and when callback runs (`_endSameRankWindow`) |
| Peeking phase timer | `_peekingPhaseTimer` – after queen peek success; expiry → `_onPeekingPhaseTimerExpired` |
| Clear special card list | `_specialCardPlayers.removeAt(0)`, `_specialCardData.clear()` when empty |
| Advance after special card | `_processNextSpecialCard()` or `_endSpecialCardsWindow()` then `_moveToNextPlayer()` |
| Jack swap UI reset (Flutter) | `PlayerAction.resetJackSwapSelections()` when status goes from `jack_swap` to `waiting` in `unified_game_board_widget.dart` |
| Human fail not cleared in round | `handleJackSwap` / `handleQueenPeek` return `false` without removing player or calling `_processNextSpecialCard()`; coordinator does not act on return value |

---

## 6. Asymmetries and edge cases

1. **Human Jack swap / Queen peek fail**  
   Round does not remove the player or call `_processNextSpecialCard()`. Only the 10s special-card timer expiry clears them. So the “failed” human stays in the special-card slot until timeout.

2. **Coordinator jack_swap validation fail (missing fields)**  
   Round is never called; player stays in `_specialCardPlayers` and timer (if started) keeps running. Again, only timeout clears.

3. **Flutter:**  
   `resetJackSwapSelections()` is only called when status changes from `jack_swap` to `waiting`. On `jack_swap_error` (or any error event), the client does not clear Jack swap selections; they clear when the next state update has status `waiting`.

4. **Wrong same rank**  
   Only the acting player is set to `waiting`; the same-rank timer is not cancelled, so the window continues for others.

5. **Computer special cards**  
   No 10s special-card timer is started for computer; skip/fail is handled synchronously in `_handleComputerActionWithYAML` by removing the player and calling `_processNextSpecialCard()`.
