# Computer Player Implementation - Database Comp Players with Rank-Based Matching

## Overview

The multiplayer game system uses real computer player users from the database instead of creating simulated CPU players. The system includes:

1. Adding `is_comp_player` field to users collection
2. Creating Flask endpoint to retrieve comp players with rank-based filtering
3. Updating Dart backend to fetch and assign comp players (excluding practice mode)
4. **Rank-based matching system** for both human and computer players
5. **Rank-to-difficulty mapping** for AI behavior configuration
6. **Level and rank fields** stored in player data and game state
7. **Profile picture support** - comp players include `profile_picture` URLs in player data, displayed in the unified game board widget

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
  - Initial coins: 1000 in `modules.dutch_game.coins`
  - Status: `active`
  - `is_comp_player`: `true`
  - **Level**: Integer (1-100+) stored in `modules.dutch_game.level`
  - **Rank**: String stored in `modules.dutch_game.rank` (one of: beginner, novice, apprentice, skilled, advanced, expert, veteran, master, elite, legend)

**Example structure**:
```javascript
{
  "_id": ObjectId("..."),
  "email": "comp_player_1@example.com",
  "username": "CompPlayer1",
  "is_comp_player": true,  // NEW FIELD
  "status": "active",
  "modules": {
    "dutch_game": {
      "level": 25,           // Player level (1-100+)
      "rank": "apprentice",  // Player rank (beginner to legend)
      "coins": 1000,
      // ... other game stats
    }
  },
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
- Accepts optional `rank_filter` parameter (list of compatible ranks)
- Queries MongoDB: `db.users.find({"is_comp_player": True, "status": "active"})`
- **Rank Filtering** (if `rank_filter` provided):
  - Filters comp players by rank: `"modules.dutch_game.rank": {"$in": rank_filter}`
  - If no comp players found with rank filter, falls back to fetching without filter
- **Randomization**: 
  - Shuffles all available comp players using `random.shuffle()`
  - Uses `random.sample()` to select the requested count
  - Shuffles selected players again before returning
  - This ensures both selection and order are truly random
- Returns list with `user_id`, `username`, `email`, `rank`, `level`, and `profile_picture` for each comp player
- Handles case where fewer comp players exist than requested (returns available ones)

**Response format**:
```json
{
  "success": true,
  "comp_players": [
    {
      "user_id": "...",
      "username": "CompPlayer1",
      "email": "...",
      "rank": "apprentice",
      "level": 25,
      "profile_picture": "https://dutch.reignofplay.com/sim_players/images/img000.jpg"
    },
    {
      "user_id": "...",
      "username": "CompPlayer2",
      "email": "...",
      "rank": "skilled",
      "level": 35,
      "profile_picture": "https://dutch.reignofplay.com/sim_players/images/img001.jpg"
    }
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
Future<Map<String, dynamic>> getCompPlayers(int count, {List<String>? rankFilter}) async {
  // POST to /public/dutch/get-comp-players
  // Body: {"count": count, "rank_filter": rankFilter}  // rankFilter is optional
  // Returns: {"success": true, "comp_players": [...], "count": N}
  // Each comp player includes: user_id, username, email, rank, level, profile_picture
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
   - **Get room difficulty** from `roomInfo.difficulty` or `stateRoot['roomDifficulty']`
   - **Calculate compatible ranks** using `RankMatcher.getCompatibleRanks(roomDifficulty)` (returns ±1 rank range)
   - Call `pythonApiClient.getCompPlayers(needed, rankFilter: compatibleRanks)`
   - **Fallback**: If no comp players found with rank filter, retry without filter
   - Handle response: extract `comp_players` array
   - For each comp player:
     - Use `user_id` as base for player `id` (generate unique ID: `comp_${userId}_${timestamp}`)
     - Use `username` as player `name` (ensure uniqueness)
     - Set `isHuman: false`
     - Set `userId: user_id` (for coin deduction)
     - **Extract `rank`, `level`, and `profile_picture`** from comp player data
     - **Map rank to difficulty** using `RankMatcher.rankToDifficulty(rank)` (returns: easy, medium, hard, expert)
     - **Store `rank`, `level`, `difficulty`, and `profile_picture`** in player object
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

## Rank-Based Matching System

### Overview

The system implements rank-based matching to ensure players of similar skill levels are matched together. This applies to both human players joining rooms and computer players being added to games.

### Rank Hierarchy

The system uses 10 ranks in ascending order:
1. `beginner` (Levels 1-10)
2. `novice` (Levels 11-20)
3. `apprentice` (Levels 21-30)
4. `skilled` (Levels 31-40)
5. `advanced` (Levels 41-50)
6. `expert` (Levels 51-60)
7. `veteran` (Levels 61-70)
8. `master` (Levels 71-80)
9. `elite` (Levels 81-90)
10. `legend` (Levels 91+)

### Room Difficulty Setting

**Multiplayer Mode**:
- When a human player creates a room, the room's `difficulty` is set to the creator's rank
- When another human player joins a room, they can only join if their rank is compatible with the room's difficulty (±1 rank)
- The room difficulty is stored in `room.difficulty` and `stateRoot['roomDifficulty']`

**Practice Mode**:
- When a practice match is initiated, the user selects a difficulty (easy, medium, hard, expert) in the lobby
- This difficulty is passed to the `room_created` hook and stored as `room.difficulty`
- Practice mode CPU players are created with this difficulty

### Rank Compatibility

Two ranks are considered compatible if they are:
- The same rank
- One rank below (e.g., `novice` can join `beginner` room)
- One rank above (e.g., `expert` can join `advanced` room)

**Implementation**: `RankMatcher.areRanksCompatible(rank1, rank2)` and `RankMatcher.getCompatibleRanks(rank)`

### Rank-to-Difficulty Mapping

Player ranks are mapped to YAML difficulty levels for AI behavior:

| Rank Range | YAML Difficulty |
|------------|----------------|
| `beginner` | `easy` |
| `novice`, `apprentice` | `medium` |
| `skilled`, `advanced`, `expert` | `hard` |
| `veteran`, `master`, `elite`, `legend` | `expert` |

**Implementation**: `RankMatcher.rankToDifficulty(rank)` returns the mapped difficulty.

### Computer Player Selection Flow

1. **Get Room Difficulty**: Retrieve from `roomInfo.difficulty` or `stateRoot['roomDifficulty']`
2. **Calculate Compatible Ranks**: Use `RankMatcher.getCompatibleRanks(roomDifficulty)` to get ±1 rank range
3. **Fetch Comp Players**: Call Flask endpoint with `rank_filter` containing compatible ranks
4. **Fallback**: If no comp players found with rank filter, retry without filter (ensures game can start)
5. **Map Difficulty**: For each comp player, map their `rank` to YAML `difficulty` using `RankMatcher.rankToDifficulty()`
6. **Store in Player Object**: Include `rank`, `level`, `difficulty`, and `profile_picture` in the player object for AI decision-making and UI display

### Practice Mode CPU Players

- Practice mode uses simulated CPU players (not from database)
- CPU players are created with the difficulty selected in the lobby
- Difficulty is retrieved from `roomInfo.difficulty` or `stateRoot['roomDifficulty']`
- Defaults to `medium` if not set

## Important Notes

- Practice mode (`practice_room_*`) MUST continue using simulated CPU players (existing behavior)
- Multiplayer mode will use database comp players when available
- Fallback to simulated CPU players ensures games can always start
- `userId` from comp players is stored for coin deduction logic
- Random selection ensures fair distribution of comp players across games
- **Rank-based filtering ensures fair matchmaking** - players are matched with similar skill levels
- **Rank-to-difficulty mapping ensures appropriate AI behavior** - comp players play at difficulty matching their rank

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
- [x] Implement rank-based filtering for comp player selection
- [x] Implement rank-to-difficulty mapping for AI behavior
- [x] Add level and rank fields to player data
- [x] Implement room difficulty setting based on creator's rank
- [x] Implement rank-based room joining validation
- [x] Store user rank and level in WebSocket session
- [x] Update practice mode to use selected difficulty
- [x] Add profile picture support for computer players (profile_picture URL included in comp player data and displayed in unified game board widget)

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
- `level` and `rank` may be updated based on performance (future feature)

Simulated CPU players (fallback) are still skipped from statistics updates.

### User Rank and Level Initialization

**New Users**:
- Default rank: `beginner`
- Default level: `1`
- Stored in `modules.dutch_game.rank` and `modules.dutch_game.level`

**Guest Users**:
- Default rank: `beginner`
- Default level: `1`
- When converted to regular user, existing rank/level are preserved (if set)

**WebSocket Session**:
- User's rank and level are retrieved from database during authentication
- Stored in session data: `_sessionToUserRank` and `_sessionToUserLevel`
- Available via `server.getUserRankForSession(sessionId)` and `server.getUserLevelForSession(sessionId)`
- Used for room difficulty setting and rank-based matching

### Files Modified (Updated)

1. ✅ `playbooks/00_local/09_setup_apps_database_structure(update_existing).yml` - Added `is_comp_player` field and comp player creation
2. ✅ `playbooks/rop01/10_setup_apps_database_structure(update_existing).yml` - Added `is_comp_player` field and comp player creation
3. ✅ `playbooks/00_local/11_add_players.py` - Script to add comp players with rank and level
4. ✅ `playbooks/rop01/11_add_players.py` - Script to add comp players with rank and level
5. ✅ `python_base_04/core/modules/dutch_game/dutch_game_main.py` - Added endpoint with rank filtering
6. ✅ `python_base_04/core/modules/dutch_game/api_endpoints.py` - Returns rank and level in token validation
7. ✅ `python_base_04/core/managers/websockets/ws_session_manager.py` - Stores rank and level in session
8. ✅ `dart_bkend_base_01/lib/services/python_api_client.dart` - Added `getCompPlayers()` with rank filter
9. ✅ `dart_bkend_base_01/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart` - Rank-based comp player fetching
10. ✅ `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` - Uses difficulty from player object
11. ✅ `dart_bkend_base_01/lib/modules/dutch_game/backend_core/utils/rank_matcher.dart` - Rank matching and difficulty mapping utilities
12. ✅ `dart_bkend_base_01/lib/modules/dutch_game/dutch_main.dart` - Sets room difficulty from creator's rank
13. ✅ `dart_bkend_base_01/lib/server/message_handler.dart` - Rank-based room joining validation
14. ✅ `dart_bkend_base_01/lib/server/websocket_server.dart` - Stores and retrieves user rank/level
15. ✅ `flutter_base_05/lib/modules/dutch_game/backend_core/dutch_game_main.dart` - Practice mode difficulty handling
16. ✅ `flutter_base_05/lib/modules/dutch_game/utils/platform/practice/stubs/room_manager_stub.dart` - Added difficulty field
