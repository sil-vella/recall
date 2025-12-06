# ✅ COMPLETED: Fix Draw Pile Issue

## Problem
After removing `self.websocket_manager` from GameRound, drawing from the draw pile stopped working. The `_extract_user_id` method was returning `session_id` instead of `player_id`.

## Root Cause
When we removed `self.websocket_manager` from `GameRound.__init__`, accessing it in `_extract_user_id` threw an `AttributeError`. This exception was caught, causing the method to return `session_id` as a fallback instead of extracting `player_id` from the data.

## Fix Applied
Modified `_extract_user_id` to get `websocket_manager` from `game_state.app_manager.get_websocket_manager()` instead of using the removed `self.websocket_manager` attribute.

## Result
✅ Draw from draw pile now works correctly
✅ Error messages (timeouts, collection rank) work correctly
✅ All functionality restored

---

# 📋 FUTURE TASK: Collection Rank Cards UI Stacking

## Feature Request
Implement visual stacking for collection rank cards in the OpponentsPanelWidget.

## Requirements
- Collection rank cards should stack on top of each other
- Each subsequent card should be positioned slightly lower than the previous one
- This creates a cascading/stacked effect that shows all cards in the collection
- Should clearly display the rank of all cards in the collection

## Implementation Location
- `flutter_base_05/lib/modules/cleco_game/widgets/opponents_panel_widget.dart`
- Specifically in the `_buildCardsRow()` method where collection rank cards are displayed

## Current Behavior
Collection rank cards are displayed side by side in a row.

## Desired Behavior
Collection rank cards should overlap vertically with a slight offset, creating a stacked appearance that shows all card ranks while saving horizontal space.

## Technical Approach (suggested)
- Use a `Stack` widget instead of `Row` for collection rank cards
- Position each card with an incremental vertical offset (e.g., 10-15 pixels per card)
- Ensure the top card is fully visible and subsequent cards show enough to identify their rank
- Consider z-index ordering so the most recent card is on top

## Priority
Medium - Visual enhancement for better UX when players have multiple collection rank cards
