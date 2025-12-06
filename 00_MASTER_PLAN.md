# Master Plan - Cleco Game Development

## Overview
This document tracks high-level development plans, todos, and architectural decisions for the Cleco game application.

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
  - **Location**: `dart_bkend_base_01/lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart` and related event handlers
  - **Impact**: Core game feature - players must complete initial peek before game can start
- [ ] **Complete instructions logic**
  - **Status**: Partially implemented - `showInstructions` flag is stored and passed through, timer logic checks it
  - **Current State**: `showInstructions` is stored in game state, timer logic respects it (timers disabled when `showInstructions == true`), value is passed from practice widget to game logic
  - **Needs**: Complete UI implementation to show/hide instructions based on flag, ensure instructions are displayed correctly in practice mode, verify timer behavior matches instructions visibility
  - **Location**: Flutter UI components (practice match widget, game play screen), timer logic in `cleco_game_round.dart`
  - **Impact**: User experience - players need clear instructions in practice mode
- [ ] **Fix CPU player Jack swap decision logic to validate cards exist in hand**
  - **Issue**: CPU players sometimes attempt Jack swaps with cards that are no longer in their hand
  - **Root Cause**: CPU decision logic uses `known_cards` (which may contain "forgotten" played cards due to difficulty-based remember probability), but by execution time the card has already been played and removed from hand
  - **Current Behavior**: Decision is made based on stale `known_cards` data, validation correctly catches invalid swaps but wastes decision attempts
  - **Solution**: Before making Jack swap decision, validate that selected cards actually exist in the player's current hand, not just in `known_cards`
  - **Location**: `dart_bkend_base_01/lib/modules/cleco_game/backend_core/shared_logic/utils/computer_player_factory.dart` - `getJackSwapDecision()` and related selection methods
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

---

## 🚀 Future Enhancements

1. **Multi-server Support**: Redis-based room sharing across servers
2. **Game Replay**: Record and replay game sessions
3. **Spectator Mode**: Allow users to watch games
4. **Tournament System**: Organize and manage tournaments
5. **Analytics**: Track game statistics and player performance

---

## 📚 Related Documentation

- `Documentation/Cleco_game/ROOM_GAME_CREATION_COMPARISON.md` - Python vs Dart backend comparison
- `Documentation/Cleco_game/COMPLETE_STATE_STRUCTURE.md` - Game state structure
- `.cursor/rules/cleco-game-state-rules.mdc` - Game system rules

---

**Last Updated**: 2025-12-04

