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
   - Manages initial peek card selection and state updates
   - Handles demo phase transitions and instructions
   - Tracks selected cards and updates `myCardsToPeek` in StateManager

4. **DemoInstructionsWidget** (`screens/demo/demo_instructions_widget.dart`)
   - Displays phase-specific instructions at the top of the demo screen
   - Overlay widget that doesn't take up layout space
   - Shows title and paragraph for each demo phase
   - Includes "Let's go" button for initial phase

5. **SelectCardsPromptWidget** (`screens/demo/select_cards_prompt_widget.dart`)
   - Displays flashing "Select two cards" text above myhand section
   - Overlay widget positioned dynamically based on myhand height
   - Only visible during initial peek phase when 0-1 cards selected
   - Uses animated glow effect with accent color

6. **Event Transport System**
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

**State Fields Updated During Demo:**
- `demoInstructionsPhase` - Controls which instruction phase is visible (independent from `gamePhase`)
- `myCardsToPeek` - Cards selected during initial peek (full data → ID-only after timer)
- `myDrawnCard` - Currently drawn card (cleared when added to hand)
- `myHandHeight` - Dynamic height of myhand section (measured via GlobalKey)
- `playerStatus` - Current player status (`'initial_peek'` → `'drawing_card'` → `'playing_card'`)
- `myHand['playerStatus']` - Status in myHand slice (for status chip display)
- `centerBoard['playerStatus']` - Status in centerBoard slice (for draw pile interaction)

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

**Initial State:**
All cards in demo mode start as ID-only (face-down):
- `cardId`: Unique identifier
- `suit`: `'?'` (hidden)
- `rank`: `'?'` (hidden)
- `points`: `0` (hidden)

**During Initial Peek:**
- When user selects cards during initial peek, full card data is retrieved from `originalDeck`
- Cards are added to `myCardsToPeek` in StateManager with full data (suit, rank, points)
- Both cards are shown simultaneously when second card is selected
- After 5-second timer, cards are converted back to ID-only format (face-down)

**Card Data Lookup:**
- Full card data is retrieved from `originalDeck` stored in game state
- `_getCardById()` method looks up cards by `cardId` in the original deck
- This allows showing card details during peek phases

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
- `draw_card` - **Implemented**: Handles drawing from draw pile or discard pile, adds card to hand, updates status
- `play_card`
- `replace_drawn_card`
- `play_drawn_card`
- `initial_peek` - **Implemented**: Handles card selection, shows card details
- `completed_initial_peek` - **Implemented**: Completes initial peek, starts timer
- `call_final_round`
- `collect_from_discard`
- `use_special_power`
- `jack_swap`
- `queen_peek`
- `play_out_of_turn`

### Initial Peek Implementation

**Card Selection Flow:**
1. User clicks first card → Card ID tracked, instructions hidden
2. User clicks second card → Both cards retrieved from `originalDeck` with full data
3. Both cards added to `myCardsToPeek` simultaneously (batched update)
4. Cards displayed with full details (suit, rank, points visible)
5. 5-second timer starts automatically
6. After timer expires → Cards converted back to ID-only format (face-down)
7. Drawing phase instructions appear
8. Player status updated to `'drawing_card'` (enables draw pile interaction)
9. Widget slices updated (`myHand`, `centerBoard`) to show correct status

### Drawing Implementation

**Action Interception:**
- `PlayerAction.playerDraw()` sends event `'draw_card'` with payload:
  - `source`: `'deck'` (for draw pile) or `'discard'` (for discard pile)
  - `game_id`: Current game ID
  - `player_id`: Auto-added by event emitter
- Event intercepted by `DemoModeBridge` when `EventTransportMode.demo`
- Routed to `DemoFunctionality._handleDrawCard()`

**Drawing Flow:**
1. User taps draw pile or discard pile
2. `PlayerAction.playerDraw()` executed → Event `'draw_card'` sent
3. Event intercepted by demo mode bridge
4. `_handleDrawCard()` processes the action:
   - **Draw Pile**: Removes ID-only card, converts to full data via `originalDeck` lookup
   - **Discard Pile**: Removes full-data card directly
5. Card added to player's hand:
   - Converted to ID-only format: `{'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}`
   - Added to **end of hand** (not in blank slots, matching practice mode behavior)
6. Player status updated to `'playing_card'`
7. State synchronized:
   - `myHandCards` updated in games map
   - `myHand` slice updated with new cards and status
   - `centerBoard` slice updated with new status
   - `playerStatus` and `currentPlayerStatus` updated in main state
   - `myDrawnCard` cleared (card is now in hand)
   - `demoInstructionsPhase` updated to `'playing'`
8. Widgets automatically rebuild via `ListenableBuilder` listening to `StateManager`
9. Status chip in myHand widget shows "Playing Card"
10. Playing phase instructions appear

**Key Implementation Details:**
- Drawn cards always go to the end of the hand (matches practice mode)
- Cards stored as ID-only in hand (face-down)
- Full card data only used temporarily during drawing process
- Status transitions: `'drawing_card'` → `'playing_card'`
- All widget slices manually updated for immediate UI feedback

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

## Demo Instructions System

### Phase-Based Instructions

The demo uses a phase-based instruction system to guide users through different game phases:

**Demo Phases:**
- `initial` - Welcome message with "Let's go" button
- `initial_peek` - Instructions for selecting 2 cards to peek at
- `drawing` - Instructions for drawing a card
- `playing` - Instructions for playing a card
- `same_rank` - Instructions for same rank window
- `jack_swap` - Instructions for Jack special power
- `queen_peek` - Instructions for Queen special power

**Instruction Widget Behavior:**
- Overlay positioned at top of screen (doesn't take layout space)
- Dark semi-transparent background matching theme
- Automatically hides when first card is selected during initial peek
- Transitions between phases based on user actions and timers

**Select Cards Prompt:**
- Flashing "Select two cards" text above myhand section (initial peek phase)
- Changes to "Tap the draw pile" text during drawing phase
- Positioned dynamically using GlobalKey to measure actual myhand height
- Only visible during:
  - Initial peek phase when 0-1 cards selected
  - Drawing phase when no card has been drawn yet (`myDrawnCard == null`)
- Automatically hides when card is drawn
- Animated glow effect using accent color
- Same background styling as instructions widget

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
- [x] Demo instructions widget with phase-based messages
- [x] Select cards prompt widget with animated glow
- [x] Initial peek card selection with full card data display
- [x] Batched state updates (both cards shown simultaneously)
- [x] Timer-based phase transitions (5-second delay after initial peek)
- [x] Card visibility management (full data → ID-only conversion)
- [x] Dynamic positioning using GlobalKey for myhand height measurement
- [x] Drawing functionality (draw from draw pile or discard pile)
- [x] Card addition to hand (ID-only format, added to end)
- [x] Status transition from drawing to playing phase
- [x] Widget slice synchronization for status updates

### 🚧 Pending Implementation

- [ ] Demo-specific action handlers in `DemoFunctionality`
  - [x] `_handleInitialPeek()` - Initial peek logic (shows card details)
  - [x] `_handleCompletedInitialPeek()` - Complete initial peek logic (starts timer)
  - [x] `_handleDrawCard()` - Draw card logic (adds card to hand, updates status to playing)
  - [ ] `_handlePlayCard()` - Play card logic
  - [ ] `_handleReplaceDrawnCard()` - Replace drawn card logic
  - [ ] `_handlePlayDrawnCard()` - Play drawn card logic
  - [ ] `_handleCallFinalRound()` - Call final round logic
  - [ ] `_handleCollectFromDiscard()` - Collect from discard logic
  - [ ] `_handleUseSpecialPower()` - Special power logic
  - [ ] `_handleJackSwap()` - Jack swap logic
  - [ ] `_handleQueenPeek()` - Queen peek logic
  - [ ] `_handlePlayOutOfTurn()` - Play out of turn logic

- [ ] Turn progression logic
- [x] Card reveal mechanics (for initial peek) - **Implemented**
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
│       ├── demo_screen.dart              # Main demo screen
│       ├── demo_mode_bridge.dart         # Event routing bridge
│       ├── demo_functionality.dart       # Demo action handlers
│       ├── demo_instructions_widget.dart # Phase-based instructions overlay
│       └── select_cards_prompt_widget.dart # Flashing prompt above myhand
├── managers/
│   ├── validated_event_emitter.dart     # Event routing (supports demo mode)
│   └── dutch_game_state_updater.dart    # State accessor (isCurrentGameDemo)
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
- Demo instructions use separate `demoInstructionsPhase` field (independent from `gamePhase`)
- Card visibility is managed through `myCardsToPeek` in StateManager
- GlobalKey is used to measure myhand height for dynamic overlay positioning
- Timer-based transitions provide smooth user experience between phases

