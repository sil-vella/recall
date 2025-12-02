# Event Emitter SessionId Verification

This document verifies that event emitters in both Flutter and Dart backend are properly passing and using `sessionId` as the player ID.

## Flutter Side - Event Emission

### RecallGameEventEmitter (`validated_event_emitter.dart`)

**Location**: `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`

#### SessionId Source
- **Line 242**: Adds `'session_id': _getSessionId()` to all event payloads
- **Line 413-419**: `_getSessionId()` retrieves from `_wsManager.socket?.id`

#### Player ID Assignment
- **Line 253-258**: For events needing `player_id`, sets `eventPayload['player_id'] = sessionId` ✅
- **Previously**: Was setting to `currentUserId` (from login state) ❌
- **Now**: Sets to `sessionId` ✅

#### Event Payload Structure
```dart
{
  'event_type': eventType,
  'session_id': sessionId,        // ✅ Always included
  'player_id': sessionId,         // ✅ For game action events (now sessionId, not userId)
  'timestamp': DateTime.now().toIso8601String(),
  ...validatedData,               // Event-specific fields
}
```

#### Events That Auto-Include player_id (as sessionId)
- `play_card`
- `replace_drawn_card`
- `play_drawn_card`
- `call_recall`
- `draw_card`
- `play_out_of_turn`
- `use_special_power`
- `same_rank_play`
- `jack_swap`
- `completed_initial_peek`
- `collect_from_discard`

### WebSocketManager (`websocket_manager.dart`)

**Location**: `flutter_base_05/lib/core/managers/websockets/websocket_manager.dart`

- **Line 867-870**: Also adds `user_id` to payload (for backward compatibility)
- **Line 872**: Emits event via `_socket!.emit(eventName, data)`
- The WebSocket connection itself provides `sessionId` to the backend

### Practice Mode Bridge (`practice_mode_bridge.dart`)

**Location**: `flutter_base_05/lib/modules/recall_game/practice/practice_mode_bridge.dart`

- **Line 85**: Routes events to coordinator with `_currentSessionId!`
- **Line 104**: Practice session ID format: `'practice_session_$userId'`
- Uses practice session ID directly as player ID ✅

---

## Backend Side - Event Reception

### Message Handler (`message_handler.dart`)

**Location**: `dart_bkend_base_01/lib/server/message_handler.dart`

#### Event Reception
- **Line 25**: `handleMessage(String sessionId, Map<String, dynamic> data)`
- **Line 130**: Receives `sessionId` from WebSocket connection (not from payload)
- **Line 594-598**: Routes game events to `_gameCoordinator.handle(sessionId, event, data)`

**Key Point**: Backend receives `sessionId` as a **parameter** from the WebSocket connection, not from the event payload.

### Game Event Coordinator (`game_event_coordinator.dart`)

**Location**: `dart_bkend_base_01/lib/modules/recall_game/backend_core/coordinator/game_event_coordinator.dart`

#### Player ID Resolution
- **Line 44-84**: `_getPlayerIdFromSession(String sessionId, String roomId)`
  - **Previously**: Tried to match by `userId` ❌
  - **Now**: Returns `sessionId` directly after verifying player exists ✅
  ```dart
  // Player ID is now sessionId - verify player exists in game
  final playerExists = players.any((p) => p['id'] == sessionId);
  if (playerExists) {
    return sessionId; // Player ID = sessionId
  }
  ```

#### Event Handling
- **Line 87**: `handle(String sessionId, String event, Map<String, dynamic> data)`
- **Line 88**: Gets `roomId` from session
- **Line 110, 121, 181**: Uses `_getPlayerIdFromSession(sessionId, roomId)` to get player ID ✅

#### Special Cases

1. **same_rank_play** (Line 129-135):
   - **Previously**: Used `data['player_id']` directly ❌
   - **Now**: Uses `_getPlayerIdFromSession(sessionId, roomId)` first, falls back to `data['player_id']` ✅

2. **queen_peek** (Line 137-157):
   - **Previously**: Used `data['user_id']` or `data['player_id']` ❌
   - **Now**: Uses `_getPlayerIdFromSession(sessionId, roomId)` first, falls back to `data['player_id']` ✅

3. **jack_swap** (Line 159-177):
   - Uses `data['first_player_id']` and `data['second_player_id']` from event
   - **Note**: These are the IDs of the two players whose cards are being swapped
   - These should be sessionIds (from the event payload where they were set)
   - ✅ Correct as-is (these are target players, not necessarily the current player)

---

## Complete Event Flow

### Example: `play_card` Event

#### 1. Flutter Side - Event Emission
```dart
// PlayerAction.playerPlayCard() creates action
PlayerAction.playerPlayCard(gameId: 'room_123', cardId: 'card_1')

// RecallGameEventEmitter.emit() adds sessionId
{
  'event_type': 'play_card',
  'session_id': '550e8400-e29b-41d4-a716-446655440000',  // ✅ From socket.id
  'player_id': '550e8400-e29b-41d4-a716-446655440000',  // ✅ Now sessionId (was userId)
  'game_id': 'room_123',
  'card_id': 'card_1',
  'timestamp': '2024-01-15T10:30:00.000Z',
}

// WebSocketManager.sendCustomEvent() adds user_id (backward compatibility)
{
  ...payload above,
  'user_id': 'user_123',  // For backward compatibility
}

// Emitted via WebSocket
_socket!.emit('play_card', payload)
```

#### 2. Backend Side - Event Reception
```dart
// WebSocketServer receives event
_onMessage(sessionId: '550e8400-e29b-41d4-a716-446655440000', message: payload)

// MessageHandler routes to coordinator
_gameCoordinator.handle(
  sessionId: '550e8400-e29b-41d4-a716-446655440000',  // ✅ From WebSocket connection
  event: 'play_card',
  data: payload
)

// GameEventCoordinator gets player ID
final playerId = _getPlayerIdFromSession(sessionId, roomId)
// Returns: '550e8400-e29b-41d4-a716-446655440000' ✅ (sessionId)

// Processes action with correct player ID
await round.handlePlayCard(cardId, playerId: playerId, ...)
```

---

## Verification Checklist

### Flutter Side ✅
- [x] `_getSessionId()` retrieves from `_wsManager.socket?.id`
- [x] `session_id` is added to all event payloads
- [x] `player_id` is set to `sessionId` (not `userId`) for game action events
- [x] Practice mode uses practice session ID correctly

### Backend Side ✅
- [x] `sessionId` is received from WebSocket connection parameter
- [x] `_getPlayerIdFromSession()` returns `sessionId` directly (after verification)
- [x] All game events use `_getPlayerIdFromSession(sessionId, roomId)` to get player ID
- [x] `same_rank_play` and `queen_peek` now use `sessionId` as primary source
- [x] `jack_swap` correctly uses player IDs from event data (target players)

---

## Summary

✅ **CONFIRMED**: Event emitters are now correctly passing and using `sessionId` as the player ID:

1. **Flutter**: Sets `player_id = sessionId` in event payloads ✅
2. **Backend**: Receives `sessionId` from WebSocket connection ✅
3. **Backend**: Uses `sessionId` directly as player ID (after verification) ✅
4. **Backend**: `_getPlayerIdFromSession()` simplified to return `sessionId` ✅

The refactoring is complete and consistent across both Flutter and Dart backend.

