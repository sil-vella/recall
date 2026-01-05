# Dutch Game Instructions System

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

The system supports 8 different instruction types, each triggered by specific game conditions:

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
- No demonstration widget

### 2. Initial Peek Instructions (`KEY_INITIAL_PEEK`)

**Trigger**: When game phase is `initial_peek` or player status is `initial_peek`

**Content**: Instructions for the initial peek phase:
- How to peek at cards (tap to flip)
- Strategy tips for choosing which cards to peek
- Card values reminder

**Demonstration**: `InitialPeekDemonstrationWidget`
- Shows hand with 4 face-down cards
- Demonstrates tapping to flip cards
- Shows which 2 cards can be peeked

### 3. Drawing Card Instructions (`KEY_DRAWING_CARD`)

**Trigger**: When player status is `drawing_card` and it's the current user's turn

**Content**: Instructions for drawing a card:
- Options: Draw from draw pile or take from discard pile
- Strategy tips about revealing information
- What happens after drawing

**Demonstration**: `DrawingCardDemonstrationWidget`
- Shows game board with draw and discard piles
- Shows "my hand" widget
- Demonstrates drawing from both piles
- Shows card animation from pile to hand

### 4. Playing Card Instructions (`KEY_PLAYING_CARD`)

**Trigger**: When player status is `playing_card` and it's the current user's turn

**Content**: Instructions for playing a card:
- Options: Play drawn card or play from hand
- Card values reminder
- Special card powers (Queens, Jacks)
- Strategy tips

**Demonstration**: `PlayingCardDemonstrationWidget`
- Shows game board with draw and discard piles
- Shows "my hand" widget
- Demonstrates playing a card from hand
- Shows card animation to discard pile
- Shows hand repositioning after play

### 5. Queen Peek Instructions (`KEY_QUEEN_PEEK`)

**Trigger**: When player status is `queen_peek` and it's the current user's turn

**Content**: Instructions for using Queen power:
- How to peek at opponent's card
- Strategy tips for using peek information

**Demonstration**: `QueenPeekDemonstrationWidget`
- Shows opponent's hand with face-down cards
- Demonstrates tapping to peek at a card
- Shows card flip animation
- Shows peeked card revealed

### 6. Jack Swap Instructions (`KEY_JACK_SWAP`)

**Trigger**: When player status is `jack_swap` and it's the current user's turn

**Content**: Instructions for using Jack power:
- How to swap cards (two-step selection)
- Strategy tips for swapping
- Can swap own cards to reorganize hand

**Demonstration**: `JackSwapDemonstrationWidget`
- Shows multiple examples of card swapping
- Demonstrates swapping between players
- Shows swapping own cards
- Shows card animation during swap
- Repeats examples with 2-second delay between cycles

### 7. Same Rank Window Instructions (`KEY_SAME_RANK_WINDOW`)

**Trigger**: When game phase is `same_rank_window`

**Content**: Instructions for playing matching cards out of turn:
- How same rank matching works
- Rank matching ignores color
- Strategy tips for using this feature

**Demonstration**: `SameRankWindowDemonstrationWidget`
- Shows game board with discard pile (no draw pile)
- Shows "my hand" widget
- **Example 1**: Successful play - card matches rank of last played card
  - Card animates from hand to discard pile
  - Animation duration: 800ms
- **Example 2**: Failed play - card doesn't match rank
  - Card animates to discard pile (800ms)
  - Card stays at discard for 1 second
  - Card reverts back to hand (800ms)
  - Penalty card animates from draw pile to hand (800ms)
  - Penalty card placed in 5th position (after last card)
- Examples cycle with 2-second delay between cycles
- No hand repositioning during demo

**Special Behavior**:
- Separate "don't show again" checkbox from collection card instruction
- Counter tracks how many times same rank window is triggered
- Counter increments only when transitioning INTO `same_rank_window` phase

### 8. Collection Card Instructions (`KEY_COLLECTION_CARD`)

**Trigger**: On the **5th time** the `same_rank_window` phase is entered

**Content**: Instructions for collecting cards:
- How collection cards work
- Matching rank with face-up collection card
- Stacking effect when collecting
- Strategy tips

**Demonstration**: `CollectionCardDemonstrationWidget`
- Shows game board with discard pile
- Shows "my hand" widget with face-up collection card
- Discard pile shows last played card (same rank as collection card)
- Animates last played card from discard pile to collection card
- Card placed on top of collection card with slight offset (8px) to show stacking
- Animation duration: 800ms
- Animation repeats every 2 seconds

**Special Behavior**:
- Only triggers on 5th same rank window occurrence
- Separate "don't show again" checkbox from same rank window instruction
- Counter (`sameRankTriggerCount`) tracks transitions into `same_rank_window` phase
- When counter reaches 5 and instruction not dismissed, collection card instruction takes precedence over same rank window instruction

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
5. **Separate Preferences**: Same rank window and collection card instructions have separate preferences

### Preference Storage

Preferences are stored in the state as a map:

```dart
'dontShowAgain': {
  'initial': true,                    // User dismissed initial instructions
  'initial_peek': false,              // User still wants to see initial peek instructions
  'drawing_card': false,               // User still wants to see drawing instructions
  'playing_card': false,               // User still wants to see playing instructions
  'queen_peek': true,                 // User dismissed queen peek instructions
  'jack_swap': false,                 // User still wants to see jack swap instructions
  'same_rank_window': false,          // User still wants to see same rank window instructions
  'collection_card': false,           // User still wants to see collection card instructions
  // ... etc
}
```

**Important**: `same_rank_window` and `collection_card` are **separate** preferences. Dismissing one does not affect the other.

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
static const String KEY_COLLECTION_CARD = 'collection_card';
```

### InstructionsWidget

**Location**: `lib/modules/cleco_game/screens/game_play/widgets/instructions_widget.dart`

**Key Features**:

- **State Subscription**: Uses `ListenableBuilder` to subscribe to `StateManager`
- **Modal Display**: Uses `showDialog` with `ModalTemplateWidget`
- **Duplicate Prevention**: Tracks currently showing instruction to prevent duplicate modals
- **User Interaction**: Handles close button and "don't show again" checkbox
- **State Updates**: Updates state when modal is closed
- **Demonstration Support**: Conditionally displays demonstration widgets based on `hasDemonstration` flag

**Modal Structure**:

```
ModalTemplateWidget
├── Title (from instruction data)
├── Icon (help_outline)
├── Content (scrollable)
│   ├── Demonstration Widget (if hasDemonstration = true)
│   │   ├── InitialPeekDemonstrationWidget (for initial_peek)
│   │   ├── DrawingCardDemonstrationWidget (for drawing_card)
│   │   ├── PlayingCardDemonstrationWidget (for playing_card)
│   │   ├── QueenPeekDemonstrationWidget (for queen_peek)
│   │   ├── JackSwapDemonstrationWidget (for jack_swap)
│   │   ├── SameRankWindowDemonstrationWidget (for same_rank_window)
│   │   └── CollectionCardDemonstrationWidget (for collection_card)
│   └── Text Content (markdown)
└── Footer
    ├── Checkbox ("Understood, don't show again")
    └── Close Button
```

**Demonstration Widgets**:

All demonstration widgets are located in `lib/modules/cleco_game/screens/game_play/widgets/`:

- `initial_peek_demonstration_widget.dart` - Shows card peeking interaction
- `drawing_card_demonstration_widget.dart` - Shows drawing from draw/discard piles
- `playing_card_demonstration_widget.dart` - Shows playing a card with hand repositioning
- `queen_peek_demonstration_widget.dart` - Shows peeking at opponent's card
- `jack_swap_demonstration_widget.dart` - Shows card swapping with multiple examples
- `same_rank_window_demonstration_widget.dart` - Shows successful and failed same rank plays
- `collection_card_demonstration_widget.dart` - Shows collecting a card onto collection card

### Event Handler Integration

**Location**: `lib/modules/cleco_game/managers/cleco_event_handler_callbacks.dart`

**Key Method**: `_triggerInstructionsIfNeeded()`

**Responsibilities**:

1. Check if instructions are enabled
2. Determine current game phase and player status
3. Track same rank window trigger count
4. Check if collection card instruction should trigger (on 5th same rank window)
5. Check if instructions should be shown
6. Update state with instruction data
7. Handle initial instructions in waiting phase

**Same Rank Window Counter Logic**:

- Counter (`sameRankTriggerCount`) is stored in `StateManager` under `cleco_game` module state
- Counter increments **only when transitioning INTO** `same_rank_window` phase
- Counter increment happens **before** state update in `handleGameStateUpdated()` to properly detect phase transitions
- When counter reaches 5 and `KEY_COLLECTION_CARD` instruction hasn't been dismissed:
  - Collection card instruction takes precedence
  - Same rank window instruction is suppressed
  - Collection card instruction is constructed directly (not fetched via `GameInstructionsProvider`)

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
4. **Add Demonstration (Optional)**: Create demonstration widget if `hasDemonstration: true`
5. **Integrate Demonstration**: Add widget to `InstructionsWidget` conditional rendering
6. **Test**: Verify instruction appears at correct time and can be dismissed

### Adding New Demonstrations

1. **Create Widget**: Create new `*_demonstration_widget.dart` file in `widgets/` directory
2. **Follow Pattern**: Use existing demonstration widgets as templates
3. **Use GlobalKeys**: For precise animation positioning, use `GlobalKey` and `RenderBox`
4. **Animation Timing**: Use consistent animation durations (typically 800ms per animation)
5. **Import Widget**: Add import to `instructions_widget.dart`
6. **Add Conditional**: Add widget to conditional rendering chain in `InstructionsWidget`
7. **Test**: Verify demonstration displays correctly and animations work smoothly

### Modifying Instruction Content

1. **Update Content**: Modify markdown content in `getInstructions()` method
2. **Test Display**: Verify markdown renders correctly in modal
3. **Check Length**: Ensure content fits in scrollable modal

### Debugging

Enable logging by setting `LOGGING_SWITCH = false` in:
- `InstructionsWidget.LOGGING_SWITCH`
- `DutchEventHandlerCallbacks.LOGGING_SWITCH`

Look for log messages prefixed with `📚` to track instruction flow.

## Demonstration Widgets

Demonstration widgets provide interactive visual examples of game mechanics. They are displayed above the instruction text content when `hasDemonstration: true` is set in the instruction data.

### Technical Implementation

**Common Patterns**:

1. **Animation Controllers**: All demonstrations use `AnimationController` with `TickerProviderStateMixin`
2. **GlobalKeys for Positioning**: Use `GlobalKey` and `RenderBox` to calculate precise animation paths
3. **Animation Timing**: Standard animation duration is 800ms per animation
4. **Cycle Delays**: Multi-example demonstrations use 2-second delays between cycles
5. **Theme Compliance**: All widgets use `AppColors`, `AppTextStyles`, `AppPadding`, and `AppBorderRadius`

### Widget Details

#### InitialPeekDemonstrationWidget
- **Purpose**: Shows how to peek at cards during initial peek phase
- **Features**: Interactive card flipping, shows which 2 cards can be peeked
- **Animation**: Card flip animation on tap

#### DrawingCardDemonstrationWidget
- **Purpose**: Demonstrates drawing from draw pile and discard pile
- **Features**: Shows game board with both piles, "my hand" widget
- **Animation**: Card animation from pile to hand

#### PlayingCardDemonstrationWidget
- **Purpose**: Shows playing a card from hand
- **Features**: Shows game board, "my hand" widget, hand repositioning after play
- **Animation**: Card animation from hand to discard pile, hand cards reposition

#### QueenPeekDemonstrationWidget
- **Purpose**: Demonstrates peeking at opponent's card
- **Features**: Shows opponent's hand, card flip animation
- **Animation**: Card flip to reveal value

#### JackSwapDemonstrationWidget
- **Purpose**: Shows multiple examples of card swapping
- **Features**: Multiple examples, swapping between players, swapping own cards
- **Animation**: Card swap animation, repeats with 2-second delay
- **Examples**: Shows 2-3 different swap scenarios

#### SameRankWindowDemonstrationWidget
- **Purpose**: Demonstrates successful and failed same rank plays
- **Features**: 
  - Game board with discard pile (no draw pile)
  - "my hand" widget
  - Two examples: successful play and failed play with penalty
- **Animation**:
  - Example 1: Card animates to discard (800ms)
  - Example 2: Card animates to discard (800ms), waits 1 second, reverts (800ms), penalty card animates from draw pile (800ms)
- **Special**: No hand repositioning, penalty card placed in 5th position

#### CollectionCardDemonstrationWidget
- **Purpose**: Shows collecting a card onto collection card
- **Features**:
  - Game board with discard pile
  - "my hand" widget with face-up collection card
  - Discard pile shows last played card (same rank)
- **Animation**: 
  - Last played card animates from discard to collection card (800ms)
  - Card placed with 8px offset to show stacking effect
  - Repeats every 2 seconds

### Animation Best Practices

1. **Consistent Timing**: Use 800ms for standard card animations
2. **Smooth Transitions**: Use `CurvedAnimation` with appropriate curves
3. **Precise Positioning**: Use `GlobalKey` and `RenderBox` for pixel-perfect positioning
4. **State Management**: Use `_animationPhase` or similar to track animation stages
5. **Visibility Control**: Use `Opacity` or conditional rendering for animated elements
6. **Resource Cleanup**: Dispose animation controllers in `dispose()` method

## Future Enhancements

Potential improvements to the instructions system:

1. **Instruction History**: Track which instructions have been shown
2. **Reset Preferences**: Allow users to reset "don't show again" preferences
3. **Instruction Tips**: Add tooltips or inline hints in addition to modals
4. **Progressive Disclosure**: Show simpler instructions first, detailed ones on demand
5. **Localization**: Support multiple languages for instruction content
6. **Analytics**: Track which instructions are most often dismissed
7. **Interactive Demonstrations**: Allow users to interact with demonstration widgets
8. **Demonstration Speed Control**: Allow users to adjust animation speed

## Related Documentation

- [State Management](./STATE_MANAGEMENT.md) - How game state is managed
- [Player Actions Flow](./PLAYER_ACTIONS_FLOW.md) - How player actions trigger state changes
- [Practice Mode](./PRACTICE_GAME_DATA_STRUCTURE.md) - Practice mode implementation details
