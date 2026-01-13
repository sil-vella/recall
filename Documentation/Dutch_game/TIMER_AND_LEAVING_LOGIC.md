# Timer and Game Leaving Logic Documentation

## Overview

This document describes the complete timer system and game leaving logic in the Dutch game. It covers all scenarios including user-initiated leaves, app closures, auto-leave on missed actions, and the differences between practice and multiplayer modes.

---

## Table of Contents

1. [Timer System](#timer-system)
2. [Game Leaving Scenarios](#game-leaving-scenarios)
3. [Flow Diagrams](#flow-diagrams)
4. [Implementation Details](#implementation-details)

## Related Documentation

- **[Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)** - Complete documentation of the phase-based timer configuration system, timer value declaration, and priority logic

---

## Timer System

### Timer Types

The Dutch game uses several types of timers to manage game flow and player actions:

#### 1. Draw Action Timer
- **Purpose**: Limits time for a player to draw a card
- **Duration**: Determined by `getTimerConfig()` based on status `drawing_card` (current: 10 seconds)
- **Location**: `DutchGameRound._drawActionTimer`
- **Configuration**: See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)
- **When Started**: 
  - When a player's turn begins (status changes to `drawing_card`)
  - After `handleDrawCard()` completes successfully
- **When Cancelled**:
  - When player successfully draws a card
  - When player successfully plays a card
  - When moving to next player
  - When timer expires
- **On Expiry**:
  1. Cancel play timer (if active)
  2. Move to next player (`_moveToNextPlayer()`)
  3. Increment missed action counter for the player
  4. If counter reaches 2, trigger auto-leave

#### 2. Play Action Timer
- **Purpose**: Limits time for a player to play a card after drawing
- **Duration**: Determined by `getTimerConfig()` based on status `playing_card` (current: 30 seconds)
- **Location**: `DutchGameRound._playActionTimer`
- **Configuration**: See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)
- **When Started**: 
  - After player successfully draws a card (status changes to `playing_card`)
- **When Cancelled**:
  - When player successfully plays a card
  - When draw timer expires
  - When moving to next player
  - When timer expires
- **On Expiry**:
  1. Cancel draw timer (if active)
  2. Clear `drawnCard` property (card remains in player's hand)
  3. Update player status to `waiting`
  4. Sanitize all players' `drawnCard` data
  5. Broadcast state update
  6. Move to next player (`_moveToNextPlayer()`)
  7. Increment missed action counter for the player
  8. If counter reaches 2, trigger auto-leave

#### 3. Same Rank Timer
- **Purpose**: Provides a window for other players to play matching rank cards
- **Duration**: Determined by `getTimerConfig()` based on phase `same_rank_window` or status `same_rank_window` (current: 10 seconds)
- **Location**: `DutchGameRound._sameRankTimer`
- **Configuration**: See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)
- **When Started**: 
  - When a card is played and triggers same rank window
- **When Cancelled**:
  - When window closes (timer expires)
  - When moving to next player
  - When special card window opens
- **On Expiry**: Closes same rank window and proceeds to special card window or next player

#### 4. Special Card Timer
- **Purpose**: Provides time for special card actions (Queen peek, Jack swap)
- **Duration**: Determined by `getTimerConfig()` based on status `queen_peek` (15s) or `jack_swap` (20s)
- **Location**: `DutchGameRound._specialCardTimer`
- **Configuration**: See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)
- **When Started**: 
  - When a special card (Queen/Jack) is played
- **When Cancelled**:
  - When special card action is completed
  - When timer expires
  - When moving to next player
- **On Expiry**: Resets player status and moves to next player

#### 5. Initial Peek Timer
- **Purpose**: Limits time for players to peek at initial cards before game starts
- **Duration**: Determined by `game_state['timerConfig']['initial_peek']` (current: 15 seconds)
- **Location**: `GameEventCoordinator._initialPeekTimers` (per room)
- **Configuration**: See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md)
- **When Started**: 
  - When match starts and game enters `initial_peek` phase
- **When Cancelled**:
  - When all players complete initial peek
  - When timer expires
- **On Expiry**: Auto-completes peek for remaining players and starts the game

### Timer Configuration

The timer system uses **phase-based configuration** where timer durations are determined by game phase and player status. See [Phase-Based Timer System](./PHASE_BASED_TIMER_SYSTEM.md) for complete details.

**Key Points**:
- Timer values are declared in `game_registry.dart` switch cases
- Status is checked before phase (status is more specific)
- `timerConfig` is added to `game_state` during initialization for UI consumption
- Timer values can be modified in `game_registry.dart` switch cases

**Timer Disabling**:
Timers can be disabled when instructions are shown:
- **Condition**: `showInstructions == true` (typically in practice mode)
- **Behavior**: All action timers (draw/play) are disabled
- **Location**: `DutchGameRound._shouldStartTimer()`
- **Note**: Same rank, special card, and initial peek timers are not affected

### Missed Action Counter

- **Purpose**: Tracks missed draw/play actions per player for auto-leave functionality
- **Location**: `DutchGameRound._missedActionCounts` (Map<String, int>)
- **Incremented**: When draw or play timer expires
- **Reset**: When player successfully completes a draw or play action
- **Threshold**: 2 missed actions triggers auto-leave (multiplayer only)
- **Scope**: Per-player, per-game round instance

---

## Game Leaving Scenarios

### Scenario 1: User Leaves Play Screen (Intentional Leave)

**Trigger**: User navigates away from game play screen or clicks leave button

**Flow**:
1. **Flutter Side** (`GameCoordinator.startLeaveGameTimer()`):
   - Starts 30-second grace period timer
   - User can return to game within 30 seconds to cancel
   - Timer survives widget disposal (managed in GameCoordinator)

2. **After 30 Seconds** (`GameCoordinator._executeLeaveGame()`):
   - **Multiplayer Games** (`room_*`):
     - Sends `leave_room` event to backend via WebSocket
     - Backend processes leave through `leave_room` hook
   - **Practice Games** (`practice_room_*`):
     - Only clears local state (no backend event)
     - Practice bridge handles its own cleanup
   - Clears game state from StateManager
   - Removes player from games map

3. **Backend Processing** (`DutchGameModule._onLeaveRoom()`):
   - Removes player from game state players list
   - Updates player count
   - Broadcasts `game_state_updated` to all remaining players
   - **Note**: If player was current player, game has already progressed (via timer expiry or normal flow)

**Files**:
- `flutter_base_05/lib/modules/cleco_game/managers/game_coordinator.dart`
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/cleco_game_main.dart`
- `dart_bkend_base_01/lib/server/message_handler.dart`

### Scenario 2: App Closure / WebSocket Disconnect

**Trigger**: User closes app, loses network connection, or WebSocket disconnects

**Flow**:
1. **WebSocket Disconnect** (`WebSocketServer._onDisconnect()`):
   - Detects connection loss
   - Cleans up session data (connections, authentication)
   - Calls `RoomManager.handleDisconnect()`

2. **Room Manager** (`RoomManager.handleDisconnect()`):
   - Calls `leaveRoom()` to remove session from room
   - If room becomes empty, triggers `room_closed` hook
   - **Note**: Does NOT trigger `leave_room` hook automatically

3. **Room Cleanup** (`DutchGameModule._onRoomClosed()`):
   - Disposes `DutchGameRound` instance
   - Clears game state from `GameStateStore`
   - All timers are cancelled when `DutchGameRound.dispose()` is called

**Important**: 
- Disconnect does NOT trigger `leave_room` hook (only `room_closed` if room becomes empty)
- Player is removed from room but game state may not be updated if disconnect happens silently
- Other players may not immediately see the disconnect until next game state update

**Files**:
- `dart_bkend_base_01/lib/server/websocket_server.dart`
- `dart_bkend_base_01/lib/server/room_manager.dart`
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/cleco_game_main.dart`

### Scenario 3: Auto-Leave on Missed Actions

**Trigger**: Player misses 2 actions (draw or play timer expires twice)

**Flow**:
1. **Timer Expiry** (`DutchGameRound._onDrawActionTimerExpired()` or `_onPlayActionTimerExpired()`):
   - Move to next player first (normal game flow)
   - Increment missed action counter
   - If counter reaches 2, call `_onMissedActionThresholdReached()`

2. **Threshold Reached** (`DutchGameRound._onMissedActionThresholdReached()`):
   - Calls `_stateCallback.triggerLeaveRoom(playerId)`

3. **GameStateCallback** (`ServerGameStateCallbackImpl.triggerLeaveRoom()`):
   - **Multiplayer Only**: Checks if room is `room_*` (not `practice_room_*`)
   - Triggers `leave_room` hook via `server.triggerHook()`
   - Practice games are skipped (no auto-leave)

4. **Leave Room Hook** (`DutchGameModule._onLeaveRoom()`):
   - Removes player from game state
   - Broadcasts update to remaining players
   - **Note**: Game has already progressed to next player before auto-leave

**Key Points**:
- Only applies to multiplayer matches (`room_*`)
- Practice matches (`practice_room_*`) are excluded
- Counter resets to 0 when player successfully completes an action
- Counter is per-player, stored in game round instance

**Files**:
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart`
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/services/game_registry.dart`
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/cleco_game_main.dart`

### Scenario 4: Room Closure (Empty Room / TTL Expiry)

**Trigger**: Room becomes empty or TTL expires

**Flow**:
1. **Room Manager** (`RoomManager.closeRoom()` or `leaveRoom()`):
   - Detects empty room or TTL expiry
   - Triggers `room_closed` hook

2. **Room Closed Hook** (`DutchGameModule._onRoomClosed()`):
   - Disposes `DutchGameRound` instance (cancels all timers)
   - Clears game state from `GameStateStore`
   - All game data is removed

**Files**:
- `dart_bkend_base_01/lib/server/room_manager.dart`
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/cleco_game_main.dart`

---

## Flow Diagrams

### Timer Expiry Flow (Draw/Play Action)

```
Timer Expires
    ↓
Cancel opposite timer (if active)
    ↓
[Play Timer Only] Clear drawnCard, sanitize, broadcast
    ↓
Move to Next Player (_moveToNextPlayer())
    ↓
Increment Missed Action Counter
    ↓
Counter == 2?
    ├─ Yes → Trigger Auto-Leave (multiplayer only)
    └─ No → Continue game
```

### Auto-Leave Flow

```
Missed Action Counter Reaches 2
    ↓
_onMissedActionThresholdReached(playerId)
    ↓
_stateCallback.triggerLeaveRoom(playerId)
    ↓
Check: Is multiplayer? (room_*)
    ├─ Yes → Trigger leave_room hook
    └─ No (practice_room_*) → Skip (no action)
    ↓
_onLeaveRoom() Hook Handler
    ↓
Remove player from game state
    ↓
Broadcast game_state_updated to remaining players
```

### User-Initiated Leave Flow

```
User Leaves Play Screen
    ↓
GameCoordinator.startLeaveGameTimer()
    ↓
30-Second Grace Period
    ├─ User Returns → Cancel timer, continue game
    └─ Timer Expires → Execute leave
    ↓
_executeLeaveGame()
    ↓
Check Game Type:
    ├─ Multiplayer (room_*) → Send leave_room event
    └─ Practice (practice_room_*) → Clear local state only
    ↓
Clear StateManager game data
    ↓
[Multiplayer Only] Backend processes leave_room hook
```

### WebSocket Disconnect Flow

```
WebSocket Disconnects
    ↓
WebSocketServer._onDisconnect()
    ↓
Clean up session data
    ↓
RoomManager.handleDisconnect()
    ↓
RoomManager.leaveRoom()
    ↓
Remove session from room
    ↓
Room Empty?
    ├─ Yes → Trigger room_closed hook
    └─ No → Continue (other players remain)
    ↓
[If room_closed] Dispose game round, clear state
```

---

## Implementation Details

### Timer Management

All timers in `DutchGameRound` are cancelled when:
- `_cancelActionTimers()` is called (draw/play timers)
- `dispose()` is called (all timers)
- Moving to next player
- Successful action completion

**Timer Lifecycle**:
```dart
// Start timer
_drawActionTimer = Timer(Duration(seconds: turnTimeLimit), () {
  _onDrawActionTimerExpired(playerId);
});

// Cancel timer
_drawActionTimer?.cancel();
_drawActionTimer = null;
```

### Missed Action Counter Management

**Storage**: `Map<String, int> _missedActionCounts` in `DutchGameRound`

**Operations**:
- **Increment**: `_missedActionCounts[playerId] = (_missedActionCounts[playerId] ?? 0) + 1`
- **Reset**: `_missedActionCounts[playerId] = 0`
- **Check**: `if (_missedActionCounts[playerId] == 2)`

**Scope**: 
- Per-game round instance
- Lost when game round is disposed
- Not persisted across game restarts

### Leave Room Hook Data Structure

```dart
{
  'room_id': roomId,
  'session_id': sessionId,  // Player ID (sessionId = playerId in this system)
  'user_id': userId,
  'left_at': DateTime.now().toIso8601String(),
}
```

### Practice vs Multiplayer Differences

| Feature | Multiplayer (`room_*`) | Practice (`practice_room_*`) |
|---------|----------------------|---------------------------|
| Auto-leave on missed actions | ✅ Yes (2 missed actions) | ❌ No |
| Leave room hook triggered | ✅ Yes | ❌ No |
| Backend cleanup | ✅ Full cleanup | ⚠️ Local only |
| Game state persistence | ✅ Shared state | ⚠️ Local state |
| WebSocket events | ✅ Yes | ⚠️ Stub implementation |

### State Cleanup

**When Player Leaves**:
1. Player removed from `gameState['players']` list
2. `playerCount` updated
3. Game state broadcasted to remaining players
4. If room becomes empty, `room_closed` hook triggered

**When Room Closes**:
1. `DutchGameRound.dispose()` called (cancels all timers)
2. Game state cleared from `GameStateStore`
3. Game round instance removed from `GameRegistry`

### Edge Cases and Considerations

1. **Player Leaves During Their Turn**:
   - If current player leaves, game has already progressed (via timer or normal flow)
   - Leave room handler doesn't need special turn progression logic

2. **Multiple Disconnects**:
   - Each disconnect is handled independently
   - Room closes only when last player leaves

3. **Timer Expiry After Leave**:
   - Timers are cancelled when player leaves
   - No action needed if timer expires after leave

4. **Practice Mode**:
   - No auto-leave functionality
   - No backend leave_room hook
   - Cleanup handled by practice bridge

5. **Player Still Receives Updates After Leave**:
   - **Issue**: Players who leave may still receive game state updates (they remain subscribed to room broadcasts)
   - **Impact**: Player can see game progressing but cannot act
   - **Solution**: Backend validation needed to reject actions from players not in game (see Master Plan TODO)

---

## Related Files

### Backend (Dart)
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart` - Timer logic and missed action counter
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/cleco_game_main.dart` - Leave room and room closed hooks
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/services/game_registry.dart` - GameStateCallback implementation
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart` - Initial peek timer
- `dart_bkend_base_01/lib/server/websocket_server.dart` - WebSocket disconnect handling
- `dart_bkend_base_01/lib/server/room_manager.dart` - Room management and cleanup
- `dart_bkend_base_01/lib/server/message_handler.dart` - Leave room event handling

### Frontend (Flutter)
- `flutter_base_05/lib/modules/cleco_game/managers/game_coordinator.dart` - Leave game timer and execution
- `flutter_base_05/lib/modules/cleco_game/utils/cleco_game_helpers.dart` - State cleanup helpers
- `flutter_base_05/lib/modules/cleco_game/screens/game_play/game_play_screen.dart` - Screen lifecycle

---

## Future Improvements

1. **Player Action Validation**: Validate player is still in game before processing actions (see Master Plan)
2. **Disconnect Detection**: Improve handling of silent disconnects
3. **Timer Persistence**: Consider persisting timer state for recovery scenarios
4. **Graceful Degradation**: Handle partial disconnects more gracefully

---

**Last Updated**: 2025-01-XX
