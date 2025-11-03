# Recall Card Game - Game Play and Rules

## Game Flow Overview

The Recall card game follows a structured turn-based system with multiple phases. Players must remember cards they've seen and strategically collect cards while avoiding penalties.

## Initial Peek Phase

The game starts with a **timed initial peek** where each player can peek at any 2 cards from their hand of 4 cards.

### Collection Rank Selection

After peeking at 2 cards, one card is automatically selected as the **collection rank card**. The selection follows this priority order (lowest ranking card is selected):

1. **Joker Exclusion**: Jokers are excluded from collection rank selection. If one card is a joker and the other is not, the non-joker is selected.

2. **Points Comparison**: If points are different, select the card with **least points**.

3. **Priority Order** (when points are equal):
   - **Ace** (Priority 1 - Highest)
   - **Numbers 2-10** (Priority 2)
   - **King** (Priority 3)
   - **Queen** (Priority 4)
   - **Jack** (Priority 5 - Lowest)

4. **Random Selection**: If both cards have the same rank, a random card is selected.

The selected collection rank card:
- Is added to the player's `collection_rank_cards` list (face up)
- Sets the player's `collection_rank` property
- Becomes visible to all players (face up in hand)
- **Cannot be played** during the game (protected from discard)

### Known Cards Storage

The other peeked card is added to the player's `known_cards` list, stored with this structure:

```
known_cards = {
  [playerId]: {
    [cardId]: {
      cardId: string,
      rank: string,
      suit: string,
      points: number,
      specialPower: string (if applicable)
    }
  }
}
```

Each player's `known_cards` is organized by:
- **Player ID as the first key** - allows tracking cards known to each player
- **Card ID as the second key** - allows quick lookup of specific card data

**Important Notes:**
- Human players' `known_cards` are updated by the system for code consistency, but human players must remember cards themselves (they don't see this list in the UI)
- Computer players use `known_cards` with YAML-based AI decision making based on difficulty settings
- `known_cards` are updated after every player action throughout the game

### Remaining Cards

After the initial peek:
- The 2 cards that were peeked remain visible to the player
- The remaining 2 cards stay face down (unturned)
- All 4 cards are in the player's hand
- The game begins with a random player selected to draw

## Turn Structure

### 1. Draw Phase

A random player is selected to start, and then play proceeds clockwise.

**Current Player Actions:**
- Draw a card from the **draw pile** (face down)
- The drawn card is **automatically added to `known_cards`** for computer players
- Human players see the drawn card and must remember it

### 2. Play or Collect Phase

After drawing, the player must choose one of the following actions:

#### Option A: Play a Card

**Available Playing Cards:**
- All cards in hand **except** collection rank cards
- Includes the drawn card
- Does **not** include cards in `collection_rank_cards` list

The played card is discarded to the discard pile (face up).

#### Option B: Collect a Card (If Applicable)

If the drawn card matches the player's `collection_rank`:
- Player can **collect** the card instead of playing or discarding
- Card is added to the `collection_rank_cards` list
- **Collection cards are always face up** in the hand when added to the collection list
- Cards in the collection list are **stacked on top of each other** (visually positioned slightly lower in the widget)
- Card remains visible to all players
- Player's `collection_rank` is updated to match the collected card's rank


### 3. Same Rank Window

After the current player plays/discards a card, the game enters the **same rank window** phase.

**Duration:** 5 seconds (automatically ends)

**Rules:**
- **Any player** can play out of turn
- Player must discard a card with the **same rank** as the last discarded card (top of discard pile)
- Players need to **remember** if and where they have this same rank card in their hand
- Cards from `known_cards` can help players identify matching rank cards

**Penalty for Wrong Play:**
- If a player plays the wrong card (rank doesn't match):
  - The played card is **reverted back to player's hand**
  - Player receives a **penalty card** from the draw pile
  - Penalty card is added to hand **face down** (`suit: '?', rank: '?', points: 0`)
  - Player status is reset to `waiting`

**Successful Same Rank Play:**
- Card is removed from hand
- Card is added to discard pile (face up)
- Player continues in same rank window (can play again if they have another matching rank card)

### 4. Special Cards Window

After the same rank window ends, the game checks for special cards played during:
- The player's turn
- The subsequent same rank window

**Special Cards:**
- **Jack** (jack_swap): Can switch any 2 cards
- **Queen** (queen_peek): Can peek at any one card

If special cards were played, they are added to a `special_cards` list and processed chronologically (in order played).

**Special Play Processing:**
1. Game enters `special_play_window` phase
2. Each player with a special card gets a **10-second timed window**
3. Players are processed **in chronological order** (order they played the special card)
4. After each player completes their special play (or timer expires), the next player's turn begins
5. After all special plays are complete, the `special_cards` list is cleared

#### Jack Swap Power

**Player Status:** `jack_swap` (10-second timer)

**Actions Allowed:**
- Switch any 2 cards from **any player's hands**
- **Non-movable cards:** Draw pile and discard pile cards

**Examples:**
- Swap one of your own cards with a card from another player's hand
- Swap 2 cards from a single player's hand (switches positions in that hand)
- Swap a card from one player with a card from a different player

**Implementation:**
- Cards are swapped in their respective hands
- All players' `known_cards` are updated after successful swap
- Player status returns to `waiting` after swap completes
- Timer automatically moves to next special card if multiple exist

#### Queen Peek Power

**Player Status:** `queen_peek` (10-second timer)

**Actions Allowed:**
- Peek at **any one card** from any player's hand
- **Non-peekable cards:** Draw pile and discard pile cards

**Implementation:**
- Peeked card is added to player's `cardsToPeek` list temporarily
- Card is removed from `cardsToPeek` when timer expires
- Player's `known_cards` are updated with the peeked card information
- Player status returns to `waiting` after timer expires

### 5. Next Player

After all special plays are complete:
- `special_cards` list is cleared
- Game moves to the next player (clockwise)
- Turn logic starts again with Draw Phase

## Known Cards Updates

Every player's `known_cards` list is updated according to game play after every player action:

1. **Initial Peek:** Peeked cards added to own `known_cards[playerId]`
2. **Drawing Cards:** Drawn cards added to computer players' `known_cards`
3. **Playing Cards:** Played cards removed/updated based on visibility
4. **Jack Swap:** All players' `known_cards` updated to reflect swapped cards
5. **Queen Peek:** Peeked card added to peeking player's `known_cards`

**Computer Players:**
- Use `known_cards` for YAML-based AI decision making
- Difficulty settings affect how computer players use `known_cards` information
- Computer players make strategic decisions based on what they know

**Human Players:**
- `known_cards` are maintained by the system for code consistency
- Human players are **not shown** their `known_cards` list in the UI
- Human players must **remember cards themselves**
- This creates the memory challenge that makes the game interesting

## Game Phases

The game progresses through these phases:

1. **`initial_peek`** - Players peek at 2 cards, collection rank selected
2. **`playing`** - Normal gameplay, player's turn
3. **`drawing_card`** - Player is in the process of drawing
4. **`same_rank_window`** - Out-of-turn same rank plays allowed (5 seconds)
5. **`special_play_window`** - Special cards being processed (10 seconds per player)
6. **`ending_round`** - Transition phase before next player
7. **`finished`** - Game completed

## Collection Rank Cards

**Characteristics:**
- **Always face up** when added to the `collection_rank_cards` list
- **Stacked on top of each other** in the hand (visually positioned slightly lower in the widget)
- Visible to all players
- Stored in `collection_rank_cards` list
- Cannot be played or discarded
- Can only be collected (from draw pile or discard pile when rank matches)

**Important Notes:**
- If a matching rank card is **NOT collected**, it remains in hand as a **face down** regular hand card
- Only cards added to the `collection_rank_cards` list become face up and stacked
- Collection cards are visually distinct in the UI (stacked slightly lower than regular hand cards)

**Collection Mechanics:**
- Cards matching `collection_rank` can be collected **at any time** during the game
- Collection is **blocked** during `initial_peek` and `same_rank_window` phases
- Collection can occur from:
  1. **Draw pile:** When drawing a card that matches `collection_rank` (during player's turn)
  2. **Discard pile:** When top card matches `collection_rank` (any time except blocked phases)
- Collection updates the player's `collection_rank` to match the collected card
- Multiple cards of the same rank can be collected
- All collected cards remain **face up** and **stacked** in the player's hand

Players can collect cards from the discard pile **at any time during the game** (no turn restrictions), with these conditions:

**Phase Restrictions:**
- ✅ Allowed during: `playing`, `waiting`, `ready`, `drawing_card`, `special_play_window`, and all other phases
- ❌ **Not allowed** during: `same_rank_window` or `initial_peek`

**Requirements:**
- Discard pile must not be empty
- Top card's rank must match player's current `collection_rank`

**What Happens:**
- Card is removed from discard pile
- Added to `collection_rank_cards` list with full card data
- Card is **face up** in hand (stacked with other collection cards, positioned slightly lower)
- Player's `collection_rank` is updated to match collected card
- No status change - player continues in current state

**Special Case - Playing Unknown Card That Matches Collection Rank:**

If a player plays one of their **unknown cards** (face down card they haven't peeked at) and it happens to be the **same rank as their `collection_rank`**:
- The card is played/discarded normally during their turn
- Player **cannot collect it during same_rank_window** (collection blocked during this phase)
- Player **must wait for same_rank_window to end**
- After same_rank_window ends, if the card is still on top of the discard pile:
  - Player can collect it if it matches their `collection_rank`
  - Card is added to `collection_rank_cards` list
  - Card becomes **face up** in hand (stacked with other collection cards)


## Winning Conditions

The game ends when **any one** of the following conditions is met:

1. A player has **no cards remaining** in hand (including collection rank cards)
2. A player has collected **all four cards** of their collection rank (4 of a kind)
3. A player calls **'Recall'** and the final round completes

**After Recall is Called:**
- All other players get **one last turn**
- Winner is determined by:
  - **Lowest points total**
  - If points tie, **fewer cards** wins
  - If points and cards tie:
    - **Recall caller wins** if involved in tie
    - Otherwise, it's a **draw**

## Penalties Summary

1. **Wrong Same Rank Play:**
   - Played card **reverted** to hand
   - **One penalty card** drawn from draw pile
   - Penalty card added **face down**

## Timer Durations

- **Initial Peek:** Configurable (typically timed)
- **Same Rank Window:** **5 seconds**
- **Special Play Window:** **10 seconds** per player with special card
- **Player Turn:** Timed per action
  - **10 seconds** to draw a card
  - **10 seconds** to play a card
  - Game progresses to next player if timer expires

---

## Technical Implementation Notes

### Collection Rank Selection Code Reference

The collection rank selection logic is implemented in both Flutter and Dart backend:
- Flutter: `practice_game.dart` - `_selectCardForCollection()` method
- Dart Backend: `game_event_coordinator.dart` - `_selectCardForCollection()` method

### Known Cards Structure

```
player.known_cards = {
  [playerId]: {
    [cardId]: {
      cardId: string,
      rank: string,
      suit: string,
      points: number,
      specialPower: string
    }
  }
}
```

### Collection Rank Cards Structure

```
player.collection_rank_cards = [
  {
    cardId: string,
    rank: string,
    suit: string,
    points: number,
    specialPower: string
  },
  // ... more collected cards
]
```

### Phase Restrictions for Collection

Collection from discard pile is **blocked** during:
- `same_rank_window` phase
- `initial_peek` phase

Collection is **allowed** during all other phases, regardless of player turn or status.

