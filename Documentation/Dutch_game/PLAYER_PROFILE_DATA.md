# Player Profile Data Implementation

## Overview

This document describes the implementation of user profile data (full name and profile picture) in the Dutch game system. Profile data is fetched from the database and displayed in the game UI, allowing players to see opponent names and profile pictures during gameplay.

---

## Implementation Summary

### ✅ Completed Features

1. **Profile Picture Sync** - Automatically syncs Google profile picture during Google Sign-In
2. **Full Name Display** - Shows full name (first_name + last_name) with fallback to username
3. **Profile Picture Display** - Shows user profile pictures in game UI with fallback to default icon
4. **Public API Endpoint** - New endpoint for fetching user profile by userId (for Dart backend)

---

## Data Flow

### 1. Profile Data Storage

**Location**: MongoDB `users` collection

**Schema**:
```json
{
  "profile": {
    "first_name": "John",
    "last_name": "Doe",
    "picture": "https://lh3.googleusercontent.com/..."
  }
}
```

**When Updated**:
- During Google Sign-In (new users, existing users, guest conversions)
- Stored in `profile.picture` field
- Updated on each Google Sign-In to get latest picture

### 2. Profile Data Fetching

**Backend Flow**:
1. Player joins game (room_created or room_joined hook)
2. Dart backend calls Python API: `POST /public/users/profile`
3. Python backend fetches user from database
4. Returns: `username`, `full_name`, `first_name`, `last_name`, `profile_picture`
5. Dart backend includes in player object

**API Endpoint**: `POST /public/users/profile`
- **Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`
- **Method**: `get_user_profile_by_id()`
- **Auth**: Public (no JWT required)
- **Used By**: Dart backend WebSocket server

### 3. Player Object Structure

**In Game State** (`game_state['players']`):
```json
{
  "id": "sessionId",
  "name": "John Doe",  // Full name (preferred) or username (fallback) or "Player_XXX" (default)
  "profile_picture": "https://...",  // Optional: URL to profile picture
  "userId": "ObjectId",  // Optional: MongoDB user ID
  "isHuman": true,
  "status": "waiting",
  "hand": [],
  "points": 0,
  ...
}
```

**Name Resolution Priority**:
1. `full_name` (first_name + last_name) - if available
2. `username` - if full_name not available
3. `"Player_XXX"` - default fallback

### 4. Frontend Display

**Location**: `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`

**Implementation**:
- `_buildOpponentCard()` - Reads `player['name']` and `player['profile_picture']`
- `_buildPlayerProfilePicture()` - Displays profile picture with fallback to icon
- Name display: Uses full name with fallback chain (full_name → name → username → default)

**Profile Picture Display**:
- For opponents: Uses `player['profile_picture']` from game state
- For current user: Uses `StateManager` login state (existing behavior)
- Fallback: Default `Icons.person` icon if picture unavailable or fails to load

---

## API Endpoints

### Get User Profile by ID (Public)

**Endpoint**: `POST /public/users/profile`

**Request**:
```json
{
  "user_id": "userId"
}
```

**Response**:
```json
{
  "success": true,
  "user_id": "userId",
  "username": "username",
  "full_name": "First Last",
  "first_name": "First",
  "last_name": "Last",
  "profile_picture": "https://..."
}
```

**Implementation**: `python_base_04/core/modules/user_management_module/user_management_main.py::get_user_profile_by_id()`

### Get Current User Profile (JWT Protected)

**Endpoint**: `GET /userauth/users/profile`

**Request Headers**: `Authorization: Bearer {jwt_token}`

**Response**:
```json
{
  "user_id": "userId",
  "email": "user@example.com",
  "username": "username",
  "profile": {
    "first_name": "First",
    "last_name": "Last",
    "picture": "https://...",
    ...
  },
  "modules": {...}
}
```

**Implementation**: `python_base_04/core/modules/user_management_module/user_management_main.py::get_user_profile()`

---

## WebSocket Events

### `dutch_new_player_joined`

Sent when a new player joins a game room.

**Event Structure**:
```json
{
  "event": "dutch_new_player_joined",
  "room_id": "room_xxx",
  "joined_player": {
    "user_id": "userId",
    "session_id": "sessionId",
    "name": "John Doe",
    "profile_picture": "https://...",
    "joined_at": "2025-01-XX..."
  },
  "game_state": {
    "players": [
      {
        "id": "sessionId",
        "name": "John Doe",
        "profile_picture": "https://...",
        ...
      }
    ]
  }
}
```

### `game_state_updated`

Sent when game state changes. Player objects include profile data.

**Player Object in game_state**:
```json
{
  "id": "sessionId",
  "name": "John Doe",
  "profile_picture": "https://...",
  "isHuman": true,
  "status": "playing_card",
  "hand": [...],
  "points": 15,
  ...
}
```

---

## Backend Implementation

### Dart Backend

**Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/dutch_game_main.dart`

**Methods**:
- `_onRoomCreated()` - Fetches creator profile when room is created
- `_onRoomJoined()` - Fetches joiner profile when player joins

**Profile Fetching**:
```dart
final profileResult = await server.pythonClient.getUserProfile(userId);
if (profileResult['success'] == true) {
  final fullName = profileResult['full_name'];
  final username = profileResult['username'];
  final profilePicture = profileResult['profile_picture'];
  
  // Use full name if available, otherwise username, otherwise default
  String playerName = (fullName != null && fullName.isNotEmpty) 
      ? fullName 
      : (username.isNotEmpty) 
          ? username 
          : 'Player_XXX';
  
  // Include in player object
  players.add({
    'id': sessionId,
    'name': playerName,
    if (profilePicture != null && profilePicture.isNotEmpty) 
      'profile_picture': profilePicture,
    ...
  });
}
```

**API Client**: `dart_bkend_base_01/lib/services/python_api_client.dart::getUserProfile()`

### Python Backend

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Method**: `get_user_profile_by_id()`

**Process**:
1. Receives `user_id` in POST body
2. Fetches user from database (handles ObjectId conversion)
3. Extracts profile data: `first_name`, `last_name`, `picture`, `username`
4. Builds `full_name` (first_name + last_name, or empty string)
5. Returns structured response

---

## Frontend Implementation

### Profile Picture Widget

**Location**: `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`

**Method**: `_buildPlayerProfilePicture(String playerId, {String? profilePictureUrl})`

**Behavior**:
- Accepts optional `profilePictureUrl` parameter (for opponents from player data)
- For current user: Gets from `StateManager` login state
- For opponents: Uses `profilePictureUrl` from player object
- Displays `Image.network` with loading indicator and error fallback
- Falls back to `Icons.person` if picture unavailable

### Name Display

**Location**: `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`

**Method**: `_buildOpponentCard()`

**Name Resolution**:
```dart
final fullName = player['full_name']?.toString();
final playerNameRaw = player['name']?.toString();
final username = player['username']?.toString();
final playerName = (fullName != null && fullName.isNotEmpty) 
    ? fullName 
    : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
        ? playerNameRaw 
        : (username != null && username.isNotEmpty) 
            ? username 
            : 'Unknown Player';
```

---

## Schema Validation

### State Schema

**Location**: `dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/state_queue_validator.dart`

**Validation**: Player objects are stored in `game_state['players']` which is validated as a `List` type. The internal structure of player objects is not validated (flexible Maps), so `profile_picture` and `full_name` fields are automatically supported.

### Event Schema

**Location**: `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_listener_validator.dart`

**Validation**: Events like `dutch_new_player_joined` and `game_state_updated` validate top-level fields (e.g., `joined_player`, `game_state`) as Map types, but do not validate internal player object structure. New fields are automatically supported.

---

## Data Storage Locations

### Backend (Database)
- **Location**: MongoDB `users` collection
- **Field**: `profile.picture` (URL string)
- **Field**: `profile.first_name` (string)
- **Field**: `profile.last_name` (string)

### Frontend (StateManager)
- **Location**: `StateManager` module state: `"login"`
- **Field**: `profilePicture` (URL string)
- **Field**: `profile` (full profile object)

### Game State (Player Objects)
- **Location**: `game_state['players']` array
- **Field**: `profile_picture` (URL string, optional)
- **Field**: `name` (full name or username, string)

---

## Error Handling

### Profile Fetching Failures

**Dart Backend**:
- If API call fails: Falls back to default name (`Player_XXX`)
- If profile picture unavailable: Player object doesn't include `profile_picture` field
- Logs warnings but continues with game creation/joining

**Frontend**:
- If profile picture fails to load: `Image.network` errorBuilder shows default icon
- If name unavailable: Falls back through chain (full_name → name → username → "Unknown Player")

### API Endpoint Errors

**400 Bad Request**: Missing `user_id` parameter
**404 Not Found**: User not found in database
**500 Internal Server Error**: Database connection or processing error

All errors return structured JSON with `success: false` and `error` message.

---

## Future Enhancements

### Potential Improvements

1. **Caching**: Cache profile data in Dart backend to reduce API calls
2. **Batch Fetching**: Fetch multiple user profiles in single API call
3. **Profile Updates**: Real-time profile picture updates during game
4. **Custom Avatars**: Allow users to upload custom profile pictures
5. **Profile Privacy**: Settings to control profile visibility in games

---

## Related Documentation

- [User Registration Documentation](../User_Registration/USER_REGISTRATION.md) - Profile picture sync implementation
- [State Management Documentation](./STATE_MANAGEMENT.md) - Player object structure
- [WebSocket Protocol Documentation](../dart_bkend_base_01/server_and_ws/PROTOCOL.md) - Event structures
- [API Reference Documentation](../flutter_base_05/API_REFERENCE.md) - API endpoint details

---

**Last Updated**: 2025-01-XX (Added player profile data implementation with full name and profile picture support)
