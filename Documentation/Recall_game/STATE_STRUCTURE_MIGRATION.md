# Recall Game State Structure Migration Plan

## Current Situation: Dual Structure Problem

The Recall game state system currently uses a **dual structure** approach that creates unnecessary complexity and potential bugs. This document explains the current state, why it's problematic, and how to migrate to a simpler, unified structure.

## The Two Structures

### 1. Storage Structure (Flattened) - What Widgets Read

**Location:** Stored in `StateManager` under `recall_game` module state

```dart
games[gameId] = {
  // All game_state fields directly here (flattened)
  'players': [...],
  'drawPile': [...],
  'discardPile': [...],
  'currentPlayer': {...},
  'gamePhase': 'playing',
  'gameId': '...',
  'gameName': '...',
  // ... all other game_state fields
  
  // UI-specific fields also at top level
  'myHandCards': [...],
  'selectedCardIndex': -1,
  'isMyTurn': true,
  'canPlayCard': false,
  'gameStatus': 'active',
  'isRoomOwner': true,
  'isInGame': true,
  'joinedAt': '...',
  'myDrawnCard': null,
  'owner_id': '...',
  'game_id': '...',
}
```

**Who Uses It:**
- All widgets (`MyHandWidget`, `OpponentsPanelWidget`, `DrawPileWidget`, etc.)
- State storage in `StateManager`
- WebSocket event handlers (after flattening)

### 2. Handler Structure (Nested) - What Handlers Expect

**Location:** Created on-the-fly by `_getCurrentGamesMap()`

```dart
games[gameId] = {
  'gameData': {
    'game_id': '...',
    'game_state': {
      // All game_state fields nested here
      'players': [...],
      'drawPile': [...],
      'discardPile': [...],
      'currentPlayer': {...},
      'gamePhase': 'playing',
      // ... all other game_state fields
    },
    'owner_id': '...',
  },
  // UI-specific fields at top level
  'myHandCards': [...],
  'selectedCardIndex': -1,
  'isMyTurn': true,
  'canPlayCard': false,
  'gameStatus': 'active',
  'isRoomOwner': true,
  'isInGame': true,
  'joinedAt': '...',
  'myDrawnCard': null,
}
```

**Who Uses It:**
- All handlers in `recall_game_round.dart` (`handleDrawCard`, `handlePlayCard`, etc.)
- `_getCurrentGameState()` method
- Any code that accesses `currentGamesMap`

## The Conversion Layer

### Flattening: Nested → Flattened (Storage)

**Where It Happens:**
1. `onGameStateChanged()` in `practice_game.dart` (lines 2409-2457)
2. `updatePracticeGameState()` in `practice_game.dart` (lines 400-453)

**What It Does:**
- Takes nested structure from handlers
- Extracts `game_state` from `gameData.game_state`
- Merges all `game_state` fields directly into `games[gameId]`
- Preserves UI-specific fields at top level
- Stores flattened structure in state

**Code Pattern:**
```dart
// Extract game_state from nested structure
final gameDataInner = gameData['gameData'] as Map<String, dynamic>?;
final gameState = gameDataInner?['game_state'] as Map<String, dynamic>? ?? {};

// Flatten: merge game_state fields directly into games[gameId]
final flattenedGame = <String, dynamic>{
  ...gameState, // All game_state fields (players, drawPile, discardPile, etc.)
  // Preserve UI-specific fields that are already at top level
  if (gameData.containsKey('myHandCards')) 'myHandCards': gameData['myHandCards'],
  // ... other UI fields
};
```

### Reconverting: Flattened → Nested (For Handlers)

**Where It Happens:**
- `_getCurrentGamesMap()` in `practice_game.dart` (lines 1029-1088)

**What It Does:**
- Reads flattened structure from state
- Extracts UI-specific fields (myHandCards, selectedCardIndex, etc.)
- Puts remaining fields into `gameData.game_state`
- Reconstructs nested structure
- Returns nested structure for handlers

**Code Pattern:**
```dart
// Extract UI-specific fields that should be at top level
final myHandCards = gameCopy.remove('myHandCards');
final selectedCardIndex = gameCopy.remove('selectedCardIndex');
// ... extract other UI fields

// Everything else is game_state fields
final gameState = gameCopy;

// Reconstruct nested structure
nestedGames[gameId] = {
  'gameData': {
    'game_id': gameIdFromState ?? gameId,
    'game_state': gameState, // All remaining fields go here
    if (ownerId != null) 'owner_id': ownerId,
  },
  // UI fields at top level
  if (myHandCards != null) 'myHandCards': myHandCards,
  // ... other UI fields
};
```

## Why This Is Problematic

### 1. **Complexity and Maintenance Burden**
- Two different structures to maintain
- Conversion logic scattered across multiple methods
- Hard to understand which structure is used where
- Easy to introduce bugs when modifying state access

### 2. **Performance Overhead**
- Every handler call triggers conversion (flattened → nested)
- Every state update triggers conversion (nested → flattened)
- Unnecessary object creation and copying
- Extra memory usage

### 3. **Potential for Bugs**
- **Mutation Issues:** The conversion uses `remove()` which can mutate state if not careful (we fixed this by creating copies)
- **Reference Issues:** `gameState` references can become stale when conversions happen
- **Synchronization Issues:** Changes to nested structure might not be reflected in flattened structure immediately
- **Lost Updates:** If conversion happens at wrong time, updates can be lost

### 4. **Example Bug We Just Fixed**
When `_startNextTurn()` set `gameState['currentPlayer'] = nextPlayer`, it modified the nested structure in memory. However, when `handleDrawCard()` called `_getCurrentGameState()`, it read from the flattened state (which didn't have the update), causing "No current player found" errors.

**The Fix:** We had to explicitly update the nested structure in `currentGamesMap` and persist it through `onGameStateChanged()`. This is exactly the kind of complexity we want to eliminate.

### 5. **Code Duplication**
- Similar conversion logic in multiple places
- UI field extraction logic duplicated
- Hard to keep conversions in sync

## The Solution: Unified Flattened Structure

### Goal
Remove the conversion layer entirely. Have **everything** (handlers, widgets, storage) use the same flattened structure.

### Migration Steps

#### Phase 1: Update Handler Access Patterns

**Current Pattern (Nested):**
```dart
final currentGames = _stateCallback.currentGamesMap;
final gameData = currentGames[_gameId];
final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;

// Access fields
final players = gameState['players'];
final currentPlayer = gameState['currentPlayer'];
```

**New Pattern (Flattened):**
```dart
final currentGames = _stateCallback.currentGamesMap;
final gameState = currentGames[_gameId] as Map<String, dynamic>?;

// Access fields directly (no nesting)
final players = gameState['players'];
final currentPlayer = gameState['currentPlayer'];
```

#### Phase 2: Update `getCurrentGameState()` Method

**Current Implementation:**
```dart
Map<String, dynamic> getCurrentGameState() {
  final currentGames = _getCurrentGamesMap(); // Returns nested
  final gameData = currentGames[currentGameId]['gameData'];
  final gameState = gameData?['game_state'];
  return gameState ?? {};
}
```

**New Implementation:**
```dart
Map<String, dynamic> getCurrentGameState() {
  final currentGames = _getCurrentGamesMap(); // Returns flattened
  return currentGames[currentGameId] ?? {};
}
```

#### Phase 3: Update `currentGamesMap` Getter

**Current Implementation:**
```dart
Map<String, dynamic> get currentGamesMap => _getCurrentGamesMap();
// _getCurrentGamesMap() converts flattened → nested
```

**New Implementation:**
```dart
Map<String, dynamic> get currentGamesMap {
  final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  // No conversion - return flattened structure directly
}
```

#### Phase 4: Remove Conversion Methods

**Methods to Remove:**
- Flattening logic in `onGameStateChanged()` (keep the method, remove flattening)
- Flattening logic in `updatePracticeGameState()` (keep the method, remove flattening)
- `_getCurrentGamesMap()` conversion logic (simplify to just read from state)

**Methods to Simplify:**
- `getCurrentGameState()` - remove nested structure access
- All handlers - update to access flattened structure directly

#### Phase 5: Update Handler State Modifications

**Current Pattern:**
```dart
// Modify nested structure
gameState['currentPlayer'] = nextPlayer;

// Get fresh games map (creates new nested structure)
final currentGames = _stateCallback.currentGamesMap;

// Update nested structure in games map
final gameData = currentGames[_gameId];
final gameDataInner = gameData['gameData'];
gameDataInner['game_state']['currentPlayer'] = nextPlayer;

// Persist
_stateCallback.onGameStateChanged({'games': currentGames});
```

**New Pattern:**
```dart
// Get current games map (flattened)
final currentGames = _stateCallback.currentGamesMap;

// Modify flattened structure directly
final gameState = currentGames[_gameId];
gameState['currentPlayer'] = nextPlayer;

// Persist
_stateCallback.onGameStateChanged({'games': currentGames});
```

## Benefits of Migration

### 1. **Simplified Codebase**
- Single structure to maintain
- No conversion logic
- Easier to understand and debug

### 2. **Better Performance**
- No conversion overhead
- Direct state access
- Less object creation

### 3. **Fewer Bugs**
- No mutation issues from conversion
- No reference staleness
- No lost updates
- Direct state access = predictable behavior

### 4. **Easier Maintenance**
- One structure to update
- Clear access patterns
- Less code to maintain

## Migration Checklist

### Handler Updates
- [ ] Update `handleDrawCard()` to use flattened structure
- [ ] Update `handlePlayCard()` to use flattened structure
- [ ] Update `handleCollectFromDiscard()` to use flattened structure
- [ ] Update `handleSameRankPlay()` to use flattened structure
- [ ] Update `handleJackSwap()` to use flattened structure
- [ ] Update `handleQueenPeek()` to use flattened structure
- [ ] Update `_startNextTurn()` to use flattened structure
- [ ] Update `_moveToNextPlayer()` to use flattened structure
- [ ] Update all other methods that access `currentGamesMap`

### Method Updates
- [ ] Simplify `getCurrentGameState()` to return flattened structure
- [ ] Simplify `currentGamesMap` getter to return flattened structure
- [ ] Remove flattening logic from `onGameStateChanged()`
- [ ] Remove flattening logic from `updatePracticeGameState()`
- [ ] Remove conversion logic from `_getCurrentGamesMap()`

### Testing
- [ ] Test all player actions (draw, play, collect, same rank, jack swap, queen peek)
- [ ] Test computer player actions
- [ ] Test state persistence
- [ ] Test widget updates
- [ ] Test WebSocket event handling

## Current State Access Patterns

### Widgets (Already Using Flattened)
```dart
final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
final players = currentGame['players']; // Direct access
final myHandCards = currentGame['myHandCards']; // Direct access
```

### Handlers (Currently Using Nested - NEEDS UPDATE)
```dart
final currentGames = _stateCallback.currentGamesMap; // Returns nested
final gameData = currentGames[_gameId];
final gameDataInner = gameData?['gameData'];
final gameState = gameDataInner?['game_state'];
final players = gameState['players']; // Nested access
```

### After Migration (Handlers Using Flattened)
```dart
final currentGames = _stateCallback.currentGamesMap; // Returns flattened
final gameState = currentGames[_gameId];
final players = gameState['players']; // Direct access (same as widgets)
```

## Key Files to Modify

1. **`practice_game.dart`**
   - `_getCurrentGamesMap()` - Remove conversion, return flattened directly
   - `getCurrentGameState()` - Simplify to return flattened structure
   - `onGameStateChanged()` - Remove flattening logic
   - `updatePracticeGameState()` - Remove flattening logic

2. **`recall_game_round.dart`**
   - All handlers - Update to access flattened structure
   - `_startNextTurn()` - Update to modify flattened structure
   - `_moveToNextPlayer()` - Update to modify flattened structure
   - All methods using `currentGamesMap` - Update access patterns

3. **`recall_event_handler_callbacks.dart`**
   - `handleGameStateUpdated()` - Already uses flattened (good!)
   - Verify all WebSocket handlers use flattened

## Notes

- **Widgets are already correct** - They read from flattened structure directly
- **WebSocket handlers are already correct** - They flatten before storing
- **Only handlers need updating** - They're the ones expecting nested structure
- **Backend doesn't need changes** - Backend uses its own structure, only Flutter needs this migration

## Timeline Recommendation

1. **Phase 1:** Update one handler at a time, test thoroughly
2. **Phase 2:** Update `getCurrentGameState()` and `currentGamesMap` getter
3. **Phase 3:** Remove conversion logic
4. **Phase 4:** Clean up and test everything

This migration will significantly simplify the codebase and eliminate a major source of bugs and complexity.

