# Recall Game State System

## Overview

The Recall game uses a **multi-layered state management system** with a **Single Source of Truth (SSOT)** architecture. The system ensures consistent state across both practice and multiplayer modes, with validation, queuing, and computed widget slices for efficient UI updates.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    UI Layer (Widgets)                        │
│  - MyHandWidget, OpponentsPanelWidget, CenterBoardWidget    │
│  - Subscribe to widget slices via ListenableBuilder         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Widget Slice Layer (Computed)                   │
│  - myHand, opponentsPanel, centerBoard, gameInfo            │
│  - Computed from SSOT state on-demand                       │
│  - Only recomputed when dependencies change                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│            Flutter StateManager (Module State)               │
│  - recall_game module state                                 │
│  - Contains games map, currentGameId, widget slices         │
│  - Notifies listeners on updates                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         State Update Pipeline (Validation & Queue)           │
│  - StateQueueValidator: Validates and queues updates        │
│  - RecallGameStateUpdater: Applies updates & computes slices│
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Backend State Store (SSOT - Per Room)                │
│  - GameStateStore: In-memory state per roomId               │
│  - Contains game_state with players, piles, etc.            │
│  - Updated by RecallGameRound (game logic)                  │
└─────────────────────────────────────────────────────────────┘
```

## Single Source of Truth (SSOT)

The **Single Source of Truth** for game state is the `GameStateStore`, which stores state per room/game:

**Location**: `backend_core/services/game_state_store.dart`

```dart
class GameStateStore {
  final Map<String, Map<String, dynamic>> _roomIdToState = {};
  
  Map<String, dynamic> getGameState(String roomId) {
    return ensure(roomId)['game_state'] as Map<String, dynamic>;
  }
  
  void setGameState(String roomId, Map<String, dynamic> gameState) {
    final state = ensure(roomId);
    state['game_state'] = gameState;
  }
}
```

### SSOT Structure

The SSOT state structure follows this hierarchy:

```
GameStateStore[roomId]
└── game_state (Map<String, dynamic>)
    ├── players (List<Map>)          # All players with hands, status, etc.
    ├── currentPlayer (Map)          # Current player whose turn it is
    ├── drawPile (List)              # Draw pile cards
    ├── discardPile (List)           # Discard pile cards
    ├── phase (String)               # Game phase (playing, waiting, etc.)
    ├── originalDeck (List)          # Full card data for lookups
    ├── turn_events (List)           # Turn events for animations
    └── ... (other game state fields)
```

**Key Principle**: All game logic reads from and writes to `GameStateStore`. The Flutter `StateManager` is a **derived view** of this SSOT, computed and synchronized via state updates.

## State Flow: Backend to Frontend

### Complete State Update Flow

```
1. Game Logic (RecallGameRound)
   └─> Updates GameStateStore via GameStateCallback
       └─> onGameStateChanged({ 'games': {...}, 'turn_events': [...] })

2. GameStateCallback (_ServerGameStateCallbackImpl)
   └─> Validates update via StateQueueValidator
       └─> enqueueUpdate(updates)

3. StateQueueValidator
   └─> Validates against schema
   └─> Queues update
   └─> Processes queue sequentially
       └─> Calls update handler with validated updates

4. Update Handler (Flutter: RecallGameStateUpdater, Backend: _ServerGameStateCallbackImpl)
   └─> Merges updates into GameStateStore (backend) or StateManager (Flutter)
   └─> Broadcasts state update (backend only)

5. State Broadcast (Backend only)
   └─> server.broadcastToRoom() → WebSocket/PracticeBridge
       └─> Routes to RecallEventManager

6. RecallEventManager (Flutter)
   └─> handleGameStateUpdated()
       └─> Updates games map in StateManager
       └─> Calls _syncWidgetStatesFromGameState()

7. Widget State Sync
   └─> Extracts player data from SSOT
   └─> Updates games map with widget-specific data
   └─> Triggers widget slice recomputation

8. Widget Slice Computation
   └─> _updateWidgetSlices() checks dependencies
   └─> Recomputes affected slices (myHand, opponentsPanel, etc.)
   └─> Updates StateManager with new slices

9. UI Update
   └─> StateManager notifies listeners
   └─> Widgets rebuild with new slice data
```

## State Update Process

### 1. State Update Initiation

State updates can be initiated from:

**A. Game Logic (Backend Core)**
```dart
// In RecallGameRound
_stateCallback.onGameStateChanged({
  'games': currentGames,
  'discardPile': updatedDiscardPile,
  'turn_events': turnEvents,
});
```

**B. Event Handlers (Flutter)**
```dart
// In RecallEventHandlerCallbacks
_updateMainGameState({
  'playerStatus': status,
  'isMyTurn': isCurrentPlayer,
});
```

### 2. State Validation

All state updates go through `StateQueueValidator`:

**Location**: `backend_core/utils/state_queue_validator.dart`

```dart
class StateQueueValidator {
  void enqueueUpdate(Map<String, dynamic> update) {
    _updateQueue.add(update);
    if (!_isProcessing) {
      processQueue();
    }
  }
  
  Future<void> processQueue() async {
    while (_updateQueue.isNotEmpty) {
      final update = _updateQueue.removeAt(0);
      final validatedUpdate = validateUpdate(update);  // Validates against schema
      _updateHandler!(validatedUpdate);  // Calls registered handler
    }
  }
}
```

**Validation Schema**: The validator uses a comprehensive schema defined in `_stateSchema` that validates:
- Field types (String, int, bool, Map, List)
- Required vs optional fields
- Allowed values (for enums like playerStatus)
- Min/max values (for numeric fields)
- Default values

### 3. State Application

After validation, updates are applied:

**Backend (GameStateStore)**:
```dart
void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
  // Merge into state root
  _store.mergeRoot(roomId, validatedUpdates);
  
  // Broadcast to clients
  server.broadcastToRoom(roomId, {
    'event': 'game_state_updated',
    'game_state': gameState,
    'turn_events': turnEvents,
  });
}
```

**Flutter (StateManager)**:
```dart
void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
  // Merge with current state
  final updatedState = Map<String, dynamic>.from(currentState);
  validatedUpdates.forEach((k, v) => updatedState[k] = v);
  
  // Recompute widget slices
  final updatedStateWithSlices = _updateWidgetSlices(
    currentState,
    updatedState,
    validatedUpdates.keys.toSet(),
  );
  
  // Update StateManager
  _stateManager.updateModuleState('recall_game', updatedStateWithSlices);
}
```

## Widget Slices

Widget slices are **computed views** of the SSOT state, optimized for specific widgets. They are only recomputed when their dependencies change.

### Slice Dependencies

Each widget slice declares its dependencies:

```dart
static const Map<String, Set<String>> _widgetDependencies = {
  'actionBar': {'currentGameId', 'games', 'isRoomOwner', 'isGameActive', 'isMyTurn'},
  'statusBar': {'currentGameId', 'games', 'gamePhase', 'isGameActive'},
  'myHand': {'currentGameId', 'games', 'isMyTurn', 'turn_events'},
  'centerBoard': {'currentGameId', 'games', 'gamePhase', 'isGameActive', 'discardPile', 'drawPile'},
  'opponentsPanel': {'currentGameId', 'games', 'currentPlayer', 'turn_events'},
  'gameInfo': {'currentGameId', 'games', 'gamePhase', 'isGameActive'},
};
```

### Slice Computation

Slices are computed from the SSOT state:

**Example: myHand Slice**
```dart
Map<String, dynamic> _computeMyHandSlice(Map<String, dynamic> state) {
  final currentGameId = state['currentGameId']?.toString() ?? '';
  final games = state['games'] as Map<String, dynamic>? ?? {};
  final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
  
  // Get hand from games map (derived from SSOT)
  final hand = currentGame['myHandCards'] ?? [];
  
  // Get turn_events for animations
  final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
  
  // Derive player status from SSOT
  final playerStatus = _getCurrentUserStatus(state);
  
  return {
    'cards': hand,
    'selectedIndex': currentGame['selectedCardIndex'] ?? -1,
    'canSelectCards': isMyTurn && canPlayCard,
    'turn_events': turnEvents,
    'playerStatus': playerStatus,
  };
}
```

**Key Principle**: Slices read from `games[currentGameId].gameData.game_state` (the SSOT), not from cached values. This ensures consistency.

### Slice Update Trigger

Slices are recomputed when their dependencies change:

```dart
Map<String, dynamic> _updateWidgetSlices(
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

## State Structure

### Flutter StateManager Structure

The `recall_game` module state in `StateManager`:

```dart
{
  // Connection state
  'isLoading': bool,
  'isConnected': bool,
  'currentRoomId': String,
  'isInRoom': bool,
  
  // Game context
  'currentGameId': String,
  'games': {
    'room_xxx': {
      'gameData': {
        'game_id': 'room_xxx',
        'game_state': {  // SSOT - synced from GameStateStore
          'players': [...],
          'currentPlayer': {...},
          'drawPile': [...],
          'discardPile': [...],
          'phase': 'playing',
          // ... other game state
        },
        'owner_id': 'user_xxx',
      },
      'myHandCards': [...],      // Widget-specific data
      'isMyTurn': bool,
      'selectedCardIndex': int,
      // ... other widget data
    }
  },
  
  // Widget slices (computed)
  'myHand': {
    'cards': [...],
    'selectedIndex': int,
    'canSelectCards': bool,
    'turn_events': [...],
    'playerStatus': String,
  },
  'opponentsPanel': {
    'opponents': [...],
    'currentTurnIndex': int,
    'turn_events': [...],
    'currentPlayerStatus': String,
  },
  'centerBoard': {
    'drawPileCount': int,
    'topDiscard': Map?,
    'topDraw': Map?,
    'canDrawFromDeck': bool,
    'canTakeFromDiscard': bool,
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
  
  // Main state fields
  'gamePhase': String,
  'isMyTurn': bool,
  'playerStatus': String,
  'turn_events': List,  // Current turn events for animations
  'myScore': int,
  'myDrawnCard': Map?,
  'myCardsToPeek': List,
  
  // Metadata
  'lastUpdated': String,
}
```

### Games Map Structure

The `games` map is the bridge between SSOT and widget slices:

```dart
games: {
  'room_xxx': {
    'gameData': {
      'game_id': 'room_xxx',
      'game_state': {  // SSOT - exact copy from GameStateStore
        'players': [...],
        'currentPlayer': {...},
        'drawPile': [...],
        'discardPile': [...],
        'phase': 'playing',
      },
      'owner_id': 'user_xxx',
    },
    // Widget-specific computed fields (derived from game_state)
    'myHandCards': [...],           // Extracted from player hand
    'isMyTurn': bool,               // Computed from currentPlayer
    'selectedCardIndex': int,       // UI state
    'discardPileCount': int,        // Computed from discardPile
    'drawPileCount': int,           // Computed from drawPile
  }
}
```

## State Synchronization

### Backend to Frontend Sync

When the backend updates `GameStateStore`, it broadcasts the update:

**Backend (GameStateCallback)**:
```dart
void onGameStateChanged(Map<String, dynamic> updates) {
  // Validate and queue update
  _validator.enqueueUpdate(updates);
  
  // After validation, merge into GameStateStore
  _store.mergeRoot(roomId, validatedUpdates);
  
  // Broadcast to clients
  server.broadcastToRoom(roomId, {
    'event': 'game_state_updated',
    'game_state': gameState,  // Full SSOT state
    'turn_events': turnEvents,
  });
}
```

**Flutter (RecallEventManager)**:
```dart
static void handleGameStateUpdated(Map<String, dynamic> data) {
  final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
  final turnEvents = data['turn_events'] as List<dynamic>? ?? [];
  
  // Update games map with SSOT state
  _updateGameData(gameId, {
    'game_state': gameState,  // Store SSOT
  });
  
  // Sync widget states from SSOT
  _syncWidgetStatesFromGameState(gameId, gameState, turnEvents: turnEvents);
}
```

### Widget State Sync

The `_syncWidgetStatesFromGameState` method extracts widget-specific data from SSOT:

```dart
static void _syncWidgetStatesFromGameState(String gameId, Map<String, dynamic> gameState, {List<dynamic>? turnEvents}) {
  // Get current user ID
  final currentUserId = getCurrentUserId();
  
  // Find player in SSOT
  final players = gameState['players'] as List<dynamic>? ?? [];
  final myPlayer = players.firstWhere((p) => p['id'] == currentUserId);
  
  // Extract widget-specific data
  final hand = myPlayer['hand'] as List<dynamic>? ?? [];
  final drawnCard = myPlayer['drawnCard'] as Map<String, dynamic>?;
  final status = myPlayer['status']?.toString() ?? 'unknown';
  
  // Update games map with widget data
  _updateGameInMap(gameId, {
    'myHandCards': hand,        // Extracted from SSOT
    'myDrawnCard': drawnCard,   // Extracted from SSOT
    'isMyTurn': isCurrentPlayer, // Computed from SSOT
    'turn_events': turnEvents,   // For animations
  });
  
  // Update main state
  _updateMainGameState({
    'playerStatus': status,      // From SSOT
    'myScore': score,            // From SSOT
    'isMyTurn': isCurrentPlayer, // Computed from SSOT
  });
}
```

## State Update Queue

The `StateQueueValidator` ensures state updates are processed **sequentially** and **validated**:

### Queue Processing

```dart
class StateQueueValidator {
  final List<Map<String, dynamic>> _updateQueue = [];
  bool _isProcessing = false;
  
  void enqueueUpdate(Map<String, dynamic> update) {
    _updateQueue.add(update);
    if (!_isProcessing) {
      processQueue();  // Start processing if not already processing
    }
  }
  
  Future<void> processQueue() async {
    _isProcessing = true;
    try {
      while (_updateQueue.isNotEmpty) {
        final update = _updateQueue.removeAt(0);
        final validatedUpdate = validateUpdate(update);  // Validate
        _updateHandler!(validatedUpdate);  // Apply
      }
    } finally {
      _isProcessing = false;
    }
  }
}
```

### Benefits

1. **Sequential Processing**: Prevents race conditions
2. **Validation**: Ensures state consistency
3. **Error Handling**: Invalid updates are logged and skipped
4. **Atomic Updates**: Each update is fully processed before next

## Turn Events

Turn events are special state fields used for **card animations**. They track card actions (draw, play, reposition) within a single turn.

### Turn Event Structure

```dart
turn_events: [
  {
    'cardId': 'card_room_xxx_ace_spades_0_1234567890',
    'actionType': 'draw',  // 'draw', 'play', 'reposition', 'collect'
    'timestamp': '2025-11-28T17:27:57.257Z',
  },
  {
    'cardId': 'card_room_xxx_king_hearts_0_0987654321',
    'actionType': 'play',
    'timestamp': '2025-11-28T17:27:57.300Z',
  },
]
```

### Turn Event Lifecycle

1. **Creation**: Turn events are created in `RecallGameRound` when actions occur:
   ```dart
   final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
     ..add(_createTurnEvent(cardId, 'play'));
   ```

2. **Inclusion in State Update**: Turn events are included in state updates:
   ```dart
   _stateCallback.onGameStateChanged({
     'games': currentGames,
     'turn_events': turnEvents,  // Included for animations
   });
   ```

3. **Broadcast**: Turn events are broadcast with game state:
   ```dart
   server.broadcastToRoom(roomId, {
     'event': 'game_state_updated',
     'game_state': gameState,
     'turn_events': turnEvents,  // Included in broadcast
   });
   ```

4. **Widget Slice Inclusion**: Turn events are included in widget slices:
   ```dart
   'myHand': {
     'cards': [...],
     'turn_events': turnEvents,  // For card animations
   }
   ```

5. **Animation Trigger**: Widgets use turn events to trigger animations:
   ```dart
   // In MyHandWidget
   final turnEvents = myHandSlice['turn_events'] as List<dynamic>? ?? [];
   for (final event in turnEvents) {
     if (event['cardId'] == cardId) {
       // Trigger animation based on actionType
       _animateCard(event['actionType']);
     }
   }
   ```

6. **Clear on Turn End**: Turn events are cleared when turn ends:
   ```dart
   // In _moveToNextPlayer
   _stateCallback.onGameStateChanged({
     'games': currentGames,
     'currentPlayer': nextPlayer,
     'turn_events': [],  // Clear for new turn
   });
   ```

## Key Components

### 1. GameStateStore (SSOT)

**Location**: `backend_core/services/game_state_store.dart`

In-memory state storage per room. This is the **authoritative source** for game state.

```dart
class GameStateStore {
  final Map<String, Map<String, dynamic>> _roomIdToState = {};
  
  Map<String, dynamic> getGameState(String roomId);
  void setGameState(String roomId, Map<String, dynamic> gameState);
  void mergeRoot(String roomId, Map<String, dynamic> updates);
}
```

### 2. StateQueueValidator

**Location**: `backend_core/utils/state_queue_validator.dart`

Validates and queues state updates for sequential processing.

```dart
class StateQueueValidator {
  void enqueueUpdate(Map<String, dynamic> update);
  Future<void> processQueue();
  Map<String, dynamic> validateUpdate(Map<String, dynamic> update);
}
```

### 3. RecallGameStateUpdater

**Location**: `managers/recall_game_state_updater.dart`

Applies validated updates to Flutter `StateManager` and computes widget slices.

```dart
class RecallGameStateUpdater {
  void updateState(Map<String, dynamic> updates);
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates);
  Map<String, dynamic> _updateWidgetSlices(...);
}
```

### 4. RecallEventHandlerCallbacks

**Location**: `managers/recall_event_handler_callbacks.dart`

Handles incoming state updates from backend and syncs to Flutter state.

```dart
class RecallEventHandlerCallbacks {
  static void handleGameStateUpdated(Map<String, dynamic> data);
  static void _syncWidgetStatesFromGameState(String gameId, Map<String, dynamic> gameState);
}
```

### 5. GameStateCallback

**Location**: `backend_core/shared_logic/game_state_callback.dart`

Interface for game logic to communicate state changes.

```dart
abstract class GameStateCallback {
  void onGameStateChanged(Map<String, dynamic> updates);
  void onPlayerStatusChanged(String status, {String? playerId, ...});
  void onActionError(String message, {Map<String, dynamic>? data});
}
```

## State Update Examples

### Example 1: Playing a Card

```
1. PlayerAction.playCard() → ValidatedEventEmitter.emit('play_card')
2. Event routed to backend → GameEventCoordinator.handle('play_card')
3. RecallGameRound.handlePlayCard()
   └─> Updates player hand in GameStateStore
   └─> Creates turn events: [draw, play, reposition]
   └─> Calls onGameStateChanged({
         'games': {...},  // Updated hand
         'discardPile': [...],  // Card added
         'turn_events': [...],  // Animation events
       })
4. StateQueueValidator validates and queues update
5. Update applied to GameStateStore
6. State broadcast to clients (game_state_updated event)
7. Flutter: RecallEventManager.handleGameStateUpdated()
   └─> Updates games map with SSOT state
   └─> Calls _syncWidgetStatesFromGameState()
       └─> Extracts myHandCards from SSOT
       └─> Updates games map
8. Widget slice recomputation triggered
   └─> _computeMyHandSlice() reads from games map
   └─> Includes turn_events for animations
9. StateManager updated with new slice
10. MyHandWidget rebuilds with new cards and animations
```

### Example 2: Turn Progression

```
1. RecallGameRound._moveToNextPlayer()
   └─> Updates currentPlayer in GameStateStore
   └─> Updates player statuses
   └─> Calls onGameStateChanged({
         'games': {...},  // Updated currentPlayer
         'currentPlayer': nextPlayer,
         'turn_events': [],  // Clear for new turn
       })
2. StateQueueValidator processes update
3. State broadcast to clients
4. Flutter: handleGameStateUpdated()
   └─> Updates games map
   └─> Syncs widget states
5. Widget slices recomputed
   └─> opponentsPanel: currentTurnIndex updated
   └─> myHand: isMyTurn updated
   └─> statusBar: currentPhase updated
6. UI updates to show new turn
```

## State Consistency Guarantees

### 1. SSOT Principle

- All game logic reads from/writes to `GameStateStore`
- Flutter `StateManager` is a **derived view** of SSOT
- Widget slices are **computed** from SSOT, never cached

### 2. Sequential Processing

- `StateQueueValidator` ensures updates are processed sequentially
- Prevents race conditions and inconsistent state

### 3. Validation

- All updates validated against schema before application
- Invalid updates are rejected and logged

### 4. Atomic Updates

- Each state update is fully processed before next
- Widget slices recomputed atomically with state update

### 5. Dependency Tracking

- Widget slices only recompute when dependencies change
- Prevents unnecessary recomputation

## Best Practices

### 1. Always Read from SSOT

When computing widget slices, always read from the SSOT:

```dart
// ✅ CORRECT: Read from SSOT
final gameState = games[currentGameId]['gameData']['game_state'];
final players = gameState['players'];

// ❌ INCORRECT: Use cached value
final players = cachedPlayers;  // May be stale
```

### 2. Update SSOT First

Always update `GameStateStore` first, then broadcast:

```dart
// ✅ CORRECT: Update SSOT, then broadcast
_store.setGameState(roomId, gameState);
server.broadcastToRoom(roomId, {'game_state': gameState});

// ❌ INCORRECT: Broadcast before updating SSOT
server.broadcastToRoom(roomId, {'game_state': gameState});
_store.setGameState(roomId, gameState);  // Too late
```

### 3. Include Turn Events

Always include `turn_events` in state updates for animations:

```dart
_stateCallback.onGameStateChanged({
  'games': currentGames,
  'turn_events': turnEvents,  // Required for animations
});
```

### 4. Clear Turn Events on Turn End

Clear `turn_events` when starting a new turn:

```dart
_stateCallback.onGameStateChanged({
  'games': currentGames,
  'currentPlayer': nextPlayer,
  'turn_events': [],  // Clear for new turn
});
```

### 5. Use Helper Methods

Use helper methods for state updates:

```dart
// ✅ CORRECT: Use helper
_updateMainGameState({'playerStatus': status});

// ❌ INCORRECT: Direct StateManager access
StateManager().updateModuleState('recall_game', {...});
```

## State Schema

The state schema is defined in `StateQueueValidator._stateSchema` and includes validation for:

- **User Context**: userId, username, playerId, isRoomOwner, isMyTurn
- **Room Context**: currentRoomId, permission, currentSize, maxSize, minSize
- **Game Context**: currentGameId, games, gamePhase, gameStatus
- **Player State**: playerStatus, myScore, myDrawnCard, myCardsToPeek
- **Widget Slices**: actionBar, statusBar, myHand, centerBoard, opponentsPanel, gameInfo
- **Turn Events**: turn_events (List of event maps)
- **Messages**: messages, actionError
- **UI State**: selectedCard, selectedCardIndex

Each field has:
- Type validation
- Required/optional flag
- Default values (where applicable)
- Allowed values (for enums)
- Min/max values (for numeric fields)

## File Locations

### Core State Components
- `backend_core/services/game_state_store.dart` - SSOT storage
- `backend_core/utils/state_queue_validator.dart` - Validation and queuing
- `backend_core/shared_logic/game_state_callback.dart` - Callback interface

### Flutter State Management
- `managers/recall_game_state_updater.dart` - State updater and slice computation
- `managers/recall_event_handler_callbacks.dart` - Event handlers and state sync
- `managers/recall_event_manager.dart` - Event manager

### State Models
- `models/state/recall_game_state.dart` - Immutable state model (future migration)
- `models/state/games_map.dart` - Games map model
- `models/state/my_hand_state.dart` - My hand slice model
- `models/state/center_board_state.dart` - Center board slice model
- `models/state/opponents_panel_state.dart` - Opponents panel slice model

### Core StateManager
- `core/managers/state_manager.dart` - Flutter StateManager (ChangeNotifier-based)

