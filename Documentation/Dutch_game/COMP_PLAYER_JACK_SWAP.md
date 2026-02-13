# Computer Player: Jack Swap Logic

This document describes how the computer player decides **whether** and **how** to use a Jack swap: strategy order, difficulty-based probabilities, history tracking, and the post-filter that can allow repeating a previously swapped pair.

---

## 1. Overview

When a computer player plays a Jack, the game asks for a **Jack swap decision**. The decision is produced by:

1. **Miss chance** (optional skip before any strategy).
2. **Strategy loop**: try strategies in a fixed order; for each strategy, roll vs its difficulty-based percentage; if the strategy is “taken”, run it and get a candidate swap (two cards from two players).
3. **Validity**: candidate must have all four IDs non-null/non-empty (first_card_id, first_player_id, second_card_id, second_player_id).
4. **History post-filter**: if the candidate pair was already swapped by this player in the same “special-cards window”, either reject it and try the next strategy, or **allow the repeat** with a difficulty-based probability.
5. If no strategy yields an accepted swap, the decision is **use: false** (skip Jack swap). Otherwise **use: true** with the chosen swap, which is then applied in `handleJackSwap` (SSOT).

Strategies do **not** receive history; history is only used as a **post-filter** on the chosen pair.

---

## 2. Entry Point and Timing

- **Entry**: `getJackSwapDecision(difficulty, gameState, playerId)` in `computer_player_factory.dart` (Dart backend and Flutter).
- **Timer**: Decision delay is derived from `gameState['timerConfig']['jack_swap']` (default 10s), via `_calculateTimerBasedDelay` (0.4–0.8 of that value).
- **Output**: Map with `action: 'jack_swap'`, `use: true|false`, optional `first_card_id`, `first_player_id`, `second_card_id`, `second_player_id`, `delay_seconds`, `difficulty`, `reasoning`.

---

## 3. Miss Chance (Pre-Strategy)

Before the strategy loop, a **miss chance** is applied per difficulty (from YAML `computer_settings.miss_chance_to_play`):

- **expert**: 0%
- **hard**: 1%
- **medium**: 3%
- **easy**: 5%

If the roll is below the miss chance, the function returns immediately with `use: false` and `missed: true`. Otherwise execution continues to the strategy loop.

---

## 4. Game Data for Strategies

`_prepareSpecialPlayGameData(gameState, playerId, difficulty)` builds a single structure used by all Jack swap (and other special-play) strategies. It includes:

- `acting_player_id`, `acting_player` (hand, known_cards, collection_cards),
- `all_players` (map of player id → hand, collection_cards, etc.),
- `game_state` (full game state),
- `isClearAndCollect`,
- `other_players_with_three_in_collection`,
- `other_players_with_one_card`,
- and related fields.

Strategies only see this `gameData`; they do **not** see `jack_swap_history`.

---

## 5. Strategy Loop and Probabilities

### 5.1 Order of Strategies

Strategies are tried in this **fixed order** (only the first has non-zero probability in code; the rest act as fallbacks when earlier ones skip or fail):

| Order | Strategy ID                      | Description (short) |
|-------|-----------------------------------|---------------------|
| 1     | `collection_three_swap`          | Clear-and-collect: swap involving players with 3+ in collection (last in list). |
| 2     | `one_card_player_priority`       | Swap involving a player with only one card; other card from another player. |
| 3     | `lowest_opponent_higher_own`     | Swap opponent’s lowest known point card with a higher point card from own hand. |
| 4     | `random_except_own`              | Random swap of two cards from other players only (excl. acting hand and collection). |

There is **no** “random_two_players” (swap including own hand) in the loop; if no strategy returns a valid swap, the AI skips the Jack swap.

### 5.2 Strategy Selection Probability (Roll vs %)

For **each** strategy in order:

1. Read the strategy’s difficulty-based percentage from the **hardcoded** list (see below).
2. Roll once: `roll = random(0, 100)`.
3. If `roll >= percent`, **skip** this strategy (log and `continue` to next).
4. If `roll < percent`, **select** this strategy: call `_selectJackSwapTargets(gameData, strategyId)` and get a candidate swap.

The percentages below are defined **in code** (not YAML) for the **first** strategy only; the others are 0 and only run when earlier strategies are skipped by the roll or produce no valid swap.

**Strategy percentages (in code):**

| Strategy ID                | expert | hard | medium | easy |
|----------------------------|--------|------|--------|------|
| collection_three_swap      | 98     | 95   | 85     | 70   |
| one_card_player_priority   | 0      | 0    | 0      | 0    |
| lowest_opponent_higher_own | 0      | 0    | 0      | 0    |
| random_except_own          | 0      | 0    | 0      | 0    |

So in practice only **collection_three_swap** is ever “rolled for”; the others are tried only when a previous strategy was skipped (roll >= percent) or returned an invalid or history-rejected swap.

### 5.3 Validity and History Check

After a strategy returns a candidate:

- **Valid** means: `first_card_id`, `first_player_id`, `second_card_id`, `second_player_id` are all non-null and non-empty.
- **Already swapped** = `_jackSwapPairAlreadyUsed(gameState, playerId, firstCardId, secondCardId)` is true (pair exists in this player’s `jack_swap_history` for the current window).

Then:

- If valid and **not** already swapped → **accept** and **break** (use this swap).
- If valid and **already swapped** → apply the **history post-filter** (see §6).
- If not valid → log and continue to the next strategy.

---

## 6. History Post-Filter: Allow-Repeat Probability

When the candidate swap is **valid** but the pair was **already swapped** by this player in the same special-cards window:

1. Get **allow-repeat percentage** for current difficulty: `_jackSwapAllowRepeatHistoryPercent(difficulty)`.
2. Roll once: `repeatRoll = random(0, 100)`.
3. If `repeatRoll < allowRepeatPercent` → **allow the repeat**: treat as accepted and **break** (use this swap).
4. Otherwise → reject and continue to the next strategy.

**Allow-repeat percentages (in code):**

| Difficulty | Allow-repeat (same pair) |
|------------|---------------------------|
| expert     | 0%                        |
| hard       | 2%                        |
| medium     | 8%                        |
| easy       | 15%                       |
| default    | 8%                        |

So expert never repeats a pair; easy has a 15% chance to repeat when the only candidate was already used.

---

## 7. Jack Swap History (SSOT)

### 7.1 Where It Lives

- **Key**: `gameState['jack_swap_history']`
- **Type**: `Map<String, dynamic>` (playerId → that player’s swap list).
- **Per-player value**: `Map<String, dynamic>` with keys `swap1`, `swap2`, … and values `[cardId1, cardId2]` (unordered pair).

So: `gameState['jack_swap_history'][actingPlayerId]['swapN'] = [firstCardId, secondCardId]`.

### 7.2 Recording (SSOT)

Recording happens **only** in `handleJackSwap` (in both Dart and Flutter `dutch_game_round.dart`), after a successful swap:

- Ensure `gameState['jack_swap_history']` exists.
- Ensure `gameState['jack_swap_history'][actingPlayerId]` exists.
- Append: `playerSwaps['swap${playerSwaps.length + 1}'] = [firstCardId, secondCardId]`.

No other code should write to `jack_swap_history`.

### 7.3 Clearing

- **When**: In **`_startNextTurn`**, when the **next** player is set (e.g. `gameStateData['currentPlayer'] = nextPlayer`).
- **What**: Only **that** player’s entry is removed: `jack_swap_history.remove(nextPlayerId)`.
- **Why**: The incoming player starts their turn with no Jack swap history; other players’ history stays until their own turn starts.

History is **not** cleared in `_endSpecialCardsWindow`; it is cleared per player at turn start.

### 7.4 Checking “Already Used”

`_jackSwapPairAlreadyUsed(gameState, actingPlayerId, card1Id, card2Id)`:

- Reads `gameState['jack_swap_history'][actingPlayerId]`.
- Iterates over each `swapN` list; if any list contains the same two card IDs (in either order), returns **true**; otherwise **false**.

---

## 8. Strategy Behaviors (Short Reference)

- **collection_three_swap**  
  Requires clear-and-collect and at least one other player with 3+ cards in collection. If 2+ such players: swap last collection card of one with last of another (players chosen randomly). If exactly one: swap their last collection card with a random playable card from another player.

- **one_card_player_priority**  
  At least one other player with exactly one (playable) card. If 2+ such players: swap those two players’ single playable cards (deterministic, first two). If exactly one: swap that card with a random playable card from another player.

- **lowest_opponent_higher_own**  
  Uses known_cards: find an opponent’s lowest-point card and a higher-point card in own hand; swap them. Falls back to `_selectRandomExceptOwn` if no such pair.

- **random_except_own**  
  Collect all playable cards (hand minus collection) from players other than the acting player; pick two from **different** players at random.

---

## 9. YAML vs Code

- **YAML** (`computer_player_config.yaml` under `events.jack_swap`) describes strategy rules and execution probabilities for documentation / other consumers. The **current** Dart/Flutter implementation does **not** use YAML for the Jack swap strategy loop; it uses the **hardcoded** strategy list and percentages in `getJackSwapDecision`.
- **Miss chance** comes from YAML: `computer_settings.miss_chance_to_play` per difficulty.
- **Timer** for Jack swap comes from `gameState['timerConfig']['jack_swap']` (e.g. from game registry default 10s).

---

## 10. Files and Locations

| Concern              | Dart backend | Flutter |
|----------------------|--------------|---------|
| Decision + strategies| `dart_bkend_base_01/.../computer_player_factory.dart` | `flutter_base_05/.../computer_player_factory.dart` |
| History record       | `dart_bkend_base_01/.../dutch_game_round.dart` (`handleJackSwap`) | `flutter_base_05/.../dutch_game_round.dart` (`handleJackSwap`) |
| History clear        | Same round files in `_startNextTurn` | Same |

Both codebases keep the same strategy order, strategy percentages, allow-repeat percentages, and history semantics so that backend and client behave consistently.
