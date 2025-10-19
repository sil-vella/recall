# ✅ FIXED: Error Messages Now Use GameEventCoordinator

## Problem
Both timeout errors and collection rank errors were not showing as snackbars in the frontend.

## Root Cause
`GameRound` was trying to use `self.websocket_manager`, which was set to `None` because:
1. Line 56 tried to get it from `game_state`: `self.websocket_manager = getattr(game_state, 'websocket_manager', None)`
2. `GameState` doesn't have a `websocket_manager` attribute
3. All error messages were failing silently with "websocket_manager is None" warnings

## Solution
Instead of directly accessing `websocket_manager`, `GameRound` now uses the existing `GameEventCoordinator._send_error()` method:

### Added Helper Method
```python
def _send_error_to_player(self, player_id: str, message: str):
    """Send error message to a player using the coordinator"""
    # Get session_id from game_state
    session_id = self.game_state.player_sessions.get(player_id)
    
    # Get coordinator from app_manager
    coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
    
    # Send error through coordinator
    coordinator._send_error(session_id, message)
```

### Updated All Error Handlers
1. **Timeout errors** (draw phase, play phase)
2. **Collection rank errors** (discard pile, play card, same rank)
3. **Phase check errors** (same rank window, initial peek, empty discard)

All now use: `self._send_error_to_player(player_id, message)`

## Result
✅ All error messages now properly reach the frontend as snackbars
✅ No more "websocket_manager is None" warnings
✅ Consistent error handling pattern across all error types
✅ Uses existing coordinator infrastructure (proper architecture)

## Files Modified
- `python_base_04/core/modules/recall_game/game_logic/game_round.py`
  - Removed `self.websocket_manager` initialization
  - Added `_send_error_to_player()` helper method
  - Updated 8 error message sending locations

## Testing
Test in a backend multiplayer game:
1. ✅ Draw timeout: Wait 10+ seconds without drawing → snackbar appears
2. ✅ Play timeout: Draw card, wait 10+ seconds → snackbar appears
3. ✅ Collection rank errors: Try to collect/play wrong cards → snackbar appears

