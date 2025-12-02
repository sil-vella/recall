# ID System Analysis: userId, playerId, sessionId, and Random Join Scenarios

## Overview

This document analyzes how different ID types are used throughout the Recall game system, with a focus on understanding the differences between the two random join scenarios:
1. **Scenario A**: Join an existing available game
2. **Scenario B**: Create a new game (no available games found)

## ID Type Definitions

### 1. **sessionId**
- **Definition**: Unique identifier for a WebSocket connection
- **Generated**: When a client connects to the WebSocket server (UUID v4)
- **Scope**: Connection-level, one per WebSocket connection
- **Storage**: `WebSocketServer._connections` map
- **Lifetime**: Exists from connection until disconnect
- **Usage**: 
  - Routing messages to specific connections
  - Tracking which connection belongs to which user
  - Room membership tracking (`RoomManager._sessionToRoom`)

**Key Code Locations**:
```dart
// dart_bkend_base_01/lib/server/websocket_server.dart:98
final sessionId = const Uuid().v4();
_connections[sessionId] = webSocket;
```

### 2. **userId**
- **Definition**: Authenticated user identifier from the authentication system
- **Source**: 
  - From JWT token validation (via Python API)
  - Fallback to `sessionId` if not authenticated
- **Storage**: `WebSocketServer._sessionToUser` map (sessionId → userId)
- **Lifetime**: Persists for the session after authentication
- **Usage**:
  - Identifying the actual user (not just the connection)
  - Room ownership (`Room.ownerId`)
  - Player creation in game state
  - Cross-session user identification

**Key Code Locations**:
```dart
// dart_bkend_base_01/lib/server/websocket_server.dart:148
_sessionToUser[sessionId] = result['user_id'] ?? sessionId;

// dart_bkend_base_01/lib/server/message_handler.dart:94
final userId = data['user_id'] as String? ?? sessionId;
```

### 3. **playerId**
- **Definition**: Identifier for a player within a specific game
- **Source**: **CRITICAL**: In the current implementation, `playerId` is **the same as `userId`**
- **Storage**: Game state `players` array, each player has `id` field
- **Lifetime**: Exists for the duration of the game
- **Usage**:
  - Identifying players in game state
  - Game actions (play card, draw card, etc.)
  - Turn management
  - Player-specific data (hand, points, status)

**Key Code Locations**:
```dart
// dart_bkend_base_01/lib/modules/recall_game/backend_core/recall_game_main.dart:144
players.add({
  'id': userId,  // ⚠️ playerId = userId
  'name': 'Player_${userId.substring(0, userId.length > 8 ? 8 : userId.length)}',
  // ...
});
```

### 4. **ownerId**
- **Definition**: The userId of the room creator
- **Source**: Set when room is created (`Room.ownerId`)
- **Storage**: `Room.ownerId` field
- **Lifetime**: Exists for the lifetime of the room
- **Usage**:
  - Determining room ownership
  - UI permissions (who can start the game)
  - Room management permissions

**Key Code Locations**:
```dart
// dart_bkend_base_01/lib/server/room_manager.dart:74
ownerId: userId,  // Set during room creation
```

### 5. **currentUser / currentPlayer**
- **Definition**: Frontend concepts for identifying the logged-in user
- **Source**: 
  - Practice mode: `recall_game` state → `practiceUser.userId`
  - Multiplayer mode: `login` state → `userId`
- **Usage**: Frontend identification of "me" in the game

**Key Code Locations**:
```dart
// flutter_base_05/lib/modules/recall_game/managers/recall_event_handler_callbacks.dart:64
static String getCurrentUserId() {
  // First check for practice user data (practice mode)
  final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final practiceUser = recallGameState['practiceUser'] as Map<String, dynamic>?;
  if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
    return practiceUser['userId']?.toString();
  }
  
  // Fall back to login state (multiplayer mode)
  final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
  return loginState['userId']?.toString() ?? '';
}
```

## ID Flow: Random Join Scenarios

### Scenario A: Join Existing Available Game

**Flow**:
1. User clicks "Join Random Game"
2. Frontend emits `join_random_game` event (no data)
3. Backend `_handleJoinRandomGame()`:
   - Extracts `userId`: `data['user_id'] ?? sessionId`
   - Finds available rooms
   - Picks random room
   - **Calls `_handleJoinRoom()`** with `room_id` and `userId`

4. `_handleJoinRoom()`:
   - Validates room exists and has capacity
   - Calls `RoomManager.joinRoom(roomId, sessionId, userId)`
   - Sends `join_room_success` and `room_joined` events
   - **Triggers `room_joined` hook**

5. `room_joined` hook (`RecallGameModule._onRoomJoined()`):
   - Receives: `room_id`, `user_id`, `session_id`
   - **Creates player with `id: userId`** (playerId = userId)
   - Adds player to game state
   - Sends game snapshot

**Key Points**:
- ✅ `userId` comes from event data or sessionId fallback
- ✅ `playerId` = `userId` (set in `_onRoomJoined`)
- ✅ Player is added to existing game state
- ✅ No room ownership (user is joining, not creating)

**Code Path**:
```dart
// message_handler.dart:378-396
_handleJoinRandomGame() 
  → _handleJoinRoom() 
    → RoomManager.joinRoom() 
    → triggerHook('room_joined')
      → RecallGameModule._onRoomJoined()
        → players.add({'id': userId, ...})
```

### Scenario B: Create New Game (No Available Games)

**Flow**:
1. User clicks "Join Random Game"
2. Frontend emits `join_random_game` event (no data)
3. Backend `_handleJoinRandomGame()`:
   - Extracts `userId`: `data['user_id'] ?? sessionId`
   - No available rooms found
   - **Calls `RoomManager.createRoom()`** with `sessionId` and `userId`
   - Room created with `ownerId: userId`
   - Sends `create_room_success` with `is_random_join: true`
   - **Triggers `room_created` hook**

4. `room_created` hook (`RecallGameModule._onRoomCreated()`):
   - Receives: `room_id`, `owner_id`
   - **Creates player with `id: ownerId`** (playerId = userId = ownerId)
   - Initializes game state with creator as first player
   - Sends initial game state

5. Backend then sends `room_joined` event:
   - **Triggers `room_joined` hook again**
   - `_onRoomJoined()` checks if player exists (it does!)
   - Skips duplicate player creation
   - Sends game snapshot

6. Auto-start logic:
   - Schedules delayed match start
   - When timer fires, calls `_startMatchForRandomJoin()`
   - Starts match with `is_random_join: true` flag

**Key Points**:
- ✅ `userId` comes from event data or sessionId fallback
- ✅ `ownerId` = `userId` (set during room creation)
- ✅ `playerId` = `userId` = `ownerId` (set in `_onRoomCreated`)
- ⚠️ **Player is created TWICE** (once in `_onRoomCreated`, once attempted in `_onRoomJoined` - but duplicate check prevents it)
- ⚠️ User is room owner (but `is_random_join` flag may affect UI behavior)

**Code Path**:
```dart
// message_handler.dart:401-483
_handleJoinRandomGame() 
  → RoomManager.createRoom(sessionId, userId)
    → triggerHook('room_created')
      → RecallGameModule._onRoomCreated()
        → players.add({'id': ownerId, ...})  // First player creation
  → sendToSession('room_joined')
    → triggerHook('room_joined')
      → RecallGameModule._onRoomJoined()
        → existingPlayer check (true) → skip  // Duplicate check prevents second creation
```

## Critical Differences Between Scenarios

### 1. **Room Ownership**

| Aspect | Scenario A (Join Existing) | Scenario B (Create New) |
|--------|---------------------------|------------------------|
| `ownerId` | Different user (room creator) | Same as joining user |
| User is owner? | ❌ No | ✅ Yes |
| Can start game? | ❌ No (unless owner) | ⚠️ Yes, but `is_random_join` flag may hide start button |

### 2. **Player Creation**

| Aspect | Scenario A (Join Existing) | Scenario B (Create New) |
|--------|---------------------------|------------------------|
| Player created in | `_onRoomJoined()` only | `_onRoomCreated()` + `_onRoomJoined()` (duplicate check) |
| Player `id` source | `userId` from join event | `ownerId` from create event |
| Result | ✅ Single player creation | ⚠️ Attempted twice, but duplicate check prevents |

### 3. **Game State Initialization**

| Aspect | Scenario A (Join Existing) | Scenario B (Create New) |
|--------|---------------------------|------------------------|
| Game state exists? | ✅ Yes (created by room creator) | ❌ No (created during this flow) |
| Initialization | Player added to existing state | Full game state created |
| Other players | May have existing players | Only creator initially |

### 4. **Auto-Start Behavior**

| Aspect | Scenario A (Join Existing) | Scenario B (Create New) |
|--------|---------------------------|------------------------|
| Auto-start? | ❌ No (game may already be started) | ✅ Yes (delayed start scheduled) |
| Start trigger | Manual (by room owner) | Automatic (after delay or max players) |
| CPU players | Created when owner starts | Created when auto-start fires |

## Potential Issues and Inconsistencies

### Issue 1: userId Resolution Inconsistency

**Problem**: In `_handleJoinRandomGame()`, `userId` is extracted as:
```dart
final userId = data['user_id'] as String? ?? sessionId;
```

The frontend doesn't explicitly send `user_id` in the `join_random_game` event data:
```dart
// flutter_base_05/lib/modules/recall_game/utils/recall_game_helpers.dart:145
await _eventEmitter.emit(
  eventType: 'join_random_game',
  data: {},  // Empty data - no user_id!
);
```

**However**: `WebSocketManager.sendCustomEvent()` **DOES** auto-add `user_id`:
```dart
// flutter_base_05/lib/core/managers/websockets/websocket_manager.dart:866-870
final currentUserId = _getCurrentUserId();
if (currentUserId.isNotEmpty) {
  data['user_id'] = currentUserId;
}
```

**Potential Issue**: 
- `WebSocketManager._getCurrentUserId()` only checks `login` state, not practice user state
- `ValidatedEventEmitter._getCurrentUserId()` checks both practice and login state
- For practice mode, `user_id` might not be added correctly
- For multiplayer mode, it should work if user is logged in

**Impact**: 
- Multiplayer: `userId` should be correctly set from login state
- Practice mode: `userId` might fallback to `sessionId` if not in login state
- Backend fallback: If `user_id` is missing, falls back to `sessionId`

**Solution**: Ensure `WebSocketManager._getCurrentUserId()` also checks practice user state, or ensure practice mode uses a different event path.

### Issue 2: Player ID vs User ID Confusion

**Problem**: The codebase uses `playerId` and `userId` interchangeably, but they're conceptually different:
- `userId`: Authenticated user identity (persistent across games)
- `playerId`: Player identity within a specific game (should be game-scoped)

**Current Implementation**: `playerId = userId` (they're the same)

**Potential Issues**:
- If a user joins multiple games, they'd have the same `playerId` in all games
- CPU players have generated IDs like `cpu_${timestamp}_${index}`, which is inconsistent
- Frontend code sometimes expects `playerId` to match `userId`, sometimes not

**Example Confusion**:
```dart
// game_event_coordinator.dart:44-63
String? _getPlayerIdFromSession(String sessionId, String roomId) {
  final userId = server.getUserIdForSession(sessionId);
  // ...
  // Tries to find player by userId
  for (final player in players) {
    final playerUserId = player['userId'] as String? ?? player['user_id'] as String?;
    if (playerUserId == userId) {
      return player['id'] as String?;  // Returns player['id'], which is actually userId!
    }
  }
}
```

### Issue 3: Duplicate Player Creation Attempt

**Problem**: In Scenario B, the player creation flow is:
1. `_onRoomCreated()` creates player with `id: ownerId`
2. `_onRoomJoined()` is triggered and tries to create player again
3. Duplicate check prevents second creation

**Impact**: 
- Redundant hook trigger
- Potential race conditions
- Confusing code flow

**Better Approach**: 
- Either create player only in `_onRoomCreated()` and skip `_onRoomJoined()` for creator
- Or create player only in `_onRoomJoined()` and ensure it's called for creator too

### Issue 4: Owner vs Player ID Mismatch

**Problem**: In Scenario B:
- Room `ownerId` = `userId` (from create)
- Player `id` = `ownerId` (from `_onRoomCreated`)
- But `_onRoomJoined()` receives `user_id` which might be different

**Impact**: 
- If `userId` resolution differs between create and join, player might not match owner
- Frontend might show incorrect ownership status

## Recommendations

### 1. **Standardize userId Resolution**

Ensure `userId` is consistently resolved:
- Always check `WebSocketServer._sessionToUser` first
- Fallback to `sessionId` only if not authenticated
- Document the resolution order

### 2. **Clarify playerId vs userId**

**Option A**: Keep current approach (playerId = userId)
- Document that they're the same
- Ensure all code treats them as equivalent
- Remove confusing `_getPlayerIdFromSession()` logic

**Option B**: Separate playerId from userId
- Generate unique player IDs per game
- Store `userId` as separate field in player object
- Update all code to use appropriate ID

### 3. **Simplify Player Creation Flow**

For Scenario B:
- Create player only in `_onRoomCreated()` for creator
- Don't trigger `_onRoomJoined()` for creator (or make it a no-op)
- Or: Don't create player in `_onRoomCreated()`, only in `_onRoomJoined()`

### 4. **Add ID Validation**

Add validation to ensure:
- `userId` is always set before player creation
- `playerId` matches `userId` (if using Option A)
- `ownerId` matches creator's `userId`

### 5. **Document ID Flow**

Create clear documentation showing:
- How IDs flow through the system
- When each ID is set
- How to resolve IDs in different contexts

## Summary

The ID system has these key characteristics:

1. **sessionId**: WebSocket connection identifier (UUID)
2. **userId**: Authenticated user identifier (from JWT or sessionId fallback)
3. **playerId**: Currently equals `userId` (player identity in game)
4. **ownerId**: Room creator's `userId`

**Random Join Differences**:
- **Scenario A**: User joins existing game, not owner, player created once
- **Scenario B**: User creates new game, is owner, player created in `_onRoomCreated()` (duplicate attempt in `_onRoomJoined()` prevented)

**Main Issues**:
1. `userId` may not be properly resolved (falls back to `sessionId`)
2. `playerId` and `userId` are used interchangeably (confusing)
3. Duplicate player creation attempt in Scenario B
4. Inconsistent ID resolution across codebase

