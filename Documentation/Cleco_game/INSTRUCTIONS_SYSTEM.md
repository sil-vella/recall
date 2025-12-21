# Cleco Game Instructions System

## Overview

The Instructions System provides contextual, interactive guidance to players during practice mode games. It displays helpful instructions at key moments in gameplay, helping new players learn the game mechanics while allowing experienced players to dismiss instructions they no longer need.

## Key Features

- **Contextual Instructions**: Instructions appear automatically based on game phase and player status
- **User Preferences**: Players can mark instructions as "Understood, don't show again" to prevent them from appearing again
- **Practice Mode Only**: Instructions are only enabled in practice mode games
- **Non-Intrusive**: Instructions appear as modal dialogs that can be dismissed by tapping outside or using the close button
- **State-Aware**: Instructions are triggered when game state changes (phase transitions, status changes, turn changes)

## Architecture

### Components

The instructions system consists of three main components:

1. **GameInstructionsProvider** (`utils/game_instructions_provider.dart`)
   - Provides instruction content based on game state
   - Determines when instructions should be shown
   - Manages instruction keys and content

2. **InstructionsWidget** (`screens/game_play/widgets/instructions_widget.dart`)
   - Displays instructions as modal dialogs
   - Handles user interaction (close, "don't show again" checkbox)
   - Subscribes to state changes via `ListenableBuilder`

3. **Event Handlers** (`managers/cleco_event_handler_callbacks.dart`)
   - Triggers instructions when game state changes
   - Updates instruction state in `StateManager`
   - Monitors game phase and player status transitions

### State Management

Instructions are managed through the `StateManager` under the `cleco_game` module state:

```dart
{
  'instructions': {
    'isVisible': bool,           // Whether instructions modal should be shown
    'title': String,              // Instruction modal title
    'content': String,            // Instruction modal content (markdown)
    'key': String,                // Instruction key identifier
    'dontShowAgain': {            // Map of instruction keys to boolean
      'initial': bool,
      'initial_peek': bool,
      'drawing_card': bool,
      // ... etc
    }
  }
}
```

## Instruction Types

The system supports 7 different instruction types, each triggered by specific game conditions:

### 1. Initial Instructions (`KEY_INITIAL`)

**Trigger**: When game is in `waiting` phase and instructions are enabled

**Content**: Welcome message with:
- Game objective
- Card values and points
- Game flow overview
- Strategy tips

**Special Behavior**: 
- Checkbox is pre-checked by default
- Shown when practice game starts (before initial peek phase)

### 2. Initial Peek Instructions (`KEY_INITIAL_PEEK`)

**Trigger**: When game phase is `initial_peek` or player status is `initial_peek`

**Content**: Instructions for the initial peek phase:
- How to peek at cards (tap to flip)
- Strategy tips for choosing which cards to peek
- Card values reminder

### 3. Drawing Card Instructions (`KEY_DRAWING_CARD`)

**Trigger**: When player status is `drawing_card` and it's the current user's turn

**Content**: Instructions for drawing a card:
- Options: Draw from draw pile or take from discard pile
- Strategy tips about revealing information
- What happens after drawing

### 4. Playing Card Instructions (`KEY_PLAYING_CARD`)

**Trigger**: When player status is `playing_card` and it's the current user's turn

**Content**: Instructions for playing a card:
- Options: Play drawn card or play from hand
- Card values reminder
- Special card powers (Queens, Jacks)
- Strategy tips

### 5. Queen Peek Instructions (`KEY_QUEEN_PEEK`)

**Trigger**: When player status is `queen_peek` and it's the current user's turn

**Content**: Instructions for using Queen power:
- How to peek at opponent's card
- Strategy tips for using peek information

### 6. Jack Swap Instructions (`KEY_JACK_SWAP`)

**Trigger**: When player status is `jack_swap` and it's the current user's turn

**Content**: Instructions for using Jack power:
- How to swap cards (two-step selection)
- Strategy tips for swapping
- Can swap own cards to reorganize hand

### 7. Same Rank Window Instructions (`KEY_SAME_RANK_WINDOW`)

**Trigger**: When game phase is `same_rank_window`

**Content**: Instructions for playing matching cards out of turn:
- How same rank matching works
- Rank matching ignores color
- Strategy tips for using this feature

## Instruction Triggering Logic

### When Instructions Are Shown

Instructions are triggered when:

1. **Phase Change**: Game phase transitions to a state with instructions
2. **Status Change**: Player status changes to a state with instructions
3. **Turn Change**: It becomes the current user's turn and there are instructions for that state

### When Instructions Are NOT Shown

Instructions are suppressed when:

1. **Disabled**: `showInstructions` flag is `false` in game state or practice settings
2. **Already Dismissed**: User has marked the instruction as "don't show again"
3. **Already Showing**: Same instruction is already displayed (prevents duplicate modals)
4. **Not User's Turn**: Instructions only show for the current user's actions (except for same rank window)

### Triggering Flow

```
Game State Change
    ↓
_triggerInstructionsIfNeeded() called
    ↓
Check showInstructions flag
    ↓
Get current game phase and player status
    ↓
Check if instruction exists for this state
    ↓
Check if user dismissed this instruction
    ↓
Check if instruction already showing
    ↓
Update StateManager with instruction data
    ↓
InstructionsWidget detects state change
    ↓
Show modal dialog
```

## User Preferences

### "Don't Show Again" Feature

Each instruction can be individually dismissed:

1. **Checkbox**: "Understood, don't show again" checkbox in modal footer
2. **Per-Instruction**: Each instruction type has its own preference
3. **Persistent**: Preferences are stored in state and persist during the game session
4. **Initial Instructions**: Checkbox is pre-checked for initial welcome message

### Preference Storage

Preferences are stored in the state as a map:

```dart
'dontShowAgain': {
  'initial': true,           // User dismissed initial instructions
  'drawing_card': false,     // User still wants to see drawing instructions
  'queen_peek': true,        // User dismissed queen peek instructions
  // ... etc
}
```

## Integration Points

### 1. Practice Mode Setup

Instructions are enabled when starting a practice game:

```dart
// In practice_match_widget.dart or lobby_screen.dart
final practiceSettings = {
  'showInstructions': true,  // Toggle in UI
  // ... other settings
};
```

### 2. Game State Configuration

When creating a practice game, `showInstructions` is passed to the game configuration:

```dart
// In game_coordinator.dart
PlayerAction.createGame(
  // ... other params
  showInstructions: practiceSettings['showInstructions'],
);
```

### 3. Event Handler Integration

Instructions are triggered in event handlers when game state updates:

```dart
// In cleco_event_handler_callbacks.dart
static void handleGameStateUpdated(String gameId, Map<String, dynamic> gameState) {
  // ... update game state
  
  // Trigger instructions if needed
  _triggerInstructionsIfNeeded(
    gameId: gameId,
    gameState: gameState,
    playerStatus: currentUserPlayerStatus,
    isMyTurn: isMyTurn,
  );
}
```

### 4. Screen Integration

The `InstructionsWidget` is included in the game play screen:

```dart
// In game_play_screen.dart
@override
Widget buildContent(BuildContext context) {
  return Stack(
    children: [
      // ... game content
      
      // Instructions Modal Widget - handles its own state subscription
      const InstructionsWidget(),
    ],
  );
}
```

## Code Structure

### GameInstructionsProvider

**Location**: `lib/modules/cleco_game/utils/game_instructions_provider.dart`

**Key Methods**:

- `getInitialInstructions()`: Returns initial welcome instructions
- `getInstructions()`: Returns instructions for a given game state
- `getInstructionKey()`: Returns instruction key for a given state
- `shouldShowInstructions()`: Determines if instructions should be shown

**Instruction Keys**:

```dart
static const String KEY_INITIAL = 'initial';
static const String KEY_INITIAL_PEEK = 'initial_peek';
static const String KEY_DRAWING_CARD = 'drawing_card';
static const String KEY_PLAYING_CARD = 'playing_card';
static const String KEY_QUEEN_PEEK = 'queen_peek';
static const String KEY_JACK_SWAP = 'jack_swap';
static const String KEY_SAME_RANK_WINDOW = 'same_rank_window';
```

### InstructionsWidget

**Location**: `lib/modules/cleco_game/screens/game_play/widgets/instructions_widget.dart`

**Key Features**:

- **State Subscription**: Uses `ListenableBuilder` to subscribe to `StateManager`
- **Modal Display**: Uses `showDialog` with `ModalTemplateWidget`
- **Duplicate Prevention**: Tracks currently showing instruction to prevent duplicate modals
- **User Interaction**: Handles close button and "don't show again" checkbox
- **State Updates**: Updates state when modal is closed

**Modal Structure**:

```
ModalTemplateWidget
├── Title (from instruction data)
├── Icon (help_outline)
├── Content (scrollable markdown text)
└── Footer
    ├── Checkbox ("Understood, don't show again")
    └── Close Button
```

### Event Handler Integration

**Location**: `lib/modules/cleco_game/managers/cleco_event_handler_callbacks.dart`

**Key Method**: `_triggerInstructionsIfNeeded()`

**Responsibilities**:

1. Check if instructions are enabled
2. Determine current game phase and player status
3. Check if instructions should be shown
4. Update state with instruction data
5. Handle initial instructions in waiting phase

**Called From**:

- `handleGameStateUpdated()`: When game state changes
- `handlePlayerAction()`: When player actions occur
- `handleGamePhaseChanged()`: When game phase transitions

## State Flow

### Showing Instructions

```
1. Game state changes (phase/status/turn)
   ↓
2. _triggerInstructionsIfNeeded() called
   ↓
3. GameInstructionsProvider.shouldShowInstructions() checks conditions
   ↓
4. If should show:
   - GameInstructionsProvider.getInstructions() gets content
   - StateManager.updateModuleState() updates instruction state
   ↓
5. InstructionsWidget detects state change via ListenableBuilder
   ↓
6. Widget calls _showInstructionsModal()
   ↓
7. Modal dialog displayed to user
```

### Closing Instructions

```
1. User clicks close button or taps outside modal
   ↓
2. _closeInstructions() called
   ↓
3. If "don't show again" checked:
   - Update dontShowAgain map in state
   ↓
4. Update state to hide instructions (isVisible: false)
   ↓
5. Navigator.pop() closes modal
   ↓
6. State cleared (title, content, key set to empty)
```

## Configuration

### Enabling/Disabling Instructions

Instructions are controlled by the `showInstructions` flag:

1. **Practice Settings**: Set in practice match widget before starting game
2. **Game State**: Stored in game state when game is created
3. **Fallback**: If not in game state, checks practice settings

### Timer Interaction

When instructions are enabled, timers are disabled:

```dart
// In cleco_game_round.dart
bool shouldStartTimer() {
  return !(config['showInstructions'] as bool? ?? false);
}
```

This ensures players have time to read instructions without timer pressure.

## Best Practices

### Adding New Instructions

1. **Add Instruction Key**: Add constant to `GameInstructionsProvider`
2. **Add Content**: Add case in `getInstructions()` method
3. **Define Trigger**: Specify when instruction should appear (phase/status/turn)
4. **Test**: Verify instruction appears at correct time and can be dismissed

### Modifying Instruction Content

1. **Update Content**: Modify markdown content in `getInstructions()` method
2. **Test Display**: Verify markdown renders correctly in modal
3. **Check Length**: Ensure content fits in scrollable modal

### Debugging

Enable logging by setting `LOGGING_SWITCH = true` in:
- `InstructionsWidget.LOGGING_SWITCH`
- `ClecoEventHandlerCallbacks.LOGGING_SWITCH`

Look for log messages prefixed with `📚` to track instruction flow.

## Future Enhancements

Potential improvements to the instructions system:

1. **Instruction History**: Track which instructions have been shown
2. **Reset Preferences**: Allow users to reset "don't show again" preferences
3. **Instruction Tips**: Add tooltips or inline hints in addition to modals
4. **Progressive Disclosure**: Show simpler instructions first, detailed ones on demand
5. **Localization**: Support multiple languages for instruction content
6. **Analytics**: Track which instructions are most often dismissed

## Related Documentation

- [State Management](./STATE_MANAGEMENT.md) - How game state is managed
- [Player Actions Flow](./PLAYER_ACTIONS_FLOW.md) - How player actions trigger state changes
- [Practice Mode](./PRACTICE_GAME_DATA_STRUCTURE.md) - Practice mode implementation details
