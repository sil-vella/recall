# Recall Game - State Management

## Overview

The Recall game uses the Flutter Base 05 state management system with a sophisticated approach to managing game state. The game state is complex, involving multiple players, cards, game phases, and real-time updates. This document describes how the Recall game leverages the state management system, with particular focus on the pattern of **passing games maps** instead of always reading directly from state.

## State Architecture

### Game State Structure

The Recall game state is organized hierarchically:

```
recall_game (module state)
├── games (Map<String, GameData>)
│   └── [gameId] (GameData)
│       └── gameData
│           └── game_state (GameStateData)
│               ├── players (List<PlayerData>)
│               ├── currentPlayer (PlayerData)
│               ├── drawPile (List<CardData>)
│               ├── discardPile (List<CardData>)
│               └── ... (other game state)
├── currentGameId (String)
├── currentPlayer (PlayerData)
├── isMyTurn (bool)
└── ... (computed widget slices)
```

### Immutable State Models

The game uses immutable state models for type safety:

- `RecallGameState`: Top-level game state
- `GamesMap`: Map of all active games
- `GameData`: Single game's data
- `GameStateData`: Core game state (players, piles, etc.)
- `PlayerData`: Individual player data
- `CardData`: Card information

## The Games Map Pattern

### Problem: Stale State Reads

When state updates are queued asynchronously (via `StateQueueValidator`), reading directly from state can result in **stale data**. This is particularly problematic in the Recall game where:

1. Turn transitions happen rapidly
2. Multiple state updates occur in sequence
3. Computer players need immediate access to current state

### Solution: Pass Games Map Directly

Instead of always reading from state, the game passes the **games map** directly through function calls. This ensures that functions work with the most up-to-date data, even if state hasn't been processed yet.

### Pattern Implementation

#### 1. Updating Player Status

The `updatePlayerStatus` function accepts an optional `gamesMap` parameter:

```dart
bool updatePlayerStatus(
  String status, {
  String? playerId,
  bool updateMainState = true,
  bool triggerInstructions = false,
  Map<String, dynamic>? gamesMap, // ✅ Pass games map directly
}) {
  // Use provided gamesMap if available (avoids stale state read)
  // Otherwise read from state
  final currentGames = gamesMap ?? _getCurrentGamesMap();
  
  if (gamesMap != null) {
    _logger.info('Using provided gamesMap (avoiding stale state read)');
  }
  
  // ... rest of implementation
}
```

**Why This Works:**
- When called immediately after updating the games map, the function uses the updated map
- Avoids reading stale state from `StateManager`
- Ensures correct `currentPlayer` identification

#### 2. Turn Management

When starting a new turn, the games map is updated and passed directly:

```dart
void _startNextTurn() {
  // Update currentPlayer in game state
  gameState['currentPlayer'] = nextPlayer;
  
  // Update currentPlayer in the games map
  final currentGames = _stateCallback.currentGamesMap;
  // ... update games map structure ...
  
  // Update state (queued asynchronously)
  _stateCallback.onGameStateChanged({
    'games': currentGames,
    'currentPlayer': nextPlayer,
    'turn_events': [],
  });
  
  // ✅ Pass gamesMap directly to avoid stale state read
  _stateCallback.onPlayerStatusChanged(
    'drawing_card',
    playerId: nextPlayer['id'],
    gamesMap: currentGames, // Pass the updated map
  );
}
```

**Why This Works:**
- The games map is updated before calling `onPlayerStatusChanged`
- The updated map is passed directly, avoiding a stale read
- State update is queued but doesn't block the immediate operation

#### 3. Computer Player Actions

Computer player actions use both `playerId` and `gamesMap` parameters:

```dart
Future<bool> handlePlayCard(String cardId, {
  String? playerId,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  // Use provided gamesMap if available (avoids stale state read)
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  final gameState = currentGames[_gameId]?['gameData']?['game_state'];
  
  // Use provided playerId if available (avoids stale currentPlayer)
  String? actualPlayerId = playerId;
  if (actualPlayerId == null) {
    // Fallback to reading from currentPlayer in games map
    actualPlayerId = gameState['currentPlayer']?['id'];
  }
  
  // ... rest of implementation
}
```

**Why This Works:**
- Computer players pass their `playerId` directly
- Functions receive `gamesMap` to avoid stale state reads
- Ensures correct player identification even during rapid turn transitions
- Works correctly even when state updates are queued asynchronously

#### 4. Event Handlers

Event handlers get the games map and pass it to action handlers:

```dart
Future<bool> _handlePlayCard(String sessionId, Map<String, dynamic> data, {
  Map<String, dynamic>? gamesMap,
}) async {
  // Use provided gamesMap if available (avoids stale state read)
  final currentGames = gamesMap ?? _getCurrentGamesMap();
  
  // Extract gameState from games map
  final gameState = currentGames[currentGameId]?['gameData']?['game_state'];
  
  // Validate current player from games map (not from state)
  final currentPlayer = gameState['currentPlayer'];
  
  // Pass gamesMap to action handler
  final success = await _gameRound!.handlePlayCard(
    cardId,
    gamesMap: currentGames, // ✅ Pass games map
  );
}
```

**Why This Works:**
- Event handlers get fresh games map at the start
- Pass games map to action handlers to avoid stale reads
- Ensures all operations use the same up-to-date state

## State Update Flow

### Normal Flow (Without Games Map Pattern)

```
1. Update games map in memory
2. Call onGameStateChanged() → queues state update
3. Call onPlayerStatusChanged() → reads from state ❌ (stale!)
4. State update processes asynchronously
```

**Problem:** Step 3 reads stale state because step 2 is queued.

### Improved Flow (With Games Map Pattern)

```
1. Update games map in memory
2. Call onGameStateChanged() → queues state update
3. Call onPlayerStatusChanged(gamesMap: currentGames) → uses provided map ✅
4. Call action handlers (handleDrawCard, handlePlayCard, etc.) with gamesMap ✅
5. State update processes asynchronously
```

**Solution:** Steps 3 and 4 use the updated map directly, avoiding stale reads.

### Event Handler Flow

When a user action triggers an event:

```
1. Event handler receives event (_handleDrawCard, _handlePlayCard, etc.)
2. Get current games map: currentGames = _getCurrentGamesMap()
3. Extract gameState from games map
4. Validate action (check current player, status, etc.) using games map
5. Call action handler with gamesMap: handleDrawCard(source, gamesMap: currentGames) ✅
6. Action handler uses provided gamesMap (avoids stale state read)
7. State updates are queued asynchronously
```

**Key Point:** The games map is obtained once at the start and passed through all function calls, ensuring consistency.

## Key Functions Using Games Map Pattern

### Player Action Handlers

All player action handlers now accept an optional `gamesMap` parameter to avoid stale state reads:

#### updatePlayerStatus

**Location:** `practice_game.dart`

**Purpose:** Update a player's status in the game state

**Games Map Usage:**
```dart
bool updatePlayerStatus(String status, {
  String? playerId,
  bool updateMainState = true,
  bool triggerInstructions = false,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) {
  final currentGames = gamesMap ?? _getCurrentGamesMap();
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_startNextTurn()` - passes updated games map
- `_moveToNextPlayer()` - passes updated games map
- Other turn management functions

#### handleDrawCard

**Location:** `recall_game_round.dart`

**Purpose:** Handle a player drawing a card

**Games Map Usage:**
```dart
Future<bool> handleDrawCard(String source, {
  String? playerId,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handleDrawCard()` event handler - passes games map
- Computer player decision execution
- Human player draw actions

#### handlePlayCard

**Location:** `recall_game_round.dart`

**Purpose:** Handle a player playing a card

**Games Map Usage:**
```dart
Future<bool> handlePlayCard(String cardId, {
  String? playerId,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handlePlayCard()` event handler - passes games map
- Computer player decision execution
- Human player play actions

#### handleSameRankPlay

**Location:** `recall_game_round.dart`

**Purpose:** Handle a player playing a card during the same rank window

**Games Map Usage:**
```dart
Future<bool> handleSameRankPlay(String playerId, String cardId, {
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handleSameRankPlay()` event handler - passes games map
- Computer player same rank play execution
- `_handleComputerSameRankPlay()` - passes games map

#### handleCollectFromDiscard

**Location:** `recall_game_round.dart`

**Purpose:** Handle a player collecting a card from the discard pile

**Games Map Usage:**
```dart
Future<bool> handleCollectFromDiscard(String playerId, {
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handleDrawCard()` event handler (when source is 'discard') - passes games map
- `_checkComputerPlayerCollectionFromDiscard()` - passes and refreshes games map in loop

#### handleJackSwap

**Location:** `recall_game_round.dart`

**Purpose:** Handle a Jack card swap between two players

**Games Map Usage:**
```dart
Future<bool> handleJackSwap({
  required String firstCardId,
  required String firstPlayerId,
  required String secondCardId,
  required String secondPlayerId,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handleJackSwap()` event handler - passes games map
- Computer player Jack swap execution

#### handleQueenPeek

**Location:** `recall_game_round.dart`

**Purpose:** Handle a Queen card peek action

**Games Map Usage:**
```dart
Future<bool> handleQueenPeek({
  required String peekingPlayerId,
  required String targetCardId,
  required String targetPlayerId,
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
}
```

**Called From:**
- `_handleQueenPeek()` event handler - passes games map
- Computer player Queen peek execution

### Event Handlers

Event handlers now accept and use gamesMap to avoid stale state reads:

#### _handleDrawCard

**Location:** `practice_game.dart`

**Purpose:** Handle the draw_card event from the UI

**Games Map Usage:**
```dart
Future<bool> _handleDrawCard(String sessionId, Map<String, dynamic> data, {
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _getCurrentGamesMap();
  // Uses provided map if available, otherwise reads from state
  // Passes gamesMap to handleDrawCard() or handleCollectFromDiscard()
}
```

#### _handlePlayCard

**Location:** `practice_game.dart`

**Purpose:** Handle the play_card event from the UI

**Games Map Usage:**
```dart
Future<bool> _handlePlayCard(String sessionId, Map<String, dynamic> data, {
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _getCurrentGamesMap();
  // Uses provided map if available, otherwise reads from state
  // Passes gamesMap to handlePlayCard()
}
```

#### _handleSameRankPlay

**Location:** `practice_game.dart`

**Purpose:** Handle the same_rank_play event from the UI

**Games Map Usage:**
```dart
Future<bool> _handleSameRankPlay(String sessionId, Map<String, dynamic> data) async {
  final currentGames = _getCurrentGamesMap();
  // Passes gamesMap to handleSameRankPlay()
  await _gameRound!.handleSameRankPlay('recall_user', cardId, gamesMap: currentGames);
}
```

### Post-Action Processing Functions

Functions that process actions after they occur also use the games map pattern:

#### _checkComputerPlayerSameRankPlays

**Location:** `recall_game_round.dart`

**Purpose:** Check and execute same rank plays for all computer players

**Games Map Usage:**
```dart
Future<void> _checkComputerPlayerSameRankPlays({
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  // Uses provided map if available, otherwise reads from state
  // Passes gamesMap to _handleComputerSameRankPlay()
}
```

**Called From:**
- `_endSameRankWindow()` - passes games map

#### _checkComputerPlayerCollectionFromDiscard

**Location:** `recall_game_round.dart`

**Purpose:** Check and execute collection from discard for all computer players

**Games Map Usage:**
```dart
Future<void> _checkComputerPlayerCollectionFromDiscard({
  Map<String, dynamic>? gamesMap, // ✅ Optional games map
}) async {
  Map<String, dynamic> currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  
  // CRITICAL: Refresh games map in each loop iteration
  while (continueChecking) {
    // Refresh to get updated state after collections
    currentGames = _stateCallback.currentGamesMap;
    // ... process collection ...
    // Pass gamesMap to handleCollectFromDiscard()
    await handleCollectFromDiscard(playerId, gamesMap: currentGames);
  }
}
```

**Called From:**
- `_endSameRankWindow()` - passes games map

#### _handleComputerSameRankPlay

**Location:** `recall_game_round.dart`

**Purpose:** Handle a single computer player's same rank play

**Games Map Usage:**
```dart
Future<void> _handleComputerSameRankPlay(
  String playerId,
  String difficulty,
  Map<String, dynamic> gamesMap, // ✅ Required games map (not optional)
) async {
  // Extract gameState from gamesMap
  final gameData = gamesMap[_gameId];
  final gameState = gameData?['gameData']?['game_state'];
  // ... process same rank play ...
  // Pass gamesMap to handleSameRankPlay()
  await handleSameRankPlay(playerId, cardId, gamesMap: gamesMap);
}
```

**Called From:**
- `_checkComputerPlayerSameRankPlays()` - passes games map

## State Update Sequence

### Turn Transition Example

Here's how a turn transition works with the games map pattern:

```dart
// 1. Current player finishes turn
_stateCallback.onPlayerStatusChanged('waiting', playerId: currentPlayerId);

// 2. Move to next player
void _moveToNextPlayer() {
  // Update game state
  gameState['currentPlayer'] = nextPlayer;
  
  // Update games map
  final currentGames = _stateCallback.currentGamesMap;
  currentGames[gameId]['gameData']['game_state']['currentPlayer'] = nextPlayer;
  
  // Queue state update (asynchronous)
  _stateCallback.onGameStateChanged({
    'games': currentGames,
    'currentPlayer': nextPlayer,
  });
  
  // ✅ Pass games map directly (synchronous, uses updated map)
  _stateCallback.onPlayerStatusChanged(
    'drawing_card',
    playerId: nextPlayerId,
    gamesMap: currentGames, // Uses the updated map, not stale state
  );
  
  // Computer player turn starts immediately
  if (!isHuman) {
    _initComputerTurn(gameState); // Uses updated gameState
  }
}
```

**Key Points:**
1. Games map is updated in memory first
2. State update is queued (asynchronous)
3. Next operation uses the updated games map directly
4. No stale state reads occur

## Widget Slice Computation

### Computed State Slices

The game computes "widget slices" - pre-computed state for specific widgets:

- `myHand`: Current player's hand state
- `opponentsPanel`: Opponents' information
- `centerBoard`: Draw/discard piles and game info
- `gameInfo`: General game information

### Slice Computation Pattern

```dart
void _updateWidgetSlices(RecallGameState state) {
  // Compute slices from SSOT (Single Source of Truth)
  final games = state.games;
  final currentGameId = state.currentGameId;
  final gameData = games.games[currentGameId];
  
  if (gameData != null) {
    // Compute myHand slice
    final myHand = _computeMyHandSlice(gameData);
    
    // Compute opponentsPanel slice
    final opponentsPanel = _computeOpponentsPanelSlice(gameData);
    
    // ... other slices
    
    // Update state with computed slices
    updateModuleState('recall_game', state.copyWith(
      myHand: myHand,
      opponentsPanel: opponentsPanel,
      // ...
    ));
  }
}
```

**Benefits:**
- Widgets receive pre-computed, optimized data
- Reduces computation in widget build methods
- Ensures consistency across widgets

## Best Practices

### 1. Pass Games Map When Available

When you've just updated the games map, pass it directly:

```dart
// ✅ Good: Pass updated map
final currentGames = _stateCallback.currentGamesMap;
// ... update currentGames ...
_stateCallback.onPlayerStatusChanged('status', gamesMap: currentGames);

// ❌ Bad: Read from state (may be stale)
_stateCallback.onPlayerStatusChanged('status'); // Reads from state
```

### 2. Use playerId and gamesMap Parameters

When calling functions that need to identify the current player:

```dart
// ✅ Good: Pass both playerId and gamesMap
final currentGames = _getCurrentGamesMap();
await handlePlayCard(cardId, playerId: playerId, gamesMap: currentGames);

// ✅ Also Good: Pass gamesMap even without playerId
final currentGames = _getCurrentGamesMap();
await handlePlayCard(cardId, gamesMap: currentGames);

// ❌ Bad: Rely on currentPlayer from state (may be stale)
await handlePlayCard(cardId); // Reads currentPlayer from state
```

### 3. Update Games Map Before State Update

Always update the games map in memory before queuing state updates:

```dart
// ✅ Good: Update map, then queue state update
final currentGames = _stateCallback.currentGamesMap;
currentGames[gameId]['gameData']['game_state']['currentPlayer'] = nextPlayer;
_stateCallback.onGameStateChanged({'games': currentGames});

// ❌ Bad: Queue state update without updating map
_stateCallback.onGameStateChanged({'currentPlayer': nextPlayer}); // Map not updated
```

### 4. Use SSOT for Status

Player status should always come from the Single Source of Truth:

```dart
// ✅ Good: Read status from players array (SSOT)
final player = gameState['players'].firstWhere((p) => p['id'] == playerId);
final status = player['status'];

// ❌ Bad: Read from redundant status field
final status = gameState['playerStatus'][playerId]; // May be stale
```

## Common Pitfalls

### Pitfall 1: Reading State Immediately After Update

```dart
// ❌ Problem: State update is queued, read happens before processing
_stateCallback.onGameStateChanged({'games': updatedGames});
final games = _getCurrentGamesMap(); // Stale!

// ✅ Solution: Use the updated map directly
_stateCallback.onGameStateChanged({'games': updatedGames});
// Use updatedGames directly, don't read from state
```

### Pitfall 2: Relying on currentPlayer from State

```dart
// ❌ Problem: currentPlayer may be stale during turn transitions
final currentPlayer = gameState['currentPlayer'];
await handlePlayCard(cardId); // Uses stale currentPlayer

// ✅ Solution: Pass playerId directly
await handlePlayCard(cardId, playerId: actualPlayerId);
```

### Pitfall 3: Not Updating Games Map Before State Update

```dart
// ❌ Problem: Games map not updated, state update has wrong data
_stateCallback.onGameStateChanged({'currentPlayer': nextPlayer});

// ✅ Solution: Update games map first
final currentGames = _stateCallback.currentGamesMap;
currentGames[gameId]['gameData']['game_state']['currentPlayer'] = nextPlayer;
_stateCallback.onGameStateChanged({'games': currentGames});
```

## Performance Considerations

### Games Map Pattern Benefits

1. **Reduces State Reads**: Functions use provided maps instead of reading from state
2. **Eliminates Stale Reads**: Direct map passing ensures up-to-date data
3. **Improves Turn Transitions**: Computer players get immediate access to current state

### Trade-offs

1. **Memory**: Maps are passed by reference, so memory usage is minimal
2. **Complexity**: Functions need to handle both provided maps and state reads
3. **Testing**: Need to test both code paths (with and without games map)

## Complete Function Reference

### Functions with gamesMap Parameter

All of these functions accept an optional `gamesMap` parameter:

**Player Action Handlers:**
- `updatePlayerStatus()` - Updates player status
- `handleDrawCard()` - Handles drawing a card
- `handlePlayCard()` - Handles playing a card
- `handleSameRankPlay()` - Handles same rank play
- `handleCollectFromDiscard()` - Handles collecting from discard
- `handleJackSwap()` - Handles Jack swap
- `handleQueenPeek()` - Handles Queen peek

**Event Handlers:**
- `_handleDrawCard()` - Draw card event handler
- `_handlePlayCard()` - Play card event handler
- `_handleSameRankPlay()` - Same rank play event handler

**Post-Action Processing:**
- `_checkComputerPlayerSameRankPlays()` - Checks computer same rank plays
- `_checkComputerPlayerCollectionFromDiscard()` - Checks computer collections
- `_handleComputerSameRankPlay()` - Handles single computer same rank play

### Functions with playerId Parameter

These functions accept an optional `playerId` parameter to avoid stale `currentPlayer` reads:

- `handleDrawCard()` - Accepts both `playerId` and `gamesMap`
- `handlePlayCard()` - Accepts both `playerId` and `gamesMap`

## Summary

The Recall game's state management approach:

- ✅ **Uses Immutable State Models**: Type-safe, predictable state updates
- ✅ **Passes Games Map Directly**: Avoids stale state reads during rapid updates
- ✅ **Leverages SSOT**: Player status comes from players array, not redundant fields
- ✅ **Computes Widget Slices**: Pre-computed state for efficient widget rendering
- ✅ **Handles Asynchronous Updates**: Works correctly with queued state updates
- ✅ **Comprehensive gamesMap Pattern**: All action handlers and event handlers use gamesMap

The games map pattern is essential for the Recall game because:
- Turn transitions happen rapidly
- Multiple state updates occur in sequence
- Computer players need immediate access to current state
- State updates are queued asynchronously
- Event handlers need consistent state throughout the action

By passing the games map directly through all function calls, the game ensures that:
- All operations work with the most up-to-date data
- No stale state reads occur during rapid updates
- Turn transitions are smooth and accurate
- Computer players make decisions based on current state
- Event handlers validate actions against current state

This comprehensive approach prevents bugs and ensures smooth, accurate gameplay.

