# WebSocket Protocol Specification

## Message Format

All WebSocket messages use JSON format with the following structure:

```json
{
  "event": "string",
  "data": "object",
  "timestamp": "string (ISO 8601)"
}
```

## Event Types

### Client → Server Events

#### `ping`
Health check request.

**Request:**
```json
{
  "event": "ping"
}
```

**Response:**
```json
{
  "event": "pong",
  "timestamp": "2025-10-28T12:53:54.015292"
}
```

#### `create_room`
Create a new game room.

**Request:**
```json
{
  "event": "create_room",
  "user_id": "player123"
}
```

**Response:**
```json
{
  "event": "room_created",
  "room_id": "room_1761652434996",
  "creator_id": "player123"
}
```

#### `join_room`
Join an existing game room.

**Request:**
```json
{
  "event": "join_room",
  "room_id": "room_1761652434996",
  "user_id": "player456"
}
```

**Response to Joiner:**
```json
{
  "event": "room_joined",
  "room_id": "room_1761652434996",
  "user_id": "player456"
}
```

**Broadcast to Room:**
```json
{
  "event": "player_joined",
  "room_id": "room_1761652434996",
  "user_id": "player456",
  "player_count": 2
}
```

#### `leave_room`
Leave the current room.

**Request:**
```json
{
  "event": "leave_room"
}
```

**Response:**
```json
{
  "event": "room_left",
  "room_id": "room_1761652434996"
}
```

**Broadcast to Room:**
```json
{
  "event": "player_left",
  "room_id": "room_1761652434996",
  "player_count": 1
}
```

#### `list_rooms`
Get all available rooms.

**Request:**
```json
{
  "event": "list_rooms"
}
```

**Response:**
```json
{
  "event": "rooms_list",
  "rooms": [
    {
      "room_id": "room_1761652434996",
      "creator_id": "player123",
      "player_count": 2,
      "created_at": "2025-10-28T12:53:54.997387"
    }
  ],
  "total": 1
}
```

### Game Events (Acknowledge Only)

#### `start_match`
Start a game match.

**Request:**
```json
{
  "event": "start_match",
  "game_id": "room_123",
  "token": "jwt_token_here"
}
```

**Response:**
```json
{
  "event": "start_match_acknowledged",
  "original_event": "start_match",
  "session_id": "session_456",
  "message": "Event received and acknowledged",
  "timestamp": "2025-10-28T12:53:54.015292",
  "data": {
    "game_id": "room_123",
    "token": "jwt_token_here"
  }
}
```

#### `play_card`
Play a card from hand.

**Request:**
```json
{
  "event": "play_card",
  "game_id": "room_123",
  "card_id": "card_456",
  "token": "jwt_token_here"
}
```

**Response:**
```json
{
  "event": "play_card_acknowledged",
  "original_event": "play_card",
  "session_id": "session_456",
  "message": "Event received and acknowledged",
  "timestamp": "2025-10-28T12:53:54.015292",
  "data": {
    "game_id": "room_123",
    "card_id": "card_456",
    "token": "jwt_token_here"
  }
}
```

#### `draw_card`
Draw card from deck or discard pile.

**Request:**
```json
{
  "event": "draw_card",
  "game_id": "room_123",
  "source": "deck",
  "token": "jwt_token_here"
}
```

**Response:**
```json
{
  "event": "draw_card_acknowledged",
  "original_event": "draw_card",
  "session_id": "session_456",
  "message": "Event received and acknowledged",
  "timestamp": "2025-10-28T12:53:54.015292",
  "data": {
    "game_id": "room_123",
    "source": "deck",
    "token": "jwt_token_here"
  }
}
```

#### Other Game Events
The following events follow the same acknowledgment pattern:
- `discard_card` → `discard_card_acknowledged`
- `take_from_discard` → `take_from_discard_acknowledged`
- `call_recall` → `call_recall_acknowledged`
- `same_rank_play` → `same_rank_play_acknowledged`
- `jack_swap` → `jack_swap_acknowledged`
- `queen_peek` → `queen_peek_acknowledged`
- `completed_initial_peek` → `completed_initial_peek_acknowledged`

### Server → Client Events

#### `connected`
Sent when client successfully connects.

```json
{
  "event": "connected",
  "session_id": "42a0f96a-d8f5-400f-a3fa-4ae166256b38",
  "message": "Welcome to Recall Game Server",
  "authenticated": false
}
```

#### `authenticated`
Sent when JWT token validation succeeds.

```json
{
  "event": "authenticated",
  "session_id": "42a0f96a-d8f5-400f-a3fa-4ae166256b38",
  "user_id": "user_123",
  "message": "Authentication successful"
}
```

#### `authentication_failed`
Sent when JWT token validation fails.

```json
{
  "event": "authentication_failed",
  "message": "Invalid or expired token"
}
```

#### `authentication_error`
Sent when authentication service is unavailable.

```json
{
  "event": "authentication_error",
  "message": "Authentication service unavailable"
}
```

#### `error`
Error message sent for invalid requests.

```json
{
  "event": "error",
  "message": "Missing room_id"
}
```

## Error Handling

### Common Error Messages

| Error | Description | Cause |
|-------|-------------|-------|
| `"Missing event field"` | No event specified | Message missing `event` field |
| `"Invalid message format"` | Invalid JSON | Malformed JSON message |
| `"Unknown event: {event}"` | Unrecognized event | Event not in supported list |
| `"Missing room_id"` | Room ID required | `join_room` without `room_id` |
| `"Failed to join room: {room_id}"` | Room not found | Attempting to join non-existent room |

## Connection Lifecycle

### 1. Connection Establishment
```
Client → Server: WebSocket connection
Server → Client: {"event": "connected", "session_id": "...", "message": "..."}
```

### 2. Room Operations
```
Client → Server: {"event": "create_room", "user_id": "player123"}
Server → Client: {"event": "room_created", "room_id": "room_123", "creator_id": "player123"}

Client → Server: {"event": "join_room", "room_id": "room_123", "user_id": "player456"}
Server → Client: {"event": "room_joined", "room_id": "room_123", "user_id": "player456"}
Server → All in Room: {"event": "player_joined", "room_id": "room_123", "user_id": "player456", "player_count": 2}
```

### 3. Disconnection
```
Client → Server: WebSocket close
Server: Cleanup session and room associations
```

## Message Validation

### Required Fields
- `event`: Must be a string
- Event-specific fields as documented

### Optional Fields
- `user_id`: Defaults to session ID if not provided
- `timestamp`: Automatically added by server for responses

### Field Types
- `event`: String
- `room_id`: String (format: `room_{timestamp}`)
- `user_id`: String
- `session_id`: String (UUID v4)
- `player_count`: Integer
- `timestamp`: String (ISO 8601 format)
- `message`: String
- `rooms`: Array of room objects

## Rate Limiting (Future)

### Planned Limits
- **Ping**: 1 per second per connection
- **Room Operations**: 10 per minute per connection
- **General Messages**: 100 per minute per connection

### Rate Limit Response
```json
{
  "event": "error",
  "message": "Rate limit exceeded",
  "retry_after": 60
}
```

## Authentication (Future)

### Planned JWT Integration
```json
{
  "event": "authenticate",
  "token": "jwt_token_here"
}
```

**Response:**
```json
{
  "event": "authenticated",
  "user_id": "player123",
  "permissions": ["read", "write"]
}
```

## Game Events (Future)

### Planned Game Events
- `start_game`: Initialize game in room
- `play_card`: Play a card
- `draw_card`: Draw from deck
- `end_turn`: End current turn
- `call_recall`: Call recall phase
- `game_state`: Broadcast game state updates

### Example Game Event
```json
{
  "event": "play_card",
  "room_id": "room_123",
  "card": {
    "id": "card_456",
    "rank": "7",
    "suit": "hearts"
  },
  "player_id": "player123"
}
```

---

*This protocol specification covers the current WebSocket implementation. Additional game-specific events will be documented as they are implemented.*
