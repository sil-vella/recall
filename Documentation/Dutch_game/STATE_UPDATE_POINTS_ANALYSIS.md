# State Update Points Analysis - Dutch Game

## Overview

This document catalogs **every instance** of frontend state updating during Dutch game play and identifies all **Single Source of Truth (SSOT)** points that game logic should use.

**Last Updated**: 2025-01-XX

---

## Single Source of Truth (SSOT) Points

### Primary SSOT: `games[gameId].gameData.game_state`

**Location**: `StateManager['dutch_game']['games'][gameId]['gameData']['game_state']`

**Description**: This is the **authoritative source** for all game data. It comes directly from the backend via `game_state_updated` events.

**Structure**:
```dart
{
  'phase': String,              // 'waiting_for_players' | 'initial_peek' | 'playing' | 'game_ended'
  'status': String,              // 'active' | 'paused' | 'ended'
  'gameType': String,            // 'normal' | 'practice'
  'roundNumber': int,
  'turnNumber': int,
  'isClearAndCollect': bool,     // Game mode flag
  'players': List<Player>,       // All players with full data for current user, ID-only for others
  'currentPlayer': Player,       // Player whose turn it is
  'drawPile': List<Card>,        // ID-only cards
  'discardPile': List<Card>,     // Full card data
  'originalDeck': List<Card>,   // Full card data for lookups
  'timerConfig': Map<String, int>, // Phase-based timer configuration
  'finalRoundActive': bool,
  'finalRoundCalledBy': String?,
  'winners': List<Player>?,
  // ... other game state fields
}
```

**Key Principle**: All game logic should read from this SSOT. Derived state (widget slices, computed fields) should be computed from this SSOT, never stored separately.

**Access Pattern**:
```dart
final games = state['games'] as Map<String, dynamic>? ?? {};
final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
// gameState is the SSOT
```

---

## State Update Flow Architecture

### Update Path Hierarchy

```
1. Backend game_state (SSOT)
   ↓
2. Event Received (WebSocket/Practice)
   ↓
3. DutchEventHandlerCallbacks.handleGameStateUpdated()
   ↓
4. _syncWidgetStatesFromGameState() - Extract widget data from SSOT
   ↓
5. _updateMainGameState() / _updateGameInMap() / _updateGameData()
   ↓
6. DutchGameHelpers.updateUIState()
   ↓
7. DutchGameStateUpdater.updateState()
   ↓
8. StateQueueValidator.validateUpdate() & enqueue
   ↓
9. DutchGameStateUpdater._applyValidatedUpdates()
   ↓
10. _updateWidgetSlices() - Recompute slices from SSOT
    ↓
11. StateManager.updateModuleState('dutch_game', newState)
    ↓
12. StateManager.notifyListeners()
    ↓
13. Widgets rebuild
```

---

## All Frontend State Update Points

### Category 1: Event Handler Updates (Primary Path)

**File**: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart`

These are the **primary** state update points that process backend events and update state from SSOT.

#### 1.1 `handleGameStateUpdated()` - Main Event Handler
- **Line**: ~586-1292
- **Purpose**: Processes `game_state_updated` events from backend
- **Updates**:
  - `games[gameId].gameData.game_state` (SSOT update)
  - `games[gameId].myHandCards` (derived from SSOT)
  - `games[gameId].myDrawnCard` (derived from SSOT)
  - `games[gameId].isMyTurn` (derived from SSOT)
  - `currentGameId`
  - `gamePhase` (normalized from SSOT)
  - `isGameActive`
  - `roundNumber`, `turnNumber`
  - `currentPlayer`, `currentPlayerStatus` (from SSOT)
  - `discardPile` (from SSOT)
  - `turn_events`
  - `playerStatus` (derived from SSOT)
- **SSOT Source**: `data['game_state']` from event
- **Method**: `_updateMainGameState()`, `_updateGameInMap()`, `_syncWidgetStatesFromGameState()`

#### 1.2 `handleGameStatePartialUpdate()` - Partial Updates
- **Line**: ~1410-1500
- **Purpose**: Processes `game_state_partial_update` events
- **Updates**:
  - Merges partial updates into existing `game_state` (SSOT)
  - Updates specific fields based on `changed_properties`
  - `gamePhase`, `currentPlayer`, `drawPileCount`, `discardPile`, etc.
- **SSOT Source**: Merged `partial_game_state` from event
- **Method**: `_updateGameData()`, `_updateMainGameState()`

#### 1.3 `handlePlayerStateUpdated()` - Player-Specific Updates
- **Line**: ~1612-1660
- **Purpose**: Processes `player_state_updated` events
- **Updates**:
  - `playerStatus`, `myScore`, `isMyTurn` (for current user)
  - `myHandCards`, `myDrawnCard`, `myCardsToPeek`
- **SSOT Source**: `data['player_data']` from event
- **Method**: `_updateMainGameState()`, `_updateGameInMap()`

#### 1.4 `handleGameStarted()` - Game Start Event
- **Line**: ~828-1000
- **Purpose**: Processes `game_started` events
- **Updates**:
  - `games[gameId].gameData.game_state` (SSOT)
  - `gamePhase`, `isGameActive`
  - Widget-specific data
- **SSOT Source**: `data['game_state']` from event
- **Method**: `_updateMainGameState()`, `_syncWidgetStatesFromGameState()`

#### 1.5 `handleDutchNewPlayerJoined()` - Player Join Event
- **Line**: ~1006-1150
- **Purpose**: Processes `cleco_new_player_joined` events
- **Updates**:
  - `games[gameId].gameData.game_state.players` (SSOT)
  - `playerCount`
  - `isRoomOwner` (if owner changed)
- **SSOT Source**: `data['game_state']` from event
- **Method**: `_updateGameData()`, `_updateMainGameState()`

#### 1.6 `handleDutchJoinedGames()` - Joined Games List
- **Line**: ~1152-1300
- **Purpose**: Processes `cleco_joined_games` events
- **Updates**:
  - `joinedGames` (list of games user has joined)
  - `totalJoinedGames`
  - `joinedGamesTimestamp`
- **SSOT Source**: `data['games']` from event
- **Method**: `_updateMainGameState()`

#### 1.7 Helper Methods (Internal)
- **`_updateMainGameState()`** (Line ~220): Wrapper for `DutchGameHelpers.updateUIState()`
- **`_updateGameInMap()`** (Line ~60): Updates specific game in games map
- **`_updateGameData()`** (Line ~81): Updates gameData structure
- **`_syncWidgetStatesFromGameState()`** (Line ~586): Extracts widget data from SSOT

### Category 2: State Updater (Core Infrastructure)

**File**: `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart`

These are the **core infrastructure** methods that apply validated updates.

#### 2.1 `updateState()` - Async Validated Updates
- **Line**: ~76-86
- **Purpose**: Main entry point for state updates (async, validated)
- **Updates**: Any state fields (validated by StateQueueValidator)
- **Method**: `_validator.enqueueUpdate()`

#### 2.2 `updateStateSync()` - Synchronous Updates
- **Line**: ~92-114
- **Purpose**: Synchronous updates for critical flags
- **Updates**: Critical flags (e.g., `isRandomJoinInProgress`)
- **Direct Call**: `StateManager.updateModuleState()` (Line 107)

#### 2.3 `updateStateImmutable()` - Immutable State Updates
- **Line**: ~118-126
- **Purpose**: Updates using immutable DutchGameState object
- **Updates**: Full state replacement
- **Direct Call**: `StateManager.updateModuleState()` (Line 121)

#### 2.4 `_applyValidatedUpdates()` - Apply Validated Updates
- **Line**: ~150-245
- **Purpose**: Applies validated updates and recomputes widget slices
- **Updates**: Merges validated updates, recomputes slices
- **Direct Call**: `StateManager.updateModuleState()` (Line 238)

#### 2.5 `_updateWidgetSlices()` - Recompute Widget Slices
- **Line**: ~269-332
- **Purpose**: Recomputes widget slices from SSOT based on changed fields
- **Updates**: Widget slices (`myHand`, `centerBoard`, `opponentsPanel`, etc.)
- **SSOT Source**: Reads from `games[gameId].gameData.game_state` (SSOT)
- **Method**: Computes slices, extracts `currentPlayer` from SSOT

### Category 3: Helper Methods (Convenience Wrappers)

**File**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`

#### 3.1 `updateUIState()` - Main Helper
- **Line**: ~232-248
- **Purpose**: Convenience wrapper for `DutchGameStateUpdater.updateState()`
- **Updates**: Any state fields
- **Method**: `DutchGameStateUpdater.instance.updateState()`

### Category 4: Widget-Level Direct Updates (Should Be Minimized)

These are **direct** calls to `StateManager.updateModuleState()` that bypass the validation system. These should be minimized and ideally refactored to use the proper update path.

#### 4.1 `unified_game_board_widget.dart`
- **Line 1342**: Updates `selectedCardIndex` in game
- **Line 1917**: Updates `actionError` state
- **Line 2459**: Updates `selectedCardIndex` to -1
- **Line 2549**: Updates `actionError` state
- **Issue**: These bypass validation. Should use `DutchGameHelpers.updateUIState()`

#### 4.2 `game_play_screen.dart`
- **Line 502**: Updates `actionError` state
- **Issue**: Should use `DutchGameHelpers.updateUIState()`

#### 4.3 `instructions_widget.dart`
- **Line 284**: Updates `instructions.isVisible` to false
- **Line 336**: Updates `instructions.dontShowAgain` map
- **Purpose**: UI-only state (instructions visibility)
- **Acceptable**: Instructions are UI-only, not game logic

#### 4.4 `messages_widget.dart`
- **Line 226**: Updates `messages.isVisible` to false
- **Purpose**: UI-only state (message modal visibility)
- **Acceptable**: Messages are UI-only, not game logic

#### 4.5 `dutch_event_handler_callbacks.dart` (Direct Updates)
- **Line 255**: Updates `instructions.isVisible` to false (instructions disabled)
- **Line 313**: Updates `instructions` (initial instructions)
- **Line 376**: Updates `sameRankTriggerCount` (transitioning into same_rank_window)
- **Line 418**: Updates `instructions` (collection card instruction)
- **Line 477**: Updates `instructions` (status-based instructions)
- **Line 562**: Updates `instructions.isVisible` to false
- **Line 572**: Updates `instructions.dontShowAgain` map
- **Line 1238**: Updates `sameRankTriggerCount` (same_rank_window transition)
- **Line 1923**: Updates `instructions` (game end instructions)
- **Purpose**: Instructions and counter updates
- **Acceptable**: Instructions are UI-only, counter is tracking state

#### 4.6 `lobby_screen.dart`
- **Line 335**: Updates `practiceSettings` state
- **Purpose**: Practice mode settings
- **Acceptable**: Settings are configuration, not game logic

#### 4.7 `demo_action_handler.dart`
- **Line 365**: Updates demo game state
- **Line 872**: Updates demo game state
- **Purpose**: Demo mode state
- **Acceptable**: Demo mode is separate from real game logic

### Category 5: Event Manager Updates

**File**: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_manager.dart`

#### 5.1 Connection State Updates
- **Line 173**: Updates `isConnected` to false (disconnect)
- **Line 198**: Updates `isConnected` to true (connect)
- **Line 215**: Updates `isConnected` to false (error)
- **Line 235**: Updates `isConnected` to false (close)
- **Line 282**: Updates `isConnected` to false (timeout)
- **Line 300**: Updates `isConnected` to false (error)
- **Line 329**: Updates `isConnected` to false (error)
- **Line 377**: Updates `isConnected` to false (error)
- **Purpose**: WebSocket connection status
- **Method**: `DutchGameHelpers.updateUIState()`
- **Acceptable**: Connection state is infrastructure, not game logic

---

## SSOT Access Patterns

### ✅ Correct: Reading from SSOT

```dart
// Get current game state from SSOT
final games = state['games'] as Map<String, dynamic>? ?? {};
final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};

// Read from SSOT
final players = gameState['players'] as List<dynamic>? ?? [];
final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
final phase = gameState['phase']?.toString();
final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
```

### ✅ Correct: Computing Derived State from SSOT

```dart
// In _syncWidgetStatesFromGameState()
final myPlayer = players.firstWhere(
  (player) => player['id'] == currentUserId
);
final hand = myPlayer['hand'] as List<dynamic>? ?? [];
final drawnCard = myPlayer['drawnCard'] as Map<String, dynamic>?;
final status = myPlayer['status']?.toString() ?? 'unknown';

// Update derived state (not SSOT)
_updateGameInMap(gameId, {
  'myHandCards': hand,  // Derived from SSOT
  'myDrawnCard': drawnCard,  // Derived from SSOT
  'isMyTurn': isCurrentPlayer,  // Derived from SSOT
});
```

### ✅ Correct: Widget Slices Computed from SSOT

```dart
// In _computeMyHandSlice()
final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
final players = gameState['players'] as List<dynamic>? ?? [];

// Find current user's player in SSOT
final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
for (final player in players) {
  if (player['id']?.toString() == currentUserId) {
    final playerStatus = player['status']?.toString() ?? 'unknown';
    // Use playerStatus from SSOT
  }
}
```

### ❌ Incorrect: Storing Game Logic State Separately

```dart
// DON'T DO THIS - Game logic should come from SSOT
StateManager().updateModuleState('dutch_game', {
  'playerStatus': 'playing_card',  // Should come from SSOT
  'currentPlayer': {...},  // Should come from SSOT
  'gamePhase': 'playing',  // Should come from SSOT
});
```

### ❌ Incorrect: Bypassing Validation for Game Logic

```dart
// DON'T DO THIS - Should use DutchGameHelpers.updateUIState()
StateManager().updateModuleState('dutch_game', {
  'games': {...},  // Should go through validation
});
```

---

## Recommendations

### 1. Minimize Direct StateManager Calls

**Current Issue**: Some widgets directly call `StateManager.updateModuleState()` for game logic updates.

**Recommendation**: 
- Refactor widget-level updates to use `DutchGameHelpers.updateUIState()`
- Only allow direct calls for UI-only state (instructions, messages visibility)

### 2. Always Read from SSOT

**Current Issue**: Some code may be reading from derived state instead of SSOT.

**Recommendation**:
- All game logic should read from `games[gameId].gameData.game_state` (SSOT)
- Derived state (`myHandCards`, `myDrawnCard`) should only be used for UI display
- Widget slices should compute from SSOT, not store separate state

### 3. Centralize State Updates

**Current Issue**: State updates are scattered across multiple files.

**Recommendation**:
- All game logic state updates should go through `DutchEventHandlerCallbacks`
- Widget-level updates should use `DutchGameHelpers.updateUIState()`
- Only UI-only state (instructions, messages) can bypass validation

### 4. Document SSOT Access

**Recommendation**:
- Add comments in code indicating SSOT access
- Use helper methods like `DutchGameStateAccessor` for SSOT access
- Create utility methods for common SSOT reads

---

## Summary

### SSOT Points (1)
1. **`games[gameId].gameData.game_state`** - Primary SSOT for all game data

### State Update Points (5 Categories)
1. **Event Handler Updates** (7 methods) - Primary path, updates from backend events
2. **State Updater** (5 methods) - Core infrastructure, applies validated updates
3. **Helper Methods** (1 method) - Convenience wrappers
4. **Widget-Level Direct Updates** (15+ instances) - Should be minimized
5. **Event Manager Updates** (8 instances) - Connection state only

### Key Principles
- ✅ All game logic should read from SSOT
- ✅ All game logic updates should come from backend events
- ✅ Widget slices should compute from SSOT
- ✅ Only UI-only state can bypass validation
- ❌ Don't store game logic state separately from SSOT
- ❌ Don't bypass validation for game logic updates

---

**Related Documentation**:
- `STATE_MANAGEMENT.md` - Complete state management architecture
- `PHASE_BASED_TIMER_SYSTEM.md` - Timer system documentation
- `PLAYER_ACTIONS_FLOW.md` - Player action flow documentation
