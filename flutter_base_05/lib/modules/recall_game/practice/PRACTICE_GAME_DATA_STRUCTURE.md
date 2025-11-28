# Practice Game Data Structure - Study Note

## TODO: Verify Practice Game Data Matches GamePlayScreen Expectations

### How GamePlayScreen Gets Game Data

The `GamePlayScreen` and its widgets read game data from `StateManager` using this structure:

```dart
// 1. Get the recall_game module state
final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};

// 2. Extract key pieces
final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
final currentGameId = gameInfo['currentGameId']?.toString() ?? ''; // OR recallGameState['currentGameId']

// 3. Access game data via games map
final gameEntry = games[currentGameId] as Map<String, dynamic>? ?? {};
final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
```

### Expected Data Structure

```dart
recallGameState = {
  'currentGameId': 'practice_room_123',  // OR in gameInfo['currentGameId']
  'currentRoomId': 'practice_room_123',
  'isInRoom': true,
  'isRoomOwner': true,
  'gameType': 'practice',
  'gameInfo': {
    'currentGameId': 'practice_room_123',
    'currentSize': 1,
    'maxSize': 4,
    'gamePhase': 'waiting',  // Derived from game_state.phase
    'gameStatus': 'inactive', // Derived from game_state.status
    'isRoomOwner': true,
    'isInGame': true,
  },
  'games': {
    'practice_room_123': {
      'gameData': {  // Single Source of Truth (SSOT)
        'game_id': 'practice_room_123',
        'owner_id': 'user_123',
        'game_type': 'practice',
        'game_state': {  // From GameStateStore
          'phase': 'waiting_for_players',  // or 'dealing_cards', 'player_turn', etc.
          'status': 'inactive',  // or 'active', 'ended', etc.
          'players': [...],
          'current_player': 'user_123',
          // ... other game state fields
        },
        'max_size': 4,
        'min_players': 2,
      },
      'gamePhase': 'waiting',  // Normalized phase (derived from game_state.phase)
      'gameStatus': 'inactive', // Derived from game_state.status
      'isRoomOwner': true,
      'isInGame': true,
      'joinedAt': '2024-11-27T22:00:00.000Z',
    }
  }
}
```

### Widgets That Read This Data

1. **GameInfoWidget** (`game_info_widget.dart`):
   - Reads: `games[gameId]['gameData']['game_state']['phase']`
   - Uses: `_getPhaseFromGamesMap(games, currentGameId)`
   - Normalizes phase: `waiting_for_players` → `waiting`, `dealing_cards` → `setup`, etc.

2. **MyHandWidget** (`my_hand_widget.dart`):
   - Reads: `games[currentGameId]['gameData']['game_state']`
   - Accesses player hands from game state

3. **OpponentsPanelWidget** (`opponents_panel_widget.dart`):
   - Reads: `games[currentGameId]['gameData']['game_state']`
   - Displays opponent information

4. **GameBoardWidget** (`game_board_widget.dart`):
   - Reads: `games[currentGameId]['gameData']['game_state']`
   - Displays game board state

5. **DrawPileWidget** (`draw_pile_widget.dart`):
   - Reads: `games[currentGameId]['gameData']['game_state']`
   - Displays draw pile

6. **DiscardPileWidget** (`discard_pile_widget.dart`):
   - Reads: `games[currentGameId]['gameData']['game_state']`
   - Displays discard pile

### Current Practice Game Setup (lobby_screen.dart)

The `_startPracticeMatch` method currently creates:

```dart
games[practiceRoomId] = {
  'gameData': {
    'game_id': practiceRoomId,
    'owner_id': currentUserId,
    'game_type': 'practice',
    'game_state': gameState,  // From GameStateStore.instance.getGameState(practiceRoomId)
    'max_size': 4,
    'min_players': 2,
  },
  'gamePhase': gamePhase,  // Derived from gameState['phase']
  'gameStatus': gameStatus, // Derived from gameState['status']
  'isRoomOwner': true,
  'isInGame': true,
  'joinedAt': DateTime.now().toIso8601String(),
};
```

### Verification Checklist

- [ ] Verify `gameState` from `GameStateStore.instance.getGameState(practiceRoomId)` has all required fields
- [ ] Verify `gameState['phase']` matches expected values (`waiting_for_players`, `dealing_cards`, etc.)
- [ ] Verify `gameState['status']` matches expected values (`inactive`, `active`, etc.)
- [ ] Verify `gameState['players']` array structure matches multiplayer format
- [ ] Verify `gameState['current_player']` is set correctly
- [ ] Verify phase normalization works correctly for practice games
- [ ] Test that all widgets can read practice game data correctly
- [ ] Verify `currentGameId` is set in both `recallGameState['currentGameId']` and `gameInfo['currentGameId']`

### Key Files to Review

1. `screens/game_play/game_play_screen.dart` - Main screen
2. `screens/game_play/widgets/game_info_widget.dart` - Phase extraction logic
3. `screens/game_play/widgets/my_hand_widget.dart` - Hand data access
4. `screens/game_play/widgets/opponents_panel_widget.dart` - Opponent data access
5. `screens/lobby_room/lobby_screen.dart` - Practice game setup (`_startPracticeMatch`)
6. `backend_core/services/game_state_store.dart` - GameStateStore structure
7. `practice/practice_mode_bridge.dart` - Practice bridge initialization

### Notes

- The `games` map is the Single Source of Truth (SSOT) for game data
- `gameData['game_state']` should match the structure returned by `GameStateStore.getGameState()`
- Phase normalization happens in `GameInfoWidget._normalizePhase()` - ensure practice game phases are compatible
- All widgets use `ListenableBuilder` to subscribe to state changes automatically

