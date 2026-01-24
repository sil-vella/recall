# Draw Card - Complete Game State Update Flow

This document traces the **entire flow of game state updates** during a draw card action, from initial state through all broadcasts to final widget updates.

## Overview

The draw card action uses a **two-step broadcast approach**:
1. **STEP 1**: Broadcast ID-only `drawnCard` to all players EXCEPT the drawing player
2. **STEP 2**: Send full `drawnCard` details ONLY to the drawing player (human only)

This ensures:
- All players see that a card was drawn (without revealing details)
- Only the drawing player sees the full card data
- Action markers (`action` + `actionData`) are included for potential animation/UI systems

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: INITIAL STATE (Before Draw)                                    │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          │ Player clicks "Draw Card" or CPU auto-draws
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: DRAW CARD PROCESSING                                           │
│ Location: dutch_game_round.dart → handleDrawCard()                     │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          ├─► Validate source (deck/discard)
                          ├─► Get game state from games map
                          ├─► Draw card from pile
                          ├─► Add card to player's hand (ID-only)
                          ├─► Create turn event
                          ├─► Set action marker
                          └─► Prepare state for broadcast
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: STEP 1 - BROADCAST TO ALL (Except Drawing Player)              │
│ Location: Line 1755-1766                                                │
│ Method: broadcastGameStateExcept(actualPlayerId, {...})                 │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          ├─► State includes:
                          │   - games[gameId].gameData.game_state.players[]
                          │     with player['drawnCard'] = ID-only
                          │   - player['action'] = 'drawn_card'
                          │   - player['actionData'] = {'cardId': '...'}
                          │   - turn_events = [{'cardId': '...', 'actionType': 'draw'}]
                          │
                          └─► Sent via WebSocket: 'game_state_updated'
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: STEP 2 - SEND TO DRAWING PLAYER (Human Only)                 │
│ Location: Line 1785-1788                                                 │
│ Method: sendGameStateToPlayer(actualPlayerId, {...})                    │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          ├─► State includes:
                          │   - games[gameId].gameData.game_state.players[]
                          │     with player['drawnCard'] = FULL DATA
                          │   - player['status'] = 'playing_card'
                          │   - player['action'] = 'drawn_card' (cleared after)
                          │   - turn_events = [{'cardId': '...', 'actionType': 'draw'}]
                          │
                          └─► Sent via WebSocket: 'game_state_updated'
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 5: FRONTEND RECEIVES STATE                                        │
│ Location: dutch_event_handler_callbacks.dart → handleGameStateUpdated() │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          ├─► Extracts: game_id, game_state, turn_events
                          ├─► Updates games map in StateManager
                          └─► Triggers state updater
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 6: STATE UPDATER PROCESSES                                         │
│ Location: dutch_game_state_updater.dart → _applyValidatedUpdates()     │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          ├─► Merges updates with current state
                          ├─► Recomputes widget slices:
                          │   - myHand
                          │   - centerBoard
                          │   - opponentsPanel
                          └─► Updates StateManager
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 7: WIDGETS REBUILD                                                │
│ Location: Various widgets listening to StateManager                     │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          └─► UI updates with new card positions
```

---

## Detailed State Structures

### PHASE 1: Initial State (Before Draw)

```dart
// StateManager state structure
{
  'currentGameId': 'game_123',
  'games': {
    'game_123': {
      'game_id': 'game_123',
      'gameData': {
        'game_state': {
          'players': [
            {
              'id': 'player_1',
              'hand': [
                {'cardId': 'card_1', 'suit': '?', 'rank': '?', 'points': 0},
                {'cardId': 'card_2', 'suit': '?', 'rank': '?', 'points': 0},
                // ... more cards
              ],
              'status': 'drawing_card',
              'drawnCard': null,  // No drawn card yet
              'action': null,      // No action yet
              'actionData': null,  // No action data yet
            },
            // ... other players
          ],
          'drawPile': [
            {'cardId': 'card_10', 'suit': '?', 'rank': '?', 'points': 0},
            {'cardId': 'card_11', 'suit': '?', 'rank': '?', 'points': 0},
            // ... more cards (ID-only format)
          ],
          'discardPile': [
            {'cardId': 'card_20', 'rank': 'King', 'suit': 'Spades', 'points': 10},
            // ... more cards (full data for top card)
          ],
        },
      },
    },
  },
  'myHand': {
    'cards': [...],  // Widget slice
    'selectedIndex': -1,
    'playerStatus': 'drawing_card',
  },
  'centerBoard': {
    'drawPileCount': 15,
    'topDiscard': {...},
    'topDraw': null,
  },
  'opponentsPanel': {
    'opponents': [...],
    'currentTurnIndex': 0,
  },
}
```

---

### PHASE 2: During Draw Processing

**Location**: `dutch_game_round.dart` → `handleDrawCard()` (lines 1439-1819)

#### Step 2a: Draw Card from Pile
```dart
// Line 1559: Remove card from draw pile
final idOnlyCard = currentDrawPile.removeLast(); // e.g., {'cardId': 'card_10', ...}

// Line 1568: Convert to full card data
drawnCard = _stateCallback.getCardById(gameState, idOnlyCard['cardId']);
// Result: {'cardId': 'card_10', 'rank': 'Queen', 'suit': 'Hearts', 'points': 10, ...}
```

#### Step 2b: Add to Hand
```dart
// Line 1623-1633: Create ID-only card for hand
final idOnlyCard = {
  'cardId': drawnCard['cardId'],  // 'card_10'
  'suit': '?',      // Face-down: hide suit
  'rank': '?',      // Face-down: hide rank
  'points': 0,      // Face-down: hide points
};

// Line 1633: Add to END of hand
hand.add(idOnlyCard);
```

#### Step 2c: Create Turn Event
```dart
// Line 1735-1736: Add turn event
final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
  ..add(_createTurnEvent(drawnCardId, 'draw'));

// Result: turnEvents = [
//   {'cardId': 'card_10', 'actionType': 'draw', ...}
// ]
```

#### Step 2d: Set Action Marker
```dart
// Line 1674-1676: Set action for animation system
player['action'] = 'drawn_card';
player['actionData'] = {'cardId': drawnCard['cardId']};

// Line 1672: Set ID-only drawnCard for initial broadcast
player['drawnCard'] = {
  'cardId': drawnCard['cardId'],  // 'card_10'
  'suit': '?',      // Hide suit
  'rank': '?',      // Hide rank
  'points': 0,      // Hide points
};
```

**State After Processing (Before Broadcast)**:
```dart
{
  'games': {
    'game_123': {
      'gameData': {
        'game_state': {
          'players': [
            {
              'id': 'player_1',
              'hand': [
                // ... existing cards
                {'cardId': 'card_10', 'suit': '?', 'rank': '?', 'points': 0}, // NEW
              ],
              'status': 'drawing_card',
              'drawnCard': {
                'cardId': 'card_10',
                'suit': '?',      // ID-only
                'rank': '?',      // ID-only
                'points': 0,      // ID-only
              },
              'action': 'drawn_card',           // NEW
              'actionData': {'cardId': 'card_10'}, // NEW
            },
          ],
          'drawPile': [
            // card_10 removed (was last item)
            {'cardId': 'card_11', ...},
            // ... remaining cards
          ],
        },
      },
    },
  },
  'turn_events': [
    {'cardId': 'card_10', 'actionType': 'draw', ...}
  ],
}
```

---

### PHASE 3: STEP 1 - Broadcast to All (Except Drawing Player)

**Location**: `dutch_game_round.dart` (lines 1755-1766)  
**Method**: `_stateCallback.broadcastGameStateExcept(actualPlayerId, {...})`

**Implementation**: `game_registry.dart` → `broadcastGameStateExcept()` (lines 179-251)

#### State Structure Sent:
```dart
{
  'games': {
    'game_123': {
      'gameData': {
        'game_state': {
          'players': [
            {
              'id': 'player_1',
              'hand': [
                // ... existing cards
                {'cardId': 'card_10', 'suit': '?', 'rank': '?', 'points': 0}, // NEW
              ],
              'status': 'drawing_card',
              'drawnCard': {
                'cardId': 'card_10',
                'suit': '?',      // ID-only (hidden from opponents)
                'rank': '?',      // ID-only
                'points': 0,      // ID-only
              },
              'action': 'drawn_card',           // Action marker
              'actionData': {'cardId': 'card_10'}, // Action data
            },
          ],
          'drawPile': [
            // card_10 removed
            {'cardId': 'card_11', ...},
          ],
        },
      },
    },
  },
  'turn_events': [
    {'cardId': 'card_10', 'actionType': 'draw', ...}
  ],
}
```

#### WebSocket Message Sent:
```json
{
  "event": "game_state_updated",
  "game_id": "game_123",
  "game_state": {
    "players": [
      {
        "id": "player_1",
        "hand": [...],
        "drawnCard": {
          "cardId": "card_10",
          "suit": "?",
          "rank": "?",
          "points": 0
        },
        "action": "drawn_card",
        "actionData": {"cardId": "card_10"}
      }
    ],
    "drawPile": [...],
    "discardPile": [...]
  },
  "turn_events": [
    {"cardId": "card_10", "actionType": "draw", ...}
  ],
  "owner_id": "player_1",
  "timestamp": "2026-01-24T10:30:00.000Z"
}
```

**Recipients**: All players EXCEPT `player_1` (the drawing player)

---

### PHASE 4: STEP 2 - Send to Drawing Player (Human Only)

**Location**: `dutch_game_round.dart` (lines 1774-1791)  
**Method**: `_stateCallback.sendGameStateToPlayer(actualPlayerId, {...})`

**Implementation**: `game_registry.dart` → `sendGameStateToPlayer()` (lines 83-152)

#### State Structure Sent:
```dart
{
  'games': {
    'game_123': {
      'gameData': {
        'game_state': {
          'players': [
            {
              'id': 'player_1',
              'hand': [
                // ... existing cards
                {'cardId': 'card_10', 'suit': '?', 'rank': '?', 'points': 0}, // NEW
              ],
              'status': 'playing_card',  // UPDATED
              'drawnCard': {
                'cardId': 'card_10',
                'rank': 'Queen',    // FULL DATA (revealed)
                'suit': 'Hearts',   // FULL DATA
                'points': 10,       // FULL DATA
                'specialPower': null,
                // ... full card data
              },
              'action': 'drawn_card',           // Will be cleared after
              'actionData': {'cardId': 'card_10'},
            },
          ],
        },
      },
    },
  },
  'turn_events': [
    {'cardId': 'card_10', 'actionType': 'draw', ...}
  ],
}
```

#### WebSocket Message Sent:
```json
{
  "event": "game_state_updated",
  "game_id": "game_123",
  "game_state": {
    "players": [
      {
        "id": "player_1",
        "hand": [...],
        "drawnCard": {
          "cardId": "card_10",
          "rank": "Queen",      // FULL DATA
          "suit": "Hearts",     // FULL DATA
          "points": 10,         // FULL DATA
          "specialPower": null
        },
        "status": "playing_card",
        "action": "drawn_card",
        "actionData": {"cardId": "card_10"}
      }
    ],
    "drawPile": [...],
    "discardPile": [...]
  },
  "turn_events": [
    {"cardId": "card_10", "actionType": "draw", ...}
  ],
  "owner_id": "player_1",
  "timestamp": "2026-01-24T10:30:01.000Z"
}
```

**Recipient**: ONLY `player_1` (the drawing player)

**After Sending**:
```dart
// Line 1791: Clear action immediately
_clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGames);
// Result: player['action'] = null, player['actionData'] = null
```

---

### PHASE 5: Frontend Receives State

**Location**: `dutch_event_handler_callbacks.dart` → `handleGameStateUpdated()` (lines 1245-1400+)

#### Processing Steps:

1. **Extract Data**:
```dart
final gameId = data['game_id']?.toString() ?? '';
final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
final turnEvents = data['turn_events'] as List<dynamic>? ?? [];
```

2. **Update Games Map**:
```dart
// Line 1302-1335: Get or create game in games map
final currentGames = _getCurrentGamesMap();
if (!currentGames.containsKey(gameId)) {
  _addGameToMap(gameId, {
    'game_id': gameId,
    'game_state': gameState,
    'owner_id': ownerId,
  });
} else {
  // Update existing game
  _updateGameInMap(gameId, {
    'game_state': gameState,
    'owner_id': ownerId,
  });
}
```

3. **Trigger State Update**:
```dart
// Line 1340+: Update StateManager
final stateUpdater = DutchGameStateUpdater.instance;
stateUpdater.updateState({
  'currentGameId': gameId,
  'games': currentGames,  // Updated games map
  'turn_events': turnEvents,
});
```

---

### PHASE 6: State Updater Processes

**Location**: `dutch_game_state_updater.dart` → `_applyValidatedUpdates()` (lines 180-348)

#### Processing Steps:

1. **Get Current State**:
```dart
final currentState = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
```

2. **Merge Updates**:
```dart
final newState = {
  ...currentState,
  ...convertedValidatedUpdates,  // New games map, turn_events, etc.
};
```

3. **Recompute Widget Slices**:
```dart
final updatedStateWithSlices = _updateWidgetSlices(
  currentState,  // OLD state
  newState,      // NEW state
  validatedUpdates.keys.toSet(),
);
```

#### Widget Slice Updates:

**myHand Slice** (`_computeMyHandSlice()`):
```dart
{
  'cards': [
    // ... existing cards
    {'cardId': 'card_10', 'suit': '?', 'rank': '?', 'points': 0}, // NEW
  ],
  'selectedIndex': -1,
  'canSelectCards': true,
  'playerStatus': 'playing_card',  // UPDATED
  'turn_events': [
    {'cardId': 'card_10', 'actionType': 'draw', ...}
  ],
}
```

**centerBoard Slice** (`_computeCenterBoardSlice()`):
```dart
{
  'drawPileCount': 14,  // DECREASED (was 15)
  'topDiscard': {...},  // Unchanged
  'topDraw': null,      // No top draw card visible
  'canDrawFromDeck': false,  // Status is now 'playing_card'
  'canTakeFromDiscard': false,
  'playerStatus': 'playing_card',
  'matchPot': 0,
}
```

**opponentsPanel Slice** (`_computeOpponentsPanelSlice()`):
```dart
{
  'opponents': [
    {
      'id': 'player_1',
      'hand': [
        // ... cards including new card_10
      ],
      'status': 'playing_card',  // UPDATED
      'drawnCard': {
        'cardId': 'card_10',
        // ID-only for opponents, full data for current user
      },
      'action': null,  // Cleared after state update
      'actionData': null,
    },
    // ... other opponents
  ],
  'currentTurnIndex': 0,
  'turn_events': [
    {'cardId': 'card_10', 'actionType': 'draw', ...}
  ],
  'currentPlayerStatus': 'playing_card',
}
```

4. **Update StateManager**:
```dart
_stateManager.updateModuleState('dutch_game', updatedStateWithSlices);
```

---

### PHASE 7: Widgets Rebuild

**Location**: Various widgets listening to `StateManager`

#### Widgets That Update:

1. **UnifiedGameBoardWidget**:
   - Reads `myHand` slice → Shows new card in hand
   - Reads `centerBoard` slice → Updates draw pile count
   - Reads `opponentsPanel` slice → Shows opponent's drawn card (ID-only)

2. **MyHandWidget**:
   - Displays new card at end of hand
   - Updates card count

3. **CenterBoardWidget**:
   - Updates draw pile count display
   - Shows/hides draw button based on status

4. **OpponentsPanelWidget**:
   - Shows opponent's drawn card (face-down, ID-only)
   - Updates opponent status

---

## State Update Timeline

```
Time    Phase                          State Changes
─────────────────────────────────────────────────────────────────────
T+0ms   Initial State                 Player status: 'drawing_card'
                                    No drawnCard
                                    Draw pile: 15 cards

T+10ms  Draw Processing               Card removed from draw pile
                                    Card added to hand (ID-only)
                                    Turn event created
                                    Action marker set

T+20ms  STEP 1 Broadcast             Broadcast to all except player_1
        (Opponents receive)          - drawnCard: ID-only
                                    - action: 'drawn_card'
                                    - turn_events: [draw event]

T+30ms  STEP 2 Send                  Send to player_1 only
        (Drawing player receives)   - drawnCard: FULL DATA
                                    - status: 'playing_card'
                                    - action: 'drawn_card' (then cleared)

T+40ms  Frontend Receives            handleGameStateUpdated() called
                                    Games map updated

T+50ms  State Updater Processes      Widget slices recomputed:
                                    - myHand: new card added
                                    - centerBoard: drawPileCount = 14
                                    - opponentsPanel: status updated

T+60ms  Widgets Rebuild              UI updates:
                                    - Hand shows new card
                                    - Draw pile count decreases
                                    - Status changes to 'playing_card'
```

---

## Key Points

1. **Two-Step Broadcast**: 
   - STEP 1: ID-only to all (except drawing player) - shows action without revealing card
   - STEP 2: Full data to drawing player only - reveals card details

2. **Action Markers**: 
   - `action: 'drawn_card'` and `actionData: {'cardId': '...'}` are set during draw
   - Cleared immediately after state update is sent
   - Currently not consumed by any system (animation system was removed)

3. **Turn Events**: 
   - Created for each draw action: `{'cardId': '...', 'actionType': 'draw'}`
   - Included in all state broadcasts
   - Used for animation/UI tracking

4. **Widget Slice Recomputation**: 
   - Happens automatically when state updates
   - Computes `myHand`, `centerBoard`, `opponentsPanel` from full game state
   - Ensures UI stays in sync with game state

5. **State Synchronization**: 
   - All players receive updates via WebSocket
   - StateManager ensures consistent state across frontend
   - Widgets rebuild automatically on state changes

---

## Code References

- **Draw Processing**: `dutch_game_round.dart` lines 1439-1819
- **STEP 1 Broadcast**: `dutch_game_round.dart` lines 1755-1766
- **STEP 2 Send**: `dutch_game_round.dart` lines 1774-1791
- **Broadcast Implementation**: `game_registry.dart` lines 179-251
- **Send Implementation**: `game_registry.dart` lines 83-152
- **Frontend Handler**: `dutch_event_handler_callbacks.dart` lines 1245-1400+
- **State Updater**: `dutch_game_state_updater.dart` lines 180-348
- **Widget Slice Computation**: `dutch_game_state_updater.dart` lines 370-1033
