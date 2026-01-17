# Collection Cards Verification - Dutch Game

## Overview

This document verifies the behavior of collection rank cards in the "Play Dutch: Clear and Collect" mode regarding:
1. Points calculation - whether collection cards are included in total hand points
2. Playability - whether collection cards can be played during the same rank window

**Last Updated**: 2025-01-XX

---

## Verification Results

### 1. Collection Cards Points in Total Hand

**Question**: Are collection rank cards' points included in the total hand points calculation?

**Answer**: ✅ **YES** - Collection rank cards **ARE** included in the total hand points calculation.

**Evidence**:

#### A. Collection Cards Are Part of the Hand

**When collecting from discard pile** (Line 1667-1678):
```dart
// Add to player's hand as ID-only (same format as regular hand cards)
final hand = player['hand'] as List<dynamic>? ?? [];
hand.add({
  'cardId': collectedCard['cardId'],
  'suit': '?',      // Face-down: hide suit
  'rank': '?',      // Face-down: hide rank
  'points': 0,      // Face-down: hide points
});

// Add to player's collection_rank_cards (full data)
collectionRankCards.add(collectedCard); // Full card data
```

**During initial peek**:
- Players are dealt 4 cards into their `hand`
- When a collection card is selected, it's added to `collection_rank_cards` (full data)
- **BUT the card REMAINS in the hand** (it's not removed)
- So collection cards exist in BOTH `hand` and `collection_rank_cards`

#### B. Points Calculation Includes All Hand Cards

**Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
**Method**: `_calculatePlayerPoints()` (Line 3469-3537)

**Implementation**:
```dart
int _calculatePlayerPoints(Map<String, dynamic> player, Map<String, dynamic> gameState) {
  final hand = player['hand'] as List<dynamic>? ?? [];
  int totalPoints = 0;
  
  // Get original deck to look up full card data
  final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
  
  for (final card in hand) {
    if (card == null) continue; // Skip blank slots
    
    // Look up full card data from originalDeck using cardId
    // This gets the real points value, even if hand card shows points: 0
    Map<String, dynamic>? fullCard;
    if (card is Map<String, dynamic>) {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        // Try to get full card data from original deck
        for (final deckCard in originalDeck) {
          if (deckCard is Map<String, dynamic> && deckCard['cardId']?.toString() == cardId) {
            fullCard = deckCard; // Gets full card with real points
            break;
          }
        }
      }
    }
    
    // Calculate points from full card data
    if (fullCard != null) {
      if (fullCard.containsKey('points')) {
        totalPoints += fullCard['points'] as int? ?? 0;
      } else {
        // Calculate based on rank
        // ... point calculation logic ...
      }
    }
  }
  
  return totalPoints;
}
```

**Key Points**:
- The function iterates through **ALL** cards in `player['hand']`
- It looks up full card data from `originalDeck` using `cardId`
- **NO filtering** to exclude collection cards
- Collection cards in the hand are included in point calculations
- Even though hand cards show `points: 0` (face-down format), the calculation uses full card data from `originalDeck`

**Game Impact**:
- Collection cards **DO** contribute to point totals
- Players cannot avoid points by collecting cards
- Final round winner calculation includes collection cards in hand points
- This means collecting high-point cards of your collection rank still adds to your score

---

### 2. Collection Cards Playability During Same Rank Window

**Question**: Can collection rank cards be played during the same rank window?

**Answer**: ❌ **NO** - Collection rank cards **CANNOT** be played during the same rank window.

**Evidence**:

#### A. Same Rank Play Handler Validation
- Location: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
- Method: `handleSameRankPlay()` (Line 2127-2404)
- Validation Code (Lines 2193-2213):
  ```dart
  // Check if card is in player's collection_rank_cards (cannot be played for same rank) - only if collection mode is enabled
  final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
  if (isClearAndCollect) {
    final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
    for (var collectionCard in collectionRankCards) {
      if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
        _logger.info('Dutch: Card $cardId is a collection rank card and cannot be played for same rank', isOn: LOGGING_SWITCH);
        
        // Show error message to user via actionError state
        _stateCallback.onActionError(
          'This card is in your collection and cannot be played for same rank.',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false; // Reject the play
      }
    }
  }
  ```

#### B. Available Same Rank Cards Filter
- Location: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
- Method: `_getAvailableSameRankCards()` (Line 3623-3743)
- Filter Code (Lines 3727-3730):
  ```dart
  if (collectionCardIds.contains(cardId)) {
    _logger.info('Dutch: DEBUG - Card $cardId is a collection card, skipping', isOn: LOGGING_SWITCH);
    continue; // Skip collection cards
  }
  ```

**Key Points**:
- Collection cards are explicitly checked and rejected in `handleSameRankPlay()`
- Collection cards are filtered out from available same rank cards
- Error message shown to user: "This card is in your collection and cannot be played for same rank."
- This validation only applies when `isClearAndCollect: true` (collection mode)

**Game Impact**:
- Players cannot use collection cards to take advantage of same rank windows
- Collection cards remain "locked" in the collection area
- This prevents players from strategically playing collection cards during same rank windows

---

## Related Documentation

### Collection Cards Overview

**What are Collection Cards?**
- In "Play Dutch: Clear and Collect" mode (`isClearAndCollect: true`), players select a collection rank during initial peek
- The card with the least points (priority order) becomes the collection rank card
- Additional cards of the same rank can be collected from the discard pile
- Collection cards are stored in `player['collection_rank_cards']` (separate from hand)

**Collection Rank Selection Priority**:
1. Least points
2. Ace (if points tie)
3. Numbered cards (2-10)
4. King
5. Queen
6. Jack
7. Jokers are excluded

**Collection Mechanics**:
- Players can collect cards from discard pile if top card matches their collection rank
- Collection is blocked during `same_rank_window` and `initial_peek` phases
- Collection cards are displayed stacked (with offset) in the UI

### Points Calculation Details

**What is Included in Hand Points?**
- **ALL cards in `player['hand']` array** (including collection cards)
- Points calculated by looking up full card data from `originalDeck` using `cardId`
- Points calculated based on card rank:
  - Numbered cards (2-10): Points equal to card number
  - Ace: 1 point
  - Queen/Jack: 10 points
  - Black King: 10 points
  - Red King (Hearts): 0 points
  - Joker: 0 points

**Important**: Even though collection cards in hand show `points: 0` (face-down format), the calculation looks up the real points from `originalDeck`, so collection cards contribute their full point value.

**What is NOT Included?**
- Cards in discard pile
- Cards in draw pile
- Known cards (peeked cards) - only if they're not in hand
- Blank slots (null entries in hand array)

### Same Rank Window Details

**What is the Same Rank Window?**
- A 5-10 second window after a card is played
- All players can play cards matching the rank of the last played card
- Window automatically closes and moves to next player
- Multiple players can play during this window

**What Cards Can Be Played?**
- Any card in hand matching the discard pile top card's rank
- Cards must be in `player['hand']` (not collection cards)
- Cards must be known (in `known_cards` for computer players)
- Cards must NOT be in `collection_rank_cards`

---

## Summary

### ✅ Verified Behaviors

1. **Collection Cards Storage**: Collection rank cards are stored in **BOTH** locations:
   - `player['hand']` - as ID-only cards (face-down format with `points: 0`)
   - `player['collection_rank_cards']` - as full card data (face-up format with real points)
   - **Initial collection card**: Remains in hand after being added to `collection_rank_cards` during initial peek
   - **Collected cards**: Added to both hand and `collection_rank_cards` when collected from discard pile

2. **Collection Cards Points**: Collection rank cards **ARE** included in total hand points calculation
   - Points calculation iterates through ALL cards in `player['hand']`
   - Looks up full card data from `originalDeck` using `cardId`
   - No filtering to exclude collection cards
   - Collection cards contribute their full point value to the total

3. **Collection Cards Playability**: Collection rank cards **CANNOT** be played during same rank window
   - Explicit validation in `handleSameRankPlay()` rejects collection cards
   - Collection cards are filtered from available same rank cards
   - Error message shown to user when attempting to play collection card

### 📋 Implementation Details

**Points Calculation**:
- Method: `_calculatePlayerPoints()` in `dutch_game_round.dart`
- Only iterates through `player['hand']`
- Does not access `collection_rank_cards`

**Same Rank Play Validation**:
- Method: `handleSameRankPlay()` in `dutch_game_round.dart`
- Checks if card ID exists in `collection_rank_cards`
- Returns `false` and shows error if collection card detected
- Only active when `isClearAndCollect: true`

**Available Cards Filter**:
- Method: `_getAvailableSameRankCards()` in `dutch_game_round.dart`
- Filters out collection card IDs from available cards
- Used by computer players for same rank play decisions

---

## Related Files

- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
  - `_calculatePlayerPoints()` - Points calculation (Line 3469)
  - `handleSameRankPlay()` - Same rank play handler (Line 2127)
  - `_getAvailableSameRankCards()` - Available cards filter (Line 3623)

- `Documentation/Dutch_game/PLAYER_ACTIONS_FLOW.md`
  - Complete action flow documentation
  - Collection mode details

- `Documentation/Dutch_game/STATE_UPDATE_POINTS_ANALYSIS.md`
  - State management documentation
  - SSOT (Single Source of Truth) details
