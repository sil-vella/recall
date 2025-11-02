# Game Creation Hooks - Dart Backend

## Overview

This document describes the hook-based game creation system in the Dart backend, which mirrors the Python backend's behavior for automatically creating and managing game instances when rooms are created and joined.

## Architecture

The Dart backend uses the `HooksManager` system to respond to room lifecycle events and automatically create/manage game instances.

### Key Components

1. **RecallGameModule** (`lib/modules/recall_game/recall_game_main.dart`)
   - Registers hook callbacks for room lifecycle events
   - Manages game creation, player addition, and cleanup

2. **HooksManager** (`lib/managers/hooks_manager.dart`)
   - Event-driven system for registering and triggering callbacks
   - Allows multiple callbacks per hook with priority ordering

3. **GameStateStore** (`lib/modules/recall_game/services/game_state_store.dart`)
   - In-memory storage for game state per room
   - Provides mutable state access for GameRound instances

4. **GameRegistry** (`lib/modules/recall_game/services/game_registry.dart`)
   - Manages GameRound instances per room
   - Provides ServerGameStateCallback for GameRound-to-server communication

## Hook Flow

### 1. room_created Hook

**Triggered by**: `MessageHandler._handleCreateRoom()` after successful room creation

**What happens**:
1. Creates a GameRound instance via `GameRegistry.instance.getOrCreate(roomId, server)`
2. Initializes minimal game state in `GameStateStore`:
   - `gameId`, `gameName`, `gameType`
   - `maxPlayers`, `minPlayers`
   - `isGameActive: false`
   - `gamePhase: 'waiting_for_players'`
   - Empty `drawPile`, `discardPile`, `originalDeck`
   - Creator added as first player with initial state
3. Sends `game_state_updated` event to the creator with initial state

**Player Initial State**:
```dart
{
  'id': ownerId,
  'name': 'Player_<userId>',
  'isHuman': true,
  'status': 'waiting',
  'hand': [],
  'visible_cards': [],
  'points': 0,
  'known_cards': {},
  'collection_rank_cards': [],
}
```

### 2. room_joined Hook

**Triggered by**: `MessageHandler._handleJoinRoom()` after successful join

**What happens**:
1. Retrieves existing game state from `GameStateStore`
2. Checks if player already exists (skip if duplicate)
3. Adds new player to `players` array with initial state
4. Sends `game_state_updated` snapshot to the joining player
5. Broadcasts `recall_new_player_joined` event to all players in the room

**Events sent**:
- To joiner: `game_state_updated` (full snapshot)
- To room: `recall_new_player_joined` (player info + current state)

### 3. leave_room Hook

**Triggered by**: `MessageHandler._handleLeaveRoom()` after player leaves

**What happens**:
1. Removes player from `players` array in game state
2. Updates game state in `GameStateStore`

### 4. room_closed Hook

**Triggered by**: `RoomManager.onRoomClosed` when room becomes empty

**What happens**:
1. Disposes GameRound instance via `GameRegistry.instance.dispose(roomId)`
2. Clears game state from `GameStateStore.instance.clear(roomId)`
3. Complete cleanup of all game resources

## Comparison with Python Backend

### Similarities
- Both use hook systems for automatic game creation
- Both create game on `room_created` and add players on `room_joined`
- Both send `game_state_updated` and `recall_new_player_joined` events
- Both clean up on `room_closed`

### Differences

| Aspect | Python Backend | Dart Backend |
|--------|----------------|--------------|
| Game Logic Location | `GameState` class | `RecallGameRound` class |
| State Storage | `GameStateManager.active_games` | `GameStateStore` singleton |
| Hook Registration | `GameStateManager._register_hook_callbacks()` | `RecallGameModule._registerHooks()` |
| Session Mapping | `GameState.player_sessions` | `WebSocketServer._sessionToUser` |
| Hook System | `HooksManager` (Python) | `HooksManager` (Dart) |

## Event Flow Diagram

```
Room Created (Flutter) 
    ↓
MessageHandler._handleCreateRoom()
    ↓
RoomManager.createRoom()
    ↓
MessageHandler triggers 'room_created' hook
    ↓
RecallGameModule._onRoomCreated()
    ↓
GameRegistry.getOrCreate(roomId)  ← Creates GameRound instance
    ↓
GameStateStore.mergeRoot(roomId)  ← Initialize minimal state
    ↓
Send 'game_state_updated' to creator
```

```
Player Joins (Flutter)
    ↓
MessageHandler._handleJoinRoom()
    ↓
RoomManager.joinRoom()
    ↓
MessageHandler triggers 'room_joined' hook
    ↓
RecallGameModule._onRoomJoined()
    ↓
Add player to GameStateStore
    ↓
Send 'game_state_updated' snapshot to joiner
    ↓
Broadcast 'recall_new_player_joined' to room
```

## Flutter Client Expectations

The Flutter client expects the following events after room creation and joining:

### After create_room:
1. `create_room_success` (from MessageHandler)
2. `room_joined` (auto-join creator)
3. `game_state_updated` (initial state with creator as first player)

### After join_room:
1. `join_room_success` (from MessageHandler)
2. `room_joined` (confirmation)
3. `game_state_updated` (full snapshot)
4. `recall_new_player_joined` (broadcast to all)

## Testing

To test the hook system:

1. **Create a room**:
   ```dart
   // Flutter sends:
   {
     'event': 'create_room',
     'user_id': '<userId>',
     'max_players': 4,
     'min_players': 2,
     'game_type': 'multiplayer'
   }
   
   // Expect to receive:
   // 1. create_room_success
   // 2. room_joined
   // 3. game_state_updated with initial state
   ```

2. **Join a room**:
   ```dart
   // Flutter sends:
   {
     'event': 'join_room',
     'room_id': '<roomId>',
     'user_id': '<userId>'
   }
   
   // Expect to receive:
   // 1. join_room_success
   // 2. room_joined
   // 3. game_state_updated (snapshot)
   // 4. recall_new_player_joined (broadcast)
   ```

3. **Leave a room**:
   ```dart
   // Flutter sends:
   {
     'event': 'leave_room'
   }
   
   // Expect:
   // - Player removed from game state
   // - leave_room_success event
   // - player_left broadcast
   ```

## Future Enhancements

1. **Computer Players**: Add logic to add computer players when a room is created
2. **Auto-Start**: Implement auto-start logic when minimum players reached
3. **Game Settings**: Support additional game settings (turn time limit, special rules)
4. **Persistence**: Add database persistence for game states
5. **Reconnection**: Handle player reconnection to existing games

## Related Files

- `lib/modules/recall_game/recall_game_main.dart` - Hook registration and callbacks
- `lib/server/message_handler.dart` - Hook triggers
- `lib/server/websocket_server.dart` - RecallGameModule initialization
- `lib/managers/hooks_manager.dart` - Hook system implementation
- `lib/modules/recall_game/services/game_state_store.dart` - State storage
- `lib/modules/recall_game/services/game_registry.dart` - GameRound management

