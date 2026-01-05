# Demo Mode System

## Overview

The Demo Mode System provides a self-contained demo experience for the Dutch card game, allowing users to explore the game mechanics without requiring backend connectivity or WebSocket communication. The demo mode intercepts all player actions and routes them to demo-specific logic, similar to how practice mode works.

## Architecture

### Core Components

1. **DemoScreen** (`screens/demo/demo_screen.dart`)
   - Main demo screen that displays the game UI
   - Manages all game state locally (no StateManager dependency for game logic)
   - Initializes demo game with predefined cards and players
   - Handles mode selection (regular vs. Clear and Collect)

2. **DemoModeBridge** (`screens/demo/demo_mode_bridge.dart`)
   - Bridges player actions to demo-specific functionality
   - Routes events from the event emitter to `DemoFunctionality`
   - Singleton instance for consistent state

3. **DemoFunctionality** (`screens/demo/demo_functionality.dart`)
   - Handles all demo-specific game logic
   - Contains action handlers for all player actions
   - Currently stubbed (ready for implementation)

4. **Event Transport System**
   - `EventTransportMode.demo` - New transport mode for demo
   - Routes all actions through `DemoModeBridge` instead of WebSocket/PracticeBridge

## State Management

### Local State (DemoScreen)

All game state is managed locally within `DemoScreenState` using `setState()`:

```dart
// Local demo state fields
String? _demoGameId;
List<Map<String, dynamic>> _players = [];
List<Map<String, dynamic>> _drawPile = [];
List<Map<String, dynamic>> _discardPile = [];
List<Map<String, dynamic>> _originalDeck = [];
Map<String, dynamic>? _currentPlayer;
String _gamePhase = 'waiting';
int _roundNumber = 1;
int _turnNumber = 1;
bool _isClearAndCollect = false;
```

### StateManager Sync

While game logic uses local state, widgets still read from `StateManager`. The demo screen:
- Updates `StateManager` with demo state structure (for widget display)
- Computes widget slices manually (`gameInfo`, `myHand`, `opponentsPanel`)
- Uses `updateStateSync()` for immediate synchronous updates

### State Structure

The demo state follows the same structure as production games:
- `games[gameId].gameData.game_state` - Single source of truth for game state
- All players have ID-only cards (face-down) in demo mode
- Game phase starts at `'initial_peek'`
- All player statuses set to `'initial_peek'`

## Card Management

### Predefined Cards

Demo mode uses manually created cards (no `YamlDeckFactory`):
- 52 standard cards (4 suits × 13 ranks)
- 2 joker cards
- Total: 54 cards

### Card Format

All cards in demo mode are ID-only (face-down):
- `cardId`: Unique identifier
- `suit`: `'?'` (hidden)
- `rank`: `'?'` (hidden)
- `points`: `0` (hidden)

This ensures consistent face-down display for all players, including the current user.

## Event Interception

### Transport Mode

When demo mode is initialized:
```dart
final eventEmitter = DutchGameEventEmitter.instance;
eventEmitter.setTransportMode(EventTransportMode.demo);
```

### Action Routing Flow

1. **Player Action** → `PlayerAction.execute()`
2. **Event Emitter** → Validates and routes based on transport mode
3. **Demo Mode Bridge** → Receives event when `EventTransportMode.demo`
4. **Demo Functionality** → Handles action with demo-specific logic

### Supported Actions

All player actions are intercepted and routed to demo functionality:
- `draw_card`
- `play_card`
- `replace_drawn_card`
- `play_drawn_card`
- `initial_peek`
- `completed_initial_peek`
- `call_final_round`
- `collect_from_discard`
- `use_special_power`
- `jack_swap`
- `queen_peek`
- `play_out_of_turn`

## Game Initialization

### Mode Selection

Users select demo mode via two buttons:
1. **"Start Dutch demo"** - Regular mode (`isClearAndCollect: false`)
2. **"Start Dutch Clear and collect demo"** - Clear and Collect mode (`isClearAndCollect: true`)

### Initialization Steps

1. **Create Predefined Cards**
   - Generate 54 cards manually (no deck factory)
   - Store in `_originalDeck` for lookups

2. **Create Players**
   - Current user + 3 opponents
   - All players get ID-only cards (face-down)
   - All player statuses set to `'initial_peek'`

3. **Deal Cards**
   - 4 cards to each player
   - Remaining cards go to draw pile
   - First card goes to discard pile (face-up)

4. **Set Game State**
   - Game phase: `'initial_peek'`
   - Game ID: `demo_game_<timestamp>`
   - Round/Turn: 1

5. **Update StateManager**
   - Sync local state to `StateManager` for widget display
   - Compute widget slices (`gameInfo`, `myHand`, `opponentsPanel`)
   - Set transport mode to `demo`

6. **Switch Event Transport**
   - Set `EventTransportMode.demo` to intercept all actions

## Widget Slices

### Manual Computation

Since `updateStateSync()` doesn't compute widget slices automatically, the demo screen manually computes:

1. **gameInfo Slice**
   ```dart
   {
     'currentGameId': currentGameId,
     'currentSize': currentSize,
     'maxSize': maxSize,
     'gamePhase': gamePhase,
     'gameStatus': gameStatus,
     'isRoomOwner': isRoomOwner,
     'isInGame': isInGame,
   }
   ```

2. **myHand Slice**
   ```dart
   {
     'cards': myHandCards,
     'selectedIndex': selectedCardIndex,
     'canSelectCards': isMyTurn && canPlayCard,
     'turn_events': turnEvents,
     'playerStatus': playerStatus,
   }
   ```

3. **opponentsPanel Slice**
   ```dart
   {
     'opponents': opponents,
     'currentTurnIndex': currentTurnIndex,
     'turn_events': turnEvents,
     'currentPlayerStatus': currentPlayerStatus,
   }
   ```

## Validation

### Game ID Pattern

The event validation system has been updated to accept demo game IDs:
- Pattern: `^(room_|practice_room_|demo_game_)[a-zA-Z0-9_]+$`
- Demo games use prefix: `demo_game_`

### State Schema

Demo mode uses only allowed fields from the state schema:
- ✅ `currentGameId`, `currentRoomId`, `isInRoom`, `isRoomOwner`
- ✅ `isGameActive`, `gamePhase`, `games`
- ✅ `playerStatus`, `currentPlayer`, `currentPlayerStatus`
- ✅ `roundNumber`, `discardPile`, `drawPileCount`
- ✅ `turn_events`, `practiceUser`, `lastUpdated`
- ❌ `turnNumber` (not allowed)
- ❌ `discardPileCount` (not allowed)

## Cleanup

When leaving the demo screen:
1. Switch transport mode back to `websocket`
2. Clear local state variables
3. Clear `StateManager` state
4. Dispose resources

## Current Implementation Status

### ✅ Completed

- [x] Demo screen structure with mode selection
- [x] Local state management (all state in `DemoScreenState`)
- [x] Predefined card creation (54 cards, manually created)
- [x] Player setup (4 players with ID-only cards)
- [x] Card dealing (4 cards per player)
- [x] StateManager sync for widget display
- [x] Widget slice computation (`gameInfo`, `myHand`, `opponentsPanel`)
- [x] Event interception system (`DemoModeBridge`, `DemoFunctionality`)
- [x] Transport mode routing (`EventTransportMode.demo`)
- [x] Game ID validation (accepts `demo_game_` prefix)
- [x] Initial peek phase setup

### 🚧 Pending Implementation

- [ ] Demo-specific action handlers in `DemoFunctionality`
  - [ ] `_handleDrawCard()` - Draw card logic
  - [ ] `_handlePlayCard()` - Play card logic
  - [ ] `_handleReplaceDrawnCard()` - Replace drawn card logic
  - [ ] `_handlePlayDrawnCard()` - Play drawn card logic
  - [ ] `_handleInitialPeek()` - Initial peek logic
  - [ ] `_handleCompletedInitialPeek()` - Complete initial peek logic
  - [ ] `_handleCallFinalRound()` - Call final round logic
  - [ ] `_handleCollectFromDiscard()` - Collect from discard logic
  - [ ] `_handleUseSpecialPower()` - Special power logic
  - [ ] `_handleJackSwap()` - Jack swap logic
  - [ ] `_handleQueenPeek()` - Queen peek logic
  - [ ] `_handlePlayOutOfTurn()` - Play out of turn logic

- [ ] Turn progression logic
- [ ] Card reveal mechanics (for initial peek)
- [ ] Game end conditions
- [ ] Score calculation
- [ ] Animation support (if needed)

## Usage

### Starting a Demo

1. Navigate to home screen
2. Tap "Take a quick demo" button
3. Select demo mode:
   - "Start Dutch demo" (regular mode)
   - "Start Dutch Clear and collect demo" (clear and collect mode)
4. Demo game initializes with:
   - 4 players (You + 3 opponents)
   - All cards face-down (ID-only)
   - Game phase: `initial_peek`
   - All actions intercepted for demo logic

### Demo vs Practice vs Multiplayer

| Feature | Demo | Practice | Multiplayer |
|---------|------|----------|-------------|
| Backend Required | ❌ | ❌ | ✅ |
| WebSocket Required | ❌ | ❌ | ✅ |
| State Management | Local (`setState`) | Backend Bridge | WebSocket |
| Card Visibility | All face-down | Normal rules | Normal rules |
| Action Routing | `DemoFunctionality` | `PracticeModeBridge` | WebSocket |
| Game ID Prefix | `demo_game_` | `practice_room_` | `room_` |

## File Structure

```
flutter_base_05/lib/modules/dutch_game/
├── screens/
│   └── demo/
│       ├── demo_screen.dart          # Main demo screen
│       ├── demo_mode_bridge.dart     # Event routing bridge
│       └── demo_functionality.dart   # Demo action handlers
├── managers/
│   ├── validated_event_emitter.dart # Event routing (supports demo mode)
│   └── dutch_game_state_updater.dart # State accessor (isCurrentGameDemo)
```

## Related Documentation

- [PLAYER_ACTIONS_FLOW.md](./PLAYER_ACTIONS_FLOW.md) - How player actions flow through the system
- [STATE_MANAGEMENT.md](./STATE_MANAGEMENT.md) - State management architecture
- Practice Mode - Similar interception pattern (reference implementation)

## Notes

- Demo mode is designed to be completely self-contained
- No backend or WebSocket dependencies
- All game logic should be implemented in `DemoFunctionality`
- State updates use `setState()` for local state, `StateManager` for widget display
- Widget slices are manually computed (not auto-computed like in normal flow)

