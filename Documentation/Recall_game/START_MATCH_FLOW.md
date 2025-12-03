# Start Match Event Flow

This document traces the complete flow of events from when the "Start Match" button is pressed in the game play screen to the backend processing and state updates.

## Overview

The "Start Match" button appears in the `GameInfoWidget` when:
- The game is a practice game (`practice_room_*` ID)
- The game phase is `'waiting'`
- The user is the room owner

## Frontend Flow

### 1. Button Press (`game_info_widget.dart`)

**Location:** `flutter_base_05/lib/modules/recall_game/screens/game_play/widgets/game_info_widget.dart`

**Method:** `_handleStartMatch()`

```dart
void _handleStartMatch() async {
  // Set loading state
  setState(() {
    _isStartingMatch = true;
  });
  
  // Get current game state
  final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
  final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
  
  // Use GameCoordinator for both practice and multiplayer games
  final gameCoordinator = GameCoordinator();
  final result = await gameCoordinator.startMatch();
}
```

**Key Points:**
- Sets local loading state (`_isStartingMatch = true`)
- Gets current game ID from state
- Delegates to `GameCoordinator.startMatch()`

### 2. GameCoordinator (`game_coordinator.dart`)

**Location:** `flutter_base_05/lib/modules/recall_game/managers/game_coordinator.dart`

**Method:** `startMatch()`

```dart
Future<bool> startMatch() async {
  // Get current game state
  final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
  final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
  
  if (currentGameId.isEmpty) {
    return false;
  }
  
  // Create and execute the player action
  final action = PlayerAction.startMatch(
    gameId: currentGameId,
  );
  
  await action.execute();
  return true;
}
```

**Key Points:**
- Retrieves `currentGameId` from state
- Creates a `PlayerAction.startMatch()` instance
- Executes the action

### 3. PlayerAction (`player_action.dart`)

**Location:** `flutter_base_05/lib/modules/recall_game/managers/player_action.dart`

**Static Factory:** `PlayerAction.startMatch()`

```dart
static PlayerAction startMatch({
  required String gameId,
}) {
  return PlayerAction._(
    actionType: PlayerActionType.useSpecialPower, // Generic type
    eventName: 'start_match',
    payload: {
      'game_id': gameId,
    },
  );
}
```

**Execution:** `execute()`

```dart
Future<void> execute() async {
  // Use event emitter for both practice and multiplayer games
  // The event emitter will route to practice bridge if transport mode is practice
  await _eventEmitter.emit(
    eventType: eventName,  // 'start_match'
    data: payload,         // {'game_id': gameId}
  );
}
```

**Key Points:**
- Creates action with `eventName: 'start_match'` and `payload: {'game_id': gameId}`
- Executes via `RecallGameEventEmitter.emit()`

### 4. ValidatedEventEmitter (`validated_event_emitter.dart`)

**Location:** `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart`

**Method:** `emit()`

```dart
Future<Map<String, dynamic>> emit({
  required String eventType,  // 'start_match'
  required Map<String, dynamic> data,  // {'game_id': gameId}
}) async {
  // Validate event type and fields
  final validatedData = _validateAndParseEventData(eventType, data);
  
  // Add minimal required context
  final eventPayload = {
    'event_type': eventType,  // 'start_match'
    'session_id': _getSessionId(),
    'timestamp': DateTime.now().toIso8601String(),
    ...validatedData,  // {'game_id': gameId}
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
```

**Validation:**
- Event type `'start_match'` is allowed
- Required field: `'game_id'` (validated against pattern: `^(room_|practice_room_)[a-zA-Z0-9_]+$`)

**Key Points:**
- Validates event structure and fields
- Adds `session_id` and `timestamp`
- Routes to either:
  - **Practice Mode:** `PracticeModeBridge.handleEvent()` (local processing)
  - **WebSocket Mode:** `WebSocketManager.sendCustomEvent()` (backend via WebSocket)

## Backend Flow (WebSocket Mode)

### 5. WebSocket Server (`websocket_server.dart`)

**Location:** `dart_bkend_base_01/lib/server/websocket_server.dart`

The WebSocket server receives the message and routes it to the message handler.

### 6. Message Handler (`message_handler.dart`)

**Location:** `dart_bkend_base_01/lib/server/message_handler.dart`

**Method:** `handleMessage()`

```dart
void handleMessage(String sessionId, Map<String, dynamic> message) {
  final event = message['event_type'] as String? ?? message['event'] as String?;
  final data = message;
  
  switch (event) {
    // ... other cases ...
    case 'start_match':
      _handleGameEvent(sessionId, event, data);
      break;
  }
}
```

**Key Points:**
- Extracts `event_type` from message
- Routes `'start_match'` to `_handleGameEvent()`

### 7. Game Event Handler (`message_handler.dart`)

**Method:** `_handleGameEvent()`

```dart
void _handleGameEvent(String sessionId, String event, Map<String, dynamic> data) {
  // Get game coordinator
  final gameCoordinator = GameEventCoordinator.instance;
  
  // Delegate to game coordinator
  gameCoordinator.handle(sessionId, event, data);
}
```

**Key Points:**
- Gets `GameEventCoordinator` instance
- Delegates to `gameCoordinator.handle()`

### 8. Game Event Coordinator (`game_event_coordinator.dart`)

**Location:** `dart_bkend_base_01/lib/modules/recall_game/backend_core/coordinator/game_event_coordinator.dart`

**Method:** `handle()`

```dart
Future<void> handle(String sessionId, String event, Map<String, dynamic> data) async {
  // Get room ID for this session
  final roomId = roomManager.getRoomForSession(sessionId);
  if (roomId == null) {
    server.sendToSession(sessionId, {
      'event': 'error',
      'message': 'Not in a room',
    });
    return;
  }

  // Get or create the game round for this room
  final round = _registry.getOrCreate(roomId, server);

  try {
    switch (event) {
      case 'start_match':
        await _handleStartMatch(roomId, round, data);
        break;
      // ... other cases ...
    }
  } catch (e) {
    // Error handling
  }
}
```

**Key Points:**
- Validates session is in a room
- Gets or creates `RecallGameRound` instance
- Routes to `_handleStartMatch()`

### 9. Start Match Handler (`game_event_coordinator.dart`)

**Method:** `_handleStartMatch()`

```dart
Future<void> _handleStartMatch(String roomId, RecallGameRound round, Map<String, dynamic> data) async {
  // 1. Get existing game state
  final stateRoot = _store.getState(roomId);
  final current = Map<String, dynamic>.from(stateRoot['game_state'] as Map<String, dynamic>? ?? {});

  // 2. Get existing players (creator and any joiners already added via hooks)
  final players = List<Map<String, dynamic>>.from(
    (current['players'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(),
  );

  // 3. Determine target player count
  final roomInfo = roomManager.getRoomInfo(roomId);
  final minPlayers = roomInfo?.minPlayers ?? (data['min_players'] as int? ?? 2);
  final maxPlayers = roomInfo?.maxSize ?? (data['max_players'] as int? ?? 4);

  // 4. Auto-create computer players
  final isPracticeMode = roomId.startsWith('practice_room_');
  int needed = isPracticeMode 
      ? maxPlayers - players.length  // Practice mode: fill to maxPlayers
      : minPlayers - players.length; // Multiplayer: only fill to minPlayers
  if (needed < 0) needed = 0;
  
  // Create CPU players with unique names
  while (needed > 0 && players.length < maxPlayers) {
    // ... create CPU player ...
    players.add({
      'id': cpuId,
      'name': name,
      'isHuman': false,
      'status': 'waiting',
      'hand': <Map<String, dynamic>>[],
      // ... other fields ...
    });
    needed--;
  }

  // 5. Build deck and deal 4 cards per player
  final deckFactory = await YamlDeckFactory.fromFile(roomId, configPath);
  final List<Card> fullDeck = deckFactory.buildDeck();
  
  // Deal 4 cards to each player (face-down, ID-only)
  final drawStack = List<Card>.from(fullDeck);
  for (final p in players) {
    final hand = <Map<String, dynamic>>[];
    for (int i = 0; i < 4 && drawStack.isNotEmpty; i++) {
      final c = drawStack.removeAt(0);
      hand.add({
        'cardId': c.cardId,
        'suit': '?',  // Face-down
        'rank': '?',  // Face-down
        'points': 0,  // Face-down
      });
    }
    p['hand'] = hand;
  }

  // 6. Set up discard pile with first card (face-up, full data)
  final discardPile = <Map<String, dynamic>>[];
  if (drawStack.isNotEmpty) {
    final firstCard = drawStack.removeAt(0);
    discardPile.add({
      'cardId': firstCard.cardId,
      'rank': firstCard.rank,
      'suit': firstCard.suit,
      'points': firstCard.points,
      // ... full card data ...
    });
  }

  // 7. Build updated game_state - set to initial_peek phase
  final gameState = <String, dynamic>{
    'gameId': roomId,
    'gameName': 'Recall Game $roomId',
    'players': players,
    'discardPile': discardPile,  // Full data (face-up)
    'drawPile': drawStack.map((c) => _cardToIdOnly(c)).toList(),  // ID-only (face-down)
    'originalDeck': fullDeck.map((c) => _cardToMap(c)).toList(),  // Full data for lookup
    'gameType': 'multiplayer',
    'isGameActive': true,
    'phase': 'initial_peek',  // Set to initial_peek phase
    'playerCount': players.length,
    'maxPlayers': maxPlayers,
    'minPlayers': minPlayers,
  };

  // 8. Set all players to initial_peek status
  for (final player in players) {
    player['status'] = 'initial_peek';
    player['collection_rank_cards'] = <Map<String, dynamic>>[];
    player['known_cards'] = <String, dynamic>{};
  }

  // 9. Save state
  stateRoot['game_state'] = gameState;
  _store.mergeRoot(roomId, stateRoot);

  // 10. Process AI initial peeks (select 2 cards, decide collection rank)
  _processAIInitialPeeks(roomId, gameState);

  // 11. Broadcast game_state_updated event
  server.broadcastToRoom(roomId, {
    'event': 'game_state_updated',
    'game_id': roomId,
    'game_state': gameState,
    'owner_id': server.getRoomOwner(roomId),
    'timestamp': DateTime.now().toIso8601String(),
  });

  // 12. DO NOT call initializeRound() yet - wait for human completed_initial_peek
}
```

**Key Points:**
- Gets existing players (from room creation/join hooks)
- Creates CPU players to fill to `minPlayers` (multiplayer) or `maxPlayers` (practice)
- Builds deck using `YamlDeckFactory` (respects `testing_mode` from config)
- Deals 4 face-down cards to each player
- Sets up discard pile with first card (face-up)
- Sets game phase to `'initial_peek'`
- Processes AI initial peeks (selects 2 cards, decides collection rank)
- Broadcasts `game_state_updated` event to all players in room
- **Does NOT** call `initializeRound()` yet - waits for human player to complete initial peek

## Practice Mode Flow

When `EventTransportMode.practice` is active, the event is routed to `PracticeModeBridge.handleEvent()` instead of WebSocket.

**Location:** `flutter_base_05/lib/modules/recall_game/practice/practice_mode_bridge.dart`

The practice bridge processes the event locally and updates the local game state store, then triggers the same `game_state_updated` event handlers.

## State Updates

### Frontend State Updates

After `game_state_updated` event is received:

1. **RecallEventManager** (`recall_event_manager.dart`)
   - Handles `game_state_updated` event
   - Calls `handleGameStateUpdated()`

2. **Game State Handler** (`recall_event_handler_callbacks.dart`)
   - Updates `games` map in state
   - Updates `gamePhase` to `'initial_peek'`
   - Triggers widget slice recomputation

3. **Widget Updates**
   - `GameInfoWidget` hides (phase is no longer `'waiting'`)
   - `MyHandWidget` shows initial peek interface
   - `OpponentsPanelWidget` shows other players
   - `CenterBoardWidget` shows discard pile

### Backend State Updates

- Game state stored in `GameStateStore`
- Phase set to `'initial_peek'`
- All players set to `'initial_peek'` status
- Cards dealt and stored in player hands
- Discard pile initialized with first card

## Event Sequence Diagram

```
[User] Presses "Start Match" Button
    ↓
[GameInfoWidget] _handleStartMatch()
    ↓
[GameCoordinator] startMatch()
    ↓
[PlayerAction] startMatch().execute()
    ↓
[ValidatedEventEmitter] emit('start_match', {'game_id': ...})
    ↓
    ├─ Practice Mode → [PracticeModeBridge] handleEvent()
    │                      ↓
    │                  [Local Processing]
    │                      ↓
    │                  [game_state_updated event]
    │
    └─ WebSocket Mode → [WebSocketManager] sendCustomEvent()
                           ↓
                       [WebSocket Server] receives message
                           ↓
                       [MessageHandler] handleMessage()
                           ↓
                       [MessageHandler] _handleGameEvent()
                           ↓
                       [GameEventCoordinator] handle()
                           ↓
                       [GameEventCoordinator] _handleStartMatch()
                           ↓
                       [GameStateStore] mergeRoot()
                           ↓
                       [WebSocket Server] broadcastToRoom('game_state_updated')
                           ↓
                       [Frontend] receives 'game_state_updated'
                           ↓
                       [RecallEventManager] handleGameStateUpdated()
                           ↓
                       [StateManager] updateModuleState()
                           ↓
                       [Widgets] rebuild with new state
```

## Key Files

### Frontend
- `flutter_base_05/lib/modules/recall_game/screens/game_play/widgets/game_info_widget.dart` - Start button UI
- `flutter_base_05/lib/modules/recall_game/managers/game_coordinator.dart` - Action coordinator
- `flutter_base_05/lib/modules/recall_game/managers/player_action.dart` - Action factory and execution
- `flutter_base_05/lib/modules/recall_game/managers/validated_event_emitter.dart` - Event validation and routing
- `flutter_base_05/lib/modules/recall_game/practice/practice_mode_bridge.dart` - Practice mode handler

### Backend
- `dart_bkend_base_01/lib/server/message_handler.dart` - Message routing
- `dart_bkend_base_01/lib/modules/recall_game/backend_core/coordinator/game_event_coordinator.dart` - Game event processing
- `dart_bkend_base_01/lib/modules/recall_game/backend_core/shared_logic/recall_game_round.dart` - Game round logic
- `dart_bkend_base_01/lib/modules/recall_game/backend_core/services/game_state_store.dart` - State persistence

## Notes

1. **Practice vs Multiplayer:** The same code path is used for both, with routing determined by `EventTransportMode`.

2. **CPU Player Creation:** 
   - Practice mode: Fills to `maxPlayers`
   - Multiplayer: Only fills to `minPlayers` (waits for real players)

3. **Initial Peek Phase:** After match starts, game enters `'initial_peek'` phase where players select 2 cards to peek at. AI players complete this automatically.

4. **State Broadcasting:** The `game_state_updated` event is broadcast to all players in the room, ensuring all clients stay synchronized.

5. **Round Initialization:** `initializeRound()` is NOT called immediately after `_handleStartMatch()`. It waits for the human player to complete their initial peek via `completed_initial_peek` event.

