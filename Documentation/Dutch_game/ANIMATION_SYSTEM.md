# Dutch Game Animation System

## Overview

The Dutch Game Animation System provides smooth, visually appealing card animations for game actions such as drawing cards, playing cards, and special power effects. The system is designed to work seamlessly with the state management architecture, detecting actions from game state changes and animating cards from their old positions to their new positions.

## Architecture Components

### 1. CardAnimationDetector (`utils/card_animation_detector.dart`)

**Purpose**: Detects player actions from game state and triggers animation queueing.

**Key Responsibilities**:
- Detects actions from `newState` (players with `action` and `actionData` fields)
- Captures previous state slices (OLD state) for animation start positions
- Queues animations in `CardAnimationManager`
- Clears actions from state to prevent re-queueing
- Implements deduplication to prevent duplicate animations

**Key Methods**:
- `detectAndQueueActionsFromState(currentStateSlices, newState)`: Main entry point called from state updater
- `_detectPlayerActionsFromState(newState)`: Extracts actions from players in game state
- `_clearActionFromState(state, playerId)`: Removes action fields after detection

### 2. CardAnimationManager (`screens/game_play/widgets/card_animation_manager.dart`)

**Purpose**: Manages animation queue, position tracking, and local state for animations.

**Key Responsibilities**:
- Maintains local state matching widget slice structure (OLD state)
- Manages animation queue (`_animationQueue`)
- Tracks card positions via GlobalKeys
- Processes animations sequentially
- Provides position lookup for animation handlers

**Key Methods**:
- `capturePreviousState(currentStateSlices)`: Stores OLD state slices before recomputation
- `queueAnimation(action, actionData, playerId)`: Adds animation to queue
- `processQueue()`: Processes all queued animations sequentially
- `getCardPosition(cardId)`: Returns current position of a card
- `getHandCardPosition(playerId, cardIndex)`: Returns position of card in hand by index

### 3. CardAnimationLayer (`screens/game_play/widgets/card_animation_layer.dart`)

**Purpose**: Renders animated card replicas during animations.

**Key Responsibilities**:
- Displays animated card replicas over the game board
- Manages AnimationControllers for smooth transitions
- Handles position and size animations
- Listens to animation triggers from detector

### 4. DutchGameStateUpdater (`managers/dutch_game_state_updater.dart`)

**Purpose**: Orchestrates state updates and coordinates with animation system.

**Key Responsibilities**:
- Captures OLD state slices before widget recomputation
- Passes OLD slices and NEW state to animation detector
- Recomputes widget slices after action detection
- Logs state transitions for debugging

## State Flow: OLD vs NEW State Logic

### Critical Concept: Two-State System

The animation system uses a **two-state approach** to determine animation start and end positions:

1. **OLD State (previousSlices)**: Widget slices from `currentState` **before** recomputation
   - Contains: `myHand`, `centerBoard`, `opponentsPanel`
   - Used for: Animation **start positions**
   - Captured at: Line 280-284 in `dutch_game_state_updater.dart`

2. **NEW State (newState)**: Complete merged state **after** updates
   - Contains: Full game state including `games[gameId].gameData.game_state.players` with `action` fields
   - Used for: Action **detection** (extracting `action` and `actionData` from players)
   - Also used for: Widget slice **recomputation** (animation end positions)

### State Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ DutchGameStateUpdater.applyStateUpdate()                        │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Capture OLD State Slices (currentState)                      │
│    - myHand (OLD)                                               │
│    - centerBoard (OLD)                                          │
│    - opponentsPanel (OLD)                                       │
│    → Stored in previousSlices                                    │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Merge Updates into newState                                   │
│    - Contains updated game state                                │
│    - Players may have 'action' and 'actionData' fields          │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Pass to Animation Detector                                    │
│    CardAnimationDetector.detectAndQueueActionsFromState(        │
│      previousSlices,  // OLD state (for start positions)        │
│      newState         // NEW state (for action detection)       │
│    )                                                             │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Animation Detector Processing                                 │
│    a) Extract actions from newState.players                     │
│    b) Capture previousSlices in CardAnimationManager            │
│    c) Queue animation with action data                          │
│    d) Clear action from newState (prevent re-queueing)          │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Recompute Widget Slices (using newState)                     │
│    - myHand (NEW) → Animation end position                      │
│    - centerBoard (NEW) → Animation end position                 │
│    - opponentsPanel (NEW) → Animation end position             │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Update StateManager with final state                         │
│    - Widgets rebuild with NEW state                             │
│    - Animation layer uses OLD state (captured) for start         │
└─────────────────────────────────────────────────────────────────┘
```

### Code Flow Example

```dart
// In DutchGameStateUpdater._updateWidgetSlices()

// Step 1: Capture OLD state slices (before recomputation)
final previousSlices = {
  'myHand': currentState['myHand'],           // OLD
  'centerBoard': currentState['centerBoard'], // OLD
  'opponentsPanel': currentState['opponentsPanel'], // OLD
};

// Step 2: Pass to animation detector
// - previousSlices: OLD state for animation start positions
// - newState: NEW state with action fields for detection
CardAnimationDetector().detectAndQueueActionsFromState(previousSlices, newState);

// Step 3: Recompute widget slices (after action detection)
// This creates NEW state slices with updated card positions
updatedState['myHand'] = _computeMyHandSlice(newState);           // NEW
updatedState['centerBoard'] = _computeCenterBoardSlice(newState); // NEW
updatedState['opponentsPanel'] = _computeOpponentsPanelSlice(newState); // NEW
```

## Action Detection Mechanism

### Action Detection Flow

1. **State Updater Calls Detector** (Line 364 in `dutch_game_state_updater.dart`):
   ```dart
   CardAnimationDetector().detectAndQueueActionsFromState(previousSlices, newState);
   ```

2. **Detector Extracts Actions** (Line 420-480 in `card_animation_detector.dart`):
   ```dart
   // Navigate to: newState['games'][currentGameId]['gameData']['game_state']['players']
   final players = gameState['players'] as List<dynamic>? ?? [];
   
   // Find player with action field
   for (final player in players) {
     final action = player['action']?.toString();
     final actionData = player['actionData'] as Map<String, dynamic>?;
     final playerId = player['id']?.toString() ?? '';
     
     if (action != null && action.isNotEmpty && actionData != null) {
       return {
         'playerId': playerId,
         'action': action,
         'actionData': actionData,
       };
     }
   }
   ```

3. **Deduplication Check** (Line 346-363):
   - Prevents same action from being queued within 500ms window
   - Uses key: `${playerId}_${action}_${actionDataHash}`

4. **Capture Previous State** (Line 380):
   ```dart
   CardAnimationManager.instance.capturePreviousState(currentStateSlices);
   ```
   - Stores OLD state slices in `CardAnimationManager._localState`
   - Used later for animation start positions

5. **Queue Animation** (Line 383-387):
   ```dart
   CardAnimationManager.instance.queueAnimation(
     actionInfo['action'] as String,
     actionInfo['actionData'] as Map<String, dynamic>,
     actionInfo['playerId'] as String,
   );
   ```

6. **Clear Action from State** (Line 395):
   ```dart
   _clearActionFromState(newState, actionPlayerId);
   ```
   - Removes `action` and `actionData` fields from player
   - Prevents re-detection on subsequent state updates

### Supported Actions

The system detects and handles the following action types. Actions are declared in the game logic (see `dutch_game_round.dart` and `game_event_coordinator.dart`) by setting `action` and `actionData` fields on player objects in the game state.

#### 1. `drawn_card`

**Location**: `dutch_game_round.dart` line 1675-1676  
**Trigger**: When a player draws a card from the draw pile  
**Action Data Structure**:
```dart
{
  'action': 'drawn_card',
  'actionData': {
    'cardId': String,  // ID of the card that was drawn
  }
}
```

**Example**:
```dart
player['action'] = 'drawn_card';
player['actionData'] = {'cardId': 'card_123'};
```

**Notes**:
- The `cardId` identifies which card was drawn
- Animation should show card moving from draw pile to player's hand
- The card's final position in hand is determined by the hand structure after the draw

#### 2. `play_card`

**Location**: `dutch_game_round.dart` line 2486-2487  
**Trigger**: When a player plays a card from their hand to the discard pile  
**Action Data Structure**:
```dart
{
  'action': 'play_card',
  'actionData': {
    'cardIndex': int,  // Index of the card in hand before removal (0-based)
  }
}
```

**Example**:
```dart
player['action'] = 'play_card';
player['actionData'] = {'cardIndex': 2};
```

**Notes**:
- `cardIndex` is captured **before** the card is removed from hand
- Use this index to find the card in the OLD state hand slice
- Animation should show card moving from hand position to discard pile

#### 3. `same_rank`

**Location**: `dutch_game_round.dart` line 3047-3048  
**Trigger**: When a player plays a card during the same rank window (out-of-turn play)  
**Action Data Structure**:
```dart
{
  'action': 'same_rank',
  'actionData': {
    'cardIndex': int,  // Index of the card in hand before removal (0-based)
  }
}
```

**Example**:
```dart
player['action'] = 'same_rank';
player['actionData'] = {'cardIndex': 1};
```

**Notes**:
- Similar structure to `play_card` but indicates out-of-turn play
- `cardIndex` is captured before card removal
- Animation should show card moving from hand to discard pile

#### 4. `jack_swap`

**Location**: `dutch_game_round.dart` line 3327-3331  
**Trigger**: When a player uses the Jack power to swap two cards between players  
**Action Data Structure**:
```dart
{
  'action': 'jack_swap',
  'actionData': {
    'card1': {
      'cardIndex': int,      // Index of first card in its owner's hand (0-based)
      'playerId': String,    // ID of player who owns the first card
    },
    'card2': {
      'cardIndex': int,      // Index of second card in its owner's hand (0-based)
      'playerId': String,    // ID of player who owns the second card
    },
  }
}
```

**Example**:
```dart
actingPlayer['action'] = 'jack_swap';
actingPlayer['actionData'] = {
  'card1': {'cardIndex': 2, 'playerId': 'player_123'},
  'card2': {'cardIndex': 0, 'playerId': 'player_456'},
};
```

**Notes**:
- The `actingPlayer` is the player who used the Jack power
- `card1` and `card2` contain the positions of both cards before swap
- Animation should show both cards swapping positions simultaneously
- Card indices are captured before the swap occurs

#### 5. `queen_peek`

**Location**: `dutch_game_round.dart` line 3637-3641  
**Trigger**: When a player uses the Queen power to peek at another player's card  
**Action Data Structure**:
```dart
{
  'action': 'queen_peek',
  'actionData': {
    'cardIndex': int,      // Index of the card being peeked at (0-based)
    'playerId': String,     // ID of the player who owns the card being peeked
  }
}
```

**Example**:
```dart
peekingPlayer['action'] = 'queen_peek';
peekingPlayer['actionData'] = {
  'cardIndex': 3,
  'playerId': 'player_789',
};
```

**Notes**:
- The `peekingPlayer` is the player who used the Queen power
- `playerId` identifies the owner of the card being peeked
- `cardIndex` is the position of the card in the owner's hand
- Animation should show a peek/flip effect on the target card
- The card data is available in `peekingPlayer['cardsToPeek']`

#### 6. `initial_peek`

**Location**: `game_event_coordinator.dart` line 1179-1183  
**Trigger**: At game start when players peek at their initial 2 cards  
**Action Data Structure**:
```dart
{
  'action': 'initial_peek',
  'actionData': {
    'cardIndex1': int,  // Index of first card to peek (0-based)
    'cardIndex2': int,  // Index of second card to peek (0-based)
  }
}
```

**Example**:
```dart
playerInGamesMap['action'] = 'initial_peek';
playerInGamesMap['actionData'] = {
  'cardIndex1': 0,
  'cardIndex2': 2,
};
```

**Notes**:
- Triggered during initial game setup
- Players peek at exactly 2 cards from their initial 4-card hand
- Animation should show both cards being revealed/flipped
- Cards are identified by their indices in the hand

### Action Declaration Locations

Actions are set in the game logic at the following locations:

| Action Type | File | Line Range | Method/Context |
|------------|------|------------|----------------|
| `drawn_card` | `dutch_game_round.dart` | 1675-1676 | `handleDrawCard()` |
| `play_card` | `dutch_game_round.dart` | 2486-2487 | `handlePlayCard()` |
| `same_rank` | `dutch_game_round.dart` | 3047-3048 | `handleSameRankPlay()` |
| `jack_swap` | `dutch_game_round.dart` | 3327-3331 | `handleJackSwap()` |
| `queen_peek` | `dutch_game_round.dart` | 3637-3641 | `handleQueenPeek()` |
| `initial_peek` | `game_event_coordinator.dart` | 1179-1183 | Initial game setup |

### Action Clearing

After actions are detected and queued by the animation system, they are cleared from the state to prevent re-queueing:

- **Location**: `card_animation_detector.dart` line 395 (`_clearActionFromState()`)
- **Method**: Removes both `action` and `actionData` fields from the player object
- **Timing**: Immediately after action is detected and queued
- **Purpose**: Prevents duplicate animations during rapid state updates

## Animation Queue System

### Queue Processing

The `CardAnimationManager` processes animations sequentially:

1. **Queue Addition**: Animations are added via `queueAnimation()`
2. **Sequential Processing**: `processQueue()` processes one animation at a time
3. **State Management**: `_localState['isOn']` controls visibility of animation layer
4. **Handler Execution**: Each action type has a dedicated handler method

### Queue Processing Flow

```dart
// In CardAnimationManager.processQueue()

while (_animationQueue.isNotEmpty) {
  // Pop first animation
  _currentAnimation = _animationQueue.removeAt(0);
  
  // Show animation layer
  _localState['isOn'] = true;
  notifyListeners();
  
  // Execute handler based on action type
  switch (_currentAnimation!.action) {
    case 'drawn_card':
      await _handleDrawCardAnimation(_currentAnimation!);
      break;
    case 'play_card':
      await _handlePlayCardAnimation(_currentAnimation!);
      break;
    // ... other handlers
  }
  
  // Clear current animation
  _currentAnimation = null;
}

// Hide animation layer when queue is empty
_localState['isOn'] = false;
notifyListeners();
```

### Animation Item Structure

```dart
class AnimationItem {
  final String action;              // Action type (e.g., 'drawn_card')
  final Map<String, dynamic> actionData;  // Action-specific data
  final String playerId;             // Player who performed action
  final DateTime timestamp;         // When action was queued
}
```

## Position Tracking System

### GlobalKey Registration

Cards and sections register GlobalKeys for position tracking:

- **Card Keys**: `_cardKeys[cardId] = GlobalKey()`
- **Section Keys**: `_sectionKeys[section] = GlobalKey()` (e.g., 'drawPile', 'discardPile', 'myHand', 'opponent_<playerId>')

### Position Lookup

The system provides multiple methods for position lookup:

1. **By Card ID**: `getCardPosition(cardId)`
   - Looks up GlobalKey for cardId
   - Captures fresh position from widget bounds

2. **By Hand Index**: `getHandCardPosition(playerId, cardIndex)`
   - Extracts cardId from hand at specified index
   - Uses OLD state (`_localState`) to find card
   - Returns position via cardId lookup

3. **By Section**: `getSectionPosition(section)`
   - Returns cached position for sections like 'drawPile', 'discardPile'
   - Uses GlobalKey lookup for dynamic sections

### Fixed Position Caching

Fixed positions (draw pile, discard pile) are captured once before animations start:

```dart
// Fixed positions captured before animation processing
_drawPilePosition = getSectionPosition('drawPile');
_discardPilePosition = getSectionPosition('discardPile');
_fixedPositionsCaptured = true;
```

## Data Structures

### Widget Slice Structure

Widget slices follow a consistent structure:

```dart
// myHand slice
{
  'cards': List<dynamic>,           // Card objects
  'selectedIndex': int,              // Currently selected card index
  'canSelectCards': bool,            // Whether selection is enabled
  'playerStatus': String,            // Player status (e.g., 'waiting', 'active')
  'turn_events': List<dynamic>,      // Turn event history
}

// centerBoard slice
{
  'drawPileCount': int,              // Number of cards in draw pile
  'topDiscard': dynamic,             // Top card of discard pile (or null)
  'topDraw': dynamic,                // Top card of draw pile (or null)
  'canDrawFromDeck': bool,           // Whether drawing is allowed
  'canTakeFromDiscard': bool,        // Whether taking from discard is allowed
  'playerStatus': String,             // Player status
  'matchPot': int,                   // Match pot amount
}

// opponentsPanel slice
{
  'opponents': List<dynamic>,        // Opponent player objects
  'currentTurnIndex': int,           // Index of current player in opponents list
  'turn_events': List<dynamic>,       // Turn event history
  'currentPlayerStatus': String,      // Current player status
}
```

### Player Object Structure (in game_state.players)

```dart
{
  'id': String,                      // Player ID
  'hand': List<dynamic>,             // Player's hand cards
  'status': String,                  // Player status
  'score': int,                      // Player score
  'action': String?,                 // Action type (if action detected)
  'actionData': Map<String, dynamic>?, // Action data (if action detected)
  // ... other player fields
}
```

## Logging and Debugging

### Logging Switches

Each component has a `LOGGING_SWITCH` constant for enabling/disabling logs:

- `CardAnimationDetector`: `const bool LOGGING_SWITCH = false;`
- `CardAnimationManager`: `const bool LOGGING_SWITCH = false;`
- `DutchGameStateUpdater`: `const bool LOGGING_SWITCH = false;`

### Key Log Points

1. **State Updater Logs**:
   - Widget slices BEFORE recomputation (OLD state)
   - Players state in newState (NEW state with actions)
   - Widget slices AFTER recomputation (NEW state)

2. **Animation Detector Logs**:
   - Action detection results
   - Deduplication skips
   - State clearing operations

3. **Animation Manager Logs**:
   - Queue processing start/end
   - Animation handler execution
   - Position lookup results

### Log Format

All animation system logs are prefixed with `🎬` emoji for easy filtering:

```dart
_logger.info('🎬 ComponentName: Message', isOn: LOGGING_SWITCH);
```

## Key Design Decisions

### 1. Two-State System

**Why**: Animations need both start (OLD) and end (NEW) positions. By capturing OLD state before recomputation and using NEW state for detection, we ensure accurate animation paths.

### 2. Action Clearing

**Why**: Actions are cleared from state immediately after detection to prevent re-queueing during rapid state updates. The backend manages game logic, but the frontend clears action flags to prevent duplicate animations.

### 3. Deduplication Window

**Why**: A 500ms deduplication window prevents the same action from being queued multiple times if state updates occur rapidly (e.g., during WebSocket message bursts).

### 4. Sequential Processing

**Why**: Animations are processed one at a time to avoid visual conflicts and ensure smooth transitions. The queue ensures animations complete before the next begins.

### 5. Non-Blocking Error Handling

**Why**: Animation detection errors should not block state updates. Errors are logged but do not prevent the game state from updating.

## Integration Points

### State Updater Integration

The animation system is integrated into `DutchGameStateUpdater._updateWidgetSlices()`:

```dart
// Before widget recomputation:
final previousSlices = { /* OLD state */ };
CardAnimationDetector().detectAndQueueActionsFromState(previousSlices, newState);

// After action detection:
updatedState['myHand'] = _computeMyHandSlice(newState); // NEW state
```

### Widget Integration

The `UnifiedGameBoardWidget` includes the `CardAnimationLayer`:

```dart
Stack(
  children: [
    // Game board widgets
    // ...
    // Animation layer (renders on top)
    CardAnimationLayer(),
  ],
)
```

## Future Enhancements

### Planned Features

1. **Animation Handlers**: Complete implementation of animation handlers for all action types
2. **Position Interpolation**: Smooth position transitions using Flutter's animation system
3. **Size Animations**: Animate card size changes during transitions
4. **Rotation Animations**: Add rotation effects for special actions
5. **Sound Effects**: Synchronize sound effects with animations

### Known Limitations

1. **Position Accuracy**: Card positions depend on widget layout completion; some edge cases may require additional position capture timing
2. **Concurrent Animations**: Currently sequential; future enhancement may support concurrent animations for different cards
3. **Animation Cancellation**: No mechanism to cancel in-progress animations if state changes rapidly

## Troubleshooting

### Common Issues

1. **Animations Not Triggering**:
   - Check that `action` and `actionData` fields are present in player objects
   - Verify `LOGGING_SWITCH` is enabled and check detector logs
   - Ensure state updater is calling `detectAndQueueActionsFromState()`

2. **Duplicate Animations**:
   - Check deduplication window (500ms)
   - Verify action clearing is working (check logs)
   - Ensure actions are cleared from state after detection

3. **Incorrect Start Positions**:
   - Verify `previousSlices` are captured before widget recomputation
   - Check that `capturePreviousState()` is called in detector
   - Ensure OLD state slices match widget structure

4. **Missing End Positions**:
   - Verify widget slices are recomputed after action detection
   - Check that NEW state contains updated card positions
   - Ensure GlobalKeys are registered for cards

## References

- **State Management**: See `FLUTTER_STATE_MANAGEMENT_BASELINE.md`
- **Card Sizing**: See `CARD_SIZING_SYSTEM.md`
- **Player Actions**: See `PLAYER_ACTIONS_FLOW.md`
