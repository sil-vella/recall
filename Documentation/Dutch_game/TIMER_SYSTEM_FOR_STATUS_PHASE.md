# Phase-Based Timer System

## Overview

The Dutch game uses a **phase-based timer system** where timer durations are dynamically determined based on the current game phase and player status. Timer values are declared in a single location in `game_registry.dart` and automatically used by both backend logic and UI initialization.

## Architecture

### Single Source of Truth

Timer values are declared **once** in `ServerGameStateCallbackImpl.getAllTimerValues()`:
- **Location**: `lib/modules/dutch_game/backend_core/services/game_registry.dart`
- **Method**: `ServerGameStateCallbackImpl.getAllTimerValues()` (static method)
- **Format**: Centralized map of all timer values
- **Usage**: 
  - Backend logic (`getTimerConfig()`) reads from this method
  - UI initialization (`game_event_coordinator.dart`) reads from this method
  - No duplication - single source of truth

### Timer Configuration Flow

```
Timer Values Declaration
    ↓
ServerGameStateCallbackImpl.getAllTimerValues()
    ├─ Single source of truth for all timer values
    └─ Returns Map<String, int> with all durations
    ↓
    ├─→ Backend Logic (game_registry.dart)
    │   └─ getTimerConfig() reads from getAllTimerValues()
    │       └─ Returns turnTimeLimit based on phase/status
    │
    └─→ Game Initialization (game_event_coordinator.dart)
        └─ _handleStartMatch() reads from getAllTimerValues()
            └─ Adds timerConfig to game_state
                └─→ UI (unified_game_board_widget.dart)
                    ├─ Reads timerConfig from game_state
                    └─ Calculates timer based on phase/status
```

## Timer Value Declaration

### Single Source of Truth (game_registry.dart)

Timer values are declared **once** in `ServerGameStateCallbackImpl.getAllTimerValues()`:

```dart
/// Get all timer values as a map (for UI consumption)
/// This is the single source of truth for all timer durations
/// Static method - doesn't require roomId since values are constant
static Map<String, int> getAllTimerValues() {
  return {
    'initial_peek': 15,
    'drawing_card': 3420,
    'playing_card': 30,
    'same_rank_window': 10,
    'queen_peek': 15,
    'jack_swap': 20,
    'peeking': 10,
    'waiting': 0,
    'default': 30,
  };
}
```

### Backend Usage (getTimerConfig)

The `getTimerConfig()` method reads from `getAllTimerValues()` and applies priority logic:

```dart
// Get all timer values from single source of truth
final allTimerValues = ServerGameStateCallbackImpl.getAllTimerValues();

// Status-based timers (checked first - more specific)
switch (status) {
  case 'initial_peek':
    turnTimeLimit = allTimerValues['initial_peek'];
    break;
  case 'drawing_card':
    turnTimeLimit = allTimerValues['drawing_card'];
    break;
  case 'playing_card':
    turnTimeLimit = allTimerValues['playing_card'];
    break;
  // ... other status cases
}

// Phase-based timers (fallback if status not available)
switch (phase) {
  case 'initial_peek':
    turnTimeLimit = allTimerValues['initial_peek'];
    break;
  case 'player_turn':
  case 'playing':
    turnTimeLimit = allTimerValues['playing_card'];
    break;
  // ... other phase cases
  default:
    turnTimeLimit = allTimerValues['default'];
}
```

### Current Timer Values

| Status/Phase | Duration (seconds) | Description |
|--------------|-------------------|-------------|
| `initial_peek` | 15 | Initial card peek phase |
| `drawing_card` | 3420 | Player drawing a card |
| `playing_card` | 30 | Player playing a card |
| `same_rank_window` | 10 | Window for same rank plays |
| `queen_peek` | 15 | Queen card peek action |
| `jack_swap` | 20 | Jack card swap action |
| `peeking` | 10 | General peeking action |
| `waiting` | 0 | No timer (waiting state) |
| `default` | 30 | Fallback timer |

**Note**: All values are defined in `ServerGameStateCallbackImpl.getAllTimerValues()` and automatically used by both backend and UI.

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

During game initialization, `timerConfig` is added to `game_state` by reading from the single source of truth:

```dart
// In game_event_coordinator._handleStartMatch()
'timerConfig': ServerGameStateCallbackImpl.getAllTimerValues(), // Get timer values from registry (single source of truth)
```

**Purpose**: Allows UI to read timer values from `game_state` without hardcoding

**Location**: `game_state['timerConfig']` (nested in `games[gameId]['gameData']['game_state']`)

**Source**: Values are automatically read from `ServerGameStateCallbackImpl.getAllTimerValues()`, ensuring consistency between backend and UI.

## Backend Timer Usage

### game_registry.dart

The `getTimerConfig()` method:
- Reads current `phase` and `status` from `game_state`
- Gets timer values from `ServerGameStateCallbackImpl.getAllTimerValues()` (single source of truth)
- Applies priority logic (status → phase → default)
- Returns `turnTimeLimit` based on priority

**Files**:
- `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`

**Key Method**: `ServerGameStateCallbackImpl.getAllTimerValues()` - static method that returns all timer values as a map

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

**Single Location Update**: Timer values are declared in one place, and all other code automatically uses the updated values.

1. **Update `ServerGameStateCallbackImpl.getAllTimerValues()`** in both Flutter and Dart backend:
   - Modify the map returned by `getAllTimerValues()`
   - This is the **single source of truth** - all other code reads from here
   - No need to update switch cases or coordinator - they automatically use the new values

2. **Files to Update**:
   - `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
   - `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`

**Note**: The coordinator (`game_event_coordinator.dart`) automatically reads from `getAllTimerValues()`, so no changes needed there.

### Example: Changing Drawing Card Timer

```dart
// In game_registry.dart - ServerGameStateCallbackImpl.getAllTimerValues()
static Map<String, int> getAllTimerValues() {
  return {
    'initial_peek': 15,
    'drawing_card': 20,  // Changed from 3420 to 20
    'playing_card': 30,
    // ... other timers
  };
}
```

**That's it!** The change automatically applies to:
- Backend logic (`getTimerConfig()` reads from `getAllTimerValues()`)
- UI initialization (coordinator reads from `getAllTimerValues()`)
- No duplication, no manual synchronization needed

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
- [Computer Player Delay System](./COMPUTER_PLAYER_DELAY_SYSTEM.md) - How computer players use timer values for decision delays

## Summary

- **Single Source of Truth**: Timer values declared **once** in `ServerGameStateCallbackImpl.getAllTimerValues()` static method
- **Automatic Propagation**: Both backend logic (`getTimerConfig()`) and UI initialization (coordinator) read from the same source
- **Priority System**: Status checked before phase (status is more specific)
- **UI Integration**: `timerConfig` added to `game_state` by reading from `getAllTimerValues()`
- **Type Safety**: UI safely converts `Map<String, dynamic>` to `Map<String, int>`
- **No Duplication**: Single location for all timer values - no manual synchronization needed
- **Easy Updates**: Change timer values in one place (`getAllTimerValues()`), and all code automatically uses the new values
