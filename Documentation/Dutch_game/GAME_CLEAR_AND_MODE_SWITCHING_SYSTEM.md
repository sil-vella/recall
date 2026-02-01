# Game Clear and Mode Switching System

This document describes how the Dutch game clears state before a new match, how transport mode (WebSocket / Practice / Demo) is set and used, and how late or stale events are ignored so mode switching and Start Match work reliably.

---

## 1. Single Entry Point: `clearAllGameStateBeforeNewGame()`

**Location:** `DutchGameHelpers.clearAllGameStateBeforeNewGame()` (Flutter)

**Purpose:** Single source of truth for “before starting a new match.” Ensures no leftover state from a previous game or mode can affect the next one.

**Callers (always at the start of the flow):**

- `DutchGameHelpers.createRoom()`
- `DutchGameHelpers.joinRoom()` (and lobby `_joinRoom()`)
- `DutchGameHelpers.joinRandomGame()`
- Lobby `_startPracticeMatch()`

**Order of operations:**

1. **Reset coordinator and set transport**
   - `GameCoordinator().resetToInit()` — clear timer and pending leave.
   - `DutchGameEventEmitter.setTransportMode(EventTransportMode.websocket)` — so any `leave_room` sent in step 2 goes over WebSocket.

2. **Clear state queues**
   - Flutter and backend `StateQueueValidator.instance.clearQueue()` — avoid applying old enqueued updates later.

3. **Leave all games**
   - `leaveAllGamesAndClearState()` — for each game in state, leave (WS `leave_room` for `room_*`, or end practice for `practice_room_*`) and remove from local state.

4. **Sync clear core game state**
   - `updateStateSync({ currentGameId: '', games: {}, joinedGames: [], totalJoinedGames: 0 })` — so the UI never sees the previous game as current.

5. **End practice and clear backend caches**
   - `PracticeModeBridge.endPracticeSession()`, `GameStateStore.clearAll()`, `GameRegistry.clearAll()`.

6. **Sync clear practice identity**
   - `updateStateSync({ practiceUser: null, practiceSettings: null })` — so `getCurrentUserId` and event handlers use WebSocket identity until practice is started again.

7. **Clear full game state**
   - `clearGameState()` — phases, messages, instructions, joinedGamesSlice, etc.

8. **Sync clear player and mode flags**
   - `updateStateSync({ playerStatus: 'waiting', ... actionError, isRandomJoinInProgress: false, randomJoinIsClearAndCollect: null })`.

9. **Clear state queues again**
   - Flutter and backend `StateQueueValidator.instance.clearQueue()` — **critical for WS → Practice:** updates enqueued by `leaveAllGamesAndClearState` (e.g. from `removePlayerFromGame`) must not be applied after `_startPracticeMatch` sets practice state, or they would overwrite `currentGameId` / `games`.

---

## 2. Transport Mode (`EventTransportMode`)

**Location:** `validated_event_emitter.dart` — `EventTransportMode { websocket, practice, demo, unset }`

**Role:** Decides where game events are sent: WebSocket, PracticeModeBridge, or DemoModeBridge.

**When it is set:**

- **During clear:** Set to `websocket` at the start of `clearAllGameStateBeforeNewGame()` so `leave_room` is sent over WebSocket.
- **Lobby / UI:**
  - Create room, Join room, Random join → `setTransportMode(EventTransportMode.websocket)` before calling helpers.
  - Start Practice → after `setPracticeStateSync()`, `setTransportMode(EventTransportMode.practice)`.
- **Game play screen:** When entering a practice game, `game_info_widget` sets `EventTransportMode.practice` so in-play actions go to the practice bridge.
- **Demo:** Demo flow sets `EventTransportMode.demo` where needed.

**Auto-sync on emit:** When emitting an event, if `game_id` is present:

- `practice_room_*` → set transport to `practice`.
- `room_*` → set transport to `websocket`.
- `demo_game_*` → set transport to `demo`.
- If transport is still `unset`, it defaults to `websocket` so create/join/leave room work.

---

## 3. Leaving Games: `leaveAllGamesAndClearState()` and `leaveGameAndClearStateForGameId()`

**leaveAllGamesAndClearState()**

- Reads `games` from `dutch_game` state.
- For each key (gameId), calls `leaveGameAndClearStateForGameId(gameId)`.
- If state was already sync-cleared (e.g. `games` empty), the list is empty and no leave is sent; the important case is when the user had joined games before clear — then we leave each one.

**leaveGameAndClearStateForGameId(gameId)**

- Adds `gameId` to `_recentlyLeftGameIds` (used later to ignore stale `game_state_updated`).
- For `room_*`: `GameCoordinator.leaveGame(gameId)` → sends `leave_room` over WebSocket.
- For `practice_room_*`: ends practice session and clears backend state.
- Calls `removePlayerFromGame(gameId)` which updates state (and may enqueue updates in `StateQueueValidator`). The final queue clear in `clearAllGameStateBeforeNewGame()` prevents those enqueued updates from applying after a new mode (e.g. practice) has set state.

---

## 4. Practice Mode: Setting State Before Any Async or Queue

**Problem:** If we switch to Practice and set `currentGameId` / `games` in state, a late WebSocket `game_state_updated` or an enqueued “clear” update could overwrite them.

**Measures:**

1. **Sync practice identity immediately after clear**
   - In `_startPracticeMatch()`, right after `clearAllGameStateBeforeNewGame()`:
   - `DutchGameHelpers.setPracticeStateSync(practiceUserData, updatedPracticeSettings)`.
   - So `practiceUser` and `practiceSettings` are in state before any async or queue processing.

2. **Handler guard in `handleGameStateUpdated`**
   - If `practiceUser != null` and `gameId.startsWith('room_')` → **ignore** the event (we are in practice; this is a WebSocket game event).

3. **Queue flush at end of clear**
   - The second `StateQueueValidator.clearQueue()` in `clearAllGameStateBeforeNewGame()` ensures any updates enqueued by `leaveAllGamesAndClearState` are never applied after `setPracticeStateSync` and the new game state.

4. **Transport mode**
   - After setting practice state, lobby sets `EventTransportMode.practice` so subsequent events (e.g. start_match) go to the practice bridge.

---

## 5. Incoming WebSocket Events: “Game Still in State” and Random Join

**Location:** `DutchGameEventListenerValidator` — before routing game-scoped events to handlers.

**Gate:**

- For events that have a `game_id` or `room_id`:
  - Compute `gameId`.
  - If `!DutchGameHelpers.isGameStillInState(gameId)` **and** `!DutchGameHelpers.isRandomJoinInProgress` → **ignore** the event (log and return).

**Definitions:**

- **isGameStillInState(gameId):** `games.containsKey(gameId) || currentGameId == gameId` in `dutch_game` state. Used to drop events for games we have already left or cleared.
- **isRandomJoinInProgress:** True when we have sent `join_random_game` and are waiting for room / `game_state_updated`. The **first** `game_state_updated` for the new room can arrive before we have put that room in state; we allow it so the new game is added and Start Match can run.

So:

- **Stale WS event** (game not in state, not random-join) → dropped at validator.
- **First event for a random-join room** (game not in state, but random-join in progress) → allowed.

---

## 6. Stale `game_state_updated` in the Handler: Practice and “Recently Left”

**Location:** `DutchEventHandlerCallbacks.handleGameStateUpdated()`.

**Guards:**

1. **Practice mode**
   - If `practiceUser != null` and `gameId.startsWith('room_')` → ignore (already described above).

2. **Recently left**
   - If `currentGames.isEmpty`, `currentGameId.isEmpty`, and `DutchGameHelpers.wasGameRecentlyLeft(gameId)` → ignore.
   - After clear, state is empty; a late `game_state_updated` for the room we just left would otherwise re-add it. `_recentlyLeftGameIds` marks that we just left this game, so we ignore that event.

3. **Clear “recently left” when we add the game**
   - When we add a new game to the map from `game_state_updated`, we call `DutchGameHelpers.clearRecentlyLeftGameId(gameId)` so that game is no longer treated as “recently left.”

---

## 7. Helper Summary

| Helper | Purpose |
|--------|--------|
| `clearAllGameStateBeforeNewGame()` | SSOT clear before new match; resets coordinator, transport, queues, leaves games, sync-clears state, clears queues again. |
| `leaveAllGamesAndClearState()` | Leaves every game in state (WS or practice) and clears their state. |
| `leaveGameAndClearStateForGameId(gameId)` | Leaves one game, marks it in `_recentlyLeftGameIds`, removes from state. |
| `setPracticeStateSync(practiceUserData, practiceSettings)` | Writes practice user/settings to state synchronously so handlers and `getCurrentUserId` see practice mode immediately. |
| `setCurrentGameSync(gameId, games)` | Writes current game and games map to state synchronously (e.g. before navigate to game play). |
| `isGameStillInState(gameId)` | True if game is in `games` or is `currentGameId`; used by validator to drop stale WS events. |
| `isRandomJoinInProgress` | True while waiting for first response after `join_random_game`; allows first `game_state_updated` before game is in state. |
| `wasGameRecentlyLeft(gameId)` | True if we just left that game (in `_recentlyLeftGameIds`); used in handler to ignore late `game_state_updated`. |
| `clearRecentlyLeftGameId(gameId)` | Removes gameId from “recently left” when we add it from an event. |

---

## 8. Mode Switching Flows (Summary)

- **Any mode → New match (same or different mode):** Call `clearAllGameStateBeforeNewGame()` first, then set transport (and for practice, `setPracticeStateSync`), then create/join/start.
- **WebSocket (create/join/random):** Transport set to `websocket` before calling create/join/random; events go to WebSocket; first `game_state_updated` for random join is allowed via `isRandomJoinInProgress`.
- **Practice:** After clear, `setPracticeStateSync` then `setTransportMode(practice)`; late WS `game_state_updated` are ignored by the handler (practiceUser + room_); enqueued clears are discarded by the final queue clear.
- **Stale WS events:** Dropped by validator when game not in state (unless random-join in progress) or by handler when practice mode or recently left.

This keeps game clear and mode switching consistent and prevents stale or cross-mode events from overwriting the current game or blocking Start Match.
