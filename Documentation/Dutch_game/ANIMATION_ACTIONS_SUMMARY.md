# Animation System Actions Summary

**Analysis Date**: 2026-01-24  
**Log File**: `python_base_04/tools/logger/server.log`  
**Total Actions Detected**: 16 unique actions  
**Time Range**: 14:44:41 - 14:47:12 (2 minutes 31 seconds)

## Summary by Player

### 1. `practice_session_practice_user_1769262261227` (Human Player)
**Total Actions**: 1

| Timestamp | Action Type | Action Data |
|-----------|-------------|-------------|
| 14:44:41.819 | `initial_peek` | `{cardIndex1: 0, cardIndex2: 1}` |

**Details**:
- Initial game setup peek at 2 cards (indices 0 and 1)

---

### 2. `cpu_1769262268530000_2` (CPU Player 2)
**Total Actions**: 4

| Timestamp | Action Type | Action Data |
|-----------|-------------|-------------|
| 14:44:54.276 | `drawn_card` | `{cardId: card_practice_room_1769262261266_jack_diamonds_1_1301247151}` |
| 14:45:00.967 | `play_card` | `{cardIndex: 0}` |
| 14:45:11.257 | `same_rank` | `{cardIndex: 1}` |
| 14:46:14.205 | `same_rank` | `{cardIndex: 0}` |

**Details**:
- Drew Jack of Diamonds from draw pile
- Played card at index 0
- Played same rank card at index 1 (out-of-turn)
- Played same rank card at index 0 (out-of-turn)

**Duplicate Detections Skipped**: 3 (all for `drawn_card` action within 500ms window)

---

### 3. `cpu_1769262268530000_3` (CPU Player 3)
**Total Actions**: 5

| Timestamp | Action Type | Action Data |
|-----------|-------------|-------------|
| 14:45:54.217 | `drawn_card` | `{cardId: card_practice_room_1769262261266_queen_diamonds_1_935878573}` |
| 14:46:03.430 | `play_card` | `{cardIndex: 1}` |
| 14:46:21.837 | `jack_swap` | `{card1: {cardIndex: 3, playerId: cpu_1769262268530000_3}, card2: {cardIndex: 1, playerId: practice_session_practice_user_1769262261227}}` |
| 14:46:41.365 | `jack_swap` | `{card1: {cardIndex: 2, playerId: cpu_1769262268530000_2}, card2: {cardIndex: 0, playerId: cpu_1769262268530000_4}}` |
| 14:47:05.410 | `same_rank` | `{cardIndex: 1}` |

**Details**:
- Drew Queen of Diamonds from draw pile
- Played card at index 1
- Used Jack power: swapped own card (index 3) with human player's card (index 1)
- Used Jack power: swapped CPU player 2's card (index 2) with CPU player 4's card (index 0)
- Played same rank card at index 1 (out-of-turn)

**Duplicate Detections Skipped**: 3 (all for `drawn_card` action within 500ms window)

---

### 4. `cpu_1769262268530000_4` (CPU Player 4)
**Total Actions**: 6

| Timestamp | Action Type | Action Data |
|-----------|-------------|-------------|
| 14:45:10.228 | `same_rank` | `{cardIndex: 1}` |
| 14:45:28.885 | `queen_peek` | `{cardIndex: 2, playerId: cpu_1769262268530000_4}` |
| 14:46:12.150 | `same_rank` | `{cardIndex: 2}` |
| 14:46:49.426 | `drawn_card` | `{cardId: card_practice_room_1769262261266_queen_spades_0_740951333}` |
| 14:46:56.473 | `play_card` | `{cardIndex: 4}` |
| 14:47:12.490 | `queen_peek` | `{cardIndex: 3, playerId: cpu_1769262268530000_4}` |

**Details**:
- Played same rank card at index 1 (out-of-turn)
- Used Queen power: peeked at own card at index 2
- Played same rank card at index 2 (out-of-turn)
- Drew Queen of Spades from draw pile
- Played card at index 4
- Used Queen power: peeked at own card at index 3

**Duplicate Detections Skipped**: 3 (all for `drawn_card` action within 500ms window)

---

## Action Type Summary

| Action Type | Count | Description |
|------------|-------|-------------|
| `initial_peek` | 1 | Initial game setup - player peeks at 2 cards |
| `drawn_card` | 3 | Card drawn from draw pile to hand |
| `play_card` | 3 | Card played from hand to discard pile |
| `same_rank` | 5 | Card played during same rank window (out-of-turn) |
| `jack_swap` | 2 | Jack power used to swap cards between players |
| `queen_peek` | 2 | Queen power used to peek at a card |

**Total**: 16 actions

---

## Deduplication System Performance

The deduplication system successfully prevented **9 duplicate action detections**:

- **CPU Player 2**: 3 duplicates for `drawn_card` (skipped at 102ms, 133ms, 193ms after initial detection)
- **CPU Player 3**: 3 duplicates for `drawn_card` (skipped at 107ms, 135ms, 179ms after initial detection)
- **CPU Player 4**: 3 duplicates for `drawn_card` (skipped at 145ms, 189ms, 251ms after initial detection)

**Deduplication Window**: 500ms (as configured in `CardAnimationDetector._deduplicationWindow`)

**Analysis**: All duplicate detections occurred for `drawn_card` actions, likely due to rapid state updates during card drawing. The deduplication system correctly identified and skipped these duplicates, preventing duplicate animations from being queued.

---

## Action Data Structure Analysis

### `initial_peek`
```dart
{
  'cardIndex1': int,  // First card index (0-based)
  'cardIndex2': int,  // Second card index (0-based)
}
```

### `drawn_card`
```dart
{
  'cardId': String,  // Full card identifier
}
```

### `play_card`
```dart
{
  'cardIndex': int,  // Card index in hand before removal (0-based)
}
```

### `same_rank`
```dart
{
  'cardIndex': int,  // Card index in hand before removal (0-based)
}
```

### `jack_swap`
```dart
{
  'card1': {
    'cardIndex': int,      // Index of first card in its owner's hand (0-based)
    'playerId': String,    // ID of player who owns the first card
  },
  'card2': {
    'cardIndex': int,      // Index of second card in its owner's hand (0-based)
    'playerId': String,    // ID of player who owns the second card
  },
}
```

### `queen_peek`
```dart
{
  'cardIndex': int,      // Index of the card being peeked at (0-based)
  'playerId': String,    // ID of the player who owns the card being peeked
}
```

---

## Observations

1. **Action Distribution**: CPU players performed most actions (15 out of 16), with the human player only performing the initial peek.

2. **Special Powers Usage**:
   - **Jack Power**: Used 2 times by CPU Player 3, swapping cards between different player combinations
   - **Queen Power**: Used 2 times by CPU Player 4, both times peeking at own cards

3. **Same Rank Plays**: 5 out-of-turn plays occurred, showing active use of the same rank window feature.

4. **Deduplication Effectiveness**: The 500ms deduplication window successfully prevented 9 duplicate animations, all related to `drawn_card` actions.

5. **Queue Management**: All actions were queued with queue length of 1, indicating sequential processing (animations completed before next action was detected).

---

## References

- **Animation System Documentation**: `Documentation/Dutch_game/ANIMATION_SYSTEM.md`
- **Action Declaration Locations**: See ANIMATION_SYSTEM.md for backend locations where actions are set
- **Log File**: `python_base_04/tools/logger/server.log`
