# Recall Game - Flutter Implementation

This directory contains the Flutter UI components for the Recall card game, designed to work with the Python backend.

## 🏗️ Architecture

The Recall game follows the established Flutter Base 05 architecture patterns:

### **Core Components**

#### **Models** (`models/`)
- **`card.dart`** - Card data model with suit, rank, points, and special powers
- **`player.dart`** - Player model (human/computer), hand, score, status
- **`game_state.dart`** - Game phase, turn order, piles, game status
- **`game_events.dart`** - WebSocket event models for game actions

#### **Managers** (`managers/`)
- **`recall_game_manager.dart`** - Main game orchestrator, integrates with existing managers
- **`recall_websocket_manager.dart`** - Game-specific WebSocket handling, extends existing WebSocketManager
- **`recall_state_manager.dart`** - Game state management, integrates with StateManager

#### **Utils** (`utils/`)
- **`game_constants.dart`** - Game constants, settings, and configuration
- **`card_utils.dart`** - ~~Utility functions for card operations and display~~ (REMOVED - redundant, backend handles all card logic)
- **`game_utils.dart`** - General game utility functions
- **`websocket_utils.dart`** - WebSocket utility functions

## 🔌 Integration with Existing Architecture

### **WebSocket Integration**
The Recall game integrates with the existing WebSocket infrastructure:

```dart
// Extends existing WebSocketManager
final WebSocketManager _wsManager = WebSocketManager.instance;

// Game-specific events with 'recall_' prefix
await _wsManager.sendMessage(gameId, 'recall_join_game', {
  'game_id': gameId,
  'player_name': 'Player Name'
});
```

### **State Management Integration**
Integrates with the existing StateManager:

```dart
// Register game state
_stateManager.registerModuleState("recall_game", {
  "hasActiveGame": false,
  "gameId": null,
  "currentPlayerId": null,
  "gamePhase": "waiting",
  "isMyTurn": false,
  "canCallRecall": false,
  "myHand": [],
  "myScore": 0,
});
```

### **Manager Pattern**
Follows the established manager pattern:

```dart
class RecallGameManager {
  static final RecallGameManager _instance = RecallGameManager._internal();
  factory RecallGameManager() => _instance;
  
  // Integrates with existing managers
  final RecallWebSocketManager _wsManager = RecallWebSocketManager();
  final RecallStateManager _stateManager = RecallStateManager();
  final StateManager _mainStateManager = StateManager();
}
```

## 🎮 Game Features

### **Real-time Multiplayer**
- Live card plays and turn changes
- Player join/leave notifications
- Game state synchronization
- WebSocket-based communication

### **Card System**
- Standard 52-card deck
- Special powers (Queens, Jacks, Added Power cards)
- Point-based scoring
- Visual card display with animations

### **Player Types**
- **Human Players** - Real users with interactive UI
- **Computer Players** - AI opponents with configurable difficulty

### **Game Flow**
1. **Lobby** - Room creation and player joining
2. **Setup** - Card dealing and game initialization
3. **Playing** - Active gameplay with turns
4. **Recall Phase** - Final round after recall is called
5. **Results** - Winner announcement and scoring

## 🚀 Usage

### **Initialization**
```dart
final gameManager = RecallGameManager();
await gameManager.initialize();
```

### **Joining a Game**
```dart
final result = await gameManager.joinGame('game_123', 'Player Name');
if (result['error'] == null) {
  // Successfully joined game
}
```

### **Playing a Card**
```dart
final result = await gameManager.playCard(card);
if (result['error'] == null) {
  // Card played successfully
}
```

### **Calling Recall**
```dart
final result = await gameManager.callRecall();
if (result['error'] == null) {
  // Recall called successfully
}
```

### **Listening to Game Events**
```dart
gameManager.gameEvents.listen((event) {
  switch (event.type) {
    case GameEventType.cardPlayed:
      // Handle card played event
      break;
    case GameEventType.recallCalled:
      // Handle recall called event
      break;
  }
});
```

## 🎨 UI Components (Planned)

### **Screens** (`screens/`)
- **`game_lobby_screen.dart`** - Room creation, joining, player list
- **`game_room_screen.dart`** - Pre-game setup, player ready states
- **`game_play_screen.dart`** - Main game interface with cards, controls
- **`game_results_screen.dart`** - Final scores, winner announcement

### **Widgets** (`widgets/`)
- **Cards** - Visual card components, hand display, pile management
- **Players** - Player info, avatars, hand visualization
- **Game** - Board layout, controls, timer, Recall button
- **UI** - Dialogs, toasts, loading states

## 🔧 Configuration

### **Game Settings**
```dart
static const Map<String, dynamic> DEFAULT_GAME_SETTINGS = {
  'maxPlayers': 6,
  'cardsPerPlayer': 7,
  'pointsToWin': 50,
  'allowComputerPlayers': true,
  'aiDifficulty': 'medium',
  'specialPowersEnabled': true,
  'addedPowerCardsEnabled': true,
};
```

### **AI Difficulty Levels**
```dart
static const Map<String, dynamic> AI_BEHAVIOR_SETTINGS = {
  'easy': {
    'aggression': 0.3,
    'riskTolerance': 0.2,
    'recallThreshold': 0.8,
  },
  'medium': {
    'aggression': 0.5,
    'riskTolerance': 0.5,
    'recallThreshold': 0.6,
  },
  'hard': {
    'aggression': 0.8,
    'riskTolerance': 0.8,
    'recallThreshold': 0.4,
  },
};
```

## 🔄 WebSocket Event Flow

### **Event Structure**
All game events use the `recall_` prefix to avoid conflicts:

- `recall_join_game` - Join a game
- `recall_leave_game` - Leave current game
- `recall_player_action` - Play card, call recall, use special power
- `recall_game_state_updated` - Game state changes
- `recall_error` - Game errors

### **Event Handling**
```dart
// Listen to WebSocket events
_wsManager.events.listen((event) {
  if (event is MessageEvent) {
    final data = jsonDecode(event.message);
    if (data['type']?.startsWith('recall_') == true) {
      _handleRecallGameEvent(data);
    }
  }
});
```

## 🧪 Testing

### **Unit Tests**
- Card model tests
- Player model tests
- Game state tests
- Manager integration tests

### **Widget Tests**
- Card widget tests
- Game screen tests
- Player widget tests

### **Integration Tests**
- Full game flow tests
- WebSocket communication tests
- State management tests

## 📚 Documentation

### **API Reference**
- `models/` - Data models and structures
- `managers/` - Business logic and state management
- `utils/` - Utility functions and constants

### **Architecture**
- Follows Flutter Base 05 patterns
- Integrates with existing managers
- Uses established state management
- Maintains separation of concerns

## 🔮 Future Enhancements

### **Planned Features**
- [ ] Animated card movements
- [ ] Sound effects and music
- [ ] Chat system
- [ ] Spectator mode
- [ ] Tournament system
- [ ] Custom card themes
- [ ] Achievement system

### **Performance Optimizations**
- [ ] Card rendering optimization
- [ ] State update batching
- [ ] Memory management
- [ ] Network optimization

## 🤝 Contributing

When adding new features:

1. **Follow existing patterns** - Use established manager/module architecture
2. **Integrate with StateManager** - Register and update state properly
3. **Use WebSocket events** - Follow the `recall_` prefix convention
4. **Add proper error handling** - Include try-catch blocks and error states
5. **Update documentation** - Keep README and comments up to date

## 📝 Notes

- All WebSocket communication uses the `recall_` prefix to avoid conflicts
- Game state is synchronized with the Python backend
- UI components will be implemented in separate `screens/` and `widgets/` directories
- The structure follows Flutter Base 05 conventions for consistency 