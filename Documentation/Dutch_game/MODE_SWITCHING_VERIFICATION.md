# Mode Switching Verification: Practice ↔ WebSocket

## Overview
This document verifies the implementation of mode switching between Practice mode and WebSocket (multiplayer) mode.

## Implementation Status: ✅ VERIFIED

### Code Flow Verification

#### 1. Practice → WebSocket (Random Join/Create/Join Room)

**Entry Points:**
- `DutchGameHelpers.joinRandomGame()`
- `lobby_screen.dart._createRoom()`
- `lobby_screen.dart._joinRoom()`

**Cleanup Sequence (in `clearAllGameStateBeforeNewGame()`):**
1. ✅ Cancel leave game timers
2. ✅ **Reset transport mode to WebSocket FIRST** (before leaving rooms)
   - Ensures `leave_room` events route to WebSocket, not practice bridge
3. ✅ Leave current game:
   - WebSocket rooms (`room_*`): Send `leave_room` event via `GameCoordinator.leaveGame()`
   - Practice rooms (`practice_room_*`): Call `PracticeModeBridge.endPracticeSession()`
4. ✅ Leave other games in games map
5. ✅ Clear GameStateStore entries
6. ✅ End practice session (catch-all cleanup)
7. ✅ Clear practice user data and settings
8. ✅ Clear all game state
9. ✅ Clear additional state fields

**After Cleanup:**
- ✅ `lobby_screen.dart` methods explicitly set transport mode to WebSocket
- ✅ `ensureWebSocketReady()` verifies WebSocket connection
- ✅ Events route to WebSocket via `DutchGameEventEmitter.emit()`

**Event Routing:**
```dart
// validated_event_emitter.dart:297-314
if (_transportMode == EventTransportMode.practice) {
  await _practiceBridge.handleEvent(eventType, eventPayload);
} else {
  await _wsManager.sendCustomEvent(eventType, eventPayload); // WebSocket
}
```

#### 2. WebSocket → Practice (Start Practice Match)

**Entry Point:**
- `lobby_screen.dart._startPracticeMatch()`

**Cleanup Sequence (in `clearAllGameStateBeforeNewGame()`):**
1. ✅ Cancel leave game timers
2. ✅ **Reset transport mode to WebSocket FIRST** (before leaving rooms)
   - Ensures `leave_room` events route to WebSocket for any active WebSocket rooms
3. ✅ Leave current game:
   - WebSocket rooms: Send `leave_room` event
   - Practice rooms: End practice session
4. ✅ Leave other games
5. ✅ Clear GameStateStore
6. ✅ End practice session (catch-all)
7. ✅ Clear practice user data and settings
8. ✅ Clear all game state

**After Cleanup:**
- ✅ Generate new practice user data
- ✅ Store practice user and settings in state
- ✅ **Set transport mode to Practice** (`EventTransportMode.practice`)
- ✅ Initialize practice bridge
- ✅ Start practice session

**Event Routing:**
- After transport mode is set to Practice, all events route to `PracticeModeBridge.handleEvent()`

## Key Implementation Details

### Transport Mode Reset Order
**Critical:** Transport mode is reset to WebSocket **BEFORE** leaving rooms. This ensures:
- `leave_room` events for WebSocket rooms route correctly
- No mode conflicts during cleanup
- Clean state for new mode

### Practice Session Cleanup
- `PracticeModeBridge.endPracticeSession()` clears:
  - Current room ID
  - Current session ID
  - Current user ID
  - Disposes game registry
  - Clears game state store
  - Closes room in room manager

### Practice User Data
- Cleared during cleanup: `practiceUser` and `practiceSettings` set to `null`
- Set when starting practice: New practice user generated and stored

## Logging

### Enabled Logging Flags
- ✅ `dutch_game_helpers.dart`: `LOGGING_SWITCH = true` (mode switching verification)
- ✅ `validated_event_emitter.dart`: `LOGGING_SWITCH = true` (mode switching verification)
- ✅ `practice_mode_bridge.dart`: `LOGGING_SWITCH = true` (practice match debugging)

### Expected Log Messages

**Practice → WebSocket:**
```
🧹 DutchGameHelpers: Clearing ALL game state before starting new game
🧹 DutchGameHelpers: Reset transport mode to WebSocket (before leaving rooms)
🧹 DutchGameHelpers: Ended practice session for room: practice_room_XXX
🧹 DutchGameHelpers: Cleared practice user data and settings
✅ DutchGameHelpers: All game state cleared successfully before new game
DutchGameEventEmitter: Transport mode set to websocket
🎯 EventEmitter: Transport mode is websocket for event join_random_game
🎯 EventEmitter: Routing to WebSocket
```

**WebSocket → Practice:**
```
🧹 DutchGameHelpers: Clearing ALL game state before starting new game
🧹 DutchGameHelpers: Reset transport mode to WebSocket (before leaving rooms)
🧹 DutchGameHelpers: Sent leave_room event for WebSocket room: room_XXX
🧹 DutchGameHelpers: Cleared practice user data and settings
✅ DutchGameHelpers: All game state cleared successfully before new game
🎮 _startPracticeMatch: Switched to practice mode
DutchGameEventEmitter: Transport mode set to practice
🎯 EventEmitter: Transport mode is practice for event start_match
🎯 EventEmitter: Routing to PracticeModeBridge
```

## Verification Checklist

### Practice → WebSocket
- [x] Transport mode reset before leaving rooms
- [x] Practice session ended
- [x] Practice user data cleared
- [x] Transport mode set to WebSocket in lobby methods
- [x] Events route to WebSocket
- [x] WebSocket connection verified

### WebSocket → Practice
- [x] Transport mode reset before leaving rooms
- [x] WebSocket rooms left properly
- [x] Practice user data cleared then regenerated
- [x] Transport mode set to Practice
- [x] Practice bridge initialized
- [x] Events route to Practice bridge

## Potential Issues & Mitigations

### Issue: Transport mode not reset before leaving rooms
**Status:** ✅ Fixed
- Transport mode is reset in step 1b, before any room leaving logic

### Issue: Practice session not ended
**Status:** ✅ Fixed
- Practice session ended in step 2a (current game) and step 4 (catch-all)

### Issue: Practice user data persists
**Status:** ✅ Fixed
- Practice user data cleared in step 4a

### Issue: Events route to wrong mode
**Status:** ✅ Fixed
- Transport mode checked in `validated_event_emitter.dart:297`
- Mode set correctly in lobby screen methods

## Testing Recommendations

1. **Practice → Random Join:**
   - Start practice match
   - Play a few turns
   - Click "Play Dutch" (random join)
   - Verify: No errors, WebSocket connection established, events route to WebSocket

2. **Random Join → Practice:**
   - Join/create a WebSocket room
   - Leave or finish game
   - Start practice match
   - Verify: No errors, practice session starts, events route to practice bridge

3. **Practice → Create Room:**
   - Start practice match
   - Create a new room
   - Verify: Practice session ended, WebSocket mode active, room created

4. **Create Room → Practice:**
   - Create a WebSocket room
   - Leave room
   - Start practice match
   - Verify: WebSocket room left, practice session starts

## Frontend vs Backend Cleanup

### ✅ CRITICAL: Frontend-Only Cleanup

**Important:** The cleanup operations in `clearAllGameStateBeforeNewGame()` are **frontend-only**. They only affect the leaving user's local state. Backend games and multiplayer sessions remain active for other players.

#### Frontend Cleanup (User's Local State Only)

**What Gets Cleared:**
1. ✅ **StateManager state** (`dutch_game` module state)
   - `games` map (user's view of games)
   - `currentGameId` (user's current game reference)
   - `playerStatus`, `myScore`, `myHandCards`, etc. (user's personal state)
   - `practiceUser`, `practiceSettings` (user's practice mode data)

2. ✅ **GameStateStore** (practice mode only)
   - Local practice game state (frontend-only, doesn't affect backend)

3. ✅ **Practice Bridge** (practice mode only)
   - Local practice session state (frontend-only)

**What Does NOT Get Cleared:**
- ❌ Backend game state (remains active for other players)
- ❌ Backend game logic (continues running)
- ❌ Other players' games (unaffected)

#### Backend Leave Handling (Multiplayer Only)

**For WebSocket Rooms (`room_*`):**
1. ✅ Frontend sends `leave_room` event via `GameCoordinator.leaveGame()`
2. ✅ Backend receives `leave_room` event in `_onLeaveRoom()` hook
3. ✅ Backend removes player from game state:
   ```dart
   players.removeWhere((p) => p['id'] == sessionId);
   gameState['players'] = players;
   gameState['playerCount'] = newPlayerCount;
   ```
4. ✅ Backend broadcasts updated game state to **all remaining players**
5. ✅ Game continues for other players (game logic unaffected)

**For Practice Rooms (`practice_room_*`):**
- ✅ Frontend-only cleanup (no backend event sent)
- ✅ Practice mode is local to the user, so no other players affected

#### Code Flow Verification

**Frontend Cleanup:**
```dart
// clearAllGameStateBeforeNewGame() - Frontend only
1. Send leave_room event (for WebSocket rooms) → Backend handles
2. Clear StateManager state → Frontend only
3. Clear GameStateStore → Frontend only (practice mode)
4. End practice session → Frontend only
5. clearGameState() → Frontend only
```

**Backend Handling:**
```dart
// _onLeaveRoom() in backend - Affects backend game state
1. Remove player from game state → Backend state updated
2. Broadcast to remaining players → Other players notified
3. Game continues → Other players unaffected
```

### Verification: Other Players Unaffected

✅ **Multiplayer Games:**
- When User A leaves, User B and User C's games continue
- Backend removes User A from game state
- Backend broadcasts updated state to User B and User C
- User B and User C see User A has left
- Game logic continues for remaining players

✅ **Practice Games:**
- Practice mode is local to each user
- No backend interaction, so no other players affected

## Conclusion

✅ **Mode switching is correctly implemented:**
- Cleanup properly handles both modes
- Transport mode reset order is correct
- Practice sessions are properly ended
- Practice user data is cleared and regenerated
- Events route correctly based on transport mode
- Logging enabled for verification

✅ **Frontend-only cleanup verified:**
- Frontend state cleared (user's local view)
- Backend games remain active for other players
- `leave_room` event properly removes player from backend
- Other players' games continue unaffected

The implementation ensures clean state transitions between Practice and WebSocket modes, preventing mode conflicts and stale state issues, while maintaining backend game integrity for other players.
