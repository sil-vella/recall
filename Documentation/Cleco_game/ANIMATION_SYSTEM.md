# Cleco Game Animation System

## Overview

The Cleco game uses a sophisticated card animation system that tracks card positions across the game board and animates card movements when cards change location. The system is designed to be automatic, requiring minimal manual intervention from widgets.

## Architecture

The animation system consists of three main components:

1. **CardPositionTracker** - Singleton that tracks all card positions and detects movement
2. **CardAnimationLayer** - Full-screen overlay widget that renders animated cards
3. **Widget Integration** - Game widgets (MyHandWidget, OpponentsPanelWidget, etc.) that track their card positions

## Components

### 1. CardPositionTracker (`card_position_tracker.dart`)

**Purpose**: Centralized position tracking and animation detection

**Key Features**:
- Singleton pattern - single instance tracks all cards
- Maintains a map of card positions (`Map<String, CardPositionData>`)
- Detects position changes and determines animation types
- Triggers animations via `ValueNotifier<CardAnimationTrigger?>`

**Key Methods**:
- `updateCardPosition()` - Called by widgets to update card positions
- `_triggerCardAnimation()` - Internal method that creates animation triggers
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

### 2. CardAnimationLayer (`card_animation_layer.dart`)

**Purpose**: Renders animated cards as a full-screen overlay

**Key Features**:
- Listens to `CardPositionTracker.cardAnimationTrigger` ValueNotifier
- Manages multiple concurrent animations
- Handles animation lifecycle (start, update, cleanup)
- Converts screen coordinates to Stack-relative coordinates

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

**Coordinate System**:
- Cards report positions in **screen coordinates** (via `localToGlobal`)
- Animation layer converts to **Stack-relative coordinates** (subtracts app bar + safe area)
- Stack is positioned in Scaffold body (below app bar)

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

## Animation Types

### 1. Draw (`AnimationType.draw`)
- **Trigger**: Card appears in hand from draw pile
- **Start**: Draw pile position
- **End**: Hand position
- **Card Display**: Back only (privacy)
- **Detection**: New card in hand OR suggested from `turn_events`

### 2. Play (`AnimationType.play`)
- **Trigger**: Card played from hand to discard pile
- **Start**: Hand position
- **End**: Discard pile position
- **Card Display**: Full card data (face visible)
- **Detection**: Position change from hand to discard OR suggested from `turn_events`

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
   - Determines animation type (suggested or detected)
   - Creates CardAnimationTrigger
   - Sets cardAnimationTrigger.value = trigger
   ↓
7. CardAnimationLayer listener fires (_onAnimationTriggered)
   ↓
8. CardAnimationLayer:
   - Gets card data (full or back-only based on type)
   - Creates ActiveAnimation with controller
   - Starts animation (600ms, easeOutCubic)
   ↓
9. Animation renders:
   - AnimatedBuilder rebuilds on each frame
   - Position and size interpolated
   - CardWidget rendered at animated position
   ↓
10. Animation completes:
    - Controller.forward() completes
    - ActiveAnimation removed from map
    - Controller disposed
    - Trigger cleared
```

## Key Design Decisions

### 1. Automatic Detection
- Widgets don't need to manually trigger animations
- System automatically detects position changes
- Fallback to position-based detection if `turn_events` unavailable

### 2. Privacy by Default
- Draw and reposition animations show card back only
- Play and collect animations show full card (already visible)
- Protects card information during draws

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
- Prevents memory leaks

## Integration Points

### Game Play Screen
- `CardAnimationLayer` added as topmost layer in Stack
- `CardPositionTracker` initialized in `initState()`
- Positions cleared in `dispose()`

### State Management
- Widgets subscribe to state via `ListenableBuilder`
- `turn_events` included in state slices for animation hints
- State updates trigger widget rebuilds → position updates

### WebSocket Events
- Game state updates come from WebSocket
- State Manager processes events
- Widgets react to state changes
- Position tracking happens automatically

## Performance Considerations

### Position Tracking
- Only tracks visible cards (cards with GlobalKey and RenderBox)
- Position updates happen in post-frame callbacks (after render)
- Logging disabled by default (reduces overhead)

### Animation Rendering
- Uses `IgnorePointer` to allow clicks through overlay
- Empty widget when no animations (minimal overhead)
- Single Stack with Positioned widgets (efficient rendering)

### Memory Management
- Animations cleaned up immediately after completion
- Controllers disposed properly
- Position map cleared on screen dispose

## Future Enhancements

### Potential Improvements
1. **Animation Queuing**: Queue animations when multiple cards move simultaneously
2. **Custom Durations**: Different durations for different animation types
3. **Easing Variants**: Different curves for different animation types
4. **Scale Effects**: Add scale animations for emphasis
5. **Rotation Effects**: Add rotation for special plays
6. **Sound Effects**: Audio feedback for animations
7. **Particle Effects**: Visual effects for special plays

### Known Limitations
1. **Fixed Duration**: All animations use 600ms (not configurable)
2. **Single Curve**: All animations use `easeOutCubic` (not configurable)
3. **No Queuing**: Multiple simultaneous animations may overlap
4. **No Pause/Resume**: Animations cannot be paused or resumed
5. **No Reversing**: Animations cannot be reversed

## Debugging

### Logging
- Logging disabled by default (`LOGGING_SWITCH = false`)
- Enable in `card_position_tracker.dart` and `card_animation_layer.dart` for debugging
- Logs include: position updates, animation triggers, animation lifecycle

### Position Inspection
- `CardPositionTracker.logAllPositions()` - Log all tracked positions
- `CardPositionTracker.getCardPosition()` - Get position for specific card
- `CardPositionTracker.getAllPositions()` - Get all positions (for testing)

### Common Issues
1. **Animations not triggering**: Check if cards have GlobalKey and RenderBox
2. **Wrong start position**: Verify old position exists in tracker
3. **Coordinate mismatch**: Check Stack offset calculation (app bar height)
4. **Missing card data**: Verify `originalDeck` contains card data

## Summary

The Cleco animation system provides automatic, privacy-aware card animations with minimal widget integration. The system tracks card positions automatically, detects movement patterns, and renders smooth animations using Flutter's animation framework. The design prioritizes simplicity, performance, and user experience.
