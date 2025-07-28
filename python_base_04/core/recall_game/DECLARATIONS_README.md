# Declarative Rules System - Complete Guide

## Overview

The Recall game system uses a **declarative rule-based architecture** where game logic is defined in YAML files rather than hardcoded. This allows for easy modification, testing, and extension of game rules without changing the core engine.

## Architecture Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   WebSocket     │───▶│  Game Logic      │───▶│  YAML Rules     │
│   Event         │    │  Engine          │    │  Files          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Event Data     │    │  Rule Matching   │    │  Rule Loading   │
│  (JSON)         │    │  & Execution     │    │  (YAMLLoader)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Validation     │    │  Effects         │    │  Notifications  │
│  & Processing   │    │  & State Changes │    │  & Broadcasting │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Complete Event Flow

### 1. Event Reception
```python
# WebSocket event received
{
    "event": "recall_player_action",
    "data": {
        "session_id": "session_123",
        "game_id": "game_456",
        "action_type": "play_card",
        "card_id": "ace_hearts_1234"
    }
}
```

### 2. Rule Processing
```python
# GameLogicEngine.process_player_action()
def process_player_action(self, game_state, action_data):
    action_type = action_data.get('action_type')
    
    # Find matching rule
    rule = self._find_matching_rule(action_type, game_state, action_data)
    if rule:
        return self._execute_rule(rule, game_state, action_data)
    
    return {'error': 'Invalid action'}
```

### 3. Rule Matching
```python
# Check if rule applies to current state
def _rule_applies(self, rule, game_state, action_data):
    triggers = rule.get('triggers', [])
    
    for trigger in triggers:
        if self._trigger_matches(trigger, game_state, action_data):
            return True
    
    return False
```

### 4. Validation
```python
# Validate action according to rule
def _validate_action(self, rule, game_state, action_data):
    validation_rules = rule.get('validation', [])
    errors = []
    
    for validation in validation_rules:
        check_type = validation.get('check')
        # Perform validation checks
        if check_type == "player_has_card":
            # Check if player has the card
        elif check_type == "card_is_playable":
            # Check if card can be played
    
    return {'valid': len(errors) == 0, 'errors': errors}
```

### 5. Effect Execution
```python
# Execute effects from rule
def _execute_rule(self, rule, game_state, action_data):
    effects = rule.get('effects', [])
    for effect in effects:
        effect_result = self._execute_effect(effect, game_state, action_data)
        # Apply effect to game state
```

### 6. Notification Generation
```python
# Generate notifications for broadcasting
def _generate_notification(self, notification, game_state, action_data):
    notification_type = notification.get('type')
    event = notification.get('event')
    data_template = notification.get('data', {})
    
    # Replace placeholders with actual values
    data = self._replace_placeholders(data_template, game_state, action_data)
    
    return {
        'type': notification_type,
        'event': event,
        'data': data
    }
```

## Rule Structure

### Action Rules (`game_rules/actions/`)

Action rules define how player actions are processed:

```yaml
action_type: "play_card"                    # Rule identifier
triggers:                                   # When this rule applies
  - condition: "is_player_turn"            # Condition to check
    game_state: "player_turn"              # Required game state
    out_of_turn: false                     # Additional parameters
  - condition: "same_rank_card"            # Alternative trigger
    game_state: "out_of_turn_play"
    out_of_turn: true

validation:                                 # Validation checks
  - check: "player_has_card"               # Check type
    card_id: "{card_id}"                   # Parameter with placeholder
  - check: "card_is_playable"
    card_rank: "{card_rank}"

effects:                                   # State changes to apply
  - type: "move_card_to_discard"          # Effect type
    from: "player_hand"
    to: "discard_pile"
    card_id: "{card_id}"
  
  - type: "replace_card_in_hand"          # Another effect
    player_id: "{player_id}"
    new_card: "drawn_card"
  
  - type: "check_special_power"           # Special power check
    card_rank: "{card_rank}"
    if_power: "trigger_special_ability"
  
  - type: "check_recall_opportunity"      # Recall opportunity
    if_called: "start_final_round"

notifications:                             # Events to broadcast
  - type: "broadcast"                      # Notification type
    event: "card_played"                   # Event name
    data:                                 # Event data with placeholders
      player_id: "{player_id}"
      card: "{card_data}"
      is_out_of_turn: "{out_of_turn}"

  - type: "broadcast"
    event: "check_out_of_turn_play"
    data:
      played_card_rank: "{card_rank}"
      timeout: 5000
```

### Card Rules (`game_rules/cards/`)

Card-specific rules define special abilities:

```yaml
card_type: "queen"                         # Card type
points: 10                                 # Point value
special_power: "peek_at_card"             # Special power type

power_effect:                              # Power effect definition
  type: "peek_at_card"                    # Effect type
  description: "Look at any one card (own or other player's)"
  validation:                              # Power validation
    - check: "card_in_hand"
      card_rank: "queen"
  execution:                               # Power execution
    - type: "show_card_to_player"
      target_player: "{player_id}"
      card_owner: "{target_player_id}"
      card_position: "{card_position}"
  notifications:                           # Power notifications
    - type: "private"
      event: "card_revealed"
      target: "{player_id}"
      data:
        card: "{card_data}"
        owner: "{card_owner}"

play_conditions:                           # When card can be played
  - condition: "is_player_turn"
  - condition: "card_in_hand"
    card_rank: "queen"

out_of_turn_play:                         # Out-of-turn play rules
  allowed: true
  condition: "same_rank_card"
```

### Special Power Rules (`game_rules/special_powers/`)

Additional power card rules:

```yaml
power_id: "steal_card"                    # Power identifier
card_type: "added_power"                  # Card type
points: 5                                 # Point value
special_power: "steal_card"               # Power type

power_effect:                              # Power effect
  type: "steal_card"
  description: "Steal a card from another player's hand"
  validation:                              # Validation
    - check: "target_player_has_cards"
      target_player: "{target_player_id}"
  execution:                               # Execution
    - type: "move_card"
      from_player: "{target_player_id}"
      to_player: "{player_id}"
      card_position: "{card_position}"
  notifications:                           # Notifications
    - type: "private"
      event: "card_stolen"
      target: "{target_player_id}"
    - type: "broadcast"
      event: "power_card_used"
      data:
        player_id: "{player_id}"
        power_type: "steal_card"

play_conditions:                           # Play conditions
  - condition: "is_player_turn"
  - condition: "card_in_hand"
    card_rank: "power_steal_card"

out_of_turn_play:                         # Out-of-turn rules
  allowed: false
```

### AI Decision Rules (`game_rules/ai_logic/`)

AI behavior is defined declaratively:

```yaml
decision_type: "play_card"                 # Decision type
triggers:                                  # When to make this decision
  - condition: "is_my_turn"
    priority: 1

evaluation:                                # Evaluation factors
  - factor: "card_points"                  # Factor name
    weight: 0.4                           # Weight in decision
    strategy: "minimize_points"            # Strategy to apply
  
  - factor: "special_power_utility"
    weight: 0.3
    strategy: "maximize_utility"
  
  - factor: "game_progression"
    weight: 0.2
    strategy: "advance_position"
  
  - factor: "risk_assessment"
    weight: 0.1
    strategy: "minimize_risk"

decision_logic:                            # Decision logic
  - if: "has_low_point_card"              # Condition
    then: "play_lowest_point_card"        # Action
  
  - if: "has_special_power_card"
    and: "power_is_useful"                # Multiple conditions
    then: "play_special_power_card"
  
  - if: "can_call_recall"
    and: "advantageous_position"
    then: "call_recall"
  
  - else: "play_safest_card"              # Default action

default_action: "play_safest_card"         # Fallback action
```

## Placeholder System

### Available Placeholders

The system supports dynamic placeholders that are replaced with actual values:

```yaml
# In rule definition
card_id: "{card_id}"                      # From action_data
player_id: "{player_id}"                  # From action_data
card_rank: "{card_rank}"                  # From action_data
out_of_turn: "{out_of_turn}"             # From action_data
card_data: "{card_data}"                  # Generated card info
```

### Placeholder Resolution

```python
def _get_placeholder_value(self, placeholder, game_state, action_data):
    if placeholder == "player_id":
        return action_data.get('player_id')
    elif placeholder == "card_id":
        return action_data.get('card_id')
    elif placeholder == "card_rank":
        return action_data.get('card_rank')
    elif placeholder == "out_of_turn":
        return action_data.get('out_of_turn', False)
    elif placeholder == "card_data":
        return {
            'card_id': action_data.get('card_id'),
            'rank': action_data.get('card_rank')
        }
    return placeholder
```

## Effect Types

### Built-in Effects

```python
# Move card to discard pile
- type: "move_card_to_discard"
  card_id: "{card_id}"

# Replace card in hand
- type: "replace_card_in_hand"
  player_id: "{player_id}"
  new_card: "drawn_card"

# Check special power
- type: "check_special_power"
  card_rank: "{card_rank}"
  if_power: "trigger_special_ability"

# Check recall opportunity
- type: "check_recall_opportunity"
  if_called: "start_final_round"

# Move to next player
- type: "next_player"
```

### Effect Implementation

```python
def _execute_effect(self, effect, game_state, action_data):
    effect_type = effect.get('type')
    
    if effect_type == "move_card_to_discard":
        return self._effect_move_card_to_discard(effect, game_state, action_data)
    elif effect_type == "replace_card_in_hand":
        return self._effect_replace_card_in_hand(effect, game_state, action_data)
    elif effect_type == "check_special_power":
        return self._effect_check_special_power(effect, game_state, action_data)
    elif effect_type == "check_recall_opportunity":
        return self._effect_check_recall_opportunity(effect, game_state, action_data)
    elif effect_type == "next_player":
        return self._effect_next_player(effect, game_state, action_data)
```

## Validation Types

### Built-in Validations

```python
# Check if player has a specific card
- check: "player_has_card"
  card_id: "{card_id}"

# Check if card is playable
- check: "card_is_playable"
  card_rank: "{card_rank}"

# Check if it's player's turn
- check: "is_player_turn"
  player_id: "{player_id}"
```

### Validation Implementation

```python
def _validate_action(self, rule, game_state, action_data):
    validation_rules = rule.get('validation', [])
    errors = []
    
    for validation in validation_rules:
        check_type = validation.get('check')
        
        if check_type == "player_has_card":
            card_id = validation.get('card_id')
            if not self._player_has_card(game_state, action_data.get('player_id'), card_id):
                errors.append(f"Player does not have card {card_id}")
        
        elif check_type == "card_is_playable":
            card_rank = validation.get('card_rank')
            if not self._card_is_playable(game_state, action_data.get('player_id'), card_rank):
                errors.append(f"Card {card_rank} is not playable")
        
        elif check_type == "is_player_turn":
            if game_state.current_player_id != action_data.get('player_id'):
                errors.append("Not player's turn")
    
    return {'valid': len(errors) == 0, 'errors': errors}
```

## Trigger Conditions

### Built-in Conditions

```python
# Is player's turn
condition: "is_player_turn"

# Same rank card played
condition: "same_rank_card"

# Recall has been called
condition: "recall_called"

# Game state matches
game_state: "player_turn"
game_state: "out_of_turn_play"
game_state: "recall_called"

# Out-of-turn play
out_of_turn: true
out_of_turn: false
```

### Trigger Implementation

```python
def _trigger_matches(self, trigger, game_state, action_data):
    condition = trigger.get('condition')
    required_game_state = trigger.get('game_state')
    out_of_turn = trigger.get('out_of_turn', False)
    
    # Check game state
    if required_game_state and game_state.phase.value != required_game_state:
        return False
    
    # Check out-of-turn condition
    if out_of_turn and game_state.current_player_id == action_data.get('player_id'):
        return False
    
    # Check specific conditions
    if condition == "is_player_turn":
        return game_state.current_player_id == action_data.get('player_id')
    elif condition == "same_rank_card":
        return self._has_same_rank_card(game_state, action_data)
    elif condition == "recall_called":
        return game_state.phase.value == "recall_called"
    
    return True
```

## Notification Types

### Built-in Notification Types

```yaml
# Broadcast to all players in game
- type: "broadcast"
  event: "card_played"
  data:
    player_id: "{player_id}"
    card: "{card_data}"

# Private message to specific player
- type: "private"
  event: "card_revealed"
  target: "{player_id}"
  data:
    card: "{card_data}"
    owner: "{card_owner}"
```

### Notification Implementation

```python
def _generate_notification(self, notification, game_state, action_data):
    notification_type = notification.get('type')
    event = notification.get('event')
    data_template = notification.get('data', {})
    
    # Replace placeholders in data template
    data = self._replace_placeholders(data_template, game_state, action_data)
    
    return {
        'type': notification_type,
        'event': event,
        'data': data
    }
```

## Complete Example Flow

### 1. Client Sends Action
```javascript
// Client sends WebSocket event
socket.emit('recall_player_action', {
    session_id: 'session_123',
    game_id: 'game_456',
    action_type: 'play_card',
    card_id: 'queen_hearts_1234'
});
```

### 2. WebSocket Handler Receives
```python
def _handle_player_action(self, data):
    session_id = data.get('session_id')
    game_id = data.get('game_id')
    action_type = data.get('action_type')
    card_id = data.get('card_id')
    
    # Process through declarative rules
    action_data = {
        'action_type': action_type,
        'player_id': player_id,
        'card_id': card_id,
        'game_id': game_id
    }
    
    result = self.game_logic_engine.process_player_action(game_state, action_data)
```

### 3. Rule Matching
```python
# Find matching rule for "play_card"
rule = self._find_matching_rule("play_card", game_state, action_data)

# Check triggers
triggers = [
    {
        "condition": "is_player_turn",
        "game_state": "player_turn",
        "out_of_turn": false
    }
]

# Rule applies if trigger matches
if self._trigger_matches(trigger, game_state, action_data):
    return rule
```

### 4. Validation
```python
# Validate action
validation = [
    {
        "check": "player_has_card",
        "card_id": "queen_hearts_1234"
    },
    {
        "check": "card_is_playable",
        "card_rank": "queen"
    }
]

# Check each validation rule
for validation_rule in validation:
    if not self._validate_rule(validation_rule, game_state, action_data):
        return {'error': 'Validation failed'}
```

### 5. Effect Execution
```python
# Execute effects
effects = [
    {
        "type": "move_card_to_discard",
        "card_id": "queen_hearts_1234"
    },
    {
        "type": "replace_card_in_hand",
        "player_id": "player_1"
    },
    {
        "type": "check_special_power",
        "card_rank": "queen",
        "if_power": "trigger_special_ability"
    }
]

for effect in effects:
    result = self._execute_effect(effect, game_state, action_data)
```

### 6. Notification Generation
```python
# Generate notifications
notifications = [
    {
        "type": "broadcast",
        "event": "card_played",
        "data": {
            "player_id": "{player_id}",
            "card": "{card_data}",
            "is_out_of_turn": "{out_of_turn}"
        }
    }
]

for notification in notifications:
    notification_data = self._generate_notification(notification, game_state, action_data)
    # Broadcast notification
```

### 7. Response
```python
# Return result
return {
    'success': True,
    'action_type': 'play_card',
    'player_id': 'player_1',
    'effects': [
        {'type': 'move_card_to_discard', 'success': True},
        {'type': 'replace_card_in_hand', 'success': True},
        {'type': 'check_special_power', 'has_power': True, 'power_type': 'peek_at_card'}
    ],
    'notifications': [
        {
            'type': 'broadcast',
            'event': 'card_played',
            'data': {
                'player_id': 'player_1',
                'card': {'card_id': 'queen_hearts_1234', 'rank': 'queen'},
                'is_out_of_turn': False
            }
        }
    ]
}
```

## Extending the System

### Adding New Effect Types

1. **Define in YAML:**
```yaml
effects:
  - type: "custom_effect"
    parameter1: "value1"
    parameter2: "{placeholder}"
```

2. **Implement in GameLogicEngine:**
```python
def _execute_effect(self, effect, game_state, action_data):
    effect_type = effect.get('type')
    
    if effect_type == "custom_effect":
        return self._effect_custom_effect(effect, game_state, action_data)
    # ... other effects

def _effect_custom_effect(self, effect, game_state, action_data):
    # Implement custom effect logic
    parameter1 = effect.get('parameter1')
    parameter2 = effect.get('parameter2')
    
    # Perform effect
    return {
        'type': 'custom_effect',
        'success': True,
        'result': 'effect_result'
    }
```

### Adding New Validation Types

1. **Define in YAML:**
```yaml
validation:
  - check: "custom_validation"
    parameter: "value"
```

2. **Implement in GameLogicEngine:**
```python
def _validate_action(self, rule, game_state, action_data):
    validation_rules = rule.get('validation', [])
    errors = []
    
    for validation in validation_rules:
        check_type = validation.get('check')
        
        if check_type == "custom_validation":
            parameter = validation.get('parameter')
            if not self._custom_validation(game_state, action_data, parameter):
                errors.append("Custom validation failed")
        # ... other validations
    
    return {'valid': len(errors) == 0, 'errors': errors}

def _custom_validation(self, game_state, action_data, parameter):
    # Implement custom validation logic
    return True  # or False
```

### Adding New Trigger Conditions

1. **Define in YAML:**
```yaml
triggers:
  - condition: "custom_condition"
    parameter: "value"
```

2. **Implement in GameLogicEngine:**
```python
def _trigger_matches(self, trigger, game_state, action_data):
    condition = trigger.get('condition')
    
    if condition == "custom_condition":
        parameter = trigger.get('parameter')
        return self._check_custom_condition(game_state, action_data, parameter)
    # ... other conditions
    
    return True

def _check_custom_condition(self, game_state, action_data, parameter):
    # Implement custom condition logic
    return True  # or False
```

## Best Practices

### 1. Rule Organization
- Keep rules focused and single-purpose
- Use descriptive names for rule files
- Group related rules in appropriate directories

### 2. Placeholder Usage
- Use placeholders for dynamic values
- Keep placeholder names descriptive
- Document available placeholders

### 3. Validation
- Always validate inputs
- Provide clear error messages
- Use multiple validation checks when needed

### 4. Effects
- Make effects atomic and reversible when possible
- Document effect parameters
- Handle effect failures gracefully

### 5. Notifications
- Use appropriate notification types (broadcast vs private)
- Include relevant data in notifications
- Keep notification data minimal and focused

### 6. Testing
- Test rules in isolation
- Test rule combinations
- Test edge cases and error conditions

## Debugging

### Rule Loading Issues
```python
# Check if rules are loaded correctly
yaml_loader = YAMLLoader()
action_rules = yaml_loader.load_action_rules()
print(f"Loaded {len(action_rules)} action rules: {list(action_rules.keys())}")
```

### Rule Matching Issues
```python
# Debug rule matching
def _find_matching_rule(self, action_type, game_state, action_data):
    if action_type not in self.action_rules:
        print(f"No rule found for action_type: {action_type}")
        return None
    
    rule = self.action_rules[action_type]
    print(f"Found rule: {rule}")
    
    if self._rule_applies(rule, game_state, action_data):
        print("Rule applies")
        return rule
    else:
        print("Rule does not apply")
        return None
```

### Effect Execution Issues
```python
# Debug effect execution
def _execute_effect(self, effect, game_state, action_data):
    effect_type = effect.get('type')
    print(f"Executing effect: {effect_type}")
    
    result = None
    if effect_type == "move_card_to_discard":
        result = self._effect_move_card_to_discard(effect, game_state, action_data)
    # ... other effects
    
    print(f"Effect result: {result}")
    return result
```

This declarative system provides a powerful, flexible, and maintainable way to define game logic while keeping the core engine clean and extensible. 