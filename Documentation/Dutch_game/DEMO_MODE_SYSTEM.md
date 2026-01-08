# Dutch Game Demo Mode System

## Overview

The Demo Mode System provides an interactive learning experience for the Dutch card game. It allows users to practice individual game actions in isolation, with each demo action starting from a clean state and providing contextual instructions.

### Key Features

- **Modular Actions**: Each demo action is independent and can be accessed individually
- **Clean State Management**: Each demo starts with a completely cleared state to prevent interference
- **Practice Match Integration**: Uses the practice match system with test deck and instructions enabled
- **Automatic Completion Detection**: Detects when a demo action is completed and handles cleanup
- **Contextual Instructions**: Shows relevant instructions at the start of each demo action
- **Custom Close Actions**: Supports instruction-specific close button behaviors

## Architecture

The demo system follows a modular architecture with clear separation of concerns:

```
DemoScreen (UI)
    ↓
DemoActionHandler (Orchestration)
    ↓
├── PracticeModeBridge (Practice Match Setup)
├── DemoStateSetup (State Configuration)
├── GameStateStore (State Persistence)
└── InstructionsWidget (Instruction Display)
```

### Component Responsibilities

1. **DemoScreen**: UI entry point with grid of demo action buttons
2. **DemoActionHandler**: Central orchestrator for all demo actions
3. **DemoStateSetup**: Configures game state for specific demo scenarios
4. **PracticeModeBridge**: Manages practice match lifecycle
5. **GameStateStore**: In-memory storage for game state
6. **InstructionsWidget**: Displays contextual instructions with custom close actions

## Core Components

### DemoActionHandler

**Location**: `lib/modules/dutch_game/screens/demo/demo_action_handler.dart`

Central singleton handler for all demo actions. Manages the complete lifecycle of demo actions from start to completion.

**Key Methods**:

- `startDemoAction(String actionType)`: Starts a new demo action
- `endDemoAction(String actionType)`: Ends a demo action and navigates back
- `showWrongSameRankInstruction(String actionType)`: Shows penalty instruction for wrong same rank play
- `isDemoActionActive()`: Checks if a demo action is currently active
- `getActiveDemoActionType()`: Gets the currently active demo action type

**State Management**:
- Tracks active demo action type (`_activeDemoActionType`)
- Prevents duplicate end calls (`_isEndingDemoAction` flag)
- Clears all state before starting new demos
- Manages state synchronization between GameStateStore and StateManager

### DemoStateSetup

**Location**: `lib/modules/dutch_game/screens/demo/demo_state_setup.dart`

Helper class that configures game state for each specific demo action. Each method sets up the appropriate phase, player status, and game state.

**Key Methods**:

- `setupActionState()`: Routes to appropriate setup method based on action type
- `setupInitialPeekState()`: Sets up initial peek scenario
- `setupDrawingState()`: Sets up drawing card scenario
- `setupPlayingState()`: Sets up playing card scenario (includes drawn card)
- `setupSameRankState()`: Sets up same rank window scenario (ensures no matching cards in hand)
- `setupQueenPeekState()`: Sets up queen peek scenario
- `setupJackSwapState()`: Sets up jack swap scenario
- `setupCallDutchState()`: Sets up call Dutch scenario
- `setupCollectRankState()`: Sets up collect rank scenario

### DemoScreen

**Location**: `lib/modules/dutch_game/screens/demo/demo_screen.dart`

UI screen displaying a grid of demo action buttons. Each button triggers a specific demo action.

**Supported Actions**:
- Initial Peek
- Drawing
- Playing
- Same Rank
- Queen Peek
- Jack Swap
- Call Dutch
- Collect Rank

## Demo Actions

### Initial Peek

**Action Type**: `'initial_peek'`

**Description**: Demonstrates the initial peek phase where players can look at 2 of their 4 cards.

**State Setup**:
- Phase: `initial_peek`
- Player Status: `initial_peek`
- Hand: 4 face-down ID-only cards

**Completion Detection**: Status changes from `initial_peek` to `waiting` or `drawing_card`

### Drawing

**Action Type**: `'drawing'`

**Description**: Demonstrates drawing a card from the draw pile.

**State Setup**:
- Phase: `playing`
- Player Status: `drawing_card`
- Hand: 4 face-down ID-only cards

**Completion Detection**: Status changes from `drawing_card` to `playing_card`

### Playing

**Action Type**: `'playing'`

**Description**: Demonstrates playing a card after drawing.

**State Setup**:
- Phase: `playing`
- Player Status: `playing_card`
- Hand: 5 cards (4 initial + 1 drawn)
- Drawn Card: Full card data available for display

**Completion Detection**: Status changes from `playing_card` to `same_rank_window`

### Same Rank

**Action Type**: `'same_rank'`

**Description**: Demonstrates playing a card during the same rank window.

**State Setup**:
- Phase: `same_rank_window`
- Player Status: `same_rank_window`
- Hand: 4 face-down ID-only cards (no drawn card)
- Discard Pile: Contains a card with a specific rank
- **Critical**: Hand is guaranteed to have NO cards matching the discard pile top card's rank

**Completion Detection**: Status changes from `same_rank_window` to `waiting`

**Special Behavior**: 
- Shows "Wrong Same Rank" instruction 2 seconds after completion
- Instruction explains penalty for playing wrong rank
- Instruction close button executes end action logic

### Queen Peek

**Action Type**: `'queen_peek'`

**Description**: Demonstrates using the Queen's peek power.

**State Setup**:
- Phase: `playing`
- Player Status: `queen_peek`
- Hand: Contains a Queen card

**Completion Detection**: Status changes from `queen_peek` to `waiting` or `playing_card`

### Jack Swap

**Action Type**: `'jack_swap'`

**Description**: Demonstrates using the Jack's swap power.

**State Setup**:
- Phase: `playing`
- Player Status: `jack_swap`
- Hand: Contains a Jack card

**Completion Detection**: Status changes from `jack_swap` to `waiting` or `playing_card`

### Call Dutch

**Action Type**: `'call_dutch'`

**Description**: Demonstrates calling Dutch to signal the final round.

**State Setup**:
- Phase: `playing`
- Player Status: `playing_card`
- Game State: Ready for Dutch call

**Completion Detection**: Status changes from `playing_card` to `waiting`

### Collect Rank

**Action Type**: `'collect_rank'`

**Description**: Demonstrates collecting cards of the same rank from the discard pile.

**State Setup**:
- Phase: `collect_from_discard`
- Player Status: Appropriate for collection
- Game State: Clear and collect mode enabled

**Completion Detection**: Status changes to `waiting`

## State Management

### State Clearing

Before starting any demo action, the system performs comprehensive state clearing:

1. **Clear Active Demo Action Type**: Prevents false completion detection
2. **Remove Player from Game**: Clears all game state
3. **End Practice Session**: Cleans up practice mode bridge
4. **Clear GameStateStore**: Removes all stored game states
5. **Reset State Fields**: Clears all relevant state fields including:
   - `currentGameId`
   - `currentRoomId`
   - `games`
   - `playerStatus`
   - `previousPlayerStatus`
   - `actionText`
   - `instructions`

### State Synchronization

The system maintains synchronization between two state stores:

1. **GameStateStore**: Backend-like game state (used by game logic)
2. **StateManager**: UI state (used by Flutter widgets)

**Synchronization Process**:
1. GameStateStore is updated with action-specific state
2. StateManager is updated with UI-relevant fields
3. `DutchGameHelpers.updateUIState()` triggers widget slice recomputation
4. `DutchEventManager().handleGameStateUpdated()` ensures all widgets are notified

### State Fields

**Critical State Fields for Demos**:
- `currentGameId`: Current practice game ID
- `gameType`: Set to `'practice'` for all demos
- `gamePhase`: Current game phase (normalized for UI)
- `playerStatus`: Current player status
- `previousPlayerStatus`: Used for completion detection
- `currentPlayer`: Top-level current player data
- `actionText`: Contextual action prompts
- `instructions`: Instruction modal state with optional `onClose` callback

## Event Handling

### Completion Detection

Demo action completion is detected in `dutch_event_handler_callbacks.dart`:

**Method**: `_checkDemoActionCompletion()`

**Detection Logic**:
1. Checks if game is practice mode
2. Checks if `showInstructions` is enabled
3. Checks if demo action is active
4. Compares previous and current player status
5. Calls `isActionCompleted()` to determine completion
6. Triggers appropriate end action

**Status Transition Mapping**:
- `initial_peek`: `initial_peek` → `waiting` or `drawing_card`
- `drawing`: `drawing_card` → `playing_card`
- `playing`: `playing_card` → `same_rank_window`
- `same_rank`: `same_rank_window` → `waiting`
- `queen_peek`: `queen_peek` → `waiting` or `playing_card`
- `jack_swap`: `jack_swap` → `waiting` or `playing_card`
- `call_dutch`: `playing_card` → `waiting`
- `collect_rank`: Any → `waiting` (when not already waiting)

### Special Handling: Same Rank Demo

The same rank demo has special completion handling:

1. **Completion Detected**: Status changes from `same_rank_window` to `waiting`
2. **Wait 2 Seconds**: Allows user to see the result
3. **Show Instruction**: Displays "Wrong Same Rank" instruction
4. **Custom Close Action**: Instruction close button executes `endDemoAction()`

**Implementation**:
```dart
if (activeDemoAction == 'same_rank') {
  demoHandler.showWrongSameRankInstruction(activeDemoAction);
} else {
  demoHandler.endDemoAction(activeDemoAction);
}
```

## Instructions System

### Instruction Display

Instructions are displayed using the `InstructionsWidget` which supports:

- **Automatic Display**: Triggered at demo action start
- **Manual Display**: Can be triggered programmatically
- **Custom Close Actions**: Each instruction can have a custom `onClose` callback
- **Demonstration Widgets**: Visual demonstrations for certain actions

### Instruction State Structure

```dart
{
  'isVisible': bool,
  'title': String,
  'content': String,
  'key': String,
  'hasDemonstration': bool,
  'onClose': void Function()?, // Optional custom close callback
  'dontShowAgain': Map<String, bool>, // Per-instruction "don't show again" flags
}
```

### Custom Close Actions

Instructions can have custom close button behaviors:

**Default Behavior**: Simply closes the instruction modal

**Custom Behavior**: Execute custom callback before default behavior

**Example - Wrong Same Rank Instruction**:
```dart
void onCloseCallback() {
  endDemoAction(actionType); // Execute end action logic
}
```

The custom callback is executed first, then the default close behavior (closing modal, clearing state) runs.

### Preventing Automatic Instructions

During demo actions, automatic instruction triggering is disabled:

```dart
if (DemoActionHandler.isDemoActionActive()) {
  return; // Skip automatic instruction triggering
}
```

This ensures demo actions have full control over when instructions are shown.

## Demo Action Lifecycle

### Starting a Demo Action

1. **Clear All State**: Remove any leftover state from previous demos
2. **Set Active Demo**: Mark demo action as active
3. **Start Practice Match**: Create practice match with `showInstructions: true` and test deck
4. **Get Initial State**: Retrieve initial game state from GameStateStore
5. **Setup Action State**: Configure state for specific demo action
6. **Sync State**: Synchronize GameStateStore and StateManager
7. **Show Instructions**: Display contextual instructions for the action
8. **Navigate**: Navigate to game play screen

### During Demo Action

- **State Updates**: Normal game state updates occur
- **Completion Detection**: System monitors status transitions
- **Instruction Control**: Demo action controls instruction display

### Ending a Demo Action

1. **Clear Active Demo**: Keep active demo flag set (prevents instructions from showing)
2. **Clear Demo State**: Clear action text, instructions, previous status
3. **Wait 2 Seconds**: Allow user to see result
4. **Clear Game State**: Remove player from game, clear GameStateStore
5. **End Practice Session**: Clean up practice mode bridge
6. **Navigate**: Navigate back to demo screen
7. **Clear Active Demo**: Finally clear active demo flag

**Note**: The active demo flag is kept set until after navigation to prevent instructions from showing during the delay period.

## Code Structure

### File Organization

```
lib/modules/dutch_game/screens/demo/
├── demo_action_handler.dart      # Main orchestrator
├── demo_state_setup.dart          # State configuration
├── demo_screen.dart               # UI entry point
├── demo_functionality.dart        # Legacy demo functionality (deprecated)
├── demo_instructions_widget.dart  # Legacy instructions (deprecated)
├── demo_mode_bridge.dart          # Legacy bridge (deprecated)
└── select_cards_prompt_widget.dart # Legacy widget (deprecated)
```

### Key Dependencies

- **PracticeModeBridge**: Practice match management
- **GameStateStore**: In-memory game state storage
- **StateManager**: Flutter state management
- **DutchGameStateUpdater**: State update validation
- **DutchEventManager**: Event handling
- **GameInstructionsProvider**: Instruction content
- **NavigationManager**: Screen navigation

## Usage Examples

### Starting a Demo Action

```dart
final demoHandler = DemoActionHandler.instance;
await demoHandler.startDemoAction('same_rank');
```

### Checking if Demo is Active

```dart
if (DemoActionHandler.isDemoActionActive()) {
  final activeAction = DemoActionHandler.getActiveDemoActionType();
  print('Active demo: $activeAction');
}
```

### Showing Custom Instruction

```dart
final stateUpdater = DutchGameStateUpdater.instance;
stateUpdater.updateStateSync({
  'instructions': {
    'isVisible': true,
    'title': 'Custom Instruction',
    'content': 'Instruction content here',
    'key': 'custom_key',
    'hasDemonstration': false,
    'onClose': () {
      // Custom close action
      print('Instruction closed');
    },
  },
});
```

### Setting Up Custom Demo State

```dart
final demoStateSetup = DemoStateSetup();
final gameState = gameStateStore.getGameState(gameId);
final updatedState = await demoStateSetup.setupActionState(
  actionType: 'same_rank',
  gameId: gameId,
  gameState: gameState,
);
```

## Best Practices

### State Management

1. **Always Clear State First**: Clear all state before starting a new demo
2. **Sync Both Stores**: Update both GameStateStore and StateManager
3. **Clear Previous Status**: Always clear `previousPlayerStatus` to prevent false detection
4. **Keep Active Flag Set**: Keep `_activeDemoActionType` set until after navigation

### Completion Detection

1. **Don't Set Previous Status During Initial Sync**: Let it be set on first real state update
2. **Check Active Demo**: Always check if demo is active before showing instructions
3. **Handle Special Cases**: Some demos (like same_rank) need special completion handling

### Instructions

1. **Manual Control**: Demo actions should manually control instruction display
2. **Custom Close Actions**: Use custom close actions for instruction-specific behaviors
3. **Clear Callbacks**: Always clear `onClose` callback after execution

### Error Handling

1. **Try-Catch Blocks**: Wrap all demo operations in try-catch
2. **Logging**: Use comprehensive logging for debugging
3. **Fallback Behavior**: Always have fallback behavior for errors
4. **State Cleanup**: Ensure state is cleaned up even on errors

## Troubleshooting

### Demo Not Starting

- Check if previous demo state is cleared
- Verify practice match is created successfully
- Check GameStateStore has initial state
- Verify state synchronization completed

### Completion Not Detected

- Check `previousPlayerStatus` is being set correctly
- Verify status transitions match expected patterns
- Ensure `_activeDemoActionType` is set
- Check `showInstructions` is enabled

### Instructions Not Showing

- Verify `DemoActionHandler.isDemoActionActive()` returns false for automatic instructions
- Check instruction state is set correctly
- Verify `onClose` callback is not blocking
- Check instruction key is unique

### State Not Clearing

- Verify `_clearAllState()` is called before starting
- Check GameStateStore is cleared for all games
- Ensure StateManager updates are applied
- Verify practice session is ended

## Future Improvements

### Potential Enhancements

1. **Demo Progress Tracking**: Track which demos user has completed
2. **Demo Sequences**: Chain multiple demos together
3. **Custom Demo Scenarios**: Allow users to create custom demo scenarios
4. **Analytics**: Track demo usage and completion rates
5. **Tutorial Mode**: Guided tutorial that walks through all demos

### Refactoring Opportunities

1. **Consolidate Legacy Code**: Remove deprecated demo functionality files
2. **Extract State Setup**: Move state setup logic to separate service
3. **Instruction Provider**: Enhance instruction provider with demo-specific content
4. **Event System**: Create dedicated demo event system

## Related Documentation

- [Practice Mode System](./PRACTICE_MODE_SYSTEM.md)
- [State Management](./STATE_MANAGEMENT.md)
- [Instructions System](./INSTRUCTIONS_SYSTEM.md)
- [Game State Store](./GAME_STATE_STORE.md)

