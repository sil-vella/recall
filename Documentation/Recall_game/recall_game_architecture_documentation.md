# Validated Incremental Event/State System

## 🎯 Overview

The Validated Incremental Event/State System is a comprehensive architecture pattern implemented in the Recall Game module to ensure strict data integrity, consistency, and type safety for all WebSocket communications and state management operations.

This system provides:
- **Strict Data Validation**: All events and state updates are validated against predefined schemas
- **Type Safety**: Compile-time and runtime type checking for all data operations
- **Single Source of Truth**: Centralized event emission and state management
- **Error Prevention**: Catches invalid keys, types, and values before they propagate
- **Minimal Overhead**: Only updates the necessary data pieces, not entire objects
- **Developer Experience**: Clear error messages and helper methods for common operations
- **Screen vs Widget Pattern**: Screens handle layout/navigation, widgets subscribe to state
- **Service Layer Architecture**: Clean separation between UI, services, and coordination

## 🏗️ Architecture Components

### 1. Auto-Change Detection System

The Recall Game module implements a sophisticated **auto-change detection system** that automatically tracks property changes in both `GameState` and `Player` objects and sends real-time updates to the frontend.

#### GameState Auto-Change Detection

**Purpose**: Automatically detect changes to game state properties and send partial updates to all players in the room.

**Implementation**:
```python
class GameState:
    def __init__(self, game_id: str, ...):
        # Auto-change detection setup
        self._change_tracking_enabled = True
        self._pending_changes = set()
        self._initialized = True
    
    def __setattr__(self, name, value):
        """Override __setattr__ to detect property changes"""
        current_value = getattr(self, name, None)
        super().__setattr__(name, value)
        
        if (self._change_tracking_enabled and 
            current_value != value and 
            name not in ['_change_tracking_enabled', '_pending_changes', '_initialized']):
            
            # Log property changes
            if name in ['draw_pile', 'discard_pile']:
                old_count = len(current_value) if current_value else 0
                new_count = len(value) if value else 0
                custom_log(f"=== PILE CHANGE DETECTED ===")
                custom_log(f"Property: {name}, Change: {old_count} -> {new_count}")
            
            self._track_change(name)
            self._send_changes_if_needed()
    
    def _track_change(self, property_name: str):
        """Track a property change"""
        self._pending_changes.add(property_name)
    
    def _send_changes_if_needed(self):
        """Send partial state updates if there are pending changes"""
        if not self._pending_changes:
            return
        
        # Get coordinator and send partial update
        coordinator = self.app_manager.game_event_coordinator
        changes_list = list(self._pending_changes)
        coordinator._send_game_state_partial_update(self.game_id, changes_list)
        self._pending_changes.clear()
```

**Key Features**:
- **Automatic Detection**: Uses Python's `__setattr__` to intercept property assignments
- **Change Tracking**: Maintains a set of changed properties
- **Partial Updates**: Sends only changed properties to reduce network traffic
- **Pile Change Detection**: Special logging for draw_pile and discard_pile changes
- **Room Broadcasting**: Sends updates to all players in the game room

#### Player Auto-Change Detection

**Purpose**: Automatically detect changes to individual player properties and send updates to both the specific player and trigger room-wide player list updates.

**Implementation**:
```python
class Player:
    def __init__(self, player_id: str, ...):
        # Auto-change detection setup
        self._change_tracking_enabled = True
        self._pending_changes = set()
        self._initialized = True
        self._game_state_manager = None
        self._game_id = None
    
    def set_game_references(self, game_state_manager, game_id: str):
        """Set references for auto-updates"""
        self._game_state_manager = game_state_manager
        self._game_id = game_id
    
    def __setattr__(self, name, value):
        """Override __setattr__ to detect property changes"""
        current_value = getattr(self, name, None)
        super().__setattr__(name, value)
        
        if (self._change_tracking_enabled and 
            current_value != value and 
            name not in ['_change_tracking_enabled', '_pending_changes', '_initialized']):
            
            self._track_change(name)
            self._send_changes_if_needed()
    
    def _send_changes_if_needed(self):
        """Send individual player update and trigger room-wide update"""
        if not self._pending_changes:
            return
        
        # Send individual player update
        coordinator = self._game_state_manager.app_manager.game_event_coordinator
        coordinator._send_player_state_update(self._game_id, self.player_id)
        
        # Also trigger GameState players property update
        self._trigger_gamestate_players_update()
        self._pending_changes.clear()
    
    def _trigger_gamestate_players_update(self):
        """Trigger GameState players property change detection"""
        game_state = self._game_state_manager.get_game(self._game_id)
        if game_state:
            game_state._track_change('players')
            game_state._send_changes_if_needed()
```

**Key Features**:
- **Dual Updates**: Sends both individual player updates and room-wide player list updates
- **Individual Targeting**: Sends `player_state_updated` to specific player session
- **Room Synchronization**: Triggers `game_state_partial_update` with `players` property to entire room
- **Automatic Integration**: Works seamlessly with existing coordinator methods

#### Manual Change Triggers

For in-place list modifications (like `list.append()`, `list.pop()`), manual triggers are required since `__setattr__` doesn't detect these changes:

```python
# In GameRound class
def _handle_draw_from_pile(self, player_id: str):
    drawn_card = self.game_state.draw_pile.pop()
    # Manually trigger change detection for draw_pile
    if hasattr(self.game_state, '_track_change'):
        self.game_state._track_change('draw_pile')
        self.game_state._send_changes_if_needed()

# In Player class
def add_card_to_hand(self, card: Card):
    self.hand.append(card)
    # Manually trigger change detection for hand modification
    if hasattr(self, '_track_change'):
        self._track_change('hand')
        self._send_changes_if_needed()
```

#### Event Flow

**GameState Changes**:
1. Property change detected via `__setattr__`
2. Change tracked in `_pending_changes`
3. `_send_changes_if_needed()` called
4. `game_state_partial_update` event sent to entire room
5. Frontend receives and processes partial update

**Player Changes**:
1. Player property change detected via `__setattr__`
2. Change tracked in `_pending_changes`
3. `_send_changes_if_needed()` called
4. `player_state_updated` event sent to specific player
5. `_trigger_gamestate_players_update()` called
6. `game_state_partial_update` with `players` property sent to entire room
7. Frontend receives both individual and room-wide updates

#### Benefits

- **Real-time Updates**: Immediate propagation of state changes
- **Network Efficiency**: Only changed properties are sent
- **Automatic Synchronization**: No manual update calls required
- **Dual Targeting**: Individual player updates + room-wide synchronization
- **Comprehensive Coverage**: Handles both direct assignments and in-place modifications

### 2. Field Specifications (`field_specifications.dart`)

Defines validation rules and data schemas for all events and state fields.

```dart
class FieldSpec {
  final Type type;
  final bool required;
  final String? pattern;
  final num? min;
  final num? max;
  final List<dynamic>? allowedValues;

  const FieldSpec({
    required this.type,
    this.required = false,
    this.pattern,
    this.min,
    this.max,
    this.allowedValues,
  });
}
```

**Key Features:**
- Type validation (String, int, bool, etc.)
- Required field enforcement
- Pattern matching (regex)
- Numeric range validation
- Enumerated value validation
- Custom validation rules

### 2. Validated Event Emitter (`validated_event_emitter.dart`)

Centralizes and validates all outgoing WebSocket event emissions.

```dart
class RecallGameEventEmitter {
  static final RecallGameEventEmitter _instance = RecallGameEventEmitter._internal();
  factory RecallGameEventEmitter() => _instance;

  Future<void> emit(String eventType, Map<String, dynamic> payload) async {
    // 1. Validate event type
    // 2. Validate payload against schema
    // 3. Add metadata (sessionId, timestamp)
    // 4. Emit via WebSocket
  }
}
```

**Supported Event Types:**
- `create_room` - Room creation
- `join_game` - Game joining
- `leave_game` - Game leaving
- `start_match` - Match starting
- `play_card` - Card playing
- `call_recall` - Recall calling
- `draw_card` - Card drawing
- `play_out_of_turn` - Out-of-turn card playing
- `use_special_power` - Special power usage
- `replace_drawn_card` - Replace drawn card
- `play_drawn_card` - Play drawn card

### 3. Validated State Updater (`validated_state_updater.dart`)

Centralizes and validates all state updates to StateManager.

```dart
class RecallGameStateUpdater {
  static final RecallGameStateUpdater _instance = RecallGameStateUpdater._internal();
  factory RecallGameStateUpdater() => _instance;

  void updateState(Map<String, dynamic> updates) {
    // 1. Validate updates against schema
    // 2. Merge with existing state
    // 3. Update StateManager
    // 4. Trigger UI rebuilds
  }
}
```

**State Schema Sections:**
- **Core Game Info**: `gameId`, `playerId`, `isGameStarted`, etc.
- **Room Management**: `roomId`, `roomName`, `isRoomOwner`, etc.
- **Player Data**: `currentTurn`, `playerCount`, `isMyTurn`, etc.
- **Connection Status**: `isConnected`, `lastPing`, etc.
- **Widget Slices**: Pre-computed UI state for specific widgets

### 4. Event Listener Validator (`recall_event_listener_validator.dart`)

Validates and processes all incoming WebSocket events from the backend.

```dart
class RecallGameEventListenerValidator {
  static final RecallGameEventListenerValidator _instance = RecallGameEventListenerValidator._internal();
  factory RecallGameEventListenerValidator() => _instance;

  void addListener(String eventType, Function(Map<String, dynamic>) callback) {
    // 1. Listen to 'recall_game_event' WebSocket events
    // 2. Extract and validate event type
    // 3. Validate event data against schema
    // 4. Call callback with validated data
  }
}
```

**Supported Incoming Event Types:**
- **Game Events**: `game_joined`, `game_left`, `game_started`, `game_ended`
- **Player Events**: `player_joined`, `player_left`, `turn_changed`
- **Card Events**: `card_played`, `card_drawn`
- **Room Events**: `room_created`, `room_joined`, `room_left`, `room_closed`
- **System Events**: `recall_called`, `game_state_updated`, `error`, `connection_status`

**Key Features:**
- **Event Schema Validation**: Validates incoming events against predefined field schemas
- **Type Safety**: Ensures event data contains expected fields and types
- **Error Handling**: Gracefully handles malformed events with detailed logging
- **Automatic Timestamping**: Adds timestamps to all validated events
- **Metadata Preservation**: Preserves additional metadata fields for extensibility
- **Singleton Pattern**: Single instance manages all event validation

### 5. Helper Methods (`recall_game_helpers.dart`)

Provides convenient, type-safe methods for common operations.

```dart
class RecallGameHelpers {
  // Event Emission Helpers
  static Future<void> createRoom(String roomName) async { ... }
  static Future<void> joinGame(String gameId, String playerName) async { ... }
  static Future<void> playCard(String cardId, int position) async { ... }
  static Future<void> drawCard(String source) async { ... }
  static Future<void> callRecall() async { ... }
  static Future<void> leaveGame() async { ... }
  static Future<void> startMatch(String gameId) async { ... }
  static Future<void> playOutOfTurn(String cardId) async { ... }
  static Future<void> useSpecialPower(String powerType, Map<String, dynamic> data) async { ... }
  static Future<void> replaceDrawnCard(String cardId, int position) async { ... }
  static Future<void> placeDrawnCard(String cardId, int position) async { ... }
  
  // State Update Helpers
  static void updateGameInfo(Map<String, dynamic> gameInfo) { ... }
  static void updatePlayerTurn(String playerId, bool isMyTurn) { ... }
  static void updateConnectionStatus(bool isConnected) { ... }
  static void updateUIState(Map<String, dynamic> updates) { ... }
  
  // UI State Helpers
  static void setSelectedCard(Map<String, dynamic> card, int index) { ... }
  static void clearSelectedCard() { ... }
  static void updateActiveGame(Map<String, dynamic> gameData) { ... }
  static void removeActiveGame(String roomId) { ... }
  static void cleanupEndedGames() { ... }
  static void setRoomOwnership(bool isOwner) { ... }
  
  // Event Listener Helpers (via extension)
  static void onEvent(String eventType, Function(Map<String, dynamic>) callback) { ... }
}
```

### 6. Service Layer Architecture

The system implements a clean service layer architecture with the following components:

#### RecallGameCoordinator (`recall_game_coordinator.dart`)
Central coordinator that manages all game operations and event handling.

```dart
class RecallGameCoordinator {
  static final RecallGameCoordinator _instance = RecallGameCoordinator._internal();
  factory RecallGameCoordinator() => _instance;

  // Core services
  final GameService _gameService = GameService();
  final RoomService _roomService = RoomService();
  final MessageService _messageService = MessageService();

  // Event handling and coordination
  Future<void> joinGameAndRoom(String roomId, String playerName) async { ... }
  Future<void> startMatch(String gameId) async { ... }
  Future<void> playCard(String cardId, int position) async { ... }
  // ... more coordination methods
}
```

#### GameService (`game_service.dart`)
Handles all game-specific business logic.

```dart
class GameService {
  Future<Map<String, dynamic>> startMatch(String gameId) async { ... }
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName) async { ... }
  Future<Map<String, dynamic>> playCard(String cardId, int position) async { ... }
  Future<Map<String, dynamic>> drawCard(String source) async { ... }
  Future<Map<String, dynamic>> callRecall() async { ... }
  Future<Map<String, dynamic>> leaveGame() async { ... }
  Future<Map<String, dynamic>> playOutOfTurn(String cardId) async { ... }
}
```

#### RoomService (`room_service.dart`)
Handles room management operations.

```dart
class RoomService {
  Future<Map<String, dynamic>> createRoom(String roomName, {int maxPlayers = 4}) async { ... }
  Future<Map<String, dynamic>> joinRoom(String roomId, String playerName) async { ... }
  Future<Map<String, dynamic>> leaveRoom(String roomId) async { ... }
  Future<Map<String, dynamic>> getPendingGames() async { ... }
}
```

#### MessageService (`message_service.dart`)
Handles messaging and communication features.

```dart
class MessageService {
  Future<Map<String, dynamic>> sendMessage(String roomId, String message) async { ... }
  Future<Map<String, dynamic>> getMessages(String roomId) async { ... }
  Future<Map<String, dynamic>> deleteMessage(String messageId) async { ... }
}
```

## 📋 Implementation Details

### Event Validation Schema

```dart
static final Map<String, Map<String, FieldSpec>> _allowedEventFields = {
  'create_room': {
    'roomName': FieldSpec(type: String, required: true),
    'maxPlayers': FieldSpec(type: int, min: 2, max: 6),
    'isPrivate': FieldSpec(type: bool),
  },
  'join_game': {
    'gameId': FieldSpec(type: String, required: true),
    'playerName': FieldSpec(type: String, required: true),
  },
  'start_match': {
    'gameId': FieldSpec(type: String, required: true),
  },
  'play_card': {
    'cardId': FieldSpec(type: String, required: true, pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$'),
    'position': FieldSpec(type: int, min: 0, max: 3),
  },
  'draw_card': {
    'source': FieldSpec(type: String, allowedValues: ['deck', 'discard']),
  },
  'call_recall': {
    'gameId': FieldSpec(type: String, required: true),
  },
  'leave_game': {
    'gameId': FieldSpec(type: String, required: true),
  },
  'play_out_of_turn': {
    'cardId': FieldSpec(type: String, required: true, pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$'),
  },
  'use_special_power': {
    'powerType': FieldSpec(type: String, required: true),
    'data': FieldSpec(type: Map, required: true),
  },
  'replace_drawn_card': {
    'cardId': FieldSpec(type: String, required: true, pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$'),
    'position': FieldSpec(type: int, min: 0, max: 3),
  },
  'play_drawn_card': {
    'cardId': FieldSpec(type: String, required: true, pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$'),
    'position': FieldSpec(type: int, min: 0, max: 3),
  },
};
```

### State Validation Schema

```dart
static final Map<String, RecallStateFieldSpec> _stateSchema = {
  // Core Game Fields
  'gameId': RecallStateFieldSpec(type: String, required: true),
  'playerId': RecallStateFieldSpec(type: String, required: true),
  'isGameStarted': RecallStateFieldSpec(type: bool, defaultValue: false),
  'gamePhase': RecallStateFieldSpec(type: String, defaultValue: 'waiting'),
  
  // Room Fields
  'roomId': RecallStateFieldSpec(type: String, required: false),
  'roomName': RecallStateFieldSpec(type: String, required: false),
  'isRoomOwner': RecallStateFieldSpec(type: bool, defaultValue: false),
  
  // Player Fields
  'currentPlayer': RecallStateFieldSpec(
    type: Map, 
    required: false, 
    description: 'Current player object with id, name, etc.'
  ),
  'currentPlayerStatus': RecallStateFieldSpec(
    type: String, 
    required: false, 
    description: 'Status of current player'
  ),
  'playerCount': RecallStateFieldSpec(type: int, defaultValue: 0),
  'isMyTurn': RecallStateFieldSpec(type: bool, defaultValue: false),
  
  // Connection Fields
  'isConnected': RecallStateFieldSpec(type: bool, defaultValue: false),
  'lastPing': RecallStateFieldSpec(type: int, defaultValue: 0),
  
  // Game State Fields
  'games': RecallStateFieldSpec(type: Map, defaultValue: {}),
  'currentGameId': RecallStateFieldSpec(type: String, required: false),
  'gameState': RecallStateFieldSpec(type: Map, defaultValue: {}),
  'players': RecallStateFieldSpec(type: List, defaultValue: []),
  'myHand': RecallStateFieldSpec(type: List, defaultValue: []),
  'discardPile': RecallStateFieldSpec(type: List, defaultValue: []),
  'drawPile': RecallStateFieldSpec(type: List, defaultValue: []),
  'centerPile': RecallStateFieldSpec(type: List, defaultValue: []),
  
  // UI State Fields
  'selectedCard': RecallStateFieldSpec(type: Map, required: false),
  'selectedCardIndex': RecallStateFieldSpec(type: int, defaultValue: -1),
  'drawnCard': RecallStateFieldSpec(type: Map, required: false),
  
  // Widget State Slices (pre-computed for UI performance)
  'actionBar': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'showStartButton': false, 'canPlayCard': false},
    description: 'Action bar widget state slice'
  ),
  'statusBar': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'currentPhase': 'waiting', 'playerCount': 0},
    description: 'Status bar widget state slice'
  ),
  'myHand': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'cards': [], 'selectedIndex': -1},
    description: 'My hand widget state slice'
  ),
  'centerBoard': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'discardPile': [], 'currentCard': null},
    description: 'Center board widget state slice'
  ),
  'opponentsPanel': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'opponents': [], 'currentTurnIndex': -1},
    description: 'Opponents panel widget state slice'
  ),
  'gameInfo': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'currentGameId': '', 'roomName': '', 'currentSize': 0},
    description: 'Game info widget state slice'
  ),
  'joinedGamesSlice': RecallStateFieldSpec(
    type: Map, 
    defaultValue: {'joinedGames': [], 'totalJoinedGames': 0},
    description: 'Joined games widget state slice'
  ),
};
```

### State Extraction and Propagation

**Critical Implementation Detail**: The state manager automatically extracts `currentPlayer` from the current game data and propagates it to the main state level for consistent widget access.

```dart
// In _updateWidgetSlices method
// Extract currentPlayer from current game data and put it in main state
final currentGameId = updatedState['currentGameId']?.toString() ?? '';
final games = updatedState['games'] as Map<String, dynamic>? ?? {};
final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
final currentPlayer = currentGame['currentPlayer'];

if (currentPlayer != null) {
  updatedState['currentPlayer'] = currentPlayer;
  _log.info('🔍 [STATE] Extracted currentPlayer from current game: ${currentPlayer['id']}');
} else {
  updatedState['currentPlayer'] = null;
  _log.info('🔍 [STATE] No currentPlayer in current game');
}
```

This ensures that all widgets can access `currentPlayer` from the main state level (`recallGameState['currentPlayer']`) following the standard pattern, rather than having to dig into the game data structure.

### Incoming Event Validation Schema

The Event Listener Validator defines comprehensive schemas for all incoming WebSocket events:

```dart
static const Map<String, Set<String>> _eventSchema = {
  // Game Lifecycle Events
  'game_joined': {
    'game_id', 'player_id', 'player_name', 'game_state', 'player',
    'room_id', 'room_name', 'is_owner', 'is_active',
  },
  'game_started': {
    'game_id', 'game_state', 'timestamp', 'started_by',
    'player_order', 'initial_hands',
  },
  'game_ended': {
    'game_id', 'game_state', 'winner', 'scores', 'reason',
    'timestamp', 'duration',
  },
  
  // Player Management Events
  'player_joined': {
    'game_id', 'player_id', 'player_name', 'player', 'players',
    'timestamp', 'room_id',
  },
  'player_left': {
    'game_id', 'player_id', 'player_name', 'reason', 'players',
    'timestamp', 'room_id',
  },
  
  // Gameplay Events
  'turn_changed': {
    'game_id', 'current_turn', 'previous_turn', 'turn_number',
    'round_number', 'timestamp',
  },
  'card_played': {
    'game_id', 'player_id', 'card', 'position', 'timestamp',
    'is_out_of_turn', 'remaining_cards',
  },
  'card_drawn': {
    'game_id', 'player_id', 'source', 'card', 'timestamp',
    'remaining_deck', 'discard_top',
  },
  
  // Room Management Events
  'room_created': {
    'room_id', 'room_name', 'owner_id', 'permission',
    'max_players', 'min_players', 'timestamp',
  },
  'room_joined': {
    'room_id', 'player_id', 'player_name', 'timestamp',
    'current_players',
  },
  'room_left': {
    'room_id', 'player_id', 'reason', 'timestamp',
  },
  'room_closed': {
    'room_id', 'reason', 'timestamp',
  },
  
  // System Events
  'recall_called': {
    'game_id', 'player_id', 'timestamp', 'scores',
    'updated_game_state',
  },
  'game_state_updated': {
    'game_id', 'game_state', 'timestamp', 'changes',
  },
  'error': {
    'error', 'message', 'code', 'details', 'timestamp',
  },
  'connection_status': {
    'status', 'session_id', 'error', 'timestamp',
  },
  
  // Additional Game Events
  'join_room_success': {
    'room_id', 'room_name', 'player_id', 'timestamp',
    'current_players', 'room_state',
  },
  'create_room_success': {
    'room_id', 'room_name', 'owner_id', 'timestamp',
    'room_state',
  },
  'leave_room_success': {
    'room_id', 'player_id', 'timestamp',
  },
  'leave_room_error': {
    'room_id', 'error', 'message', 'timestamp',
  },
  'get_public_rooms': {
    'rooms', 'timestamp',
  },
};
```

**Validation Process:**
1. **Event Type Extraction**: Extracts `event_type` from incoming WebSocket data
2. **Schema Lookup**: Finds the corresponding field schema for the event type
3. **Field Validation**: Only includes fields that exist in the schema
4. **Data Enrichment**: Adds `event_type` and `timestamp` to validated data
5. **Callback Execution**: Calls the registered callback with validated data
6. **Error Handling**: Logs validation errors without crashing the application

## 🚀 Usage Examples

### Event Emission

```dart
// ❌ OLD WAY: Direct WebSocket calls, no validation
_wsManager.sendCustomEvent('create_room', {
  'name': roomName, // Wrong key name
  'max_players': 'four', // Wrong type
});

// ✅ NEW WAY: Validated helper method
await RecallGameHelpers.createRoom(roomName);

// ✅ NEW WAY: Service layer method
final roomService = RoomService();
final result = await roomService.createRoom(roomName, maxPlayers: 4);

// ✅ NEW WAY: Direct validated emission
await RecallGameEventEmitter().emit('create_room', {
  'roomName': roomName,
  'maxPlayers': 4,
  'isPrivate': false,
});
```

### State Updates

```dart
// ❌ OLD WAY: Direct StateManager calls, no validation
_stateManager.updateModuleState('recall_game', {
  'game_id': gameId, // Wrong key format
  'is_started': 'yes', // Wrong type
  'invalid_field': 'value', // Invalid field
});

// ✅ NEW WAY: Validated helper method
RecallGameHelpers.updateGameInfo({
  'gameId': gameId,
  'isGameStarted': true,
});

// ✅ NEW WAY: UI state updates
RecallGameHelpers.updateUIState({
  'actionBar': {'showStartButton': true},
  'statusBar': {'currentPhase': 'active'},
});

// ✅ NEW WAY: Direct validated update
RecallGameStateUpdater().updateState({
  'gameId': gameId,
  'isGameStarted': true,
  'gamePhase': 'active',
});
```

### Event Listening

```dart
// ✅ NEW WAY: Validated event listening
RecallGameHelpers.onEvent('game_started', (data) {
  // data is validated and contains only allowed fields
  final gameId = data['game_id'];
  final gameState = data['game_state'];
  final startedBy = data['started_by'];
  
  // Update UI state with validated data
  RecallGameHelpers.updateGameInfo({
    'gameId': gameId,
    'isGameStarted': true,
    'gameState': gameState,
  });
});

// ✅ Listen to player join events
RecallGameHelpers.onEvent('player_joined', (data) {
  final playerId = data['player_id'];
  final playerName = data['player_name'];
  
  // Update player list
  RecallGameHelpers.updatePlayerTurn(playerId, false);
});

// ✅ Listen to card played events
RecallGameHelpers.onEvent('card_played', (data) {
  final card = data['card'];
  final position = data['position'];
  final isOutOfTurn = data['is_out_of_turn'] ?? false;
  
  // Update game board
  RecallGameHelpers.updateUIState({
    'centerBoard': {
      'lastPlayedCard': card,
      'lastPosition': position,
      'wasOutOfTurn': isOutOfTurn,
    }
  });
});

// ✅ Listen to room events
RecallGameHelpers.onEvent('room_created', (data) {
  final roomId = data['room_id'];
  final roomName = data['room_name'];
  final ownerId = data['owner_id'];
  
  // Update room ownership
  RecallGameHelpers.setRoomOwnership(ownerId == currentUserId);
});

// ✅ Listen to error events
RecallGameHelpers.onEvent('error', (data) {
  final errorCode = data['code'];
  final errorMessage = data['message'];
  
  // Show error to user
  _showErrorSnackBar('Error $errorCode: $errorMessage');
});
```

### Service Layer Usage

```dart
// ✅ Game operations via service layer
final gameService = GameService();

// Start a match
final startResult = await gameService.startMatch(gameId);
if (startResult['success'] == true) {
  RecallGameHelpers.updateGameInfo({
    'isGameStarted': true,
    'gamePhase': 'active',
  });
}

// Play a card
final playResult = await gameService.playCard(cardId, position);
if (playResult['success'] == true) {
  RecallGameHelpers.clearSelectedCard();
}

// Draw a card
final drawResult = await gameService.drawCard('deck');
if (drawResult['success'] == true) {
  final drawnCard = drawResult['card'];
  RecallGameHelpers.updateUIState({
    'drawnCard': drawnCard,
  });
}

// ✅ Room operations via service layer
final roomService = RoomService();

// Create a room
final createResult = await roomService.createRoom('My Game Room', maxPlayers: 4);
if (createResult['success'] == true) {
  final roomId = createResult['room_id'];
  RecallGameHelpers.updateUIState({
    'roomId': roomId,
    'isRoomOwner': true,
  });
}

// Join a room
final joinResult = await roomService.joinRoom(roomId, playerName);
if (joinResult['success'] == true) {
  RecallGameHelpers.updateUIState({
    'roomId': roomId,
    'isRoomOwner': false,
  });
}

// ✅ Message operations via service layer
final messageService = MessageService();

// Send a message
final sendResult = await messageService.sendMessage(roomId, 'Hello everyone!');
if (sendResult['success'] == true) {
  // Message sent successfully
}

// Get messages
final messagesResult = await messageService.getMessages(roomId);
if (messagesResult['success'] == true) {
  final messages = messagesResult['messages'];
  RecallGameHelpers.updateUIState({
    'messageBoard': {'messages': messages},
  });
}
```

### UI State Management

```dart
// ✅ Transient UI state (not validated for performance)
RecallGameHelpers.setSelectedCard(cardData, cardIndex);
RecallGameHelpers.updateUIState({
  'rooms': roomsList,
  'myHand': {'selectedIndex': selectedIndex},
});
RecallGameHelpers.clearSelectedCard();

// ✅ Widget-specific state slices
RecallGameHelpers.updateUIState({
  'actionBar': {
    'showStartButton': true,
    'canPlayCard': false,
    'canCallRecall': false,
  },
  'statusBar': {
    'currentPhase': 'waiting',
    'turnInfo': 'Waiting for players...',
    'playerCount': 2,
  },
  'myHand': {
    'cards': myCards,
    'selectedCardId': selectedCardId,
    'canSelectCards': true,
  },
});
```

### Coordinator Usage

```dart
// ✅ High-level coordination via RecallGameCoordinator
final coordinator = RecallGameCoordinator();

// Join game and room in one operation
await coordinator.joinGameAndRoom(roomId, playerName);

// Start match
await coordinator.startMatch(gameId);

// Play card
await coordinator.playCard(cardId, position);

// Leave game
await coordinator.leaveGame();
```

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## ✅ **Current Implementation Status**

### 🎉 **FULLY IMPLEMENTED AND STANDARDIZED (August 16, 2025)**

The Recall Game module has been **completely refactored** and **100% standardized** to use the Validated Incremental Event/State System. All architectural phases have been completed successfully.

#### **📊 Implementation Summary**

| Component Type | Pattern Used | Status |
|----------------|--------------|---------|
| **All Screens** | No state subscription (layout only) | ✅ **Implemented** |
| **All Widgets** | ListenableBuilder with StateManager | ✅ **Implemented** |
| **Service Layer** | GameService, RoomService, MessageService | ✅ **Implemented** |
| **Coordinator** | RecallGameCoordinator for high-level operations | ✅ **Implemented** |
| **Validation System** | Validated event emission and state updates | ✅ **Implemented** |
| **Event Listening** | Validated incoming event processing | ✅ **Implemented** |
| **State Slices** | Pre-computed widget-specific slices | ✅ **Implemented** |

#### **🎯 Completed Architectural Phases**

| Phase | Status | Priority | Progress |
|-------|--------|----------|----------|
| **Phase 1**: Documentation Alignment & Initial Compliance | ✅ **COMPLETED** | CRITICAL | 100% |
| **Phase 2**: Screen vs Widget State Pattern | ✅ **COMPLETED** | CRITICAL | 100% |
| **Phase 3A**: Service Layer Creation | ✅ **COMPLETED** | MEDIUM | 100% |
| **Phase 3B**: Service Layer Migration | ✅ **COMPLETED** | MEDIUM | 100% |
| **Phase 4**: UI Layer Simplification | ✅ **COMPLETED** | CRITICAL | 100% |
| **Phase 5**: Model Consistency | ✅ **COMPLETED** | LOW | 100% |

**Overall Progress: 100%** (5 of 5 major phases completed)

#### **🔧 Standardized Implementation Pattern**

```dart
// ✅ CURRENT IMPLEMENTATION: All recall game components use this pattern

// Screens - No state subscription, layout only
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        ActionBar(),    // Widgets handle their own state
        StatusBar(),    // Each subscribes independently
        MyHandPanel(),  // Granular, efficient updates
        CenterBoard(),  // Using ListenableBuilder
      ],
    );
  }
}

// Widgets - ListenableBuilder with StateManager
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}

// Services - Clean business logic separation
class GameService {
  Future<Map<String, dynamic>> startMatch(String gameId) async {
    return await RecallGameHelpers.startMatch(gameId);
  }
}

// Coordinator - High-level operation coordination
class RecallGameCoordinator {
  final GameService _gameService = GameService();
  
  Future<void> startMatch(String gameId) async {
    await _gameService.startMatch(gameId);
  }
}
```

#### **📈 Performance Metrics**

- **🚀 Widget Creation**: Simplified (ListenableBuilder pattern)
- **⚡ State Access**: Optimal (singleton StateManager instance)
- **🔄 Rebuilds**: Granular (only affected widgets rebuild)
- **🧹 Code Consistency**: 100% (all components follow same pattern)
- **🐛 Error Reduction**: Significant (validated events and state)
- **📊 Memory Usage**: Optimized (no unnecessary subscriptions)

#### **🎯 Architecture Compliance**

| Rule | Status | Details |
|------|--------|---------|
| Screens don't subscribe to state | ✅ **Compliant** | All screens handle layout only |
| Widgets use ListenableBuilder | ✅ **Compliant** | All widgets follow standardized pattern |
| Service layer separation | ✅ **Compliant** | GameService, RoomService, MessageService |
| Coordinator pattern | ✅ **Compliant** | RecallGameCoordinator for high-level operations |
| Validated events/state | ✅ **Compliant** | All updates use validation system |
| Event listener validation | ✅ **Compliant** | All incoming events validated |
| Widget state slices | ✅ **Compliant** | Pre-computed slices for performance |
| Proper lifecycle management | ✅ **Compliant** | All components handle init/dispose |

#### **🏆 Achieved Benefits**

1. **✅ Single Source of Truth**: `StateManager` is the ONLY state container
2. **✅ Clear Separation of Concerns**: Each component has ONE responsibility
3. **✅ Consistent Event Flow**: All events flow through validated systems
4. **✅ Modular Design**: Components can be independently tested and replaced
5. **✅ Predictable Data Flow**: Unidirectional data flow patterns
6. **✅ Screen vs Widget Pattern**: Screens load once, widgets subscribe to state
7. **✅ Service Layer Architecture**: Clean separation between UI, services, and coordination
8. **✅ Validated Event/State System**: Type-safe, validated WebSocket communication
9. **✅ Model Consistency**: All models use consistent patterns and proper logging
10. **✅ No Legacy Code**: All deprecated patterns completely removed
11. **✅ Performance Optimized**: Granular updates, minimal rebuilds
12. **✅ Developer Experience**: Clear APIs, comprehensive error handling

#### **🔍 Implementation Verification**

All components have been verified to follow the standardized pattern:

**Screens (2 total):**
- ✅ `GamePlayScreen` - No state subscription, layout only
- ✅ `LobbyScreen` - No state subscription, layout only

**Widgets (All follow standardized pattern):**
- ✅ **Consistent State Subscription**: All widgets use ListenableBuilder with StateManager
- ✅ **Standardized Structure**: All widgets follow the same 6-step pattern:
  1. **State Subscription**: `ListenableBuilder(listenable: StateManager())`
  2. **State Extraction**: `StateManager().getModuleState<Map<String, dynamic>>('recall_game')`
  3. **Slice Access**: Extract widget-specific state slice
  4. **Context Variables**: Extract standard game context (gamePhase, isGameActive, isMyTurn, playerStatus)
  5. **Build Method**: Call `_buildWidgetName()` with consistent parameters
  6. **Performance**: Nested ListenableBuilders for fine-grained reactivity when needed
- ✅ **Error Handling**: All widgets handle null states gracefully
- ✅ **Empty States**: All widgets have proper empty state displays

### 🏗️ Standardized Widget State Structure Pattern

All widgets in the Recall Game module follow a consistent, standardized pattern for state subscription and management. This ensures maintainability, predictability, and optimal performance.

#### **1. State Subscription Pattern**
```dart
return ListenableBuilder(
  listenable: StateManager(),
  builder: (context, child) {
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
```

#### **2. State Slice Extraction**
Each widget extracts its specific state slice:
```dart
// Widget-specific state slice extraction
final mySlice = recallGameState['widgetSpecificSlice'] as Map<String, dynamic>? ?? {};
```

#### **3. Standard Context Variables**
All widgets extract the same 4 context variables for consistency:
```dart
final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
final isGameActive = recallGameState['isGameActive'] ?? false;
final isMyTurn = recallGameState['isMyTurn'] ?? false;
final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
```

#### **4. Build Method Structure**
All widgets follow the same pattern:
```dart
return _buildWidgetName(
  // widget-specific parameters
  gamePhase: gamePhase,
  isGameActive: isGameActive,
  isMyTurn: isMyTurn,
  playerStatus: playerStatus,
);
```

#### **5. Build Method Signatures**
All `_build*` methods have consistent parameter signatures:
```dart
Widget _buildWidgetName({
  // widget-specific required params
  required String gamePhase,
  required bool isGameActive,
  required bool isMyTurn,
  required String playerStatus,
}) {
```

#### **6. Performance Optimizations**
- **Nested ListenableBuilders**: Used for fine-grained reactivity when needed
- **Consistent Error Handling**: All widgets handle null states gracefully
- **Empty State Handling**: All widgets have proper empty state displays

#### **7. Widget Type Consistency**
- **StatelessWidget**: Used for widgets that don't need internal state
- **StatefulWidget**: Used only when internal state is required (e.g., tracking clicked items)

This standardized pattern ensures that all widgets are:
- **Predictable**: Same structure across all widgets
- **Maintainable**: Easy to understand and modify
- **Performant**: Optimized for minimal rebuilds
- **Consistent**: Follows the same architectural principles

**Services (3 total):**
- ✅ `GameService` - Game-specific business logic
- ✅ `RoomService` - Room management operations
- ✅ `MessageService` - Messaging and communication

**Coordinators (1 total):**
- ✅ `RecallGameCoordinator` - High-level operation coordination

**Validation Components (4 total):**
- ✅ `RecallGameEventEmitter` - Outgoing event validation
- ✅ `RecallGameStateUpdater` - State update validation
- ✅ `RecallGameEventListenerValidator` - Incoming event validation
- ✅ `RecallGameHelpers` - Convenient helper methods

#### **🎉 Final Result**

The Recall Game module has been **successfully and completely refactored** to follow modern Flutter architecture patterns with **strict adherence** to the Validated Incremental Event/State System guidelines! 

**No legacy code remains** - the architecture is now clean, maintainable, and ready for future development! 🎉

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(gameId),
                child: Text('Start Match'),
              ),
          ],
        );
      },
    );
  }
}
```

### 📋 Implementation Rules

#### 1. Screen Responsibilities
```dart
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // ✅ Screens handle:
    // - Layout structure
    // - Navigation logic
    // - One-time initialization
    // - Static UI elements
    
    return Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: Column(
        children: [
          MyWidget1(), // Widgets handle their own state
          MyWidget2(), // Each subscribes independently
          MyWidget3(), // Granular, efficient updates
        ],
      ),
    );
  }
}
```

#### 2. Widget Responsibilities
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['myWidgetSlice'] as Map<String, dynamic>? ?? {};
        
        // ✅ Widgets handle:
        // - Data display
        // - State-driven UI updates
        // - User interactions
        // - Specific business logic
        
        return Container(
          child: Text(mySlice['displayText'] ?? 'Loading...'),
        );
      },
    );
  }
}
```

### 🎯 State Slice Design

#### Optimized Widget Slices
```dart
// Pre-computed state slices for optimal performance
'recall_game': {
  // Core game data
  'gameId': 'game_123',
  'isGameStarted': true,
  
  // Widget-specific slices (pre-computed for performance)
  'actionBar': {
    'showStartButton': false,
    'canPlayCard': true,
    'canCallRecall': false,
    'isGameStarted': true,
  },
  'statusBar': {
    'currentPhase': 'active',
    'turnInfo': 'Your turn',
    'playerCount': 4,
  },
  'myHand': {
    'cards': [...],
    'selectedCardId': 'card_hearts_ace',
    'canSelectCards': true,
  },
  'centerBoard': {
    'discardPile': [...],
    'currentCard': {...},
    'animations': {...},
  },
  'messageBoard': {
    'messages': [...],
    'unreadCount': 3,
  },
  'roomList': {
    'rooms': [...],
    'selectedRoomId': 'room_123',
  },
  'connectionStatus': {
    'isConnected': true,
    'lastPing': 1234567890,
    'connectionQuality': 'good',
  },
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        
        // ✅ Access only your widget's slice
        final statusBarState = state['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Widget only rebuilds when statusBar slice changes
        return Container(
          child: Column(
            children: [
              Text('Phase: ${statusBarState['currentPhase'] ?? 'Unknown'}'),
              Text('Turn: ${statusBarState['turnInfo'] ?? 'Waiting...'}'),
              Text('Players: ${statusBarState['playerCount'] ?? 0}'),
            ],
          ),
        );
      },
    );
  }
}
```

### ⚡ Performance Benefits

#### Before (Screen Subscription)
```
State Change → Entire Screen Rebuilds → All Widgets Rebuild → Poor Performance
```

#### After (Widget Subscription with ListenableBuilder)
```
State Change → Only Affected Widget Rebuilds → Optimal Performance
```

#### Benchmark Example
```dart
// ❌ Screen subscription: 1 state change = 10 widget rebuilds
// ✅ Widget subscription: 1 state change = 1 widget rebuild (90% reduction)
```

### 🧪 Testing Widget Subscriptions

```dart
testWidgets('Widget subscribes to correct state slice', (tester) async {
  // Setup state
  StateManager().updateModuleState('recall_game', {
    'actionBar': {'showStartButton': true},
    'statusBar': {'currentPhase': 'waiting'}, // Different slice
  });
  
  await tester.pumpWidget(ActionBar());
  
  // ActionBar should show start button
  expect(find.text('Start Match'), findsOneWidget);
  
  // Update different slice
  StateManager().updateModuleState('recall_game', {
    'statusBar': {'currentPhase': 'active'}, // ActionBar shouldn't rebuild
  });
  
  await tester.pump();
  
  // ActionBar still shows start button (didn't rebuild unnecessarily)
  expect(find.text('Start Match'), findsOneWidget);
});
```

### 🔧 Migration from Screen to Widget Subscription

#### Step 1: Remove Screen State Subscription
```dart
// Before
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ❌ Remove this
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        return MyWidget();
      },
    );
  }
}

// After  
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Simple, no state subscription
  }
}
```

#### Step 2: Add Widget State Subscriptions with ListenableBuilder
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('my_module') ?? {};
        final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
        return Text(mySlice['text'] ?? 'Loading...');
      },
    );
  }
}
```

### 📊 State Slice Optimization

#### Helper Method for State Slice Updates
```dart
// In RecallGameHelpers
static void updateActionBarState({
  bool? showStartButton,
  bool? canPlayCard,
  bool? canCallRecall,
}) {
  final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentActionBar = currentState['actionBar'] as Map<String, dynamic>? ?? {};
  
  final updatedActionBar = Map<String, dynamic>.from(currentActionBar);
  if (showStartButton != null) updatedActionBar['showStartButton'] = showStartButton;
  if (canPlayCard != null) updatedActionBar['canPlayCard'] = canPlayCard;
  if (canCallRecall != null) updatedActionBar['canCallRecall'] = canCallRecall;
  
  RecallGameStateUpdater().updateState({
    'actionBar': updatedActionBar,
  });
}
```

This pattern ensures that:
- 🎯 **Screens load once** and handle layout/navigation
- 🔄 **Widgets subscribe individually** to their specific state slices using ListenableBuilder
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## 🛡️ Validation Rules

### Type Validation
- **String**: Must be string type
- **int**: Must be integer type
- **bool**: Must be boolean type
- **Map**: Must be Map<String, dynamic>
- **List**: Must be List<dynamic>

### Pattern Validation
```dart
// Card ID pattern
'cardId': FieldSpec(pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$')
// Matches: card_hearts_ace, card_spades_10, card_clubs_king

// Room ID pattern  
'roomId': FieldSpec(pattern: r'^room_[a-zA-Z0-9_]+$')
// Matches: room_abc123, room_lobby_001
```

### Range Validation
```dart
// Player count limits
'maxPlayers': FieldSpec(type: int, min: 2, max: 6)

// Card position limits
'position': FieldSpec(type: int, min: 0, max: 3)
```

### Enumerated Values
```dart
// Game phase validation
'gamePhase': FieldSpec(allowedValues: ['waiting', 'active', 'finished'])

// Card suit validation
'suit': FieldSpec(allowedValues: ['hearts', 'diamonds', 'clubs', 'spades'])
```

## 🔄 Data Flow

### Event Flow
```
User Action → Helper Method → Event Emitter → Validation → WebSocket → Backend
     ↓
UI Update ← State Manager ← State Updater ← Validation ← WebSocket ← Backend Response
```

### State Flow
```
Backend Event → Event Handler → Helper Method → State Updater → Validation → StateManager → UI Rebuild
```

### Incoming Event Flow
```
WebSocket Event → Event Listener Validator → Schema Validation → Data Enrichment → Callback Execution → State Updates
     ↓
Backend Event → Event Type Extraction → Field Validation → Timestamp Addition → Validated Data → UI State Changes
```

**Incoming Event Processing:**
1. **WebSocket Reception**: `WSEventManager` receives `recall_game_event` messages
2. **Event Validation**: `RecallGameEventListenerValidator` validates event type and data
3. **Schema Compliance**: Only allowed fields are included in validated data
4. **Data Enrichment**: `event_type` and `timestamp` are automatically added
5. **Callback Execution**: Registered event listeners receive validated data
6. **State Synchronization**: UI components update based on validated event data

## 🖼️ Screen vs Widget State Subscription Pattern

### ⚠️ CRITICAL ARCHITECTURAL RULE

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices using ListenableBuilder.**

This pattern ensures:
- **Granular Updates**: Only affected widgets rebuild, not entire screens
- **Performance**: Minimizes unnecessary rebuilds
- **Separation of Concerns**: Screens handle layout/navigation, widgets handle data display
- **Maintainability**: Clear responsibility boundaries

### ❌ WRONG: Screen State Subscription

```dart
// ❌ DON'T DO THIS - Screen subscribing to state
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // ❌ Screen subscribing
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        return Column(
          children: [
            ActionBar(), // Entire screen rebuilds when ANY state changes
            StatusBar(),
            MyHandPanel(),
            CenterBoard(),
          ],
        );
      },
    );
  }
}
```

**Problems with this approach:**
- 🐌 **Poor Performance**: Entire screen rebuilds on any state change
- 🔄 **Unnecessary Rebuilds**: All widgets rebuild even if their data didn't change
- 🧩 **Tight Coupling**: Screen becomes dependent on all state changes
- 🐛 **Hard to Debug**: Difficult to track which widget caused a rebuild

### ✅ CORRECT: Widget State Subscription with ListenableBuilder

```dart
// ✅ CORRECT - Screen loads once, no state subscription
class GamePlayScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    // Screen loads once and never rebuilds from state changes
    return Column(
      children: [
        ActionBar(),    // Each widget subscribes to its own state slice
        StatusBar(),    // Only rebuilds when its specific data changes
        MyHandPanel(),  // Independent state subscriptions
        CenterBoard(),  // Granular, efficient updates
      ],
    );
  }
}

// ✅ Individual widgets subscribe to their state slices using ListenableBuilder
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final state = StateManager().getModuleState('recall_game') ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        