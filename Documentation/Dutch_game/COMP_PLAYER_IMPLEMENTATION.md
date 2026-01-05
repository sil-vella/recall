# Replace CPU Players with Database Comp Players

## Overview

Modify the multiplayer game system to use real computer player users from the database instead of creating simulated CPU players. This involves:

1. Adding `is_comp_player` field to users collection
2. Creating Flask endpoint to retrieve comp players
3. Updating Dart backend to fetch and assign comp players (excluding practice mode)

## Database Changes

### 1. Add `is_comp_player` Field to Users Collection

**Files**: 
- `playbooks/00_local/09_setup_apps_database_structure(update_existing).yml` (local)
- `playbooks/rop01/10_setup_apps_database_structure(update_existing).yml` (VPS)

**What it does**:
- Adds `is_comp_player: false` to all existing users in the users collection
- Creates index: `db.users.createIndex({ "is_comp_player": 1 })`
- Creates 5 computer players with predefined usernames:
  - `alex.morris87`
  - `lena_kay`
  - `jordanrivers`
  - `samuel.b`
  - `nina_holt`
- Each comp player has:
  - Email: `{username}@cp.com`
  - Password: `comp_player_pass` (bcrypt hashed)
  - Initial coins: 1000 in `modules.cleco_game.coins`
  - Status: `active`
  - `is_comp_player`: `true`

**Example structure**:
```javascript
{
  "_id": ObjectId("..."),
  "email": "comp_player_1@example.com",
  "username": "CompPlayer1",
  "is_comp_player": true,  // NEW FIELD
  "status": "active",
  // ... rest of user structure
}
```

## Flask Backend Changes

### 2. Create Flask Endpoint for Comp Players

**File**: `python_base_04/core/modules/cleco_game/cleco_game_main.py`

Add new public endpoint in `register_routes()`:
```python
self._register_route_helper("/public/cleco/get-comp-players", self.get_comp_players, methods=["POST"])
```

**File**: `python_base_04/core/modules/cleco_game/cleco_game_main.py`

Add method `get_comp_players()`:
- Accepts `count` parameter (number of comp players needed)
- Queries MongoDB: `db.users.find({"is_comp_player": True, "status": "active"})`
- **Randomization**: 
  - Shuffles all available comp players using `random.shuffle()`
  - Uses `random.sample()` to select the requested count
  - Shuffles selected players again before returning
  - This ensures both selection and order are truly random
- Returns list with `user_id`, `username`, `email` for each comp player
- Handles case where fewer comp players exist than requested (returns available ones)

**Response format**:
```json
{
  "success": true,
  "comp_players": [
    {"user_id": "...", "username": "CompPlayer1", "email": "..."},
    {"user_id": "...", "username": "CompPlayer2", "email": "..."}
  ],
  "count": 2
}
```

### 3. Update Database Query Logic

**File**: `python_base_04/core/modules/cleco_game/cleco_game_main.py`

- Use `DatabaseManager` to query users collection
- Filter by `is_comp_player: True` and `status: "active"`
- Use `random.sample()` to randomly select requested count
- Handle edge cases (no comp players, fewer than requested)

## Dart Backend Changes

### 4. Add Method to PythonApiClient

**File**: `dart_bkend_base_01/lib/services/python_api_client.dart`

Add new method:
```dart
Future<Map<String, dynamic>> getCompPlayers(int count) async {
  // POST to /public/cleco/get-comp-players
  // Body: {"count": count}
  // Returns: {"success": true, "comp_players": [...], "count": N}
}
```

### 5. Update GameEventCoordinator CPU Player Creation

**File**: `dart_bkend_base_01/lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart`

**Location**: `_handleStartMatch()` method, lines 238-275

**Changes**:

1. Add condition to skip this logic for practice mode:
   ```dart
   // Skip comp player fetching for practice mode
   if (isPracticeMode) {
     // Use existing simulated CPU player creation (current code)
     // ... existing while loop ...
   } else {
     // NEW: Fetch comp players from Flask backend
   }
   ```

2. For multiplayer (non-practice):
   - Call `pythonApiClient.getCompPlayers(needed)`
   - Handle response: extract `comp_players` array
   - For each comp player:
     - Use `user_id` as player `id` (or generate sessionId-like ID)
     - Use `username` as player `name`
     - Set `isHuman: false`
     - Set `userId: user_id` (for coin deduction)
     - Initialize other player fields (hand, status, points, etc.)

3. Fallback logic:
   - If API call fails or returns fewer comp players than needed:
     - Use returned comp players
     - Calculate remaining: `remaining = needed - returned_count`
     - Create simulated CPU players for remainder (existing logic)

**Key implementation details**:
- Ensure `isPracticeMode` check is at the top to exclude practice rooms
- Store `userId` from comp player data for coin deduction logic
- Maintain existing player structure format
- Log comp player assignment for debugging

### 6. Error Handling

**File**: `dart_bkend_base_01/lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart`

- Wrap API call in try-catch
- If API fails: log error and fall back to simulated CPU players
- If insufficient comp players: use available ones + simulated for remainder
- Ensure game can still start even if API fails

## Testing Considerations

1. **Database**: Verify `is_comp_player` field exists and comp players are created
2. **Flask Endpoint**: Test `/public/cleco/get-comp-players` with various counts
3. **Dart Backend**: 
   - Test practice mode still uses simulated CPU players
   - Test multiplayer mode fetches comp players
   - Test fallback when API fails
   - Test partial fill when fewer comp players available

## Files Modified

1. ✅ `playbooks/00_local/09_setup_apps_database_structure(update_existing).yml` - Added `is_comp_player` field and comp player creation
2. ✅ `playbooks/rop01/10_setup_apps_database_structure(update_existing).yml` - Added `is_comp_player` field and comp player creation
3. ✅ `python_base_04/core/modules/cleco_game/cleco_game_main.py` - Added endpoint and method with randomization
4. ✅ `dart_bkend_base_01/lib/services/python_api_client.dart` - Added `getCompPlayers()` method
5. ✅ `dart_bkend_base_01/lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart` - Updated `_handleStartMatch()` with comp player fetching
6. ✅ `dart_bkend_base_01/lib/modules/cleco_game/backend_core/services/game_registry.dart` - Updated `onGameEnded()` to handle comp player statistics
7. ✅ `dart_bkend_base_01/lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart` - Added guard to prevent duplicate game end processing
8. ✅ `dart_bkend_base_01/lib/server/websocket_server.dart` - Made Python API URL configurable
9. ✅ `dart_bkend_base_01/app.dart` - VPS configuration (Docker service name)
10. ✅ `dart_bkend_base_01/app.debug.dart` - Local development configuration (localhost)

## Important Notes

- Practice mode (`practice_room_*`) MUST continue using simulated CPU players (existing behavior)
- Multiplayer mode will use database comp players when available
- Fallback to simulated CPU players ensures games can always start
- `userId` from comp players is stored for coin deduction logic
- Random selection ensures fair distribution of comp players across games

## Implementation Status

✅ **COMPLETED** - All implementation tasks have been completed:

- [x] Add `is_comp_player` field to users collection in database setup playbook
- [x] Create `/public/cleco/get-comp-players` endpoint in Flask backend
- [x] Implement `get_comp_players()` method with database query and random selection
- [x] Add `getCompPlayers()` method to PythonApiClient
- [x] Update `_handleStartMatch()` to fetch comp players for multiplayer (exclude practice mode)
- [x] Implement fallback to simulated CPU players when API fails or insufficient comp players
- [x] Add randomization to ensure comp players are selected and ordered randomly
- [x] Update game end logic to update statistics for comp players from database

## Implementation Details

### Comp Player Usernames

The system uses 5 predefined comp player usernames:
- `alex.morris87`
- `lena_kay`
- `jordanrivers`
- `samuel.b`
- `nina_holt`

These are created automatically by the database setup playbook with:
- Email format: `{username}@cp.com`
- Password: `comp_player_pass` (bcrypt hashed)
- Initial coins: 1000 in `modules.cleco_game.coins`
- Status: `active`
- `is_comp_player`: `true`

### Randomization

The Flask endpoint ensures true randomization:
1. Shuffles all available comp players before selection
2. Uses `random.sample()` to select the required count
3. Shuffles selected players again before returning
4. This ensures both selection and order are random

### Statistics Updates

Comp players from the database have their statistics updated at game end:
- `total_matches` incremented
- `wins` or `losses` updated based on game outcome
- `coins` updated (deducted for entry, added for wins)
- `win_rate` recalculated
- `last_match_date` updated

Simulated CPU players (fallback) are still skipped from statistics updates.
