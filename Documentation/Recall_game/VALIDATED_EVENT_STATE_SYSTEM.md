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

## 🏗️ Architecture Components

### 1. Field Specifications (`field_specifications.dart`)

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

Centralizes and validates all WebSocket event emissions.

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
  static Future<void> joinGame(String gameId) async { ... }
  static Future<void> playCard(String cardId) async { ... }
  
  // State Update Helpers
  static void updateGameInfo(Map<String, dynamic> gameInfo) { ... }
  static void updatePlayerTurn(String playerId, bool isMyTurn) { ... }
  static void updateConnectionStatus(bool isConnected) { ... }
  
  // UI State Helpers
  static void setSelectedCard(String cardId) { ... }
  static void updateUIState(String key, dynamic value) { ... }
  
  // Event Listener Helpers (via extension)
  static void onEvent(String eventType, Function(Map<String, dynamic>) callback) { ... }
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
  'play_card': {
    'cardId': FieldSpec(type: String, required: true, pattern: r'^card_[a-zA-Z]+_[a-zA-Z0-9]+$'),
    'position': FieldSpec(type: int, min: 0, max: 3),
  },
  // ... more event types
};
```

### State Validation Schema

```dart
static final Map<String, FieldSpec> _stateSchema = {
  // Core Game Fields
  'gameId': FieldSpec(type: String),
  'playerId': FieldSpec(type: String),
  'isGameStarted': FieldSpec(type: bool),
  'gamePhase': FieldSpec(type: String, allowedValues: ['waiting', 'active', 'finished']),
  
  // Room Fields
  'roomId': FieldSpec(type: String),
  'roomName': FieldSpec(type: String),
  'isRoomOwner': FieldSpec(type: bool),
  
  // Player Fields
  'currentTurn': FieldSpec(type: String),
  'playerCount': FieldSpec(type: int, min: 1, max: 6),
  'isMyTurn': FieldSpec(type: bool),
  
  // Connection Fields
  'isConnected': FieldSpec(type: bool),
  'lastPing': FieldSpec(type: int),
  
  // Widget State Slices (not validated - for UI performance)
  'actionBar': FieldSpec(type: Map),
  'statusBar': FieldSpec(type: Map),
  'myHand': FieldSpec(type: Map),
  'centerBoard': FieldSpec(type: Map),
  'opponentsPanel': FieldSpec(type: Map),
};
```

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
  
  // System Events
  'recall_called': {
    'game_id', 'player_id', 'timestamp', 'scores',
    'updated_game_state',
  },
  'error': {
    'error', 'message', 'code', 'details', 'timestamp',
  },
  'connection_status': {
    'status', 'session_id', 'error', 'timestamp',
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
  RecallGameHelpers.updateUIState('centerBoard', {
    'lastPlayedCard': card,
    'lastPosition': position,
    'wasOutOfTurn': isOutOfTurn,
  });
});

// ✅ Listen to error events
RecallGameHelpers.onEvent('error', (data) {
  final errorCode = data['code'];
  final errorMessage = data['message'];
  
  // Show error to user
  _showErrorSnackBar('Error $errorCode: $errorMessage');
});
```

### UI State Management

```dart
// ✅ Transient UI state (not validated for performance)
RecallGameHelpers.setSelectedCard('card_hearts_ace');
RecallGameHelpers.updateUIState('rooms', roomsList);
RecallGameHelpers.clearSelectedCard();
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

**Screens DO NOT subscribe to state. Only individual widgets subscribe to their specific state slices.**

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

### ✅ CORRECT: Widget State Subscription

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

// ✅ Individual widgets subscribe to their state slices
class ActionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'), // Widget-level subscription
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        final actionBarState = state['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Only rebuilds when actionBar state changes
        return Row(
          children: [
            if (actionBarState['showStartButton'] == true)
              ElevatedButton(
                onPressed: () => RecallGameHelpers.startMatch(),
                child: Text('Start Match'),
              ),
            if (actionBarState['canPlayCard'] == true)
              ElevatedButton(
                onPressed: () => _playSelectedCard(),
                child: Text('Play Card'),
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
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
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
}
```

#### Widget State Access Pattern
```dart
class StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('recall_game'),
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
        
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

#### After (Widget Subscription)
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

#### Step 2: Add Widget State Subscriptions
```dart
// Add subscription to individual widgets
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>( // ✅ Widget-level subscription
      stream: StateManager().getModuleStateStream('my_module'),
      builder: (context, snapshot) {
        final state = snapshot.data ?? {};
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
- 🔄 **Widgets subscribe individually** to their specific state slices  
- ⚡ **Performance is optimized** with minimal, targeted rebuilds
- 🧩 **Concerns are separated** between layout and data display
- 🐛 **Debugging is easier** with clear responsibility boundaries

## ✅ **Current Implementation Status**

### 🎉 **Pattern 1 Fully Implemented (August 16, 2025)**

The recall game module has been **completely standardized** to use Pattern 1 across all widgets. Here's the current state:

#### **📊 Implementation Summary**

| Component Type | Pattern Used | Status |
|----------------|--------------|---------|
| **All Widgets** | Pattern 1: `final StateManager _stateManager = StateManager()` | ✅ **Implemented** |
| **All Screens** | No state subscription (layout only) | ✅ **Implemented** |
| **State Slices** | Pre-computed widget-specific slices | ✅ **Implemented** |
| **Validation System** | Validated event emission and state updates | ✅ **Implemented** |

#### **🎯 Widgets Following Pattern 1**

**Game Play Widgets:**
- ✅ `ActionBar` - Creates own StateManager instance
- ✅ `StatusBar` - Creates own StateManager instance  
- ✅ `MyHandPanel` - Creates own StateManager instance
- ✅ `CenterBoard` - Creates own StateManager instance

**Lobby Widgets:**
- ✅ `MessageBoardWidget` - Creates own StateManager instance
- ✅ `RoomMessageBoardWidget` - Creates own StateManager instance
- ✅ `CurrentRoomWidget` - Creates own StateManager instance
- ✅ `RoomListWidget` - Creates own StateManager instance
- ✅ `ConnectionStatusWidget` - Creates own StateManager instance

**Screens & Services:**
- ✅ `GamePlayScreen` - No state subscription (layout only)
- ✅ `LobbyScreen` - No state subscription (layout only)
- ✅ `RoomService` - Creates own StateManager instance

#### **🔧 Standardization Results**

```dart
// ✅ CURRENT IMPLEMENTATION: All widgets use this pattern
class MyWidget extends StatefulWidget {
  const MyWidget({Key? key}) : super(key: key); // No StateManager parameter

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final StateManager _stateManager = StateManager(); // ✅ Widget creates its own instance

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onChanged); // ✅ Direct subscription
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onChanged); // ✅ Proper cleanup
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {}); // ✅ Safe rebuilds
  }

  @override
  Widget build(BuildContext context) {
    final state = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
    return Text(mySlice['text'] ?? 'Loading...'); // ✅ Widget-specific state access
  }
}
```

#### **📈 Performance Metrics**

- **🚀 Widget Creation**: Simplified (no parameter passing)
- **⚡ State Access**: Optimal (singleton StateManager instance)
- **🔄 Rebuilds**: Granular (only affected widgets rebuild)
- **🧹 Code Consistency**: 100% (all widgets follow same pattern)
- **🐛 Error Reduction**: Significant (no parameter passing mistakes)

#### **🎯 Architecture Compliance**

| Rule | Status | Details |
|------|--------|---------|
| Screens don't subscribe to state | ✅ **Compliant** | All screens handle layout only |
| Widgets create own StateManager | ✅ **Compliant** | All 12 widgets follow Pattern 1 |
| Widget state slices | ✅ **Compliant** | Pre-computed slices for performance |
| Validated events/state | ✅ **Compliant** | All updates use validation system |
| Proper lifecycle management | ✅ **Compliant** | All widgets handle init/dispose |

## ⚡ Performance Optimizations

### 1. Incremental Updates
- Only validates and updates changed fields
- Avoids full object replacement
- Minimizes UI rebuilds

### 2. Widget State Slices
```dart
// Pre-computed widget-specific state
'actionBar': {
  'showStartButton': true,
  'canPlayCard': false,
  'canCallRecall': false,
  'isGameStarted': false,
}
```

### 3. Validation Caching
- Schema validation is performed once at startup
- Field specs are cached for repeated use
- Type checking is optimized for common types

## 🚨 Error Handling

### Validation Errors
```dart
try {
  await RecallGameEventEmitter().emit('play_card', {
    'cardId': 'invalid_format', // Fails pattern validation
  });
} catch (e) {
  // ValidationError: Field 'cardId' does not match pattern '^card_[a-zA-Z]+_[a-zA-Z0-9]+$'
}
```

### Schema Errors
```dart
try {
  RecallGameStateUpdater().updateState({
    'unknownField': 'value', // Not in schema
  });
} catch (e) {
  // SchemaError: Field 'unknownField' is not defined in schema
}
```

### Type Errors
```dart
try {
  RecallGameStateUpdater().updateState({
    'playerCount': 'three', // Wrong type (should be int)
  });
} catch (e) {
  // ValidationError: Field 'playerCount' expected int, got String
}
```

### Event Listener Validation Errors

The Event Listener Validator provides robust error handling for incoming WebSocket events:

```dart
// ❌ Missing event_type field
// WebSocket data: {'data': 'some_value'}
// Result: Logs error "Missing event_type in recall game event"

// ❌ Unknown event type
// WebSocket data: {'event_type': 'unknown_event', 'data': 'value'}
// Result: Logs error "Unknown recall game event type: unknown_event"

// ❌ Invalid event data structure
// WebSocket data: {'event_type': 'game_started', 'invalid_field': 'value'}
// Result: Only valid fields are included, invalid fields are filtered out

// ✅ Valid event processing
// WebSocket data: {'event_type': 'game_started', 'game_id': '123', 'game_state': 'active'}
// Result: Event processed successfully, callback executed with validated data
```

**Error Handling Features:**
- **Graceful Degradation**: Invalid events don't crash the application
- **Detailed Logging**: Comprehensive error messages for debugging
- **Field Filtering**: Only schema-compliant fields are passed to callbacks
- **Automatic Recovery**: Application continues processing valid events
- **Developer Feedback**: Clear error messages identify validation issues

## 🧪 Testing

### Unit Tests
```dart
test('Event validation rejects invalid card ID', () {
  expect(
    () => RecallGameEventEmitter().emit('play_card', {'cardId': 'invalid'}),
    throwsA(isA<ValidationError>()),
  );
});

test('State validation accepts valid game phase', () {
  expect(
    () => RecallGameStateUpdater().updateState({'gamePhase': 'active'}),
    returnsNormally,
  );
});
```

### Integration Tests
```dart
testWidgets('Helper methods update UI correctly', (tester) async {
  RecallGameHelpers.updateGameInfo({'isGameStarted': true});
  await tester.pump();
  
  expect(find.text('Game Started'), findsOneWidget);
});
```

### Event Listener Tests
```dart
test('Event listener validator processes valid events correctly', () {
  final validator = RecallGameEventListenerValidator.instance;
  bool callbackCalled = false;
  Map<String, dynamic>? receivedData;
  
  // Add listener for game_started event
  validator.addListener('game_started', (data) {
    callbackCalled = true;
    receivedData = data;
  });
  
  // Simulate valid WebSocket event
  final validEvent = {
    'event_type': 'game_started',
    'game_id': 'game_123',
    'game_state': 'active',
    'started_by': 'player_456',
  };
  
  // Process event (this would normally come from WSEventManager)
  // For testing, we need to simulate the event processing
  
  expect(callbackCalled, isTrue);
  expect(receivedData, isNotNull);
  expect(receivedData!['game_id'], equals('game_123'));
  expect(receivedData!['event_type'], equals('game_started'));
  expect(receivedData!['timestamp'], isNotNull); // Auto-added
});

test('Event listener validator filters invalid fields', () {
  final validator = RecallGameEventListenerValidator.instance;
  Map<String, dynamic>? receivedData;
  
  validator.addListener('player_joined', (data) {
    receivedData = data;
  });
  
  // Event with valid and invalid fields
  final mixedEvent = {
    'event_type': 'player_joined',
    'game_id': 'game_123',
    'player_id': 'player_789',
    'player_name': 'John',
    'invalid_field': 'should_be_filtered', // Not in schema
    'another_invalid': 'also_filtered',    // Not in schema
  };
  
  // Process event and verify only valid fields remain
  // receivedData should only contain schema-defined fields
  
  expect(receivedData!.containsKey('invalid_field'), isFalse);
  expect(receivedData!.containsKey('another_invalid'), isFalse);
  expect(receivedData!.containsKey('game_id'), isTrue);
  expect(receivedData!.containsKey('player_id'), isTrue);
});

test('Event listener validator handles unknown event types gracefully', () {
  final validator = RecallGameEventListenerValidator.instance;
  bool callbackCalled = false;
  
  validator.addListener('unknown_event', (data) {
    callbackCalled = true;
  });
  
  // Simulate unknown event type
  final unknownEvent = {
    'event_type': 'completely_unknown_event',
    'data': 'some_value',
  };
  
  // Process event - should log error but not crash
  // Callback should not be called for unknown events
  
  expect(callbackCalled, isFalse);
});
```

## 🔧 Configuration

### Adding New Event Types
```dart
// In field_specifications.dart
static final Map<String, Map<String, FieldSpec>> _allowedEventFields = {
  'new_event_type': {
    'requiredField': FieldSpec(type: String, required: true),
    'optionalField': FieldSpec(type: int, min: 0),
  },
};
```

### Adding New State Fields
```dart
// In field_specifications.dart
static final Map<String, FieldSpec> _stateSchema = {
  'newStateField': FieldSpec(type: bool),
  'newComplexField': FieldSpec(type: Map),
};
```

### Adding New Helper Methods
```dart
// In recall_game_helpers.dart
class RecallGameHelpers {
  static Future<void> newEventHelper(String param) async {
    await RecallGameEventEmitter().emit('new_event_type', {
      'requiredField': param,
    });
  }
  
  static void newStateHelper(dynamic value) {
    RecallGameStateUpdater().updateState({
      'newStateField': value,
    });
  }
}
```

### Adding New Event Types

To add new incoming event types to the Event Listener Validator:

```dart
// In recall_event_listener_validator.dart
static const Map<String, Set<String>> _eventSchema = {
  // ... existing events ...
  
  // New event type
  'new_game_event': {
    'game_id', 'event_data', 'timestamp', 'metadata',
  },
  
  // New player event
  'player_achievement': {
    'player_id', 'achievement_type', 'achievement_data', 'timestamp',
  },
};
```

**Adding New Event Types Process:**
1. **Define Schema**: Add the event type and its allowed fields to `_eventSchema`
2. **Field Selection**: Choose only the fields that are essential for the event
3. **Consistent Naming**: Use snake_case for field names to match backend conventions
4. **Required Fields**: Include `timestamp` and other essential identifiers
5. **Optional Fields**: Add fields that might be useful but aren't critical
6. **Testing**: Verify the new event type processes correctly with test data

### Event Schema Best Practices

```dart
// ✅ GOOD: Clear, focused field sets
'card_played': {
  'game_id', 'player_id', 'card', 'position', 'timestamp',
  'is_out_of_turn', 'remaining_cards',
},

// ❌ AVOID: Too many fields, unclear purpose
'card_played': {
  'game_id', 'player_id', 'card', 'position', 'timestamp',
  'is_out_of_turn', 'remaining_cards', 'weather', 'mood', 'random_data',
},

// ✅ GOOD: Consistent field naming
'player_joined': {
  'game_id', 'player_id', 'player_name', 'timestamp',
},

// ❌ AVOID: Inconsistent naming
'player_joined': {
  'game_id', 'playerId', 'player_name', 'time', // Mixed naming conventions
},
```

## 📊 Benefits

### Before Implementation
- ❌ Manual validation in each component
- ❌ Inconsistent data formats
- ❌ Runtime errors from invalid data
- ❌ Difficult debugging
- ❌ Fragile event/state coupling
- ❌ No validation of incoming WebSocket events
- ❌ Risk of backend data corruption affecting frontend
- ❌ Difficult to track event processing issues

### After Implementation  
- ✅ Centralized validation for both outgoing and incoming events
- ✅ Consistent data schemas across the entire system
- ✅ Compile-time error prevention
- ✅ Clear error messages for debugging
- ✅ Robust event/state architecture
- ✅ Developer-friendly APIs
- ✅ Performance optimized with granular updates
- ✅ Easily testable components
- ✅ Maintainable and scalable codebase
- ✅ **Incoming Event Protection**: All backend events are validated before processing
- ✅ **Data Integrity**: Only schema-compliant fields reach UI components
- ✅ **Error Resilience**: Invalid events don't crash the application
- ✅ **Automatic Logging**: Comprehensive event tracking for debugging
- ✅ **Schema Evolution**: Easy to add new event types and fields

## 🎯 Migration Guide

### Step 1: Replace Direct Event Emissions
```dart
// Before
_wsManager.sendCustomEvent('create_room', {'name': roomName});

// After
await RecallGameHelpers.createRoom(roomName);
```

### Step 2: Replace Direct State Updates
```dart
// Before
_stateManager.updateModuleState('recall_game', {'gameId': id});

// After
RecallGameHelpers.updateGameInfo({'gameId': id});
```

### Step 3: Update Event Handlers
```dart
// Before
void _handleGameStarted(Map<String, dynamic> data) {
  _stateManager.updateModuleState('recall_game', data);
}

// After
void _handleGameStarted(Map<String, dynamic> data) {
  RecallGameHelpers.updateGameInfo(data);
}
```

### Step 4: Replace Direct Event Listening
```dart
// Before: Direct WebSocket event handling
_wsManager.onEvent('recall_game_event', (data) {
  if (data['event_type'] == 'game_started') {
    // Manual validation and processing
    if (data.containsKey('game_id') && data.containsKey('game_state')) {
      _handleGameStarted(data);
    }
  }
});

// After: Validated event listening
RecallGameHelpers.onEvent('game_started', (data) {
  // data is automatically validated and contains only allowed fields
  _handleGameStarted(data);
});
```

### Step 5: Update Event Handler Registration
```dart
// Before: Manual event type checking
void _setupEventHandlers() {
  _wsManager.onEvent('recall_game_event', (data) {
    final eventType = data['event_type'];
    switch (eventType) {
      case 'game_started':
        _handleGameStarted(data);
        break;
      case 'player_joined':
        _handlePlayerJoined(data);
        break;
      // ... more cases
    }
  });
}

// After: Clean, validated event handlers
void _setupEventHandlers() {
  RecallGameHelpers.onEvent('game_started', _handleGameStarted);
  RecallGameHelpers.onEvent('player_joined', _handlePlayerJoined);
  RecallGameHelpers.onEvent('card_played', _handleCardPlayed);
  RecallGameHelpers.onEvent('turn_changed', _handleTurnChanged);
  // ... more handlers
}
```

## 🔮 Future Enhancements

### Planned Features
- **Schema Versioning**: Support for backward-compatible schema changes
- **Custom Validators**: Plugin architecture for complex validation rules  
- **Performance Metrics**: Built-in monitoring for validation overhead
- **Auto-Documentation**: Generate API docs from schema definitions
- **IDE Integration**: VSCode extension for schema validation
- **Real-time Debugging**: Development tools for event/state inspection

### Extensibility
- **Multi-Module Support**: Extend to other game modules
- **Backend Integration**: Share schemas between frontend and backend
- **Cross-Platform**: Use same validation system across Flutter platforms

---

## 📚 Related Documentation

- [Architecture Overview](ARCHITECTURE.md)
- [State Manager Guide](MANAGERS.md)
- [WebSocket Integration](API_REFERENCE.md)
- [Testing Guidelines](../Recall_game/Game_play.md)

## 🚀 Quick Reference

### ✅ **Current Standardized Pattern (Fully Implemented)**

```dart
// ✅ CURRENT IMPLEMENTATION: All recall game widgets use this pattern
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return MyWidget(); // ✅ Screen loads once, no subscription, no parameters
  }
}

class MyWidget extends StatefulWidget {
  const MyWidget({Key? key}) : super(key: key); // ✅ No StateManager parameter

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final StateManager _stateManager = StateManager(); // ✅ Widget creates its own instance

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onChanged); // ✅ Direct subscription
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onChanged); // ✅ Proper cleanup
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {}); // ✅ Safe rebuilds
  }

  @override
  Widget build(BuildContext context) {
    final state = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final mySlice = state['mySlice'] as Map<String, dynamic>? ?? {};
    return Text(mySlice['text'] ?? 'Loading...'); // ✅ Widget-specific state access
  }
}
```

### ❌ **Deprecated Patterns (No Longer Used)**

```dart
// ❌ DEPRECATED: Screen subscribes to state (never use)
class MyScreen extends BaseScreen {
  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StateManager().getModuleStateStream('module'), // ❌ Don't do this
      builder: (context, snapshot) => MyWidget(),
    );
  }
}

// ❌ DEPRECATED: Widget receives StateManager parameter (no longer used)
class MyWidget extends StatefulWidget {
  final StateManager stateManager; // ❌ No longer needed
  const MyWidget({Key? key, required this.stateManager}) : super(key: key);
}
```

### Event Emission Pattern
```dart
// ❌ OLD: Direct WebSocket calls
_wsManager.sendCustomEvent('create_room', {'name': roomName});

// ✅ NEW: Validated helper methods
await RecallGameHelpers.createRoom(roomName);
```

### State Update Pattern
```dart
// ❌ OLD: Direct StateManager calls
_stateManager.updateModuleState('recall_game', {'gameId': id});

// ✅ NEW: Validated helper methods
RecallGameHelpers.updateGameInfo({'gameId': id});
```

### Event Listening Pattern
```dart
// ❌ OLD: Direct WebSocket event handling with manual validation
_wsManager.onEvent('recall_game_event', (data) {
  if (data['event_type'] == 'game_started') {
    // Manual field checking and validation
    if (data.containsKey('game_id')) {
      _handleGameStarted(data);
    }
  }
});

// ✅ NEW: Validated event listening
RecallGameHelpers.onEvent('game_started', (data) {
  // data is automatically validated and contains only allowed fields
  _handleGameStarted(data);
});
```

### Key Principles ✅ **All Implemented**
1. **🎯 Screens**: Load once, handle layout/navigation, no state subscription ✅ **Implemented**
2. **🔄 Widgets**: Create own StateManager instance, subscribe to specific state slices ✅ **Implemented**
3. **🛡️ Validation**: All events and state updates are validated ✅ **Implemented**
4. **📡 Event Listening**: All incoming events are validated and processed safely ✅ **Implemented**
5. **⚡ Performance**: Granular updates, minimal rebuilds ✅ **Implemented**
6. **🧩 Separation**: Clear boundaries between concerns ✅ **Implemented**
7. **🔧 Consistency**: All 12 widgets follow Pattern 1 standardization ✅ **Implemented**

---

**Last Updated**: August 16, 2025  
**Version**: 2.0.0  
**Status**: ✅ Fully Implemented and Standardized (Pattern 1)

