# Master Plan - Dutch Game Development

## Overview
This document tracks high-level development plans, todos, and architectural decisions for the Dutch game application.

---

## 🎯 Current Status

### Completed
- ✅ Practice mode implementation with player ID to sessionId refactoring
- ✅ Room/game creation and joining logic migrated from Python to Dart backend
- ✅ TTL management for rooms implemented in Dart backend
- ✅ Game state management integrated in Dart backend
- ✅ Player ID validation patterns updated for practice mode
- ✅ Remove WebSocket init/connect snackbars from game play screen; replaced with Logger calls behind `if (LOGGING_SWITCH)` (see `Documentation/flutter_base_05/LOGGING_SYSTEM.md`)
- ✅ Center my hand cards – hand row centered in its area (unified_game_board_widget.dart: Align + Wrap with WrapAlignment.center and leading spacer)
- ✅ Collection stack – darker top shadow and 10% stack offset (card_dimensions.dart STACK_OFFSET_PERCENTAGE = 0.10; unified_game_board_widget collection stack Container with boxShadow)
- ✅ Peek/selection overlay – same border radius as cards (flash overlay uses CardDimensions.calculateBorderRadius; selection overlay in CardWidget already matched)
- ✅ App bar logo – Home and Game play screens show `assets/images/logo.png` at full app bar height (BaseScreen.useLogoInAppBar, kAppBarLogoAsset in screen_base.dart); Lobby shows "Game Lobby" text
- ✅ Complete initial peek logic – flow from initial peek to game start (all players done / timeout) in dutch_game_round.dart
- ✅ Initial peek UI – peeked card data visible for at least 5 seconds (local state + timer in unified_game_board_widget / MyHand)
- ✅ Unify full-data card display with opponents-style UI (rank/suit only; special-card backgrounds)
- ✅ Queen peek: clear cardsToPeek when phase ends (timer expiry, flow advance, or explicit close)
- ✅ CPU Queen peek rule: peek at opponent when all own cards are known (peek_opponent_when_all_own_known in getQueenPeekDecision)
- ✅ Jack swap validation fixes: validate cards exist in hand before decision; filter by current hand after same-rank play (no picking discarded cards)
- ✅ **App bar feature slot**: optional GlobalKey for parent access (e.g. coin stream target)
- ✅ **Winner celebration**: confetti (3s) on game end when current user wins; close button navigates to lobby
- ✅ **Coin stream**: popup to app bar coins slot (post-match coin animation)
- ✅ **Account screen email**: show actual email (profile API returns plain email from JWT; account screen fallback from SharedPreferences when state has det_)
- ✅ **WebSocket auth timeout**: 10s wait + single retry via emitAuthenticate() in ensureWebSocketReady
- ✅ **Current rooms panel**: removed from lobby screen
- ✅ **Opponents columns spacing**: layout fixed when match pot image is visible (unified_game_board_widget / opponent widgets)
- ✅ **Home screen feature widget sizes**: text area and widget dimensions consistent (home feature components)
- ✅ **Same rank timer UI alignment**: UI timer duration aligned with game logic (timerConfig / dutch_game_round)
- ✅ **Clear game state when switching matches**: centralized cleanup in start_match, leave, mode switch (game_event_coordinator, dutch_event_handler_callbacks, dutch_game_state_updater; Flutter + Dart backend)
- ✅ **Room management**: get_public_rooms endpoint (match Python backend), user_joined_rooms event, room access control (allowed_users, allowed_roles)
- ✅ **Complete instructions logic**: UI for show/hide instructions from showInstructions in practice mode; timer behavior aligned with instructions visibility
- ✅ **Jack swap AI** (design and YAML in place; **currently shortcut**): YAML-driven rules designed (priority order: collection_three_swap, one_card_player_priority, lowest_opponent_higher_own, random_except_own, random_two_players, skip); doc `COMP_PLAYER_JACK_SWAP.md`. In code, `getJackSwapDecision()` now skips YAML parsing and returns `use: false` with log "jack decision not yet implemented" — see **Top Priority** for restoring full logic.
- ✅ **Queen peek AI**: Rule 2 (peek_random_other_player) execution probability aligned with Rule 1 (Expert 100%, Hard 95%, Medium 70%, Easy 50%)
- ✅ **Room TTL**: Configurable `WS_ROOM_TTL` (default 180s) and `WS_ROOM_TTL_PERIODIC_TIMER` (default 60s); TTL extended on create (first join) and on each join; periodic cleanup closes expired rooms with reason `ttl_expired`; logging in room_manager (LOGGING_SWITCH). Done and tested.

### In Progress

_(No items currently.)_

---

## 📋 TODO

### Top Priority

- [ ] **Jack swap computer logic – currently shortcut (implement full YAML-based decision)**
  - **Current shortcut (in place):** In `getJackSwapDecision()` (both Flutter and Dart backend `computer_player_factory.dart`), **YAML parsing is skipped**. Right after the "BEFORE YAML PARSING" log and the miss-chance check, we:
    - Add a note: `// NOTE: Jack decision YAML parsing is temporarily disabled - not yet implemented.`
    - Log (under `LOGGING_SWITCH`): `Dutch: jack decision not yet implemented`
    - Return immediately with `use: false`, `reasoning: 'jack decision not yet implemented'`, and the usual `action`, `delay_seconds`, `difficulty`. No card IDs or player IDs are chosen; the CPU never executes a swap.
  - **Effect:** Computer players with a Jack never perform a swap; the timer runs and the turn advances without a swap. All existing methods (e.g. `_prepareSpecialPlayGameData`, `_evaluateSpecialPlayRules`, `getEventConfig('jack_swap')`) remain in the codebase but are not called for the jack decision path.
  - **Intended full logic:** When implemented, the computer should use the YAML-driven rules (see `Documentation/Dutch_game/COMP_PLAYER_JACK_SWAP.md` and `computer_player_config.yaml` `jack_swap.strategy_rules`) to decide whether to swap (`use: true/false`) and, if so, which two card **indexes** and players. **The new jack swap system will handle swaps by index only (hand index per player), not by card IDs** — so the decision and execution should use e.g. `first_player_id` + `first_card_index`, `second_player_id` + `second_card_index`, and the backend/round logic should resolve cards in hand via index (or existing known_cards handIndex fallback) rather than by cardId. Restore the code that loads `jack_swap` config, prepares game data, evaluates `_evaluateSpecialPlayRules`, and returns the merged decision using indexes (and player IDs) only.

- [ ] **Review same rank plays – move to index-based handling (no card IDs)**
  - Same as jack swap direction: **same rank plays should work with hand index only, not card IDs**. Review the full same-rank flow (decision in computer player factory, event payload, round/coordinator handling, known_cards updates) and refactor so that the chosen card is identified by **player_id + card_index** (hand index), and the backend resolves the card in hand by index (or known_cards handIndex fallback). Align with the index-only approach used for the new jack swap system.

### High Priority

_(No high-priority items currently.)_

### Medium Priority

#### UI/Visual Issues
- [x] **Fix opponents columns spacing causing vertical layout issues when match pot image is showing (Dart backend version)** (Done)
  - **Issue**: Opponents panel columns have spacing issues that cause vertical layout problems when the match pot image is displayed
  - **Current Behavior**: Layout breaks or overlaps when match pot image is visible
  - **Expected Behavior**: Opponents columns should maintain proper spacing and layout regardless of match pot image visibility
  - **Location**: Flutter UI components for opponents panel (likely in `unified_game_board_widget.dart` or related opponent display widgets)
  - **Impact**: User experience - layout issues affect game playability and visual consistency
- [x] **Fix home screen feature widget sizes including the text area** (Done)
  - **Issue**: Home screen feature widgets (e.g. Dutch game entry, practice, etc.) have sizing issues; the text area and overall widget dimensions need adjustment
  - **Expected Behavior**: Feature widget sizes should be consistent and appropriate; text area should fit content and scale correctly
  - **Location**: Flutter home screen – feature/widget components that display game options or feature tiles (e.g. Dutch game card, practice mode entry)
  - **Impact**: Better home screen layout and readability
- [ ] **Table side borders: % based on table dimensions**
  - **Issue**: Table side borders use fixed values; they should scale with the table
  - **Expected Behavior**: Table side borders (left/right, and any decorative borders) should be defined as a **percentage of the table dimensions** (e.g. width or height) so they scale correctly on different screen sizes
  - **Location**: Flutter game play table widget – border width/stroke (e.g. `unified_game_board_widget.dart` or game play screen table decoration)
  - **Impact**: Consistent visual proportions across devices and window sizes
  - **Done**: Outer border (dark brown/charcoal) is now 1% of table width, max 10px (`game_play_screen.dart`). Inner gradient border (20px margin, 6px width) remains fixed; can be made %-based later if desired.
- [x] **Same rank timer UI widget: verify alignment with same rank time** (Done)
  - **Issue**: The same rank timer shown in the UI may not match the actual same rank window duration used by game logic
  - **Expected Behavior**: The same rank timer UI widget should display a countdown (or elapsed time) that **aligns with the same rank time** configured in game logic (e.g. `_sameRankTimer` duration in `dutch_game_round.dart`)
  - **Verification**: Confirm the UI timer duration and the backend same-rank window duration use the same value (e.g. from `timerConfig` or a shared constant); ensure countdown start/end matches when the window opens and closes
  - **Location**: Flutter same rank timer widget (e.g. in `unified_game_board_widget.dart` or game play screen); game logic in `dutch_game_round.dart` (same rank timer duration)
  - **Impact**: User experience – players see an accurate representation of how long they have to play a same-rank card
- [x] **Jack swap animation: overlay on affected card indexes (like peeking) along with swap** (Done)
  - **Issue**: Jack swap animation should visually highlight the two cards being swapped (by card index / position) with an overlay on the affected card indexes, similar to the peek overlay, in addition to the swap animation.
  - **Current Behavior**: Swap animation may run without overlays on the source and target card positions.
  - **Expected Behavior**: During jack swap, show an overlay on the **affected card indexes** (the two cards being swapped) – e.g. same style as the peeking overlay – so it is clear which cards are involved, **along with** the swap animation.
  - **Location**: Flutter jack swap animation / overlay logic (e.g. `unified_game_board_widget.dart`, jack swap demonstration widget, or card animation/overlay layer); ensure overlay targets card indexes (or positions) for both swapped cards (my hand and opponent, or two opponents).
  - **Impact**: User experience – clearer feedback on which cards were swapped during the jack swap.
- [x] **Card back images: load on match start, not on first show** (Done)
  - **Issue**: Suit/card back images should be loaded when the match starts so they are ready when first displayed, instead of loading lazily on first show (which can cause delay or flash).
  - **Current Behavior**: Card back images (e.g. for hand, discard, draw pile) may load on first display, causing a brief delay or visible load when cards are first shown.
  - **Expected Behavior**: Preload card back image(s) (assets and/or server-backed image) **on match start** (e.g. when game state indicates match started or when entering game play for the match) so the first time cards are shown the back image is already in cache.
  - **Location**: Flutter – match/game start flow (e.g. game event handlers, game play screen init, or a dedicated preload step); CardWidget or card back image usage; ensure `precacheImage` or equivalent is called at match start for the relevant back image(s).
  - **Impact**: Smoother UX – no visible load or flash when card backs are first shown.
#### Room Management Features
- [x] Implement `get_public_rooms` endpoint (matching Python backend) (Done)
- [x] Implement `user_joined_rooms` event (list rooms user is in) (Done)
- [x] Add room access control (`allowed_users`, `allowed_roles` lists) (Done)

#### Game Features
- [x] **Properly clear game maps and game-related state when switching from one match to another** (Done)
  - **Issue**: When starting a new match, old game data may persist in game maps and state, causing conflicts or incorrect behavior
  - **Current Behavior**: Game maps (`games` in state manager) and game-related state may retain data from previous matches when starting a new game
  - **Expected Behavior**: All game maps and game-related state should be completely cleared before starting a new match to ensure clean state
  - **State to Clear**:
    - `games` map in state manager (remove all previous game entries)
    - `currentGameId` and `currentRoomId` (reset to null/empty)
    - Game state slices: `myHandCards`, `discardPile`, `drawPile`, `opponentsPanel`, `centerBoard`
    - Game-related identifiers: `roundNumber`, `gamePhase`, `roundStatus`, `currentPlayer`
    - Player state: `playerStatus`, `myScore`, `isMyTurn`, `myDrawnCard`
    - Messages and turn events: `messages`, `turn_events`
    - Animation data: any cached animation state or position tracking data
    - Computer player factory state (if any cached state exists)
  - **When to Clear**:
    - Before starting a new match (`start_match` event handler)
    - When leaving/ending a match
    - When switching between practice and multiplayer modes
    - On explicit game cleanup/exit actions
  - **Location**: 
    - `flutter_base_05/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart` - `_handleStartMatch()` method (clear before new match)
    - `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart` - Match start/end handlers
    - `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart` - State clearing utilities
    - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart` - Same for Dart backend
  - **Implementation**:
    - Create centralized `clearAllGameState()` function that clears all game-related state
    - Call this function at the start of `_handleStartMatch()` before initializing new game
    - Ensure cleanup happens in both Flutter and Dart backend versions
    - Clear both state manager state and any in-memory game maps/registries
    - Verify no stale references remain after cleanup
  - **Impact**: Game integrity and reliability - prevents state conflicts between matches, ensures each new match starts with clean state
- [x] **Investigate joining rooms/games: log full state and WS events, then fix current games widget** (Done)
  - **Done**: Join/leave flow investigated; current-games list in lobby stays in sync when joining/leaving rooms and games (state + WS events aligned).
  - **Issue** (historical): Need to see every state key and WebSocket event affected when joining rooms/games so we can correctly add/clear current games in the lobby widget.
  - **Action** (completed):
    1. **Enable logging** per `.cursor/rules/enable-logging-switch.mdc`: set `LOGGING_SWITCH = false` (or equivalent) in the relevant Flutter/Dart and backend files for join flow, state updates, and WS events.
    2. **Log complete state** on join-related paths: when joining a room, when joining/entering a game, log the full state (all keys) before and after so we know exactly which keys are set/cleared.
    3. **Log WebSocket events** for join flow: log every WS message (event type and payload) sent/received around join room, join game, and any related state pushes.
    4. **Document** every state key that is read/written by the join flow (from logs).
    5. **Fix current games widget** in lobby: use that list of keys to properly add games when joining and clear/update when leaving or when list changes (so the current games widget shows the correct list and stays in sync).
  - **Location**: 
    - Join flow: lobby screens, room/game join handlers, WebSocket client, state manager updates (Flutter and backend as needed).
    - Lobby widget: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/current_games_widget.dart`.
  - **Impact**: Reliable lobby UX – current games list reflects actual joined games and is cleared/updated correctly; also gives a clear map of state for future fixes (e.g. clear on match switch).
- [x] **Complete instructions logic** (Done)
  - **Status**: Partially implemented - `showInstructions` flag is stored and passed through, timer logic checks it
  - **Current State**: `showInstructions` is stored in game state, timer logic respects it (timers disabled when `showInstructions == true`), value is passed from practice widget to game logic
  - **Needs**: Complete UI implementation to show/hide instructions based on flag, ensure instructions are displayed correctly in practice mode, verify timer behavior matches instructions visibility
  - **Location**: Flutter UI components (practice match widget, game play screen), timer logic in `dutch_game_round.dart`
  - **Impact**: User experience - players need clear instructions in practice mode
- [x] **Fine-tune computer Jack swap decisions: avoid frequent self-hand swaps** (Done)
  - **Issue**: Computer players are swapping cards from their own hands too often; same-hand swaps should be rare
  - **Expected Behavior**: Jack swap should predominantly swap cards **between different players**
  - **Done**: YAML rules and selection logic updated: `random_except_own` and `random_two_players` always choose cards from different players; new rules (collection_three_swap, one_card_player_priority) target other players only; `COMP_PLAYER_JACK_SWAP.md` documents all options. Flutter + Dart backend.
  - **Location**: `computer_player_factory.dart`, `computer_player_config.yaml` (Flutter assets + Dart backend)
- [ ] **Known cards: store hand index and use as fallback for jack swap / same-rank resolution**
  - **Intent**: Probabilistic known_cards updates (remember/forget) are intended; when the AI "forgets," a card can still appear in known_cards even though it was already played or swapped. Resolution should still succeed by falling back to the card at the **saved hand index** for that known card.
  - **1. Known_cards structure**
    - In each player's `known_cards` (per tracked player / per card), store **hand index** in addition to card id and player id: the index in that player's hand when the card was recorded (e.g. when added to known_cards on play, same-rank, jack_swap, queen_peek, or initial peek).
    - Ensure every place that **writes** to known_cards (adds or updates an entry) also records the current hand index for that card at that moment (e.g. `updateKnownCards` call sites, and any logic that builds known_cards on deal/peek).
  - **2. Jack swap resolution**
    - When resolving which card to swap (first card and second card): **first** try to find the card in the player's hand by **card id** (current logic). **If not found** (e.g. card was swapped/played but still in known_cards due to forget): resolve the card by **hand index** from the known_cards entry for that card id (use the saved index for that player) and select the card currently at that index in that player's hand.
    - Apply this in both places that perform jack swap validation and hand lookup: Flutter and Dart backend `dutch_game_round.dart` (e.g. `handleJackSwap` / jack swap handling).
  - **3. Same-rank play resolution**
    - When resolving which card was played for a same-rank play: **first** try to find the card in the player's hand by **card id**. **If not found**: resolve by **hand index** from known_cards for that card id (saved index for that player) and use the card currently at that index in that player's hand.
    - Apply in same-rank play handling in both Flutter and Dart backend `dutch_game_round.dart`.
  - **4. Where to pass/store hand index**
    - **updateKnownCards** (and any helpers like `_processPlayCardUpdate`, `_processJackSwapUpdate`, `_processQueenPeekUpdate`): when adding or moving cards in known_cards, accept and store hand index (e.g. for the acting player's card at play/same-rank, and for both cards in jack_swap). Callers must pass the hand index(es) at the time of the action.
    - **Initial deal / initial peek**: when populating known_cards for the two cards each player peeked, store the hand indices of those cards.
    - **Queen peek**: when recording the peeked card in known_cards, store its hand index in the target player's hand.
  - **5. Scope**
    - **Flutter**: `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` (known_cards structure, updateKnownCards and processors, handleJackSwap card resolution, same-rank card resolution).
    - **Dart backend**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` (same changes).
    - **Computer player factory**: no change to strategy output (still proposes card ids); resolution fallback is entirely in round logic when finding the physical card in hand by id vs by index.
  - **6. Wrong same-rank play selection**
    - **Current behavior**: When the CPU "plays wrong" (wrong_rank_probability), the wrong card is chosen by: filtering known_cards to cards with rank ≠ discard rank, then **picking one at random** from that list.
    - **Change**: Remove the random selection. **Known_cards will effectively handle the wrong same-rank play**: the card to attempt is determined from known_cards in a deterministic or known_cards-driven way (no random among wrong cards). **Resolution** (same as jack swap): when executing the wrong same-rank play, **first** attempt to find the card in hand by **card id**; **if not in hand**, play the card at the **index attached to that card in known_cards** (saved hand index for that card).
  - **Impact**: Jack swaps and same-rank plays that use a "forgotten" card (still in known_cards but no longer at that card id in hand) will succeed by using the card at the stored hand index, preserving intended forget behavior while keeping actions valid. Wrong same-rank play will be consistent with known_cards and not depend on random choice among wrong cards.
#### Match end and winners popup
- [x] **Replace all hand cards with full data before showing winners popup** (Done)
  - **Issue**: At match end, hands still contain ID-only card data, so the UI shows placeholders/backs instead of actual cards when the winners popup is shown
  - **Current Behavior**: Game state broadcasts final state with ID-only cards in players' hands (and possibly discard/draw); winners popup or end-of-match view shows cards without rank/suit/points
  - **Expected Behavior**: **Before** showing the winners popup, replace every card in every player's hand (and any other visible piles if needed) from ID-only to **full card data** (rank, suit, points) so the UI can display them
  - **Implementation**: When determining match end (e.g. four-of-a-kind or Dutch round complete), resolve all card IDs in all hands (and discard/draw if shown) to full card data (from deck definition or stored full data), update game state with this "reveal" state, then trigger winners popup
  - **Location**: Game round or coordinator – match-end flow (e.g. `dutch_game_round.dart`, `game_event_coordinator.dart`); ensure both Flutter and Dart backend apply the same reveal before emitting final state / opening popup
  - **Impact**: Players can see everyone's final hands and card values in the winners screen
- [x] **Winners popup: all 4 players in order with cards, values, and total points** (Done)
  - **Issue**: Winners popup should show a full summary of all players, not just the winner
  - **Current Behavior**: Popup may show only winner or a limited subset
  - **Expected Behavior**: Winners popup must contain the **list of all 4 players in order**: **winner first**, then the **rest from least points to most** (ascending by points). For each player show: **their cards**, **each card's value** (points), and **total points**
  - **Implementation**: Build ordered list: [winner, then remaining 3 sorted by points ascending]; for each player render name, list of cards (with rank/suit and points per card), and total points
  - **Location**: Flutter UI – winners popup / match end dialog (e.g. in game play screen or unified game board); game state or coordinator may need to provide final player order and resolved card data (see item above)
  - **Impact**: Clear, fair summary of match result and final hands for all players
- [x] **Game end popup: winner celebration and close → lobby or stats** (Done)
  - **Issue**: Game end popup should celebrate when the current user is the winner and the close action should lead somewhere meaningful (lobby or updated stats).
  - **Expected Behavior**:
    1. **Winner check**: In the game end popup modal, detect if the current user is the winner (e.g. compare winner id with current user/session id).
    2. **Celebratory animations**: If the user is the winner, add celebratory animations (Flutter ideally – e.g. confetti, glow, short sequence). Non-winners see the standard popup without celebration.
    3. **Close button**: The close button should **navigate to the lobby screen** or open **another modal/screen showing the user's new stats** (e.g. updated rank, level, coins, match summary).
  - **Location**: Flutter – game end / winners popup modal (game play screen or unified game board); navigation to lobby or stats screen/modal.
  - **Impact**: Better UX for match end – clear feedback for winner and a clear next step (lobby or stats) after closing.
- [ ] **Practice mode: replace CPU player names with "Player"**
  - **Issue**: In practice mode, opponent names are shown as "CPU" (or similar); should be more human-readable.
  - **Expected Behavior**: Display names for practice opponents as "Player" (e.g. "Player 1", "Player 2", "Player 3") instead of "CPU" or generic CPU labels.
  - **Location**: Flutter – practice mode player naming (e.g. computer player factory, opponent display, game state display names); ensure display name is set when creating/broadcasting practice players.
  - **Impact**: Clearer, friendlier practice UX.
- [ ] **Winning modal: replace trophy icon with image, position above modal**
  - **Issue**: Winner celebration currently uses an `Icons.emoji_events` trophy icon; should use an actual image asset and be placed just above the modal.
  - **Expected Behavior**: Use a real image (e.g. trophy/medal asset) for the winner celebration instead of the Material icon; position the image **just above** the modal (aligned above the modal card, not overlapping).
  - **Location**: Flutter – `messages_widget.dart` `_WinnerCelebrationOverlay` (trophy widget); add image asset and adjust positioning/layout.
  - **Impact**: More polished, branded winner experience.
- [ ] **Winning modal: replace generated sparkles with template or GIF**
  - **Issue**: Screen sparkles are currently drawn with CustomPainter (dots); should use a template image or GIF for a consistent, reusable effect.
  - **Expected Behavior**: Replace the programmatic sparkle particles with a **template image** or **GIF** (e.g. sparkle overlay asset) that plays for a few seconds. Asset should be minimal and match the celebration theme.
  - **Location**: Flutter – `messages_widget.dart` `_WinnerCelebrationOverlay` / `_SparklePainter`; replace with `Image` or GIF-capable widget (e.g. asset or network image, or package for GIF playback).
  - **Impact**: Consistent, design-controlled celebration effect; easier to theme or swap.
- [ ] **Game end modal close: navigate to account screen instead of lobby**
  - **Issue**: After closing the game end (winners) modal, the app currently navigates to the lobby; should navigate to the **account screen** instead.
  - **Expected Behavior**: When the user closes the game end modal (e.g. "Close" or back), **navigate to the account screen** (e.g. `/account` or equivalent route) instead of `/dutch/lobby`.
  - **Location**: Flutter – `messages_widget.dart` `_closeMessage` or equivalent (where navigation to lobby is triggered on game end); change target route to account screen.
  - **Impact**: Post-game flow directs users to account/stats and encourages login/registration.
- [ ] **Account screen: collapsible login/register tabs and guest warning**
  - **Issue**: Account screen should present login/register in collapsible tabs and warn guest/non-logged-in users about losing winning data.
  - **Expected Behavior**:
    1. **Collapsible tabs**: Show **Login** and **Register** (or equivalent) in **collapsible sections/tabs** (e.g. expandable panels) so the screen is cleaner and users can expand only what they need.
    2. **Guest / non-logged-in message**: For **guest accounts** or **non-logged-in users**, display a clear message that they should **switch from guest to a regular account** (or **register**) so they **do not lose winning data** (e.g. coins, progress, stats).
  - **Location**: Flutter – account screen (e.g. account module or profile screen); add collapsible UI for login/reg and a banner or inline message for guest/unauthenticated state.
  - **Impact**: Clearer account UX and reduced risk of users losing progress by staying on guest.

### Low Priority

#### Infrastructure
- [ ] Add Redis persistence for rooms (if needed for production)
- [ ] Implement user presence tracking
- [ ] Add session data persistence
- [ ] Improve room ID generation (use UUID instead of timestamp)

#### Testing & Documentation
- [ ] Add unit tests for room management
- [ ] Add integration tests for game flow
- [ ] Document WebSocket event protocol
- [ ] Create API documentation

---

## 🏗️ Architecture Decisions

### Current Architecture

#### Backend Split
- **Python Backend** (`python_base_04`):
  - Handles authentication (JWT validation)
  - Provides REST API endpoints
  - Uses Redis for persistence (if needed)
  - Port: 5001

- **Dart Backend** (`dart_bkend_base_01`):
  - Handles WebSocket connections
  - Manages game logic and state
  - In-memory storage (no Redis)
  - Port: 8080 (configurable)

#### Communication Flow
```
Flutter Client
    ↓ (WebSocket)
Dart Backend (Game Logic)
    ↓ (HTTP API - JWT validation only)
Python Backend (Auth)
```

### Key Design Decisions

1. **No Redis in Dart Backend**: 
   - Rooms and game state are in-memory only
   - Rooms lost on server restart (acceptable for current use case)
   - TTL implemented in-memory with periodic cleanup

2. **SessionId as Player ID**:
   - In multiplayer: WebSocket sessionId is used as player ID
   - In practice mode: `practice_session_<userId>` format
   - More reliable than userId for WebSocket connections

3. **Optional Authentication**:
   - Currently, clients can connect without JWT
   - Authentication happens when token is provided
   - **TODO**: Enforce authentication for game events

---

## 🔧 Technical Debt

1. **Authentication Enforcement**: WebSocket events should require authentication
2. **Error Handling**: Some game events lack comprehensive error handling
3. **Room Discovery**: Missing `get_public_rooms` functionality
4. **Testing**: Limited test coverage for game logic

---

## 📝 Notes

### Room TTL Implementation (done)
- **WS_ROOM_TTL**: default 180s (3 min); configurable via env or `secrets/ws_room_ttl`
- **WS_ROOM_TTL_PERIODIC_TIMER**: default 60s (check interval); configurable via env or `secrets/ws_room_ttl_periodic_timer`
- TTL set/extended on room create (first join) and on each join via `reinstateRoomTtl`
- Periodic timer runs every N seconds, closes rooms where `now > ttlExpiresAt` with reason `'ttl_expired'`
- Empty rooms are closed on last leave (reason `'empty'`) before TTL; TTL expiry applies when room still has sessions but no activity for TTL period

### Player ID System
- Multiplayer: `sessionId` (WebSocket session ID)
- Practice mode: `practice_session_<userId>`
- Validation patterns updated to accept both formats

### Queen Peek Timer
- **Issue**: Queen peek timer should stop after the player has peeked at a card
- **Current Behavior**: Timer may continue running even after peek action is completed
- **Expected Behavior**: Timer should be cancelled/stopped immediately when player completes the peek action
- **Location**: Timer logic in game round/event handlers, likely in `dutch_game_round.dart` or related timer management code
- **Impact**: User experience - prevents confusion and ensures timer accurately reflects available time
- **Related**: When the user stays past the timer (or flow advances), **cardsToPeek state is cleared** so the UI stops showing peeked cards (done).

### Game State Cleanup on Navigation
- **Issue**: Game data persists in state and game maps when navigating away from game play screen
- **Current Behavior**: Game state, games map, and related data remain in memory when user navigates to other screens
- **Expected Behavior**: All game data should be completely cleared from state and all game maps when leaving the game play screen
- **Location**: Navigation logic, game play screen lifecycle (dispose/onExit), state management in `dutch_event_handler_callbacks.dart` and `dutch_game_state_updater.dart`
- **Impact**: Memory management and state consistency - prevents stale game data from affecting new games or causing memory leaks
- **Action Items**:
  - Clear `games` map in state manager
  - Clear `currentGameId`, `currentRoomId`, and related game identifiers
  - Clear widget-specific state slices (myHandCards, discardPile, etc.)
  - Clear messages state (including modal state)
  - Clear turn_events and animation data
  - Ensure cleanup happens on both explicit navigation and screen disposal

### Penalty Card System
- **Issue**: Penalty card system needs verification - playing a penalty card as a same rank to a different turn didn't work
- **Status**: 🔄 **Needs Investigation** - System may not be handling penalty cards correctly in same rank play scenarios
- **Current Behavior**: Attempted to play a penalty card as a same rank play to a different turn, but the action didn't work
- **Expected Behavior**: Penalty cards should be playable as same rank plays when appropriate
- **Location**: 
  - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` - Same rank play logic
  - Penalty card validation and handling logic
- **Impact**: Game functionality - penalty cards are a core game mechanic and must work correctly
- **Action Items**:
  - Verify penalty card validation logic in same rank play
  - Check if penalty cards are being properly identified and allowed in same rank scenarios
  - Test penalty card play across different turn scenarios
  - Ensure penalty cards follow correct game rules for same rank plays

### Drawn Card Logic in Opponents Panel
- **Issue**: Opponents were seeing full drawn card data (rank/suit) when they should only see ID-only format
- **Status**: ✅ **Almost Fixed** - Sanitization logic implemented, needs final verification
- **Current Behavior**: 
  - Fixed: Sanitization function `_sanitizeDrawnCardsInGamesMap()` now converts full card data to ID-only format before broadcasting
  - Implemented in both Flutter and Dart backend versions of `dutch_game_round.dart`
  - Sanitization added before all critical `onGameStateChanged()` broadcasts (play_card, same_rank_play, jack_swap, collect_from_discard, etc.)
- **Expected Behavior**: 
  - Opponents should only see ID-only format (`{'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}`) for drawn cards
  - Only the drawing player should see full card data
  - **CRITICAL**: When sanitizing, preserve the card ID in ID-only format - do NOT completely remove the `drawnCard` property, especially during play actions since the draw data would still be there
- **Location**: 
  - `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
  - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
  - Helper function: `_sanitizeDrawnCardsInGamesMap()` (lines ~40-76 in both files)
- **Impact**: Game integrity and fairness - prevents opponents from seeing sensitive card information
- **Remaining Action Items**:
  - ✅ Verify sanitization preserves card ID (ID-only format) rather than removing drawnCard completely
  - ✅ Test that during play actions, drawnCard data is properly sanitized to ID-only (not removed)
  - Test edge cases: card replacement, card play, turn transitions
  - Verify with logging that sanitization is working correctly in all scenarios

### Animation System Refactor
- **Issue**: Current animation system relies on position tracking that happens asynchronously during widget rebuilds, which can cause timing issues and race conditions
- **Status**: 🔄 **Planned** - Major refactor needed
- **Current Behavior**: 
  - Animations are triggered based on position changes detected during widget rebuilds
  - Position tracking happens in post-frame callbacks, which can be delayed
  - Game logic continues immediately after state updates, potentially before animations complete
  - Race conditions can occur when cards are played before their positions are properly tracked
- **Expected Behavior**: 
  - Implement a "pause for animation" mechanism during game logic execution
  - Game logic should pause after state updates that require animations
  - System should:
    1. Update game state (e.g., card played, card drawn)
    2. Wait for position tracker to update with proper card positions
    3. Trigger and wait for animation to complete
    4. Continue with game logic (e.g., move to next player, check game end conditions)
  - This ensures animations have proper timing and all positions are tracked before animations start
- **Implementation Approach**:
  - Add animation completion callbacks/promises to game logic flow
  - Create animation queue system that game logic can wait on
  - Modify game event handlers to pause execution until animations complete
  - Ensure position tracking completes before animation starts
  - Handle edge cases (e.g., multiple simultaneous animations, animation failures)
- **Alternative Animation Approach - Animation ID System**:
  - **Concept**: Declarative animation system using shared animation IDs
  - **How it works**:
    1. During gameplay, affected objects are assigned an `animationId` (e.g., draw pile gets `animationId: "draw_123"`)
    2. When a second object receives the same `animationId` (e.g., card in hand gets `animationId: "draw_123"`), the system triggers a predefined animation
    3. Animation type is determined by the ID pattern or explicit animation type in state
    4. Card data can be passed as needed for the animation
  - **Example Flow**:
    - Draw action: Draw pile gets `animationId: "draw_card_abc123"`, card appears in hand with same `animationId: "draw_card_abc123"`
    - System detects matching IDs and triggers draw animation from draw pile position to hand position
    - After animation completes, animation IDs are cleared from both objects
  - **Benefits**:
    - More declarative - game logic sets animation IDs, animation system handles the rest
    - Eliminates need for complex position tracking and comparison
    - Clearer separation of concerns (game logic vs animation system)
    - Easier to handle multiple simultaneous animations (each has unique ID)
    - Can work with "pause for animation" mechanism - game logic sets IDs, waits for animation completion
  - **Implementation Considerations**:
    - Animation IDs should be unique per animation instance (e.g., timestamp-based or UUID)
    - Animation type can be inferred from ID pattern or stored separately in state
    - Objects need to store animation ID in their state/data structure
    - Animation system listens for matching IDs and triggers appropriate animation
    - IDs should be cleared after animation completes or after timeout
  - **Location**: 
    - Game state objects (cards, piles) need `animationId` field
    - Animation system needs ID matching logic
    - Game logic sets animation IDs when actions occur
- **Immediate Animation from User Actions**:
  - **Concept**: For animations triggered by user actions (e.g., playing a card, drawing a card), get positions immediately from the user interaction instead of waiting for state updates and position tracking
  - **How it works**:
    1. User performs action (e.g., taps card to play it)
    2. Widget immediately knows:
       - Source position: Card's current position (from GlobalKey/RenderBox or tap location)
       - Target position: Destination position (e.g., discard pile position from tracker or known location)
       - Card data: Already available in widget
    3. Trigger animation immediately with known positions
    4. State update happens in parallel/after animation starts
    5. No need to wait for position tracking or state propagation
  - **Example Flow**:
    - User taps card in hand to play it
    - Widget gets card position from GlobalKey immediately
    - Widget gets discard pile position from CardPositionTracker (already tracked)
    - Widget triggers play animation immediately with both positions
    - Backend processes play action and updates state
    - Animation completes before or during state update
  - **Benefits**:
    - Instant visual feedback - animation starts immediately on user action
    - Eliminates delay from state update → widget rebuild → position tracking → animation trigger
    - Better user experience - feels more responsive
    - Reduces race conditions - animation uses known positions at action time
    - Works well with "pause for animation" - animation can start immediately, game logic waits for completion
  - **Implementation Considerations**:
    - Widget needs access to CardPositionTracker to get target positions
    - Source position available from card's GlobalKey/RenderBox
    - Card data already available in widget
    - Animation can be triggered directly from widget action handler
    - State update can happen in parallel (doesn't block animation)
    - Need to handle cases where target position isn't available yet (fallback to state-based animation)
  - **Location**: 
    - Widget action handlers (e.g., `_handleCardSelection` in MyHandWidget)
    - CardPositionTracker for getting target positions
    - CardAnimationLayer for immediate animation triggering
- **Location**: 
  - `flutter_base_05/lib/modules/dutch_game/screens/game_play/card_position_tracker.dart`
  - `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/card_animation_layer.dart`
  - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` (game logic coordination)
  - `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart` (event handling)
- **Impact**: 
  - Improves animation reliability and timing
  - Eliminates race conditions with position tracking
  - Provides better visual feedback and smoother gameplay experience
  - Ensures game logic proceeds only after animations complete
  - Animation ID approach offers cleaner, more maintainable architecture
- **Related Documentation**: `Documentation/Dutch_game/ANIMATION_SYSTEM.md`

---

## 🚀 Future Enhancements

1. **Multi-server Support**: Redis-based room sharing across servers
2. **Game Replay**: Record and replay game sessions
3. **Spectator Mode**: Allow users to watch games
4. **Tournament System**: Organize and manage tournaments
5. **Analytics**: Track game statistics and player performance

---

## 📚 Related Documentation

- `Documentation/Dutch_game/ROOM_GAME_CREATION_COMPARISON.md` - Python vs Dart backend comparison
- `Documentation/Dutch_game/COMPLETE_STATE_STRUCTURE.md` - Game state structure
- `.cursor/rules/dutch-game-state-rules.mdc` - Game system rules

---

**Last Updated**: 2026-02-05 (Added: known_cards hand index + jack swap/same-rank fallback TODO)

