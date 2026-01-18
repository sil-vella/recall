# WebSocket Authentication Failure Analysis

## Overview
This document traces all instances where random match join/create room operations fail because WebSocket connection requires a logged-in user. The goal is to identify where we can auto-create a guest user if no user data is found in state and SharedPreferences.

## Flow Diagram

```
User Action (Join/Create Room)
    ↓
Check Coins (if applicable)
    ↓
ensureWebSocketReady() ← CRITICAL CHECKPOINT
    ↓
Check isLoggedIn in StateManager
    ↓
[IF NOT LOGGED IN] → Return false → Show error → Navigate to account screen
    ↓
[IF LOGGED IN] → Check WebSocketManager.isInitialized
    ↓
[IF NOT INITIALIZED] → WebSocketManager.initialize()
    ↓
    → Check LoginModule.hasValidToken()
    ↓
    → Get JWT token from LoginModule
    ↓
    → Connect WebSocket with token
    ↓
[IF INITIALIZED] → Check isConnected
    ↓
[IF NOT CONNECTED] → WebSocketManager.connect()
    ↓
Success → Proceed with room operation
```

## Critical Checkpoints

### 1. `ensureWebSocketReady()` - Primary Gatekeeper
**Location**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart:179`

**Flow**:
1. Checks `StateManager().getModuleState('login')['isLoggedIn']`
2. If `false` → Returns `false` immediately (line 188-190)
3. If `true` → Proceeds to initialize/connect WebSocket

**Called From**:
- `createRoom()` - line 43
- `joinRoom()` - line 88
- `joinRandomGame()` - line 256
- `lobby_screen.dart` - `_createRoom()` - line 145
- `lobby_screen.dart` - `_joinRoom()` - line 199
- `join_random_game_widget.dart` - `_handleJoinRandomGame()` - line 88
- `create_join_game_widget.dart` - `_joinRoom()` - line 194

### 2. `WebSocketManager.initialize()` - Token Validation
**Location**: `flutter_base_05/lib/core/managers/websockets/websocket_manager.dart:108`

**Flow**:
1. Gets `LoginModule` from ModuleManager (line 124)
2. Checks `loginModule.hasValidToken()` (line 130)
3. If `false` → Returns `false` (line 133)
4. Gets JWT token via `loginModule.getCurrentToken()` (line 137)
5. If token is `null` → Returns `false` (line 140)
6. Connects WebSocket with token in query/auth params (line 172-181)

**Failure Points**:
- No LoginModule available
- No valid JWT token
- Token retrieval fails

### 3. `LobbyScreen._initializeWebSocket()` - Screen-Level Check
**Location**: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart:49`

**Flow**:
1. Checks `StateManager().getModuleState('login')['isLoggedIn']` (line 56)
2. If `false` → Skips WebSocket initialization entirely (line 61-63)
3. Allows user to stay on lobby screen but cannot play

## Failure Instances

### Instance 1: Create Room
**File**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
**Method**: `createRoom()`
**Line**: 43-48

```dart
final isReady = await ensureWebSocketReady();
if (!isReady) {
  return {
    'success': false,
    'error': 'WebSocket not ready - cannot create room. Please ensure you are logged in.',
  };
}
```

**User Experience**:
- Error message returned in result
- No automatic navigation (calling code handles it)

**Called From**:
- `lobby_screen.dart` - `_createRoom()` - line 155

### Instance 2: Join Room
**File**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
**Method**: `joinRoom()`
**Line**: 88-94

```dart
final isReady = await ensureWebSocketReady();
if (!isReady) {
  return {
    'success': false,
    'error': 'WebSocket not ready - cannot join room. Please ensure you are logged in.',
  };
}
```

**User Experience**:
- Error message returned in result
- No automatic navigation (calling code handles it)

**Called From**:
- `lobby_screen.dart` - `_joinRoom()` - line 208 (via GameCoordinator)
- `create_join_game_widget.dart` - `_joinRoom()` - line 219

### Instance 3: Join Random Game
**File**: `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`
**Method**: `joinRandomGame()`
**Line**: 256-259

```dart
final isReady = await ensureWebSocketReady();
if (!isReady) {
  throw Exception('WebSocket not ready - cannot join random game. Please ensure you are logged in.');
}
```

**User Experience**:
- Exception thrown
- Caught in catch block, returns error result

**Called From**:
- `join_random_game_widget.dart` - `_handleJoinRandomGame()` - line 102

### Instance 4: Lobby Screen - Create Room
**File**: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart`
**Method**: `_createRoom()`
**Line**: 145-151

```dart
final isReady = await DutchGameHelpers.ensureWebSocketReady();
if (!isReady) {
  if (mounted) {
    _showSnackBar('Unable to connect to game server. Please log in to continue.', isError: true);
    DutchGameHelpers.navigateToAccountScreen('ws_not_ready', 'Unable to connect to game server. Please log in to continue.');
  }
  return;
}
```

**User Experience**:
- SnackBar error message
- **Automatic navigation to account screen** with reason `'ws_not_ready'`

### Instance 5: Lobby Screen - Join Room
**File**: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart`
**Method**: `_joinRoom()`
**Line**: 199-205

```dart
final isReady = await DutchGameHelpers.ensureWebSocketReady();
if (!isReady) {
  if (mounted) {
    _showSnackBar('Unable to connect to game server', isError: true);
  }
  return;
}
```

**User Experience**:
- SnackBar error message
- No automatic navigation (different from create room)

### Instance 6: Join Random Game Widget
**File**: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/join_random_game_widget.dart`
**Method**: `_handleJoinRandomGame()`
**Line**: 88-99

```dart
final isReady = await DutchGameHelpers.ensureWebSocketReady();
if (!isReady) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unable to connect to game server'),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }
  return;
}
```

**User Experience**:
- SnackBar error message
- No automatic navigation

### Instance 7: Create/Join Game Widget - Join Room
**File**: `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/create_join_game_widget.dart`
**Method**: `_joinRoom()`
**Line**: 194-208

```dart
final isReady = await DutchGameHelpers.ensureWebSocketReady();
if (!isReady) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unable to connect to game server'),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }
  setState(() {
    _isLoading = false;
  });
  return;
}
```

**User Experience**:
- SnackBar error message
- Loading state reset
- No automatic navigation

## State and SharedPreferences Checks

### Where Login State is Checked

1. **StateManager**:
   - Path: `StateManager().getModuleState<Map<String, dynamic>>('login')`
   - Key: `'isLoggedIn'`
   - Type: `bool`
   - Location: `ensureWebSocketReady()` - line 184-185

2. **SharedPreferences** (via LoginModule):
   - Key: `'is_logged_in'`
   - Type: `bool`
   - Checked in: `LoginModule.hasValidToken()` and `LoginModule.getCurrentToken()`

3. **JWT Token**:
   - Stored in: `AuthManager` (via `SecureStorage`)
   - Retrieved via: `LoginModule.getCurrentToken()`
   - Required for: WebSocket connection authentication

## Proposed Solution Points

### Option 1: Auto-Create Guest in `ensureWebSocketReady()`
**Location**: `dutch_game_helpers.dart:179`

**Logic**:
```dart
if (!isLoggedIn) {
  // Check SharedPreferences for existing guest credentials
  // If none found, auto-create guest user
  // Then retry ensureWebSocketReady()
}
```

**Pros**:
- Centralized solution
- All room operations benefit automatically

**Cons**:
- May create guest users when not needed
- Requires async guest creation flow

### Option 2: Auto-Create Guest in Each Action Method
**Locations**:
- `createRoom()` - before `ensureWebSocketReady()`
- `joinRoom()` - before `ensureWebSocketReady()`
- `joinRandomGame()` - before `ensureWebSocketReady()`

**Pros**:
- More granular control
- Can handle different scenarios per action

**Cons**:
- Code duplication
- More places to maintain

### Option 3: Auto-Create Guest in Widget Level
**Locations**:
- `join_random_game_widget.dart` - before calling helper
- `create_join_game_widget.dart` - before calling helper
- `lobby_screen.dart` - before calling helper

**Pros**:
- UI-level control
- Can show loading states during guest creation

**Cons**:
- Most duplication
- Logic spread across multiple files

## Recommended Approach

**Option 1** (Centralized in `ensureWebSocketReady()`) is recommended because:
1. Single point of control
2. All room operations automatically benefit
3. Consistent behavior across all entry points
4. Easier to maintain and test

## Implementation Considerations

1. **Guest User Creation**:
   - Check `SharedPreferences` for existing guest credentials
   - If found, use them to log in
   - If not found, create new guest user via `LoginModule.registerGuestUser()`
   - Update `StateManager` with login state
   - Retry `ensureWebSocketReady()`

2. **Error Handling**:
   - If guest creation fails, return `false` (existing behavior)
   - Show appropriate error messages

3. **State Updates**:
   - Ensure `StateManager` login state is updated after guest creation
   - Ensure `SharedPreferences` is updated
   - Trigger any necessary state listeners

4. **Navigation**:
   - Should NOT navigate to account screen if auto-creating guest
   - Only navigate if guest creation fails

## Related Files

### Core Files
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart` - Main helper functions
- `flutter_base_05/lib/core/managers/websockets/websocket_manager.dart` - WebSocket initialization
- `flutter_base_05/lib/modules/login_module/login_module.dart` - Login/guest user management

### UI Files
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart` - Main lobby screen
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/join_random_game_widget.dart` - Random join widget
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/create_join_game_widget.dart` - Create/join widget

### State Management
- `flutter_base_05/lib/core/managers/state_manager.dart` - State management
- `flutter_base_05/lib/core/services/shared_preferences.dart` - SharedPreferences service

## Summary

**Total Failure Points**: 7 instances across 4 files

**Navigation to Account Screen**: 1 instance (lobby_screen.dart - create room)

**Error Messages Shown**: 7 instances (all show user-friendly messages)

**Key Checkpoint**: `ensureWebSocketReady()` - This is where we should implement auto-guest creation

**State Check**: `StateManager().getModuleState('login')['isLoggedIn']`

**Token Check**: `LoginModule.hasValidToken()` and `LoginModule.getCurrentToken()`
