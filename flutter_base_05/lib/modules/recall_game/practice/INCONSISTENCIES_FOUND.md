# Practice Game Data Structure Inconsistencies

## Issues Found

### 1. ❌ gamePhase Not Normalized

**Location**: `screens/lobby_room/lobby_screen.dart:227`

**Problem**: Practice game stores RAW phase instead of normalized phase.

```dart
// CURRENT (WRONG):
final gamePhase = gameState['phase']?.toString() ?? 'waiting_for_players';
// Stores: 'waiting_for_players' (raw backend phase)

// SHOULD BE (like multiplayer):
final rawPhase = gameState['phase']?.toString();
final uiPhase = rawPhase == 'waiting_for_players'
    ? 'waiting'
    : (rawPhase ?? 'playing');
// Stores: 'waiting' (normalized UI phase)
```

**Reference**: Multiplayer normalizes phase in `recall_event_handler_callbacks.dart:356-359`

---

### 2. ❌ gamePhase Stored in Wrong Location

**Location**: `screens/lobby_room/lobby_screen.dart:237`

**Problem**: Practice game stores `gamePhase` in the `games` map entry, but it should be in the MAIN state.

```dart
// CURRENT (WRONG):
games[practiceRoomId] = {
  'gameData': gameData,
  'gamePhase': gamePhase,  // ❌ Wrong location
  'gameStatus': gameStatus,
  // ...
};

// SHOULD BE (like multiplayer):
// 1. Don't store gamePhase in games map
games[practiceRoomId] = {
  'gameData': gameData,
  // 'gamePhase': removed - not stored here
  'gameStatus': gameStatus,
  // ...
};

// 2. Store normalized gamePhase in MAIN state
RecallGameHelpers.updateUIState({
  'currentGameId': practiceRoomId,
  'games': games,
  'gamePhase': uiPhase,  // ✅ Correct location
  // ...
});
```

**Reference**: 
- Comment in `recall_event_handler_callbacks.dart:88`: `// Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice`
- Multiplayer stores in main state: `recall_event_handler_callbacks.dart:362-367`

---

### 3. ❌ Missing gameInfo Slice Update

**Location**: `screens/lobby_room/lobby_screen.dart:245-252`

**Problem**: Practice game doesn't update `gameInfo` slice with normalized `gamePhase`, which widgets expect.

**Current**: Only updates top-level state:
```dart
RecallGameHelpers.updateUIState({
  'currentGameId': practiceRoomId,
  'currentRoomId': practiceRoomId,
  'isInRoom': true,
  'isRoomOwner': true,
  'gameType': 'practice',
  'games': games,
  // ❌ Missing: 'gamePhase': uiPhase
});
```

**Should also include**:
```dart
RecallGameHelpers.updateUIState({
  'currentGameId': practiceRoomId,
  'currentRoomId': practiceRoomId,
  'isInRoom': true,
  'isRoomOwner': true,
  'gameType': 'practice',
  'games': games,
  'gamePhase': uiPhase,  // ✅ Add normalized phase
});
```

**Reference**: Widgets read from `gameInfo['gamePhase']` (e.g., `game_info_widget.dart:79`)

---

### 4. ⚠️ gameStatus May Be Missing from Initial State

**Location**: `screens/lobby_room/lobby_screen.dart:228`

**Problem**: Initial game state from `GameStateStore.getGameState()` may not have a `status` field.

**Current**:
```dart
final gameStatus = gameState['status']?.toString() ?? 'inactive';
```

**Analysis**: 
- Initial state created in `recall_game_main.dart:61-92` has `isGameActive: false` but no `status` field
- Defaulting to `'inactive'` is probably correct, but inconsistent with how multiplayer handles it
- Multiplayer extracts status from game state updates that come from backend events

**Recommendation**: Verify that initial practice game state should have `status: 'inactive'` explicitly set, or ensure the default is correct.

---

### 5. ⚠️ gameInfo Slice Not Fully Populated

**Location**: `screens/lobby_room/lobby_screen.dart:245-252`

**Problem**: Practice game doesn't populate all `gameInfo` fields that widgets might expect.

**Missing fields**:
- `currentSize`: Number of players currently in room
- `maxSize`: Maximum players allowed
- `isInGame`: Whether user is actively in the game

**Current**: Only sets top-level fields, relies on state updater to compute `gameInfo` slice.

**Reference**: `game_info_widget.dart:74-75` reads `currentSize` and `maxSize` from `gameInfo`.

---

## Summary of Required Fixes

1. ✅ Normalize `gamePhase` from raw backend phase to UI phase
2. ✅ Store `gamePhase` in MAIN state, not in `games` map entry
3. ✅ Update `gameInfo` slice with normalized `gamePhase`
4. ⚠️ Verify `gameStatus` handling matches multiplayer behavior
5. ⚠️ Ensure `gameInfo` slice has all required fields (`currentSize`, `maxSize`, `isInGame`)

---

## Corrected Practice Game Setup

```dart
// Get game state from GameStateStore
final gameStateStore = GameStateStore.instance;
final gameState = gameStateStore.getGameState(practiceRoomId);

// Create gameData structure matching multiplayer format
final gameData = {
  'game_id': practiceRoomId,
  'owner_id': currentUserId,
  'game_type': 'practice',
  'game_state': gameState,
  'max_size': maxPlayersValue,
  'min_players': minPlayersValue,
};

// Extract and normalize phase (like multiplayer)
final rawPhase = gameState['phase']?.toString();
final uiPhase = rawPhase == 'waiting_for_players'
    ? 'waiting'
    : (rawPhase ?? 'playing');

// Extract game status
final gameStatus = gameState['status']?.toString() ?? 'inactive';

// Get current games map
final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});

// Add/update the current game in the games map (matching multiplayer format)
games[practiceRoomId] = {
  'gameData': gameData,  // Single source of truth
  // ❌ REMOVED: 'gamePhase': gamePhase,  // Not stored here anymore
  'gameStatus': gameStatus,
  'isRoomOwner': true,
  'isInGame': true,
  'joinedAt': DateTime.now().toIso8601String(),
};

// Update UI state to reflect practice game (matching multiplayer format)
RecallGameHelpers.updateUIState({
  'currentGameId': practiceRoomId,
  'currentRoomId': practiceRoomId,
  'isInRoom': true,
  'isRoomOwner': true,
  'gameType': 'practice',
  'games': games,
  'gamePhase': uiPhase,  // ✅ Store normalized phase in MAIN state
  // ✅ Optional: Add gameInfo fields if needed
  // 'currentSize': 1,
  // 'maxSize': maxPlayersValue,
  // 'isInGame': true,
});
```

