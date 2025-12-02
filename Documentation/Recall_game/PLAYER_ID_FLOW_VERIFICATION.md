# Player ID Flow Verification

This document traces the complete flow from room creation to player addition, confirming that **player ID = sessionId** at every step.

## Flow 1: Regular Room Creation

### Step 1: Room Creation Request
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Function**: `_handleCreateRoom(String sessionId, Map<String, dynamic> data)`
- **Line 93**: Receives `sessionId` as parameter
- **Line 107**: Calls `_roomManager.createRoom(sessionId, userId, ...)` - passes `sessionId` as first parameter

### Step 2: Trigger room_created Hook
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Lines 143-153**: 
```dart
_server.triggerHook('room_created', data: {
  'room_id': roomId,
  'owner_id': room.ownerId,
  'session_id': sessionId, // ✅ sessionId included in hook data
  // ... other fields
});
```

### Step 3: Game Creation Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomCreated(Map<String, dynamic> data)`
- **Line 45**: Extracts `sessionId = data['session_id']`
- **Line 50**: Validates `sessionId != null`
- **Line 80**: Creates player with `'id': sessionId` ✅
```dart
'players': <Map<String, dynamic>>[
  {
    'id': sessionId, // ✅ Player ID = sessionId
    'name': 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}',
    // ... other player fields
  }
]
```

### Step 4: Auto-Join Creator (room_joined Hook)
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Lines 167-176**:
```dart
_server.triggerHook('room_joined', data: {
  'room_id': roomId,
  'session_id': sessionId, // ✅ sessionId included
  'user_id': userId, // Kept for backward compatibility
  // ... other fields
});
```

### Step 5: Player Join Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomJoined(Map<String, dynamic> data)`
- **Line 123**: Extracts `sessionId = data['session_id']`
- **Line 137**: Checks if player exists: `players.any((p) => p['id'] == sessionId)` ✅
- **Line 138-142**: If player already exists (from `_onRoomCreated`), skips duplicate addition ✅
- **Line 147**: If new player, creates with `'id': sessionId` ✅

**Result**: Creator player is created in `_onRoomCreated` with `id = sessionId`. The `room_joined` hook finds the existing player and doesn't create a duplicate.

---

## Flow 2: Random Join - Creating New Room

### Step 1: Random Join Request
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Function**: `_handleJoinRandomGame(String sessionId, Map<String, dynamic> data)`
- **Line 381**: Receives `sessionId` as parameter
- **Line 409**: Calls `_roomManager.createRoom(sessionId, userId, ...)` - passes `sessionId`

### Step 2: Trigger room_created Hook
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Lines 444-454**:
```dart
_server.triggerHook('room_created', data: {
  'room_id': roomId,
  'owner_id': room.ownerId,
  'session_id': sessionId, // ✅ sessionId included
  // ... other fields
});
```

### Step 3: Game Creation Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomCreated(Map<String, dynamic> data)`
- **Line 45**: Extracts `sessionId = data['session_id']`
- **Line 80**: Creates player with `'id': sessionId` ✅

### Step 4: Auto-Join Creator (room_joined Hook)
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Lines 470-478**:
```dart
_server.triggerHook('room_joined', data: {
  'room_id': roomId,
  'session_id': sessionId, // ✅ sessionId included
  'user_id': userId, // Kept for backward compatibility
  // ... other fields
});
```

### Step 5: Player Join Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomJoined(Map<String, dynamic> data)`
- **Line 137**: Checks if player exists by `sessionId` ✅
- **Line 138-142**: Finds existing player, skips duplicate ✅

**Result**: Same as Flow 1 - player created with `id = sessionId`, no duplicate on join.

---

## Flow 3: Random Join - Joining Existing Room

### Step 1: Random Join Request
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Function**: `_handleJoinRandomGame(String sessionId, Map<String, dynamic> data)`
- **Line 381**: Receives `sessionId` as parameter
- **Line 397**: Calls `_handleJoinRoom(sessionId, {...})` - passes `sessionId`

### Step 2: Join Room Handler
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Function**: `_handleJoinRoom(String sessionId, Map<String, dynamic> data)`
- **Line 189**: Receives `sessionId` as parameter
- **Line 281-289**: Triggers `room_joined` hook with `'session_id': sessionId` ✅

### Step 3: Player Join Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomJoined(Map<String, dynamic> data)`
- **Line 123**: Extracts `sessionId = data['session_id']`
- **Line 137**: Checks if player exists: `players.any((p) => p['id'] == sessionId)` ✅
- **Line 147**: Creates new player with `'id': sessionId` ✅

**Result**: New player added with `id = sessionId`.

---

## Flow 4: Regular Join Room

### Step 1: Join Room Request
**File**: `dart_bkend_base_01/lib/server/message_handler.dart`
**Function**: `_handleJoinRoom(String sessionId, Map<String, dynamic> data)`
- **Line 189**: Receives `sessionId` as parameter
- **Line 281-289**: Triggers `room_joined` hook with `'session_id': sessionId` ✅

### Step 2: Player Join Hook Handler
**File**: `dart_bkend_base_01/lib/modules/recall_game/recall_game_main.dart`
**Function**: `_onRoomJoined(Map<String, dynamic> data)`
- **Line 123**: Extracts `sessionId = data['session_id']`
- **Line 147**: Creates player with `'id': sessionId` ✅

**Result**: Player added with `id = sessionId`.

---

## Verification Summary

### ✅ Confirmed: Player ID = sessionId at Every Step

| Flow | Step | Location | Player ID Source | Status |
|------|------|----------|------------------|--------|
| **Room Creation** | Hook Trigger | `message_handler.dart:146` | `sessionId` from parameter | ✅ |
| **Room Creation** | Player Creation | `recall_game_main.dart:80` | `'id': sessionId` | ✅ |
| **Room Creation** | Join Hook | `message_handler.dart:170` | `sessionId` from parameter | ✅ |
| **Room Creation** | Join Check | `recall_game_main.dart:137` | Checks by `sessionId` | ✅ |
| **Random Join (New)** | Hook Trigger | `message_handler.dart:447` | `sessionId` from parameter | ✅ |
| **Random Join (New)** | Player Creation | `recall_game_main.dart:80` | `'id': sessionId` | ✅ |
| **Random Join (Existing)** | Join Hook | `message_handler.dart:281` | `sessionId` from parameter | ✅ |
| **Random Join (Existing)** | Player Creation | `recall_game_main.dart:147` | `'id': sessionId` | ✅ |
| **Regular Join** | Join Hook | `message_handler.dart:281` | `sessionId` from parameter | ✅ |
| **Regular Join** | Player Creation | `recall_game_main.dart:147` | `'id': sessionId` | ✅ |

### Key Points

1. **All hook triggers include `session_id`**: Both `room_created` and `room_joined` hooks now include `'session_id': sessionId` in their data.

2. **All player creations use `sessionId`**: 
   - `_onRoomCreated` creates player with `'id': sessionId` (line 80)
   - `_onRoomJoined` creates player with `'id': sessionId` (line 147)

3. **Duplicate prevention uses `sessionId`**: 
   - `_onRoomJoined` checks for existing players using `p['id'] == sessionId` (line 137)

4. **No dependency on `userId` for player ID**: 
   - `userId` is still passed for backward compatibility but is NOT used as player ID
   - Player ID is always `sessionId`

### Conclusion

✅ **CONFIRMED**: The logic is correct. Player IDs are consistently set to `sessionId` throughout the entire flow from room creation to player addition. The refactoring is complete and working as intended.

