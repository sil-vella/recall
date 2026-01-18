# Card Sizing System Documentation - Dutch Game

## Overview

This document describes how card sizes are determined for different widgets in the Dutch game. The system uses a combination of fixed unified dimensions and responsive sizing based on container width.

---

## Card Dimensions Architecture

### Core Component: `CardDimensions` Class

**Location**: `flutter_base_05/lib/modules/cleco_game/utils/card_dimensions.dart`

**Purpose**: Single Source of Truth (SSOT) for all card dimensions, maintaining consistent aspect ratio across all card displays.

**Key Constants**:
- `UNIFIED_CARD_SIZE = CardSize.medium` (65px width)
- `MAX_CARD_WIDTH = 65.0` (maximum width for all cards)
- `CARD_ASPECT_RATIO = 5.0 / 7.0` (standard poker card ratio)
- `STACK_OFFSET_PERCENTAGE = 0.15` (15% of card height for stacked cards)

**Base Widths** (all capped at MAX_CARD_WIDTH):
- `small`: 50px
- `medium`: 65px (unified default, matches MAX_CARD_WIDTH)
- `large`: 65px (capped at max)
- `extraLarge`: 65px (capped at max)

**Methods**:
- `clampCardWidth(double)` → Clamps any card width to MAX_CARD_WIDTH (65px)
- `getUnifiedDimensions()` → Returns `Size(65, 91)` (medium size with 5:7 ratio)
- `getDimensions(CardSize)` → Returns dimensions for specific size (automatically clamped)
- `getStackOffset()` → Returns offset for stacked collection cards
- `calculateBorderRadius(Size)` → Calculates border radius as 5% of card width (clamped 2.0-12.0)
- `getBorderRadius(CardSize)` → Returns border radius for a given card size
- `getUnifiedBorderRadius()` → Returns border radius for unified card size

---

## Card Sizing Strategies

### 1. Fixed Unified Dimensions (Draw Pile, Discard Pile)

**Used By**:
- `DrawPileWidget` - Draw pile display
- `DiscardPileWidget` - Discard pile display

**Implementation**:
```dart
final cardDimensions = CardDimensions.getUnifiedDimensions();
// Returns: Size(65.0, 91.0) - fixed size (capped at MAX_CARD_WIDTH)
```

**Characteristics**:
- ✅ Fixed size: 65px width × 91px height (5:7 aspect ratio)
- ✅ Consistent across all cards in the widget
- ✅ Predictable layout (no responsive calculations)
- ✅ Respects MAX_CARD_WIDTH constraint

**Example** (`draw_pile_widget.dart`):
```dart
Widget _buildCardWidget(...) {
  // Size determined at widget level using CardDimensions
  final cardDimensions = CardDimensions.getUnifiedDimensions();
  
  Widget cardWidget = CardWidget(
    card: updatedCardModel,
    dimensions: cardDimensions, // Fixed: 65x91
    config: CardDisplayConfig.forDrawPile(),
    // ...
  );
}
```

---

### 2. Responsive Container-Based Sizing (Player's Hand & Opponents Panel)

**Used By**:
- `MyHandWidget` - Player's own hand
- `OpponentsPanelWidget` - Opponent cards display

**Implementation**:
```dart
// Use LayoutBuilder to get available width
return LayoutBuilder(
  builder: (context, constraints) {
    final containerWidth = constraints.maxWidth.isFinite 
        ? constraints.maxWidth 
        : MediaQuery.of(context).size.width * 0.5; // Fallback
    
    // Calculate card dimensions: 15% of container width, clamped to MAX_CARD_WIDTH
    final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.15); // 15% of container width, clamped to 65px max
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
- ✅ Percentage-based: 15% of container width per card
- ✅ **Maximum constraint**: All cards capped at 50px width (MAX_CARD_WIDTH)
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
      final cardWidth = containerWidth * 0.15; // 15% of container
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

| Widget | Sizing Strategy | Width | Height | Aspect Ratio | Responsive? | Max Width |
|--------|----------------|-------|--------|--------------|-------------|-----------|
| **Player's Hand** | Responsive | 15% of container (max 65px) | Calculated (5:7) | 5:7 | ✅ Yes | 65px |
| **Draw Pile** | Fixed Unified | 65px | 91px | 5:7 | ❌ No | 65px |
| **Discard Pile** | Fixed Unified | 65px | 91px | 5:7 | ❌ No | 65px |
| **Opponents Panel** | Responsive | 15% of container (max 65px) | Calculated (5:7) | 5:7 | ✅ Yes | 65px |

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

## Border Radius Calculation

**Used For**: All card displays (my hand, opponents, draw pile, discard pile)

**Purpose**: Ensures cards have proportional corner rounding regardless of size, preventing overly rounded corners on small cards.

**Calculation**:
```dart
final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
// Calculates 5% of card width, clamped between 2.0 and 12.0
```

**Formula**:
- Base calculation: `cardWidth × 0.05` (5% of card width)
- Minimum: 2.0px (for very small cards)
- Maximum: 12.0px (for very large cards)

**Examples**:
- Small responsive cards (~30px width): borderRadius = 1.5px → clamped to **2.0px**
- Medium responsive cards (~45px width): borderRadius = 2.25px → clamped to **2.25px**
- My Hand/Opponents (responsive, ~60px width): borderRadius = 3.0px
- My Hand/Opponents (at max 65px width): borderRadius = **3.25px**
- Draw/Discard Pile (fixed 65px width): borderRadius = **3.25px**
- Large cards (240px width): borderRadius = 12px → clamped to **12.0px**

**Implementation**:
- All `CardWidget` instances automatically use dynamic borderRadius when using default `CardDisplayConfig` (borderRadius = 8.0)
- If a custom borderRadius is explicitly set in config, it will be used instead
- The calculation is performed in `CardWidget._buildCardFront()` and `CardWidget._buildCardBack()`

**Visual Effect**:
- Small cards (opponents) have subtle, proportional rounding
- Medium cards (my hand, piles) have moderate rounding
- Large cards have more pronounced but still proportional rounding
- All cards maintain consistent visual appearance across different sizes

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
final cardWidth = containerWidth * 0.15; // 15% of container width
```

**Examples** (all clamped to 65px max):
- Container width: 200px → Card width: 30px (15% = 30px, under max)
- Container width: 300px → Card width: 45px (15% = 45px, under max)
- Container width: 400px → Card width: 60px (15% = 60px, under max)
- Container width: 433px → Card width: 65px (15% = 65px, at max)
- Container width: 500px → Card width: 65px (15% = 75px, clamped to 65px max)

### Card Height Calculation

```dart
final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
// CARD_ASPECT_RATIO = 5.0 / 7.0 = 0.714
```

**Examples**:
- Card width: 30px → Card height: 42px (30 / 0.714)
- Card width: 45px → Card height: 63px (45 / 0.714)
- Card width: 60px → Card height: 84px (60 / 0.714)
- Card width: 65px (max) → Card height: 91px (65 / 0.714)

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
- **Purpose**: SSOT for card dimensions, aspect ratio, and border radius calculations

### Player's Hand Widget
- **File**: `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`
- **Method**: `_buildMyHandCardsGrid()` (line ~2323)
- **Sizing**: Responsive (15% of container width, clamped to 65px max)

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
- ✅ Single card displays (draw pile, discard pile)
- ✅ When consistent size is more important than space efficiency
- ✅ When only one card is shown at a time

### When to Use Responsive Dimensions
- ✅ Multiple cards in limited horizontal space
- ✅ Player's hand and opponent displays
- ✅ When cards need to fit regardless of screen size
- ✅ When cards should wrap to new lines instead of scrolling

### Always Maintain Aspect Ratio
- ✅ Always use `CARD_ASPECT_RATIO` when calculating height
- ✅ Never hardcode height values
- ✅ Use `CardDimensions` utility methods

### Always Use Dynamic Border Radius
- ✅ Use `CardDimensions.calculateBorderRadius(dimensions)` for proportional corner rounding
- ✅ Never hardcode borderRadius values
- ✅ Let `CardWidget` automatically apply dynamic borderRadius when using default config

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
- Better visibility on smaller cards (15% of container width)
- Cleaner appearance without corner clutter
- Easier to read rank and suit at a glance
- More space-efficient for opponent displays

---

## Future Considerations

### Potential Improvements
1. **Card Count Scaling**: Could adjust card size based on number of cards in hand
2. **Screen Size Detection**: Could use different strategies for tablet vs phone
3. **User Preferences**: Could allow users to adjust card sizes
4. **Dynamic Percentage**: Could adjust percentage based on available space

### Current Limitations
- Both player's hand and opponents use fixed 15% percentage (may be too small on large screens)
- No dynamic adjustment based on number of cards
- Cards wrap to new lines but don't adjust size based on wrap count

---

## Maximum Card Width Constraint

**All cards are capped at 65px width** (`MAX_CARD_WIDTH = 65.0`).

This ensures:
- ✅ Consistent maximum size across all card displays
- ✅ Better space efficiency on all screen sizes
- ✅ Prevents cards from becoming too large on wide screens
- ✅ Applied automatically via `CardDimensions.clampCardWidth()`

**Implementation**:
- Fixed unified dimensions: Set to 65px (was 70px)
- Responsive calculations: Automatically clamped to 65px max
- All size options (small, medium, large, extraLarge): Capped at 65px (except small which is 50px)

## Summary

The card sizing system uses two strategies, both respecting the 65px maximum width:

1. **Fixed Unified Dimensions** (65px × 91px):
   - Draw pile, discard pile
   - Consistent size regardless of screen size
   - Capped at MAX_CARD_WIDTH (65px)
   - Used for single card displays

2. **Responsive Container-Based** (15% of container width, max 65px):
   - Player's hand and opponents panel
   - Scales with available space (15% of container width)
   - Automatically clamped to 65px maximum
   - Maintains aspect ratio (5:7)
   - Cards wrap to new lines when needed (using Wrap widget)
   - Better for fitting multiple cards in limited space

**Key Principles**:
1. **Maximum Width**: All cards are capped at 65px width (`MAX_CARD_WIDTH = 65.0`)
2. **Aspect Ratio**: All cards maintain the 5:7 aspect ratio (standard poker card ratio) regardless of sizing strategy
3. **Border Radius**: All cards use dynamic border radius calculation (5% of card width, clamped 2.0-12.0px) for proportional corner rounding
4. **SSOT**: All card dimensions and styling calculations use `CardDimensions` utility class for consistency
5. **Automatic Clamping**: All responsive calculations automatically use `clampCardWidth()` to enforce the maximum
6. **Consistent Sizing**: Both player's hand and opponents use the same 15% responsive sizing for visual consistency

---

**Last Updated**: 2026-01-18
