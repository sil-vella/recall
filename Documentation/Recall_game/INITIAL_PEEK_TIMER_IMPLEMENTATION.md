# Initial Peek Timer Implementation Plan

## 🎯 Problem Statement

**Current Issue**: Players are stuck in `initial_peek` status indefinitely with no automatic transition to the next phase.

**Expected Behavior**: After 10 seconds, all players should automatically transition to the next phase and the game should begin.

---

## 📊 Old System Analysis

### How It Worked (Python-only System)

**1. Timer Start** (`on_start_match` → `initial_peek`):
```python
# Set all players to INITIAL_PEEK status
updated_count = game.update_all_players_status(PlayerStatus.INITIAL_PEEK, filter_active=True)

# Start 10-second timer
timer_thread = threading.Timer(10.0, self._initial_peek_timeout, args=[game])
timer_thread.daemon = True
timer_thread.start()
```

**2. During 10 Seconds**:
- Players can complete their initial peek manually
- `on_completed_initial_peek`: Sets individual player to `WAITING` status
- Players who complete early: `WAITING`
- Players who don't complete: Still `INITIAL_PEEK`

**3. Timer Expires** (`_initial_peek_timeout`):
```python
# Set ALL players back to WAITING status
updated_count = game.update_all_players_status(PlayerStatus.WAITING, filter_active=True)

# Start the game round
game_round = game.get_round()
start_turn_result = game_round.start_turn()
```

---

## 🔧 New System Implementation

### Files to Modify

1. **`game_state.dart`**:
   - Add timer field
   - Add `startInitialPeekTimer()` method
   - Add `_onInitialPeekTimeout()` method

2. **`game_round.dart`**:
   - Ensure `startMatch()` calls the initial peek timer
   - Handle timer expiration logic

3. **`game_event_coordinator.py`**:
   - Handle the timer expiration event from Dart
   - Send updates to frontend

### Implementation Steps

#### Step 1: Add Timer to Dart GameState

```dart
import 'dart:async';

class GameState {
  // Add timer field
  Timer? initialPeekTimer;
  
  // Start initial peek timer
  void startInitialPeekTimer() {
    Logger().info('Starting 10-second initial peek timer', isOn: LOGGING_SWITCH);
    
    // Cancel any existing timer
    initialPeekTimer?.cancel();
    
    // Set all players to initialPeek status
    for (var player in players.values) {
      if (player.isActive) {
        player.updateStatus(PlayerStatus.initialPeek);
      }
    }
    
    // Start 10-second timer
    initialPeekTimer = Timer(Duration(seconds: 10), () {
      _onInitialPeekTimeout();
    });
  }
  
  void _onInitialPeekTimeout() {
    try {
      Logger().info('Initial peek timer expired - transitioning all players', isOn: LOGGING_SWITCH);
      
      // Set all players to waiting/ready status
      for (var player in players.values) {
        if (player.isActive) {
          player.updateStatus(PlayerStatus.waiting);
        }
      }
      
      // Start the game round
      if (round != null) {
        round!.startTurn();
      }
      
      Logger().info('Initial peek timeout complete - game started', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Error in initial peek timeout: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  void dispose() {
    // Cancel timer on cleanup
    initialPeekTimer?.cancel();
    // ... other cleanup
  }
}
```

#### Step 2: Call Timer from start_match

```dart
// In game_round.dart startMatch() method
void startMatch() {
  // ... existing logic ...
  
  // Start initial peek timer
  gameState.startInitialPeekTimer();
  
  // ... rest of logic ...
}
```

#### Step 3: Handle Manual Completion

```dart
// In game_round.dart or wherever completed_initial_peek is handled
void handleCompletedInitialPeek(String playerId) {
  // Set individual player to waiting
  final player = gameState.players[playerId];
  if (player != null) {
    player.updateStatus(PlayerStatus.waiting);
  }
  
  // Check if all players completed
  bool allCompleted = true;
  for (var player in gameState.players.values) {
    if (player.isActive && player.status == PlayerStatus.initialPeek) {
      allCompleted = false;
      break;
    }
  }
  
  // If all completed early, cancel timer and start game
  if (allCompleted) {
    gameState.initialPeekTimer?.cancel();
    gameState.round?.startTurn();
  }
}
```

---

## 🎯 Expected Flow

### Scenario 1: Timer Expires (10 seconds)
1. `start_match` called
2. All players → `initialPeek` status
3. 10-second timer starts
4. (Players may or may not peek)
5. **Timer expires at 10 seconds**
6. All players → `waiting` status
7. Game round starts automatically
8. Frontend receives status updates

### Scenario 2: All Players Complete Early
1. `start_match` called
2. All players → `initialPeek` status
3. 10-second timer starts
4. Player 1 completes peek → `waiting`
5. Player 2 completes peek → `waiting`
6. **All players completed!**
7. Timer cancelled
8. Game round starts immediately
9. Frontend receives status updates

### Scenario 3: Some Players Complete, Some Don't
1. `start_match` called
2. All players → `initialPeek` status
3. 10-second timer starts
4. Player 1 completes peek → `waiting`
5. Player 2 doesn't peek (still `initialPeek`)
6. **Timer expires at 10 seconds**
7. Player 2 forced to `waiting`
8. Game round starts automatically
9. Frontend receives status updates

---

## 📋 Testing Checklist

- [ ] Timer starts when match begins
- [ ] All players show `initial_peek` status
- [ ] Players can complete peek early (manual completion)
- [ ] Early completion sets player to `waiting`
- [ ] Timer expires after 10 seconds
- [ ] All players transition to `waiting` on timeout
- [ ] Game starts automatically after timeout
- [ ] Frontend receives all status updates
- [ ] Timer is cancelled if all players complete early
- [ ] Game starts immediately if all complete early

---

## 🚀 Implementation Priority

**HIGH PRIORITY**:
1. Add timer to Dart GameState
2. Implement `startInitialPeekTimer()`
3. Implement `_onInitialPeekTimeout()`
4. Call timer from `startMatch()`

**MEDIUM PRIORITY**:
5. Handle manual completion
6. Add early completion logic
7. Test all scenarios

**LOW PRIORITY**:
8. Add timer UI to frontend
9. Display countdown to users
10. Add timer configuration options

---

## 🔄 Status Update Flow

```
START MATCH
    ↓
Set all players → initialPeek
    ↓
Start 10-second Timer
    ↓
[10 seconds pass OR all players complete]
    ↓
Set all players → waiting
    ↓
player.updateStatus() triggers change detection
    ↓
coordinator.sendPlayerStateUpdate() for each player
    ↓
Frontend receives player_state_updated events
    ↓
Game round starts
    ↓
Frontend shows game in progress
```

---

## 📝 Notes

- Timer uses Dart's `Timer` class (not threading like Python)
- Timer automatically runs on the event loop
- Status changes trigger the existing change detection system
- Frontend will receive updates automatically through existing infrastructure
- No changes needed to Python coordinator or frontend handlers

**The timer implementation will leverage the existing status change system we just implemented!** 🎉

