# Computer Player Delay System

## Overview

The computer player delay system has been improved to use **timer-based delays** instead of fixed delays. This creates more realistic and dynamic AI behavior that adapts to the actual time available for each action. The system also includes **miss chance mechanics** to simulate human-like errors.

## Key Improvements

### 1. Timer-Based Delays (Replaces Fixed Delays)

**Old System**: Fixed delays from YAML configuration (e.g., `decision_delay_seconds: 3.0`)

**New System**: Dynamic delays calculated as **40% to 80% of the action timer**

**Benefits**:
- More realistic timing - AI responds faster when time is short
- Adapts to game phase - different delays for different actions
- Creates natural variation - randomized within the range

### 2. Miss Chance Mechanics

**New Feature**: Computer players can "miss" actions (fail to play) based on difficulty level

**Miss Chance Percentages**:
- **Easy**: 6% miss chance
- **Medium**: 4% miss chance
- **Hard**: 2% miss chance
- **Expert**: 1% miss chance

**Benefits**:
- Simulates human errors
- Makes AI feel more natural
- Difficulty-appropriate error rates

## How It Works

### Timer Configuration Source

Timer values are declared in `ServerGameStateCallbackImpl.getAllTimerValues()` (single source of truth):

```dart
static Map<String, int> getAllTimerValues() {
  return {
    'initial_peek': 10,
    'drawing_card': 5,
    'playing_card': 15,
    'same_rank_window': 5,
    'queen_peek': 10,
    'jack_swap': 10,
    'peeking': 5,
    'waiting': 0,
    'default': 30,
  };
}
```

These values are automatically added to `game_state['timerConfig']` during game initialization.

### Delay Calculation

For each action, the system:

1. **Reads Timer Value**: Gets the timer for the current action from `gameState['timerConfig']`
2. **Calculates Delay Range**: 40% to 80% of timer value
3. **Randomizes**: Selects random delay within the range

**Formula**:
```dart
minDelay = timerValue * 0.4
maxDelay = timerValue * 0.8
delay = minDelay + (random * (maxDelay - minDelay))
```

**Example**:
- Timer: 15 seconds (playing_card)
- Min delay: 6 seconds (15 * 0.4)
- Max delay: 12 seconds (15 * 0.8)
- Actual delay: Random between 6-12 seconds

### Miss Chance Check

Before making a decision, the system:

1. **Checks Miss Chance**: Compares random value against difficulty's miss chance
2. **If Missed**: Returns decision with `missed: true` flag, skips action
3. **If Not Missed**: Proceeds with normal decision-making

**Implementation**:
```dart
bool _checkMissChance(String difficulty) {
  final missChance = config.getMissChanceToPlay(difficulty);
  return _random.nextDouble() < missChance;
}
```

## Action-Specific Behavior

### 1. Draw Card Decision

**Timer Used**: `drawing_card` (default: 5 seconds)

**Delay Range**: 2.0 - 4.0 seconds (40-80% of 5s)

**Miss Chance**: Not applied (drawing is mandatory)

**Implementation**:
```dart
final drawingCardTimeLimit = timerConfig['drawing_card'] ?? 5;
final decisionDelay = _calculateTimerBasedDelay(drawingCardTimeLimit);
```

### 2. Play Card Decision

**Timer Used**: `playing_card` (default: 15 seconds)

**Delay Range**: 6.0 - 12.0 seconds (40-80% of 15s)

**Miss Chance**: Applied before card selection

**Flow**:
1. Calculate timer-based delay
2. Check miss chance → if missed, return `missed: true`
3. If not missed, proceed with card selection
4. Pass timer config to card selection for time pressure adjustments

**Implementation**:
```dart
final playingCardTimeLimit = timerConfig['playing_card'] ?? 15;
final decisionDelay = _calculateTimerBasedDelay(playingCardTimeLimit);

if (_checkMissChance(difficulty)) {
  return {
    'action': 'play_card',
    'card_id': null,
    'delay_seconds': decisionDelay,
    'missed': true,
    'reasoning': 'Missed play action (X% miss chance)',
  };
}
// ... continue with card selection
```

### 3. Same Rank Play Decision

**Timer Used**: `same_rank_window` (default: 5 seconds)

**Delay Range**: 2.0 - 4.0 seconds (40-80% of 5s)

**Miss Chance**: Applied before play probability check

**Flow**:
1. Calculate timer-based delay
2. Check miss chance → if missed, skip action
3. If not missed, check play probability (existing logic)
4. Continue with same rank play logic

### 4. Jack Swap Decision

**Timer Used**: `jack_swap` (default: 10 seconds)

**Delay Range**: 4.0 - 8.0 seconds (40-80% of 10s)

**Miss Chance**: Applied before YAML rules evaluation

**Flow**:
1. Calculate timer-based delay
2. Check miss chance → if missed, return `use: false, missed: true`
3. If not missed, evaluate YAML rules

### 5. Queen Peek Decision

**Timer Used**: `queen_peek` (default: 10 seconds)

**Delay Range**: 4.0 - 8.0 seconds (40-80% of 10s)

**Miss Chance**: Applied before YAML rules evaluation

**Flow**:
1. Calculate timer-based delay
2. Check miss chance → if missed, return `use: false, missed: true`
3. If not missed, evaluate YAML rules

### 6. Collect From Discard Decision

**Timer Used**: `same_rank_window` (default: 5 seconds)

**Delay Range**: 2.0 - 4.0 seconds (40-80% of 5s)

**Miss Chance**: Applied before YAML rules evaluation

**Note**: Uses `same_rank_window` timer since collection happens during the same rank window phase.

## Time Pressure Adjustments

### Card Selection Under Time Pressure

When the `playing_card` timer is less than 10 seconds, the AI adjusts its strategy:

**Adjustments**:
- **Optimal Play Probability**: Reduced by 30% (favor simpler decisions)
- **Strategy Selection**: Prefers faster/simpler strategies
- **YAML Rules Access**: Timer config passed to rules engine for conditional logic

**Implementation**:
```dart
final playingCardTimeLimit = timerConfig['playing_card'] ?? 30;
final isTimePressure = playingCardTimeLimit < 10;

if (isTimePressure) {
  optimalPlayProb = optimalPlayProb * 0.7; // 30% reduction
}

// Pass to YAML rules engine
gameData['timer_config'] = timerConfig;
gameData['time_pressure'] = isTimePressure;
gameData['playing_card_time_limit'] = playingCardTimeLimit;
```

## YAML Configuration

### Miss Chance Configuration

Added to `computer_player_config.yaml`:

```yaml
computer_settings:
  # Miss chance to play (probability of not playing when action is available)
  miss_chance_to_play:
    easy: 0.06    # 6% miss chance
    medium: 0.04  # 4% miss chance
    hard: 0.02    # 2% miss chance
    expert: 0.01  # 1% miss chance
```

### Legacy Delay Configuration

**Note**: The old `decision_delay_seconds` in difficulty configs is **no longer used** for action delays. It remains in the YAML for backward compatibility but is ignored by the new system.

**Old Configuration** (still present but unused):
```yaml
difficulties:
  easy:
    decision_delay_seconds: 3.0  # ❌ No longer used for delays
```

## Decision Execution

### Handling Missed Actions

When a decision has `missed: true`, the execution logic:

1. **Logs Miss**: Records miss chance trigger
2. **Increments Counter**: Adds to missed action counter (for auto-leave logic)
3. **Skips Action**: Does not execute the action
4. **Moves to Next**: Advances to next player/turn

**Implementation** (`dutch_game_round.dart`):
```dart
case 'play_card':
  final missed = decision['missed'] as bool? ?? false;
  if (missed) {
    _logger.info('Computer player $playerId missed play action (miss chance)');
    _missedActionCounts[playerId] = (_missedActionCounts[playerId] ?? 0) + 1;
    if (_missedActionCounts[playerId] == 2) {
      _onMissedActionThresholdReached(playerId);
    }
    _moveToNextPlayer();
    break;
  }
  // ... continue with normal execution
```

### Missed Action Counter

The system tracks missed actions for auto-leave logic:
- **Threshold**: 2 missed actions
- **Action**: Triggers auto-leave (same as timer expiry)
- **Reset**: Counter resets on successful actions

## Benefits of New System

### 1. Realistic Timing

- AI responds faster when time is short
- Delays adapt to game phase
- Creates natural variation in response times

### 2. Human-Like Behavior

- Miss chance simulates human errors
- Difficulty-appropriate error rates
- Makes AI feel more natural

### 3. Dynamic Adaptation

- Timer values can be changed in one place
- AI automatically adapts to new timer values
- No need to update delay configs separately

### 4. Time Pressure Awareness

- AI makes simpler decisions under time pressure
- Strategy adjusts based on available time
- YAML rules can access timer information

## Migration from Old System

### What Changed

1. **Delay Calculation**: From fixed YAML values to timer-based (40-80% range)
2. **Miss Chance**: New feature (not in old system)
3. **Timer Access**: AI can now read timer config from game state

### What Stayed the Same

1. **YAML Configuration**: Still uses `computer_player_config.yaml`
2. **Difficulty Levels**: Same difficulty system (easy, medium, hard, expert)
3. **Decision Methods**: Same method signatures and return formats
4. **Execution Flow**: Same execution logic (with miss handling added)

### Backward Compatibility

- Old `decision_delay_seconds` values remain in YAML (ignored)
- Decision return format unchanged (added `missed` flag)
- Execution logic handles both old and new formats

## Configuration Reference

### Timer Values (Single Source of Truth)

Located in `ServerGameStateCallbackImpl.getAllTimerValues()`:

| Timer Key | Default Value | Used By |
|-----------|--------------|---------|
| `drawing_card` | 5s | Draw card decision |
| `playing_card` | 15s | Play card decision |
| `same_rank_window` | 5s | Same rank play, collect decisions |
| `jack_swap` | 10s | Jack swap decision |
| `queen_peek` | 10s | Queen peek decision |
| `initial_peek` | 10s | Initial peek phase |
| `peeking` | 5s | Peeking status |
| `waiting` | 0s | Waiting status |
| `default` | 30s | Fallback timer |

### Miss Chance Values

Located in `computer_player_config.yaml`:

| Difficulty | Miss Chance | Percentage |
|------------|-------------|------------|
| `easy` | 0.06 | 6% |
| `medium` | 0.04 | 4% |
| `hard` | 0.02 | 2% |
| `expert` | 0.01 | 1% |

### Delay Range Formula

For any timer value `T`:
- **Minimum Delay**: `T * 0.4`
- **Maximum Delay**: `T * 0.8`
- **Actual Delay**: Random value between min and max

## Code Locations

### Implementation Files

**Flutter**:
- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/platform/computer_player_config_parser.dart`
- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`

**Dart Backend**:
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/utils/platform/computer_player_config_parser.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`

### Configuration Files

- `flutter_base_05/assets/computer_player_config.yaml`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/config/computer_player_config.yaml`

### Timer Declaration

- `flutter_base_05/lib/modules/dutch_game/backend_core/services/game_registry.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/services/game_registry.dart`

## Testing

### Test Scenarios

1. **Timer-Based Delays**:
   - Verify delays are within 40-80% range
   - Test with different timer values
   - Verify randomization

2. **Miss Chance**:
   - Test miss chance percentages for each difficulty
   - Verify missed actions are handled correctly
   - Test missed action counter

3. **Time Pressure**:
   - Test strategy adjustments under time pressure
   - Verify optimal play probability reduction
   - Test YAML rules with timer config

4. **Action-Specific**:
   - Test each action type (draw, play, same rank, jack, queen, collect)
   - Verify correct timer is used for each action
   - Test miss chance application

## Related Documentation

- [Phase-Based Timer System](./TIMER_SYSTEM_FOR_STATUS_PHASE.md) - Timer value declaration and configuration
- [Computer Player Implementation](./COMP_PLAYER_IMPLEMENTATION.md) - Overall computer player system
- [Timer and Leaving Logic](./TIMER_AND_LEAVING_LOGIC.md) - Timer lifecycle and missed action handling
