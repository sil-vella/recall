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
- `play_card` - **Implemented**: Handles playing a card, moves card to discard pile, triggers same rank window, auto-plays opponent same rank cards
- `replace_drawn_card`
- `play_drawn_card`
- `initial_peek` - **Implemented**: Handles card selection, shows card details
- `completed_initial_peek` - **Implemented**: Completes initial peek, starts timer
- `call_final_round`
- `collect_from_discard`
- `use_special_power`
- `jack_swap` - **Implemented**: Handles jack play and jack swap card swapping
- `queen_peek` - **Implemented**: Handles queen peek card selection and display
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

### Play Card Implementation

**Action Interception:**
- `PlayerAction.playerPlayCard()` sends event `'play_card'` with payload:
  - `card_id`: ID of the card to play
  - `game_id`: Current game ID
  - `player_id`: Auto-added by event emitter
- Event intercepted by `DemoModeBridge` when `EventTransportMode.demo`
- Routed to `DemoFunctionality._handlePlayCard()`

**Playing Flow:**
1. User taps a card in their hand
2. `PlayerAction.playerPlayCard()` executed → Event `'play_card'` sent
3. Event intercepted by demo mode bridge
4. `_handlePlayCard()` processes the action:
   - Checks if played card is a queen (for special play routing)
   - If queen: Routes to `_handleQueenPlay()` for special handling
   - If not queen: Continues with regular play logic
   - Finds card in player's hand by cardId
   - Removes card from hand (creates blank slot if index ≤ 3, otherwise removes entirely)
   - If a drawn card exists, it replaces the played card's position
   - Adds played card to discard pile with full data
   - Updates all players' status to `'same_rank_window'` (except human player during opponent simulation)
   - Triggers opponent same rank auto-play check
5. State synchronized:
   - `myHandCards` updated in games map
   - `myHand` slice updated with new cards
   - `centerBoard` slice updated with discard pile
   - `playerStatus` and `currentPlayerStatus` updated to `'same_rank_window'`
   - `demoInstructionsPhase` cleared (instructions shown after opponent plays)
6. Opponent same rank auto-play:
   - Checks each opponent for matching rank cards
   - Waits 3 seconds before each opponent plays (fixed delay for demo)
   - Auto-plays first matching card if found
   - Updates opponent's hand and discard pile
   - After opponent plays, waits 3 seconds then shows same rank instructions

**Wrong Same Rank Play:**
- When user plays a card of wrong rank during same rank window:
  - Card is added to discard pile
  - User receives a penalty card (added to hand)
  - Hand count hardcoded to 5 cards in instruction text
  - `demoInstructionsPhase` set to `wrong_same_rank_penalty`
  - Instruction shown with "Let's go" button
  - Opponent simulation starts only after "Let's go" button is pressed

**Queen Play (Special Play):**
- When user plays a queen card:
  - Action intercepted and routed to `_handleQueenPlay()`
  - Queen card removed from hand (using smart blank slot logic)
  - Drawn card repositioned if it wasn't the played card
  - Original queen card (from originalDeck) added to discard pile
  - Player status updated to `'queen_peek'`
  - `demoInstructionsPhase` set to `'queen_peek'`
  - Queen peek instructions displayed
  - Prompt text "Tap a card to peek" shown above myhand
  - **Note**: Same rank window is skipped for queen play (no opponent auto-play)

**Jack Play (Special Play):**
- When user plays a jack card:
  - Action intercepted and routed to `_handleJackPlay()`
  - Jack card removed from hand (using smart blank slot logic)
  - Drawn card repositioned if it wasn't the played card
  - Original jack card (from originalDeck) added to discard pile
  - Player status updated to `'jack_swap'`
  - `demoInstructionsPhase` set to `'jack_swap'`
  - Jack swap instructions displayed
  - Prompt text "Tap two cards to swap" shown above myhand
  - **Note**: Same rank window is skipped for jack play (no opponent auto-play)

**Queen Peek Implementation Pattern (Reference for Jack Swap):**

The queen peek implementation follows a specific pattern that should be replicated for jack swap:

1. **Action Interception**:
   - In `_handlePlayCard()`, check if the played card is a queen (or jack)
   - Route to special handler: `_handleQueenPlay()` or `_handleJackPlay()`

2. **State Updates (SSOT - Single Source of Truth)**:
   ```dart
   // Step 1: Re-read latest state from SSOT to avoid stale references
   final stateManager = StateManager();
   final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
   final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
   final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
   final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
   final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? gameState;
   final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
   
   // Step 2: Find user player from latest players (not stale parameter)
   Map<String, dynamic>? userPlayer;
   int userPlayerIndex = -1;
   for (int i = 0; i < latestPlayers.length; i++) {
     final p = latestPlayers[i];
     if (p is Map<String, dynamic> && p['isHuman'] == true) {
       userPlayer = Map<String, dynamic>.from(p);
       userPlayerIndex = i;
       break;
     }
   }
   
   // Step 3: Update user player's hand and status
   userPlayer['hand'] = mutableHand; // Updated hand after card removal
   userPlayer['status'] = 'queen_peek'; // or 'jack_swap'
   
   // Step 4: Update SSOT structure (deep copies)
   final updatedPlayers = List<dynamic>.from(latestPlayers);
   updatedPlayers[userPlayerIndex] = userPlayer;
   final updatedGameState = Map<String, dynamic>.from(latestGameState);
   updatedGameState['players'] = updatedPlayers;
   updatedGameState['currentPlayer'] = userPlayer; // Important: Set currentPlayer
   updatedGameState['discardPile'] = discardPile;
   final updatedGameData = Map<String, dynamic>.from(latestGameData);
   updatedGameData['game_state'] = updatedGameState;
   final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
   updatedCurrentGame['gameData'] = updatedGameData;
   updatedCurrentGame['myHandCards'] = myHandCards;
   final updatedGames = Map<String, dynamic>.from(latestGames);
   updatedGames[currentGameId] = updatedCurrentGame;
   ```

3. **Widget Slice Updates**:
   ```dart
   // Get current dutch game state for widget slice updates
   final stateManagerForSlices = StateManager();
   final currentDutchGameState = stateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
   
   // Update widget slices manually
   final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
   centerBoard['playerStatus'] = 'queen_peek'; // or 'jack_swap'
   
   final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
   myHand['playerStatus'] = 'queen_peek'; // or 'jack_swap'
   myHand['cards'] = myHandCards; // Update cards in myHand slice
   ```

4. **State Synchronization (Two-Step Process)**:
   ```dart
   final stateUpdater = DutchGameStateUpdater.instance;
   
   // Step 1: Update SSOT and main state fields using updateStateSync
   stateUpdater.updateStateSync({
     'currentGameId': currentGameId,
     'games': updatedGames, // SSOT with player status = 'queen_peek'
     'discardPile': discardPile,
     'myDrawnCard': null, // Clear drawn card
     'currentPlayer': userPlayer, // Set currentPlayer so _getCurrentUserStatus can find it
     'currentPlayerStatus': 'queen_peek', // or 'jack_swap'
     'playerStatus': 'queen_peek', // or 'jack_swap'
     'lastUpdated': DateTime.now().toIso8601String(),
   });
   
   // Step 2: Update widget slices using updateStateSync
   stateUpdater.updateStateSync({
     'centerBoard': centerBoard, // Update centerBoard slice
     'myHand': myHand, // Update myHand slice with new status and cards
   });
   
   // Step 3: Update instructions phase separately using updateState (triggers widget rebuild)
   // CRITICAL: Use updateState (not updateStateSync) to ensure ListenableBuilder rebuilds
   // NOTE: Do NOT set gamePhase - it's validated and 'queen_peek'/'jack_swap' are not allowed
   // Only set demoInstructionsPhase which controls the instructions widget
   stateUpdater.updateState({
     'demoInstructionsPhase': 'queen_peek', // or 'jack_swap'
     'lastUpdated': DateTime.now().toIso8601String(),
   });
   ```

5. **Instructions Configuration**:
   - Add instruction entry in `_demoPhaseInstructions` list:
   ```dart
   DemoPhaseInstruction(
     phase: 'queen_peek', // or 'jack_swap'
     title: 'Queen Peek:', // or 'Jack Swap:'
     paragraph: 'When a queen is played, that player can take a quick peek at any card from any player\'s hand, including their own.',
   ),
   ```

6. **Prompt Text Configuration**:
   - Update `SelectCardsPromptWidget` to show phase-specific text:
   ```dart
   } else if (demoInstructionsPhase == 'queen_peek') {
     promptText = 'Tap a card to peek';
     shouldShow = true;
   } else if (demoInstructionsPhase == 'jack_swap') {
     promptText = 'Tap two cards to swap';
     shouldShow = true;
   }
   ```

**Queen Peek Implementation:**
- When user selects a card to peek at:
  - Action intercepted by `_handleQueenPeek()`
  - Card ID extracted from payload (`card_id` and `ownerId`)
  - Full card data retrieved from `originalDeck` using `_getCardById()`
  - Card added to `myCardsToPeek` with full data (suit, rank, points visible)
  - Player status immediately set to `'waiting'` (not `'playing_card'`)
  - Peeked card displayed with full details
  - 3-second timer starts automatically
  - After timer expires:
    - User's hand updated from 4 queens to 4 jacks (one per suit)
    - Player status updated to `'playing_card'`
    - `myCardsToPeek` cleared (card goes back to face-down)
    - `demoInstructionsPhase` set to `'special_plays'` (for jack swap demo)
    - Instructions and prompt text updated

**Jack Swap Implementation:**
- When user selects two cards to swap:
  - Action intercepted by `_handleJackSwap()`
  - Payload contains: `first_card_id`, `first_player_id`, `second_card_id`, `second_player_id`
  - Both players found in game state
  - Both cards found in their respective hands
  - Full card data retrieved using `_getCardById()` for both cards
  - Cards converted to ID-only format (face-down format)
  - Cards swapped between hands:
    - First player's hand updated with second card (ID-only)
    - Second player's hand updated with first card (ID-only)
  - If user is involved, status updated to `'playing_card'`
  - State synchronized:
    - `myHandCards` updated if user is involved
    - `opponentsPanel` updated if opponents are involved
    - Widget slices (`centerBoard`, `myHand`, `opponentsPanel`) updated
  - `demoInstructionsPhase` set to `'playing'` after swap completes
  - Instructions and prompt text updated

**Key Points for Special Play Implementation:**
- Follow the exact same pattern as `_handleQueenPlay()` for play handlers
- Use `updateStateSync()` for SSOT and widget slice updates
- Use `updateState()` for `demoInstructionsPhase` to trigger widget rebuilds
- **DO NOT** set `gamePhase` to `'queen_peek'` or `'jack_swap'` - these values are not allowed by the validator
- Set `currentPlayer` in the game state so `_getCurrentUserStatus()` can find the user's status
- Update both `centerBoard` and `myHand` widget slices with the new status
- Add instruction entry in `_demoPhaseInstructions`
- Add prompt text condition in `SelectCardsPromptWidget`
- For jack swap, update `opponentsPanel` slice if opponents are involved in the swap

**Key Implementation Details:**
- Cards removed from hand create blank slots (index ≤ 3) or are removed entirely (index > 3)
- Drawn cards repositioned to fill blank slots created by played cards
- All players' status updated to `'same_rank_window'` after card is played
- Opponents automatically play matching rank cards after 3-second delay
- Same rank instructions appear 3 seconds after opponent plays
- Hand manipulation uses mutable `List<dynamic>` to allow null values for blank slots

## Game Initialization

### Mode Selection

Users select demo mode via two buttons:
1. **"Start Dutch demo"** - Regular mode (`isClearAndCollect: false`)
2. **"Start Dutch Clear and collect demo"** - Clear and Collect mode (`isClearAndCollect: true`)

### Initialization Steps

1. **Create Predefined Cards**
   - Generate 54 cards manually (no deck factory)
   - Store in `_originalDeck` for lookups
   - Queens are excluded from draw pile (they're in user's hand during special plays phase)

2. **Create Players with Hardcoded Hands**
   - Current user + 3 opponents
   - **User hand**: Ace hearts, 5 diamonds, 8 clubs, 4 hearts
   - **Opponent 1 hand**: 2 clubs, 3 hearts, 6 diamonds, 9 hearts (other numbers, no ace/jack/queen)
   - **Opponent 2 hand**: King spades (at index 0), 2 hearts, 6 clubs, 9 diamonds (has K, rest other numbers)
   - **Opponent 3 hand**: Ace spades, 5 clubs, 8 diamonds, 4 clubs (same ranks as user, different suits)
   - All players get ID-only cards (face-down)
   - All player statuses set to `'initial_peek'`
   - Opponents do not have special cards (Queen/Jack) in their predefined hands

3. **Deal Cards**
   - 4 cards to each player (hardcoded distribution)
   - Remaining cards go to draw pile
   - First card goes to discard pile (face-up)
   - Next 3 cards in draw pile are regular number cards (not special cards)
   - Queens are filtered out from draw pile

4. **Set Game State**
   - Game phase: `'initial_peek'`
   - Game ID: `demo_game_<timestamp>`
   - Round/Turn: 1

5. **Update StateManager**
   - Sync local state to `StateManager` for widget display
   - Compute widget slices (`gameInfo`, `myHand`, `opponentsPanel`)
   - Set transport mode to `demo`
   - Set `demoInstructionsPhase` to `'initial'`

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
- `same_rank` - Instructions for same rank window (shown 3 seconds after opponent plays)
- `wrong_same_rank_penalty` - Instructions shown when user plays wrong rank in same rank window (with "Let's go" button)
- `special_plays` - Instructions for special card plays (queen/jack)
- `queen_peek` - Instructions for Queen special power (shown after queen is played)
  - Title: "Queen Peek:"
  - Text: "When a queen is played, that player can take a quick peek at any card from any player's hand, including their own."
  - Prompt text: "Tap a card to peek"
- `jack_swap` - Instructions for Jack special power
  - Title: "Jack Swap:"
  - Text: "When a jack is played, that player can switch any two cards between any players."
  - Prompt text: "Tap two cards to swap"

**Instruction Widget Behavior:**
- Overlay positioned at top of screen (doesn't take layout space)
- Dark semi-transparent background matching theme
- Automatically hides when first card is selected during initial peek
- Transitions between phases based on user actions and timers
- Same rank instructions use timer-based display (3 seconds after opponent plays)

**Same Rank Instructions:**
- Text: "An opponent has played a card of the same rank, and now they have 3 cards left. During same rank window any player can play a card of the same rank. If an incorrect rank is attempted, that player will be given an extra penalty card."
- Display timing: Instructions appear 3 seconds after an opponent plays a same rank card
- Trigger: Automatically shown via timer when opponent auto-plays matching rank card
- Phase transition: Instructions hidden when player plays a card, shown again after next opponent play
- Card count: Hardcoded to "3 cards" (not dynamic)
- Prompt text: "Tap any card from your hand" appears above myhand at the same time as same rank instructions

**Wrong Same Rank Penalty Instructions:**
- Phase: `wrong_same_rank_penalty`
- Title: "You played a wrong rank"
- Text: "When playing a wrong rank in the same rank window you will be given an extra penalty card. Now you have 5 cards. Next we will wait for your opponents to play their turns."
- Card count: Hardcoded to "5 cards" (not dynamic)
- Button: "Let's go" button that triggers opponent simulation
- Trigger: Shown when user plays a card of wrong rank during same rank window
- Action: After "Let's go" button is pressed, opponent simulation begins

**Special Plays Instructions:**
- Phase: `special_plays`
- Title: "Special Plays"
- Text: "When a queen or a jack is played, that player will have a special play."
- Prompt text: "Tap any card from your hand" appears above myhand
- Trigger: Shown after opponent simulation completes (after opponent 3 plays)
- User hand: Updated to 4 queens (one of each suit: hearts, diamonds, clubs, spades) with actual card IDs from originalDeck
- User status: Set to `playing_card` to enable card interaction
- **After Queen Peek**: User hand automatically updated to 4 jacks (one per suit) after 3-second peek timer expires, then `demoInstructionsPhase` set to `special_plays` for jack swap demo

**Select Cards Prompt:**
- Flashing prompt text above myhand section that changes based on demo phase
- Text variations:
  - "Select two cards" (initial peek phase)
  - "Tap the draw pile" (drawing phase)
  - "Select any card to play" (playing phase)
  - "Tap any card from your hand" (same rank phase - appears at same time as same rank instructions)
  - "Tap any card from your hand" (special_plays phase - appears when special plays instruction is shown)
  - "Tap a card to peek" (queen_peek phase - appears when queen peek instructions are shown)
  - "Tap two cards to swap" (jack_swap phase - appears when jack swap instructions are shown)
- Positioned dynamically using GlobalKey to measure actual myhand height
- Only visible during:
  - Initial peek phase when 0-1 cards selected
  - Drawing phase when no card has been drawn yet (`myDrawnCard == null`)
  - Playing phase (when `demoInstructionsPhase == 'playing'`)
  - Same rank phase (when `demoInstructionsPhase == 'same_rank'` - appears 3 seconds after opponent plays)
  - Special plays phase (when `demoInstructionsPhase == 'special_plays'`)
  - Queen peek phase (when `demoInstructionsPhase == 'queen_peek'`)
  - Jack swap phase (when `demoInstructionsPhase == 'jack_swap'`)
- Automatically hides when appropriate action is taken or phase changes
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

### Player ID Pattern

The event validation system has been updated to accept demo player IDs:
- Pattern includes `demo_[a-zA-Z0-9_]+` prefix for demo players
- Used in fields: `ownerId`, `queen_peek_player_id`, `first_player_id`, `second_player_id`
- Allows demo opponents to be selected for queen peek and jack swap actions

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
- [x] Play card functionality (removes card from hand, adds to discard pile)
- [x] Blank slot creation in hand (for cards at index ≤ 3)
- [x] Drawn card repositioning to fill blank slots
- [x] Same rank window activation after card play
- [x] Opponent same rank auto-play (3-second delay before each opponent)
- [x] Same rank instructions with timer (3 seconds after opponent plays)
- [x] Wrong same rank penalty handling (penalty card, instruction with "Let's go" button)
- [x] Opponent simulation after penalty (predefined plays for each opponent)
- [x] Special plays instruction phase (shown after opponent simulation)
- [x] User hand update to 4 queens (one per suit) with actual card IDs
- [x] Queen play interception and routing to special handler
- [x] Queen peek instructions after queen is played
- [x] Queen peek card selection and display with timer
- [x] Queen peek timer (3 seconds) with hand update to jacks after expiration
- [x] Jack play interception and routing to special handler
- [x] Jack swap instructions after jack is played
- [x] Jack swap card swapping between any players (user and opponents)
- [x] Jack swap state updates (myHandCards, opponentsPanel, widget slices)
- [x] Hardcoded hands for all players (user and opponents)
- [x] Queens excluded from draw pile
- [x] Status text corrections (`drawing_card`, `playing_card` instead of `drawing`, `playing`)
- [x] Human player exclusion from `same_rank_window` during opponent simulation
- [x] Timer management (all timers stopped after opponent simulation)

### 🚧 Pending Implementation

- [ ] Demo-specific action handlers in `DemoFunctionality`
  - [x] `_handleInitialPeek()` - Initial peek logic (shows card details)
  - [x] `_handleCompletedInitialPeek()` - Complete initial peek logic (starts timer)
  - [x] `_handleDrawCard()` - Draw card logic (adds card to hand, updates status to playing)
  - [x] `_handlePlayCard()` - Play card logic (removes from hand, adds to discard, triggers same rank window, routes queen/jack plays)
  - [x] `_handleOpponentSameRankPlays()` - Auto-play opponent matching rank cards (3-second delay)
  - [x] `_handleSameRankPlay()` - Handle valid same rank play
  - [x] `_handleWrongSameRankPlay()` - Handle wrong same rank play (penalty card, instruction)
  - [x] `endSameRankWindowAndSimulateOpponents()` - Opponent simulation after penalty (predefined plays)
  - [x] `_handleQueenPlay()` - Handle queen play (special play routing, queen peek instructions)
- [x] `_handleJackPlay()` - Handle jack play (special play routing, jack swap instructions, skips same rank window)
- [x] `_handleQueenPeek()` - Handle queen peek (card selection, display, timer, hand update to jacks)
- [x] `_handleJackSwap()` - Handle jack swap (card swapping between any players, state updates)
  - [ ] `_handleReplaceDrawnCard()` - Replace drawn card logic
  - [ ] `_handlePlayDrawnCard()` - Play drawn card logic
  - [ ] `_handleCallFinalRound()` - Call final round logic
  - [ ] `_handleCollectFromDiscard()` - Collect from discard logic
  - [ ] `_handleUseSpecialPower()` - Special power logic
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
- Opponent auto-play uses fixed 3-second delay before each opponent plays (for demo consistency)
- Same rank instructions use timer-based display (3 seconds after opponent plays) to avoid showing instructions before opponent action is visible
- Hand manipulation allows null values in list for blank slots (cards at index ≤ 3 create blank slots, others are removed entirely)
- Opponent simulation uses predefined play indices: Opponent 1 plays index 3, Opponent 2 plays index 2, Opponent 3 plays index 4 (the drawn card)
- Each opponent in simulation: draws card, waits 2 seconds, plays card, waits 1 second, drawn card moves to played card's position
- All timers are cancelled and set to null after opponent simulation completes
- Human player is excluded from `same_rank_window` status during opponent simulation
- User's hand is updated to 4 queens (one per suit) with actual card IDs from originalDeck when special plays instruction is shown
- Queens are filtered out from draw pile during initialization
- Card counts in instructions are hardcoded (not dynamic): "3 cards" for same rank, "5 cards" for penalty
- Queen play is intercepted and routed to `_handleQueenPlay()` which handles the special play logic and shows queen peek instructions
- All state updates use `DutchGameStateUpdater.updateState()` (not `updateStateSync()`) to ensure widget slice recomputation
- State updates include all necessary fields (`currentGameId`, `games`, `discardPile`, `drawPileCount`, `turn_events`, `currentPlayer`, `currentPlayerStatus`, `playerStatus`) to trigger widget dependencies

## Special Play Implementation Pattern (Queen Peek / Jack Swap)

### Summary

When implementing special plays (queen peek, jack swap, etc.), follow this exact pattern:

1. **Intercept in `_handlePlayCard()`**: Check card rank and route to special handler
2. **Re-read SSOT**: Always re-read latest state from `StateManager` to avoid stale references
3. **Update Player Status**: Set player status in SSOT (`userPlayer['status'] = 'special_play'`)
4. **Update SSOT Structure**: Create deep copies of game state structure and update with new player status
5. **Update Widget Slices**: Manually update `centerBoard` and `myHand` slices with new status
6. **Three-Step State Sync**:
   - Step 1: `updateStateSync()` for SSOT and main state fields
   - Step 2: `updateStateSync()` for widget slices
   - Step 3: `updateState()` for `demoInstructionsPhase` (triggers widget rebuilds)
7. **Configure Instructions**: Add entry in `_demoPhaseInstructions` list
8. **Configure Prompt Text**: Add condition in `SelectCardsPromptWidget`

### Critical Notes

- **DO NOT** set `gamePhase` to special play values (`'queen_peek'`, `'jack_swap'`) - these are not allowed by the validator
- **DO** set `currentPlayer` in game state so `_getCurrentUserStatus()` can find the user's status
- **DO** use `updateState()` (not `updateStateSync()`) for `demoInstructionsPhase` to ensure `ListenableBuilder` rebuilds
- **DO** update both `centerBoard` and `myHand` widget slices with the new status
- **DO** re-read state from SSOT at the start of the handler to avoid stale references

### Reference Implementations

- **Queen Play**: See `_handleQueenPlay()` in `demo_functionality.dart` (lines 629-900) for the complete implementation pattern
- **Jack Play**: See `_handleJackPlay()` in `demo_functionality.dart` (lines 902-1170) - follows same pattern as queen play
- **Queen Peek**: See `_handleQueenPeek()` in `demo_functionality.dart` (lines 1871-2055) - includes timer and hand update logic
- **Jack Swap**: See `_handleJackSwap()` in `demo_functionality.dart` (lines 1864-2070) - handles card swapping between any players

