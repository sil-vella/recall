# Game Creation System Documentation

## Overview

This document describes the **first implementation** of the multiplayer game creation system for the Recall card game. This system handles room creation, player discovery, and player joining through a combination of WebSocket events and HTTP API calls.

> **Note**: This is the first implementation. Additional game creation implementations will be added in the future to support different game modes, matchmaking systems, and room discovery mechanisms.

---

## Architecture Overview

The game creation system uses a **hook-based architecture** where room management events trigger game state updates, keeping the game state synchronized with room membership.

### Components

- **Frontend (Flutter)**: `flutter_base_05/lib/modules/recall_game/`
- **Backend (Dart)**: `dart_bkend_base_01/lib/modules/recall_game/`
- **Backend (Python)**: `python_base_04/core/modules/recall_game/` (for room discovery via API)

### Key Files

**Frontend**:
- `utils/recall_game_helpers.dart` - Helper methods for room operations
- `screens/lobby_room/lobby_screen.dart` - Main lobby UI
- `screens/lobby_room/widgets/create_game_widget.dart` - Room creation form
- `screens/lobby_room/widgets/join_game_widget.dart` - Room joining form
- `screens/lobby_room/widgets/available_games_widget.dart` - Available games list

**Backend (Dart)**:
- `recall_game_main.dart` - Hook callbacks for game lifecycle
- `backend_core/recall_game_main.dart` - Game state initialization
- `server/message_handler.dart` - WebSocket message handling
- `server/room_manager.dart` - Room management logic

**Backend (Python)**:
- API endpoints for room discovery (`/userauth/recall/get-available-games`, `/userauth/recall/find-room`)

---

## Game Creation Flow

### Frontend Initiation

#### 1. User Interface

The user fills out the room creation form in `CreateRoomWidget` with the following settings:

- **Permission**: `public` or `private`
- **Max Players**: Maximum number of players (default: 4)
- **Min Players**: Minimum players required to start (default: 2)
- **Game Type**: Type of game (default: `classic`)
- **Turn Time Limit**: Time limit per turn in seconds (default: 30)
- **Auto Start**: Whether to auto-start when min players reached (default: `false`)
- **Password**: Optional password for private rooms

#### 2. Helper Method Call

When the user submits the form, `RecallGameHelpers.createRoom()` is called:

```dart
final result = await RecallGameHelpers.createRoom(
  permission: roomSettings['permission'] ?? 'public',
  maxPlayers: roomSettings['maxPlayers'],
  minPlayers: roomSettings['minPlayers'],
  gameType: roomSettings['gameType'] ?? 'classic',
  turnTimeLimit: roomSettings['turnTimeLimit'] ?? 30,
  autoStart: roomSettings['autoStart'] ?? true,
  password: roomSettings['password'],
);
```

#### 3. WebSocket Event Emission

The helper method validates inputs and emits a `create_room` WebSocket event:

```dart
{
  'event': 'create_room',
  'permission': 'public',
  'max_players': 4,
  'min_players': 2,
  'game_type': 'classic',
  'turn_time_limit': 30,
  'auto_start': false,
  'password': null  // Only included if room is private
}
```

**Important**: The frontend ensures WebSocket is connected before sending the event. If not connected, it attempts to connect first.

---

### Backend Handling (Dart Server)

#### 1. Message Handler

`MessageHandler._handleCreateRoom()` receives the WebSocket event:

```dart
void _handleCreateRoom(String sessionId, Map<String, dynamic> data) {
  final userId = data['user_id'] as String? ?? sessionId;
  
  // Extract room settings
  final maxPlayers = data['max_players'] as int? ?? 4;
  final minPlayers = data['min_players'] as int? ?? 2;
  final gameType = data['game_type'] as String? ?? 'classic';
  final permission = data['permission'] as String?;
  final password = data['password'] as String?;
  final turnTimeLimit = data['turn_time_limit'] as int? ?? 30;
  final autoStart = data['auto_start'] as bool? ?? false;
  
  // Create room via RoomManager
  final roomId = _roomManager.createRoom(
    sessionId,
    userId,
    maxSize: maxPlayers,
    minPlayers: minPlayers,
    gameType: gameType,
    permission: permission,
    password: password,
    turnTimeLimit: turnTimeLimit,
    autoStart: autoStart,
  );
  
  // Send success response
  _server.sendToSession(sessionId, {
    'event': 'create_room_success',
    'room_id': roomId,
    'owner_id': userId,
    // ... other room info
  });
  
  // Trigger room_created hook
  _server.triggerHook('room_created', data: {
    'room_id': roomId,
    'owner_id': userId,
    'max_size': maxPlayers,
    'min_players': minPlayers,
    'game_type': gameType,
  });
}
```

#### 2. Room Manager

`RoomManager.createRoom()` creates the room and stores room metadata:

- Generates unique `room_id`
- Stores room settings (max players, min players, permission, etc.)
- Sets creator as room owner
- Auto-joins creator to the room

#### 3. Hook System: `room_created`

The `room_created` hook is triggered with room data. This hook is registered by `RecallGameModule`:

```dart
hooksManager.registerHookCallback('room_created', _onRoomCreated, priority: 100);
```

#### 4. Game State Initialization

`RecallGameModule._onRoomCreated()` hook callback:

```dart
void _onRoomCreated(Map<String, dynamic> data) {
  final roomId = data['room_id'] as String?;
  final ownerId = data['owner_id'] as String?;
  final maxSize = data['max_size'] as int? ?? 4;
  final minPlayers = data['min_players'] as int? ?? 2;
  final gameType = data['game_type'] as String? ?? 'multiplayer';

  // Create GameRound instance via registry
  GameRegistry.instance.getOrCreate(roomId, server);

  // Initialize minimal game state in store
  final store = GameStateStore.instance;
  store.mergeRoot(roomId, {
    'game_id': roomId,
    'game_state': {
      'gameId': roomId,
      'gameName': 'Game_$roomId',
      'gameType': gameType,
      'maxPlayers': maxSize,
      'minPlayers': minPlayers,
      'isGameActive': false,
      'phase': 'waiting_for_players',
      'playerCount': 1,
      'players': [
        {
          'id': ownerId,  // Creator auto-added as first player
          'name': 'Player_${ownerId.substring(0, 8)}',
          'isHuman': true,
          'status': 'waiting',
          'hand': [],
          'visible_cards': [],
          'points': 0,
          'known_cards': {},
          'collection_rank_cards': [],
        }
      ],
      'drawPile': [],
      'discardPile': [],
      'originalDeck': [],
    },
  });

  // Send initial game_state_updated to creator
  server.sendToSession(
    server.getSessionForUser(ownerId) ?? '',
    {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': store.getState(roomId)['game_state'],
      'owner_id': ownerId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}
```

**Key Points**:
- Creator is automatically added as the first player
- Game state is initialized with `phase: 'waiting_for_players'`
- `GameRound` instance is created via `GameRegistry`
- Initial state snapshot is sent to the creator

---

## Player Discovery and Search

Players can find and join games through three different mechanisms:

### 1. Search by Room ID (API - Python Backend)

**Frontend**: `RecallGameHelpers.findRoom(roomId)`

```dart
static Future<Map<String, dynamic>> findRoom(String roomId) async {
  // Makes HTTP POST to Python backend
  final response = await connectionsModule.sendPostRequest(
    '/userauth/recall/find-room',
    {'room_id': roomId},
  );
  
  return {
    'success': true,
    'game': response['game'],
    'message': response['message'],
  };
}
```

**Backend**: Python API endpoint `/userauth/recall/find-room`
- Queries database/room manager for room information
- Returns room details if found
- Requires JWT authentication

**Use Case**: Direct room joining when player knows the room ID

---

### 2. Fetch Available Games (API - Python Backend)

**Frontend**: `RecallGameHelpers.fetchAvailableGames()`

```dart
static Future<Map<String, dynamic>> fetchAvailableGames() async {
  // Makes HTTP GET to Python backend
  final response = await connectionsModule.sendGetRequest(
    '/userauth/recall/get-available-games'
  );
  
  return {
    'success': true,
    'games': response['games'] ?? [],
    'count': games.length,
  };
}
```

**Backend**: Python API endpoint `/userauth/recall/get-available-games`
- Returns list of public/available games
- Includes room metadata (player count, phase, etc.)
- Requires JWT authentication

**Use Case**: Displaying list of available games in `AvailableGamesWidget`

---

### 3. List Rooms (WebSocket - Dart Backend)

**Frontend**: Send `list_rooms` WebSocket event

```dart
socket.emit('list_rooms');
```

**Backend**: `MessageHandler._handleListRooms()`

```dart
void _handleListRooms(String sessionId) {
  final rooms = _roomManager.getAllRooms();
  _server.sendToSession(sessionId, {
    'event': 'rooms_list',
    'rooms': rooms.map((r) => r.toJson()).toList(),
    'total': rooms.length,
  });
}
```

**Use Case**: Real-time room listing via WebSocket

---

## Player Joining Flow

### Frontend Initiation

#### 1. User Interface

The user enters:
- **Room ID**: The ID of the room to join
- **Password**: Required if the room is private

#### 2. Helper Method Call

`RecallGameHelpers.joinRoom()` is called:

```dart
final result = await RecallGameHelpers.joinRoom(
  roomId: roomId,
);
```

Or directly via WebSocket:

```dart
{
  'event': 'join_room',
  'room_id': 'room_123',
  'password': 'optional_password'  // Only if private room
}
```

---

### Backend Handling (Dart Server)

#### 1. Message Handler

`MessageHandler._handleJoinRoom()` receives the event:

```dart
void _handleJoinRoom(String sessionId, Map<String, dynamic> data) {
  final userId = data['user_id'] as String? ?? sessionId;
  final roomId = data['room_id'] as String?;
  final password = data['password'] as String?;
  
  // Validate room exists
  final room = _roomManager.getRoomInfo(roomId);
  if (room == null) {
    _sendError(sessionId, 'Room not found');
    return;
  }
  
  // Check if user already in room
  if (_roomManager.isUserInRoom(sessionId, roomId)) {
    _server.sendToSession(sessionId, {
      'event': 'already_joined',
      'room_id': roomId,
    });
    return;
  }
  
  // Check room capacity
  if (!_roomManager.canJoinRoom(roomId)) {
    _sendError(sessionId, 'Room is full');
    return;
  }
  
  // Validate password for private rooms
  if (!_roomManager.validateRoomPassword(roomId, password)) {
    _sendError(sessionId, 'Invalid password');
    return;
  }
  
  // Join room
  if (_roomManager.joinRoom(roomId, sessionId, userId, password: password)) {
    // Send success response
    _server.sendToSession(sessionId, {
      'event': 'join_room_success',
      'room_id': roomId,
      // ... room info
    });
    
    // Trigger room_joined hook
    _server.triggerHook('room_joined', data: {
      'room_id': roomId,
      'session_id': sessionId,
      'user_id': userId,
    });
  }
}
```

#### 2. Validation Steps

Before joining, the system validates:
- ✅ Room exists
- ✅ User is not already in the room
- ✅ Room has capacity (not full)
- ✅ Password is correct (for private rooms)

#### 3. Hook System: `room_joined`

The `room_joined` hook is triggered with join data. This hook is registered by `RecallGameModule`:

```dart
hooksManager.registerHookCallback('room_joined', _onRoomJoined, priority: 100);
```

#### 4. Player Addition to Game State

`RecallGameModule._onRoomJoined()` hook callback:

```dart
void _onRoomJoined(Map<String, dynamic> data) {
  final roomId = data['room_id'] as String?;
  final userId = data['user_id'] as String?;
  final sessionId = data['session_id'] as String?;

  final store = GameStateStore.instance;
  final gameState = store.getGameState(roomId);
  final players = gameState['players'] as List<dynamic>? ?? [];

  // Check if player already exists (prevent duplicates)
  final existingPlayer = players.any((p) => p['id'] == userId);
  if (existingPlayer) {
    // Still send snapshot
    _sendGameSnapshot(sessionId, roomId);
    return;
  }

  // Add new player
  players.add({
    'id': userId,
    'name': 'Player_${userId.substring(0, userId.length > 8 ? 8 : userId.length)}',
    'isHuman': true,
    'status': 'waiting',
    'hand': [],
    'visible_cards': [],
    'points': 0,
    'known_cards': {},
    'collection_rank_cards': [],
  });

  gameState['players'] = players;
  gameState['playerCount'] = players.length;
  store.setGameState(roomId, gameState);

  // Send snapshot to the joiner
  _sendGameSnapshot(sessionId, roomId);

  // Broadcast player_joined to room
  final ownerId = roomManager.getRoomInfo(roomId)?.ownerId;
  server.broadcastToRoom(roomId, {
    'event': 'recall_new_player_joined',
    'room_id': roomId,
    'owner_id': ownerId,
    'joined_player': {
      'user_id': userId,
      'session_id': sessionId,
      'name': 'Player_...',
      'joined_at': DateTime.now().toIso8601String(),
    },
    'game_state': gameState,
    'timestamp': DateTime.now().toIso8601String(),
  });
}
```

**Key Points**:
- Duplicate prevention: Checks if player already exists
- Player added to `game_state['players']` array
- `playerCount` updated
- Game state snapshot sent to the joiner
- `recall_new_player_joined` event broadcast to all room members

---

## Complete Flow Diagrams

### Game Creation Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (Flutter)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 1. User fills CreateRoomWidget form
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         RecallGameHelpers.createRoom()                       │
│  - Validates inputs                                          │
│  - Ensures WebSocket connected                               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 2. Emit WebSocket event
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              WebSocket: 'create_room' event                  │
│  {                                                           │
│    'permission': 'public',                                  │
│    'max_players': 4,                                        │
│    'min_players': 2,                                        │
│    'game_type': 'classic',                                  │
│    ...                                                       │
│  }                                                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 3. Backend receives event
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         MessageHandler._handleCreateRoom()                   │
│  - Extracts room settings                                    │
│  - Calls RoomManager.createRoom()                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 4. Room created
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              RoomManager.createRoom()                        │
│  - Generates unique room_id                                  │
│  - Stores room metadata                                      │
│  - Sets creator as owner                                     │
│  - Auto-joins creator                                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 5. Trigger hook
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Hook: 'room_created'                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 6. Hook callback
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│      RecallGameModule._onRoomCreated()                       │
│  - Creates GameRound instance                                │
│  - Initializes game state in GameStateStore                  │
│  - Adds creator as first player                              │
│  - Sets phase: 'waiting_for_players'                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 7. Send state snapshot
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Frontend receives 'game_state_updated'               │
│  - Room created successfully                                 │
│  - Creator sees waiting room                                 │
└─────────────────────────────────────────────────────────────┘
```

### Player Joining Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (Flutter)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 1. User enters room ID (and password)
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         RecallGameHelpers.joinRoom()                         │
│  - Validates inputs                                          │
│  - Ensures WebSocket connected                               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 2. Emit WebSocket event
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              WebSocket: 'join_room' event                    │
│  {                                                           │
│    'room_id': 'room_123',                                   │
│    'password': 'optional'                                    │
│  }                                                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 3. Backend receives event
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         MessageHandler._handleJoinRoom()                     │
│  - Validates room exists                                     │
│  - Checks capacity                                           │
│  - Validates password (if private)                           │
│  - Checks if already joined                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 4. Join room
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              RoomManager.joinRoom()                          │
│  - Adds session to room                                      │
│  - Updates room size                                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 5. Trigger hook
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Hook: 'room_joined'                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 6. Hook callback
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│      RecallGameModule._onRoomJoined()                        │
│  - Checks for duplicate player                               │
│  - Adds player to game_state['players']                      │
│  - Updates playerCount                                       │
│  - Saves to GameStateStore                                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ 7. Send notifications
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Joiner receives: 'game_state_updated'                       │
│  Room members receive: 'recall_new_player_joined'            │
│  - All players see updated player count                      │
│  - New player sees game state                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. Hook-Based Architecture

**Why**: Separates concerns between room management and game state management. Room events trigger game state updates automatically.

**Benefits**:
- Modular design
- Easy to extend with additional hooks
- Room management and game logic are decoupled

### 2. Creator Auto-Join

**Why**: When a room is created, the creator is automatically added as the first player in the game state.

**Implementation**: The `room_created` hook adds the creator to the `players` array during game state initialization.

### 3. Duplicate Prevention

**Why**: Prevents the same player from being added multiple times to the game state.

**Implementation**: `_onRoomJoined()` checks if a player with the same `user_id` already exists before adding.

### 4. State Snapshots

**Why**: New joiners need the complete current game state to render the UI correctly.

**Implementation**: `_sendGameSnapshot()` sends the full game state to the joining player via `game_state_updated` event.

### 5. Broadcast Notifications

**Why**: All room members need to know when a new player joins.

**Implementation**: `recall_new_player_joined` event is broadcast to all room members with updated game state.

---

## Player Discovery Mechanisms

### Comparison

| Method | Protocol | Backend | Use Case | Authentication |
|--------|----------|---------|----------|----------------|
| **Search by Room ID** | HTTP POST | Python | Direct join with known ID | JWT Required |
| **Fetch Available Games** | HTTP GET | Python | Browse public games | JWT Required |
| **List Rooms** | WebSocket | Dart | Real-time room listing | Session-based |

### When to Use Each

1. **Search by Room ID**: When a player has a specific room ID (e.g., shared via link, QR code, or friend)
2. **Fetch Available Games**: When displaying a list of joinable games in the UI
3. **List Rooms**: For real-time room discovery without page refresh

---

## State Management

### GameStateStore Structure

```dart
{
  'game_id': 'room_123',
  'game_state': {
    'gameId': 'room_123',
    'gameName': 'Game_room_123',
    'gameType': 'multiplayer',
    'maxPlayers': 4,
    'minPlayers': 2,
    'isGameActive': false,
    'phase': 'waiting_for_players',
    'playerCount': 2,
    'players': [
      {
        'id': 'user_1',
        'name': 'Player_user1',
        'isHuman': true,
        'status': 'waiting',
        'hand': [],
        'points': 0,
        // ... other player fields
      },
      {
        'id': 'user_2',
        'name': 'Player_user2',
        'isHuman': true,
        'status': 'waiting',
        'hand': [],
        'points': 0,
        // ... other player fields
      }
    ],
    'drawPile': [],
    'discardPile': [],
    'originalDeck': [],
  }
}
```

### State Updates

- **On Room Creation**: Initial state created with creator as first player
- **On Player Join**: New player added to `players` array, `playerCount` incremented
- **On Player Leave**: Player removed from `players` array, `playerCount` decremented
- **On Game Start**: `phase` changes from `'waiting_for_players'` to `'playing'`

---

## Error Handling

### Common Errors

1. **Room Not Found**: When joining a non-existent room
   - Response: `join_room_error` with message "Room not found"

2. **Room Full**: When joining a room at capacity
   - Response: `join_room_error` with message "Room is full"

3. **Invalid Password**: When password is incorrect for private room
   - Response: `join_room_error` with message "Invalid password"

4. **Already Joined**: When user is already in the room
   - Response: `already_joined` event (not an error, just notification)

5. **WebSocket Not Connected**: When trying to create/join without connection
   - Frontend handles by attempting to connect first

---

## Future Implementations

This is the **first implementation** of the game creation system. Future implementations may include:

1. **Matchmaking System**: Automatic player matching based on skill level, preferences
2. **Quick Join**: Join the first available room matching criteria
3. **Friend Invites**: Direct invitations to specific users
4. **Tournament Mode**: Tournament bracket creation and management
5. **Custom Game Modes**: Different game rule sets and configurations
6. **Room Categories**: Categorized rooms (beginner, advanced, casual, competitive)
7. **Room Persistence**: Rooms that persist across server restarts
8. **Spectator Mode**: Allow users to watch games without playing

---

## Related Documentation

- [STATE_SYSTEM.md](./STATE_SYSTEM.md) - Game state management system
- [UNIFIED_GAME_SYSTEM.md](./UNIFIED_GAME_SYSTEM.md) - Overall game system architecture

---

## Summary

The first implementation of the game creation system provides:

✅ **Room Creation**: Users can create rooms with customizable settings  
✅ **Player Discovery**: Multiple methods to find and join games  
✅ **Player Joining**: Secure joining with validation and duplicate prevention  
✅ **State Synchronization**: Hook-based system keeps game state in sync with room membership  
✅ **Real-time Updates**: WebSocket-based communication for instant updates  

The system is designed to be extensible, with clear separation between room management and game state management, making it easy to add new game creation mechanisms in the future.

