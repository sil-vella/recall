# API Reference

## WebSocketServer Class

### Overview
The `WebSocketServer` class manages WebSocket connections, session handling, and message routing for the Recall game server.

### Constructor
```dart
WebSocketServer()
```
Creates a new WebSocket server instance with room management and message handling capabilities.

### Properties

#### `connectionCount` → `int`
- **Description**: Returns the current number of active WebSocket connections
- **Type**: `int`
- **Example**: `5`

### Methods

#### `handleConnection(WebSocketChannel webSocket)`
- **Description**: Processes a new WebSocket connection
- **Parameters**:
  - `webSocket` (`WebSocketChannel`): The WebSocket channel to handle
- **Returns**: `void`
- **Behavior**:
  - Assigns a unique session ID to the connection
  - Sends a welcome message to the client
  - Sets up message listeners for incoming data
  - Handles connection cleanup on disconnect

**Example:**
```dart
final server = WebSocketServer();
server.handleConnection(webSocket);
```

#### `sendToSession(String sessionId, Map<String, dynamic> message)`
- **Description**: Sends a message to a specific client session
- **Parameters**:
  - `sessionId` (`String`): The target session identifier
  - `message` (`Map<String, dynamic>`): The message data to send
- **Returns**: `void`
- **Error Handling**: Logs errors if session not found or send fails

**Example:**
```dart
server.sendToSession('session_123', {
  'event': 'room_created',
  'room_id': 'room_456',
  'creator_id': 'player789'
});
```

#### `broadcastToRoom(String roomId, Map<String, dynamic> message)`
- **Description**: Broadcasts a message to all clients in a specific room
- **Parameters**:
  - `roomId` (`String`): The target room identifier
  - `message` (`Map<String, dynamic>`): The message data to broadcast
- **Returns**: `void`
- **Behavior**: Iterates through all sessions in the room and sends the message

**Example:**
```dart
server.broadcastToRoom('room_456', {
  'event': 'player_joined',
  'room_id': 'room_456',
  'user_id': 'player789',
  'player_count': 2
});
```

## RoomManager Class

### Overview
The `RoomManager` class handles the creation, management, and lifecycle of game rooms.

### Constructor
```dart
RoomManager()
```
Creates a new room manager instance.

### Properties

#### `roomCount` → `int`
- **Description**: Returns the current number of active rooms
- **Type**: `int`
- **Example**: `3`

### Methods

#### `createRoom(String creatorSessionId, String userId)` → `String`
- **Description**: Creates a new game room
- **Parameters**:
  - `creatorSessionId` (`String`): The session ID of the room creator
  - `userId` (`String`): The user identifier of the creator
- **Returns**: `String` - The generated room ID
- **Behavior**: Creates a new room and adds the creator as the first player

**Example:**
```dart
final roomManager = RoomManager();
final roomId = roomManager.createRoom('session_123', 'player456');
print('Created room: $roomId'); // Output: Created room: room_1761652434996
```

#### `joinRoom(String roomId, String sessionId, String userId)` → `bool`
- **Description**: Adds a player to an existing room
- **Parameters**:
  - `roomId` (`String`): The target room identifier
  - `sessionId` (`String`): The player's session ID
  - `userId` (`String`): The user identifier
- **Returns**: `bool` - `true` if successful, `false` if room not found
- **Behavior**: Adds the session to the room's player list

**Example:**
```dart
final success = roomManager.joinRoom('room_456', 'session_789', 'player123');
if (success) {
  print('Successfully joined room');
} else {
  print('Failed to join room');
}
```

#### `leaveRoom(String sessionId)` → `void`
- **Description**: Removes a player from their current room
- **Parameters**:
  - `sessionId` (`String`): The player's session ID
- **Returns**: `void`
- **Behavior**: Removes the session from the room and destroys the room if empty

**Example:**
```dart
roomManager.leaveRoom('session_123');
```

#### `getRoom(String roomId)` → `Room?`
- **Description**: Retrieves a room by its ID
- **Parameters**:
  - `roomId` (`String`): The room identifier
- **Returns**: `Room?` - The room object or `null` if not found

**Example:**
```dart
final room = roomManager.getRoom('room_456');
if (room != null) {
  print('Room found: ${room.roomId}');
} else {
  print('Room not found');
}
```

#### `getSessionsInRoom(String roomId)` → `List<String>`
- **Description**: Gets all session IDs in a specific room
- **Parameters**:
  - `roomId` (`String`): The room identifier
- **Returns**: `List<String>` - List of session IDs in the room

**Example:**
```dart
final sessions = roomManager.getSessionsInRoom('room_456');
print('Sessions in room: ${sessions.length}');
```

#### `getAllRooms()` → `List<Room>`
- **Description**: Gets all active rooms
- **Returns**: `List<Room>` - List of all room objects

**Example:**
```dart
final rooms = roomManager.getAllRooms();
print('Total rooms: ${rooms.length}');
```

#### `getRoomForSession(String sessionId)` → `String?`
- **Description**: Gets the room ID for a specific session
- **Parameters**:
  - `sessionId` (`String`): The session identifier
- **Returns**: `String?` - The room ID or `null` if not in any room

**Example:**
```dart
final roomId = roomManager.getRoomForSession('session_123');
if (roomId != null) {
  print('Session is in room: $roomId');
}
```

#### `handleDisconnect(String sessionId)` → `void`
- **Description**: Handles session disconnection cleanup
- **Parameters**:
  - `sessionId` (`String`): The disconnected session identifier
- **Returns**: `void`
- **Behavior**: Removes the session from any room and cleans up associations

**Example:**
```dart
roomManager.handleDisconnect('session_123');
```

## Room Class

### Overview
The `Room` class represents a game room with players and metadata.

### Constructor
```dart
Room(String roomId, String creatorId)
```
- **Parameters**:
  - `roomId` (`String`): Unique room identifier
  - `creatorId` (`String`): User ID of the room creator

### Properties

#### `roomId` → `String`
- **Description**: Unique room identifier
- **Format**: `room_{timestamp}`
- **Example**: `"room_1761652434996"`

#### `creatorId` → `String`
- **Description**: User ID of the room creator
- **Example**: `"player123"`

#### `sessionIds` → `List<String>`
- **Description**: List of connected session IDs in the room
- **Type**: `List<String>`
- **Example**: `["session_123", "session_456"]`

#### `createdAt` → `DateTime`
- **Description**: Room creation timestamp
- **Type**: `DateTime`
- **Example**: `DateTime(2025, 10, 28, 12, 53, 54)`

### Methods

#### `toJson()` → `Map<String, dynamic>`
- **Description**: Serializes the room to JSON format
- **Returns**: `Map<String, dynamic>` - JSON representation of the room
- **Format**:
  ```json
  {
    "room_id": "room_1761652434996",
    "creator_id": "player123",
    "player_count": 2,
    "created_at": "2025-10-28T12:53:54.997387"
  }
  ```

**Example:**
```dart
final room = Room('room_456', 'player123');
final json = room.toJson();
print(json['room_id']); // Output: room_456
```

## MessageHandler Class

### Overview
The `MessageHandler` class processes incoming WebSocket messages and routes them to appropriate handlers.

### Constructor
```dart
MessageHandler(RoomManager roomManager, WebSocketServer server)
```
- **Parameters**:
  - `roomManager` (`RoomManager`): Room management instance
  - `server` (`WebSocketServer`): WebSocket server instance

### Methods

#### `handleMessage(String sessionId, Map<String, dynamic> data)` → `void`
- **Description**: Processes incoming messages and routes them to appropriate handlers
- **Parameters**:
  - `sessionId` (`String`): Source session identifier
  - `data` (`Map<String, dynamic>`): Parsed message data
- **Returns**: `void`
- **Behavior**: Routes to appropriate event handler based on event type

**Example:**
```dart
final handler = MessageHandler(roomManager, server);
handler.handleMessage('session_123', {
  'event': 'create_room',
  'user_id': 'player456'
});
```

### Private Methods

#### `_handlePing(String sessionId)` → `void`
- **Description**: Handles ping requests
- **Parameters**: `sessionId` (`String`): Source session identifier
- **Behavior**: Sends pong response with timestamp

#### `_handleCreateRoom(String sessionId, Map<String, dynamic> data)` → `void`
- **Description**: Handles room creation requests
- **Parameters**:
  - `sessionId` (`String`): Source session identifier
  - `data` (`Map<String, dynamic>`): Message data
- **Behavior**: Creates room and sends confirmation

#### `_handleJoinRoom(String sessionId, Map<String, dynamic> data)` → `void`
- **Description**: Handles room join requests
- **Parameters**:
  - `sessionId` (`String`): Source session identifier
  - `data` (`Map<String, dynamic>`): Message data
- **Behavior**: Joins room and broadcasts to all players

#### `_handleLeaveRoom(String sessionId)` → `void`
- **Description**: Handles room leave requests
- **Parameters**: `sessionId` (`String`): Source session identifier
- **Behavior**: Leaves room and notifies remaining players

#### `_handleListRooms(String sessionId)` → `void`
- **Description**: Handles room listing requests
- **Parameters**: `sessionId` (`String`): Source session identifier
- **Behavior**: Sends list of all available rooms

## Error Handling

### Common Exceptions

#### `FormatException`
- **Cause**: Invalid JSON format in incoming messages
- **Handling**: Send error message to client
- **Example**: `"Invalid message format"`

#### `NoSuchMethodError`
- **Cause**: Missing required fields in message data
- **Handling**: Send error message to client
- **Example**: `"Missing event field"`

### Error Response Format
```json
{
  "event": "error",
  "message": "Error description"
}
```

## Usage Examples

### Basic Server Setup
```dart
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'lib/server/websocket_server.dart';

void main() async {
  final wsServer = WebSocketServer();
  
  final handler = webSocketHandler((webSocket) {
    wsServer.handleConnection(webSocket);
  });
  
  final server = await shelf_io.serve(handler, '0.0.0.0', 8080);
  print('Server running on ws://${server.address.host}:${server.port}');
}
```

### Room Management
```dart
final roomManager = RoomManager();

// Create room
final roomId = roomManager.createRoom('session_123', 'player456');

// Join room
final success = roomManager.joinRoom(roomId, 'session_789', 'player789');

// Get room info
final room = roomManager.getRoom(roomId);
print('Room has ${room?.sessionIds.length} players');

// Leave room
roomManager.leaveRoom('session_789');
```

### Message Broadcasting
```dart
final server = WebSocketServer();

// Send to specific session
server.sendToSession('session_123', {
  'event': 'room_created',
  'room_id': 'room_456'
});

// Broadcast to room
server.broadcastToRoom('room_456', {
  'event': 'player_joined',
  'user_id': 'player789',
  'player_count': 2
});
```

---

*This API reference covers the current WebSocket server implementation. Additional methods and classes will be documented as they are added.*
