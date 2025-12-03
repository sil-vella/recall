# Master Plan - Recall Game Development

## Overview
This document tracks high-level development plans, todos, and architectural decisions for the Recall game application.

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

- `Documentation/Recall_game/ROOM_GAME_CREATION_COMPARISON.md` - Python vs Dart backend comparison
- `Documentation/Recall_game/COMPLETE_STATE_STRUCTURE.md` - Game state structure
- `.cursor/rules/recall-game-state-rules.mdc` - Game system rules

---

**Last Updated**: 2024-12-19

