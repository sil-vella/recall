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

#### WebSocket JWT Validation
- [ ] **Enforce JWT validation for WebSocket connections**
  - Currently, authentication is optional - clients can connect and send events without authenticating
  - Add authentication check in `_onMessage()` or `handleMessage()` to reject events from unauthenticated sessions
  - Allow only `authenticate`, `ping`, and `pong` events for unauthenticated sessions
  - Reject all game events (`create_room`, `join_room`, `start_match`, etc.) if session is not authenticated
  - **Location**: `dart_bkend_base_01/lib/server/websocket_server.dart` and `message_handler.dart`
  - **Impact**: Security improvement - prevents unauthorized game actions

#### Player Action Validation
- [ ] **Validate player is still in game before processing any action**
  - **Issue**: Players who leave a game can still see game updates (they remain subscribed to room broadcasts) and may attempt to perform actions
  - **Current Behavior**: Actions from players who have left may be processed if validation is missing
  - **Expected Behavior**: All game actions must verify that the player is still in the game's players list before processing
  - **Actions to Validate**: 
    - `draw_card` - verify player exists in game state players list
    - `play_card` - verify player exists in game state players list
    - `same_rank_play` - verify player exists in game state players list
    - `queen_peek` - verify player exists in game state players list
    - `jack_swap` - verify both players exist in game state players list
    - `collect_from_discard` - verify player exists in game state players list
    - Any other game action events
  - **Location**: 
    - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart` - Add validation in `handle()` method before routing to game logic
    - Or in individual action handlers in `dutch_game_round.dart` (draw, play, etc.)
  - **Implementation**: 
    - Get current game state
    - Check if playerId (sessionId) exists in `gameState['players']` list
    - If player not found, reject action with appropriate error message
    - Return early before processing the action
  - **Impact**: Game integrity - prevents actions from disconnected/removed players from affecting active games

#### JWT Authentication Between Dart Backend and Python
- [ ] **Create JWT token system for Dart backend to Python API communication**
  - **Current State**: Dart backend calls Python API endpoints (e.g., `/public/dutch/update-game-stats`) without authentication
  - **Issue**: Public endpoints are vulnerable to unauthorized access
  - **Expected Behavior**: Dart backend should authenticate with Python backend using JWT tokens
  - **Implementation Steps**:
    1. **Dart Backend JWT Client**:
       - Create JWT token management in Dart backend
       - Store JWT token (received from Flutter client or obtained via service-to-service auth)
       - Add JWT token to HTTP request headers when calling Python API
       - Handle token refresh/expiration
    2. **Python Backend JWT Validation**:
       - Modify Python endpoints to accept and validate JWT tokens from Dart backend
       - Extract user_id from JWT token for authorization
       - Reject requests with invalid/missing tokens
    3. **Token Exchange**:
       - Determine token source: Flutter client passes token to Dart backend, or Dart backend obtains service token
       - Implement token forwarding/storage mechanism
  - **Location**: 
    - `dart_bkend_base_01/lib/services/python_api_client.dart` - Add JWT token handling
    - `python_base_04/core/modules/dutch_game/dutch_game_main.py` - Add JWT validation to endpoints
    - `python_base_04/core/managers/jwt_manager.py` - Use existing JWT manager for validation
  - **Impact**: Security improvement - prevents unauthorized API calls and ensures proper user identification

- [ ] **Modify game statistics update endpoint to use JWT authentication**
  - **Current State**: `/public/dutch/update-game-stats` endpoint is public (no authentication)
  - **Expected Behavior**: Endpoint should require JWT authentication and extract user_id from token
  - **Implementation**:
    - Change endpoint from `/public/dutch/update-game-stats` to `/dutch/update-game-stats` (remove public prefix)
    - Add JWT validation decorator/middleware to endpoint
    - Extract `user_id` from JWT token instead of relying on request body
    - Validate that JWT user_id matches the user_id in the game results
    - Update Dart backend to send JWT token in Authorization header
  - **Location**: 
    - `python_base_04/core/modules/dutch_game/dutch_game_main.py` - Modify `update_game_stats()` method
    - `dart_bkend_base_01/lib/services/python_api_client.dart` - Add JWT token to requests
    - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart` - Pass JWT token when calling API
  - **Impact**: Security improvement - ensures only authenticated requests can update game statistics, prevents unauthorized data manipulation

### Medium Priority

#### Room Management Features
- [ ] Implement `get_public_rooms` endpoint (matching Python backend)
- [ ] Implement `user_joined_rooms` event (list rooms user is in)
- [ ] Add room access control (`allowed_users`, `allowed_roles` lists)

#### Game Features
- [ ] Add comprehensive error handling for game events
- [ ] Implement game state persistence (optional, for recovery)
- [ ] Add game replay/logging system
- [ ] **Complete initial peek logic**
  - **Status**: Partially implemented - initial peek phase exists but needs completion
  - **Current State**: Game enters `initial_peek` phase on match start, players can peek at 2 cards
  - **Needs**: Complete the flow from initial peek to game start, ensure all players complete peek before proceeding, handle timeout/auto-complete scenarios
  - **Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` and related event handlers
  - **Impact**: Core game feature - players must complete initial peek before game can start
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

**Last Updated**: 2025-01-XX (Added JWT authentication system between Dart backend and Python)

