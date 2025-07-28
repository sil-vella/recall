# Recall Game System

A comprehensive implementation of the Recall card game with declarative rule processing, AI players, and real-time WebSocket communication.

## Overview

The Recall game system is built on the Python Base 04 architecture and provides:

- **Declarative Game Logic**: Game rules are defined in YAML files for easy modification
- **AI Players**: Computer players with configurable difficulty levels
- **Real-time Communication**: WebSocket-based multiplayer support using existing architecture
- **Special Power Cards**: Extended game mechanics with special abilities
- **Modular Architecture**: Clean separation of concerns

## Architecture

### Core Components

```
recall_game/
├── models/                    # Data models
│   ├── card.py               # Card and deck system
│   ├── player.py             # Human and computer players
│   └── game_state.py         # Game state management
├── game_logic/               # Game logic engine
│   ├── game_logic_engine.py  # Main logic processor
│   ├── computer_player_logic.py # AI decision making
│   └── yaml_loader.py        # YAML rule loader
├── websocket_handlers/       # Real-time communication
│   └── game_websocket_manager.py
├── game_rules/               # Declarative rules
│   ├── actions/              # Action rules
│   ├── cards/                # Card-specific rules
│   ├── special_powers/       # Special power rules
│   └── ai_logic/             # AI decision rules
└── example_usage.py          # Usage examples
```

## Integration with Python Base 04

### WebSocket Integration

The Recall game system integrates with the existing WebSocket architecture:

```python
# Initialize with app_manager
websocket_manager = RecallGameWebSocketManager(app_manager)
websocket_manager.initialize(app_manager)

# Register game-specific handlers
websocket_manager.register_handler('recall_join_game', handler_function)
websocket_manager.register_handler('recall_player_action', handler_function)
```

### Event Flow

1. **Client Connection**: Uses existing WebSocket manager
2. **Game Events**: Registered with `recall_` prefix
3. **Session Management**: Leverages existing session tracking
4. **Room Management**: Uses existing room system
5. **Broadcasting**: Uses existing broadcast methods

### WebSocket Events

| Event | Description | Data |
|-------|-------------|------|
| `recall_join_game` | Join a game | `session_id`, `game_id`, `player_name`, `player_type` |
| `recall_leave_game` | Leave a game | `session_id`, `game_id` |
| `recall_player_action` | Play a card | `session_id`, `game_id`, `action_type`, `card_id` |
| `recall_call_recall` | Call Recall | `session_id`, `game_id` |
| `recall_play_out_of_turn` | Play out of turn | `session_id`, `game_id`, `card_id` |
| `recall_use_special_power` | Use special power | `session_id`, `game_id`, `power_type`, `target_data` |

## Game Rules

### Card Point System
- **Joker Cards**: 0 points
- **Red King**: 0 points
- **Ace cards**: 1 point
- **Numbered cards**: Points equal to their number (2-10)
- **All Kings (except red)**: 10 points
- **All Queens and Jacks**: 10 points
- **Added Power cards**: Special added powers (subject to conditions)

### Special Card Abilities
- **Queens**: When played, look at any one card (own or other player's)
- **Jacks**: When played, switch any two playing cards between any players
- **Added Power cards**: Additional special abilities beyond standard queen/jack powers

### Game Flow
1. **Setup**: Each player is dealt 4 cards face down
2. **Initial Look**: Players can look at any 2 of their 4 cards
3. **Turns**: Players draw and play cards, replacing played cards
4. **Out-of-turn Play**: Players can play cards of the same rank when others play
5. **Recall**: Any player can call "Recall" to start the final round
6. **End Game**: Player with least points wins (tiebreaker: least cards, then Recall caller)

## Declarative Rules System

### Action Rules (`game_rules/actions/`)

Action rules define how player actions are processed:

```yaml
action_type: "play_card"
triggers:
  - condition: "is_player_turn"
    game_state: "player_turn"
    out_of_turn: false

validation:
  - check: "player_has_card"
    card_id: "{card_id}"

effects:
  - type: "move_card_to_discard"
    card_id: "{card_id}"

notifications:
  - type: "broadcast"
    event: "card_played"
    data:
      player_id: "{player_id}"
      card: "{card_data}"
```

### Card Rules (`game_rules/cards/`)

Card-specific rules define special abilities:

```yaml
card_type: "queen"
points: 10
special_power: "peek_at_card"

power_effect:
  type: "peek_at_card"
  description: "Look at any one card (own or other player's)"
  validation:
    - check: "card_in_hand"
      card_rank: "queen"
```

### AI Decision Rules (`game_rules/ai_logic/`)

AI behavior is defined declaratively:

```yaml
decision_type: "play_card"
evaluation:
  - factor: "card_points"
    weight: 0.4
    strategy: "minimize_points"

decision_logic:
  - if: "has_low_point_card"
    then: "play_lowest_point_card"
  - else: "play_safest_card"
```

## Usage Examples

### Module Integration

```python
from core.recall_game.websocket_handlers.game_websocket_manager import RecallGameWebSocketManager

class RecallGameModule:
    def __init__(self, app_manager):
        self.app_manager = app_manager
        self.websocket_manager = None
    
    def initialize(self):
        """Initialize the Recall game module"""
        self.websocket_manager = RecallGameWebSocketManager(self.app_manager)
        self.websocket_manager.initialize(self.app_manager)
    
    def create_game(self, max_players=4):
        """Create a new game"""
        return self.websocket_manager.game_state_manager.create_game(max_players)
```

### WebSocket Event Handling

```python
# Client joins game
{
    "event": "recall_join_game",
    "data": {
        "session_id": "session_123",
        "game_id": "game_456",
        "player_name": "Alice",
        "player_type": "human"
    }
}

# Client plays card
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

### Processing Player Actions

```python
# Player action
action_data = {
    'action_type': 'play_card',
    'player_id': 'player_1',
    'card_id': 'ace_hearts_1234',
    'game_id': game_id
}

# Process through declarative rules
result = game_logic_engine.process_player_action(game_state, action_data)

if result.get('success'):
    print("Card played successfully")
else:
    print(f"Error: {result.get('error')}")
```

## AI Players

### Difficulty Levels

- **Easy**: Basic card selection, minimal strategy
- **Medium**: Balanced approach, considers special powers
- **Hard**: Advanced strategy, optimal play

### AI Decision Making

AI players use declarative rules to make decisions:

1. **Evaluate Game State**: Assess current position
2. **Calculate Card Values**: Consider points and special powers
3. **Apply Strategy**: Follow difficulty-specific rules
4. **Execute Action**: Play card or call Recall

## Special Power Cards

### Available Powers

- **Steal Card**: Take a card from another player
- **Draw Extra**: Draw additional cards
- **Protect Card**: Prevent card from being stolen
- **Skip Turn**: Skip the next player's turn
- **Double Points**: Double the points of played cards

### Power Usage

Special powers are triggered when their cards are played:

```python
# Use special power
power_data = {
    'session_id': 'session_123',
    'game_id': game_id,
    'power_type': 'steal_card',
    'target_data': {
        'target_player_id': 'player_2',
        'card_position': 0
    }
}

# Send via WebSocket
socket.emit('recall_use_special_power', power_data)
```

## Configuration

### Game Settings

```python
# Game configuration
game_config = {
    'max_players': 4,
    'include_jokers': True,
    'include_special_powers': True,
    'ai_difficulty': 'medium'
}
```

### Rule Customization

Modify YAML files in `game_rules/` to customize:

- Action processing logic
- Card special abilities
- AI decision making
- Game flow rules

## Testing

### Running Examples

```bash
cd python_base_04/core/recall_game
python example_usage.py
```

### Unit Tests

```python
# Test game logic
def test_card_play():
    game_state = GameState("test_game")
    # Add test logic

# Test AI decisions
def test_ai_decision():
    ai_logic = ComputerPlayerLogic("medium")
    # Add test logic

# Test WebSocket integration
def test_websocket_integration():
    websocket_manager = RecallGameWebSocketManager(app_manager)
    # Add test logic
```

## Deployment

### Requirements

- Python Base 04 dependencies
- Flask-SocketIO for WebSocket support
- PyYAML for rule processing
- Redis for state management

### Environment Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Configure Redis
redis-server

# Run the application
python app.py
```

## Contributing

### Adding New Rules

1. Create YAML file in appropriate `game_rules/` directory
2. Follow the established rule format
3. Update the `GameLogicEngine` to handle new rule types
4. Add tests for new functionality

### Extending AI Logic

1. Add new decision rules in `ai_logic/`
2. Implement new conditions in `ComputerPlayerLogic`
3. Update evaluation functions as needed

### Adding Special Powers

1. Define power in `special_powers/`
2. Implement power logic in `GameState`
3. Add WebSocket handlers for power usage

### WebSocket Integration

1. Register new handlers with `websocket_manager.register_handler()`
2. Use existing session and room management
3. Follow established event naming conventions (`recall_` prefix)
4. Use existing broadcast methods

## License

This project is proprietary and confidential. All rights reserved. 