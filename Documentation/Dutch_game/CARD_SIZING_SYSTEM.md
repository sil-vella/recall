# Card Sizing System Documentation - Dutch Game

## Overview

This document describes how card sizes are determined for different widgets in the Dutch game. The system uses a combination of fixed unified dimensions and responsive sizing based on container width.

---

## Card Dimensions Architecture

### Core Component: `CardDimensions` Class

**Location**: `flutter_base_05/lib/modules/cleco_game/utils/card_dimensions.dart`

**Purpose**: Single Source of Truth (SSOT) for all card dimensions, maintaining consistent aspect ratio across all card displays.

**Key Constants**:
- `UNIFIED_CARD_SIZE = CardSize.medium` (70px width)
- `CARD_ASPECT_RATIO = 5.0 / 7.0` (standard poker card ratio)
- `STACK_OFFSET_PERCENTAGE = 0.15` (15% of card height for stacked cards)

**Base Widths**:
- `small`: 50px
- `medium`: 70px (unified default)
- `large`: 80px
- `extraLarge`: 100px

**Methods**:
- `getUnifiedDimensions()` → Returns `Size(70, 98)` (medium size with 5:7 ratio)
- `getDimensions(CardSize)` → Returns dimensions for specific size
- `getStackOffset()` → Returns offset for stacked collection cards

---

## Card Sizing Strategies

### 1. Fixed Unified Dimensions (Player's Hand, Draw Pile, Discard Pile)

**Used By**:
- `MyHandWidget` - Player's own hand
- `DrawPileWidget` - Draw pile display
- `DiscardPileWidget` - Discard pile display

**Implementation**:
```dart
final cardDimensions = CardDimensions.getUnifiedDimensions();
// Returns: Size(70.0, 98.0) - fixed size
```

**Characteristics**:
- ✅ Fixed size: 70px width × 98px height (5:7 aspect ratio)
- ✅ Consistent across all cards in the widget
- ✅ Better for interaction (player's hand needs precise tapping)
- ✅ Predictable layout (no responsive calculations)

**Example** (`my_hand_widget.dart`):
```dart
Widget _buildCardWidget(...) {
  // Size determined at widget level using CardDimensions
  final cardDimensions = CardDimensions.getUnifiedDimensions();
  
  Widget cardWidget = CardWidget(
    card: updatedCardModel,
    dimensions: cardDimensions, // Fixed: 70x98
    config: CardDisplayConfig.forMyHand(),
    // ...
  );
}
```

---

### 2. Responsive Container-Based Sizing (Opponents Panel)

**Used By**:
- `OpponentsPanelWidget` - Opponent cards display

**Implementation**:
```dart
// Use LayoutBuilder to get available width
return LayoutBuilder(
  builder: (context, constraints) {
    final containerWidth = constraints.maxWidth.isFinite 
        ? constraints.maxWidth 
        : MediaQuery.of(context).size.width * 0.5; // Fallback
    
    // Calculate card dimensions: 6% of container width
    final cardWidth = containerWidth * 0.06; // 6% of container width
    final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO; // Maintain 5:7 ratio
    final cardDimensions = Size(cardWidth, cardHeight);
    
    // Card padding: 2% of container width
    final cardPadding = containerWidth * 0.02;
    
    // Use cardDimensions for all cards in the row
  }
);
```

**Characteristics**:
- ✅ Responsive: Scales based on container width
- ✅ Percentage-based: 6% of container width per card
- ✅ Maintains aspect ratio: Always 5:7 (width:height)
- ✅ Adaptive spacing: 2% of container width between cards
- ✅ Better for fitting multiple opponent cards in limited space

**Example** (`opponents_panel_widget.dart`):
```dart
Widget _buildCardsRow(...) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final containerWidth = constraints.maxWidth.isFinite 
          ? constraints.maxWidth 
          : MediaQuery.of(context).size.width * 0.5;
      
      // Calculate responsive dimensions
      final cardWidth = containerWidth * 0.06; // 6% of container
      final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
      final cardDimensions = Size(cardWidth, cardHeight);
      
      // Build cards with responsive dimensions
      return ListView.builder(
        itemBuilder: (context, index) {
          return CardWidget(
            card: cardModel,
            dimensions: cardDimensions, // Responsive: varies by container width
            config: CardDisplayConfig.forOpponent(), // Uses centeredOnly display mode
            // ...
          );
        },
      );
    },
  );
}
```

---

## Size Comparison

| Widget | Sizing Strategy | Width | Height | Aspect Ratio | Responsive? |
|--------|----------------|-------|--------|--------------|-------------|
| **Player's Hand** | Fixed Unified | 70px | 98px | 5:7 | ❌ No |
| **Draw Pile** | Fixed Unified | 70px | 98px | 5:7 | ❌ No |
| **Discard Pile** | Fixed Unified | 70px | 98px | 5:7 | ❌ No |
| **Opponents Panel** | Responsive | 6% of container | Calculated (5:7) | 5:7 | ✅ Yes |

---

## Why Different Strategies?

### Player's Hand: Fixed Size
- **Reason**: Better user experience for interaction
  - Larger, consistent size makes cards easier to tap
  - Predictable layout helps with card selection
  - Player needs to see their own cards clearly
  - Fixed size ensures cards don't shrink too small

### Opponents Panel: Responsive Size
- **Reason**: Space efficiency and scalability
  - Multiple opponents need to fit in limited horizontal space
  - Responsive sizing ensures all opponent cards fit regardless of screen size
  - Smaller cards are acceptable for opponents (less interaction needed)
  - Adapts to different numbers of opponents (2-4 players)

---

## Card Display Configurations

**Location**: `flutter_base_05/lib/modules/cleco_game/models/card_display_config.dart`

Different configs are used for different contexts:

1. **`CardDisplayConfig.forMyHand()`**
   - Player's own hand
   - Full card details visible
   - Interactive (tappable for selection)

2. **`CardDisplayConfig.forOpponent()`**
   - Opponent cards
   - **Display Mode**: `centeredOnly` - rank and suit centered, no corners
   - **Text Size**: 40% of card height for rank and suit
   - May show back (ID-only cards) or front (peeked/known cards)
   - Interactive only during special powers (queen_peek, jack_swap)

3. **`CardDisplayConfig.forDiscardPile()`**
   - Discard pile top card
   - Always shows front (full data)
   - Interactive (tappable to take from discard)

4. **`CardDisplayConfig.forDrawPile()`**
   - Draw pile
   - Always shows back (face-down)
   - Interactive (tappable to draw)

---

## Stack Offset for Collection Cards

**Used For**: Collection rank cards (cards selected during initial peek)

**Calculation**:
```dart
final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
// STACK_OFFSET_PERCENTAGE = 0.15 (15% of card height)
```

**Example**:
- Card height: 98px (fixed) or responsive height
- Stack offset: 98px × 0.15 = 14.7px
- Each stacked card is offset 14.7px downward from the previous card

**Visual Effect**:
- Collection rank cards appear stacked on top of each other
- Creates a "fan" effect showing multiple cards
- Only the first collection card position is used; subsequent cards stack above it

---

## Responsive Sizing Details (Opponents Panel)

### Container Width Calculation

```dart
final containerWidth = constraints.maxWidth.isFinite 
    ? constraints.maxWidth  // Use actual container width
    : MediaQuery.of(context).size.width * 0.5; // Fallback: 50% of screen width
```

**Fallback Logic**:
- If `constraints.maxWidth` is unbounded (infinite), use 50% of screen width
- Ensures cards always have a calculable size

### Card Width Calculation

```dart
final cardWidth = containerWidth * 0.06; // 6% of container width
```

**Examples**:
- Container width: 300px → Card width: 18px
- Container width: 400px → Card width: 24px
- Container width: 500px → Card width: 30px

### Card Height Calculation

```dart
final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
// CARD_ASPECT_RATIO = 5.0 / 7.0 = 0.714
```

**Examples**:
- Card width: 18px → Card height: 25.2px (18 / 0.714)
- Card width: 24px → Card height: 33.6px (24 / 0.714)
- Card width: 30px → Card height: 42px (30 / 0.714)

### Card Padding Calculation

```dart
final cardPadding = containerWidth * 0.02; // 2% of container width
```

**Examples**:
- Container width: 300px → Padding: 6px
- Container width: 400px → Padding: 8px
- Container width: 500px → Padding: 10px

---

## Aspect Ratio Maintenance

**Critical**: All card sizes maintain the 5:7 aspect ratio (standard poker card ratio).

**Formula**:
```dart
height = width / CARD_ASPECT_RATIO
// CARD_ASPECT_RATIO = 5.0 / 7.0 = 0.714285714...
```

**Why**: 
- Matches physical poker cards (2.5" × 3.5")
- Consistent visual appearance across all card displays
- Prevents card distortion

---

## Code Locations

### Card Dimensions Utility
- **File**: `flutter_base_05/lib/modules/cleco_game/utils/card_dimensions.dart`
- **Purpose**: SSOT for card dimensions and aspect ratio

### Player's Hand Widget
- **File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/my_hand_widget.dart`
- **Method**: `_buildCardWidget()` (line ~1093)
- **Sizing**: Fixed unified dimensions

### Opponents Panel Widget
- **File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/opponents_panel_widget.dart`
- **Method**: `_buildCardsRow()` (line ~391)
- **Sizing**: Responsive (15% of container width)

### Draw Pile Widget
- **File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/draw_pile_widget.dart`
- **Sizing**: Fixed unified dimensions

### Discard Pile Widget
- **File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/discard_pile_widget.dart`
- **Sizing**: Fixed unified dimensions

---

## Best Practices

### When to Use Fixed Dimensions
- ✅ Player's own hand (better interaction)
- ✅ Single card displays (draw pile, discard pile)
- ✅ When consistent size is more important than space efficiency

### When to Use Responsive Dimensions
- ✅ Multiple cards in limited horizontal space
- ✅ Opponent displays (less interaction needed)
- ✅ When cards need to fit regardless of screen size

### Always Maintain Aspect Ratio
- ✅ Always use `CARD_ASPECT_RATIO` when calculating height
- ✅ Never hardcode height values
- ✅ Use `CardDimensions` utility methods

---

## Opponent Card Display Mode

### Centered Display (centeredOnly)

Opponent cards use a special display mode that shows rank and suit centered on the card with no corner displays.

**Display Characteristics**:
- **Mode**: `CardDisplayMode.centeredOnly`
- **Rank Display**: Centered, top position
- **Suit Display**: Centered, below rank
- **Text Size**: 40% of card height (both rank and suit)
- **No Corners**: Top-left and bottom-right corners are empty
- **Layout**: Vertical stack (rank above suit)

**Implementation** (`card_widget.dart`):
```dart
Widget _buildCenteredRankAndSuit(Size dimensions) {
  final fontSize = dimensions.height * 0.4; // 40% of card height
  
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Rank
      Text(
        card.rankSymbol,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: card.color,
        ),
      ),
      // Suit
      Text(
        card.suitSymbol,
        style: TextStyle(
          fontSize: fontSize,
          color: card.color,
        ),
      ),
    ],
  );
}
```

**Visual Example**:
```
┌─────────┐
│         │
│    A    │  ← Rank (centered, 80% width)
│    ♠    │  ← Suit (centered, 80% width)
│         │
└─────────┘
```

**Why Centered Display**:
- Better visibility on smaller cards (6% of container width)
- Cleaner appearance without corner clutter
- Easier to read rank and suit at a glance
- More space-efficient for opponent displays

---

## Future Considerations

### Potential Improvements
1. **Adaptive Sizing**: Could make player's hand responsive on very small screens
2. **Card Count Scaling**: Could adjust opponent card size based on number of opponents
3. **Screen Size Detection**: Could use different strategies for tablet vs phone
4. **User Preferences**: Could allow users to adjust card sizes

### Current Limitations
- Player's hand uses fixed size (may be too large on small screens)
- Opponent cards use fixed percentage (may be too small on large screens)
- No dynamic adjustment based on number of cards

---

## Summary

The card sizing system uses two strategies:

1. **Fixed Unified Dimensions** (70px × 98px):
   - Player's hand, draw pile, discard pile
   - Better for interaction and visibility
   - Consistent size regardless of screen size

2. **Responsive Container-Based** (6% of container width):
   - Opponents panel
   - Scales with available space
   - Maintains aspect ratio (5:7)
   - Better for fitting multiple cards

**Key Principle**: All cards maintain the 5:7 aspect ratio (standard poker card ratio) regardless of sizing strategy.

---

**Last Updated**: 2025-01-XX
