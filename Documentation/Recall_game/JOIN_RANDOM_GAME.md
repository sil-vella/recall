# Join Random Game Feature

## Overview

The "Join Random Game" feature allows users to quickly join an available game or automatically create and start a new game if none are available. This provides a streamlined way for players to get into a game without manually searching for rooms or configuring game settings.

## Feature Description

When a user clicks the "Join Random Game" button:
1. The system searches for available public games that are waiting for players
2. If available games are found, the user is randomly assigned to one
3. If no available games exist, a new game is automatically created and started
4. The game immediately begins with CPU opponents (auto-filled to minimum player count)

## User Interface

### Widget Location
- **Screen**: `LobbyScreen`
- **Widget**: `JoinRandomGameWidget`
- **Position**: Below the Create/Join Room section

### Widget Features
- Single "Join Random Game" button
- Loading state during search/join process
- Error handling with user-friendly messages
- Semantics identifier: `join_random_game_button` (for automation)

## Implementation Details

### Frontend Flow

#### 1. User Interaction
**File**: `flutter_base_05/lib/modules/recall_game/screens/lobby_room/widgets/join_random_game_widget.dart`

```dart
// User clicks "Join Random Game" button
_handleJoinRandomGame() {
  // Calls helper method
  RecallGameHelpers.joinRandomGame();
}
```

#### 2. Helper Method
**File**: `flutter_base_05/lib/modules/recall_game/utils/recall_game_helpers.dart`

```dart
static Future<Map<String, dynamic>> joinRandomGame() async {
  // Ensure WebSocket is connected
  // Emit 'join_random_game' WebSocket event
  await _eventEmitter.emit(
    eventType: 'join_random_game',
    data: {},
  );
}
```

#### 3. Event Registration
**File**: `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`

- Event type: `'join_random_game'`
- No required fields (empty data object)
- User ID is auto-added by WebSocketManager

### Backend Flow

#### 1. Event Handler
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`

```dart
case 'join_random_game':
  _handleJoinRandomGame(sessionId, data);
  break;
```

#### 2. Main Logic
**Method**: `_handleJoinRandomGame(String sessionId, Map<String, dynamic> data)`

**Step 1: Search for Available Rooms**
```dart
final availableRooms = _getAvailableRoomsForRandomJoin();
```

**Step 2A: Join Random Room (if available)**
```dart
if (availableRooms.isNotEmpty) {
  // Pick random room
  final selectedRoom = availableRooms[random.nextInt(availableRooms.length)];
  
  // Use existing join room logic
  _handleJoinRoom(sessionId, {
    'room_id': selectedRoom.roomId,
    'user_id': userId,
  });
  return;
}
```

**Step 2B: Auto-Create and Auto-Start (if no rooms available)**
```dart
// Create room with default settings
final roomId = _roomManager.createRoom(
  sessionId,
  userId,
  maxSize: 4,
  minPlayers: 2,
  gameType: 'classic',
  permission: 'public',
  autoStart: true,
);

// Trigger room_created hook (creates game state)
_server.triggerHook('room_created', data: {...});

// Trigger room_joined hook (adds player)
_server.triggerHook('room_joined', data: {...});

// Auto-start the match immediately
_gameCoordinator.handle(sessionId, 'start_match', {
  'game_id': roomId,
  'min_players': 2,
  'max_players': 4,
});
```

#### 3. Room Filtering Logic
**Method**: `_getAvailableRoomsForRandomJoin()`

Filters rooms by:
- **Permission**: Must be `'public'`
- **Capacity**: `currentSize < maxSize` (not full)
- **Phase**: Game phase must be `'waiting_for_players'` (checked via GameStateStore)

```dart
List<Room> _getAvailableRoomsForRandomJoin() {
  final allRooms = _roomManager.getAllRooms();
  final store = GameStateStore.instance;
  final availableRooms = <Room>[];
  
  for (final room in allRooms) {
    // Filter: public permission
    if (room.permission != 'public') continue;
    
    // Filter: has capacity
    if (room.currentSize >= room.maxSize) continue;
    
    // Filter: phase is waiting_for_players
    final gameState = store.getGameState(room.roomId);
    final phase = gameState['phase'] as String?;
    if (phase != 'waiting_for_players') continue;
    
    availableRooms.add(room);
  }
  
  return availableRooms;
}
```

## State Management

### Owner Handling

For auto-created rooms, the `isOwner` flag is set to `false` even though the user technically created the room. This is handled via the `is_random_join` flag:

**Backend** (`message_handler.dart`):
```dart
_server.sendToSession(sessionId, {
  'event': 'create_room_success',
  'is_random_join': true, // Flag to indicate auto-created for random join
  ...
});
```

**Frontend** (`ws_event_handler.dart`):
```dart
final isRandomJoin = data['is_random_join'] == true;
final isRoomOwner = isRandomJoin ? false : (currentUserId == ownerId);
```

**Frontend** (`recall_event_manager.dart`):
```dart
final isRandomJoin = data['is_random_join'] == true;
final isOwner = isRandomJoin ? false : (data['is_owner'] == true);
```

This ensures that:
- Users cannot see the "Start Match" button for auto-created rooms
- The game starts automatically without user intervention
- The UI correctly reflects that the user is not the room owner

## Auto-Start Integration

When a new room is auto-created, the game immediately starts:

1. **Room Creation**: Room is created with default settings
2. **Game State Initialization**: `room_created` hook initializes game state
3. **Player Addition**: `room_joined` hook adds the player to the game
4. **Match Start**: `start_match` event is triggered automatically
5. **CPU Opponent Creation**: The existing `_handleStartMatch()` logic automatically creates CPU opponents to fill to `minPlayers` (currently 2)

The CPU opponent creation is handled by the existing `GameEventCoordinator._handleStartMatch()` method, which:
- Checks current player count
- Creates CPU players to reach `minPlayers`
- Initializes the deck and deals cards
- Sets game phase to `initial_peek`

## Event Flow Diagram

```
User clicks "Join Random Game"
  ↓
Frontend: joinRandomGame() helper
  ↓
Frontend: Emit 'join_random_game' WebSocket event
  ↓
Backend: _handleJoinRandomGame()
  ↓
Backend: _getAvailableRoomsForRandomJoin()
  ↓
    ├─→ Available rooms found?
    │   ├─→ YES: Pick random room
    │   │   └─→ _handleJoinRoom() → User joins existing game
    │   │
    │   └─→ NO: Create new room
    │       ├─→ RoomManager.createRoom()
    │       ├─→ Trigger 'room_created' hook
    │       ├─→ Trigger 'room_joined' hook
    │       ├─→ Send 'create_room_success' with is_random_join=true
    │       └─→ Auto-start: _gameCoordinator.handle('start_match')
    │           └─→ GameEventCoordinator._handleStartMatch()
    │               └─→ Auto-creates CPU opponents
    │               └─→ Initializes game state
    │               └─→ Game begins
```

## Default Settings for Auto-Created Rooms

When no available rooms are found, a new room is created with these defaults:

- **Max Players**: 4
- **Min Players**: 2
- **Game Type**: `'classic'`
- **Permission**: `'public'`
- **Auto Start**: `true`
- **Turn Time Limit**: 30 seconds (default from RoomManager)

## Error Handling

### Frontend
- WebSocket connection check before emitting event
- Loading state during operation
- Error messages via SnackBar
- Listens for `join_room_error` events

### Backend
- Try-catch blocks around critical operations
- Error responses sent to client
- Logging for debugging
- Graceful fallback if room creation fails

## Files Modified

### Frontend
1. `flutter_base_05/lib/modules/recall_game/screens/lobby_room/widgets/join_random_game_widget.dart` (NEW)
2. `flutter_base_05/lib/modules/recall_game/screens/lobby_room/lobby_screen.dart`
3. `flutter_base_05/lib/modules/recall_game/utils/recall_game_helpers.dart`
4. `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`
5. `flutter_base_05/lib/core/managers/websockets/ws_event_handler.dart`
6. `flutter_base_05/lib/modules/recall_game/managers/recall_event_manager.dart`

### Backend
1. `dart_bkend_base_01/lib/server/message_handler.dart`

## Testing Considerations

### Test Scenarios
1. **Join Existing Room**: Verify user joins a random available room
2. **Auto-Create Room**: Verify new room is created when none available
3. **Auto-Start**: Verify game starts immediately after room creation
4. **CPU Opponents**: Verify CPU players are created automatically
5. **Owner Flag**: Verify `isOwner` is `false` for auto-created rooms
6. **Error Handling**: Test with WebSocket disconnected, room full, etc.
7. **Multiple Users**: Test concurrent random joins

### Edge Cases
- No rooms available → Auto-create works
- All rooms full → Auto-create works
- All rooms in non-waiting phase → Auto-create works
- User already in a room → Should handle gracefully
- WebSocket disconnection → Error message shown

## Future Enhancements

### Planned Features
1. **Player Matching System**: Replace CPU opponent auto-creation with searching for available players who are also looking to join a random room
   - Queue system for players waiting to join
   - Matchmaking algorithm based on skill/level
   - Real-time player matching

2. **Level/Skill Filtering**: Filter available rooms by player skill level
   - Match players of similar skill
   - Prevent mismatched games

3. **Preference Matching**: Match players based on game preferences
   - Game type preferences
   - Turn time limit preferences
   - Max players preferences

4. **Queue System**: Implement a waiting queue for players
   - Players can wait in queue for matches
   - Automatic matching when enough players available
   - Queue status display

## Related Documentation

- [Game Creation System](./GAME_CREATION_SYSTEM.md) - Details on manual room creation
- [State Management](./STATE_SYSTEM.md) - Game state structure and management
- [Unified Game System](./UNIFIED_GAME_SYSTEM.md) - Overall game architecture

## Notes

- This is the **first implementation** of the random join feature
- CPU opponent creation is temporary - will be replaced with player matching
- The `is_random_join` flag is used to distinguish auto-created rooms from manually created ones
- Auto-start ensures immediate gameplay without waiting for manual start

