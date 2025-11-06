# TODO: Add YAML Decision Logic for Collection Cards

## Current Status

✅ **Structure Already in Place:**
- `getCollectFromDiscardDecision()` method exists in `computer_player_factory.dart` (line 264)
- Method is called from `recall_game_round.dart` when collection rank matches top discard card
- Rank matching is done in Dart before YAML decision (correct approach)
- Method currently returns `collect: false` with placeholder reasoning

❌ **Missing:**
- YAML configuration for `collect_from_discard` in `computer_player_config.yaml`
- YAML rule evaluation logic in `getCollectFromDiscardDecision()`
- Game data preparation for collection decision (similar to `_prepareSpecialPlayGameData`)

## Required Implementation

### 1. YAML Configuration Structure

Add to `flutter_base_05/assets/computer_player_config.yaml`:

```yaml
  collect_from_discard:
    # Decision logic for collecting from discard pile
    optimal_collect_probability:
      easy: 0.6      # 60% chance to collect optimally
      medium: 0.8    # 80% chance to collect optimally
      hard: 0.95     # 95% chance to collect optimally
      expert: 1.0    # 100% chance to collect optimally (always optimal)
    
    # YAML-driven strategy rules (ordered from expert down to easy)
    strategy_rules:
      # Rule 1 (Expert/Hard): Collect if it helps reduce points
      - name: "collect_if_reduces_points"
        priority: 1
        description: "Collect if the card reduces total points in hand"
        condition:
          type: "and"
          conditions:
            - field: "acting_player.hand"
              operator: "not_empty"
            - field: "discard_pile.top_card"
              operator: "exists"
        action:
          type: "collect_from_discard"
        execution_probability:
          expert: 1.0    # 100% chance to execute if condition met
          hard: 0.95     # 95% chance to execute if condition met
          medium: 0.7    # 70% chance to execute if condition met
          easy: 0.5      # 50% chance to execute if condition met
      
      # Rule 2 (Medium/Easy): Collect if it doesn't increase points significantly
      - name: "collect_if_low_points"
        priority: 2
        description: "Collect if the card has low points (doesn't hurt much)"
        condition:
          type: "and"
          conditions:
            - field: "discard_pile.top_card.points"
              operator: "less_than"
              value: 5
        action:
          type: "collect_from_discard"
        execution_probability:
          expert: 0.0    # 0% chance (expert uses rule 1)
          hard: 0.05     # 5% chance (hard prefers rule 1)
          medium: 0.3    # 30% chance (medium uses this as fallback)
          easy: 0.5      # 50% chance (easy uses this more often)
      
      # Rule 3: Skip collection (fallback)
      - name: "skip_collect"
        priority: 3
        description: "Skip collecting from discard pile"
        condition:
          type: "always"
        action:
          type: "skip_collect"
```

### 2. Update `getCollectFromDiscardDecision()` Method

**Location:** `flutter_base_05/lib/modules/recall_game/game_logic/practice_match/shared_logic/utils/computer_player_factory.dart`

**Current Implementation (line 264):**
```dart
Map<String, dynamic> getCollectFromDiscardDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
  final decisionDelay = config.getDecisionDelay(difficulty);
  
  // For now, return empty decision (YAML not implemented yet)
  return {
    'action': 'collect_from_discard',
    'collect': false, // YAML not implemented yet
    'delay_seconds': decisionDelay,
    'difficulty': difficulty,
    'reasoning': 'Collect from discard decision (YAML not implemented yet)',
  };
}
```

**Required Changes:**
1. Use `_prepareSpecialPlayGameData()` to prepare game data (similar to `getJackSwapDecision` and `getQueenPeekDecision`)
2. Add discard pile top card to game data
3. Use `_evaluateSpecialPlayRules()` to evaluate YAML rules (similar to special plays)
4. Handle `collect_from_discard` action type in `_executeSpecialPlayAction()`
5. Return decision with `collect: true/false` based on YAML evaluation

**Pattern to Follow:**
- Same structure as `getJackSwapDecision()` and `getQueenPeekDecision()`
- Use `_prepareSpecialPlayGameData()` for data preparation
- Use `_evaluateSpecialPlayRules()` for rule evaluation
- Include fallback logic if a rule doesn't yield valid results

### 3. Alignment with Other Decision Structures

**Ensure consistency with:**
- ✅ `jack_swap` - Uses `_prepareSpecialPlayGameData()` and `_evaluateSpecialPlayRules()`
- ✅ `queen_peek` - Uses `_prepareSpecialPlayGameData()` and `_evaluateSpecialPlayRules()`
- ✅ `play_card` - Uses `_prepareGameDataForYAML()` and `_evaluateStrategyRules()`

**Key Differences:**
- `collect_from_discard` is simpler (binary decision: collect or not)
- No target selection needed (only one card to collect)
- Action type should be `collect_from_discard` (not `use_special_play`)

### 4. Action Execution

**Update `_executeSpecialPlayAction()` method:**
- Add case for `collect_from_discard` action type
- Return `{'collect': true, 'reasoning': ruleName}` or `{'collect': false, 'reasoning': ruleName}`

**Note:** The actual collection logic is already implemented in `handleCollectFromDiscard()` in `recall_game_round.dart` - we only need to wire the YAML decision.

## Implementation Checklist

- [ ] Add `collect_from_discard` section to `computer_player_config.yaml`
- [ ] Add `optimal_collect_probability` configuration
- [ ] Add `strategy_rules` list with priority-based rules
- [ ] Update `getCollectFromDiscardDecision()` to use YAML evaluation
- [ ] Add discard pile top card to game data preparation
- [ ] Update `_executeSpecialPlayAction()` to handle `collect_from_discard` action
- [ ] Ensure fallback logic works (try next rule if current rule doesn't yield result)
- [ ] Test with different difficulty levels
- [ ] Verify decision aligns with other special play decisions

## Notes

- Rank matching is already done in Dart (correct approach)
- YAML only handles the AI decision (collect or not)
- Structure should match `jack_swap` and `queen_peek` for consistency
- Priority-based rules ensure expert players use optimal strategies first
- Execution probability allows difficulty-based decision making

