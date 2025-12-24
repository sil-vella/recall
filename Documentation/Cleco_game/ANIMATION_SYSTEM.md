# Animation System Documentation - Cleco Game

## Overview

This document describes the card animation system for the Cleco game. The system automatically detects card movements and animates them smoothly across the game board, including draw, play, collect, reposition, and jack swap animations.

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Core Components](#core-components)
3. [Animation Types](#animation-types)
4. [Position Tracking](#position-tracking)
5. [Animation Detection](#animation-detection)
6. [Animation Rendering](#animation-rendering)
7. [Card Tracking in Piles](#card-tracking-in-piles)
8. [Coordinate System](#coordinate-system)
9. [State Update Handling](#state-update-handling)
10. [Integration Points](#integration-points)
11. [Related Files](#related-files)

---

## System Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│              Card Animation System Flow                       │
└─────────────────────────────────────────────────────────────┘

UnifiedGameBoardWidget rebuilds
    ↓
PostFrameCallback triggers
    ↓
_scanCardPositions() - Scan all card positions
    ↓
CardPositionScanner.scanAllCards() - Get current positions
    ↓
_detectAndTriggerAnimations() - Compare positions
    ↓
CardAnimationDetector.detectAnimations() - Detect movements
    ↓
CardAnimationDetector.animationTriggers.value = animations
    ↓
CardAnimationLayer receives trigger
    ↓
_startAnimation() - Create animation controllers
    ↓
AnimatedBuilder renders animated card
    ↓
Animation completes → Cleanup
```

### Component Interaction

```
┌─────────────────────┐
│ UnifiedGameBoard    │
│      Widget         │
└──────────┬──────────┘
           │
           ├─── CardPositionScanner (singleton)
           │    └─── Tracks all card positions
           │
           ├─── CardAnimationDetector (singleton)
           │    └─── Detects movements
           │
           └─── GlobalKey management
                └─── One key per cardId
                     
┌─────────────────────┐
│ CardAnimationLayer  │
│      Widget         │
└──────────┬──────────┘
           │
           ├─── Listens to animationTriggers
           │
           ├─── AnimationController per card
           │
           └─── Renders animated cards as overlay
```

---

## Core Components

### 1. CardPositionScanner

**Location**: `flutter_base_05/lib/modules/cleco_game/utils/card_position_scanner.dart`

**Purpose**: Singleton utility that scans and tracks all card positions on the screen.

**Key Features**:
- Scans all cards after each widget rebuild
- Maintains previous positions for comparison
- Handles state update edge cases (missing/duplicate cardIds)
- Preserves positions for cards that temporarily disappear

**Key Methods**:
```dart
// Scan all cards and return current positions
Map<String, CardPosition> scanAllCards(Map<String, CardKeyData> cardKeys)

// Get previous positions for comparison
Map<String, CardPosition> getPreviousPositions()

// Clear all tracked positions
void clearPositions()
```

**Position Preservation Logic**:
- If a cardId is missing from current scan but exists in previous: **Preserve old position** (state still updating)
- If a cardId appears in two different positions: **Use new position** (state updated, old widget still exists)

**CardPosition Model**:
```dart
class CardPosition {
  final String cardId;
  final Offset position;        // Top-left corner in global coordinates
  final Size size;
  final String location;        // 'my_hand', 'opponent_hand_{playerId}', 'draw_pile', 'discard_pile'
  final String? playerId;       // For player hands
  final bool isFaceUp;          // true for face up, false for face down
  final int? index;             // Position in hand (for ordering)
}
```

---

### 2. CardAnimationDetector

**Location**: `flutter_base_05/lib/modules/cleco_game/utils/card_animation_detector.dart`

**Purpose**: Singleton utility that detects card movements and determines animation types.

**Key Features**:
- Compares current vs previous positions
- Determines animation type based on location changes
- Handles special cases (draw pile, discard pile, empty states)
- Triggers animations via ValueNotifier

**Key Methods**:
```dart
// Detect animations by comparing positions
List<CardAnimation> detectAnimations(
  Map<String, CardPosition> currentPositions,
  Map<String, CardPosition> previousPositions,
)

// Determine animation type from position change
AnimationType _determineAnimationType(CardPosition oldPos, CardPosition newPos)

// Find draw pile position for draw animations
CardPosition? _findDrawPilePosition(Map<String, CardPosition> positions)

// Find discard pile position for play animations
CardPosition? _findDiscardPilePosition(Map<String, CardPosition> positions)
```

**Animation Detection Logic**:

1. **Location Changed** (highest priority):
   - Hand → Discard Pile = `play`
   - Draw Pile → Hand = `draw`
   - Discard Pile → Hand = `collect`
   - Opponent Hand → Opponent Hand = `jackSwap`

2. **Same Location, Different Position**:
   - Same location but position changed = `reposition`
   - Skipped for static locations (draw_pile, discard_pile)

3. **Card Appeared** (exists in new but not old):
   - Appeared in hand = `draw` (from draw pile)

4. **Card Disappeared** (exists in old but not new):
   - Disappeared from hand = `play` (to discard pile)

**ValueNotifier Communication**:
```dart
final ValueNotifier<List<CardAnimation>?> animationTriggers = ValueNotifier(null);

// Trigger animations
animationTriggers.value = animations;

// Clear after one frame (prevents duplicate triggers)
Future.microtask(() {
  animationTriggers.value = null;
});
```

---

### 3. CardAnimationLayer

**Location**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/card_animation_layer.dart`

**Purpose**: Full-screen overlay widget that renders animated cards.

**Key Features**:
- Listens to animation triggers from CardAnimationDetector
- Creates AnimationControllers for each animation
- Renders animated cards as overlay (on top of game board)
- Handles coordinate conversion (global → Stack-relative)
- Cleans up animations after completion

**Key Methods**:
```dart
// Handle animation triggers
void _onAnimationTriggersChanged()

// Start a new animation
void _startAnimation(CardAnimation animation)

// Convert global coordinates to Stack-relative coordinates
Offset _convertToStackCoordinates(Offset globalPosition)

// Handle animation completion
void _completeAnimation(String cardId)

// Cleanup completed animation
void _cleanupAnimation(String cardId)

// Get card data for animation rendering
CardModel _getCardData(String cardId, bool showFaceUp)
```

**Animation Controller Setup**:
```dart
// Position animation (always created)
final positionTween = Tween<Offset>(
  begin: _convertToStackCoordinates(animation.startPosition.position),
  end: _convertToStackCoordinates(animation.endPosition.position),
);
final positionAnimation = positionTween.animate(
  CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
);

// Size animation (only if sizes differ)
Animation<Size>? sizeAnimation;
if (animation.startPosition.size != animation.endPosition.size) {
  final sizeTween = Tween<Size>(
    begin: animation.startPosition.size,
    end: animation.endPosition.size,
  );
  sizeAnimation = sizeTween.animate(
    CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
  );
}
```

**Animation Duration**: 600ms (constant)

**Coordinate Conversion**:
- Cards are positioned using global screen coordinates
- Must convert to Stack-relative coordinates for rendering
- Uses `GlobalKey` on parent Stack to get exact position
- Formula: `stackRelative = globalPosition - stackGlobalPosition`

---

### 4. UnifiedGameBoardWidget

**Location**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/unified_game_board_widget.dart`

**Purpose**: Main widget that combines all game board components and manages animation tracking.

**Key Features**:
- Manages GlobalKeys for all cards
- Scans positions after each rebuild
- Triggers animation detection
- Renders all game board components (opponents, draw pile, discard pile, my hand)

**Key Methods**:
```dart
// Get or create GlobalKey for a card
GlobalKey _getOrCreateCardKey(String cardId, String keyType)

// Scan all card positions after build
void _scanCardPositions()

// Detect and trigger animations
void _detectAndTriggerAnimations()
```

**Position Scanning Flow**:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _scanCardPositions();  // Scan after build completes
});

void _scanCardPositions() {
  // 1. Collect all card keys with metadata
  final Map<String, CardKeyData> cardKeys = {};
  
  // 2. Add draw pile cards
  // 3. Add discard pile cards
  // 4. Add opponent cards
  // 5. Add my hand cards
  
  // 6. Scan positions
  final currentPositions = _positionScanner.scanAllCards(cardKeys);
  
  // 7. Detect animations
  _detectAndTriggerAnimations();
}
```

---

## Animation Types

### 1. Draw Animation

**Trigger**: Card moves from draw pile to hand

**Detection**:
- Location change: `draw_pile` → `my_hand` or `opponent_hand_{playerId}`
- OR: Card appeared in hand (exists in new but not old)

**Visual**:
- Card shows back (face down)
- Animates from draw pile position to hand position
- Size may change (draw pile cards are larger)

**Example**:
```dart
CardAnimation(
  cardId: 'card_123',
  startPosition: CardPosition(location: 'draw_pile', ...),
  endPosition: CardPosition(location: 'my_hand', ...),
  type: AnimationType.draw,
  showFaceUp: false,  // Show card back
)
```

---

### 2. Play Animation

**Trigger**: Card moves from hand to discard pile

**Detection**:
- Location change: `my_hand` or `opponent_hand_{playerId}` → `discard_pile`
- OR: Card disappeared from hand (exists in old but not new)

**Visual**:
- Card shows face (face up)
- Animates from hand position to discard pile position
- Size may change (hand cards are smaller)

**Example**:
```dart
CardAnimation(
  cardId: 'card_123',
  startPosition: CardPosition(location: 'my_hand', ...),
  endPosition: CardPosition(location: 'discard_pile', ...),
  type: AnimationType.play,
  showFaceUp: true,  // Show card face
)
```

---

### 3. Collect Animation

**Trigger**: Card moves from discard pile to hand

**Detection**:
- Location change: `discard_pile` → `my_hand` or `opponent_hand_{playerId}`

**Visual**:
- Card shows face (face up)
- Animates from discard pile position to hand position
- Size may change

**Example**:
```dart
CardAnimation(
  cardId: 'card_123',
  startPosition: CardPosition(location: 'discard_pile', ...),
  endPosition: CardPosition(location: 'my_hand', ...),
  type: AnimationType.collect,
  showFaceUp: true,  // Show card face
)
```

---

### 4. Reposition Animation

**Trigger**: Card moves within the same location (e.g., reordering in hand)

**Detection**:
- Same location but different position
- Position difference > threshold (10.0 pixels)

**Visual**:
- Card animates to new position within same location
- Size typically unchanged

**Example**:
```dart
CardAnimation(
  cardId: 'card_123',
  startPosition: CardPosition(location: 'my_hand', position: Offset(100, 500), ...),
  endPosition: CardPosition(location: 'my_hand', position: Offset(200, 500), ...),
  type: AnimationType.reposition,
  showFaceUp: true,  // Keep current face state
)
```

**Note**: Reposition animations are skipped for static locations (draw_pile, discard_pile)

---

### 5. Jack Swap Animation

**Trigger**: Card moves between opponent hands (jack power)

**Detection**:
- Location change: `opponent_hand_{playerId1}` → `opponent_hand_{playerId2}`

**Visual**:
- Card animates from one opponent hand to another
- Size may change (different opponent hand sizes)

**Example**:
```dart
CardAnimation(
  cardId: 'card_123',
  startPosition: CardPosition(location: 'opponent_hand_cpu_1', ...),
  endPosition: CardPosition(location: 'opponent_hand_cpu_2', ...),
  type: AnimationType.jackSwap,
  showFaceUp: false,  // Opponent cards are face down
)
```

---

## Position Tracking

### Card Key Management

Each card has a unique `GlobalKey` that is reused across rebuilds:

```dart
// Key format: '{keyType}_{cardId}'
// Examples:
// - 'draw_pile_card_123'
// - 'discard_pile_card_456'
// - 'opponent_hand_cpu_1_card_789'
// - 'my_hand_card_012'

GlobalKey _getOrCreateCardKey(String cardId, String keyType) {
  final key = '${keyType}_$cardId';
  if (!_cardKeys.containsKey(key)) {
    _cardKeys[key] = GlobalKey(debugLabel: key);
  }
  return _cardKeys[key]!;
}
```

### Position Scanning Process

1. **Collect Card Keys**: Build map of all cardIds → CardKeyData
   - Draw pile cards (all cards in draw pile)
   - Discard pile cards (all cards in discard pile)
   - Opponent cards (all cards in all opponent hands)
   - My hand cards (all cards in my hand)

2. **Scan Positions**: Use `CardPositionScanner.scanAllCards()`
   - For each card key, get RenderBox
   - Extract global position and size
   - Create CardPosition object

3. **Compare Positions**: Use `CardAnimationDetector.detectAnimations()`
   - Compare current vs previous positions
   - Detect movements and determine animation types

4. **Preserve Previous**: Save current positions as previous for next scan

### CardKeyData Structure

```dart
class CardKeyData {
  final GlobalKey key;
  final String location;      // 'my_hand', 'opponent_hand_{playerId}', 'draw_pile', 'discard_pile'
  final bool isFaceUp;        // true for face up, false for face down
}
```

---

## Animation Detection

### Detection Algorithm

```dart
for (final entry in currentPositions.entries) {
  final cardId = entry.key;
  final newPosition = entry.value;
  final oldPosition = previousPositions[cardId];
  
  if (oldPosition != null) {
    // Card exists in both old and new positions
    if (oldPosition.location != newPosition.location) {
      // Location changed → Determine animation type
      final animationType = _determineAnimationType(oldPosition, newPosition);
      // Create animation
    } else if (oldPosition.isDifferentFrom(newPosition)) {
      // Same location but position changed → Reposition
      // (Skipped for static locations)
    }
  } else {
    // Card appeared (exists in new but not old)
    if (newPosition.location == 'my_hand' || newPosition.location.startsWith('opponent_hand_')) {
      // Appeared in hand → Draw animation
      // Use draw pile position as start
    }
  }
}

// Check for disappeared cards
for (final entry in previousPositions.entries) {
  if (!currentPositions.containsKey(entry.key)) {
    // Card disappeared → Play animation (if was in hand)
    // Use discard pile position as end
  }
}
```

### Animation Type Priority

1. **Location Change** (highest priority):
   - Hand → Discard = `play`
   - Draw Pile → Hand = `draw`
   - Discard → Hand = `collect`
   - Opponent → Opponent = `jackSwap`

2. **Position Change** (same location):
   - Same location, different position = `reposition`

3. **Card Appeared**:
   - Appeared in hand = `draw`

4. **Card Disappeared**:
   - Disappeared from hand = `play`

---

## Animation Rendering

### Overlay Layer

The `CardAnimationLayer` is rendered as a full-screen overlay on top of the game board:

```dart
Stack(
  children: [
    // Main game content
    SingleChildScrollView(...),
    
    // Animation layer (on top)
    CardAnimationLayer(stackKey: _mainStackKey),
    
    // Other overlays (instructions, messages)
    InstructionsWidget(),
    MessagesWidget(),
  ],
)
```

### Rendering Process

1. **Receive Trigger**: Listen to `animationTriggers` ValueNotifier
2. **Start Animation**: Create AnimationController and animations
3. **Render Card**: Use AnimatedBuilder to render animated card
4. **Coordinate Conversion**: Convert global → Stack-relative coordinates
5. **Animation Complete**: Cleanup after animation finishes

### Positioned Widget

Animated cards are rendered using `Positioned` widgets:

```dart
Positioned(
  left: currentPosition.dx,
  top: currentPosition.dy,
  width: currentSize.width,
  height: currentSize.height,
  child: CardWidget(
    card: cardData,
    dimensions: currentSize,
    config: CardDisplayConfig.forMyHand(),
    showBack: !animation.showFaceUp,
  ),
)
```

### IgnorePointer

The animation layer uses `IgnorePointer` to allow interaction with widgets below:

```dart
IgnorePointer(
  ignoring: true,  // Ignore pointer events (pass through)
  child: Stack(...),
)
```

---

## Card Tracking in Piles

### Draw Pile Tracking

**All cards in draw pile are tracked individually**:

```dart
// Get full draw pile list from game state
final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];

// Render all cards (stacked, all at same position)
Stack(
  children: drawPile.asMap().entries.map((entry) {
    final cardId = cardData['cardId']?.toString();
    final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
    
    // Only top card visible, but all tracked
    return Positioned.fill(
      child: Opacity(
        opacity: isTopCard ? 1.0 : 0.0,
        child: CardWidget(key: cardKey, ...),
      ),
    );
  }).toList(),
)
```

**Benefits**:
- All draw pile cards have the same position (stacked)
- Each card tracked by its actual cardId
- Draw animations can use actual card positions

### Discard Pile Tracking

**All cards in discard pile are tracked individually**:

```dart
// Get full discard pile list from game state
final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];

// Render all cards (stacked, all at same position)
Stack(
  children: discardPile.asMap().entries.map((entry) {
    final cardId = cardData['cardId']?.toString();
    final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
    
    // Only top card visible, but all tracked
    return Positioned.fill(
      child: Opacity(
        opacity: isTopCard ? 1.0 : 0.0,
        child: CardWidget(key: cardKey, ...),
      ),
    );
  }).toList(),
)
```

**Benefits**:
- All discard pile cards have the same position (stacked)
- Each card tracked by its actual cardId
- Play animations can use actual card positions

### Empty Pile Handling

When a pile is empty, a placeholder card is rendered:

```dart
// Empty draw pile
if (drawPile.isEmpty) {
  final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
  return CardWidget(
    key: emptyKey,
    card: CardModel(cardId: 'draw_pile_empty', ...),
    ...
  );
}

// Empty discard pile
if (discardPile.isEmpty) {
  final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
  return CardWidget(
    key: emptyKey,
    card: CardModel(cardId: 'discard_pile_empty', ...),
    ...
  );
}
```

---

## Coordinate System

### Global Coordinates

Cards are positioned using **global screen coordinates**:

```dart
final RenderBox? renderBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
final globalPosition = renderBox.localToGlobal(Offset.zero);
final size = renderBox.size;
```

### Stack-Relative Coordinates

For animation rendering, coordinates must be converted to **Stack-relative coordinates**:

```dart
Offset _convertToStackCoordinates(Offset globalPosition) {
  final RenderBox? stackRenderBox = widget.stackKey.currentContext?.findRenderObject() as RenderBox?;
  final stackGlobalPosition = stackRenderBox.localToGlobal(Offset.zero);
  
  return Offset(
    globalPosition.dx - stackGlobalPosition.dx,
    globalPosition.dy - stackGlobalPosition.dy,
  );
}
```

### Stack Key Setup

The parent Stack in `GamePlayScreen` has a GlobalKey:

```dart
class GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final GlobalKey _mainStackKey = GlobalKey(debugLabel: 'GamePlayScreenStack');
  
  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      key: _mainStackKey,  // Key for coordinate conversion
      children: [
        // Main content
        SingleChildScrollView(...),
        
        // Animation layer
        CardAnimationLayer(stackKey: _mainStackKey),
      ],
    );
  }
}
```

---

## State Update Handling

### Missing CardId (State Still Updating)

**Scenario**: CardId exists in previous scan but missing in current scan

**Handling**: Preserve old position (don't create animation)

```dart
// In CardPositionScanner
if (!currentPositions.containsKey(cardId) && previousPositions.containsKey(cardId)) {
  // Preserve old position
  _logger.info('Preserved position for $cardId (missing from scan, state still updating)');
  // Old position kept in scanner
}
```

**Reason**: State is still updating, card will appear in next scan

---

### Duplicate CardId (State Updated, Old Widget Still Exists)

**Scenario**: CardId appears in two different positions (old widget still exists, new widget created)

**Handling**: Use new position (create animation from old to new)

```dart
// In CardAnimationDetector
if (oldPosition != null && newPosition != null) {
  if (oldPosition.location != newPosition.location) {
    // Location changed → Create animation
    final animation = CardAnimation(
      startPosition: oldPosition,  // Old position
      endPosition: newPosition,    // New position
      ...
    );
  }
}
```

**Reason**: State has updated, new position is correct, old widget will be removed

---

### Special Pile CardIds

**Special cardIds are skipped** during animation detection:

```dart
// Skip special pile cardIds
if (cardId.startsWith('draw_pile_') || cardId == 'discard_pile_empty') {
  continue;  // Don't create animations for these
}
```

**Special cardIds**:
- `draw_pile_full` - Draw pile has cards (placeholder)
- `draw_pile_empty` - Draw pile is empty (placeholder)
- `discard_pile_empty` - Discard pile is empty (placeholder)

**Reason**: These are placeholder cards, not actual game cards

---

## Integration Points

### UnifiedGameBoardWidget

**Location**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/unified_game_board_widget.dart`

**Responsibilities**:
- Manage GlobalKeys for all cards
- Scan positions after each rebuild
- Trigger animation detection
- Render all game board components

**Key Integration**:
```dart
@override
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: StateManager(),
    builder: (context, child) {
      // Schedule position scanning after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanCardPositions();
      });
      
      return Column(
        children: [
          _buildOpponentsPanel(),
          _buildGameBoard(),  // Draw pile, discard pile, match pot
          _buildMyHand(),
        ],
      );
    },
  );
}
```

---

### GamePlayScreen

**Location**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/game_play_screen.dart`

**Responsibilities**:
- Provide Stack with GlobalKey for coordinate conversion
- Render CardAnimationLayer as overlay

**Key Integration**:
```dart
@override
Widget buildContent(BuildContext context) {
  return Stack(
    key: _mainStackKey,  // Key for coordinate conversion
    children: [
      // Main game content
      SingleChildScrollView(...),
      
      // Animation layer (full-screen overlay)
      CardAnimationLayer(stackKey: _mainStackKey),
      
      // Other overlays
      InstructionsWidget(),
      MessagesWidget(),
    ],
  );
}
```

---

## Related Files

### Core Animation Files

1. **CardPositionScanner**
   - `flutter_base_05/lib/modules/cleco_game/utils/card_position_scanner.dart`
   - Position tracking and scanning

2. **CardAnimationDetector**
   - `flutter_base_05/lib/modules/cleco_game/utils/card_animation_detector.dart`
   - Animation detection and type determination

3. **CardAnimationLayer**
   - `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/card_animation_layer.dart`
   - Animation rendering and overlay

### Integration Files

4. **UnifiedGameBoardWidget**
   - `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/unified_game_board_widget.dart`
   - Main widget that manages animation tracking

5. **GamePlayScreen**
   - `flutter_base_05/lib/modules/cleco_game/screens/game_play/game_play_screen.dart`
   - Screen that renders animation layer

### Supporting Files

6. **CardModel**
   - `flutter_base_05/lib/modules/cleco_game/models/card_model.dart`
   - Card data model

7. **CardWidget**
   - `flutter_base_05/lib/modules/cleco_game/widgets/card_widget.dart`
   - Card rendering widget

8. **CardDisplayConfig**
   - `flutter_base_05/lib/modules/cleco_game/models/card_display_config.dart`
   - Card display configuration

---

## Future Improvements

### Potential Enhancements

1. **Animation Customization**:
   - Different animation curves per type
   - Configurable animation duration
   - Easing functions per animation type

2. **Performance Optimization**:
   - Batch position scans
   - Debounce animation triggers
   - Optimize coordinate conversion

3. **Visual Enhancements**:
   - Shadow effects during animation
   - Rotation animations
   - Scale animations for emphasis

4. **Debugging Tools**:
   - Animation visualization overlay
   - Position debugging tools
   - Animation timeline viewer

5. **Accessibility**:
   - Reduced motion support
   - Animation speed controls
   - Skip animations option

---

## Summary

The animation system provides smooth, automatic card animations for all card movements in the Cleco game. It uses a three-component architecture:

1. **CardPositionScanner**: Tracks all card positions
2. **CardAnimationDetector**: Detects movements and determines animation types
3. **CardAnimationLayer**: Renders animated cards as overlay

The system handles edge cases like state updates, missing cards, and duplicate positions, ensuring animations work correctly even during rapid state changes.

All cards in draw and discard piles are tracked individually by their actual cardIds, enabling accurate animation detection and smooth visual transitions.

