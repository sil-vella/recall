# Backend Coin Check Analysis

## Current Flow

### Create Room Flow
1. **Frontend** → Emits `create_room` WebSocket event
2. **`ws_event_handlers.py:handle_create_room()`** (line 369)
   - Validates permission (public/private)
   - Resolves user_id from session/JWT (line 385)
   - Generates room_id if not provided (line 388)
   - Gets password if provided (line 392)
   - **Creates room** via `websocket_manager.create_room()` (line 395)
   - **Joins user to room** via `websocket_manager.join_room()` (line 399) ⚠️ **CHECK HERE**
   - Emits success events (lines 406-424)
   - Triggers `room_created` hook (line 439)
   - Triggers `room_joined` hook (line 452)

### Join Room Flow
1. **Frontend** → Emits `join_room` WebSocket event
2. **`ws_event_handlers.py:handle_join_room()`** (line 250)
   - Validates room_id provided (line 253)
   - Checks if room exists (line 261)
   - Validates password for private rooms (lines 267-279)
   - Gets session data (line 282)
   - Resolves user_id from session/JWT (line 288)
   - **Joins user to room** via `websocket_manager.join_room()` (line 291) ⚠️ **CHECK HERE**
   - Emits success events (lines 300-320)
   - Triggers `room_joined` hook (line 325)

## Recommended Check Points

### ✅ **BEST OPTION: Check in Event Handlers Before join_room()**

**Location 1: `handle_create_room()` - Before line 399**
```python
# After resolving user_id (line 385)
# Before websocket_manager.join_room() (line 399)

# Check coins requirement
required_coins = data.get('required_coins', 25)  # Default 25, can be overridden
if not self._check_user_coins(user_id, required_coins):
    self.socketio.emit('create_room_error', {
        'error': f'Insufficient coins. Required: {required_coins}'
    })
    return False
```

**Location 2: `handle_join_room()` - Before line 291**
```python
# After resolving user_id (line 288)
# Before websocket_manager.join_room() (line 291)

# Check coins requirement
required_coins = 25  # Default, could also come from room settings
if not self._check_user_coins(user_id, required_coins):
    self.socketio.emit('join_room_error', {
        'error': f'Insufficient coins. Required: {required_coins}'
    })
    return False
```

### Why This Location?

✅ **Advantages:**
1. **Early validation** - Checks before any room operations
2. **No rollback needed** - Room not created/joined yet
3. **Clear error messages** - Can return specific error to client
4. **Consistent with existing validation** - Password check happens here too
5. **User_id already resolved** - Available from `_resolve_user_id()`
6. **Database access available** - Can query user's coins from MongoDB

❌ **Alternative locations considered:**
- **In `websocket_manager.join_room()`** - Too low-level, mixes concerns
- **After room creation** - Would need to rollback room creation
- **In Dart backend hooks** - Too late, user already in room

## Implementation Details

### Helper Method Needed

Add to `ws_event_handlers.py`:

```python
def _check_user_coins(self, user_id: str, required_coins: int = 25) -> bool:
    """
    Check if user has enough coins to join/create a game
    
    Args:
        user_id: User ID (string or ObjectId)
        required_coins: Required number of coins (default 25)
    
    Returns:
        True if user has enough coins, False otherwise
    """
    try:
        from bson import ObjectId
        
        # Get database manager from app_manager
        db_manager = self.app_manager.get_db_manager(role="read")
        if not db_manager:
            custom_log("❌ Coin check: Database manager not available", level="ERROR")
            return False
        
        # Convert user_id to ObjectId if string
        if isinstance(user_id, str):
            try:
                user_id = ObjectId(user_id)
            except:
                custom_log(f"❌ Coin check: Invalid user_id format: {user_id}", level="ERROR")
                return False
        
        # Get user from database
        user = db_manager.find_one("users", {"_id": user_id})
        if not user:
            custom_log(f"❌ Coin check: User not found: {user_id}", level="ERROR")
            return False
        
        # Extract cleco_game module data
        modules = user.get('modules', {})
        cleco_game = modules.get('cleco_game', {})
        
        # Get current coins (default to 0 if not found)
        current_coins = cleco_game.get('coins', 0)
        
        # Check if user has enough coins
        if current_coins < required_coins:
            custom_log(
                f"⚠️ Coin check failed: User {user_id} has {current_coins} coins, "
                f"required {required_coins}",
                level="WARNING"
            )
            return False
        
        custom_log(
            f"✅ Coin check passed: User {user_id} has {current_coins} coins, "
            f"required {required_coins}",
            level="INFO"
        )
        return True
        
    except Exception as e:
        custom_log(f"❌ Coin check error: {e}", level="ERROR")
        return False
```

### Integration Points

**1. In `handle_create_room()` - After line 385, before line 395:**
```python
# Resolve user id using backend auth/JWT if available
user_id = self._resolve_user_id(session_id, data)

# Check coins requirement (default 25, can be overridden in data)
required_coins = data.get('required_coins', 25)
if not self._check_user_coins(user_id, required_coins):
    self.socketio.emit('create_room_error', {
        'error': f'Insufficient coins to create a game. Required: {required_coins}'
    })
    return False

# Generate room_id if not provided...
```

**2. In `handle_join_room()` - After line 288, before line 291:**
```python
# Resolve user id using backend auth/JWT if available
user_id = self._resolve_user_id(session_id, data)

# Check coins requirement (default 25)
required_coins = 25  # Could also get from room_info if room has custom requirement
if not self._check_user_coins(user_id, required_coins):
    self.socketio.emit('join_room_error', {
        'error': f'Insufficient coins to join a game. Required: {required_coins}'
    })
    return False

# Join the room
join_result = self.websocket_manager.join_room(room_id, session_id, user_id)
```

## Error Handling

The coin check should:
1. **Return False** if insufficient coins
2. **Emit error event** to client (`create_room_error` or `join_room_error`)
3. **Log the check result** for debugging
4. **Handle database errors gracefully** - return False on error (fail closed)

## Frontend Error Handling

Frontend already handles these error events:
- `create_room_error` → Shows error snackbar
- `join_room_error` → Shows error snackbar

No frontend changes needed - errors will be displayed automatically.

## Summary

**Best location:** In `ws_event_handlers.py`:
- `handle_create_room()` - Before `websocket_manager.join_room()` (after line 385, before line 399)
- `handle_join_room()` - Before `websocket_manager.join_room()` (after line 288, before line 291)

**Why:** Early validation, no rollback needed, consistent with existing validation pattern, user_id already available, database access available.
