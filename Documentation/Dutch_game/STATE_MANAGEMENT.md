# State Management Documentation - Dutch Game (Flutter)

## Overview

This document describes the complete state management system for the Dutch game in Flutter. It covers state architecture, update flows, player actions, event handling, widget synchronization, and all state-related scenarios during gameplay.

---

## Game Modes

The Dutch game supports two distinct game modes, controlled by the `isClearAndCollect` flag in the game state:

### 1. **Play Dutch** (Clear Mode)
- **Flag**: `isClearAndCollect: false`
- **Description**: A simplified game mode without collection mechanics
- **Features**:
  - No collection rank selection during initial peek
  - Both peeked cards are stored as ID-only (face-down) in `known_cards`
  - Collection from discard pile is disabled
  - Collection cards cannot be played (validation skipped)
  - Four-of-a-kind win condition is disabled
  - AI players do not attempt to collect cards
  - Collection-related UI elements are hidden

### 2. **Play Dutch: Clear and Collect** (Collection Mode)
- **Flag**: `isClearAndCollect: true`
- **Description**: The full game mode with collection mechanics enabled
- **Features**:
  - Collection rank selection during initial peek
  - One peeked card becomes the collection rank card (face-up)
  - Other peeked card stored in `known_cards` (face-down)
  - Collection from discard pile is enabled
  - Collection cards cannot be played (validation active)
  - Four-of-a-kind win condition is enabled
  - AI players attempt to collect matching cards
  - Collection-related UI elements are visible

**Important**: The `isClearAndCollect` flag is set when the game is initiated (via lobby screen buttons) and remains constant throughout the game session. It cannot be changed mid-game.

---

## Table of Contents

1. [Game Modes](#game-modes)
2. [State Architecture](#state-architecture)
2. [State Structure](#state-structure)
3. [State Update Flow](#state-update-flow)
4. [Player Actions Flow](#player-actions-flow)
5. [Event Handling](#event-handling)
6. [Widget State Synchronization](#widget-state-synchronization)
7. [State Update Scenarios](#state-update-scenarios)
8. [Widget Rebuild System](#widget-rebuild-system)
9. [Special State Handling](#special-state-handling)
10. [Practice vs Multiplayer Differences](#practice-vs-multiplayer-differences)
11. [State Cleanup](#state-cleanup)
12. [Related Files](#related-files)
13. [Future Improvements](#future-improvements)

---

## State Architecture

### Core Components

The state management system consists of several key components:

1. **StateManager** (Singleton, ChangeNotifier)
   - Central state store for all modules
   - Implements `ChangeNotifier` for reactive updates
   - Location: `flutter_base_05/lib/core/managers/state_manager.dart`
   - Manages module states as `Map<String, ModuleState>`

2. **DutchGameStateUpdater** (Singleton)
   - Validates and applies state updates
   - Computes widget slices based on dependencies
   - Location: `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart`
   - Uses `StateQueueValidator` for validation

3. **StateQueueValidator** (Singleton)
   - Validates state updates before applying
   - Ensures state structure consistency
   - Location: `flutter_base_05/lib/modules/dutch_game/utils/state_queue_validator.dart`
   - Queues updates and applies them asynchronously

4. **DutchEventHandlerCallbacks** (Static methods)
   - Processes game events and updates state
   - Handles all game-related events
   - Location: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart`
   - Main entry point for event-driven state updates

5. **DutchEventManager** (Singleton)
   - Receives and routes events
   - Delegates to `DutchEventHandlerCallbacks`
   - Location: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_manager.dart`
   - Registers WebSocket event listeners

6. **DutchGameHelpers** (Static methods)
   - Convenient helper methods for state updates
   - Wraps `DutchGameStateUpdater` calls
   - Location: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
   - Provides high-level state update API

### State Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    State Management Flow                     │
└─────────────────────────────────────────────────────────────┘

Event Received (WebSocket/Practice)
    ↓
DutchEventManager.handleGameStateUpdated()
    ↓
DutchEventHandlerCallbacks.handleGameStateUpdated()
    ↓
Extract game state, players, turn_events
    ↓
Update games map with new game_state
    ↓
_syncWidgetStatesFromGameState() - Extract widget data
    ↓
DutchGameHelpers.updateUIState()
    ↓
DutchGameStateUpdater.updateState()
    ↓
StateQueueValidator.validateUpdate() & enqueue
    ↓
DutchGameStateUpdater._applyValidatedUpdates()
    ↓
_updateWidgetSlices() - Recompute slices
    ↓
StateManager.updateModuleState('dutch_game', newState)
    ↓
StateManager.notifyListeners() (via Future.microtask)
    ↓
All ListenableBuilder widgets rebuild
```

---

## State Structure

### Module State: `dutch_game`

The Dutch game module state is stored under the key `'dutch_game'` in `StateManager`. The complete structure is:

```dart
{
  // ========================================
  // CONNECTION STATE
  // ========================================
  'isConnected': bool,           // WebSocket connection status
  'isLoading': bool,             // Loading state for async operations
  'lastError': String?,          // Last error message (if any)
  
  // ========================================
  // CURRENT GAME REFERENCES
  // ========================================
  'currentGameId': String,       // ID of currently active game
  'currentRoomId': String,       // ID of current room (same as gameId for multiplayer)
  'isInRoom': bool,              // Whether user is in a room
  'isRoomOwner': bool,           // Whether user owns the current room
  'isGameActive': bool,          // Whether game is currently active (not ended)
  
  // ========================================
  // GAMES MAP (Single Source of Truth)
  // ========================================
  'games': {
    'gameId': {
      // Game metadata
      'gameData': {
        'game_id': String,
        'owner_id': String?,
        'game_state': {          // ⭐ SINGLE SOURCE OF TRUTH (SSOT)
          'phase': String,       // 'waiting_for_players' | 'initial_peek' | 'playing' | 'game_ended'
          'status': String,      // 'active' | 'paused' | 'ended'
          'gameType': String,    // 'normal' | 'practice'
          'roundNumber': int,
          'turnNumber': int,
          'isClearAndCollect': bool,  // Game mode flag: false = clear mode (no collection), true = collection mode
          
          // Players (full data for current user, ID-only for others)
          'players': [
            {
              'id': String,              // Player ID (sessionId in multiplayer)
              'name': String,
              'hand': List<Card>,        // Full cards for current user, ID-only for others
              'drawnCard': Card?,        // Full data for current user, ID-only for others
              'cardsToPeek': List<Card>, // Cards available to peek (Queen power)
              'status': String,          // 'waiting' | 'drawing_card' | 'playing_card' | ...
              'score': int,
              'points': int,
              'isCurrentPlayer': bool,
            }
          ],
          
          // Current player
          'currentPlayer': {
            'id': String,
            'name': String,
            'status': String,
          },
          
          // Piles
          'drawPile': List<Card>,        // ID-only cards
          'discardPile': List<Card>,     // Full card data
          'originalDeck': List<Card>,    // Full card data for lookups
          
          // Game state
          'playerCount': int,
          'maxPlayers': int,
          'minPlayers': int,
          'showInstructions': bool,
          'isClearAndCollect': bool,  // Game mode flag: false = clear mode (no collection), true = collection mode
          'dutchCalledBy': String?,   // Player ID who called Dutch (final round)
          'winners': List<Player>?,
        },
      },
      
      // Widget-specific derived data
      'gameStatus': String,              // 'active' | 'inactive' | 'ended'
      'isRoomOwner': bool,               // Computed from owner_id
      'isInGame': bool,                  // Whether user is in this game
      'joinedAt': String,                // ISO timestamp
      
      // Widget data (derived from game_state)
      'myHandCards': List<Card>,         // Current user's hand (full data)
      'myDrawnCard': Card?,              // Current user's drawn card (full data)
      'isMyTurn': bool,                  // Whether it's current user's turn
      'selectedCardIndex': int,          // Currently selected card index (-1 if none)
      'turn_events': List<Event>,        // Animation events for this turn
      
      // Pile information (for centerBoard widget)
      'drawPileCount': int,
      'discardPileCount': int,
      'discardPile': List<Card>,
    }
  },
  
  // ========================================
  // MAIN STATE FIELDS (Derived/Computed)
  // ========================================
  'gamePhase': String,           // 'waiting' | 'playing' | 'game_ended' (normalized from backend)
  'playerStatus': String,        // Current user's player status (from SSOT)
  'currentPlayer': Player?,      // Whose turn it is (from SSOT)
  'currentPlayerStatus': String, // Current player's status
  'roundNumber': int,            // Current round number
  'turnNumber': int,             // Current turn number
  'roundStatus': String,         // 'active' | 'paused' | 'ended'
  
  // Pile data (for centerBoard widget)
  'discardPile': List<Card>,     // Top-level discard pile reference
  'drawPileCount': int,          // Draw pile count
  'discardPileCount': int,       // Discard pile count
  
  // Turn events (for animations)
  'turn_events': List<Event>,    // Animation events for current turn
  
  // ========================================
  // WIDGET SLICES (Computed by StateUpdater)
  // ========================================
  'myHand': {
    'cards': List<Card>,
    'selectedIndex': int,
    'canSelectCards': bool,
    'playerStatus': String,
    'turn_events': List<Event>,
  },
  
  'centerBoard': {
    'drawPileCount': int,
    'topDiscard': Card?,
    'topDraw': Card?,
    'canDrawFromDeck': bool,
    'canTakeFromDiscard': bool,
    'playerStatus': String,
  },
  
  'opponentsPanel': {
    'opponents': List<Player>,
    'currentTurnIndex': int,
    'turn_events': List<Event>,
    'currentPlayerStatus': String,
  },
  
  'actionBar': {
    'showStartButton': bool,
    'canPlayCard': bool,
    'canCallDutch': bool,
    'isGameStarted': bool,
  },
  
  'statusBar': {
    'currentPhase': String,
    'turnInfo': String,
    'playerCount': int,
    'gameStatus': String,
    'connectionStatus': String,
    'playerStatus': String,
  },
  
  'gameInfo': {
    'currentGameId': String,
    'currentSize': int,
    'maxSize': int,
    'gamePhase': String,
    'gameStatus': String,
    'isRoomOwner': bool,
    'isInGame': bool,
  },
  
  // ========================================
  // MESSAGES AND INSTRUCTIONS
  // ========================================
  'messages': {
    'session': List<Message>,    // Session-level messages
    'rooms': Map<String, List<Message>>,  // Room-specific messages
    'isVisible': bool,           // Modal visibility
    'title': String?,            // Modal title
    'content': String?,          // Modal content
    'type': String?,             // 'info' | 'success' | 'warning' | 'error'
    'showCloseButton': bool,
    'autoClose': bool,
    'autoCloseDelay': int,
  },
  
  'instructions': {
    'isVisible': bool,
    'title': String,
    'content': String,
    'key': String,               // Instruction key (e.g., 'initial', 'draw_card')
    'dontShowAgain': Map<String, bool>,  // Per-instruction "don't show again" flags
  },
  
  // ========================================
  // PROTECTED DATA (Temporary)
  // ========================================
  'protectedCardsToPeek': List<Card>?,      // Protected cardsToPeek data (5-second protection)
  'protectedCardsToPeekTimestamp': int?,    // Timestamp for protection expiry
  
  // ========================================
  // JOINED GAMES LIST
  // ========================================
  'joinedGames': List<Game>,     // List of games user has joined
  'totalJoinedGames': int,       // Total count
  'joinedGamesTimestamp': String, // Last update timestamp
  
  // ========================================
  // METADATA
  // ========================================
  'lastUpdated': String,         // ISO timestamp of last update
  'isRandomJoinInProgress': bool, // Flag for random join flow
}
```

### Single Source of Truth (SSOT)

**Key Principle**: `games[gameId].gameData.game_state` is the single source of truth for all game data.

- All game state comes from backend via `game_state_updated` events
- Widget-specific data (`myHandCards`, `myDrawnCard`) is **derived** from SSOT
- Player status, current player, and other fields are **computed** from SSOT
- Widget slices are **computed** from SSOT and main state fields

**Data Flow**:
```
Backend game_state (SSOT)
    ↓
games[gameId].gameData.game_state
    ↓
_syncWidgetStatesFromGameState() extracts current user's player
    ↓
games[gameId].myHandCards, myDrawnCard (derived)
    ↓
Widget slices computed
    ↓
Widgets read from slices
```

---

## State Update Flow

### Complete Update Flow

1. **Event Received**
   - WebSocket event arrives via `WebSocketManager`
   - Or practice bridge event via `PracticeModeBridge`
   - Event type: `game_state_updated`, `game_state_partial_update`, etc.

2. **Event Routing**
   - `DutchEventManager.handleGameStateUpdated()` receives event
   - Delegates to `DutchEventHandlerCallbacks.handleGameStateUpdated()`

3. **Event Processing**
   - Extract `game_id`, `game_state`, `turn_events`, `owner_id` from event
   - Check if game exists in games map (new game vs. existing game)
   - Update games map with new `game_state`

4. **Widget State Synchronization**
   - `_syncWidgetStatesFromGameState()` called
   - Find current user's player in `gameState['players']`
   - Extract widget data: `myHandCards`, `myDrawnCard`, `myCardsToPeek`
   - Update games map with widget-specific data
   - Update main state with player info

5. **State Update**
   - `DutchGameHelpers.updateUIState()` or `_updateMainGameState()` called
   - Goes through `DutchGameStateUpdater.updateState()`
   - `StateQueueValidator.validateUpdate()` validates structure
     - **⚠️ Important**: Validator checks against predefined schema - must update validator when adding new fields
   - Update queued for async processing

6. **Widget Slice Computation**
   - `DutchGameStateUpdater._applyValidatedUpdates()` called
   - `_updateWidgetSlices()` recomputes slices based on changed fields
   - Only slices with changed dependencies are recomputed

7. **State Manager Update**
   - `StateManager.updateModuleState('dutch_game', newState)` called
   - State merged with existing state
   - `StateManager.notifyListeners()` called (via `Future.microtask`)

8. **Widget Rebuild**
   - All `ListenableBuilder(listenable: StateManager())` widgets rebuild
   - Widgets read from state slices
   - UI updates to reflect new state

### Update Methods

**Three Update Paths:**

1. **`DutchGameHelpers.updateUIState()`** (Most Common)
   - Main path for UI updates
   - Goes through `DutchGameStateUpdater.updateState()`
   - Validated and queued (async)
   - Used for most state updates

2. **`DutchGameStateUpdater.updateStateSync()`** (Critical Flags)
   - Synchronous updates
   - Bypasses validation queue
   - Used for critical flags that must be set before async operations
   - Example: `isRandomJoinInProgress` before emitting WebSocket events

3. **`StateManager.updateModuleState()`** (Direct)
   - Direct updates (less common)
   - Used for simple state changes
   - Still triggers `notifyListeners()`
   - Example: Instructions visibility

---

## Player Actions Flow

### User Action → State Update

**Complete Flow:**

```
1. User Interaction
   User clicks/interacts (e.g., draw card, play card)
   ↓
2. Widget Action
   Widget calls PlayerAction.playerDraw() or PlayerAction.playerPlayCard()
   ↓
3. Action Execution
   PlayerAction.execute()
   - Validates action
   - Sets _isProcessingAction flag (prevents rapid clicks)
   - Does NOT update state optimistically (backend controls state)
   ↓
4. Event Emission
   DutchGameEventEmitter.emit()
   - Validates event structure
   - Auto-adds player_id from sessionId
   - Routes to transport:
     * WebSocket (multiplayer) → WebSocketManager.send()
     * Practice Bridge (practice) → PracticeModeBridge.handleEvent()
   ↓
5. Backend Processing
   Backend (DutchGameRound) processes action
   - Validates action
   - Updates game state
   - Processes game logic
   ↓
6. Backend Broadcast
   Backend broadcasts 'game_state_updated' event
   - Sent to all players in room
   - Contains complete game state
   ↓
7. Frontend Receives Event
   Event received via WebSocket or practice bridge
   ↓
8. State Update Flow
   Follows complete state update flow (see above)
   ↓
9. Widget Rebuild
   Widgets rebuild with new state
   - Card appears in hand (draw)
   - Card removed from hand (play)
   - Discard pile updates
   - Turn info updates
```

### Key Points

- **No Optimistic Updates**: Frontend does not update state optimistically. Backend is authoritative.
- **Rapid-Click Prevention**: Widgets use `_isProcessingAction` flag to prevent multiple actions
- **Action Validation**: All actions are validated before sending (structure, required fields)
- **Auto-Player-ID**: `player_id` is automatically added by event emitter (from sessionId)
- **Transport Abstraction**: Same action code works for both multiplayer and practice modes

### Player Action Types

**Card Actions:**
- `drawCard`: Draw from draw pile or discard pile
- `playCard`: Play a card from hand
- `sameRankPlay`: Play matching rank card out of turn
- `collectFromDiscard`: Take top card from discard pile

**Special Actions:**
- `callDutch`: Call Dutch to end game
- `queenPeek`: Peek at any player's card (Queen power)
- `jackSwap`: Swap two cards between players (Jack power)
- `completedInitialPeek`: Complete initial peek phase

**Game Actions:**
- `createRoom`: Create a new game room
- `joinRoom`: Join an existing room
- `startMatch`: Start the game (room owner only)
- `leaveRoom`: Leave the current room

---

## Event Handling

### Event Types

**Main Events:**

1. **`game_state_updated`** (Most Common)
   - Full game state update
   - Contains complete `game_state` object
   - Triggered after any game action
   - Handler: `DutchEventHandlerCallbacks.handleGameStateUpdated()`

2. **`game_state_partial_update`**
   - Partial game state update
   - Contains only changed fields
   - More efficient for small updates
   - Handler: `DutchEventHandlerCallbacks.handleGameStatePartialUpdate()`

3. **`player_state_updated`**
   - Single player state update
   - Contains player-specific data
   - Handler: `DutchEventHandlerCallbacks.handlePlayerStateUpdated()`

4. **`game_started`**
   - Game has started
   - Triggered when match begins
   - Handler: `DutchEventHandlerCallbacks.handleGameStarted()`

5. **`turn_started`**
   - New turn has started
   - Contains turn information
   - Handler: `DutchEventHandlerCallbacks.handleTurnStarted()`

6. **`cleco_new_player_joined`**
   - Player joined the room
   - Handler: `DutchEventHandlerCallbacks.handleDutchNewPlayerJoined()`

7. **`cleco_joined_games`**
   - List of games user has joined
   - Handler: `DutchEventHandlerCallbacks.handleDutchJoinedGames()`

### Event Processing

**Main Handler: `handleGameStateUpdated()`**

```dart
static void handleGameStateUpdated(Map<String, dynamic> data) {
  // 1. Extract event data
  final gameId = data['game_id'];
  final gameState = data['game_state'];
  final turnEvents = data['turn_events'];
  final ownerId = data['owner_id'];
  
  // 2. Check if new game or existing game
  if (!gamesMap.containsKey(gameId)) {
    // Add new game to map
    _addGameToMap(gameId, gameData);
  } else {
    // Update existing game
    _updateGameData(gameId, {'game_state': gameState});
  }
  
  // 3. Sync widget states from game state
  _syncWidgetStatesFromGameState(gameId, gameState, turnEvents: turnEvents);
  
  // 4. Update main state
  _updateMainGameState({
    'currentGameId': gameId,
    'gamePhase': normalizedPhase,
    'games': updatedGamesMap,
    'turn_events': turnEvents,
    // ... other fields
  });
  
  // 5. Trigger instructions if needed
  _triggerInstructionsIfNeeded(...);
  
  // 6. Handle game end scenario
  if (gamePhase == 'game_ended') {
    _addSessionMessage(showModal: true, ...);
  }
}
```

---

## Widget State Synchronization

### Widget Slice System

**Purpose**: Widgets read from computed "slices" rather than raw state. This ensures:
- Consistent data structure
- Dependency tracking
- Efficient rebuilds (only affected widgets rebuild)

### ⚠️ Important: Updating State Validator When Modifying State

**CRITICAL**: When modifying state structure (adding/removing fields in state slices or main state), you **MUST** also update the state validator schema.

**Why**: The `StateQueueValidator` validates all state updates against a predefined schema. If you add a new field to a state slice (e.g., `matchPot` in `centerBoard`), the validator must know about it to allow it in state updates.

**What to Update**:

1. **State Slice Computation** (`cleco_game_state_updater.dart`):
   - Update the slice computation method (e.g., `_computeCenterBoardSlice()`)
   - Add the new field to the returned map

2. **State Validator Schema** (`state_queue_validator.dart`):
   - Find the corresponding field spec in `_stateSchema`
   - Update the `defaultValue` map to include the new field
   - Example: If adding `matchPot` to `centerBoard` slice:
     ```dart
     'centerBoard': DutchStateFieldSpec(
       type: Map,
       defaultValue: {
         'drawPileCount': 0,
         'topDiscard': null,
         'topDraw': null,
         'canDrawFromDeck': false,
         'canTakeFromDiscard': false,
         'matchPot': 0,  // ← NEW FIELD ADDED
         'playerStatus': 'unknown',
       },
       description: 'Center board widget state slice',
     ),
     ```

3. **Widget Dependencies** (if needed):
   - Check if the new field should trigger slice recomputation
   - Update `_widgetDependencies` if the field affects when slices should rebuild

**Checklist When Modifying State**:
- [ ] Update slice computation method to include new field
- [ ] Update state validator schema `defaultValue` to include new field
- [ ] Update widget dependencies if field affects rebuild triggers
- [ ] Test that state updates work correctly
- [ ] Verify widgets can read the new field from slice

**Example**: Adding `matchPot` to `centerBoard` slice:
1. ✅ Updated `_computeCenterBoardSlice()` to extract `match_pot` from `game_state` and add to result
2. ✅ Updated `state_queue_validator.dart` `centerBoard` default value to include `'matchPot': 0`
3. ✅ No dependency changes needed (field is part of `games` which is already a dependency)

**Slice Dependencies:**

| Slice | Dependencies |
|-------|-------------|
| `myHand` | `currentGameId`, `games`, `isMyTurn`, `turn_events` |
| `centerBoard` | `currentGameId`, `games`, `gamePhase`, `discardPile`, `drawPile` |
| `opponentsPanel` | `currentGameId`, `games`, `currentPlayer`, `turn_events` |
| `actionBar` | `currentGameId`, `games`, `isRoomOwner`, `isGameActive`, `isMyTurn` |
| `statusBar` | `currentGameId`, `games`, `gamePhase`, `playerCount` |
| `gameInfo` | `currentGameId`, `games`, `gamePhase`, `gameStatus` |

**Slice Computation:**

When state updates, `_updateWidgetSlices()` checks which fields changed and recomputes only affected slices:

```dart
void _updateWidgetSlices(
  Map<String, dynamic> oldState,
  Map<String, dynamic> newState,
  Set<String> changedFields,
) {
  // Only rebuild slices that depend on changed fields
  for (final entry in _widgetDependencies.entries) {
    final sliceName = entry.key;
    final dependencies = entry.value;
    
    if (changedFields.any(dependencies.contains)) {
      // Recompute this slice
      switch (sliceName) {
        case 'myHand':
          updatedState['myHand'] = _computeMyHandSlice(newState);
          break;
        // ... other slices
      }
    }
  }
}
```

### Widget State Sync Process

**Method: `_syncWidgetStatesFromGameState()`**

This method extracts widget-specific data from the SSOT (`game_state`):

```dart
static void _syncWidgetStatesFromGameState(
  String gameId,
  Map<String, dynamic> gameState,
  {List<dynamic>? turnEvents}
) {
  // 1. Get current user ID
  final currentUserId = getCurrentUserId();
  
  // 2. Find current user's player in gameState['players']
  final players = gameState['players'] as List<dynamic>? ?? [];
  final myPlayer = players.firstWhere(
    (player) => player['id'] == currentUserId
  );
  
  // 3. Extract widget data
  final hand = myPlayer['hand'] as List<dynamic>? ?? [];
  final drawnCard = myPlayer['drawnCard'] as Map<String, dynamic>?;
  final cardsToPeek = myPlayer['cardsToPeek'] as List<dynamic>? ?? [];
  final status = myPlayer['status']?.toString() ?? 'unknown';
  final score = myPlayer['score'] as int? ?? 0;
  
  // 4. Determine if it's current player's turn
  final currentPlayer = gameState['currentPlayer'];
  final isCurrentPlayer = currentPlayer['id'] == currentUserId;
  
  // 5. Update games map with widget data
  _updateGameInMap(gameId, {
    'myHandCards': hand,
    'myDrawnCard': drawnCard,
    'isMyTurn': isCurrentPlayer,
    'turn_events': turnEvents,
  });
  
  // 6. Update main state with player info
  _updateMainGameState({
    'playerStatus': status,
    'myScore': score,
    'isMyTurn': isCurrentPlayer,
    'myDrawnCard': drawnCard,
    'myCardsToPeek': cardsToPeek,
  });
}
```

### Widget Listening Pattern

All game widgets use `ListenableBuilder` to listen to state changes:

```dart
ListenableBuilder(
  listenable: StateManager(),
  builder: (context, child) {
    // Read state
    final state = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    
    // Read from slice
    final myHand = state['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    
    // Build widget
    return MyHandWidgetContent(cards: cards);
  }
)
```

**Key Points:**
- All widgets listen to `StateManager()` (singleton)
- When `StateManager.notifyListeners()` is called, all listeners rebuild
- Widgets read from computed slices, not raw state
- Only widgets with changed dependencies rebuild (efficiency)

---

## State Update Scenarios

### Scenario A: Player Draws Card

**Flow:**

1. User clicks draw pile → `PlayerAction.playerDraw(pileType: 'draw_pile')`
2. Event `draw_card` sent to backend
3. Backend processes → adds card to player's hand
4. Backend broadcasts `game_state_updated` with:
   - Updated `game_state['players']` (new card in hand)
   - Updated `game_state['drawPile']` (card removed)
   - Updated `game_state['currentPlayer']['status']` → `'playing_card'`
   - `turn_events` with draw action
5. Frontend receives → `handleGameStateUpdated()`
6. Updates games map with new `game_state`
7. `_syncWidgetStatesFromGameState()` extracts:
   - New card in `myHandCards` (full data for current user)
   - `myDrawnCard` set to drawn card (full data for current user)
   - `playerStatus` updated to `'playing_card'`
   - `isMyTurn` remains `true`
8. Widget slices recomputed:
   - `myHand` → new card added
   - `centerBoard` → draw pile count decreases
   - `statusBar` → player status updates
9. Widgets rebuild:
   - `MyHandWidget` → shows new card
   - `DrawPileWidget` → count decreases
   - `PlayerStatusChipWidget` → status updates

### Scenario B: Player Plays Card

**Flow:**

1. User selects card → clicks play → `PlayerAction.playerPlayCard(cardId: '...')`
2. Event `play_card` sent to backend
3. Backend processes → removes card from hand, adds to discard
4. Backend broadcasts `game_state_updated` with:
   - Updated `game_state['players']` (card removed from hand)
   - Updated `game_state['discardPile']` (card added)
   - Updated `game_state['currentPlayer']` (moved to next player)
   - `turn_events` with play action (for animation)
5. Frontend receives → `handleGameStateUpdated()`
6. Updates games map
7. `_syncWidgetStatesFromGameState()` extracts:
   - Updated `myHandCards` (card removed)
   - `myDrawnCard` cleared (if it was the played card)
   - `playerStatus` updated to `'waiting'`
   - `isMyTurn` set to `false` (next player's turn)
8. Widget slices recomputed:
   - `myHand` → card removed
   - `centerBoard` → discard pile updates, new top card
   - `opponentsPanel` → current player indicator moves
   - `statusBar` → turn info updates
9. Widgets rebuild:
   - `MyHandWidget` → card removed, animation triggered
   - `DiscardPileWidget` → new top card
   - `OpponentsPanelWidget` → turn indicator updates
   - `CardAnimationLayer` → plays card movement animation (from `turn_events`)

### Scenario C: Other Player's Action

**Flow:**

1. Other player performs action (draw/play)
2. Backend broadcasts `game_state_updated` to all players
3. Frontend receives → `handleGameStateUpdated()`
4. Updates games map with new `game_state`
5. `_syncWidgetStatesFromGameState()` extracts current user's data:
   - `myHandCards` unchanged (other player's action)
   - `myDrawnCard` unchanged
   - `playerStatus` unchanged (still waiting)
   - `isMyTurn` may change (if it's now current user's turn)
6. Widget slices recomputed:
   - `opponentsPanel` → opponent's hand count changes, status updates
   - `centerBoard` → discard pile updates (if card played)
   - `statusBar` → turn info updates
   - `actionBar` → may enable actions (if it's now current user's turn)
7. Widgets rebuild:
   - `OpponentsPanelWidget` → opponent's status updates
   - `DiscardPileWidget` → new top card (if card played)
   - `StatusBarWidget` → turn info updates
   - `ActionBarWidget` → actions enabled/disabled

### Scenario D: Navigation Away from Game

**Flow:**

1. User navigates away from `GamePlayScreen`
2. `GamePlayScreen.didChangeDependencies()` or `dispose()` called
3. `GameCoordinator.startLeaveGameTimer()` called
4. 30-second grace period starts
5. **If user returns:**
   - Timer cancelled
   - Game continues normally
6. **If timer expires:**
   - `GameCoordinator._executeLeaveGame()` called
   - **For multiplayer:**
     - Sends `leave_room` event to backend
     - Backend removes player from game
     - Backend broadcasts `game_state_updated` to remaining players
   - **For practice:**
     - Clears local state only (no backend event)
   - `DutchGameHelpers.removePlayerFromGame(gameId)` called
7. State cleanup:
   - Game removed from `games` map
   - `currentGameId` cleared
   - `currentRoomId` cleared
   - `isInRoom` set to `false`
   - All widget-specific state cleared:
     - `myHandCards`, `myDrawnCard`
     - `discardPile`, `drawPileCount`
     - `turn_events`
     - Widget slices cleared
8. State update triggers widget cleanup
9. Widgets rebuild → show empty state or navigate to lobby

### Scenario E: App Closure / Disconnect

**Flow:**

1. User closes app or loses network connection
2. WebSocket disconnects
3. `WebSocketServer._onDisconnect()` called (backend)
4. `RoomManager.handleDisconnect()` removes session
5. **If room becomes empty:**
   - `room_closed` hook triggered
   - Backend disposes `DutchGameRound` instance
   - Game state cleared
6. **Frontend:**
   - May not immediately detect disconnect (depends on WebSocket state)
   - State remains until next update or cleanup
   - On reconnect, state may be stale
   - Should rejoin room or clear state

---

## Widget Rebuild System

### Rebuild Triggers

**How Widgets Rebuild:**

1. **StateManager.notifyListeners()** called
   - Triggered by `StateManager.updateModuleState()`
   - Called via `Future.microtask` to avoid calling during build
   - All `ListenableBuilder(listenable: StateManager())` widgets rebuild

2. **Widgets Read from State**
   - Widgets read from computed slices
   - Only widgets with changed dependencies rebuild (efficiency)
   - Equality checks prevent unnecessary rebuilds

3. **Widget Rebuild Process:**
   ```dart
   ListenableBuilder(
     listenable: StateManager(),
     builder: (context, child) {
       // 1. Read state
       final state = StateManager().getModuleState<Map>('cleco_game');
       
       // 2. Read from slice
       final slice = state['myHand'];
       
       // 3. Build widget
       return Widget(data: slice);
     }
   )
   ```

### Rebuild Optimization

**Dependency Tracking:**

- Widget slices only recomputed when dependencies change
- `_updateWidgetSlices()` checks `changedFields` against `_widgetDependencies`
- Only affected slices recomputed
- Unchanged slices keep same reference (equality check passes)

**Equality Checks:**

- `StateManager.updateModuleState()` checks for actual changes
- For immutable state: reference equality (fast)
- For map state: JSON comparison (slower but thorough)
- Skips update if no changes detected

**Future.microtask:**

- `notifyListeners()` called via `Future.microtask`
- Prevents calling during build phase
- Ensures widgets rebuild after current frame

---

## Special State Handling

### Turn Events (Animations)

**Purpose**: `turn_events` array contains animation hints for card movements and actions.

**Structure:**
```dart
'turn_events': [
  {
    'actionType': 'draw_card' | 'play_card' | 'jack_swap' | ...,
    'cardId': String,
    'fromPlayerId': String?,
    'toPlayerId': String?,
    'fromLocation': 'hand' | 'drawPile' | 'discardPile',
    'toLocation': 'hand' | 'discardPile',
    // ... other animation data
  }
]
```

**Usage:**
- Widgets read `turn_events` from state
- `CardAnimationLayer` processes events and plays animations
- Events cleared at start of new turn
- Stored in both games map and main state

### CardsToPeek Protection

**Purpose**: Prevents flickering when `cardsToPeek` is temporarily cleared.

**Mechanism:**
1. When `cardsToPeek` contains full card data, it's protected for 5 seconds
2. Stored in `protectedCardsToPeek` in main state
3. Widgets use protected data even if `cardsToPeek` is cleared
4. Protection expires after 5 seconds

**Implementation:**
```dart
// In _syncWidgetStatesFromGameState()
if (cardsToPeek.hasFullCardData) {
  _updateMainGameState({
    'protectedCardsToPeek': cardsToPeek,
    'protectedCardsToPeekTimestamp': DateTime.now().millisecondsSinceEpoch,
  });
}

// In widget
final protectedData = state['protectedCardsToPeek'];
final timestamp = state['protectedCardsToPeekTimestamp'];
final isValid = (now - timestamp) < 5000;
final cardsToPeek = isValid ? protectedData : state['myCardsToPeek'];
```

### Instructions System

**Purpose**: Shows contextual instructions based on game phase and player status.

**Structure:**
```dart
'instructions': {
  'isVisible': bool,
  'title': String,
  'content': String,
  'key': String,  // 'initial' | 'draw_card' | 'play_card' | ...
  'dontShowAgain': Map<String, bool>,  // Per-instruction flags
}
```

**Triggering:**
- `_triggerInstructionsIfNeeded()` called after state updates
- Checks `showInstructions` flag from game state
- Checks game phase and player status
- Shows appropriate instruction
- Respects "don't show again" flags

**Instruction Keys:**
- `initial`: Initial game instructions
- `draw_card`: How to draw a card
- `play_card`: How to play a card
- `queen_peek`: Queen power instructions
- `jack_swap`: Jack power instructions
- etc.

### Messages System

**Purpose**: Displays session and room messages, including game end modals.

**Structure:**
```dart
'messages': {
  'session': List<Message>,  // Session-level messages
  'rooms': Map<String, List<Message>>,  // Room-specific messages
  'isVisible': bool,  // Modal visibility
  'title': String?,  // Modal title
  'content': String?,  // Modal content
  'type': String?,  // 'info' | 'success' | 'warning' | 'error'
  'showCloseButton': bool,
  'autoClose': bool,
  'autoCloseDelay': int,
}
```

**Usage:**
- `_addSessionMessage()` adds messages
- Game end messages show modal automatically (`showModal: true`)
- Normal messages added to session list (no modal)
- Modal controlled by `isVisible` flag

---

## Practice vs Multiplayer Differences

### Practice Mode

**State Storage:**
- State stored locally (no backend sync)
- Uses `practice_session_<userId>` as player ID
- Practice bridge handles events locally

**Transport:**
- Events routed to `PracticeModeBridge`
- No WebSocket communication
- Same state structure, different transport

**State Updates:**
- Same update flow (event → handler → state update)
- Events generated locally by practice bridge
- No network latency

### Multiplayer Mode

**State Storage:**
- State synced via WebSocket
- Uses `sessionId` as player ID
- Backend is authoritative

**Transport:**
- Events routed to `WebSocketManager`
- Real-time synchronization
- Network latency considerations

**State Updates:**
- Same update flow
- Events received from backend
- All players receive same `game_state_updated` events

### Key Differences

| Feature | Practice Mode | Multiplayer Mode |
|---------|--------------|------------------|
| Player ID | `practice_session_<userId>` | `sessionId` |
| Transport | `PracticeModeBridge` | `WebSocketManager` |
| State Sync | Local only | WebSocket sync |
| Backend | Local (Flutter) | Remote (Dart backend) |
| Latency | None | Network latency |
| Authority | Local | Backend |

---

## State Cleanup

### When Player Leaves

**Method: `DutchGameHelpers.removePlayerFromGame()`**

**Clears:**
- Game from `games` map
- `currentGameId`, `currentRoomId`
- `isInRoom`, `isRoomOwner`
- All widget-specific state:
  - `myHandCards`, `myDrawnCard`
  - `discardPile`, `drawPileCount`
  - `turn_events`
  - Widget slices
- Round information:
  - `roundNumber`, `turnNumber`
  - `currentPlayer`, `currentPlayerStatus`

**State Update:**
```dart
DutchGameHelpers.updateUIState({
  'games': updatedGamesMap,  // Game removed
  'currentGameId': '',
  'currentRoomId': '',
  'isInRoom': false,
  'isRoomOwner': false,
  'isGameActive': false,
  'gamePhase': 'waiting',
  // ... all widget state cleared
});
```

### When Room Closes

**Backend:**
- `room_closed` hook triggered
- `DutchGameRound.dispose()` called
- Game state cleared

**Frontend:**
- May not receive `room_closed` event (if disconnected)
- State cleanup happens on next navigation or app restart
- Should handle stale state gracefully

### State Cleanup Best Practices

1. **Always clear state when leaving game**
   - Prevents stale state
   - Ensures clean UI

2. **Handle disconnects gracefully**
   - Check connection status
   - Clear state on disconnect
   - Rejoin or navigate to lobby

3. **Validate state before use**
   - Check if game exists in games map
   - Check if currentGameId is valid
   - Handle missing data gracefully

---

## Modifying State Structure

### ⚠️ Required Steps When Adding/Removing State Fields

When modifying the state structure (adding or removing fields in state slices or main state), follow these steps:

1. **Update Slice Computation** (`cleco_game_state_updater.dart`):
   - Modify the appropriate `_compute*Slice()` method
   - Add/remove fields in the returned map
   - Ensure field values are extracted from SSOT (`game_state`)

2. **Update State Validator Schema** (`state_queue_validator.dart`):
   - Locate the field spec in `_stateSchema` (e.g., `'centerBoard'`, `'myHand'`, etc.)
   - Update the `defaultValue` map to include/exclude the new field
   - Ensure default value matches the type returned by slice computation

3. **Update Widget Dependencies** (if needed):
   - Check `_widgetDependencies` in `cleco_game_state_updater.dart`
   - Add field to dependency set if it should trigger slice recomputation
   - Example: If field is part of `games`, it's already covered

4. **Update Widgets** (if needed):
   - Update widgets that read from the slice to use the new field
   - Ensure proper null handling and default values

5. **Test**:
   - Verify state updates work correctly
   - Test that widgets can read the new field
   - Check that validation doesn't reject valid updates

**Example Workflow**:
```
Adding matchPot to centerBoard slice:
1. Update _computeCenterBoardSlice() in dutch_game_state_updater.dart → Add 'matchPot': matchPot
2. Update state_queue_validator.dart → Add 'matchPot': 0 to centerBoard defaultValue
3. Create/update widget → Read matchPot from centerBoard slice
4. Test → Verify pot displays correctly during gameplay
```

**Common Mistakes to Avoid**:
- ❌ Adding field to slice but forgetting validator → Validation errors
- ❌ Adding field to validator but not slice → Field always has default value
- ❌ Mismatched field names → Field not found in slice
- ❌ Wrong default value type → Type validation errors

**Note**: When modifying state structure, update both Flutter and Dart backend validators:
- Flutter: `flutter_base_05/lib/modules/dutch_game/utils/state_queue_validator.dart`
- Dart Backend: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/state_queue_validator.dart`

---

## WebSocket Connection and Authentication

### Connection Behavior

WebSocket connections are **not** automatically established when entering the lobby screen. Instead, connections are attempted **on-demand** when game actions are initiated:

1. **Random Join**: When user clicks "Play Dutch" or "Play Dutch: Clear and Collect" buttons
2. **Create Room**: When user creates a new game room
3. **Join Room**: When user joins an existing room

### ensureWebSocketReady() Helper

**Location**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`

**Purpose**: Centralized WebSocket readiness check before game actions

**Behavior**:
1. Checks login status from `StateManager`
2. Initializes WebSocket if not initialized
3. Connects WebSocket if not connected
4. Navigates to account screen if login/connection fails
5. Returns `true` if ready, `false` otherwise

**Usage**:
```dart
final isReady = await DutchGameHelpers.ensureWebSocketReady();
if (!isReady) {
  // Navigation to account screen already handled
  return;
}
// Proceed with game action
```

### Navigation to Account Screen

**Important**: Navigation to the account screen is handled by the **Dutch game module**, not the WebSocket module.

**Triggered when**:
- User is not logged in
- WebSocket initialization fails
- WebSocket connection fails

**Method**: `DutchGameHelpers.navigateToAccountScreen(reason, message)`

**Location**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`

**Implementation**:
- Uses `NavigationManager` to navigate to `/account`
- Passes `auth_reason` and `auth_message` as route parameters
- Handles errors gracefully with logging

## Related Files

### Backend (Dart)
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` - Game logic and state generation
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart` - Game state callback implementation
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/dutch_game_main.dart` - Event handlers and hooks
- `dart_bkend_base_01/lib/server/websocket_server.dart` - WebSocket event broadcasting

### Frontend (Flutter)
- `flutter_base_05/lib/core/managers/state_manager.dart` - Core state management
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart` - State updater and slice computation
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart` - Event processing and state updates
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_manager.dart` - Event routing
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart` - Helper methods (including `ensureWebSocketReady()` and `navigateToAccountScreen()`)
- `flutter_base_05/lib/modules/dutch_game/utils/state_queue_validator.dart` - State validation
- `flutter_base_05/lib/modules/dutch_game/managers/player_action.dart` - Player action execution
- `flutter_base_05/lib/modules/dutch_game/managers/validated_event_emitter.dart` - Event emission
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/*.dart` - Game widgets (read from state)

---

## Future Improvements

1. **Immutable State Migration**
   - Migrate from map-based state to immutable state objects
   - Better type safety
   - Easier equality checks

2. **State Persistence**
   - Persist game state to local storage
   - Restore state on app restart
   - Handle reconnection scenarios

3. **Optimistic Updates**
   - Add optimistic updates for better UX
   - Rollback on error
   - Conflict resolution

4. **State Validation**
   - Enhanced state validation
   - Schema validation
   - Type checking

5. **Performance Optimization**
   - Reduce unnecessary rebuilds
   - Optimize slice computation
   - Cache computed values

6. **State Debugging**
   - State inspector tool
   - State change logging
   - Time-travel debugging

---

**Last Updated**: 2025-01-XX
