# Draw Action Flow - Complete Trace

This document traces the complete flow of a draw action for human players, from screen tap to final widget updates.

## Overview

The draw action flow spans multiple layers:
1. **Flutter UI Layer** - Screen tap and widget interaction
2. **Action Layer** - PlayerAction creation and execution
3. **Event Layer** - WebSocket event emission
4. **Backend Layer** - Dart backend processing (ClecoGameRound)
5. **State Update Layer** - State management and widget slice computation
6. **Widget Rebuild Layer** - UI updates and final rendering

---

## 1. Screen Tap (Flutter UI)

**File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/draw_pile_widget.dart`

### 1.1 User Interaction
- User taps on the draw pile card widget
- `CardWidget`'s `onTap` callback triggers `_handlePileClick()`

### 1.2 Validation Check
```dart
// Line 198-206
void _handlePileClick() async {
  final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
  final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
  final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
  
  // Check if current player can interact with draw pile (drawing_card status only)
  if (currentPlayerStatus == 'drawing_card') {
    // Proceed with draw action
  }
}
```

**Key Points**:
- Reads state from `StateManager` (module: `cleco_game`)
- Gets `playerStatus` from `centerBoard` slice (computed from SSOT)
- Only allows draw when status is `'drawing_card'`

### 1.3 Action Creation
```dart
// Line 222-226
final drawAction = PlayerAction.playerDraw(
  pileType: 'draw_pile',
  gameId: currentGameId,
);
await drawAction.execute();
```

**Key Points**:
- Creates `PlayerAction` with `pileType: 'draw_pile'` and `gameId`
- `playerId` is NOT provided - it's auto-added by event emitter
- Executes the action asynchronously

---

## 2. PlayerAction Execution

**File**: `flutter_base_05/lib/modules/cleco_game/managers/player_action.dart`

### 2.1 Action Factory Method
```dart
// Line 157-184
static PlayerAction playerDraw({
  required String pileType, // 'draw_pile' or 'discard_pile'
  required String gameId,
}) {
  // Convert frontend pile type to backend source value
  String source;
  switch (pileType) {
    case 'draw_pile':
      source = 'deck';
      break;
    case 'discard_pile':
      source = 'discard';
      break;
  }
  
  return PlayerAction._(
    actionType: PlayerActionType.drawCard,
    eventName: 'draw_card',
    payload: {
      'game_id': gameId,
      'source': source, // Backend expects 'deck' or 'discard'
      // player_id will be automatically included by the event emitter
    },
  );
}
```

**Key Points**:
- Converts frontend `'draw_pile'` to backend `'deck'`
- Creates action with `eventName: 'draw_card'`
- Payload includes `game_id` and `source`

### 2.2 Action Execution
```dart
// Line 53-104
Future<void> execute() async {
  try {
    // Note: Removed _setPlayerStatusToWaiting() call
    // Rapid-click prevention is now handled by local widget state
    // This prevents the frontend from overriding backend status updates
    
    // Use event emitter for both practice and multiplayer games
    await _eventEmitter.emit(
      eventType: eventName,
      data: payload,
    );
  } catch (e) {
    _logger.error('Error executing action ${actionType.name}: $e');
    rethrow;
  }
}
```

**Key Points**:
- No optimistic status update (backend controls status)
- Uses `ClecoGameEventEmitter` to send event
- Event type: `'draw_card'`, data: `{'game_id': ..., 'source': 'deck'}`

---

## 3. Event Emission (WebSocket)

**File**: `flutter_base_05/lib/modules/cleco_game/managers/validated_event_emitter.dart`

### 3.1 Event Validation
```dart
// Line 236-281
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
  
  // Auto-include sessionId as player_id for events that need it
  final eventsNeedingPlayerId = {
    'play_card', 'draw_card', 'play_out_of_turn', ...
  };
  
  if (eventsNeedingPlayerId.contains(eventType)) {
    final sessionId = _getSessionId();
    if (sessionId.isNotEmpty && sessionId != 'unknown_session') {
      eventPayload['player_id'] = sessionId; // Use sessionId as player_id
    }
  }
  
  // Route based on transport mode
  if (_transportMode == EventTransportMode.practice) {
    await _practiceBridge.handleEvent(eventType, eventPayload);
  } else {
    return await _wsManager.sendCustomEvent(eventType, eventPayload);
  }
}
```

**Key Points**:
- Validates event fields against schema
- Auto-adds `player_id` from `sessionId` (WebSocket session ID)
- Routes to WebSocket manager (multiplayer) or practice bridge (practice mode)
- Final payload: `{'event_type': 'draw_card', 'session_id': '...', 'player_id': '...', 'game_id': '...', 'source': 'deck', 'timestamp': '...'}`

### 3.2 WebSocket Transmission
**File**: `flutter_base_05/lib/core/managers/websockets/websocket_manager.dart`

- WebSocket manager sends event to Dart backend server
- Event format: `{'event': 'draw_card', 'data': {...}}`

---

## 4. Backend Event Reception

**File**: `flutter_base_05/lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart`

### 4.1 Event Handler
```dart
// Line 70-99
Future<void> handle(String sessionId, String event, Map<String, dynamic> data) async {
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
      case 'draw_card':
        final gamesMap = _getCurrentGamesMap(roomId);
        final playerId = _getPlayerIdFromSession(sessionId, roomId);
        await round.handleDrawCard(
          (data['source'] as String?) ?? 'deck',
          playerId: playerId,
          gamesMap: gamesMap,
        );
        break;
    }
  } catch (e) {
    _logger.error('GameEventCoordinator: error on $event -> $e');
    server.sendToSession(sessionId, {
      'event': '${event}_error',
      'room_id': roomId,
      'message': e.toString(),
    });
  }
}
```

**Key Points**:
- Gets `roomId` from session mapping
- Gets `playerId` from session (player ID = session ID)
- Gets current games map from state store
- Calls `round.handleDrawCard()` with `source`, `playerId`, and `gamesMap`

---

## 5. Backend Draw Card Processing

**File**: `flutter_base_05/lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart`

### 5.1 Draw Card Handler
```dart
// Line 923-1179
Future<bool> handleDrawCard(String source, {String? playerId, Map<String, dynamic>? gamesMap}) async {
  // Validate source
  if (source != 'deck' && source != 'discard') {
    return false;
  }
  
  // Use provided gamesMap if available (avoids stale state)
  final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
  final gameData = currentGames[_gameId];
  final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
  final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
  
  // Get player ID
  String? actualPlayerId = playerId;
  if (actualPlayerId == null || actualPlayerId.isEmpty) {
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    actualPlayerId = currentPlayer['id']?.toString() ?? '';
  }
  
  // Draw card based on source
  Map<String, dynamic>? drawnCard;
  
  if (source == 'deck') {
    final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
    final idOnlyCard = drawPile.removeLast(); // Remove last card (top of pile)
    
    // Convert ID-only card to full card data
    drawnCard = _stateCallback.getCardById(gameState, idOnlyCard['cardId']);
  } else if (source == 'discard') {
    final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
    drawnCard = discardPile.removeLast(); // Remove last card (top of pile)
  }
  
  // Get player and hand
  final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
  final playerIndex = players.indexWhere((p) => p['id'] == actualPlayerId);
  final player = players[playerIndex];
  final hand = player['hand'] as List<dynamic>? ?? [];
  
  // Add card to player's hand as ID-only (player hands always store ID-only cards)
  final idOnlyCard = {
    'cardId': drawnCard['cardId'],
    'suit': '?',
    'rank': '?',
    'points': 0,
  };
  
  // IMPORTANT: Drawn cards ALWAYS go to the end of the hand (not in blank slots)
  hand.add(idOnlyCard);
  
  // TWO-STEP APPROACH: First broadcast ID-only drawnCard to all players,
  // then send full card details only to the drawing player
  
  final isHuman = player['isHuman'] as bool? ?? false;
  
  // STEP 1: Set drawnCard to ID-only for ALL players (including human) for initial broadcast
  final idOnlyDrawnCard = {
    'cardId': drawnCard['cardId'],
    'suit': '?',
    'rank': '?',
    'points': 0,
  };
  player['drawnCard'] = idOnlyDrawnCard;
  
  // For computer players, also add to known_cards (they need full data for logic)
  if (!isHuman) {
    // Add to known_cards...
  }
  
  // Add turn event for draw action
  final drawnCardId = drawnCard['cardId']?.toString() ?? '';
  final currentTurnEvents = _getCurrentTurnEvents();
  final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
    ..add(_createTurnEvent(drawnCardId, 'draw'));
  
  // STEP 1: Broadcast ID-only drawnCard to all players EXCEPT the drawing player
  if (source == 'discard') {
    final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
    _stateCallback.broadcastGameStateExcept(actualPlayerId, {
      'games': currentGames, // Games map with ID-only drawnCard
      'discardPile': updatedDiscardPile, // Updated discard pile (card removed)
      'turn_events': turnEvents, // Add turn event for animation
    });
  } else {
    // Drawing from deck - only update games (discard pile unchanged)
    _stateCallback.broadcastGameStateExcept(actualPlayerId, {
      'games': currentGames, // Games map with ID-only drawnCard
      'turn_events': turnEvents, // Add turn event for animation
    });
  }
  
  // Cancel draw timer (draw action completed)
  _drawActionTimer?.cancel();
  _drawActionTimer = null;
  
  // STEP 2: If human player, send full card details ONLY to the drawing player
  if (isHuman) {
    // Update player's drawnCard with full card data and status
    player['drawnCard'] = drawnCard; // Full card data for human player
    player['status'] = 'playing_card'; // Update status to playing_card
    
    // Send full card details only to the drawing player
    _stateCallback.sendGameStateToPlayer(actualPlayerId, {
      'games': currentGames, // Games map with full drawnCard and updated status
      'turn_events': turnEvents, // Include turn events
    });
  } else {
    // For computer players, update status in games map
    _updatePlayerStatusInGamesMap('playing_card', playerId: actualPlayerId);
  }
  
  // Start play timer for ALL players (human and CPU) if status is playing_card
  _startPlayActionTimer(actualPlayerId);
  
  return true;
}
```

**Key Points**:
- Validates source (`'deck'` or `'discard'`)
- Uses provided `gamesMap` to avoid stale state
- Draws card from appropriate pile (removes last card)
- Converts ID-only card to full card data (for deck draws)
- Adds card to player's hand as ID-only (at end of hand)
- **Two-step broadcast**:
  1. Broadcast ID-only `drawnCard` to all players EXCEPT drawing player
  2. Send full `drawnCard` details ONLY to drawing player (if human)
- Updates player status to `'playing_card'`
- Adds turn event for animation
- Cancels draw timer, starts play timer

---

## 6. State Callback Execution

**File**: `flutter_base_05/lib/modules/cleco_game/backend_core/services/game_registry.dart`

### 6.1 Broadcast Game State Except
```dart
// Line 138-202
void broadcastGameStateExcept(String excludePlayerId, Map<String, dynamic> updates) {
  // Validate and apply updates to state store
  _store.mergeRoot(_gameId, updates);
  
  // Get all sessions in the room
  final sessions = _roomManager.getSessionsInRoom(_gameId);
  
  // Filter out the excluded player
  final targetSessions = sessions.where((sessionId) => sessionId != excludePlayerId).toList();
  
  // Send game_state_updated event to each target session
  for (final sessionId in targetSessions) {
    _server.sendToSession(sessionId, {
      'event': 'game_state_updated',
      'game_id': _gameId,
      'game_state': gameState,
      'owner_id': _server.getRoomOwner(_gameId),
      'turn_events': turnEvents,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

### 6.2 Send Game State To Player
```dart
// Line 204-232
void sendGameStateToPlayer(String playerId, Map<String, dynamic> updates) {
  // Validate and apply updates to state store
  _store.mergeRoot(_gameId, updates);
  
  // Get session for player (player ID = session ID)
  final sessionId = playerId;
  
  // Send game_state_updated event to the player
  _server.sendToSession(sessionId, {
    'event': 'game_state_updated',
    'game_id': _gameId,
    'game_state': gameState,
    'owner_id': _server.getRoomOwner(_gameId),
    'turn_events': turnEvents,
    'timestamp': DateTime.now().toIso8601String(),
  });
}
```

**Key Points**:
- Updates state store with new game state
- Sends `game_state_updated` WebSocket event to target sessions
- Event includes `game_state`, `turn_events`, `owner_id`, etc.

---

## 7. Frontend Event Reception

**File**: `flutter_base_05/lib/modules/cleco_game/managers/cleco_event_handler_callbacks.dart`

### 7.1 Game State Updated Handler
```dart
// Line 828-1017
static void handleGameStateUpdated(Map<String, dynamic> data) {
  final gameId = data['game_id']?.toString() ?? '';
  final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
  final ownerId = data['owner_id']?.toString();
  final turnEvents = data['turn_events'] as List<dynamic>? ?? [];
  
  // Extract pile information from game state
  final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
  final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
  final drawPileCount = drawPile.length;
  final discardPileCount = discardPile.length;
  
  // Extract players list
  final players = gameState['players'] as List<dynamic>? ?? [];
  
  // Check if game exists in games map, if not add it
  final currentGames = _getCurrentGamesMap();
  final wasNewGame = !currentGames.containsKey(gameId);
  
  if (wasNewGame) {
    _addGameToMap(gameId, {...});
  }
  
  // Sync widget states with game state
  // Update games map with widget-specific data
  _syncWidgetStatesWithGameState(gameId, gameState, players);
  
  // Update main state with games map, discardPile, currentPlayer, turn_events
  _updateMainGameState({
    'currentGameId': gameId,
    'games': currentGamesAfterSync, // Updated games map with widget data synced
    'gamePhase': uiPhase,
    'isGameActive': uiPhase != 'game_ended',
    'roundNumber': roundNumber,
    'currentPlayer': currentPlayerFromState ?? currentPlayer,
    'currentPlayerStatus': currentPlayerStatus,
    'roundStatus': roundStatus,
    'discardPile': discardPile, // Updated discard pile for centerBoard slice
    'turn_events': turnEvents, // Include turn_events for animations
  });
}
```

**Key Points**:
- Extracts `game_state`, `turn_events`, `owner_id` from event
- Updates games map with new game state
- Syncs widget states with game state
- Updates main state via `_updateMainGameState()` which calls `ClecoGameHelpers.updateUIState()`

---

## 8. State Update Processing

**File**: `flutter_base_05/lib/modules/cleco_game/managers/cleco_game_state_updater.dart`

### 8.1 State Update Entry Point
```dart
// Line 76-86
void updateState(Map<String, dynamic> updates) {
  try {
    // Use StateQueueValidator to validate and queue the update
    // The validator will call our update handler with validated updates
    _validator.enqueueUpdate(updates);
  } catch (e) {
    _logger.error('ClecoGameStateUpdater: State update failed: $e');
    rethrow;
  }
}
```

### 8.2 Validated Update Application
```dart
// Line 150-241
void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
  // Get current state
  final currentState = _stateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
  
  // Check if there are actual changes (excluding lastUpdated)
  bool hasActualChanges = false;
  for (final key in validatedUpdates.keys) {
    if (key == 'lastUpdated') continue;
    // Compare current vs new values...
    if (currentValue != newValue) {
      hasActualChanges = true;
      break;
    }
  }
  
  if (!hasActualChanges) {
    return; // Skip update if no changes
  }
  
  // Apply only the validated updates
  final newState = {
    ...currentState,
    ...validatedUpdates,
  };
  
  // Rebuild dependent widget slices only if relevant fields changed
  final updatedStateWithSlices = _updateWidgetSlices(
    currentState,
    newState,
    validatedUpdates.keys.toSet(),
  );
  
  // Update StateManager
  _stateManager.updateModuleState('cleco_game', updatedStateWithSlices);
}
```

**Key Points**:
- Validates updates via `StateQueueValidator`
- Checks for actual changes (skips if no changes)
- Merges updates with current state
- Recomputes widget slices based on changed fields
- Updates `StateManager` with final state

### 8.3 Widget Slice Computation
```dart
// Line 243-306
Map<String, dynamic> _updateWidgetSlices(
  Map<String, dynamic> oldState,
  Map<String, dynamic> newState,
  Set<String> changedFields,
) {
  final updatedState = Map<String, dynamic>.from(newState);
  
  // Only rebuild slices that depend on changed fields
  for (final entry in _widgetDependencies.entries) {
    final sliceName = entry.key;
    final dependencies = entry.value;
    
    if (changedFields.any(dependencies.contains)) {
      switch (sliceName) {
        case 'actionBar':
          updatedState['actionBar'] = _computeActionBarSlice(newState);
          break;
        case 'statusBar':
          updatedState['statusBar'] = _computeStatusBarSlice(newState);
          break;
        case 'myHand':
          updatedState['myHand'] = _computeMyHandSlice(newState);
          break;
        case 'centerBoard':
          updatedState['centerBoard'] = _computeCenterBoardSlice(newState);
          break;
        case 'opponentsPanel':
          updatedState['opponentsPanel'] = _computeOpponentsPanelSlice(newState);
          break;
        case 'gameInfo':
          updatedState['gameInfo'] = _computeGameInfoSlice(newState);
          break;
      }
    }
  }
  
  // Extract currentPlayer from current game data and put it in main state
  final currentGameId = updatedState['currentGameId']?.toString() ?? '';
  final games = updatedState['games'] as Map<String, dynamic>? ?? {};
  final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
  final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
  final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
  final currentPlayer = gameState['currentPlayer'];
  
  if (currentPlayer != null) {
    updatedState['currentPlayer'] = currentPlayer;
  }
  
  return updatedState;
}
```

**Key Points**:
- Only recomputes slices that depend on changed fields
- For draw action, likely updates: `centerBoard`, `myHand`, `opponentsPanel`
- Computes slices from SSOT (games map)

### 8.4 Center Board Slice Computation
```dart
// Line 445-504
Map<String, dynamic> _computeCenterBoardSlice(Map<String, dynamic> state) {
  final currentGameId = state['currentGameId']?.toString() ?? '';
  final games = state['games'] as Map<String, dynamic>? ?? {};
  final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
  final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
  final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
  
  // Get pile information from game state
  final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
  final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
  final drawPileCount = drawPile.length;
  
  // Derive current user status from SSOT
  final playerStatus = _getCurrentUserStatus(state);
  
  return {
    'drawPileCount': drawPileCount,
    'topDiscard': discardPile.isNotEmpty ? discardPile.last : null,
    'topDraw': topDraw,
    'canDrawFromDeck': drawPileCount > 0,
    'canTakeFromDiscard': discardPile.isNotEmpty,
    'playerStatus': playerStatus, // Computed from SSOT
  };
}
```

**Key Points**:
- Reads from SSOT (games map)
- Computes `drawPileCount` from `drawPile` length
- Computes `playerStatus` from current user's player in game state
- Returns slice with pile counts and player status

---

## 9. Widget Rebuild

**File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/draw_pile_widget.dart`

### 9.1 ListenableBuilder Rebuild
```dart
// Line 39-68
@override
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: StateManager(),
    builder: (context, child) {
      final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      
      // Get centerBoard state slice
      final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
      final drawPileCount = centerBoard['drawPileCount'] ?? 0;
      final canDrawFromDeck = centerBoard['canDrawFromDeck'] ?? false;
      final playerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
      
      return _buildDrawPileCard(
        drawPileCount: drawPileCount,
        canDrawFromDeck: canDrawFromDeck,
        playerStatus: playerStatus,
        // ... other params
      );
    },
  );
}
```

**Key Points**:
- `ListenableBuilder` listens to `StateManager()` changes
- When state updates, builder rebuilds
- Reads `centerBoard` slice from state
- Extracts `drawPileCount`, `canDrawFromDeck`, `playerStatus`
- Rebuilds draw pile card widget with new values

### 9.2 Final Widget Rendering
```dart
// Line 70-137
Widget _buildDrawPileCard({
  required int drawPileCount,
  required bool canDrawFromDeck,
  required String playerStatus,
  // ...
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Title
          Row(
            children: [
              Icon(Icons.style, color: Colors.blue),
              Text('Draw'),
            ],
          ),
          
          // Draw pile visual representation (clickable)
          CardWidget(
            card: CardModel(
              cardId: 'draw_pile_${drawPileCount > 0 ? 'full' : 'empty'}',
              rank: '?',
              suit: '?',
              points: 0,
            ),
            config: CardDisplayConfig.forDrawPile(),
            showBack: true, // Always show back for draw pile
            onTap: _handlePileClick,
          ),
        ],
      ),
    ),
  );
}
```

**Key Points**:
- Widget rebuilds with new `drawPileCount`
- Card widget shows back (face-down)
- `onTap` handler remains attached (ready for next draw)

---

## 10. Additional Widget Updates

### 10.1 My Hand Widget
**File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/my_hand_widget.dart`

- Reads `myHand` slice from state
- Displays player's hand cards
- Shows drawn card (if visible to player)
- Updates when `myHand` slice changes

### 10.2 Opponents Panel Widget
**File**: `flutter_base_05/lib/modules/cleco_game/screens/game_play/widgets/opponents_panel_widget.dart`

- Reads `opponentsPanel` slice from state
- Displays opponent players
- Shows drawn card indicator (ID-only for opponents)
- Updates when `opponentsPanel` slice changes

---

## Summary: Complete Flow Diagram

```
1. USER TAP
   └─> DrawPileWidget._handlePileClick()
       └─> Validates playerStatus == 'drawing_card'
           └─> PlayerAction.playerDraw(pileType: 'draw_pile', gameId: ...)
               └─> PlayerAction.execute()
                   └─> ClecoGameEventEmitter.emit(eventType: 'draw_card', data: {...})
                       └─> WebSocketManager.sendCustomEvent()
                           └─> [WebSocket Transmission]

2. BACKEND RECEPTION
   └─> GameEventCoordinator.handle(sessionId, 'draw_card', data)
       └─> Gets roomId, playerId, gamesMap
           └─> ClecoGameRound.handleDrawCard(source: 'deck', playerId: ..., gamesMap: ...)
               └─> Draws card from drawPile
                   └─> Adds card to player's hand (ID-only)
                       └─> Sets player['drawnCard'] = idOnlyDrawnCard
                           └─> Adds turn event
                               └─> STEP 1: broadcastGameStateExcept(playerId, {...})
                                   └─> GameRegistry.broadcastGameStateExcept()
                                       └─> Updates state store
                                           └─> Sends 'game_state_updated' to all except player
                               └─> STEP 2: sendGameStateToPlayer(playerId, {...})
                                   └─> GameRegistry.sendGameStateToPlayer()
                                       └─> Updates state store
                                           └─> Sends 'game_state_updated' to player only

3. FRONTEND EVENT HANDLING
   └─> ClecoEventHandlerCallbacks.handleGameStateUpdated(data)
       └─> Extracts game_state, turn_events, owner_id
           └─> Updates games map
               └─> Syncs widget states
                   └─> _updateMainGameState({games: ..., turn_events: ..., discardPile: ...})
                       └─> ClecoGameHelpers.updateUIState()
                           └─> ClecoGameStateUpdater.updateState()
                               └─> StateQueueValidator.enqueueUpdate()
                                   └─> _applyValidatedUpdates()
                                       └─> Checks for actual changes
                                           └─> Merges with current state
                                               └─> _updateWidgetSlices()
                                                   └─> Recomputes centerBoard, myHand, opponentsPanel slices
                                                       └─> StateManager.updateModuleState('cleco_game', newState)

4. WIDGET REBUILD
   └─> StateManager.notifyListeners()
       └─> ListenableBuilder rebuilds
           └─> DrawPileWidget.build()
               └─> Reads centerBoard slice
                   └─> Extracts drawPileCount, playerStatus
                       └─> Rebuilds CardWidget with new drawPileCount
                           └─> [UI Update Complete]
```

---

## Key Design Patterns

1. **Two-Step Broadcast**: 
   - Step 1: Broadcast ID-only `drawnCard` to all players except drawing player
   - Step 2: Send full `drawnCard` details only to drawing player
   - Prevents other players from seeing card details

2. **SSOT (Single Source of Truth)**:
   - Game state stored in `games[gameId].gameData.game_state`
   - Widget slices computed from SSOT
   - No duplicate state storage

3. **Widget Slice Pattern**:
   - Widgets depend on computed slices (e.g., `centerBoard`, `myHand`)
   - Slices recomputed only when dependencies change
   - Reduces unnecessary rebuilds

4. **State Queue Validation**:
   - All state updates go through `StateQueueValidator`
   - Validates schema and queues updates
   - Prevents invalid state updates

5. **Event-Driven Architecture**:
   - Actions emit events via WebSocket
   - Backend processes events and broadcasts state updates
   - Frontend receives events and updates state
   - Widgets rebuild based on state changes

---

## State Flow Summary

1. **Initial State**: `playerStatus: 'drawing_card'`, `drawPileCount: N`
2. **After Draw Action**: 
   - `drawPileCount: N-1` (card removed from draw pile)
   - `player['drawnCard']: {...}` (ID-only for others, full for player)
   - `player['status']: 'playing_card'` (status updated)
   - `turn_events: [{cardId: '...', actionType: 'draw'}]` (animation event)
3. **Widget Updates**:
   - `centerBoard.drawPileCount` decreases
   - `centerBoard.playerStatus` changes to `'playing_card'`
   - `myHand` shows drawn card (if player)
   - `opponentsPanel` shows drawn card indicator (if opponent)

---

## Critical Points

1. **Player ID = Session ID**: In multiplayer mode, player IDs are WebSocket session IDs
2. **ID-Only Cards**: Player hands store cards as ID-only (`{cardId: '...', suit: '?', rank: '?', points: 0}`)
3. **Full Card Data**: Full card data stored in `originalDeck` for lookup
4. **Drawn Card Property**: `player['drawnCard']` contains the drawn card (ID-only for others, full for player)
5. **Status Transitions**: `drawing_card` → `playing_card` (after draw)
6. **Turn Events**: Used for animations (card draw animation, etc.)
7. **State Store**: Backend maintains state store, frontend receives updates via WebSocket
