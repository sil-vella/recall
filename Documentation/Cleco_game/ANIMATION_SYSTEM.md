# Cleco Game Animation System

## Overview

The Cleco game uses a sophisticated card animation system that tracks card positions across the game board and animates card movements when cards change location. The system is designed to be automatic, requiring minimal manual intervention from widgets. It includes advanced features like empty slot placeholders, drawn card visibility management, and event-driven animation completion notifications.

## Architecture

The animation system consists of four main components:

1. **CardPositionTracker** - Singleton that tracks all card positions and detects movement
2. **CardAnimationLayer** - Full-screen overlay widget that renders animated cards and empty slots
3. **Widget Integration** - Game widgets (MyHandWidget, OpponentsPanelWidget, etc.) that track their card positions
4. **Animation Completion Events** - Event system for widgets to react to animation completion

## Components

### 1. CardPositionTracker (`card_position_tracker.dart`)

**Purpose**: Centralized position tracking and animation detection

**Key Features**:
- Singleton pattern - single instance tracks all cards
- Maintains a map of card positions (`Map<String, CardPositionData>`)
- Detects position changes and determines animation types
- Triggers animations via `ValueNotifier<CardAnimationTrigger?>`
- Notifies animation completion via `ValueNotifier<CardAnimationComplete?>`
- Fallback position search for edge cases (e.g., drawn cards played before position tracked)

**Key Methods**:
- `updateCardPosition()` - Called by widgets to update card positions
- `_triggerCardAnimation()` - Internal method that creates animation triggers
- `notifyAnimationComplete()` - Called by animation layer when animation completes
- `getCardPosition()` - Retrieve position data for a card
- `clearAllPositions()` - Clear all tracked positions (called on screen dispose)

**Position Tracking**:
- Cards are tracked using composite keys:
  - My hand: `cardId`
  - Opponent hands: `playerId_cardId`
  - Piles: `draw_pile`, `discard_pile`, `discard_pile_empty`

**Animation Detection**:
The tracker uses a two-priority system:

1. **Priority 1: Suggested Animation Type** (from widgets via `turn_events`)
   - Widgets can suggest animation types based on game state
   - Takes precedence over position-based detection
   - Used when widgets know the action type (draw, play, collect, reposition)

2. **Priority 2: Position-Based Detection** (fallback)
   - Analyzes position changes to infer animation type
   - Detects: new cards in hand → draw, hand to discard → play, discard to hand → collect, reposition within hand → reposition

**Fallback Position Search**:
- For `play` animations, if the old position is not found, the tracker performs an explicit search through all known positions
- Searches for cards in `my_hand` or `opponent_hand` locations
- Ensures animations can trigger even if position tracking was delayed (e.g., newly drawn cards)

**Animation Completion Events**:
- `cardAnimationComplete` ValueNotifier emits `CardAnimationComplete` events
- Contains: `cardId`, `key`, `animationType`, `playerId`, `timestamp`
- Widgets can listen to these events to react to animation completion (e.g., show drawn cards)
- Events are cleared after one frame to prevent duplicate handling

### 2. CardAnimationLayer (`card_animation_layer.dart`)

**Purpose**: Renders animated cards and empty slot placeholders as a full-screen overlay

**Key Features**:
- Listens to `CardPositionTracker.cardAnimationTrigger` ValueNotifier
- Manages multiple concurrent animations
- Handles animation lifecycle (start, update, cleanup)
- Converts screen coordinates to Stack-relative coordinates
- Manages empty slot placeholders during play/reposition animations
- Emits animation completion events

**Animation Properties**:
- **Duration**: 600ms (fixed)
- **Curve**: `Curves.easeOutCubic`
- **Animations**: Position (Offset) and Size (Size)

**Card Data Handling**:
- **Full Card Data** (for `play` and `collect` animations):
  - Retrieves full card data from game state (`originalDeck`)
  - Shows card face with rank, suit, and points
  
- **Card Back Only** (for `draw` and `reposition` animations):
  - Creates minimal CardModel with `rank='?', suit='?', points=0`
  - Shows card back (privacy for draws, repositioning)

**Empty Slot Management**:
- **Empty Slot Placeholders**: During `play` animations, an empty slot placeholder is created at the play start position
- **Visual Style**: Empty slots use card back color with 0.2 saturation, 8px border radius, 2px border
- **Lifecycle**:
  - Created when `play` animation starts
  - Remains visible during both play and reposition animations
  - Removed when reposition animation completes (if reposition follows)
  - Removed immediately after play completes if no reposition animation follows (e.g., when playing a drawn card)
- **Detection Logic**: Checks for active reposition animations that would fill the slot before removing it
- **Delay Mechanism**: 100ms delay after play completion to catch reposition animations that start slightly after

**Coordinate System**:
- Cards report positions in **screen coordinates** (via `localToGlobal`)
- Animation layer converts to **Stack-relative coordinates** (subtracts app bar + safe area)
- Stack is positioned in Scaffold body (below app bar)

**Animation Completion**:
- When animation completes, calls `CardPositionTracker.notifyAnimationComplete()`
- Passes animation metadata (cardId, key, animationType, playerId)
- Allows widgets to react to animation completion events

### 3. Widget Integration

**Widgets that Track Positions**:
- `MyHandWidget` - Tracks player's hand cards
- `OpponentsPanelWidget` - Tracks opponent hand cards
- `DrawPileWidget` - Tracks draw pile position
- `DiscardPileWidget` - Tracks discard pile position

**Position Tracking Flow**:
1. Widget builds cards with `GlobalKey` for each card
2. On rebuild, widget calls `_updateCardPositions()` in `addPostFrameCallback`
3. For each card:
   - Gets `RenderBox` from `GlobalKey`
   - Calculates screen position via `localToGlobal(Offset.zero)`
   - Gets card size from `RenderBox.size`
   - Extracts animation type from `turn_events` (if available)
   - Calls `tracker.updateCardPosition()` with position, size, location, and suggested animation type

**Turn Events Integration**:
- Widgets read `turn_events` from state slices (`myHand.turn_events`, `opponentsPanel.turn_events`)
- Maps `actionType` strings to `AnimationType` enum:
  - `'draw'` → `AnimationType.draw`
  - `'play'` → `AnimationType.play`
  - `'collect'` → `AnimationType.collect`
  - `'reposition'` → `AnimationType.reposition`
- Passes as `suggestedAnimationType` to tracker

**Drawn Card Visibility Management**:
- **MyHandWidget** and **OpponentsPanelWidget** manage drawn card visibility
- **Initialization**: When a drawn card first appears, it's initialized as hidden (`opacity: 0.0`)
- **Visibility Map**: `Map<String, bool> _visibleDrawnCards` tracks which drawn cards should be visible
- **Animation Completion Listener**: Widgets listen to `CardPositionTracker.cardAnimationComplete`
- **Show on Completion**: When a `draw` animation completes, the drawn card visibility is set to `true`
- **Cleanup**: Old visibility states are cleaned up when a new drawn card appears or when drawn card is removed
- **Position Tracking**: Drawn cards are tracked even when hidden (opacity 0) to ensure animations can find their position when played

**Drawn Card Tracking**:
- Widgets explicitly track drawn cards even when they're visually hidden
- Ensures position data is available for play animations
- Logs when drawn cards are tracked for debugging

### 4. Animation Completion Events

**Purpose**: Allow widgets to react to animation completion

**Event Structure**:
```dart
class CardAnimationComplete {
  final String cardId;
  final String key;
  final AnimationType animationType;
  final String? playerId;
  final DateTime timestamp;
}
```

**Usage**:
- Widgets subscribe to `CardPositionTracker.instance().cardAnimationComplete`
- Listen for `AnimationType.draw` completion events
- Update visibility state when draw animation completes
- Clean up listeners in `dispose()`

**Event Lifecycle**:
1. Animation completes in `CardAnimationLayer`
2. `CardPositionTracker.notifyAnimationComplete()` is called
3. `cardAnimationComplete.value` is set to the completion event
4. Widgets listening to the ValueNotifier receive the event
5. Event is cleared in next frame via `addPostFrameCallback`

## Animation Types

### 1. Draw (`AnimationType.draw`)
- **Trigger**: Card appears in hand from draw pile
- **Start**: Draw pile position
- **End**: Hand position
- **Card Display**: Back only (privacy)
- **Detection**: New card in hand OR suggested from `turn_events`
- **Special Behavior**: 
  - Drawn card is hidden (opacity 0) in widget during animation
  - Becomes visible when animation completes (via completion event)
  - Position tracked even when hidden

### 2. Play (`AnimationType.play`)
- **Trigger**: Card played from hand to discard pile
- **Start**: Hand position
- **End**: Discard pile position
- **Card Display**: Full card data (face visible)
- **Detection**: Position change from hand to discard OR suggested from `turn_events`
- **Special Behavior**:
  - Creates empty slot placeholder at start position
  - Empty slot remains until reposition completes (if reposition follows)
  - Empty slot removed immediately if no reposition follows (e.g., drawn card played)

### 3. Collect (`AnimationType.collect`)
- **Trigger**: Card collected from discard pile to hand
- **Start**: Discard pile position
- **End**: Hand position
- **Card Display**: Full card data (face visible)
- **Detection**: Position change from discard to hand OR suggested from `turn_events`

### 4. Reposition (`AnimationType.reposition`)
- **Trigger**: Card repositioned within hand (same rank play)
- **Start**: Old position in hand
- **End**: New position in hand
- **Card Display**: Back only (privacy)
- **Detection**: Position change within same hand OR suggested from `turn_events`
- **Special Behavior**:
  - Removes empty slot placeholder when reposition completes
  - Fills the gap left by the played card

## Animation Flow

### Complete Flow Diagram

```
1. Game State Update (WebSocket event)
   ↓
2. State Manager updates game state
   ↓
3. Widget rebuilds (ListenableBuilder)
   ↓
4. Widget calls _updateCardPositions() (post-frame callback)
   ↓
5. For each card:
   - Get RenderBox from GlobalKey
   - Calculate screen position (localToGlobal)
   - Extract animation type from turn_events
   - Call tracker.updateCardPosition()
   ↓
6. CardPositionTracker:
   - Compares old position vs new position
   - Performs fallback search if old position not found (for play animations)
   - Determines animation type (suggested or detected)
   - Creates CardAnimationTrigger
   - Sets cardAnimationTrigger.value = trigger
   ↓
7. CardAnimationLayer listener fires (_onAnimationTriggered)
   ↓
8. CardAnimationLayer:
   - Gets card data (full or back-only based on type)
   - Creates ActiveAnimation with controller
   - If play animation: Creates empty slot placeholder
   - Starts animation (600ms, easeOutCubic)
   ↓
9. Animation renders:
   - AnimatedBuilder rebuilds on each frame
   - Position and size interpolated
   - CardWidget rendered at animated position
   - Empty slot placeholder rendered (if applicable)
   ↓
10. Animation completes:
    - Controller.forward() completes
    - If play animation: Check for reposition animation
    - If no reposition: Remove empty slot after 100ms delay
    - If reposition: Keep empty slot until reposition completes
    - ActiveAnimation removed from map
    - Controller disposed
    - Trigger cleared
    - notifyAnimationComplete() called
    ↓
11. Widget receives completion event:
    - Listens to cardAnimationComplete ValueNotifier
    - If draw animation: Set drawn card visibility to true
    - Widget rebuilds with visible drawn card
```

### Drawn Card Visibility Flow

```
1. New drawn card appears in state
   ↓
2. Widget initializes _visibleDrawnCards[cardId] = false
   ↓
3. Widget renders card with opacity: 0.0 (hidden)
   ↓
4. Draw animation triggers and completes
   ↓
5. CardAnimationLayer calls notifyAnimationComplete()
   ↓
6. Widget receives completion event
   ↓
7. Widget sets _visibleDrawnCards[cardId] = true
   ↓
8. Widget rebuilds with opacity: 1.0 (visible)
```

### Empty Slot Lifecycle Flow

```
1. Play animation starts
   ↓
2. CardAnimationLayer creates EmptySlotData at play start position
   ↓
3. Empty slot rendered with card back color (0.2 saturation)
   ↓
4. Play animation completes
   ↓
5. CardAnimationLayer checks for reposition animation:
   - If reposition found: Keep empty slot
   - If no reposition: Schedule removal after 100ms
   ↓
6. If reposition follows:
   - Reposition animation completes
   - Empty slot removed (position matches reposition end)
   ↓
7. If no reposition:
   - After 100ms delay, empty slot removed
```

## Key Design Decisions

### 1. Automatic Detection
- Widgets don't need to manually trigger animations
- System automatically detects position changes
- Fallback to position-based detection if `turn_events` unavailable
- Fallback position search ensures animations work even with delayed tracking

### 2. Privacy by Default
- Draw and reposition animations show card back only
- Play and collect animations show full card (already visible)
- Protects card information during draws
- Drawn cards hidden until animation completes

### 3. Coordinate System
- Cards report in screen coordinates (includes app bar)
- Animation layer converts to Stack coordinates (excludes app bar)
- Ensures animations align with actual card positions

### 4. Concurrent Animations
- Multiple animations can run simultaneously
- Each animation has unique ID: `{type}_{cardId}_{counter}`
- Map-based storage allows independent lifecycle management

### 5. Lifecycle Management
- Animations auto-cleanup on completion
- Controllers disposed after animation
- Positions cleared on screen dispose
- Visibility states cleaned up when drawn card changes
- Prevents memory leaks

### 6. Empty Slot Management
- Empty slots provide visual continuity during play/reposition
- Smart removal logic handles both reposition and no-reposition cases
- Delay mechanism catches reposition animations that start slightly after play

### 7. Event-Driven Visibility
- Animation completion events replace fragile timers
- Widgets react to actual animation completion
- More reliable than time-based visibility toggling

## Integration Points

### Game Play Screen
- `CardAnimationLayer` added as topmost layer in Stack
- `CardPositionTracker` initialized in `initState()`
- Positions cleared in `dispose()`

### State Management
- Widgets subscribe to state via `ListenableBuilder`
- `turn_events` included in state slices for animation hints
- State updates trigger widget rebuilds → position updates
- Drawn card visibility managed via state map

### WebSocket Events
- Game state updates come from WebSocket
- State Manager processes events
- Widgets react to state changes
- Position tracking happens automatically

### Animation Completion
- Widgets subscribe to `cardAnimationComplete` ValueNotifier
- React to draw animation completion to show drawn cards
- Clean up listeners in `dispose()`

## Performance Considerations

### Position Tracking
- Only tracks visible cards (cards with GlobalKey and RenderBox)
- Position updates happen in post-frame callbacks (after render)
- Logging disabled by default (reduces overhead)
- Drawn cards tracked even when hidden (minimal overhead)

### Animation Rendering
- Uses `IgnorePointer` to allow clicks through overlay
- Empty widget when no animations (minimal overhead)
- Single Stack with Positioned widgets (efficient rendering)
- Empty slots rendered alongside animated cards

### Memory Management
- Animations cleaned up immediately after completion
- Controllers disposed properly
- Position map cleared on screen dispose
- Visibility states cleaned up when drawn card changes
- Empty slots removed after animations complete

## Visual Details

### Empty Slot Styling
- **Background Color**: Card back color with 0.2 saturation
- **Border Radius**: 8px
- **Border**: 2px solid, using `AppColors.borderDefault`
- **Size**: Matches card dimensions at play start position

### Drawn Card Styling
- **Initial State**: Opacity 0.0 (hidden)
- **After Animation**: Opacity 1.0 (visible)
- **Glow Effect**: Gold glow (`Color(0xFFFBC02D)` with 0.6 opacity) when visible
- **Extra Margin**: 16px left margin for drawn cards in my hand

## Future Enhancements

### Potential Improvements
1. **Animation Queuing**: Queue animations when multiple cards move simultaneously
2. **Custom Durations**: Different durations for different animation types
3. **Easing Variants**: Different curves for different animation types
4. **Scale Effects**: Add scale animations for emphasis
5. **Rotation Effects**: Add rotation for special plays
6. **Sound Effects**: Audio feedback for animations
7. **Particle Effects**: Visual effects for special plays
8. **Animation Cancellation**: Ability to cancel in-progress animations

### Known Limitations
1. **Fixed Duration**: All animations use 600ms (not configurable)
2. **Single Curve**: All animations use `easeOutCubic` (not configurable)
3. **No Queuing**: Multiple simultaneous animations may overlap
4. **No Pause/Resume**: Animations cannot be paused or resumed
5. **No Reversing**: Animations cannot be reversed
6. **Empty Slot Delay**: 100ms fixed delay for reposition detection (not configurable)

## Debugging

### Logging
- Logging disabled by default (`LOGGING_SWITCH = false`)
- Enable in `card_position_tracker.dart`, `card_animation_layer.dart`, and widget files for debugging
- Logs include: position updates, animation triggers, animation lifecycle, visibility state changes, empty slot management

### Position Inspection
- `CardPositionTracker.logAllPositions()` - Log all tracked positions
- `CardPositionTracker.getCardPosition()` - Get position for specific card
- `CardPositionTracker.getAllPositions()` - Get all positions (for testing)

### Visibility State Inspection
- Check `_visibleDrawnCards` map in widgets
- Log visibility state changes in `_onAnimationComplete()`
- Log visibility checks in `_buildCardWidget()`

### Common Issues
1. **Animations not triggering**: Check if cards have GlobalKey and RenderBox
2. **Wrong start position**: Verify old position exists in tracker, check fallback search logs
3. **Coordinate mismatch**: Check Stack offset calculation (app bar height)
4. **Missing card data**: Verify `originalDeck` contains card data
5. **Drawn card not showing**: Check if animation completion event was received, verify visibility state map
6. **Empty slot not removed**: Check if reposition animation is active, verify empty slot removal logic
7. **Drawn card animation missing**: Verify drawn card is tracked even when hidden, check fallback position search

## Summary

The Cleco animation system provides automatic, privacy-aware card animations with minimal widget integration. The system tracks card positions automatically, detects movement patterns, and renders smooth animations using Flutter's animation framework. Advanced features include empty slot placeholders for visual continuity, event-driven drawn card visibility management, and robust position tracking with fallback mechanisms. The design prioritizes simplicity, performance, and user experience while maintaining visual polish and reliability.
