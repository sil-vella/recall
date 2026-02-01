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

### In Progress
- 🔄 Room TTL implementation (recently completed, needs testing)

---

## 📋 TODO

### High Priority

_(No high-priority items currently.)_

### Medium Priority

#### UI/Visual Issues
- [ ] **Fix opponents columns spacing causing vertical layout issues when match pot image is showing (Dart backend version)**
  - **Issue**: Opponents panel columns have spacing issues that cause vertical layout problems when the match pot image is displayed
  - **Current Behavior**: Layout breaks or overlaps when match pot image is visible
  - **Expected Behavior**: Opponents columns should maintain proper spacing and layout regardless of match pot image visibility
  - **Location**: Flutter UI components for opponents panel (likely in `unified_game_board_widget.dart` or related opponent display widgets)
  - **Impact**: User experience - layout issues affect game playability and visual consistency
- [ ] **Highlight borders for peeking and selected cards: remove border radius**
  - **Issue**: Highlight borders used for peeking (e.g. queen peek, initial peek) and for selected cards use rounded corners; they should be sharp (no border radius)
  - **Current Behavior**: Peek and selection highlight borders are drawn with border radius
  - **Expected Behavior**: These highlights should be drawn **without border radius** (rectangular borders only)
  - **Location**: Flutter UI where peek highlights and selection highlights are built (e.g. flashCard overlay, card selection decoration in hand/discard widgets)
  - **Impact**: Visual consistency and clearer emphasis on peek/selection state
- [ ] **Unify full-data card display with opponents-style UI (rank/suit only; special-card backgrounds)**
  - **Issue**: Cards that show full data (e.g. in hand, discard pile) currently use full "play card" style; they should match the opponents section style: rank and suit only, with special-card backgrounds
  - **Current Behavior**: My hand and discard show full playing-card artwork/style; opponents section shows compact rank/suit (and special backgrounds for face cards)
  - **Expected Behavior**: All cards that reveal full data should follow the **same UI as the opponents section**: display **only rank and suit** (no full play-card artwork). Special cards (King, Jack, Queen, Joker) should have a **background relative to that rank** (e.g. distinct background per rank type)
  - **Scope**: My hand, discard pile, and any other areas that show full card data
  - **Location**: Flutter card display widgets for hand, discard, and shared card component used by opponents section; ensure one consistent "compact full-data" style
  - **Impact**: Consistent visual language across the board; clearer distinction between hidden (back) and revealed (rank/suit + special background) cards
- [ ] **Collection cards stack: darker top shadow and 10% offset**
  - **Issue**: Collection cards stack (stacked widget) needs a slightly darker shadow at the top and a smaller vertical offset between cards
  - **Current Behavior**: Stack uses `CardDimensions.STACK_OFFSET_PERCENTAGE` (15%) for offset; shadow may be too light
  - **Expected Behavior**: Make the shadow at the top of the collection cards widget **a bit darker**; **decrease the stack offset to 10%** (of card height)
  - **Location**: `flutter_base_05/lib/modules/dutch_game/utils/card_dimensions.dart` – `STACK_OFFSET_PERCENTAGE` (change from 0.15 to 0.10); Flutter widget that draws the collection stack (unified_game_board_widget or related) – shadow styling for the stack
  - **Impact**: Clearer visual separation of stacked collection cards and more readable stack
- [ ] **Center my hand cards**
  - **Issue**: My hand cards should be centered in their container
  - **Expected Behavior**: The row/list of cards in the player's hand (my hand section) should be centered horizontally (and vertically if applicable) within the hand area
  - **Location**: Flutter UI for my hand – `unified_game_board_widget.dart` or related MyHandWidget / hand layout
  - **Impact**: Better visual balance and polish of the game board
- [ ] **Fix home screen feature widget sizes including the text area**
  - **Issue**: Home screen feature widgets (e.g. Dutch game entry, practice, etc.) have sizing issues; the text area and overall widget dimensions need adjustment
  - **Expected Behavior**: Feature widget sizes should be consistent and appropriate; text area should fit content and scale correctly
  - **Location**: Flutter home screen – feature/widget components that display game options or feature tiles (e.g. Dutch game card, practice mode entry)
  - **Impact**: Better home screen layout and readability
- [ ] **Remove the "failed to initialize websocket" snackbar error**
  - **Issue**: A snackbar shows "failed to initialize websocket" (or similar) to the user when WebSocket initialization fails
  - **Expected Behavior**: Remove or replace this snackbar so users are not shown this error (e.g. handle silently, use a less alarming message, or show only in debug)
  - **Location**: Flutter – WebSocket initialization/connection handling (likely in websocket manager, connection status, or game/lobby screens)
  - **Impact**: Avoid confusing or alarming users when WebSocket fails (e.g. in practice mode or before connection is needed)
- [ ] **Table side borders: % based on table dimensions**
  - **Issue**: Table side borders use fixed values; they should scale with the table
  - **Expected Behavior**: Table side borders (left/right, and any decorative borders) should be defined as a **percentage of the table dimensions** (e.g. width or height) so they scale correctly on different screen sizes
  - **Location**: Flutter game play table widget – border width/stroke (e.g. `unified_game_board_widget.dart` or game play screen table decoration)
  - **Impact**: Consistent visual proportions across devices and window sizes
  - **Done**: Outer border (dark brown/charcoal) is now 1% of table width, max 10px (`game_play_screen.dart`). Inner gradient border (20px margin, 6px width) remains fixed; can be made %-based later if desired.
- [ ] **Same rank timer UI widget: verify alignment with same rank time**
  - **Issue**: The same rank timer shown in the UI may not match the actual same rank window duration used by game logic
  - **Expected Behavior**: The same rank timer UI widget should display a countdown (or elapsed time) that **aligns with the same rank time** configured in game logic (e.g. `_sameRankTimer` duration in `dutch_game_round.dart`)
  - **Verification**: Confirm the UI timer duration and the backend same-rank window duration use the same value (e.g. from `timerConfig` or a shared constant); ensure countdown start/end matches when the window opens and closes
  - **Location**: Flutter same rank timer widget (e.g. in `unified_game_board_widget.dart` or game play screen); game logic in `dutch_game_round.dart` (same rank timer duration)
  - **Impact**: User experience – players see an accurate representation of how long they have to play a same-rank card
- [ ] **Jack swap animation: overlay on affected card indexes (like peeking) along with swap**
  - **Issue**: Jack swap animation should visually highlight the two cards being swapped (by card index / position) with an overlay on the affected card indexes, similar to the peek overlay, in addition to the swap animation.
  - **Current Behavior**: Swap animation may run without overlays on the source and target card positions.
  - **Expected Behavior**: During jack swap, show an overlay on the **affected card indexes** (the two cards being swapped) – e.g. same style as the peeking overlay – so it is clear which cards are involved, **along with** the swap animation.
  - **Location**: Flutter jack swap animation / overlay logic (e.g. `unified_game_board_widget.dart`, jack swap demonstration widget, or card animation/overlay layer); ensure overlay targets card indexes (or positions) for both swapped cards (my hand and opponent, or two opponents).
  - **Impact**: User experience – clearer feedback on which cards were swapped during the jack swap.
- [ ] **Card back images: load on match start, not on first show**
  - **Issue**: Suit/card back images should be loaded when the match starts so they are ready when first displayed, instead of loading lazily on first show (which can cause delay or flash).
  - **Current Behavior**: Card back images (e.g. for hand, discard, draw pile) may load on first display, causing a brief delay or visible load when cards are first shown.
  - **Expected Behavior**: Preload card back image(s) (assets and/or server-backed image) **on match start** (e.g. when game state indicates match started or when entering game play for the match) so the first time cards are shown the back image is already in cache.
  - **Location**: Flutter – match/game start flow (e.g. game event handlers, game play screen init, or a dedicated preload step); CardWidget or card back image usage; ensure `precacheImage` or equivalent is called at match start for the relevant back image(s).
  - **Impact**: Smoother UX – no visible load or flash when card backs are first shown.
- [ ] **Game play screen app bar: replace title with app logo**
  - **Issue**: Check if we have existing logic to replace the game play screen title in the app bar with the app logo.
  - **Action**: Verify whether the game play screen (or base screen / app bar) already supports or implements showing the app logo in the app bar instead of a text title; if so, document where; if not, add as enhancement.
  - **Expected Behavior**: Game play screen app bar shows the app logo (e.g. `Image.asset` or existing logo widget) instead of or in addition to the screen title.
  - **Location**: Flutter – game play screen (e.g. `game_play_screen.dart`), BaseScreen/app bar, or shared app bar / theme configuration.
  - **Impact**: Consistent branding and polish on the game play screen.

#### Room Management Features
- [ ] Implement `get_public_rooms` endpoint (matching Python backend)
- [ ] Implement `user_joined_rooms` event (list rooms user is in)
- [ ] Add room access control (`allowed_users`, `allowed_roles` lists)

#### Game Features
- [ ] Add comprehensive error handling for game events
- [ ] Implement game state persistence (optional, for recovery)
- [ ] Add game replay/logging system
- [ ] **Properly clear game maps and game-related state when switching from one match to another**
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
- [ ] **Complete initial peek logic**
  - **Status**: Partially implemented - initial peek phase exists but needs completion
  - **Current State**: Game enters `initial_peek` phase on match start, players can peek at 2 cards
  - **Needs**: Complete the flow from initial peek to game start, ensure all players complete peek before proceeding, handle timeout/auto-complete scenarios
  - **Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` and related event handlers
  - **Impact**: Core game feature - players must complete initial peek before game can start
- [ ] **Modify initial peek UI to persist selected card data for minimum 5 seconds**
  - **Issue**: When players peek at cards during initial peek phase, the card data (rank/suit) is cleared from state immediately after the peek action, causing the UI to hide the card information too quickly
  - **Current Behavior**: Card data is shown when peeked, but disappears as soon as the state is updated/cleared
  - **Expected Behavior**: Selected cards' data (rank/suit) should remain visible in the UI for at least 5 seconds, even if the game state is cleared or updated
  - **Implementation**:
    - Add local state management in the initial peek UI widget to track peeked cards with timestamps
    - When a card is peeked, store the card data locally with a timestamp
    - Display card data from local state if available, even if state has been cleared
    - Use a timer to clear local peek data after 5 seconds minimum
    - Ensure the 5-second minimum is enforced even if state updates occur during this period
  - **Location**: 
    - Flutter UI components for initial peek (likely in `MyHandWidget` or related card display widgets)
    - Initial peek event handlers in `dutch_game_round.dart` or `game_event_coordinator.dart`
  - **Impact**: User experience - ensures players have adequate time to view and remember their peeked cards before the information disappears
- [ ] **Complete instructions logic**
  - **Status**: Partially implemented - `showInstructions` flag is stored and passed through, timer logic checks it
  - **Current State**: `showInstructions` is stored in game state, timer logic respects it (timers disabled when `showInstructions == true`), value is passed from practice widget to game logic
  - **Needs**: Complete UI implementation to show/hide instructions based on flag, ensure instructions are displayed correctly in practice mode, verify timer behavior matches instructions visibility
  - **Location**: Flutter UI components (practice match widget, game play screen), timer logic in `dutch_game_round.dart`
  - **Impact**: User experience - players need clear instructions in practice mode
- [ ] **Fix CPU player Jack swap decision logic to validate cards exist in hand**
  - **Issue**: CPU players sometimes attempt Jack swaps with cards that are no longer in their hand
  - **Root Cause**: CPU decision logic uses `known_cards` (which may contain "forgotten" played cards due to difficulty-based remember probability), but by execution time the card has already been played and removed from hand
  - **Current Behavior**: Decision is made based on stale `known_cards` data, validation correctly catches invalid swaps but wastes decision attempts
  - **Solution**: Before making Jack swap decision, validate that selected cards actually exist in the player's current hand, not just in `known_cards`
  - **Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart` - `getJackSwapDecision()` and related selection methods
  - **Impact**: Improves CPU player decision accuracy, reduces failed swap attempts
- [ ] **Jack swap after same-rank play: computer picks cards already played (discarded)**
  - **Issue**: When a Jack is played as same-rank, it is moved to the discard pile; the special-card window then runs and the computer's Jack swap decision can choose that same Jack (or another card just played) for the swap. Those cards are no longer in any player's hand, so validation fails with "Invalid Jack swap - one or both cards not found in players' hands".
  - **Observed in logs**: CPU plays two Jacks in same-rank (diamonds, then hearts); for each Jack's special-card window the AI selects e.g. `card_..._23_...` (jack diamonds) and `card_..._52_...` (joker in opponent hand). The jack diamonds was already played and is in the discard, so the swap fails.
  - **Root Cause**: Jack swap decision uses card IDs / known_cards that reflect state before the same-rank play; by the time the special-card window runs, the played Jack(s) have been removed from hands.
  - **Expected Behavior**: Jack swap selection must use only cards that currently exist in players' hands (e.g. filter candidate cards by current hand contents, or re-read hand state at decision time in the special-card window).
  - **Location**: Same as above – `getJackSwapDecision()` and card selection in `computer_player_factory.dart` (and Flutter equivalent if present); ensure special-card window receives or reads current hand state after same-rank plays.
  - **Impact**: Eliminates failed Jack swap attempts and "Invalid Jack swap" errors when Jacks are played via same-rank.
- [ ] **Fine-tune computer Jack swap decisions: avoid frequent self-hand swaps**
  - **Issue**: Computer players are swapping cards from their own hands too often; same-hand swaps should be rare
  - **Current Behavior**: Jack swap decision logic allows or prefers swapping within the same player's hand, leading to frequent self-hand swaps
  - **Expected Behavior**: Jack swap should predominantly swap cards **between different players**; swapping two cards within the same hand should be infrequent (e.g. only when no beneficial cross-player swap exists)
  - **Implementation**: Adjust `getJackSwapDecision()` (and related selection logic) to strongly prefer cross-player swaps; deprioritize or restrict same-hand swaps (e.g. low probability, or only when hand size/strategy justifies it)
  - **Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart` (and Flutter equivalent if present) - Jack swap decision and card selection
  - **Impact**: More realistic and strategic computer play; Jack swap used for disruption across players rather than within own hand
- [ ] **Add computer player Queen peek decision rule: peek at opponent when all own cards are known**
  - **Issue**: Computer players need smarter Queen peek decision logic
  - **Current Behavior**: Computer players use existing rules (peek_own_unknown_cards, peek_random_other_player, skip_queen_peek)
  - **Expected Behavior**: If all cards in the computer player's own hand are known (no unknown cards), the computer should peek at an opponent's hand instead
  - **Implementation**: 
    - Add new decision rule: `peek_opponent_when_all_own_known`
    - Check if computer player has any unknown cards in their hand
    - If all cards are known, prioritize peeking at opponent's hand over skipping
    - This rule should have higher priority than `skip_queen_peek` but lower than `peek_own_unknown_cards`
  - **Location**: 
    - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart` - `getQueenPeekDecision()` method
    - YAML configuration for computer player strategies (if applicable)
  - **Impact**: Improves computer player AI - makes strategic use of Queen peek when own hand is fully known
- [ ] **Queen peek for user: clear cardsToPeek state when past timer (or when flow advances)**
  - **Issue**: When the human user is in queen peek and stays past the timer (or the flow advances by other logic), `cardsToPeek` state must be cleared at some point so the UI stops showing peeked cards and state stays consistent.
  - **Current Behavior**: Peeked card data is shown via `cardsToPeek` / `myCardsToPeek`; if the user does not complete an action and the timer expires (or flow moves on), the state may not be cleared.
  - **Expected Behavior**: Ensure that when the queen peek phase ends (timer expiry, flow advance, or explicit close), `cardsToPeek` (and `myCardsToPeek` where applicable) are cleared for the peeking player so the UI no longer shows peeked cards and state is clean for the next phase.
  - **Implementation**: Identify all exit paths from queen peek (timer expiry, user action, flow advance); in each path, clear `player.cardsToPeek` and main state `myCardsToPeek` for the human player before or when advancing.
  - **Location**: 
    - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` – queen peek timer and flow (e.g. `handleQueenPeek`, `_onSpecialCardTimerExpired`, special-card window end)
    - `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` – same if logic is duplicated
    - Event handlers / coordinator if they mutate or broadcast state on queen peek end
  - **Impact**: Prevents stale peek data on screen and inconsistent state when queen peek ends without an explicit user action.

#### Match end and winners popup
- [ ] **Replace all hand cards with full data before showing winners popup**
  - **Issue**: At match end, hands still contain ID-only card data, so the UI shows placeholders/backs instead of actual cards when the winners popup is shown
  - **Current Behavior**: Game state broadcasts final state with ID-only cards in players' hands (and possibly discard/draw); winners popup or end-of-match view shows cards without rank/suit/points
  - **Expected Behavior**: **Before** showing the winners popup, replace every card in every player's hand (and any other visible piles if needed) from ID-only to **full card data** (rank, suit, points) so the UI can display them
  - **Implementation**: When determining match end (e.g. four-of-a-kind or Dutch round complete), resolve all card IDs in all hands (and discard/draw if shown) to full card data (from deck definition or stored full data), update game state with this "reveal" state, then trigger winners popup
  - **Location**: Game round or coordinator – match-end flow (e.g. `dutch_game_round.dart`, `game_event_coordinator.dart`); ensure both Flutter and Dart backend apply the same reveal before emitting final state / opening popup
  - **Impact**: Players can see everyone's final hands and card values in the winners screen
- [ ] **Winners popup: all 4 players in order with cards, values, and total points**
  - **Issue**: Winners popup should show a full summary of all players, not just the winner
  - **Current Behavior**: Popup may show only winner or a limited subset
  - **Expected Behavior**: Winners popup must contain the **list of all 4 players in order**: **winner first**, then the **rest from least points to most** (ascending by points). For each player show: **their cards**, **each card's value** (points), and **total points**
  - **Implementation**: Build ordered list: [winner, then remaining 3 sorted by points ascending]; for each player render name, list of cards (with rank/suit and points per card), and total points
  - **Location**: Flutter UI – winners popup / match end dialog (e.g. in game play screen or unified game board); game state or coordinator may need to provide final player order and resolved card data (see item above)
  - **Impact**: Clear, fair summary of match result and final hands for all players
- [ ] **Game end popup: winner celebration and close → lobby or stats**
  - **Issue**: Game end popup should celebrate when the current user is the winner and the close action should lead somewhere meaningful (lobby or updated stats).
  - **Expected Behavior**:
    1. **Winner check**: In the game end popup modal, detect if the current user is the winner (e.g. compare winner id with current user/session id).
    2. **Celebratory animations**: If the user is the winner, add celebratory animations (Flutter ideally – e.g. confetti, glow, short sequence). Non-winners see the standard popup without celebration.
    3. **Close button**: The close button should **navigate to the lobby screen** or open **another modal/screen showing the user's new stats** (e.g. updated rank, level, coins, match summary).
  - **Location**: Flutter – game end / winners popup modal (game play screen or unified game board); navigation to lobby or stats screen/modal.
  - **Impact**: Better UX for match end – clear feedback for winner and a clear next step (lobby or stats) after closing.

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

### Room TTL Implementation
- Default TTL: 24 hours (86400 seconds)
- TTL extended on each join/activity
- Automatic cleanup every 60 seconds
- Expired rooms closed with reason `'ttl_expired'`

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
- **Related**: When the user stays past the timer (or flow advances), **cardsToPeek state must be cleared** so the UI stops showing peeked cards; see TODO "Queen peek for user: clear cardsToPeek state when past timer".

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

**Last Updated**: 2026-01-31 (Added Queen peek: clear cardsToPeek state when user stays past timer or flow advances)

