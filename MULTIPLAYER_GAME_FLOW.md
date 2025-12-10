# Multiplayer Game Join/Create Flow

This document traces the complete flow of creating and joining multiplayer games, starting from the lobby screen.

## Entry Point: Lobby Screen

**File:** `flutter_base_05/lib/modules/cleco_game/screens/lobby_room/lobby_screen.dart`

The lobby screen provides three main entry points for multiplayer games:

1. **Create Room** - `_createRoom()` method (line 84)
2. **Join Room** - `_joinRoom()` method (line 127)
3. **Join Random Game** - via `JoinRandomGameWidget` (line 418)

---

## 1. CREATE ROOM Flow

### Step 1: User Action
- User clicks "Create New Game" button in `CreateRoomWidget`
- Modal opens (`CreateRoomModal`) where user sets:
  - Permission (public/private)
  - Max players
  - Min players
  - Game type
  - Turn time limit
  - Auto-start
  - Password (if private)

### Step 2: Lobby Screen Handler
**File:** `lobby_screen.dart:84-125`

```dart
Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
  // 1. Clear practice user data
  ClecoGameHelpers.updateUIState({'practiceUser': null});
  
  // 2. Set WebSocket transport mode
  eventEmitter.setTransportMode(EventTransportMode.websocket);
  
  // 3. Ensure WebSocket is connected
  if (!_websocketManager.isConnected) {
    await _websocketManager.connect();
  }
  
  // 4. Call helper method to create room
  final result = await ClecoGameHelpers.createRoom(
    permission: roomSettings['permission'] ?? 'public',
    maxPlayers: roomSettings['maxPlayers'],
    minPlayers: roomSettings['minPlayers'],
    gameType: roomSettings['gameType'] ?? 'classic',
    turnTimeLimit: roomSettings['turnTimeLimit'] ?? 30,
    autoStart: roomSettings['autoStart'] ?? true,
    password: roomSettings['password'],
  );
}
```

### Step 3: Helper Method
**File:** `cleco_game_helpers.dart:24-51`

```dart
static Future<Map<String, dynamic>> createRoom({...}) {
  final data = {
    'permission': permission,
    'max_players': maxPlayers,
    'min_players': minPlayers,
    'game_type': gameType,
    'turn_time_limit': turnTimeLimit,
    'auto_start': autoStart,
  };
  
  if (permission == 'private' && password != null) {
    data['password'] = password;
  }
  
  return _eventEmitter.emit(
    eventType: 'create_room',
    data: data,
  );
}
```

### Step 4: Event Emission
**File:** `validated_event_emitter.dart` (via `ClecoGameEventEmitter`)

- Validates event fields against schema (line 54-57)
- Injects user_id from AuthManager
- Emits WebSocket event: `create_room` with data payload

### Step 5: Backend Handler (Python)
**File:** `python_base_04/core/managers/websockets/ws_event_listeners.py:56-59`

```python
@socketio.on('create_room')
def handle_create_room(data=None):
    session_id = request.sid
    return self.event_handlers.handle_create_room(session_id, data or {})
```

**File:** `python_base_04/core/managers/websockets/ws_event_handlers.py:369-397`

```python
def handle_create_room(self, session_id, data):
    # 1. Validate permission (public/private)
    # 2. Resolve user_id from session/JWT
    # 3. Generate room_id if not provided: "room_{uuid}"
    # 4. Get password if provided
    # 5. Create room via websocket_manager.create_room()
    # 6. Emit 'room_created' event back to client
```

**File:** `python_base_04/core/managers/websockets/websocket_manager.py:414-445`

```python
def create_room(self, room_id, permission, owner_id, password):
    # 1. Validate permission
    # 2. Check if room exists (return True if exists)
    # 3. Create room_data dict with:
    #    - room_id, permission, owner_id
    #    - allowed_users, allowed_roles
    #    - created_at, size, max_size, min_players
    #    - password (if private)
    # 4. Store in Redis with TTL
    # 5. Return success
```

### Step 6: Backend Event Response
The backend emits `room_created` event with:
- `room_id`
- `owner_id`
- Room metadata

### Step 7: Frontend Event Handler
**File:** `flutter_base_05/lib/core/managers/websockets/websocket_manager.dart:372-392`

```dart
_socket!.on('room_created', (data) {
  final roomId = data['room_id'] ?? '';
  final roomData = data is Map<String, dynamic> ? data : <String, dynamic>{};
  
  // Update room info in state
  WebSocketStateHelpers.updateRoomInfo(
    roomId: roomId,
    roomInfo: roomData,
  );
  
  // Emit RoomEvent to stream
  _roomController.add(RoomEvent(...));
});
```

### Step 8: Cleco Game Event Handler
**File:** `flutter_base_05/lib/modules/cleco_game/backend_core/cleco_game_main.dart:40-92`

The Dart backend (running in Flutter) listens for `room_created` events and:
1. Creates a minimal game state via `GameRegistry.createGame()`
2. Initializes `ClecoGameRound` instance
3. Sets up game state with:
   - `phase: 'waiting_for_players'`
   - `status: 'inactive'`
   - `players: []`
   - `owner_id: sessionId`
4. Stores game state in `GameStateStore`
5. Emits `cleco_room_created` event to update Flutter state

### Step 9: State Update
**File:** `flutter_base_05/lib/modules/cleco_game/managers/cleco_event_handler_callbacks.dart`

The `cleco_room_created` event handler:
1. Updates `cleco_game` state with:
   - `currentRoomId`
   - `currentGameId`
   - `isInRoom: true`
   - `isRoomOwner: true`
   - Game data in `games` map
2. Adds game to `joinedGames` list
3. Triggers UI updates via StateManager

---

## 2. JOIN ROOM Flow

### Step 1: User Action
- User enters room ID (and password if private) in `JoinRoomWidget`
- Clicks "Join Game" button

### Step 2: Widget Handler
**File:** `join_game_widget.dart:145-203`

```dart
Future<void> _joinRoom() async {
  final roomId = _roomIdController.text.trim();
  final password = _passwordController.text.trim();
  
  // Validate password for private rooms
  if (_isPrivateRoom && password.isEmpty) {
    throw Exception('Password is required for private games');
  }
  
  // Check WebSocket connection
  if (!wsManager.isConnected) {
    throw Exception('Not connected to server');
  }
  
  // Prepare join data
  final joinData = {
    'room_id': roomId,
  };
  if (password.isNotEmpty) {
    joinData['password'] = password;
  }
  
  // Emit join_room event
  await eventEmitter.emit(
    eventType: 'join_room',
    data: joinData,
  );
}
```

### Step 3: Alternative Join Path (GameCoordinator)
**File:** `lobby_screen.dart:127-164`

```dart
Future<void> _joinRoom(String roomId) async {
  // 1. Clear practice user data
  // 2. Set WebSocket transport mode
  // 3. Ensure WebSocket connected
  
  // 4. Use GameCoordinator
  final gameCoordinator = GameCoordinator();
  final success = await gameCoordinator.joinGame(
    gameId: roomId,
    playerName: 'Player',
  );
}
```

**File:** `game_coordinator.dart:27-49`

```dart
Future<bool> joinGame({String? gameId, required String playerName, ...}) async {
  final action = PlayerAction.joinGame(
    gameId: gameId,
    playerName: playerName,
    playerType: playerType,
    maxPlayers: maxPlayers,
  );
  await action.execute();
  return true;
}
```

**File:** `player_action.dart:398-415`

```dart
static PlayerAction joinGame({...}) {
  return PlayerAction._(
    eventName: 'join_game',  // Note: different from 'join_room'
    payload: {
      'game_id': gameId,
      'player_name': playerName,
      'player_type': playerType,
      'max_players': maxPlayers,
    },
  );
}
```

### Step 4: Backend Handler (Python)
**File:** `ws_event_listeners.py:50-54`

```python
@socketio.on('join_room')
def handle_join_room(data=None):
    session_id = request.sid
    return self.event_handlers.handle_join_room(session_id, data or {})
```

The handler:
1. Validates room exists
2. Checks password (if private)
3. Checks room capacity
4. Adds user to room via `websocket_manager.join_room()`
5. Emits `room_joined` event back to client

### Step 5: Frontend Event Handler
**File:** `websocket_manager.dart` (room_joined listener)

The `room_joined` event:
1. Updates room info in state
2. Emits `RoomEvent` to stream

### Step 6: Cleco Game Event Handler
**File:** `cleco_game_main.dart` (Dart backend)

The Dart backend listens for `room_joined` events and:
1. Retrieves game state from `GameStateStore`
2. Adds player to game state
3. Emits game state snapshot via `cleco_room_joined` event
4. Updates Flutter state with:
   - `currentRoomId`
   - `currentGameId`
   - `isInRoom: true`
   - Updated game data in `games` map

---

## 3. JOIN RANDOM GAME Flow

### Step 1: User Action
- User clicks "Join Random Game" button in `JoinRandomGameWidget`

### Step 2: Widget Handler
**File:** `join_random_game_widget.dart:60-109`

```dart
Future<void> _handleJoinRandomGame() async {
  final result = await ClecoGameHelpers.joinRandomGame();
}
```

### Step 3: Helper Method
**File:** `cleco_game_helpers.dart:136-178`

```dart
static Future<Map<String, dynamic>> joinRandomGame() async {
  // 1. Ensure WebSocket connected
  // 2. Set isRandomJoinInProgress flag
  // 3. Emit join_random_game event
  await _eventEmitter.emit(
    eventType: 'join_random_game',
    data: {},
  );
}
```

### Step 4: Backend Handler (Python)
The backend:
1. Searches for available public rooms with space
2. If found: joins the room (same as join_room flow)
3. If not found: creates new room and joins (same as create_room + join_room flow)
4. Emits appropriate events back

---

## Key Components

### Event Emitter
**File:** `validated_event_emitter.dart`
- Validates event schemas
- Injects user_id automatically
- Handles WebSocket vs Practice mode routing

### State Management
**File:** `cleco_game_state_updater.dart`
- Validates all state updates
- Computes derived state slices (gameInfo, joinedGamesSlice, etc.)
- Ensures state consistency

### Event Handlers
**File:** `cleco_event_handler_callbacks.dart`
- Handles all cleco_* WebSocket events
- Updates state via validated updater
- Triggers UI updates via StateManager

### Game State Store
**File:** `game_state_store.dart` (Dart backend)
- Stores game state in memory
- Provides game state snapshots
- Manages game lifecycle

---

## State Flow Summary

1. **User Action** → Lobby Screen method
2. **Helper Method** → Validates and prepares data
3. **Event Emitter** → Validates and emits WebSocket event
4. **Backend (Python)** → Processes request, updates Redis, emits response
5. **WebSocket Manager** → Receives event, updates connection state
6. **Dart Backend** → Processes game logic, updates game state
7. **Event Handler** → Updates Flutter state via StateManager
8. **UI Updates** → Widgets rebuild based on state changes

---

## Navigation

After successful room creation/join:
- State is updated with `currentGameId` and `isInRoom: true`
- Navigation to game play screen happens automatically via:
  - WebSocket event handlers that check game phase
  - Or explicit navigation in event callbacks
  - **File:** `navigation_manager.dart` → `navigateTo('/cleco/game-play')`
