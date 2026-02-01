# State Updates for New Rooms / Games (from server.log analysis)

This document describes **exactly** which state pieces are updated when the user joins or creates rooms/games, derived from `server.log` across **2 tests**: (1) **join_random_game** (anonymous WebSocket), (2) **Practice match** (practice user).

---

## 1. State keys present in initial state (before any join)

These keys exist from app/StateManager init and are **not** set by room/game events in the observed tests:

- `currentRoomId`, `currentRoom`, `isInRoom`, `myCreatedRooms`, `players`
- `joinedGames`, `totalJoinedGames`, `currentGameId`, `games`
- `userStats`, `showCreateRoom`, `showRoomList`, `actionBar`, `statusBar`
- `myHand`, `centerBoard`, `opponentsPanel`, `myDrawnCard`, `cards_to_peek`, `turn_events`
- `isLoading`, `isConnected`

`currentRoom` and `myCreatedRooms` **do not** appear as handler-invoked keys in the log; they stay as initially set (or default). Only the pieces below are **updated** by join/room/game flows.

---

## 2. State pieces updated when joining a room (e.g. join_random_game)

### 2.1 From backend response to join (before first `game_state_updated`)

| Keys | Source / Trigger |
|------|-------------------|
| `currentRoomId`, `isRoomOwner`, `isInRoom` | Backend response to `join_random_game` / `join_room` |
| `gamePhase`, `gameStatus`, `isGameActive`, `playerCount`, `currentSize`, `maxSize`, `minSize` | Same response (room/game summary) |
| `messages` | Room messages from backend |
| `isRandomJoinInProgress` | Client (set true when starting random join, then false when join completes) |

**Widget slices recomputed** (because their dependency set includes the changed keys):  
`actionBar`, `statusBar`, `centerBoard`, `gameInfo`.  
At this moment **games** map is still empty, so `joinedGamesSlice` stays `null` and **CurrentRoomWidget** still renders "0 games from joinedGamesSlice".

### 2.2 When first `game_state_updated` arrives (game added to map)

| Keys | Source / Trigger |
|------|-------------------|
| **`games`** | `handleGameStateUpdated` → `_addGameToMap(gameId, gameData)` → validated update. **This is the SSOT**: one entry per game the client knows about (current user is a player). |

**Widget slices recomputed** (because `games` changed):  
`actionBar`, `statusBar`, `myHand`, `centerBoard`, `opponentsPanel`, `gameInfo`, **`joinedGamesSlice`**.

- **`joinedGamesSlice`** is **computed** inside `DutchGameStateUpdater._updateWidgetSlices`: it is derived from the **`games`** map (filter: games where current user is a player). So when `games` gets its first entry, `joinedGamesSlice` goes from `null` to a list with 1 game — **CurrentRoomWidget** then "Rendering with 1 games from joinedGamesSlice".

### 2.3 Right after adding game to map (current game and player state)

| Keys | Source / Trigger |
|------|-------------------|
| **`currentGameId`, `games`** | `handleGameStateUpdated` sets `currentGameId` to the new game id when it was null/empty, then pushes this update. |
| **`playerStatus`, `myScore`, `isMyTurn`, `myDrawnCard`, `myCardsToPeek`** | `_syncWidgetStatesFromGameState` (from same game state) → validated update. |
| **`protectedCardsToPeek`** | Same sync; may be no-op if cardsToPeek is empty. |

### 2.4 After processing game state (phase, round, discard, etc.)

| Keys | Source / Trigger |
|------|-------------------|
| **`currentGameId`, `games`, `gamePhase`, `isGameActive`, `roundNumber`, `currentPlayer`, `currentPlayerStatus`, `roundStatus`, `discardPile`, `turn_events`** | `handleGameStateUpdated` builds this bundle from `game_state_updated` payload and pushes validated update. |

Again, any change to **`games`** triggers full widget-slice recomputation including **`joinedGamesSlice`**.

### 2.5 Callback-driven “joined games” list (separate from slice)

| Keys | Source / Trigger |
|------|-------------------|
| **`joinedGames`, `totalJoinedGames`** | **DutchEventHandlerCallbacks**: when it detects a `game_state_updated` for a game where the current user is a player and the game is “new” to the callback, it adds the game to an internal **joinedGames** list and pushes `{ joinedGames, totalJoinedGames }`. Log: *"Adding game &lt;gameId&gt; to joinedGames list (first time)"*. |

So there are **two** representations of “games I’m in”:

1. **`games`** — Map&lt;gameId, gameData&gt; (SSOT). Updated by every `game_state_updated` (add/update entry).
2. **`joinedGames`** / **`totalJoinedGames`** — List/count maintained by callbacks when they see a new game for the current user.
3. **`joinedGamesSlice`** — **Computed** from **`games`** only (see `_widgetDependencies`: `'joinedGamesSlice': {'games'}`). Used by **CurrentRoomWidget** for rendering.

---

## 3. State pieces updated during an ongoing game (both tests)

These are updated on **every** (or many) `game_state_updated` events; they are the same for “new room/game” and “existing game”:

- **`games`** — Map entry for that game id is updated (merge/replace with new `game_state`).
- **`currentGameId`, `games`, `gamePhase`, `isGameActive`, `roundNumber`, `currentPlayer`, `currentPlayerStatus`, `roundStatus`, `discardPile`, `turn_events`** — Bundled update from `handleGameStateUpdated`.
- **`playerStatus`, `myScore`, `isMyTurn`, `myDrawnCard`, `myCardsToPeek`** — From `_syncWidgetStatesFromGameState`.
- **`protectedCardsToPeek`** — From same sync when peek data exists.
- **`messages`** — When a session message is added (e.g. “Game State Updated”).
- **`isRoomOwner`** — Sometimes updated when owner_id is normalized (e.g. practice mode: owner_id vs currentUserId).

Whenever **`games`** changes, all dependent slices are recomputed: **actionBar**, **statusBar**, **myHand**, **centerBoard**, **opponentsPanel**, **gameInfo**, **joinedGamesSlice**.

---

## 4. Summary: state pieces that are updated with new rooms/games

**Directly set by events / callbacks:**

| State key | When it’s updated |
|-----------|-------------------|
| **currentRoomId** | Join response (join_random_game / join_room). |
| **isRoomOwner** | Join response; later possibly corrected (e.g. practice owner_id). |
| **isInRoom** | Join response. |
| **gamePhase**, **gameStatus**, **isGameActive** | Join response; then every game_state_updated. |
| **playerCount**, **currentSize**, **maxSize**, **minSize** | Join response. |
| **messages** | Join/room messages; then session messages. |
| **isRandomJoinInProgress** | Client (start/end of random join). |
| **games** | Every game_state_updated: add or update entry for that gameId (SSOT). |
| **currentGameId** | Set when first game is added (or when switching active game). |
| **playerStatus**, **myScore**, **isMyTurn**, **myDrawnCard**, **myCardsToPeek** | From game state sync after game_state_updated. |
| **protectedCardsToPeek** | From game state sync when peek data present. |
| **joinedGames**, **totalJoinedGames** | Callback when “Adding game … to joinedGames list (first time)”. |
| **currentPlayer**, **currentPlayerStatus**, **roundNumber**, **roundStatus**, **discardPile**, **turn_events** | From game_state_updated payload in handleGameStateUpdated. |

**Computed (widget slices) — not stored as independent source of truth; recomputed when dependencies change:**

| Slice | Depends on | Used by |
|-------|------------|--------|
| **joinedGamesSlice** | **games** | CurrentRoomWidget (“Rendering with N games from joinedGamesSlice”) |
| **actionBar** | currentGameId, games, isRoomOwner, isGameActive, isMyTurn | UI |
| **statusBar** | currentGameId, games, gamePhase, isGameActive | UI |
| **myHand** | currentGameId, games, isMyTurn, turn_events | UI |
| **centerBoard** | currentGameId, games, gamePhase, isGameActive, discardPile, drawPile | UI |
| **opponentsPanel** | currentGameId, games, currentPlayer, turn_events | UI |
| **gameInfo** | currentGameId, games, gamePhase, isGameActive | UI |

**Not updated in the two tests (remain from initial state or other flows):**

- **currentRoom**, **myCreatedRooms** — never appear as handler-invoked keys in the log.

---

## 5. Order of updates (join_random_game, first game)

1. **join_random_game** sent.
2. Backend response → **currentRoomId, isRoomOwner, isInRoom, gamePhase, gameStatus, isGameActive, playerCount, currentSize, maxSize, minSize**.
3. **messages** (room message).
4. **isRandomJoinInProgress** (e.g. false).
5. **game_state_updated** → **_addGameToMap** → **games** (1 entry) → StateManager updated; **joinedGamesSlice** recomputed from **games** (1 game).
6. **currentGameId, games** (currentGameId set to new game id).
7. **protectedCardsToPeek**, **playerStatus, myScore, isMyTurn, myDrawnCard, myCardsToPeek** (from _syncWidgetStatesFromGameState).
8. Further **games** updates (e.g. hand/round data).
9. **currentGameId, games, gamePhase, isGameActive, roundNumber, currentPlayer, currentPlayerStatus, roundStatus, discardPile, turn_events**.
10. **DutchEventHandlerCallbacks**: “Adding game … to joinedGames list (first time)” → **joinedGames, totalJoinedGames**.
11. **messages** (e.g. “Game State Updated”).

So for the **current games widget**, the only state it needs to show “games I’m in” is **joinedGamesSlice**, which is derived from **games**. The **games** map is populated solely by **game_state_updated** and **handleGameStateUpdated** (via _addGameToMap or update of existing entry). **joinedGames** / **totalJoinedGames** are a separate list/count maintained by callbacks and are **not** the source for **joinedGamesSlice** (the slice is computed from **games** only).
