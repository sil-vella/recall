# Same Rank Play – Computer Player Flow (current)

This document describes how same rank play is handled for computer players: what data is used, what is parsed, and how the actual play is executed. All references are to the Flutter/Dart codebase; the Dart backend mirrors the same logic.

---

## 1. Entry point

- When the **same rank window** starts, `_handleSameRankWindow()` sets all players to `same_rank_window` and starts the timer.
- When the timer ends, `_endSameRankWindow()` runs. For each **computer** player it calls **`_handleComputerSameRankPlay(playerId, difficulty, currentGames)`** (e.g. `dutch_game_round.dart` ~4271–4272, ~4982).

---

## 2. Data used (round → factory)

### 2.1 Building “available” same rank cards (round)

- **Method:** `_getAvailableSameRankCards(playerId, gameState)` in `dutch_game_round.dart` (~5064–5213).
- **Inputs:**  
  - `gameState`: players, hands, `known_cards`, `discardPile`, `drawPile`, `isClearAndCollect`, etc.  
  - `playerId`: the computer player.
- **Logic:**
  - Target rank = rank of **top of discard pile**.
  - Get that player’s **hand** (list of card maps, often ID-only) and **known_cards** (card-ID-based: `known_cards[playerId][cardId]` with optional `handIndex`).
  - Optional: if collection mode is on, get **collection_rank_cards** and treat those card IDs as excluded.
  - Loop over **hand by index** `i`:
    - Read **cardId** from `hand[i]['cardId']`.
    - Resolve **full card** via `_stateCallback.getCardById(gameState, cardId)` to get rank.
    - If rank != target rank → skip.
    - If **cardId not in known_cards** (for this player) → skip (only “known” same-rank cards are playable).
    - Else add **cardId** to the list.
  - Build **collection card IDs** and skip any hand card whose ID is in that set when in clear-and-collect mode.
- **Output:** `List<String>` of **card IDs** – the “available same rank cards” for that player. So the round currently works in terms of **card IDs**, not indices, when building the list passed to the factory.

---

## 3. What is parsed (computer player factory)

- **Method:** `getSameRankPlayDecision(difficulty, gameState, availableCards)` in `computer_player_factory.dart` (~175–261).
- **Inputs:**
  - `difficulty`: string (e.g. easy/medium/hard/expert).
  - `gameState`: full game state (players, hands, discard, etc.).
  - **`availableCards`:** `List<String>` of **card IDs** (from the round’s `_getAvailableSameRankCards`).
- **Logic (high level):**
  - **Miss chance:** optional skip; return `play: false`, `card_id: null`.
  - **Play probability:** optional “don’t play”; return `play: false`, `card_id: null`.
  - **Wrong-card (inaccuracy):** optionally pick a **wrong** card from hand (different rank); still returns a **card ID** in `card_id`.
  - **Correct play:** call **`_selectSameRankCard(availableCards, ...)`** which:
    - Builds **game data** via `_prepareSameRankGameData(availableCards, currentPlayer, gameState)`:
      - Splits `availableCards` into **known_same_rank_cards** vs **unknown_same_rank_cards** using player’s **known_cards** (by card ID).
      - Passes `available_same_rank_cards`, `known_same_rank_cards`, `unknown_same_rank_cards`, `all_cards_data` to the YAML engine.
    - Loads **YAML:** `config.getEventConfig('same_rank_play')` → `strategy_rules`.
    - **YAML rules engine** runs over that game data and returns a **single card ID** (one of the available cards).
  - Return map includes **`card_id`** (String, the chosen card ID), `play: true`, `delay_seconds`, `difficulty`, `reasoning`.
- So the factory **only ever sees and returns card IDs**; it does not use or return hand indices.

---

## 4. How the actual same rank play is executed (round + coordinator)

### 4.1 Computer path (in-process)

- In **`_handleComputerSameRankPlay`** (`dutch_game_round.dart` ~5020–5047):
  - `decision['card_id']` is read; if invalid, fallback to first valid ID in `availableCards`.
  - Then **`handleSameRankPlay(playerId, cardId)`** is called with that **card ID**.

### 4.2 Human / client path (event)

- **Coordinator** (`game_event_coordinator.dart` ~160–169): on **`same_rank_play`** event it reads:
  - **`player_id` / `playerId`**
  - **`card_id` / `cardId`**
  and calls **`round.handleSameRankPlay(playerId, cardId)`**.

So both computer and human paths currently use **playerId + cardId** as the interface.

### 4.3 Executing the play in the round

- **Method:** `handleSameRankPlay(playerId, cardId, { gamesMap })` in `dutch_game_round.dart` (~3056–3330).
- **Resolve card in hand:**
  - **`_getCardInHandByCardIdOrIndex(player, hand, cardId)`**:
    - First tries to find the card by **scanning hand** for `card['cardId'] == cardId`.
    - If not found, **fallback:** use **known_cards[playerId][cardId]['handIndex']** and return `hand[handIndex]` and that index.
  - If resolution fails → log “Card not found…” and return false.
- **Validation:** `_validateSameRankPlay(gameState, cardRank)` checks played card rank vs discard top rank. If wrong rank → **penalty** (draw from draw pile, add to hand, broadcast, return true).
- **Successful play:**
  - **cardIndex** = resolved index from above.
  - Create **blank slot** at that index or **remove** the card (depending on `_shouldCreateBlankSlotAtIndex`).
  - **Action for animation:** `card1Data: { cardIndex, playerId }` (index is used here).
  - Add card to discard, update **turn_events** (by cardId + actionType `'play'`), **updateKnownCards** for `same_rank_play`, broadcast state.

So: the **external interface** (decision, event, `handleSameRankPlay` parameter) is **card ID**. The round **resolves** that to a hand index (by cardId then handIndex fallback) and then uses **index** internally for editing the hand and for animation data.

---

## 5. Summary table

| Stage | Data used / parsed | Type |
|-------|--------------------|------|
| Round builds “available” list | Hand (by index), getCardById(cardId), known_cards by cardId, target rank from discard | **Output:** `List<String>` **card IDs** |
| Factory decision | availableCards (card IDs), gameState, known_cards (by cardId) | **Output:** `card_id` (String) |
| Coordinator (human) | Event payload `player_id`, `card_id` | **Forwards:** playerId, cardId |
| handleSameRankPlay | playerId, **cardId** | Resolves to **index** via cardId then handIndex fallback; then uses **index** for hand edit and actionData |

---

## 6. Index-only direction (for refactor)

To align with the “index only, no card IDs” plan:

- **Round:** Build “available” same rank as **list of (playerId, handIndex)** or at least **hand indices** for the acting player, instead of card IDs.
- **Factory:** Consume indices (or index-based game data) and return e.g. **`card_index`** (and playerId) instead of **`card_id`**.
- **handleSameRankPlay:** Add an overload or change semantics to accept **playerId + cardIndex** and resolve the card from `hand[cardIndex]` (no cardId lookup). Coordinator and computer path would then send/receive index instead of card_id.
- **known_cards:** Can still be updated by card identity after the play (e.g. card at index was played); resolution for the play itself would be by index only.

This document reflects the **current** behaviour; the refactor to index-only is described in `00_MASTER_PLAN.md` (Top Priority – same rank).
