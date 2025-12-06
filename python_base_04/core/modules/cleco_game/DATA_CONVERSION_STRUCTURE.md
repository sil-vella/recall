# Cleco Game Data Conversion Structure

## Overview

This document defines the **TWO consolidated data conversion methods** that structure ALL data sent from the Python backend to the Flutter frontend. These methods ensure data consistency and match the Flutter frontend schema exactly.

## 🎯 **Consolidated Data Conversion Methods**

### 1. **`_to_flutter_player_data()`** - Player Data Structure
**Location**: `game_state.py` in `GameStateManager` class
**Purpose**: Convert player objects to Flutter-compatible format

```python
def _to_flutter_player_data(self, player, is_current: bool = False) -> Dict[str, Any]:
    """
    Convert player to Flutter format - SINGLE SOURCE OF TRUTH for player data structure
    
    This method structures ALL player data that will be sent to the frontend.
    The structure MUST match the Flutter frontend schema exactly.
    """
    return {
        'id': player.player_id,
        'name': player.name,
        'type': 'human' if player.player_type.value == 'human' else 'computer',
        'hand': [self._to_flutter_card(c, full_data=False) for c in player.hand if c is not None],  # Face-down cards
        'visibleCards': [self._to_flutter_card(c, full_data=True) for c in player.visible_cards if c is not None],  # Face-up cards
        'score': int(player.calculate_points()),
        'status': player.status.value,
        'isCurrentPlayer': is_current,
        'hasCalledCleco': bool(player.has_called_cleco),
    }
```

### 2. **`_to_flutter_game_data()`** - Game Data Structure
**Location**: `game_state.py` in `GameStateManager` class
**Purpose**: Convert game state objects to Flutter-compatible format

```python
def _to_flutter_game_data(self, game: GameState) -> Dict[str, Any]:
    """
    Convert game state to Flutter format - SINGLE SOURCE OF TRUTH for game data structure
    
    This method structures ALL game data that will be sent to the frontend.
    The structure MUST match the Flutter frontend schema exactly.
    """
    # Build complete game data structure matching Flutter schema
    game_data = {
        # Core game identification
        'gameId': game.game_id,
        'gameName': f"Cleco Game {game.game_id}",
        
        # Player information
        'players': [self._to_flutter_player_data(player, pid == game.current_player_id) for pid, player in game.players.items()],
        'currentPlayer': current_player,
        'playerCount': len(game.players),
        'maxPlayers': game.max_players,
        'minPlayers': game.min_players,
        'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
        
        # Game state and phase
        'phase': phase_mapping.get(game.phase.value, 'waiting'),
        'status': 'active' if game.phase.value in ['player_turn', 'out_of_turn_play', 'cleco_called'] else 'inactive',
        
        # Card piles
        'drawPile': [self._to_flutter_card(card, full_data=False) for card in game.draw_pile],  # Face-down cards
        'discardPile': [self._to_flutter_card(card, full_data=True) for card in game.discard_pile],  # Face-up cards
        
        # Game timing
        'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time else None,
        'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time else None,
        
        # Game completion
        'winner': game.winner,
        'gameEnded': game.game_ended,
        
        # Room settings
        'permission': game.permission,
        
        # Additional game metadata
        'clecoCalledBy': game.cleco_called_by,
        'lastPlayedCard': self._to_flutter_card(game.last_played_card, full_data=True) if game.last_played_card else None,  # Face-up card
        'outOfTurnDeadline': game.out_of_turn_deadline,
        'outOfTurnTimeoutSeconds': game.out_of_turn_timeout_seconds,
    }
    
    return game_data
```

## 🔄 **Delegation Pattern**

Both the `GameEventCoordinator` and `GameRound` classes delegate to the `GameStateManager` methods:

### Coordinator Delegation
```python
def _to_flutter_game_data(self, game) -> Dict[str, Any]:
    """Convert game state to Flutter format - delegates to game_state manager"""
    try:
        if hasattr(game, '_to_flutter_game_data'):
            return game._to_flutter_game_data()
        elif hasattr(game, '_to_flutter_game_state'):
            # Fallback to deprecated method during migration
            return game._to_flutter_game_state()
        else:
            custom_log(f"❌ Game object has no data conversion method", level="ERROR")
            return {}
    except Exception as e:
        custom_log(f"❌ Error converting game state: {e}", level="ERROR")
        return {}
```

### Game Round Delegation
```python
def _to_flutter_game_data(self) -> Dict[str, Any]:
    """Convert game state to Flutter format - delegates to game_state manager"""
    try:
        if hasattr(self.game_state, '_to_flutter_game_data'):
            return self.game_state._to_flutter_game_data()
        elif hasattr(self.game_state, '_to_flutter_game_state'):
            # Fallback to deprecated method during migration
            return self.game_state._to_flutter_game_state(self.game_state)
        else:
            custom_log(f"❌ Game state has no data conversion method", level="ERROR")
            return {}
    except Exception as e:
        custom_log(f"❌ Error converting game state: {e}", level="ERROR")
        return {}
```

## 📊 **Data Structure Mapping**

### Frontend Schema Compatibility
The data structures are designed to match the Flutter frontend schema exactly:

1. **Game State Fields**:
   - `gameId`, `gameName` → Frontend `currentGameId`, `roomName`
   - `phase` → Frontend `gamePhase` (with mapping: `waiting_for_players` → `waiting`)
   - `status` → Frontend `gameStatus` (with mapping: `player_turn` → `active`)
   - `players` → Frontend `opponents` + `myHand` slices
   - `drawPile`, `discardPile` → Frontend `centerBoard` slice

2. **Player State Fields**:
   - `id`, `name`, `type` → Frontend player identification
   - `hand`, `visibleCards` → Frontend `myHand` slice
   - `score`, `status` → Frontend player status display
   - `isCurrentPlayer` → Frontend turn management

3. **Card Structure**:
   - `cardId`, `suit`, `rank`, `points` → Frontend card display
   - `displayName`, `color` → Frontend UI rendering

## 🚨 **Migration Notes**

### Deprecated Methods (To Be Removed)
The following methods are now deprecated and will be removed after migration:

1. **`_to_flutter_card()`** → Use `_to_flutter_player_data()` or `_to_flutter_game_data()`
   - **Note**: `_to_flutter_card()` now accepts a `full_data` parameter:
     - `full_data=False` (default): Sends ID-only data for face-down cards
     - `full_data=True`: Sends complete card data for face-up cards
2. **`_to_flutter_player()`** → Use `_to_flutter_player_data()`
3. **`_to_flutter_game_state()`** → Use `_to_flutter_game_data()`

### Fallback Support
During migration, the system supports both old and new method names to ensure backward compatibility.

## ✅ **Benefits of Consolidation**

1. **Single Source of Truth**: Only 2 methods structure ALL frontend data
2. **Schema Consistency**: Guaranteed match with Flutter frontend expectations
3. **Maintainability**: Changes to data structure only need to be made in 2 places
4. **Type Safety**: Consistent data types and structure across all endpoints
5. **Performance**: Eliminates duplicate data conversion logic

## 🔍 **Usage Examples**

### Converting Player Data
```python
# In GameStateManager
player_data = self._to_flutter_player_data(player, is_current=True)

# In Coordinator (delegates to GameStateManager)
player_data = coordinator._to_flutter_player_data(player, is_current=True)
```

### Converting Game Data
```python
# In GameStateManager
game_data = self._to_flutter_game_data(game)

# In Coordinator (delegates to GameStateManager)
game_data = coordinator._to_flutter_game_data(game)

# In GameRound (delegates to GameStateManager)
game_data = self._to_flutter_game_data()
```

## 📝 **Maintenance Guidelines**

1. **NEVER modify data structure in coordinator or game_round classes**
2. **ALWAYS modify data structure in GameStateManager methods**
3. **Test data structure changes against Flutter frontend schema**
4. **Update this documentation when data structure changes**
5. **Remove deprecated methods after migration is complete**

This consolidation ensures that the Python backend and Flutter frontend maintain perfect data structure synchronization through exactly 2 well-defined conversion methods.
