# Recall Game Frontend Alignment Plan

## 🚨 **Current Redundancy Issues**

### **Overlapping Responsibilities**
- **RecallGameManager** (1283 lines): Game logic + State + Events + WebSocket
- **RecallGameCoordinator** (228 lines): Coordination + Service orchestration  
- **GameService** (289 lines): Game logic + Backend calls
- **RecallGameHelpers** (685 lines): Events + State + UI helpers
- **GamePlayScreen** (651 lines): UI + Turn state + Actions

### **Duplicated Methods**
- `startMatch()`: 4 implementations
- `playCard()`: 4 implementations  
- `drawCard()`: 4 implementations
- `callRecall()`: 4 implementations
- State updates: 3 implementations
- Event handling: 3 implementations

## 🎯 **Target Clean Architecture**

### **1. Single Responsibility Distribution**

```
UI Layer (Screens)
├── GamePlayScreen (UI only)
├── LobbyScreen (UI only)
└── Other Screens (UI only)

RecallGameCoordinator (Orchestrator - 200 lines max)
├── Coordinates services
├── Handles high-level flows
├── Manages initialization
└── Routes events to services

Service Layer
├── GameService (Game business logic)
├── RoomService (Room operations)
└── MessageService (Message processing)

Validated Systems
├── Event Emitter (Outgoing events)
├── State Updater (State updates)
└── WebSocket Manager (Connection/Events)
```

### **2. Clean Method Distribution**

| Component | Responsibility | Methods |
|-----------|---------------|---------|
| **RecallGameCoordinator** | Orchestration | `initialize()`, `handleGameEvent()`, `handleRoomEvent()` |
| **GameService** | Game logic | `startMatch()`, `playCard()`, `drawCard()`, `callRecall()` |
| **RoomService** | Room ops | `joinRoom()`, `leaveRoom()`, `createRoom()` |
| **MessageService** | Messages | `sendMessage()`, `handleMessage()`, `getMessages()` |
| **RecallGameHelpers** | Convenience | `quickStart()`, `quickJoin()`, `quickPlay()` |
| **GamePlayScreen** | UI only | `build()`, `_onButtonPressed()` |

## 🔧 **Implementation Steps**

### **Phase 1: Consolidate Game Logic (Priority: CRITICAL)**

#### **Step 1.1: Enhance GameService**
```dart
// Move ALL game logic to GameService
class GameService {
  // Game operations (single implementation)
  Future<Map<String, dynamic>> startMatch(String gameId) async { /* ... */ }
  Future<Map<String, dynamic>> playCard(String gameId, String cardId, String playerId) async { /* ... */ }
  Future<Map<String, dynamic>> drawCard(String gameId, String playerId, String source) async { /* ... */ }
  Future<Map<String, dynamic>> callRecall(String gameId, String playerId) async { /* ... */ }
  Future<Map<String, dynamic>> leaveGame(String gameId, String reason) async { /* ... */ }
  Future<Map<String, dynamic>> playOutOfTurn(String gameId, String cardId, String playerId) async { /* ... */ }
  
  // Game state validation
  bool isValidGameState(GameState gameState) { /* ... */ }
  bool canPlayerPlayCard(String playerId, GameState gameState) { /* ... */ }
  bool isGameReadyToStart(GameState gameState) { /* ... */ }
  bool canPlayerCallRecall(String playerId, GameState gameState) { /* ... */ }
  
  // Game business logic
  List<Card> getValidCardsForPlayer(String playerId, GameState gameState) { /* ... */ }
  Player? getWinner(GameState gameState) { /* ... */ }
  Map<String, dynamic> getGameStatistics(GameState gameState) { /* ... */ }
}
```

#### **Step 1.2: Simplify RecallGameCoordinator**
```dart
// Remove game logic, keep only coordination
class RecallGameCoordinator {
  final GameService _gameService = GameService();
  final RoomService _roomService = RoomService();
  final MessageService _messageService = MessageService();
  
  // High-level coordination only
  Future<bool> initialize() async { /* ... */ }
  void handleGameEvent(Map<String, dynamic> data) { /* ... */ }
  void handleRoomEvent(Map<String, dynamic> data) { /* ... */ }
  void handleMessageEvent(Map<String, dynamic> data) { /* ... */ }
  
  // Delegate to services
  Future<Map<String, dynamic>> startMatch(String gameId) async {
    return await _gameService.startMatch(gameId);
  }
  
  Future<Map<String, dynamic>> playCard(String gameId, String cardId, String playerId) async {
    return await _gameService.playCard(gameId, cardId, playerId);
  }
  
  // ... other delegations
}
```

#### **Step 1.3: Remove Game Logic from RecallGameManager**
```dart
// Remove all game logic methods, keep only event handling
class RecallGameManager {
  // Remove: startMatch(), playCard(), drawCard(), callRecall(), etc.
  // Keep: event handling, state updates, WebSocket coordination
  
  void _handleGameEvent(Map<String, dynamic> data) { /* ... */ }
  void _handleGameStarted(Map<String, dynamic> data) { /* ... */ }
  void _handleCardPlayed(Map<String, dynamic> data) { /* ... */ }
  // ... other event handlers
}
```

### **Phase 2: Simplify RecallGameHelpers (Priority: HIGH)**

#### **Step 2.1: Preserve Validation Systems, Convert to Convenience Methods**
```dart
// KEEP: All validation systems - CRITICAL
// MODIFY: Business logic methods to delegate to GameService
class RecallGameHelpers {
  static final RecallGameCoordinator _coordinator = RecallGameCoordinator();
  
  // KEEP: All validated event emission methods (CRITICAL)
  static Future<Map<String, dynamic>> startMatch(String gameId) async {
    // KEEP: Validation via RecallGameEventEmitter
    return await _eventEmitter.emit(
      eventType: 'start_match',
      data: {'game_id': gameId},
    );
  }
  
  static Future<Map<String, dynamic>> playCard({
    required String gameId,
    required String cardId,
    required String playerId,
  }) async {
    // KEEP: Validation via RecallGameEventEmitter
    return await _eventEmitter.emit(
      eventType: 'play_card',
      data: {
        'game_id': gameId,
        'card_id': cardId,
        'player_id': playerId,
      },
    );
  }
  
  // KEEP: All validated state update methods (CRITICAL)
  static void updateGameInfo({
    String? gameId,
    String? gamePhase,
    String? gameStatus,
    // ... other parameters
  }) {
    // KEEP: Validation via RecallGameStateUpdater
    _stateUpdater.updateState({
      if (gameId != null) 'currentGameId': gameId,
      if (gamePhase != null) 'gamePhase': gamePhase,
      if (gameStatus != null) 'gameStatus': gameStatus,
      // ... other fields
    });
  }
  
  // KEEP: UI state helpers
  static void setSelectedCard(Map<String, dynamic>? cardJson, int? cardIndex) { /* ... */ }
  static void clearSelectedCard() { /* ... */ }
  static void updateUIState(Map<String, dynamic> updates) { /* ... */ }
  
  // MODIFY: Business logic methods to delegate to GameService
  static Future<Map<String, dynamic>> drawCard({
    required String gameId,
    required String playerId,
    required String source,
  }) async {
    // Delegate to GameService for business logic
    return await GameService().drawCard(gameId, playerId, source);
  }
  
  // ... other business logic delegations
}
```

### **Phase 3: Clean GamePlayScreen (Priority: HIGH)**

#### **Step 3.1: Preserve Catchall System, Simplify Business Logic**
```dart
// KEEP: handlePlayerAction() and PlayerAction enum - CRITICAL FOR TUTORIAL
// MODIFY: _executePlayerAction() to delegate to GameService instead of direct backend calls
class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  // KEEP: Centralized action handler (CRITICAL)
  Future<void> handlePlayerAction(PlayerAction action, {Map<String, dynamic>? actionData}) async {
    // Common validation (KEEP)
    // Action execution (MODIFY: delegate to GameService)
    // Success/failure handling (KEEP)
    // Tutorial integration ready (KEEP)
  }
  
  // MODIFY: Delegate to GameService instead of direct backend calls
  Future<Map<String, dynamic>> _executePlayerAction(
    PlayerAction action, 
    String gameId, 
    String playerId, 
    Map<String, dynamic>? actionData
  ) async {
    switch (action) {
      case PlayerAction.drawFromDeck:
        return await GameService().drawCard(gameId, playerId, 'deck');
      case PlayerAction.playCard:
        return await GameService().playCard(gameId, _selectedCard!.cardId, playerId);
      // ... other delegations to GameService
    }
  }
  
  // KEEP: Individual action methods that delegate to catchall
  Future<void> _onDrawFromDeck() async {
    await handlePlayerAction(PlayerAction.drawFromDeck);
  }
  
  Future<void> _onPlaySelected() async {
    await handlePlayerAction(PlayerAction.playCard);
  }
  
  // ... etc
}
```

#### **Step 3.2: Keep Turn State Management**
```dart
// Keep turn state management (UI concern)
class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  PlayerTurnPhase _currentTurnPhase = PlayerTurnPhase.waiting;
  
  void _updateTurnStateFromGameState() { /* ... */ }
  void _setTurnPhase(PlayerTurnPhase newPhase) { /* ... */ }
  bool _isActionAvailable(String action) { /* ... */ }
  
  // Keep UI methods
  Widget _buildTurnPhaseIndicator() { /* ... */ }
  Widget _buildDebugControls() { /* ... */ }
}
```

### **Phase 4: Consolidate Event Handling (Priority: MEDIUM)**

#### **Step 4.1: Single Event Router**
```dart
// Create single event router in RecallGameCoordinator
class RecallGameCoordinator {
  void _setupEventListeners() {
    final eventTypes = [
      'game_joined', 'game_left', 'player_joined', 'player_left',
      'game_started', 'game_ended', 'turn_changed', 'card_played',
      'card_drawn', 'recall_called', 'game_state_updated', 'game_phase_changed',
    ];
    
    for (final eventType in eventTypes) {
      wsManager.eventListener?.registerCustomListener(eventType, (data) {
        _handleGameEvent({
          'event_type': eventType,
          ...(data is Map<String, dynamic> ? data : {}),
        });
      });
    }
  }
  
  void _handleGameEvent(Map<String, dynamic> data) {
    final eventType = data['event_type'];
    
    switch (eventType) {
      case 'game_started':
        _gameService.handleGameStarted(data);
        break;
      case 'card_played':
        _gameService.handleCardPlayed(data);
        break;
      // ... other event types
    }
  }
}
```

#### **Step 4.2: Remove Duplicate Event Handlers**
- Remove event handlers from RecallGameManager
- Remove event handlers from GamePlayScreen
- Keep only in RecallGameCoordinator

### **Phase 5: Clean State Management (Priority: MEDIUM)**

#### **Step 5.1: Single State Update Path**
```dart
// All state updates go through RecallGameCoordinator
class RecallGameCoordinator {
  void updateGameState(GameState newGameState) {
    // Update via validated system
    RecallGameHelpers.updateGameInfo(
      gameId: newGameState.gameId,
      gamePhase: newGameState.phase.name,
      gameStatus: newGameState.status.name,
      // ... other fields
    );
    
    // Update UI slices
    RecallGameHelpers.updateUIState({
      'actionBar': _buildActionBarState(newGameState),
      'statusBar': _buildStatusBarState(newGameState),
      'myHand': _buildMyHandState(newGameState),
      'centerBoard': _buildCenterBoardState(newGameState),
      'opponentsPanel': _buildOpponentsPanelState(newGameState),
    });
  }
}
```

#### **Step 5.2: Remove State Updates from Other Components**
- Remove state updates from RecallGameManager
- Remove state updates from GamePlayScreen
- Remove state updates from RecallGameHelpers (except convenience methods)

## 📊 **Success Metrics**

### **Before Alignment**
- ❌ RecallGameManager: 1283 lines, multiple responsibilities
- ❌ RecallGameCoordinator: 228 lines, overlapping logic
- ❌ GameService: 289 lines, mixed concerns
- ❌ RecallGameHelpers: 685 lines, business logic + UI helpers
- ❌ GamePlayScreen: 651 lines, UI + business logic
- ❌ **Total**: 3136 lines with significant redundancy

### **After Alignment**
- ✅ RecallGameCoordinator: ~200 lines, coordination only
- ✅ GameService: ~150 lines, game logic only
- ✅ RoomService: ~100 lines, room operations only
- ✅ MessageService: ~100 lines, message processing only
- ✅ RecallGameHelpers: ~100 lines, convenience methods only
- ✅ GamePlayScreen: ~300 lines, UI only
- ✅ **Total**: ~950 lines, clean separation of concerns

## 🚀 **Implementation Priority**

1. **Phase 1** (CRITICAL): Consolidate game logic into GameService
2. **Phase 2** (HIGH): Simplify RecallGameHelpers to convenience methods
3. **Phase 3** (HIGH): Clean GamePlayScreen to UI only
4. **Phase 4** (MEDIUM): Consolidate event handling
5. **Phase 5** (MEDIUM): Clean state management

## 🛡️ **Protected Systems (DO NOT MODIFY)**

### **1. Catchall Player Action System** ⚠️ **CRITICAL - PRESERVE**
```dart
// KEEP: PlayerAction enum and catchall method in GamePlayScreen
enum PlayerAction {
  drawFromDeck, takeFromDiscard, playCard, replaceWithDrawn,
  placeDrawnAndPlay, callRecall, playOutOfTurn, selectCard, startMatch,
}

// KEEP: Centralized action handler
Future<void> handlePlayerAction(PlayerAction action, {Map<String, dynamic>? actionData}) async {
  // Common validation
  // Action execution
  // Success/failure handling
  // Tutorial integration ready
}
```

### **2. Validated Event System** ⚠️ **CRITICAL - PRESERVE**
```dart
// KEEP: RecallGameEventEmitter with validation
class RecallGameEventEmitter {
  static final Map<String, List<String>> _allowedEventFields = {
    'start_match': ['game_id'],
    'play_card': ['game_id', 'card_id', 'player_id', 'replace_index'],
    'draw_card': ['game_id', 'player_id', 'source'],
    'call_recall': ['game_id', 'player_id'],
    // ... all other event validations
  };
  
  static Future<Map<String, dynamic>> emit({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    // Validation logic
    // WebSocket emission
    // Error handling
  }
}
```

### **3. Validated State Update System** ⚠️ **CRITICAL - PRESERVE**
```dart
// KEEP: RecallGameStateUpdater with validation
class RecallGameStateUpdater {
  static final Map<String, FieldSpec> _fieldValidation = {
    'isGameActive': FieldSpec(type: FieldType.BOOL),
    'currentGameId': FieldSpec(type: FieldType.STRING),
    'playerId': FieldSpec(type: FieldType.STRING),
    'gamePhase': FieldSpec(type: FieldType.STRING, allowedValues: ['waiting', 'playing', 'finished']),
    // ... all other field validations
  };
  
  static void updateState(Map<String, dynamic> updates) {
    // Validation logic
    // StateManager updates
    // Error handling
  }
}
```

### **4. Screen vs Widget State Pattern** ⚠️ **CRITICAL - PRESERVE**
```dart
// KEEP: Screen doesn't subscribe to state, widgets do
class GamePlayScreen extends BaseScreen {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          StatusBarWidget(),    // ← Widget subscribes to status state
          ActionBarWidget(),    // ← Widget subscribes to action state
          CenterBoardWidget(),  // ← Widget subscribes to game state
          MyHandPanelWidget(),  // ← Widget subscribes to hand state
        ],
      ),
    );
  }
}
```

## ⚠️ **Risk Mitigation**

1. **Incremental Migration**: Implement one phase at a time
2. **Backward Compatibility**: Keep existing interfaces during transition
3. **Comprehensive Testing**: Test each phase thoroughly
4. **Rollback Plan**: Keep backup of current implementation
5. **Documentation**: Update all documentation after each phase
6. **Protected Systems**: Never modify catchall, validation, or state patterns
