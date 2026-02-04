# Computer Player: Jack Swap Options and Conditions

This document describes all Jack swap decision options and conditions for the computer player in the Dutch game. Configuration is YAML-driven; target selection is implemented in `computer_player_factory.dart` (Flutter and Dart backend).

---

## 1. Overview

When a computer player plays a Jack, they enter the **jack_swap** phase and must decide whether to use the power and, if so, which two cards to swap. The decision pipeline is:

1. **Miss chance** (per difficulty) — may skip using the Jack entirely.
2. **Game data** — `_prepareSpecialPlayGameData(gameState, playerId, difficulty)` builds the context for rules.
3. **Strategy rules** — evaluated in **priority order** (1 → 6). The first rule whose conditions pass and whose **execution probability** (per difficulty) rolls true is used.
4. **Target selection** — the chosen rule’s `target_strategy` is executed to pick `first_card_id`, `first_player_id`, `second_card_id`, `second_player_id`. If selection fails (e.g. no valid swap), the result can be no-swap.

Config files:

- **Flutter:** `flutter_base_05/assets/computer_player_config.yaml`
- **Dart backend:** `dart_bkend_base_01/lib/modules/dutch_game/config/computer_player_config.yaml`

---

## 2. Pre-checks (before rules)

### 2.1 Miss chance to play

Before any rule is evaluated, the computer may “miss” using the Jack (global `miss_chance_to_play`):

| Difficulty | Miss chance |
|------------|------------|
| Easy       | 6%         |
| Medium     | 4%         |
| Hard       | 2%         |
| Expert     | 1%         |

If the roll hits miss, the decision returns `use: false`, `missed: true` and no swap is performed.

### 2.2 Use probability (per difficulty)

The `difficulties.*.special_cards.jack_swap.use_probability` values indicate intent to use the Jack at all (higher difficulties use it more often). Actual “use or not” is determined by the **strategy rules** below; these values are not re-checked in the current YAML rule flow but reflect design per difficulty:

| Difficulty | Use probability |
|------------|-----------------|
| Easy       | 0.6 (60%)      |
| Medium     | 0.8 (80%)      |
| Hard       | 0.9 (90%)      |
| Expert     | 1.0 (100%)     |

---

## 3. Strategy rules (evaluation order)

Rules are evaluated in **priority order** (1 → 6). Conditions are checked; then the rule’s **execution_probability** for the current difficulty is rolled. If the roll succeeds, that rule runs and no lower-priority rule is used. If conditions fail or the roll fails, evaluation continues to the next rule.

---

### Rule 1: `collection_three_swap` (priority 1)

**Target strategy:** `collection_three_swap`

**Conditions (all required):**

- `isClearAndCollect` — equals `true` (clear-and-collect mode is enabled)
- `other_players_with_three_in_collection` — not empty (at least one player other than the acting player has **3 or more cards in their collection**)

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 100%        |
| Hard       | 95%         |
| Medium     | 70%         |
| Easy       | 50%         |

**Behavior:**

- Only applies when **clear-and-collect** is on. Collection cards are stored per player in a **list** (e.g. `collection_rank_cards` / `collection_cards` in game data); we use the **last** card in that list when selecting.
- **If 2 or more players** (excl. acting) have 3+ cards in collection: swap the **last card in the collection list** of one such player with the **last card in the collection list** of another such player. The two players are chosen at random from the set of players with 3+ in collection.
- **If exactly 1 player** (excl. acting) has 3+ in collection: **first card** = last card in that player’s collection list. **Second card** = any **non-collection** card from **any other player** (excluding the acting player and the first card’s owner), chosen at random. If no such second card exists, the swap is skipped.

---

### Rule 2: `one_card_player_priority` (priority 2)

**Target strategy:** `one_card_player_priority`

**Conditions (all required):**

- `other_players_with_one_card` — not empty (at least one player other than the acting player has exactly 1 card in hand, excluding collection)
- `all_players` — not empty

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 100%        |
| Hard       | 95%         |
| Medium     | 70%         |
| Easy       | 50%         |

**Behavior:**

- “One card in hand” is determined by hand size **excluding collection** (playable count = 1). Irrelevant of `known_cards`.
- If **two or more players** have exactly 1 playable card, those players take **priority** for being selected: one of them is chosen at random as the first side of the swap.
- **First card:** from a player who has only 1 card (if multiple such players, one is chosen at random).
- **Second card:** from **any other player** (excluding the acting player and the first card’s owner) with at least one playable card, chosen at random.
- If there is no valid second player/card (e.g. only one other player and they are the 1-card player), the swap is skipped (no-swap result).

---

### Rule 3: `swap_lowest_opponent_for_higher_own` (priority 3)

**Target strategy:** `lowest_opponent_higher_own`

**Conditions (all required):**

- `acting_player.known_cards` — not empty
- `all_players` — not empty

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 100%        |
| Hard       | 95%         |
| Medium     | 70%         |
| Easy       | 50%         |

**Behavior:**

- From the acting player’s **known cards** (own hand), choose the card with **highest points** → this is the card we give away (`first_card_id`, `first_player_id` = acting player).
- From **other players’ known cards** (in game state), choose the card with **lowest points** → this is the card we take (`second_card_id`, `second_player_id`).
- Swap is only performed if the opponent’s card has **fewer points** than our card (beneficial swap). Otherwise the implementation falls back to `random_two_players` (Rule 5).

**Note:** “Other players’ known cards” currently means each opponent’s view of their own known cards, not necessarily cards the acting player learned via Queen peek. See project notes on known_cards structure.

---

### Rule 4: `random_swap_except_own` (priority 4)

**Target strategy:** `random_except_own`

**Conditions (all required):**

- `all_players` — not empty

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 0%          |
| Hard       | 0%          |
| Medium     | 50%         |
| Easy       | 40%         |

**Behavior:**

- Build a pool of all playable cards (hand minus collection) from **other players only** (acting player’s hand is excluded).
- **The two chosen cards must be from different players** (never two cards from the same player).
- If there are fewer than 2 playable cards in total, or only one player has playable cards (so a second player cannot be chosen), the swap is skipped (no-swap result).
- Otherwise: pick one card at random from the pool, then pick a second card at random from the pool **with a different `playerId`**. Return the two cards as first/second.

---

### Rule 5: `swap_random_two_players` (priority 5)

**Target strategy:** `random_two_players`

**Conditions (all required):**

- `all_players` — not empty
- `acting_player.hand` — not empty (acting player has at least one card)

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 0%          |
| Hard       | 0%          |
| Medium     | 40%         |
| Easy       | 60%         |

**Behavior:**

- Swap **one of our cards** (acting player, excluding collection) with **one card from one other player** (excluding their collection).
- **The two cards are always from different players** (acting vs one other). With only one other player, the swap is still valid (our card ↔ their card).
- One other player is chosen at random; then one card from our hand and one from their hand are chosen at random.

---

### Rule 6: `skip_jack_swap` (priority 6)

**Target strategy:** (none — skip)

**Conditions:**

- `type: "always"` (always passes)

**Execution probability:**

| Difficulty | Probability |
|------------|-------------|
| Expert     | 0%          |
| Hard       | 0%          |
| Medium     | 0%          |
| Easy       | 0%          |

**Behavior:**

- Returns `use: false` (skip). No swap is performed. This rule is used when all higher-priority rules (1–5) have been evaluated and either their conditions failed or their execution probability roll failed.

---

## 4. Summary: which option runs when

| Difficulty | Typical flow |
|------------|----------------|
| **Expert** | Rule 1 (collection three), Rule 2 (one-card priority), or Rule 3 (beneficial swap) when conditions met. If not → skip. Never Rule 4 or 5. |
| **Hard**   | Rule 1, 2 or 3 (95% when conditions met). If not → skip. Never Rule 4 or 5. |
| **Medium** | Rule 1, 2 or 3 (70% when met). If not → Rule 4 (50%) or Rule 5 (40%) or skip. |
| **Easy**   | Rule 1, 2 or 3 (50% when met). If not → Rule 4 (40%) or Rule 5 (60%) or skip. |

---

## 5. Constraints (both random strategies)

- **Random except own:** The two swapped cards are always from **two different players** (never two cards from the same opponent).
- **Random two players:** The two swapped cards are always **our card** and **another player’s card** (always two different players).

Collection cards are excluded from selection in all strategies.

---

## 6. Output shape

The Jack swap decision returns a map compatible with the game round and coordinator, including:

- `action`: `"jack_swap"`
- `use`: `true` or `false`
- `first_card_id`, `first_player_id`, `second_card_id`, `second_player_id` (when `use: true`)
- `delay_seconds`, `difficulty`, `reasoning`
- Optional `missed: true` when the pre-check miss chance triggered

---

## 7. Related files

- **Config (YAML):** `computer_player_config.yaml` (Flutter assets + Dart backend config).
- **Logic:** `computer_player_factory.dart` — `getJackSwapDecision`, `_prepareSpecialPlayGameData` (adds `other_players_with_one_card`, `other_players_with_three_in_collection`), `_evaluateSpecialPlayRules`, `_selectJackSwapTargets`, `_selectCollectionThreeSwap`, `_selectOneCardPlayerPriority`, `_selectLowestOpponentHigherOwn`, `_selectRandomExceptOwn`, `_selectRandomTwoPlayers` (in both `flutter_base_05` and `dart_bkend_base_01`).
- **Game round:** `dutch_game_round.dart` — invokes `getJackSwapDecision` and applies the swap.
