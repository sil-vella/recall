# Demo Mode System

## Overview

The Demo Mode System provides individual, focused demo experiences for specific game mechanics. Each demo action is a separate, tappable demo that:
- Clears and resets state entirely before starting
- Starts a fresh practice match with `showInstructions: true` and test deck
- Sets up game state for the specific action being demonstrated
- Navigates to game play screen with all state correctly set
- Uses unified state updater to trigger widget updates
- Displays instructions widget and action text widget as overlays
- Prevents game progression (timers disabled when `showInstructions: true`)

## Architecture

### Core Components

1. **DemoScreen** (`screens/demo/demo_screen.dart`)
   - Main demo screen that displays a grid of action buttons
   - Each button triggers a specific demo action
   - No local state management - uses practice match logic

2. **DemoActionHandler** (`screens/demo/demo_action_handler.dart`)
   - Centralized handler for all demo actions
   - Clears state, starts practice match, sets up game state
   - Uses unified state updater for all state updates
   - Navigates to game play screen

3. **DemoStateSetup** (`screens/demo/demo_state_setup.dart`)
   - Helper methods to set up game state for each action
   - Each method modifies game state to match action requirements
   - Uses test deck cards for predictable setup

4. **ActionTextWidget** (`screens/game_play/widgets/action_text_widget.dart`)
   - Displays contextual action prompts (e.g., "Tap a card to peek", "Draw a card")
   - Overlay widget positioned at bottom of screen
   - Only visible when `showInstructions: true`
   - Reads from `actionText` state slice

5. **InstructionsWidget** (`screens/game_play/widgets/instructions_widget.dart`)
   - Existing instructions widget (already integrated)
   - Automatically shows when `showInstructions: true` and game state matches instruction trigger
   - Uses `GameInstructionsProvider` to get instruction content
   - Shows as modal overlay

6. **Practice Match Integration**
   - Uses existing `PracticeModeBridge` for practice match initialization
   - Uses `PlayerAction.startMatch()` with `showInstructions: true` and `testingModeOverride: true`
   - Leverages existing practice match logic for state initialization

## State Management

### Unified State Updater

All state updates go through `DutchGameHelpers.updateUIState()`:
- Ensures widget slices are recomputed
- Triggers `ListenableBuilder` rebuilds
- Follows same pattern as practice match and multiplayer

### State Structure

The demo state follows the same structure as practice matches:
- `games[gameId].gameData.game_state` - Single source of truth for game state
- Uses practice match initialization logic
- Test deck provides predictable card distribution
- `showInstructions: true` disables timers (prevents auto-progression)

### Action Text State

The `actionText` state slice controls the action text widget:
```dart
'actionText': {
  'isVisible': bool,
  'text': String,  // Prompt text for current action
}
```

This is updated by demo action handlers to show contextual prompts.

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

## Demo Actions

The demo screen displays a grid of buttons for each action:

1. **Initial Peek** - Game in `initial_peek` phase
2. **Drawing** - Game started, player in `drawing_card` status
3. **Playing** - Game started, player in `playing_card` status with drawn card
4. **Same Rank** - Game in `same_rank_window` phase
5. **Queen Peek** - Game started, player played Queen, in `queen_peek` status
6. **Jack Swap** - Game started, player played Jack, in `jack_swap` status
7. **Call Dutch** - Game started, player can call Dutch (button visible)
8. **Collect Rank** - Game in `initial_peek` phase, collection mode enabled

## Demo Action Flow

### Starting a Demo Action

1. **User Taps Demo Button**
   - Button in grid triggers `DemoActionHandler.startDemoAction(actionType)`

2. **Clear All State**
   - `DutchGameHelpers.removePlayerFromGame()` clears game state
   - `PracticeModeBridge.endPracticeSession()` ends any existing practice session
   - All state fields reset to defaults

3. **Start Practice Match**
   - `PracticeModeBridge.startPracticeSession()` creates practice room
   - `PlayerAction.startMatch()` with:
     - `showInstructions: true` (enables instructions, disables timers)
     - `testingModeOverride: true` (uses test deck)
     - `isClearAndCollect: true/false` (based on action)

4. **Set Up Game State**
   - `DemoStateSetup.setupActionState()` modifies game state for specific action
   - Each action has its own setup method that configures:
     - Player status
     - Game phase
     - Piles (draw/discard)
     - Current player
     - Other action-specific requirements

5. **Sync State**
   - `DutchEventManager().handleGameStateUpdated()` syncs widget states
   - `DutchGameHelpers.updateUIState()` triggers widget slice recomputation
   - All widgets rebuild via `ListenableBuilder`

6. **Navigate to Game Play Screen**
   - `NavigationManager().navigateTo('/dutch/game-play')`
   - Instructions widget automatically shows (if enabled)
   - Action text widget shows contextual prompt

### Action State Setup

Each demo action requires specific game state:

- **Initial Peek**: `phase: 'initial_peek'`, player in `initial_peek` status
- **Drawing**: `phase: 'playing'`, player in `drawing_card` status, game started
- **Playing**: `phase: 'playing'`, player in `playing_card` status, has `drawnCard`, game started
- **Same Rank**: `phase: 'same_rank_window'`, player in `same_rank_window` status, discard pile has card
- **Queen Peek**: `phase: 'playing'`, player in `queen_peek` status, Queen in discard pile
- **Jack Swap**: `phase: 'playing'`, player in `jack_swap` status, Jack in discard pile
- **Call Dutch**: `phase: 'playing'`, player in `playing_card` status, `finalRoundActive: false`, `hasCalledFinalRound: false`
- **Collect Rank**: `phase: 'initial_peek'`, `isClearAndCollect: true`, player in `initial_peek` status

## Instructions and Action Text System

### Instructions Widget

The existing `InstructionsWidget` automatically shows when:
- `showInstructions: true` in game state
- Game state matches instruction trigger (phase/status/turn)
- Instruction hasn't been dismissed ("don't show again")

**Instruction Types:**
- `initial` - Welcome message
- `initial_peek` - Instructions for selecting 2 cards to peek at
- `drawing_card` - Instructions for drawing a card
- `playing_card` - Instructions for playing a card
- `same_rank_window` - Instructions for same rank window
- `queen_peek` - Instructions for Queen special power
- `jack_swap` - Instructions for Jack special power
- `collection_card` - Instructions for collection cards (collection mode only)

### Action Text Widget

The `ActionTextWidget` displays contextual action prompts:
- Overlay positioned at bottom of screen
- Shows action-specific prompt text
- Only visible when `showInstructions: true` and `actionText.isVisible == true`
- Updates based on `playerStatus` and `gamePhase`

**Action Text Examples:**
- "Tap a card to peek" (queen peek)
- "Tap two cards to swap" (jack swap)
- "Draw a card" (drawing)
- "Select any card to play" (playing)
- "Tap 'Call Dutch' then play a card" (call Dutch)

The action text is set by demo action handlers via state updates:
```dart
DutchGameHelpers.updateUIState({
  'actionText': {
    'isVisible': true,
    'text': 'Tap a card to peek',
  },
});
```

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

- [x] Demo screen refactored to show action buttons grid
- [x] DemoActionHandler with centralized action handling
- [x] DemoStateSetup with state setup helpers for each action
- [x] Practice match integration with showInstructions and test deck
- [x] Unified state updater usage (DutchGameHelpers.updateUIState)
- [x] State cleanup before each demo action
- [x] ActionTextWidget for contextual prompts
- [x] ActionTextWidget integrated into GamePlayScreen
- [x] State validator updated with actionText schema
- [x] Navigation to game play screen after demo action setup
- [x] Instructions widget integration (existing, works automatically)
- [x] Timer prevention (timers disabled when showInstructions: true)

### Demo Actions Implemented

- [x] Initial Peek - Game state setup for initial peek phase
- [x] Drawing - Game state setup for drawing action
- [x] Playing - Game state setup for playing action
- [x] Same Rank - Game state setup for same rank window
- [x] Queen Peek - Game state setup for queen peek action
- [x] Jack Swap - Game state setup for jack swap action
- [x] Call Dutch - Game state setup for call Dutch action
- [x] Collect Rank - Game state setup for collect rank action (collection mode)

### 🚧 Future Enhancements

- [ ] Action completion detection (prevent game from moving forward)
- [ ] Action-specific action text updates
- [ ] Enhanced state setup for more complex scenarios
- [ ] Additional demo actions as needed

## Usage

### Starting a Demo Action

1. Navigate to demo screen
2. Tap any demo action button (e.g., "Drawing", "Playing", "Queen Peek")
3. Demo action handler:
   - Clears all state
   - Starts fresh practice match with instructions enabled
   - Sets up game state for the specific action
   - Navigates to game play screen
4. Instructions widget automatically shows (if enabled)
5. Action text widget shows contextual prompt
6. User can complete the action (game waits, no timer)

### Demo vs Practice vs Multiplayer

| Feature | Demo | Practice | Multiplayer |
|---------|------|----------|-------------|
| Backend Required | ❌ | ❌ | ✅ |
| WebSocket Required | ❌ | ❌ | ✅ |
| State Management | Practice Match Logic | Backend Bridge | WebSocket |
| Instructions | ✅ Always Enabled | ✅ Optional | ❌ |
| Test Deck | ✅ Always Used | ✅ When Instructions On | ❌ |
| Timers | ❌ Disabled | ✅ When Instructions Off | ✅ Enabled |
| Action Routing | Practice Bridge | `PracticeModeBridge` | WebSocket |
| Game ID Prefix | `practice_room_` | `practice_room_` | `room_` |

## File Structure

```
flutter_base_05/lib/modules/dutch_game/
├── screens/
│   ├── demo/
│   │   ├── demo_screen.dart              # Main demo screen with action buttons
│   │   ├── demo_action_handler.dart     # Centralized demo action handler
│   │   └── demo_state_setup.dart        # Game state setup helpers for each action
│   └── game_play/
│       └── widgets/
│           ├── instructions_widget.dart  # Instructions modal (existing)
│           └── action_text_widget.dart  # Action text overlay (new)
├── managers/
│   └── dutch_game_state_updater.dart    # State updater with unified updateUIState
├── practice/
│   └── practice_mode_bridge.dart        # Practice match initialization
└── utils/
    ├── dutch_game_helpers.dart          # Unified state updater
    └── state_queue_validator.dart      # State schema (includes actionText)
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

## Implementation Details

### Demo Action Handler

The `DemoActionHandler` provides a centralized `startDemoAction()` method that:

1. **Clears State**: Uses `DutchGameHelpers.removePlayerFromGame()` and `PracticeModeBridge.endPracticeSession()`
2. **Starts Practice Match**: Creates practice session and starts match with `showInstructions: true` and `testingModeOverride: true`
3. **Sets Up Game State**: Calls `DemoStateSetup.setupActionState()` to configure game state for the action
4. **Syncs State**: Uses `DutchEventManager().handleGameStateUpdated()` and `DutchGameHelpers.updateUIState()`
5. **Navigates**: Navigates to game play screen

### Demo State Setup

The `DemoStateSetup` class provides helper methods for each action:

- `setupInitialPeekState()` - Sets phase to `initial_peek`, player status to `initial_peek`
- `setupDrawingState()` - Sets phase to `playing`, player status to `drawing_card`
- `setupPlayingState()` - Sets phase to `playing`, player status to `playing_card`, adds drawn card
- `setupSameRankState()` - Sets phase to `same_rank_window`, simulates a card being played
- `setupQueenPeekState()` - Sets phase to `playing`, player status to `queen_peek`, adds Queen to discard
- `setupJackSwapState()` - Sets phase to `playing`, player status to `jack_swap`, adds Jack to discard
- `setupCallDutchState()` - Sets phase to `playing`, player status to `playing_card`, ensures call Dutch button visible
- `setupCollectRankState()` - Sets phase to `initial_peek`, enables collection mode

Each method:
- Takes current game state from `GameStateStore`
- Modifies game state to match action requirements
- Updates `GameStateStore` with modified state
- Returns modified game state

### Test Deck Usage

When `testingModeOverride: true` is passed to `YamlDeckFactory`:
- Test deck configuration is used (from `assets/deck_config.yaml`)
- Provides predictable card distribution
- See `DECK_CREATION_RESHUFFLING_AND_CONFIG.md` for details

### Timer Prevention

When `showInstructions: true`:
- `_shouldStartTimer()` in `DutchGameRound` returns `false`
- Timers are disabled for draw and play actions
- Game waits for user action (no automatic progression)

### Action Completion Detection

**Future Enhancement**: Detect when action is completed and prevent game from moving forward. This should utilize the `showInstructions` flag to keep timers disabled, ensuring the game waits for user interaction.

