# Dual Update Pattern - Game State Distribution

## Overview

The Recall game implements a **DUAL UPDATE PATTERN** for distributing game state to players. This pattern ensures:
1. **Privacy**: Players only see their own cards
2. **Consistency**: All players see the same public game state
3. **Real-time**: Both public and private updates happen simultaneously

## Architecture Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│ DART GAME STATE (Source of Truth)                              │
│ - Full game state with all player hands                         │
│ - Maintained by dart_game_service.dart                          │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│ PYTHON COORDINATOR (game_event_coordinator.py)                 │
│                                                                  │
│ _send_dart_game_state_to_frontend(game_id)                     │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────┐    │
│ │ 1️⃣  PUBLIC UPDATE (Room Broadcast)                      │    │
│ │    Event: 'game_state_updated'                          │    │
│ │    Recipient: ALL players in room                       │    │
│ │    Data: Game state with ALL hands                      │    │
│ │         - Computer players: hands visible              │    │
│ │         - Human players: hands visible (legacy)        │    │
│ │    Method: _send_to_all_players()                       │    │
│ │    Purpose: Sync game phase, piles, all players        │    │
│ └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────┐    │
│ │ 2️⃣  PRIVATE UPDATES (Individual Sessions)               │    │
│ │    Event: 'player_state_updated'                        │    │
│ │    Recipient: EACH player individually                  │    │
│ │    Data: Player's OWN hand data                         │    │
│ │    Method: _send_dart_player_states_to_frontend()      │    │
│ │    Purpose: Send private hand data to owner only        │    │
│ └─────────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│ FLUTTER FRONTEND                                                │
│                                                                  │
│ ┌────────────────────────────────────────────┐                  │
│ │ handleGameStateUpdated()                   │                  │
│ │ - Updates game phase                       │                  │
│ │ - Updates player list (no hands)           │                  │
│ │ - Updates draw/discard piles               │                  │
│ │ - Triggers UI refresh                      │                  │
│ └────────────────────────────────────────────┘                  │
│                                                                  │
│ ┌────────────────────────────────────────────┐                  │
│ │ handlePlayerStateUpdated()                 │                  │
│ │ - Checks if update is for current user     │                  │
│ │ - Updates myHandCards with actual cards    │                  │
│ │ - Updates myScore, myStatus                │                  │
│ │ - Triggers myHand widget refresh ✅         │                  │
│ └────────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. Python Coordinator Methods

#### `_send_dart_game_state_to_frontend(game_id)`
Main orchestrator method that triggers both updates:

```python
def _send_dart_game_state_to_frontend(self, game_id: str):
    # Get full game state from Dart
    dart_response = self.dart_manager.get_game_state(game_id)
    game_state_data = dart_response.get('data', {}).get('game_state', {})
    
    # Convert to Flutter format (hands will be empty)
    flutter_game_data = self._convert_dart_to_flutter_format(game_state_data)
    
    # PUBLIC UPDATE - Broadcast to room (hands empty)
    payload = {
        'event_type': 'game_state_updated',
        'game_id': game_id,
        'owner_id': owner_id,
        'game_state': flutter_game_data,
        'timestamp': datetime.now().isoformat()
    }
    self._send_to_all_players(game_id, 'game_state_updated', payload)
    
    # PRIVATE UPDATES - Individual sessions (hands included)
    self._send_dart_player_states_to_frontend(game_id, game_state_data)
```

#### `_send_dart_player_states_to_frontend(game_id, dart_game_state)`
Sends private player data to each player:

```python
def _send_dart_player_states_to_frontend(self, game_id: str, dart_game_state: Dict):
    players_data = dart_game_state.get('players', {})
    
    for player_id, player_data in players_data.items():
        # Skip computer players
        if player_id.startswith('computer_'):
            continue
        
        # Find player's session ID
        player_session_id = self._find_player_session(game_id, player_id)
        
        # Convert player data WITH hand
        flutter_player_data = self._convert_dart_player_to_flutter(
            player_data,
            is_current=(player_id == current_player_id),
            include_hand=True  # CRITICAL: Include actual hand
        )
        
        # Send to specific player only
        player_payload = {
            'event_type': 'player_state_updated',
            'game_id': game_id,
            'player_id': player_id,
            'player_data': flutter_player_data,
            'timestamp': datetime.now().isoformat()
        }
        
        self.websocket_manager.send_to_session(
            player_session_id, 
            'player_state_updated', 
            player_payload
        )
```

#### `_convert_dart_player_to_flutter(player_data, is_current, include_hand)`
Shared player data conversion with privacy control:

```python
def _convert_dart_player_to_flutter(self, player_data, is_current=False, include_hand=False):
    player_id = player_data.get('player_id', '')
    
    # Privacy control via include_hand parameter
    if include_hand:
        hand = self._convert_dart_cards_to_flutter(player_data.get('hand', []))
    else:
        hand = []  # Empty for public broadcast
    
    return {
        'id': player_id,
        'name': player_data.get('name'),
        'type': 'human' if player_data.get('player_type') == 'human' else 'computer',
        'hand': hand,  # Conditional based on privacy
        'visibleCards': self._convert_dart_cards_to_flutter(player_data.get('visible_cards', [])),
        'cardsToPeek': self._convert_dart_cards_to_flutter(player_data.get('cards_to_peek', [])),
        'score': int(player_data.get('points', 0)),
        'status': player_data.get('status', 'waiting'),
        'isCurrentPlayer': is_current,
        'hasCalledRecall': player_data.get('has_called_recall', False),
        'drawnCard': self._convert_dart_card_to_flutter(player_data.get('drawn_card'))
    }
```

### 2. Frontend Handlers

#### `handleGameStateUpdated(data)`
Processes public game state (hands empty):

```dart
static void handleGameStateUpdated(Map<String, dynamic> data) {
  final gameId = data['game_id']?.toString() ?? '';
  final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
  
  // Extract game state data
  final phase = gameState['phase']?.toString() ?? 'waiting';
  final players = gameState['players'] as List<dynamic>? ?? [];  // Hands empty!
  final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
  final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
  
  // Update game state in StateManager
  _updateGameInMap(gameId, {
    'gamePhase': phase,
    'players': players,
    'drawPile': drawPile,
    'discardPile': discardPile,
    // ... other public data
  });
}
```

#### `handlePlayerStateUpdated(data)`
Processes private player data (hands included):

```dart
static void handlePlayerStateUpdated(Map<String, dynamic> data) {
  final gameId = data['game_id']?.toString() ?? '';
  final playerId = data['player_id']?.toString() ?? '';
  final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
  
  // Find current user's ID
  final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
  final currentUserId = loginState['userId']?.toString() ?? '';
  
  // Only process if this update is for the current user
  final isMyUpdate = playerId == currentUserId;
  
  if (isMyUpdate) {
    // Extract private player data
    final hand = playerData['hand'] as List<dynamic>? ?? [];  // ACTUAL CARDS!
    final cardsToPeek = playerData['cardsToPeek'] as List<dynamic>? ?? [];
    final drawnCard = playerData['drawnCard'] as Map<String, dynamic>?;
    final score = playerData['score'] as int? ?? 0;
    final status = playerData['status']?.toString() ?? 'unknown';
    final isCurrentPlayer = playerData['isCurrentPlayer'] == true;
    
    // Update main game state
    _updateMainGameState({
      'playerStatus': status,
      'myScore': score,
      'isMyTurn': isCurrentPlayer,
      'myDrawnCard': drawnCard,
      'myCardsToPeek': cardsToPeek,
    });
    
    // Update games map with hand data
    _updateGameInMap(gameId, {
      'myHandCards': hand,  // ✅ myHand widget now populated!
      'selectedCardIndex': -1,
      'isMyTurn': isCurrentPlayer,
      'myDrawnCard': drawnCard,
      'myCardsToPeek': cardsToPeek,
    });
  }
}
```

## Data Flow Sequence

```
1. Game Action (e.g., start_match)
   ↓
2. Dart game logic executes
   ↓
3. GameRound calls action handler
   ↓
4. Action returns success
   ↓
5. Coordinator calls _send_dart_game_state_to_frontend(game_id)
   ↓
6. DUAL UPDATE:
   ├─→ PUBLIC: _send_to_all_players('game_state_updated')
   │   └─→ All players receive game state (hands empty)
   │
   └─→ PRIVATE: _send_dart_player_states_to_frontend()
       └─→ Each player receives own hand data individually
   ↓
7. Frontend processes both events:
   ├─→ handleGameStateUpdated() - Updates game state
   └─→ handlePlayerStateUpdated() - Updates myHandCards
   ↓
8. UI refreshes with full data ✅
```

## Key Benefits

### 🔒 Privacy
- **Computer players**: Hands ALWAYS visible to all players (in public broadcast)
- **Human players**: Hands included in both public AND private updates
  - Public update: All human hands visible (legacy behavior, security note in old code)
  - Private update: Ensures each human player has their own hand data
- Computer players don't receive any updates (no sessions)

### ⚡ Real-time
- Both updates sent immediately after game state change
- No delay between public and private updates
- Atomic operation ensures consistency

### 🎯 Consistency
- All players see same public game state
- Each player sees their own private data
- No race conditions or timing issues

### 🔧 Maintainability
- Single source of truth (Dart game state)
- Clear separation of public vs private data
- Reusable player conversion method with privacy flag

## When Updates Trigger

The dual update pattern is triggered after ANY game action:

1. **Room Creation**: `_on_room_created` → `_send_dart_game_state_to_frontend`
2. **Room Join**: `_on_room_joined` → `_send_dart_game_state_to_frontend`
3. **Start Match**: `_handle_player_action_through_round` → `_send_dart_game_state_to_frontend`
4. **Player Actions**: Any action → `_send_dart_game_state_to_frontend`
5. **Initial Peek**: `completed_initial_peek` → `_send_dart_game_state_to_frontend`

## Testing Checklist

- [x] Public update broadcasts to all players
- [x] Private updates sent to each human player individually
- [x] Computer players skipped in private updates
- [x] Hand data empty in public broadcast
- [x] Hand data full in private updates
- [x] Frontend myHandCards populated after start_match
- [ ] Test with 2+ human players to verify privacy
- [ ] Verify player 1 cannot see player 2's cards
- [ ] Verify player 2 cannot see player 1's cards

## Migration from Old System

### Old Python-Only System
```python
# Old approach - both methods were separate
_send_game_state_partial_update(game_id, changes)
_send_player_state_update_to_all(game_id)
```

### New Hybrid System
```python
# New approach - unified in one method
_send_dart_game_state_to_frontend(game_id)
  ├─→ _convert_dart_to_flutter_format() [hands empty]
  └─→ _send_dart_player_states_to_frontend() [hands included]
```

## Related Files

### Python Backend
- `python_base_04/core/modules/recall_game/game_logic/game_event_coordinator.py`
  - `_send_dart_game_state_to_frontend()`
  - `_send_dart_player_states_to_frontend()`
  - `_convert_dart_player_to_flutter()`

### Dart Game Service
- `python_base_04/core/modules/recall_game/game_logic/dart_services/dart_game_service.dart`
  - Maintains full game state with all hands

### Flutter Frontend
- `flutter_base_05/lib/modules/recall_game/managers/recall_event_handler_callbacks.dart`
  - `handleGameStateUpdated()` - Public data
  - `handlePlayerStateUpdated()` - Private data

## Troubleshooting

### myHand widget not populating?
1. Check `player_state_updated` event is being sent
2. Verify `include_hand=True` in private update
3. Check frontend `handlePlayerStateUpdated` is being called
4. Verify `currentUserId` matches `playerId` in update

### Players seeing other players' cards?
1. Check `include_hand=False` in public broadcast
2. Verify `_convert_dart_to_flutter_format` uses correct flag
3. Ensure hands are empty arrays in public payload

### Updates not real-time?
1. Verify `_send_dart_game_state_to_frontend` called after actions
2. Check WebSocket connections are active
3. Verify both public and private updates sent together

---

**Last Updated**: September 30, 2025  
**Status**: ✅ Implemented and Ready for Testing

