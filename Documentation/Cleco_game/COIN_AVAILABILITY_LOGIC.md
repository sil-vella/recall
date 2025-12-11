# Coin Availability Logic

This document describes the comprehensive coin availability validation system for the Cleco game, which ensures users have sufficient coins before they can create or join multiplayer games.

## Overview

The coin availability system validates that users have enough coins (default: 25) before allowing them to:
- Create a new game room
- Join an existing game room
- Join a random available game
- Join a game from the available games list

**Subscription Tier System:**
- Users have a `subscription_tier` field in `modules.cleco_game.subscription_tier`
- **Promotional Tier** (`'promotional'`): Free play - no coin check required, no coins deducted
- **Free/Regular Tier** (`'free'` or `'regular'`): Requires coins - coin check and deduction applies
- Default tier for new users: `'promotional'`
- Tier is checked before coin validation and during coin deduction

**Coin Deduction:** Coins are deducted from all active players (including creator) when the game actually starts (when `start_match` event is processed and game phase changes to `initial_peek`). This happens after coin availability validation but before the game begins. **Promotional tier players are exempt from coin deduction.**

**Key Principles:**
- **Subscription Tier System:** Users have a `subscription_tier` field in `modules.cleco_game.subscription_tier`
  - **Promotional Tier:** Free play - no coin check required, no coins deducted
  - **Free/Regular Tier:** Requires coins - coin check and deduction applies
- **Validation:** All validation happens on the frontend (Flutter) before any WebSocket events are sent to the backend
- **Tier Check First:** Subscription tier is checked before coin validation (promotional tier skips coin check)
- **Deduction:** Coins are deducted when the game starts, not when players join/create
- **Per-Player Tier Check:** Each player's subscription tier is checked individually during coin deduction
- **Scope:** All active players have coins deducted (creator + all joiners), except promotional tier players
- **Practice Mode:** Practice mode games do NOT deduct coins

---

## Architecture

### Components

1. **API Endpoints:**
   - `/userauth/cleco/get-user-stats` (GET) - Returns user's cleco_game module data including coins
   - `/userauth/cleco/deduct-game-coins` (POST) - Deducts coins from multiple players when game starts
   - Both endpoints are protected by JWT authentication

2. **Helper Methods:**
   - `ClecoGameHelpers.checkCoinsRequirement()` - Validates coins before create/join
   - `ClecoGameHelpers.deductGameCoins()` - Deducts coins from all players when game starts

3. **Entry Points** (All game join/create actions)
   - Lobby screen create room
   - Lobby screen join room
   - Join room widget
   - Join random game widget
   - Available games widget

4. **Coin Deduction Trigger**
   - `ClecoEventHandlerCallbacks._handleCoinDeductionOnGameStart()` - Triggered when game phase changes to `initial_peek`

---

## Flow Diagram

### Coin Validation Flow (Before Game Start)

```
User Action (Create/Join Game)
    ↓
Check Subscription Tier
    ├─ Promotional → Skip coin check, proceed (free play)
    └─ Free/Regular → Continue to coin check
    ↓
Check Coins Requirement
    ↓
Fetch Fresh Stats from API
    ├─ Success → Extract coins and subscription_tier from response
    └─ Failure → Fallback to cached state
    ↓
Compare: currentCoins >= requiredCoins?
    ├─ Yes → Proceed with WebSocket event (create/join room)
    └─ No → Show error, stop (no WebSocket event)
```

### Coin Deduction Flow (When Game Starts)

```
Game Start (start_match event processed)
    ↓
Game Phase Changes to 'initial_peek'
    ↓
Flutter: handleGameStateUpdated() detects phase change
    ↓
Check: Is practice mode? (practice_room_*)
    ├─ Yes → Skip coin deduction
    └─ No → Continue
    ↓
Check: Coins already deducted for this game?
    ├─ Yes → Skip (prevent duplicate deductions)
    └─ No → Continue
    ↓
Get all active players from game state
    ↓
Extract user IDs from player objects
    ↓
Call ClecoGameHelpers.deductGameCoins()
    ↓
POST /userauth/cleco/deduct-game-coins
    ├─ For each player:
    │   ├─ Check subscription_tier
    │   ├─ If promotional → Skip deduction (free play)
    │   └─ If free/regular → Deduct coins using MongoDB $inc
    └─ Return success/error with updated counts (includes skipped players)
    ↓
Mark coins as deducted in state
    ↓
Refresh user stats to show updated coin count
```

---

## Implementation Details

### 1. Helper Method: `checkCoinsRequirement()`

**Location:** `flutter_base_05/lib/modules/cleco_game/utils/cleco_game_helpers.dart`

**Signature:**
```dart
static Future<bool> checkCoinsRequirement({
  int requiredCoins = 25,
  bool fetchFromAPI = true
})
```

**Parameters:**
- `requiredCoins`: Number of coins required (default: 25)
- `fetchFromAPI`: Whether to fetch fresh stats from API (default: true)

**Behavior:**
1. **First checks subscription tier:**
   - Calls `getSubscriptionTier()` to get user's subscription tier
   - If `subscription_tier == 'promotional'` → Returns `true` immediately (free play, no coin check)
   - If `subscription_tier != 'promotional'` → Continues with coin check
2. If `fetchFromAPI` is true:
   - Calls `getUserClecoGameData()` to fetch fresh stats from API
   - Extracts `coins` and `subscription_tier` from API response
   - Falls back to cached state if API call fails
3. If `fetchFromAPI` is false:
   - Uses cached state from `getUserClecoGameStats()`
4. Compares current coins with required coins
5. Returns `true` if sufficient, `false` otherwise
6. Logs all operations for debugging

**Subscription Tier Integration:**
- First checks `subscription_tier` from user stats
- If `subscription_tier == 'promotional'` → Returns `true` immediately (free play, no coin check)
- If `subscription_tier != 'promotional'` → Proceeds with coin validation
- This allows promotional tier users to play for free without coin requirements

**Example Usage:**
```dart
// Check with default 25 coins, fetch from API
// Will skip coin check if user has promotional tier
final hasEnough = await ClecoGameHelpers.checkCoinsRequirement();

// Check with custom requirement, fetch from API
final hasEnough = await ClecoGameHelpers.checkCoinsRequirement(
  requiredCoins: 50,
  fetchFromAPI: true
);

// Check using cached state (faster, but may be stale)
final hasEnough = await ClecoGameHelpers.checkCoinsRequirement(
  fetchFromAPI: false
);
```

---

### 2. API Integration

**Endpoint:** `GET /userauth/cleco/get-user-stats`

**Authentication:** JWT token (automatically included via `ConnectionsApiModule`)

**Response Format:**
```json
{
  "success": true,
  "data": {
    "coins": 100,
    "wins": 5,
    "losses": 2,
    "points": 150,
    "level": 3,
    "rank": "intermediate",
    "subscription_tier": "promotional",
    ...
  },
  "user_id": "68700c8550fad8a5be4e28bd",
  "timestamp": "2025-12-10T12:41:05.225Z"
}
```

**Subscription Tier Values:**
- `"promotional"`: Free play tier - no coin check or deduction required
- `"free"`: Free tier - requires coins for gameplay
- `"regular"`: Regular tier - requires coins for gameplay

**Error Response:**
```json
{
  "success": false,
  "error": "User not authenticated",
  "message": "No user ID found in request"
}
```

**Implementation:** `getUserClecoGameData()` in `cleco_game_helpers.dart`
- Uses `ConnectionsApiModule` to make authenticated GET request
- Handles errors gracefully
- Returns structured response with success/error status

---

### 3. Entry Points

All game creation/joining actions validate coins before proceeding:

#### 3.1 Create Room

**Location:** `lobby_screen.dart` → `_createRoom()`

**Flow:**
```dart
Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
  // Get required coins (default 25, can be overridden in roomSettings)
  final requiredCoins = roomSettings['requiredCoins'] as int? ?? 25;
  
  // Check coins with fresh API data
  final hasEnoughCoins = await ClecoGameHelpers.checkCoinsRequirement(
    requiredCoins: requiredCoins,
    fetchFromAPI: true
  );
  
  if (!hasEnoughCoins) {
    // Show error, return early (no WebSocket event sent)
    _showSnackBar('Insufficient coins to create a game. Required: $requiredCoins');
    return;
  }
  
  // Proceed with room creation via WebSocket
  final result = await ClecoGameHelpers.createRoom(...);
}
```

**Custom Coin Requirements:**
- Room settings can specify `requiredCoins` to override default
- Example: Premium rooms could require 50 coins

#### 3.2 Join Room (Lobby Screen)

**Location:** `lobby_screen.dart` → `_joinRoom()`

**Flow:**
```dart
Future<void> _joinRoom(String roomId) async {
  // Check coins with default 25 requirement
  final hasEnoughCoins = await ClecoGameHelpers.checkCoinsRequirement(
    fetchFromAPI: true
  );
  
  if (!hasEnoughCoins) {
    _showSnackBar('Insufficient coins to join a game. Required: 25');
    return;
  }
  
  // Proceed with room join via GameCoordinator
  final gameCoordinator = GameCoordinator();
  await gameCoordinator.joinGame(gameId: roomId, playerName: 'Player');
}
```

#### 3.3 Join Room (Widget)

**Location:** `join_game_widget.dart` → `_joinRoom()`

**Flow:**
- Same validation as lobby screen join
- Shows error via `ScaffoldMessenger` if insufficient coins
- Prevents WebSocket `join_room` event from being sent

#### 3.4 Join Random Game

**Location:** `join_random_game_widget.dart` → `_handleJoinRandomGame()`

**Flow:**
```dart
Future<void> _handleJoinRandomGame() async {
  // Check coins before joining random game
  final hasEnoughCoins = await ClecoGameHelpers.checkCoinsRequirement(
    fetchFromAPI: true
  );
  
  if (!hasEnoughCoins) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Insufficient coins to join a game. Required: 25'))
    );
    return;
  }
  
  // Proceed with random game join
  final result = await ClecoGameHelpers.joinRandomGame();
}
```

#### 3.5 Join from Available Games

**Location:** `available_games_widget.dart` → `_joinGame()`

**Flow:**
- Validates coins before calling `GameCoordinator.joinGame()`
- Shows error snackbar if insufficient
- Prevents game join action

---

### 4. Coin Deduction on Game Start

**Location:** `cleco_event_handler_callbacks.dart` → `_handleCoinDeductionOnGameStart()`

**Trigger:** When game phase changes to `initial_peek` (game started)

**Flow:**
```dart
// In handleGameStateUpdated()
if (phase changes to 'initial_peek') {
  _handleCoinDeductionOnGameStart(gameId, gameState);
}
```

**Deduction Process:**
1. **Skip Practice Mode:** If `gameId.startsWith('practice_room_')`, skip deduction
2. **Check Duplicate Prevention:** Verify coins haven't already been deducted for this game
3. **Get Active Players:** Extract all players with `isActive == true` from game state
4. **Extract User IDs:** Get MongoDB user IDs from player objects (stored when players join)
5. **Call API:** `ClecoGameHelpers.deductGameCoins()` with all player user IDs
6. **Mark as Deducted:** Store game ID in `coinsDeductedGames` state to prevent duplicates
7. **Refresh Stats:** Update local user stats to show new coin count

**Python API Endpoint:** `/userauth/cleco/deduct-game-coins`
- Method: POST
- Authentication: JWT required
- Request body: `{ "coins": 25, "game_id": "room_xxx", "player_ids": ["user_id1", "user_id2", ...] }`
- For each player:
  1. **Check Subscription Tier:**
     - Retrieves player's `modules.cleco_game.subscription_tier` from database
     - If `subscription_tier == 'promotional'`:
       - Skips coin deduction (free play)
       - Adds player to response with `coins_deducted: 0`, `skipped: true`, `reason: "promotional_tier"`
       - Logs: "Skipping coin deduction for player X - promotional tier (free play)"
     - If `subscription_tier != 'promotional'`:
       - Continues with coin deduction
  2. **Validate Coins:** Validates user has enough coins (defense in depth)
  3. **Deduct Coins:** Uses MongoDB `$inc` operator to atomically deduct coins
  4. **Update Timestamp:** Updates `last_updated` timestamp
- Returns: Success/error with list of updated players (includes both deducted and skipped players) and their new coin counts

**User ID Storage:**
- `userId` is stored in player objects when they join (from `room_created`/`room_joined` events)
- Creator's `userId` comes from `ownerId` in `room_created` event
- Joiners' `userId` comes from `user_id` in `room_joined` event
- Fallback: Current user's `userId` from login state if not in player object

**Error Handling:**
- If deduction fails, game continues (coin check should have passed before game start)
- Partial failures are logged but don't prevent game from continuing
- Missing user IDs for some players are logged as warnings

---

## Error Handling

### API Call Failures

If the API call to fetch fresh stats fails:
1. Logs warning message
2. Falls back to cached state from `getUserClecoGameStats()`
3. Uses cached coins value for validation
4. Continues with validation (may use stale data)

**Rationale:** Better to allow action with potentially stale data than block all actions if API is temporarily unavailable.

### Insufficient Coins

When user doesn't have enough coins:
1. Validation returns `false`
2. Error message shown to user via snackbar
3. Action is stopped (no WebSocket event sent)
4. User remains on current screen
5. Logs warning with required vs current coins

**Error Messages:**
- Create room: `"Insufficient coins to create a game. Required: {requiredCoins}"`
- Join room: `"Insufficient coins to join a game. Required: 25"`

### Missing User Stats

If user stats are not available (neither from API nor cache):
1. Validation returns `false`
2. Logs warning: `"Cannot check coins - userStats not found"`
3. Action is blocked
4. User sees generic error message

---

## State Management

### Coin Data Storage

Coins are stored in two places:

1. **Backend Database** (Source of Truth)
   - MongoDB: `users.modules.cleco_game.coins`
   - Updated by game results, purchases, rewards, etc.

2. **Frontend State** (Cache)
   - `cleco_game` module state: `userStats.coins`
   - Updated via `fetchAndUpdateUserClecoGameData()`
   - May be stale, so API fetch is preferred for validation

### State Update Flow

```
Backend Database (MongoDB)
    ↓ (API call)
getUserClecoGameData()
    ↓ (updates state)
StateManager: cleco_game.userStats.coins
    ↓ (used for display)
Coins Display Widget
```

**Note:** For validation, we always fetch fresh data from API to ensure accuracy.

---

## Configuration

### Default Coin Requirement

**Default:** 25 coins

**Location:** `checkCoinsRequirement()` method parameter

**Override Options:**
1. Per-action: Pass `requiredCoins` parameter
2. Per-room: Include `requiredCoins` in room settings
3. Global: Change default in helper method

### Future Enhancements

Potential configuration options:
- Different requirements for different game types
- Different requirements for public vs private rooms
- Time-based requirements (e.g., higher during peak hours)
- User tier-based requirements (e.g., VIP users pay less)

---

## Logging

All coin validation operations are logged for debugging:

**Log Levels:**
- **INFO:** Successful validation, API fetch success
- **WARNING:** Insufficient coins, API fetch failure, missing stats
- **ERROR:** Exceptions during validation

**Example Log Messages:**
```
📊 ClecoGameHelpers: Fetching fresh user stats from API for coin check
📊 ClecoGameHelpers: Fetched coins from API: 100
✅ ClecoGameHelpers: Coins check passed - Required: 25, Current: 100

⚠️ ClecoGameHelpers: Insufficient coins - Required: 25, Current: 10
⚠️ ClecoGameHelpers: Failed to fetch stats from API, falling back to state
❌ ClecoGameHelpers: Error checking coins requirement: [error details]
```

**Logging Switch:** Controlled by `LOGGING_SWITCH` constant in `cleco_game_helpers.dart`

---

## Testing Considerations

### Test Scenarios

1. **Sufficient Coins**
   - User has 100 coins, requires 25 → Should proceed
   - User has exactly 25 coins, requires 25 → Should proceed

2. **Insufficient Coins**
   - User has 10 coins, requires 25 → Should block with error
   - User has 0 coins, requires 25 → Should block with error

3. **API Failures**
   - API returns error → Should fallback to cached state
   - API timeout → Should fallback to cached state
   - No cached state available → Should block with error

4. **Edge Cases**
   - User not logged in → API call should fail gracefully
   - Missing coins field in response → Should default to 0
   - Negative coins (shouldn't happen, but handle gracefully)

### Manual Testing

1. **Test with sufficient coins:**
   - Ensure user has >25 coins
   - Try to create/join game
   - Should succeed

2. **Test with insufficient coins:**
   - Set user coins to <25 in database
   - Try to create/join game
   - Should show error, no WebSocket event sent

3. **Test API failure:**
   - Disconnect backend or block API endpoint
   - Try to create/join game
   - Should fallback to cached state or show error

---

## Security Considerations

### Frontend Validation

**Important:** Frontend validation is for UX only. It should not be relied upon for security.

**Why:**
- Users can modify client-side code
- Network requests can be intercepted
- Validation can be bypassed

**Backend Validation (Future):**
- Backend should also validate coins before allowing room creation/join
- This provides defense in depth
- Prevents malicious users from bypassing frontend checks

### Current State

Currently, only frontend validation exists. Backend validation should be added for production.

**Recommended Backend Validation:**
- Check coins in `handle_create_room()` before creating room
- Check coins in `handle_join_room()` before joining room
- Return error if insufficient coins
- This ensures server-side enforcement

---

## Performance Considerations

### API Call Overhead

Each coin check makes an API call to fetch fresh stats. This adds latency:

**Typical Latency:**
- API call: ~100-300ms
- Total validation time: ~150-400ms

**Optimization Options:**
1. **Cache API responses:** Cache for 1-2 seconds to avoid duplicate calls
2. **Batch validation:** If multiple checks happen quickly, reuse same API response
3. **Optimistic UI:** Show loading state, validate in background

**Current Implementation:**
- No caching between checks
- Each action makes fresh API call
- Acceptable for current use case (user-initiated actions)

### Fallback Strategy

If API is slow or fails:
- Falls back to cached state immediately
- No retry logic (keeps UX responsive)
- User may proceed with potentially stale data

---

## Related Documentation

- **State Management:** See `STATE_MANAGEMENT.md` for details on how coin data is stored in state
- **API Endpoints:** See Python backend documentation for `/userauth/cleco/get-user-stats` endpoint
- **Game Flow:** See `MULTIPLAYER_GAME_FLOW.md` for overall game creation/join flow

---

## Summary

The coin availability logic provides a robust, user-friendly validation and deduction system that:

✅ **Subscription tier aware** - Checks subscription tier before coin validation and deduction  
✅ **Promotional tier free play** - Promotional tier users skip coin check and deduction  
✅ **Validates before action** - Checks coins before sending WebSocket events (for non-promotional users)  
✅ **Deducts on game start** - Coins are deducted when game actually starts (not on join/create)  
✅ **Per-player tier check** - Each player's subscription tier is checked individually during deduction  
✅ **All players included** - Creator and all joiners have coins deducted (except promotional tier)  
✅ **Practice mode exempt** - Practice games do NOT deduct coins  
✅ **Uses fresh data** - Fetches latest coins from API for validation  
✅ **Graceful fallback** - Uses cached state if API fails  
✅ **Clear feedback** - Shows specific error messages to users  
✅ **Comprehensive coverage** - Validates all game entry points  
✅ **Duplicate prevention** - Tracks deducted games to prevent double-charging  
✅ **Well logged** - Detailed logging for debugging  
✅ **Configurable** - Supports custom coin requirements  

**Coin Deduction Details:**
- **When:** Game phase changes to `initial_peek` (game started)
- **Who:** All active players (creator + joiners), except promotional tier players
- **Subscription Tier Check:** Each player's tier is checked individually during deduction
  - **Promotional Tier:** No coins deducted (free play)
  - **Free/Regular Tier:** Coins deducted (default 25 coins)
- **Amount:** Default 25 coins (configurable)
- **Mode:** Multiplayer only (practice mode exempt)
- **API:** `/userauth/cleco/deduct-game-coins` (JWT protected)
- **Atomic Operation:** Uses MongoDB `$inc` for safe coin deduction
- **Per-Player Processing:** Each player is processed individually, allowing mixed-tier games

**Subscription Tier System:**
- **Promotional Tier** (`'promotional'`): Free play - no coin check, no coin deduction
- **Free/Regular Tier** (`'free'` or `'regular'`): Requires coins - coin check and deduction applies
- **Default**: New users start with `subscription_tier: 'promotional'`
- **Per-Player Check**: Each player's tier is checked individually during deduction
- **Mixed Games**: Promotional tier players can play with free/regular tier players (only free/regular players pay)

**Future Improvements:**
- Add backend validation for security (defense in depth)
- Implement caching to reduce API calls
- Support dynamic coin requirements based on game type/room settings
- Add analytics to track coin validation failures and deduction success rates
- Handle race conditions better (multiple players triggering deduction simultaneously)
- Support additional subscription tiers (e.g., premium, VIP)
