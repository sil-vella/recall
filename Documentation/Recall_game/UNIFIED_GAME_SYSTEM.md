# Unified Game System Architecture

## Overview

The Recall game system uses a **Single Source of Truth (SSOT)** architecture where both **practice mode** and **multiplayer mode** share the exact same backend game logic. This unified approach ensures consistent game behavior, reduces code duplication, and simplifies maintenance.

## Architecture Principles

### Single Source of Truth (SSOT)

The core game logic lives in `backend_core/` directories that are **exact replicas** across both modes:

- **Flutter Practice Mode**: `flutter_base_05/lib/modules/recall_game/backend_core/`
- **Dart Backend (Multiplayer)**: `dart_bkend_base_01/lib/modules/recall_game/backend_core/`

Both directories contain identical implementations of:
- `shared_logic/recall_game_round.dart` - Core game round management
- `coordinator/game_event_coordinator.dart` - Event routing and coordination
- `services/game_registry.dart` - Game instance management
- `services/game_state_store.dart` - State persistence
- All game models, utilities, and shared logic

### Unified Game Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Player Action (UI)                        │
│  (play_card, draw_card, same_rank_play, etc.)               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Transport Layer (Mode-Specific)                 │
│  ┌────────────────────┐      ┌──────────────────────┐      │
│  │  Practice Mode     │      │  Multiplayer Mode    │      │
│  │  Bridge            │      │  WebSocket Bridge    │      │
│  └────────────────────┘      └──────────────────────┘      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│           Unified Backend Core (SSOT)                        │
│  ┌────────────────────────────────────────────────────┐    │
│  │  GameEventCoordinator                              │    │
│  │  - Routes events to appropriate handlers           │    │
│  │  - Manages room/session mapping                    │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼─────────────────────────────┐    │
│  │  GameRegistry                                       │    │
│  │  - Creates/manages RecallGameRound instances       │    │
│  │  - One round per room/game                         │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼─────────────────────────────┐    │
│  │  RecallGameRound (Core Game Logic)                 │    │
│  │  - Turn management                                 │    │
│  │  - Card actions (play, draw, same rank, etc.)      │    │
│  │  - Special cards (Jack, Queen)                     │    │
│  │  - Computer player AI                              │    │
│  │  - State updates via GameStateCallback             │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼─────────────────────────────┐    │
│  │  GameStateStore                                    │    │
│  │  - Persists game state per room                    │    │
│  │  - Single source of truth for game data            │    │
│  └────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              State Broadcast (Mode-Specific)                 │
│  ┌────────────────────┐      ┌──────────────────────┐      │
│  │  Practice Mode     │      │  Multiplayer Mode    │      │
│  │  Event Manager     │      │  WebSocket Broadcast │      │
│  └────────────────────┘      └──────────────────────┘      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    UI State Updates                          │
│  (StateManager → Widget Slices → UI Rendering)              │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. GameEventCoordinator

The central event router that receives all game events and delegates to the appropriate game logic.

**Location**: `backend_core/coordinator/game_event_coordinator.dart`

**Responsibilities**:
- Route events to the correct game round instance
- Map sessions to rooms and players
- Validate event context (room membership, player turn, etc.)

**Key Method**:
```dart
Future<void> handle(String sessionId, String event, Map<String, dynamic> data) async {
  final roomId = roomManager.getRoomForSession(sessionId);
  final round = _registry.getOrCreate(roomId, server);
  
  switch (event) {
    case 'play_card':
      await round.handlePlayCard(cardId, playerId: playerId, gamesMap: gamesMap);
      break;
    case 'draw_card':
      await round.handleDrawCard(source, playerId: playerId, gamesMap: gamesMap);
      break;
    // ... other events
  }
}
```

### 2. GameRegistry

Manages game round instances, ensuring one `RecallGameRound` per room.

**Location**: `backend_core/services/game_registry.dart`

**Responsibilities**:
- Create and cache `RecallGameRound` instances
- Wire game rounds with appropriate callbacks
- Dispose of game rounds when rooms close

**Key Method**:
```dart
RecallGameRound getOrCreate(String roomId, WebSocketServer server) {
  return _roomIdToRound.putIfAbsent(roomId, () {
    final callback = _ServerGameStateCallbackImpl(roomId, server);
    final round = RecallGameRound(callback, roomId);
    return round;
  });
}
```

### 3. RecallGameRound

The core game logic engine that handles all gameplay mechanics.

**Location**: `backend_core/shared_logic/recall_game_round.dart`

**Responsibilities**:
- Turn management and progression
- Card actions (play, draw, same rank plays)
- Special card powers (Jack swap, Queen peek)
- Computer player AI decision-making
- Game state updates via `GameStateCallback`

**Key Methods**:
- `handlePlayCard()` - Process card play actions
- `handleDrawCard()` - Process card draw actions
- `handleSameRankPlay()` - Process out-of-turn same rank plays
- `_moveToNextPlayer()` - Advance to next player's turn
- `_handleSameRankWindow()` - Manage same rank play window
- `_handleSpecialCardsWindow()` - Process special card powers

### 4. GameStateStore

The persistent state storage that maintains game state per room.

**Location**: `backend_core/services/game_state_store.dart`

**Responsibilities**:
- Store and retrieve game state per room ID
- Provide state access to game logic
- Maintain state consistency

**Key Methods**:
```dart
void setGameState(String roomId, Map<String, dynamic> gameState)
Map<String, dynamic> getGameState(String roomId)
void clear(String roomId)
```

### 5. GameStateCallback

Interface for game logic to communicate state changes back to the transport layer.

**Location**: `backend_core/shared_logic/game_state_callback.dart`

**Responsibilities**:
- Define callback interface for state updates
- Allow game logic to broadcast state changes
- Support both practice and multiplayer transport layers

**Key Methods**:
```dart
void onGameStateChanged(Map<String, dynamic> updates)
void onPlayerStatusChanged(String status, {String? playerId, ...})
void onActionError(String message, {Map<String, dynamic>? data})
```

## Bridging Systems

The bridging systems connect the unified backend core to the mode-specific transport layers. Each mode has its own bridge that translates between the transport mechanism (practice mode local calls vs. multiplayer WebSocket) and the unified backend interface.

---

## Practice Mode Bridge

### Overview

The Practice Mode Bridge connects Flutter's practice mode UI to the unified backend core using **direct method calls** instead of WebSocket communication. It creates a local game instance and routes events synchronously.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Flutter Practice Mode UI                        │
│  (PlayerAction → ValidatedEventEmitter)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         PracticeModeBridge (Singleton)                       │
│  ┌────────────────────────────────────────────────────┐    │
│  │  - Creates local game instance                     │    │
│  │  - Routes events to backend coordinator            │    │
│  │  - Converts backend broadcasts to event manager    │    │
│  └──────────────────────┬─────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Unified Backend Core (SSOT)                         │
│  (GameEventCoordinator → GameRegistry → RecallGameRound)    │
└─────────────────────────────────────────────────────────────┘
```

### Implementation

**Location**: `flutter_base_05/lib/modules/recall_game/practice/practice_mode_bridge.dart`

#### Initialization

The bridge initializes with stubs that mimic the WebSocket server interface:

```dart
class PracticeModeBridge {
  static PracticeModeBridge? _instance;
  static PracticeModeBridge get instance {
    _instance ??= PracticeModeBridge._internal();
    return _instance!;
  }

  final RoomManagerStub _roomManager = RoomManagerStub();
  late final WebSocketServerStub _server;
  late final RecallGameModule _gameModule;
  final GameRegistry _registry = GameRegistry.instance;
  final GameStateStore _store = GameStateStore.instance;
  final RecallEventManager _eventManager = RecallEventManager();

  Future<void> initialize() async {
    // Create WebSocket server stub with callbacks
    _server = WebSocketServerStub(
      roomManager: _roomManager,
      onSendToSession: _handleSendToSession,      // Routes to event manager
      onBroadcastToRoom: _handleBroadcastToRoom,  // Routes to event manager
      onTriggerHook: (hookName, {data, context}) {
        _hooksManager.triggerHook(hookName, data: data, context: context);
      },
    );

    // Initialize game module with stubs
    _gameModule = RecallGameModule(_server, _roomManager, _hooksManager);
  }
}
```

#### Event Routing

Events from the UI are routed directly to the backend coordinator:

```dart
Future<void> handleEvent(String event, Map<String, dynamic> data) async {
  if (!_initialized) {
    await initialize();
  }

  // Ensure we have a session/room context
  if (_currentSessionId == null || _currentRoomId == null) {
    _logger.warning('No active session/room for event $event');
    return;
  }

  try {
    // Route event directly to coordinator
    await _gameModule.coordinator.handle(_currentSessionId!, event, data);
  } catch (e) {
    _logger.error('Error handling event $event: $e');
  }
}
```

#### State Broadcast Handling

When the backend broadcasts state updates, the bridge routes them to the Flutter event manager:

```dart
void _handleSendToSession(String sessionId, Map<String, dynamic> message) {
  final event = message['event'] as String?;
  if (event == null) return;

  // Route to appropriate event manager handler
  switch (event) {
    case 'game_state_updated':
      _eventManager.handleGameStateUpdated(message);
      break;
    case 'player_status_updated':
      _eventManager.handlePlayerStateUpdated(message);
      break;
    // ... other events
  }
}

void _handleBroadcastToRoom(String roomId, Map<String, dynamic> message) {
  // Same as sendToSession for practice mode (single player)
  _handleSendToSession(_currentSessionId ?? 'practice_session', message);
}
```

#### Session Management

The bridge manages practice sessions:

```dart
Future<String> startPracticeSession({
  required String userId,
  required String displayName,
}) async {
  // Generate practice room and session IDs
  _currentRoomId = 'practice_room_${DateTime.now().millisecondsSinceEpoch}';
  _currentSessionId = 'practice_session_${DateTime.now().millisecondsSinceEpoch}';
  _currentUserId = userId;

  // Create room in stub room manager
  _roomManager.createRoom(
    _currentRoomId!,
    ownerId: userId,
    metadata: {
      'isPracticeRoom': true,
      'displayName': displayName,
    },
  );

  // Join session to room
  _roomManager.joinRoom(_currentSessionId!, _currentRoomId!, userId);

  // Initialize game module (creates coordinator)
  await initialize();

  // Start game session via coordinator
  await _gameModule.coordinator.handle(
    _currentSessionId!,
    'create_room',
    {
      'room_id': _currentRoomId!,
      'user_id': userId,
      'display_name': displayName,
    },
  );

  return _currentRoomId!;
}
```

### Key Features

1. **Direct Method Calls**: No network overhead, synchronous execution
2. **Stub-Based Architecture**: Uses stubs (`WebSocketServerStub`, `RoomManagerStub`) to mimic WebSocket interface
3. **Event Manager Integration**: Routes backend broadcasts to Flutter's `RecallEventManager`
4. **State Synchronization**: Maintains same state structure as multiplayer mode

### Event Flow Example: Playing a Card

```
1. UI: Player clicks card → PlayerAction.playCard()
2. PlayerAction: Creates event → ValidatedEventEmitter.emit('play_card', data)
3. ValidatedEventEmitter: Detects practice mode → PracticeModeBridge.handleEvent()
4. PracticeModeBridge: Routes to coordinator → _gameModule.coordinator.handle()
5. GameEventCoordinator: Routes to game round → round.handlePlayCard()
6. RecallGameRound: Processes play → Updates state → Calls GameStateCallback
7. GameStateCallback: Broadcasts update → server.broadcastToRoom()
8. WebSocketServerStub: Routes to bridge → _handleBroadcastToRoom()
9. PracticeModeBridge: Routes to event manager → _eventManager.handleGameStateUpdated()
10. RecallEventManager: Updates StateManager → Widget slices recompute → UI updates
```

---

## Multiplayer Mode Bridge

### Overview

The Multiplayer Mode Bridge connects Flutter's multiplayer UI to the unified backend core via **WebSocket communication** with a remote server. Events are sent over the network and state updates are received asynchronously.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Flutter Multiplayer UI                          │
│  (PlayerAction → ValidatedEventEmitter)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         WebSocketManager                                     │
│  - Sends events via Socket.IO                               │
│  - Receives broadcasts from server                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ WebSocket Protocol
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Python Backend Server                                │
│  ┌────────────────────────────────────────────────────┐    │
│  │  WSEventListeners                                  │    │
│  │  - Receives Socket.IO events                      │    │
│  │  - Routes to event handlers                       │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼─────────────────────────────┐    │
│  │  WSEventHandlers                                    │    │
│  │  - Validates events                                │    │
│  │  - Routes to game coordinator                      │    │
│  └──────────────────────┬─────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼─────────────────────────────┐    │
│  │  RecallGameModule (Python)                         │    │
│  │  - Wraps Dart backend via FFI or subprocess        │    │
│  │  - Routes to Dart backend coordinator              │    │
│  └──────────────────────┬─────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ (If using Dart backend)
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Dart Backend Server                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │  MessageHandler                                    │    │
│  │  - Receives WebSocket messages                    │    │
│  │  - Routes to game coordinator                     │    │
│  └──────────────────────┬─────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         Unified Backend Core (SSOT)                         │
│  (GameEventCoordinator → GameRegistry → RecallGameRound)    │
└─────────────────────────────────────────────────────────────┘
```

### Implementation

#### Flutter Side: Event Emission

**Location**: `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`

Events are validated and sent via WebSocket:

```dart
class ValidatedEventEmitter {
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final PracticeModeBridge _practiceBridge = PracticeModeBridge.instance;
  EventTransportMode _transportMode = EventTransportMode.websocket;

  Future<Map<String, dynamic>> emit({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    // Validate event type and fields
    final validatedData = _validateAndParseEventData(eventType, data);
    
    // Add minimal required context
    final eventPayload = {
      'event_type': eventType,
      'session_id': _getSessionId(),
      'timestamp': DateTime.now().toIso8601String(),
      ...validatedData,
    };

    // Route based on transport mode
    if (_transportMode == EventTransportMode.practice) {
      // Route to practice bridge
      await _practiceBridge.handleEvent(eventType, eventPayload);
      return {'success': true, 'mode': 'practice'};
    } else {
      // Send via WebSocket (default)
      return await _wsManager.sendCustomEvent(eventType, eventPayload);
    }
  }
}
```

#### Flutter Side: Event Reception

**Location**: `flutter_base_05/lib/modules/recall_game/managers/recall_event_listener_validator.dart`

WebSocket events are received and routed to the event manager:

```dart
class RecallEventListenerValidator {
  void _registerListenerNow() {
    final wsManager = WebSocketManager.instance;
    
    if (wsManager.eventListener != null) {
      // Register listeners for all configured events
      final eventNames = _eventConfigs.keys.toList();
      
      for (final eventName in eventNames) {
        wsManager.eventListener!.registerCustomListener(eventName, (data) {
          _handleDirectEvent(eventName, data);
        });
      }
    }
  }
  
  void _handleDirectEvent(String eventType, Map<String, dynamic> data) {
    // Validate event data against schema
    final validatedData = _validateEventData(eventType, data);
    if (validatedData == null) {
      return;
    }

    // Add minimal required context
    final eventPayload = {
      'event_type': eventType,
      'timestamp': DateTime.now().toIso8601String(),
      ...validatedData,
    };

    // Route directly to RecallEventManager
    _routeEventToManager(eventType, eventPayload);
  }
}
```

#### Server Side: Event Handling

**Location**: `dart_bkend_base_01/lib/server/message_handler.dart` (Dart backend)

WebSocket messages are received and routed to the coordinator:

```dart
class MessageHandler {
  final GameEventCoordinator _coordinator;
  final RoomManager _roomManager;

  void handleMessage(String sessionId, Map<String, dynamic> message) {
    final event = message['event_type'] as String?;
    if (event == null) return;

    // Route to coordinator
    _coordinator.handle(sessionId, event, message);
  }
}
```

**Location**: `python_base_04/core/managers/websockets/ws_event_listeners.py` (Python backend)

Socket.IO events are received and routed:

```python
class WSEventListeners:
    def register_all_listeners(self):
        # Catch-all handler for all events
        @self.socketio.on('*')
        def catch_all(event, data=None):
            # Route to event handlers
            return self.event_handlers.handle_unified_event(event, event, data or {})
```

### Key Features

1. **Asynchronous Communication**: Events sent/received over network
2. **Real-time Updates**: State changes broadcast to all connected clients
3. **Session Management**: Server tracks sessions and room membership
4. **Multi-client Synchronization**: All players see same game state

### Event Flow Example: Playing a Card

```
1. UI: Player clicks card → PlayerAction.playCard()
2. PlayerAction: Creates event → ValidatedEventEmitter.emit('play_card', data)
3. ValidatedEventEmitter: Detects multiplayer mode → WebSocketManager.sendCustomEvent()
4. WebSocketManager: Sends via Socket.IO → Server receives event
5. Server: Routes to coordinator → coordinator.handle(sessionId, 'play_card', data)
6. GameEventCoordinator: Routes to game round → round.handlePlayCard()
7. RecallGameRound: Processes play → Updates state → Calls GameStateCallback
8. GameStateCallback: Broadcasts update → server.broadcastToRoom()
9. Server: Sends to all clients → WebSocketManager receives broadcast
10. RecallEventListenerValidator: Routes to event manager → handleGameStateUpdated()
11. RecallEventManager: Updates StateManager → Widget slices recompute → UI updates
```

---

## State Management

### State Flow

Both modes use the same state management pattern:

1. **Backend Core** updates `GameStateStore` (SSOT)
2. **GameStateCallback** broadcasts state changes
3. **Bridge** routes broadcasts to Flutter event manager
4. **RecallEventManager** updates `StateManager`
5. **Widget Slices** recompute from state
6. **UI** rebuilds with new state

### State Structure

The game state follows a consistent structure:

```dart
{
  'game_state': {
    'players': [...],           // List of player objects
    'currentPlayer': {...},     // Current player object
    'drawPile': [...],          // Draw pile cards
    'discardPile': [...],       // Discard pile cards
    'phase': 'playing',         // Game phase
    'turn_events': [...],       // Turn events for animations
    // ... other game state fields
  },
  'game_id': 'room_xxx',
  'owner_id': 'user_xxx',
  'timestamp': '...',
}
```

### Widget Slices

UI widgets subscribe to computed "slices" of the game state:

- `myHand` - Current player's hand state
- `opponentsPanel` - Opponents' information
- `centerBoard` - Draw/discard piles and game info
- `gameInfo` - General game information

These slices are computed from the SSOT state in `recall_game_state_updater.dart`.

---

## Benefits of Unified Architecture

1. **Consistency**: Both modes use identical game logic, ensuring consistent behavior
2. **Maintainability**: Bug fixes and features only need to be implemented once
3. **Testability**: Practice mode can be used to test game logic without network overhead
4. **Code Reuse**: No duplication of game logic between modes
5. **Reliability**: Same battle-tested code path for both modes

---

## Key Differences Between Modes

| Aspect | Practice Mode | Multiplayer Mode |
|--------|--------------|------------------|
| **Transport** | Direct method calls | WebSocket (Socket.IO) |
| **Latency** | Synchronous, instant | Asynchronous, network-dependent |
| **State Updates** | Immediate, local | Broadcast to all clients |
| **Session Management** | Local stubs | Server-managed sessions |
| **Network** | None | Required |
| **Players** | 1 human + CPUs | Multiple humans + CPUs |

Despite these differences, both modes share the **exact same backend core logic**, ensuring consistent game behavior regardless of transport mechanism.

---

## Adding a New Player Action

When adding a new player action to the game, you need to update several components. The good news is that **the bridges themselves are generic** and don't need changes - they automatically route any event. However, you do need to update:

### Required Updates

#### 1. Unified Backend Core (SSOT) - **REQUIRED**

**Location**: `backend_core/shared_logic/recall_game_round.dart`

Add the handler method that implements the game logic:

```dart
Future<bool> handleNewAction(String param1, {String? playerId, Map<String, dynamic>? gamesMap}) async {
  // Implement game logic here
  // Update game state
  // Call GameStateCallback to broadcast updates
}
```

**Location**: `backend_core/coordinator/game_event_coordinator.dart`

Add a case in the `handle()` method to route the event:

```dart
case 'new_action':
  final param1 = data['param1'] as String?;
  if (param1 != null) {
    final gamesMap = _getCurrentGamesMap(roomId);
    final playerId = _getPlayerIdFromSession(sessionId, roomId);
    await round.handleNewAction(param1, playerId: playerId, gamesMap: gamesMap);
  }
  break;
```

**Note**: Update this in **both** locations:
- `flutter_base_05/lib/modules/recall_game/backend_core/`
- `dart_bkend_base_01/lib/modules/recall_game/backend_core/`

#### 2. Event Validation - **REQUIRED**

**Location**: `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`

Add validation rules for the new event:

```dart
// In _allowedEventFields map
'new_action': {
  'game_id', 'param1', 'param2'  // Define allowed fields
},

// In _fieldValidation map (if field needs validation)
'param1': RecallEventFieldSpec(
  type: String,
  required: true,
  description: 'Description of param1',
),
```

If the action needs `player_id` auto-injection, add it to `eventsNeedingPlayerId`:

```dart
final eventsNeedingPlayerId = {
  'play_card', 'draw_card', 'new_action', // Add here
  // ... other events
};
```

#### 3. Player Action Factory (Flutter UI) - **REQUIRED**

**Location**: `flutter_base_05/lib/modules/recall_game/managers/player_action.dart`

Add a factory method for the new action:

```dart
// In PlayerActionType enum
newAction,

// Add factory method
static PlayerAction newAction({
  required String gameId,
  required String param1,
}) {
  return PlayerAction._(
    actionType: PlayerActionType.newAction,
    eventName: 'new_action',
    payload: {
      'game_id': gameId,
      'param1': param1,
    },
  );
}
```

#### 4. Server-to-Client Events (If Applicable) - **OPTIONAL**

If your new action triggers a new server-to-client event (not just `game_state_updated`), you need to:

**Location**: `flutter_base_05/lib/modules/recall_game/managers/recall_event_listener_validator.dart`

Add event configuration:

```dart
// In _eventConfigs map
'new_action_result': EventConfig(
  schema: {'game_id', 'result', 'timestamp'},
  handlerMethod: 'handleNewActionResult',
),
```

**Location**: `flutter_base_05/lib/modules/recall_game/managers/recall_event_manager.dart`

Add handler method:

```dart
void handleNewActionResult(Map<String, dynamic> data) {
  RecallEventHandlerCallbacks.handleNewActionResult(data);
}
```

**Location**: `flutter_base_05/lib/modules/recall_game/managers/recall_event_handler_callbacks.dart`

Add callback implementation:

```dart
static void handleNewActionResult(Map<String, dynamic> data) {
  // Process the event and update state
}
```

### What You DON'T Need to Update

✅ **PracticeModeBridge** - Generic, automatically routes any event  
✅ **WebSocketManager** - Generic, sends any event over WebSocket  
✅ **MessageHandler** (server) - Generic, routes any event to coordinator  
✅ **Event routing logic** - All generic and event-agnostic

### Summary

For a **client-to-server action** (player initiates):
1. ✅ Unified backend core (handler + coordinator routing)
2. ✅ Event validation (field specs)
3. ✅ PlayerAction factory method

For a **server-to-client event** (new broadcast type):
4. ✅ Event listener config
5. ✅ Event manager handler
6. ✅ Event handler callback

The bridges are **completely generic** and will automatically handle any new event without modification.

---

## File Locations

### Unified Backend Core (SSOT)
- `flutter_base_05/lib/modules/recall_game/backend_core/`
- `dart_bkend_base_01/lib/modules/recall_game/backend_core/`

### Practice Mode Bridge
- `flutter_base_05/lib/modules/recall_game/practice/practice_mode_bridge.dart`
- `flutter_base_05/lib/modules/recall_game/utils/platform/practice/stubs/`

### Multiplayer Mode Bridge
- `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`
- `flutter_base_05/lib/modules/recall_game/managers/recall_event_listener_validator.dart`
- `dart_bkend_base_01/lib/server/message_handler.dart`
- `python_base_04/core/managers/websockets/`

### State Management
- `flutter_base_05/lib/modules/recall_game/managers/recall_game_state_updater.dart`
- `flutter_base_05/lib/modules/recall_game/managers/recall_event_handler_callbacks.dart`

