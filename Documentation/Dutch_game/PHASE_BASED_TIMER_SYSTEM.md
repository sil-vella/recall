# Phase-Based Timer System

## Overview

The Dutch game uses a **phase-based timer system** where timer durations are dynamically determined based on the current game phase and player status. Timer values are declared in `game_registry.dart` and added to `game_state` during game initialization for UI consumption.

## Architecture

### Single Source of Truth

Timer values are declared **once** in `game_registry.dart` switch cases:
- **Location**: `lib/modules/dutch_game/backend_core/services/game_registry.dart`
- **Method**: `getTimerConfig()`
- **Format**: Hardcoded values in switch statements

### Timer Configuration Flow

```
Game Initialization
    ↓
game_event_coordinator._handleStartMatch()
    ↓
Add timerConfig to game_state
    ↓
Backend Logic (game_registry.dart)
    ├─ Reads timer values from switch cases
    └─ Returns turnTimeLimit based on phase/status
    ↓
UI (unified_game_board_widget.dart)
    ├─ Reads timerConfig from game_state
    └─ Calculates timer based on phase/status
```

## Timer Value Declaration

### Backend Declaration (game_registry.dart)

Timer values are declared directly in switch cases within `getTimerConfig()`:

```dart
// Status-based timers (checked first - more specific)
switch (status) {
  case 'initial_peek':
    turnTimeLimit = 15;
    break;
  case 'drawing_card':
    turnTimeLimit = 10;  // Current value
    break;
  case 'playing_card':
    turnTimeLimit = 30;
    break;
  case 'same_rank_window':
    turnTimeLimit = 10;
    break;
  case 'queen_peek':
    turnTimeLimit = 15;
    break;
  case 'jack_swap':
    turnTimeLimit = 20;
    break;
  case 'peeking':
    turnTimeLimit = 10;
    break;
  case 'waiting':
    turnTimeLimit = 0;
    break;
}

// Phase-based timers (fallback if status not available)
switch (phase) {
  case 'initial_peek':
    turnTimeLimit = 15;
    break;
  case 'player_turn':
  case 'playing':
    turnTimeLimit = 30;  // Default for player turn
    break;
  case 'same_rank_window':
    turnTimeLimit = 10;
    break;
  case 'queen_peek_window':
    turnTimeLimit = 15;
    break;
  case 'special_play_window':
    turnTimeLimit = 20;
    break;
  default:
    turnTimeLimit = 30;  // Final fallback
}
```

### Current Timer Values

| Status/Phase | Duration (seconds) | Description |
|--------------|-------------------|-------------|
| `initial_peek` | 15 | Initial card peek phase |
| `drawing_card` | 10 | Player drawing a card |
| `playing_card` | 30 | Player playing a card |
| `same_rank_window` | 10 | Window for same rank plays |
| `queen_peek` | 15 | Queen card peek action |
| `jack_swap` | 20 | Jack card swap action |
| `peeking` | 10 | General peeking action |
| `waiting` | 0 | No timer (waiting state) |
| `default` | 30 | Fallback timer |

## Timer Priority System

### Status Over Phase

The system prioritizes **status** over **phase** because status is more specific:

1. **Check Status First**: If player has a specific status (e.g., `drawing_card`), use that timer
2. **Fallback to Phase**: If status is null/empty or doesn't match, check phase
3. **Final Fallback**: Default to 30 seconds if neither status nor phase provides a timer

### Example Priority Flow

```
Player Status: 'drawing_card'
Phase: 'player_turn'
    ↓
Check Status: 'drawing_card' → 10 seconds ✅
(Phase 'player_turn' is ignored)
```

```
Player Status: null
Phase: 'player_turn'
    ↓
Status check: No match
    ↓
Check Phase: 'player_turn' → 30 seconds ✅
```

## Game State Integration

### timerConfig in game_state

During game initialization, `timerConfig` is added to `game_state`:

```dart
// In game_event_coordinator._handleStartMatch()
'timerConfig': {
  'initial_peek': 15,
  'drawing_card': 10,
  'playing_card': 30,
  'same_rank_window': 10,
  'queen_peek': 15,
  'jack_swap': 20,
  'peeking': 10,
  'waiting': 0,
  'default': 30,
}
```

**Purpose**: Allows UI to read timer values from `game_state` without hardcoding

**Location**: `game_state['timerConfig']` (nested in `games[gameId]['gameData']['game_state']`)

## Backend Timer Usage

### game_registry.dart

The `getTimerConfig()` method:
- Reads current `phase` and `status` from `game_state`
- Uses hardcoded switch cases (not reading from `timerConfig` map)
- Returns `turnTimeLimit` based on priority (status → phase → default)

**Files**:
- `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`

### Timer Usage Points

1. **Draw Action Timer** (`dutch_game_round.dart`):
   - Called when player status changes to `drawing_card`
   - Uses `getTimerConfig()['turnTimeLimit']`

2. **Play Action Timer** (`dutch_game_round.dart`):
   - Called when player status changes to `playing_card`
   - Uses `getTimerConfig()['turnTimeLimit']`

3. **Same Rank Window Timer** (`dutch_game_round.dart`):
   - Called when same rank window opens
   - Uses `getTimerConfig()['turnTimeLimit']`

4. **Special Card Timer** (`dutch_game_round.dart`):
   - Called for queen peek or jack swap actions
   - Uses `getTimerConfig()['turnTimeLimit']`

5. **Initial Peek Timer** (`game_event_coordinator.dart`):
   - Called during initial peek phase
   - Reads from `game_state['timerConfig']['initial_peek']`

## UI Timer Usage

### unified_game_board_widget.dart

The UI reads `timerConfig` from `game_state` and calculates timers using the same priority logic:

1. **Opponent Cards Timer**:
   - Reads `gameState['timerConfig']`
   - Calculates based on `effectiveStatus` (priority) or `phase` (fallback)
   - Passes to `CircularTimerWidget`

2. **My Hand Timer**:
   - Reads `gameState['timerConfig']`
   - Calculates based on `playerStatus` (priority) or `phase` (fallback)
   - Passes to `CircularTimerWidget`

### Type Safety

The UI safely converts `Map<String, dynamic>` to `Map<String, int>`:

```dart
final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
final timerConfig = timerConfigRaw?.map((key, value) => 
  MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)
) ?? <String, int>{};
```

## Modifying Timer Values

### To Change Timer Durations

1. **Update game_registry.dart** (both Flutter and Dart backend):
   - Modify values in `getTimerConfig()` switch cases
   - Update status-based timers first
   - Update phase-based timers if needed

2. **Update game_event_coordinator.dart** (both Flutter and Dart backend):
   - Update `timerConfig` map in `_handleStartMatch()`
   - This ensures UI receives correct values

3. **Files to Update**:
   - `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
   - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`
   - `flutter_base_05/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart`
   - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart`

### Example: Changing Drawing Card Timer

```dart
// In game_registry.dart
case 'drawing_card':
  turnTimeLimit = 20;  // Changed from 10 to 20
  break;

// In game_event_coordinator.dart
'timerConfig': {
  'drawing_card': 20,  // Must match game_registry value
  // ... other timers
}
```

## Timer Lifecycle

### When Timers Start

1. **Draw Timer**: When player status becomes `drawing_card`
2. **Play Timer**: When player status becomes `playing_card`
3. **Same Rank Timer**: When same rank window phase begins
4. **Special Card Timer**: When queen peek or jack swap status is set
5. **Initial Peek Timer**: When game enters `initial_peek` phase

### When Timers Cancel

- Successful action completion (draw/play card)
- Moving to next player
- Timer expiry
- Game state changes that invalidate the timer

## Practice Mode

Practice mode uses the same timer system:
- Timer values are identical to multiplayer
- `timerConfig` is added to `game_state` in practice mode as well
- UI reads from `game_state['timerConfig']` in both modes

## State Schema

The `timerConfig` field is part of `game_state` schema:

```dart
'game_state': {
  // ... other fields
  'timerConfig': Map<String, int>,  // Phase-based timer configuration
  // timerConfig structure:
  //   'initial_peek': int,
  //   'drawing_card': int,
  //   'playing_card': int,
  //   'same_rank_window': int,
  //   'queen_peek': int,
  //   'jack_swap': int,
  //   'peeking': int,
  //   'waiting': int,
  //   'default': int,
}
```

## Related Documentation

- [Timer and Leaving Logic](./TIMER_AND_LEAVING_LOGIC.md) - Detailed timer lifecycle and leaving scenarios
- [State Management](./STATE_MANAGEMENT.md) - Complete game state schema including timerConfig
- [Player Actions Flow](./PLAYER_ACTIONS_FLOW.md) - How timers interact with player actions

## Summary

- **Single Source**: Timer values declared in `game_registry.dart` switch cases
- **Priority**: Status checked before phase (status is more specific)
- **UI Integration**: `timerConfig` added to `game_state` for UI to read
- **Type Safety**: UI safely converts `Map<String, dynamic>` to `Map<String, int>`
- **No Duplication**: Removed `PhaseTimerConfig` class, values only in registry
