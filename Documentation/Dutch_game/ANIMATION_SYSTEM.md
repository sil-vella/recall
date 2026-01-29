# Dutch Game – Animation System

This document describes the animation system used for card movements, peeks, and special actions in the Dutch game. It covers action declarations, bounds caching, animation types, overlay rendering, queueing, and duplicate detection.

---

## 1. Overview

- **Purpose**: Animate card moves (draw, play, reposition, collect, jack swap) and special effects (queen/initial peek flash) so the UI reflects game actions clearly.
- **Flow**: Game round declares **actions** (name + data) on players; state is broadcast; the unified game board **collects** actions from all players, **expands** some (e.g. jack_swap → two sub-actions), **resolves** source/destination **bounds** from cached card positions, and runs **one animation per action** in sequence on an **overlay**.
- **Key files**:
  - **Action declarations**: `lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
  - **Action → type mapping, validation, duplicate set**: `lib/modules/dutch_game/screens/game_play/functionality/animations.dart`
  - **Bounds cache**: `lib/modules/dutch_game/screens/game_play/functionality/playscreenfunctions.dart`
  - **Overlay, queue processing, trigger**: `lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`

---

## 2. Action Declarations

### 2.1 Format (SSOT)

All animated actions use the **same queue format** so the UI can consume them uniformly.

- **Location**: `DutchGameRound._addActionToPlayerQueue(player, actionName, actionData)` (game_round.dart).
- **Contract**:
  - `player['action']` is a **List** of items.
  - Each item is `{ 'name': String, 'data': Map<String, dynamic> }`.
  - `name` = `'<base_action>_<6-digit-id>'` (e.g. `drawn_card_123456`, `jack_swap_1_123457`).
  - `data` always has at least `card1Data`; some actions also have `card2Data`.

`_addActionToPlayerQueue`:

- Ensures `player['action']` exists and is a List (converts legacy single `action` + `actionData` if needed).
- Appends one entry: `{ 'name': actionName, 'data': actionData }`.
- Used for: **drawn_card**, **play_card**, **draw_reposition**, **same_rank**, **queen_peek**, **jack_swap**, **collect_from_discard** (human and computer paths).

### 2.2 Action names and data shape

| Action                 | Declared in / when                    | actionData shape |
|------------------------|----------------------------------------|------------------|
| `drawn_card_<id>`      | After adding drawn card to hand        | `card1Data: { cardIndex, playerId }` (destination hand index) |
| `collect_from_discard_<id>` | After adding collected card to hand   | `card1Data: { cardIndex, playerId }` — **cardIndex = first collection card index** (stack position), not append index; see §2.3 |
| `play_card_<id>`       | When playing a card to discard         | `card1Data: { cardIndex, playerId }` (source hand) |
| `same_rank_<id>`       | When playing same-rank to discard      | `card1Data: { cardIndex, playerId }` |
| `draw_reposition_<id>`| When repositioning drawn card in hand | `card1Data`, `card2Data`: each `{ cardIndex, playerId }` (source slot, dest slot) |
| `queen_peek_<id>`      | When queen peek targets one card       | `card1Data: { cardIndex, playerId }` (peeked card) |
| `initial_peek_<id>`    | Coordinator, per player after deal    | `card1Data`, `card2Data` (two peeked cards) |
| `jack_swap_<id>`       | When jack swap completes (two cards)   | `card1Data`, `card2Data`: each `{ cardIndex, playerId }` (first card, second card) |

- **IDs**: 6-digit numeric suffix from `_generateActionId()` (100000–999999) so each action name is unique.
- **Base name**: Obtained by stripping that suffix (e.g. `drawn_card_123456` → `drawn_card`). Used for mapping to animation type and for overlay logic (e.g. empty slot at source vs destination).

### 2.3 Collection destination index (collect_from_discard)

When a card is collected from the discard pile it is **appended** to the hand and added to `collection_rank_cards`. The UI renders collection cards as a **stack** at the **first** collection card’s hand index (see §5.4). The action must therefore declare **cardIndex = first collection card index** (the minimum hand index whose card is in `collection_rank_cards`), not the append index (`hand.length - 1`). Otherwise the animation would target the wrong slot. Game round computes this in `handleCollectFromDiscard`: after adding the card to hand and to `collection_rank_cards`, it scans the hand for the first index whose card is in the collection set and uses that as `cardIndex` in the action.

---

## 3. Action → Animation type mapping

- **API**: `Animations.getAnimationTypeForAction(actionName)` (animations.dart).
- **Logic**: `extractBaseActionName(actionName)` removes the trailing `_<6-digit-id>`; then a switch on the base name returns an `AnimationType`.

### 3.1 Base name extraction

- **Rule**: If the substring after the last `_` is exactly 6 digits, it is treated as the action ID and removed.
- **Examples**: `drawn_card_123456` → `drawn_card`; `jack_swap_1_123457` → `jack_swap_1`.

### 3.2 Mapping table

| Base action             | AnimationType        | Notes |
|-------------------------|----------------------|--------|
| `drawn_card`            | `moveCard`           | Draw pile → hand |
| `collect_from_discard`  | `moveCard`           | Discard pile → hand |
| `play_card`             | `moveWithEmptySlot` | Hand → discard; empty at source |
| `same_rank`             | `moveWithEmptySlot`  | Hand → discard; empty at source |
| `draw_reposition`       | `moveWithEmptySlot`  | Hand slot → hand slot; empty at source (and dest) |
| `jack_swap`             | `moveWithEmptySlot`  | Expanded at queue into jack_swap_1 + jack_swap_2 |
| `jack_swap_1`           | `moveWithEmptySlot`  | First leg: card1 → slot2; empty at source |
| `jack_swap_2`           | `moveWithEmptySlot`  | Second leg: card2 → slot1; empty at destination only |
| `queen_peek`            | `flashCard`          | Flash border on one card |
| `initial_peek`          | `flashCard`          | Flash border on multiple cards |
| (default)               | `none`               | No animation |

---

## 4. Animation types

- **Enum**: `AnimationType` in animations.dart (`fadeIn`, `fadeOut`, `slideIn`, `slideOut`, `scaleIn`, `scaleOut`, `move`, **moveCard**, **moveWithEmptySlot**, `swap`, `peek`, **flashCard**, **none**).
- **Used in game**: `moveCard`, `moveWithEmptySlot`, `flashCard`, `none`.

### 4.1 Durations and curves

- **Durations** (ms): `moveCard` 1000, `moveWithEmptySlot` 1000, `flashCard` 1500 (3 flashes).
- **Curves**: `moveCard` and `moveWithEmptySlot` use `Curves.easeInOutCubic`; `flashCard` uses `Curves.easeInOut`.

---

## 5. Bounds cached for cards (and piles)

Bounds are stored in **PlayScreenFunctions** (playscreenfunctions.dart) and read when building animations.

### 5.1 What is cached

- **Piles**: Draw pile, discard pile, game board — each as `Map<String, dynamic>?` with `position` (Offset) and `size` (Size). Updated from `GlobalKey` + `RenderBox.localToGlobal` in a **rate-limited** update (see below).
- **My hand**: `_myHandCardBounds`: `Map<int, Map<String, dynamic>>` (index → bounds). Keys stored in `_myHandCardKeys`.
- **Opponents**: `_opponentCardBounds`: `Map<String, Map<int, Map<String, dynamic>>>` (playerId → index → bounds). Keys in `_opponentCardKeys`.

Each bounds entry has `position` (global Offset) and `size` (Size).

### 5.2 When bounds are updated

- **Piles**: Via a rate-limited callback (e.g. 5-second interval) that reads `drawPileKey`, `discardPileKey`, `gameBoardKey` and updates `_drawPileBounds`, `_discardPileBounds`, `_gameBoardBounds`.
- **My hand**: A **post-frame callback** in the unified game board iterates over all hand indices and calls `updateMyHandCardBounds(i, cardKey)`. For **collection stack** indices, the same key (first collection index’s key) is used so all get the same bounds; see §5.4.
- **Opponents**: Same pattern: post-frame callback iterates indices and calls `updateOpponentCardBounds(playerId, i, cardKey)`. Collection indices use the first collection index’s key; see §5.4.
- **Cleanup**: `clearMissingMyHandCardBounds`, `clearMissingOpponentCardBounds` remove indices that no longer exist.

### 5.3 How animations use bounds

- **Unified game board** holds a `PlayScreenFunctions` instance and uses it inside `_triggerAnimation` to resolve **sourceBounds** and **destBounds** from action data:
  - **moveCard**: e.g. draw/discard pile bounds for source; `getCachedMyHandCardBounds(index)` or `getCachedOpponentCardBounds(playerId, index)` for dest (used for drawn_card, collect_from_discard).
  - **moveWithEmptySlot**: hand bounds for source (my hand or opponent); discard pile for play_card/same_rank; or hand-to-hand for draw_reposition / jack_swap_1 / jack_swap_2 (card1Data = source, card2Data = dest).
- **flashCard**: Collects a list of card bounds (from my hand + opponents) for the peeked cards and passes them to the overlay.

So overlay positions are **always** from the cache (`getCached*`), not from a second measurement at animation time.

### 5.4 Collection stacks (one key per stack)

Collection cards (same rank) are rendered as a **stack** at a single slot: the **first** collection card’s hand index. Bounds are normalized so that **every index that belongs to that stack** resolves to the **same** bounds (the stack position). That way animations that target any collection index (e.g. `collect_from_discard` with `cardIndex` = first collection index) use the stack position.

- **My hand**: The stack is built with **one key** on the stack container (`SizedBox`), not on each inner card. Inner cards are built with `key: null`. In the post-frame bounds callback, the widget computes the set of **collection indices** (hand indices whose card is in `collection_rank_cards`), takes the **first** (minimum) index, and for every index in that set uses that index’s key when calling `updateMyHandCardBounds`. So all collection indices get the same cached bounds (the stack container’s bounds).
- **Opponents**: The stack reuses existing card widgets; in the post-frame callback, for every index in the collection set the same key (first collection index’s key) is used when calling `updateOpponentCardBounds`. So all collection indices again share one bounds (the first card’s position = stack position).

The **declaration** side (game round) must pass the **first collection index** as `cardIndex` for actions that animate to a collection (e.g. `collect_from_discard`); see §2.3.

---

## 6. Animation overlay (layers)

- **Widget**: `_buildAnimationOverlay()` in unified_game_board_widget.dart. Rendered only when `_activeAnimations` is non-empty.
- **Coordinate system**: Overlay is a Stack; global bounds from PlayScreenFunctions are converted to **local** by subtracting the main Stack’s `localToGlobal(Offset.zero)` so overlay children use local coordinates.

### 6.1 Two visual layers

1. **Non–flashCard animations** (moveCard, moveWithEmptySlot): Each entry in `_activeAnimations` produces one child from `_buildAnimatedCard(animData, stackGlobalOffset)`. These are stacked first.
2. **flashCard animations**: Each flashCard entry produces one or more border widgets from `_buildFlashCardBorders(...)`. These are stacked after the moving cards so borders draw on top.

So: **layer 1** = moving cards (and their empty slots); **layer 2** = flash borders.

### 6.2 _buildAnimatedCard (moveCard vs moveWithEmptySlot)

- **Input**: `animData` contains `animationType`, `sourceBounds`, `destBounds`, `controller`, `animation`, `cardData`, `actionName`.
- **moveCard**: Renders a single card that interpolates from `sourceBounds.position` to `destBounds.position` (and size lerp). No empty-slot widgets.
- **moveWithEmptySlot**: Renders **empty slot(s)** and **one moving card**:
  - **Empty at source**: Shown for all except when `baseActionName == 'jack_swap_2'`.
  - **Empty at destination**: Shown when `baseActionName == 'draw_reposition'` (both source and dest) or `baseActionName == 'jack_swap_2'` (dest only).
  - Empty slots use `_buildBlankCardSlot(size)` (felt + border).
  - The moving card is an `AnimatedBuilder` that lerps position/size from source to destination over the animation value.

So **empty slots in the overlay are tied to animation type** (only for `moveWithEmptySlot`) and **placement** (source vs dest) is **tied to base action name** (draw_reposition, jack_swap_2, etc.).

### 6.3 flashCard

- **flashCard** does not use source/dest bounds for a move; it uses a **list of card bounds** (`cardBoundsList`) stored in `animData`.
- **Rendering**: 3 flashes (opacity pattern over 0–0.33, 0.33–0.66, 0.66–1.0) with borders at each card’s bounds.

---

## 7. Queueing and processing order

### 7.1 Where actions come from

- **State**: Each player has `player['action']` in game state (list format or legacy single action + `actionData`).
- **Collection**: On state update, `_processStateUpdate` walks all players and builds **allActions**: a flat list of `{ 'name', 'data', 'playerId' }` from every player’s queue (and legacy format is normalized to the same shape).

### 7.2 Expansion (jack_swap)

- Before running any animation, the list is **expanded**:
  - For each item with `extractBaseActionName(name) == 'jack_swap'`, that single action is **replaced** by two:
    - First: `name: 'jack_swap_1_<id+1>'`, `data: { card1Data, card2Data }` (card1 → slot2).
    - Second: `name: 'jack_swap_2_<id+2>'`, `data: { card1Data: card2Data, card2Data: card1Data }` (card2 → slot1).
  - The original `jack_swap_<id>` is **marked as processed** so it is never run as-is.
- All other actions are left unchanged. The result is the **expanded action list** used for the rest of the pipeline.

### 7.3 Sequential processing

- Actions are processed **one after another**: for each entry, the widget calls `_triggerAnimation(action, actionData)` and **awaits** the returned Future before processing the next.
- A **4-second timeout** is active while any action is pending; on timeout, active animations are disposed and state update completes so the UI does not hang if an animation never finishes.

---

## 8. Duplicate detection

Two mechanisms prevent the same logical action from animating twice.

### 8.1 Processed-action set (Animations)

- **Storage**: `Animations._processedActions` (static `Set<String>`).
- **Mark**: `Animations.markActionAsProcessed(actionName)` is called when an animation is **started** (and when jack_swap is expanded for the original name).
- **Check**: `Animations.isActionProcessed(actionName)` is used in the processing loop; if true, the action is **skipped** (no animation triggered).
- So the **same action name** (e.g. `drawn_card_123456`) is only ever animated once per app run, even if state is re-delivered.

### 8.2 Active-animations map (UnifiedGameBoardWidget)

- **Storage**: `_activeAnimations`: `Map<String, Map<String, dynamic>>` (actionName → anim data).
- **Check**: At the start of `_triggerAnimation`, if `_activeAnimations.containsKey(actionName)` we return without starting another animation.
- **Cleanup**: When the animation completes (or errors), that key is removed from `_activeAnimations`. So we avoid **concurrent** duplicate runs for the same action; the processed set avoids **re-runs** on later state updates.

---

## 9. Validation

- **API**: `Animations.validateActionData(actionName, actionData)`.
- **Rules**:
  - `actionData` must be non-null and contain `card1Data`.
  - `card1Data` must contain `cardIndex` and `playerId`.
  - If `actionName.startsWith('jack_swap')` or `actionName.startsWith('initial_peek')`, `actionData` must also contain `card2Data` with `cardIndex` and `playerId`.
- Used before calling `_triggerAnimation`; if validation fails, the action is skipped (and a warning may be logged).

---

## 10. End-to-end flow (summary)

1. **Game round** (or coordinator for initial_peek): Appends actions via `_addActionToPlayerQueue` with unique `action_name_<id>` and structured `data`. State is broadcast.
2. **Unified game board** receives state; runs `_processStateUpdate`.
3. **Collect** all actions from all players into one list; **expand** jack_swap into jack_swap_1 and jack_swap_2.
4. For each action in order: **skip** if `_activeAnimations` or `Animations.isActionProcessed` already has it; **validate** data; **resolve** source/dest bounds from PlayScreenFunctions cache using action type and card1Data/card2Data; **store** in `_activeAnimations` and **mark** as processed; **start** controller; **await** completion; then remove from `_activeAnimations`.
5. **Overlay** builds from `_activeAnimations`: moveCard/moveWithEmptySlot → `_buildAnimatedCard` (with optional empty slots by action name); flashCard → `_buildFlashCardBorders`.
6. When all actions in the list have been processed, state update completes (prev_state updated, etc.).

---

## 11. File reference

| Concern | File |
|--------|------|
| Action queue format, SSOT append | `dutch_game_round.dart` – `_addActionToPlayerQueue`, `_generateActionId` |
| Action → type, validation, processed set | `animations.dart` – `getAnimationTypeForAction`, `extractBaseActionName`, `validateActionData`, `markActionAsProcessed`, `isActionProcessed` |
| Bounds cache (piles, my hand, opponents) | `playscreenfunctions.dart` – `getCached*`, `update*Bounds`, rate-limited pile updates |
| Overlay, queue loop, trigger, active map | `unified_game_board_widget.dart` – `_processStateUpdate`, `_triggerAnimation`, `_buildAnimationOverlay`, `_buildAnimatedCard`, `_buildBlankCardSlot`, `_buildFlashCardBorders` |

For timer and status behaviour around actions, see **TIMER_SYSTEM_FOR_STATUS_PHASE.md** and **COMPUTER_PLAYER_DELAY_SYSTEM.md**. For state flow and where actions live in game state, see **STATE_MANAGEMENT.md** and **DRAW_CARD_STATE_FLOW.md**.
