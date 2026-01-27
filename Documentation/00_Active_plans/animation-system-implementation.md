# Animation System Implementation Plan

**Status**: In Progress  
**Created**: January 26, 2026  
**Last Updated**: January 27, 2026

## Objective

Implement a simple, non-position-tracking animation system for card movements in player hands. When widget slices detect changes in player hands, cards will animate smoothly using an overlay approach rather than tracking exact positions.

## Implementation Steps
- [x] Add GlobalKeys and RenderBox tracking for piles (draw pile, discard pile, game board) ✅
- [x] Add GlobalKeys for individual cards in myHand and opponent hands ✅
- [x] Implement bounds tracking system with rate limiting (5 seconds) ✅
- [x] Create PlayScreenFunctions class for centralized bounds management ✅
- [x] Create overlay system with red borders for visual debugging ✅
- [x] Implement cache cleanup for missing cards ✅
- [ ] Define list of possible change types/animations
- [ ] Create animation detection system in widget slices
- [ ] Implement predefined animation library with parameters
- [ ] Create overlay card animation system
- [ ] Add opacity transition logic
- [ ] Integrate with existing card rendering

## Current Progress

### Completed (January 27, 2026)

**Bound Tracking Infrastructure:**
- Created `PlayScreenFunctions` class in `playscreenfunctions.dart` for centralized bounds management
- Added GlobalKeys and RenderBox tracking for:
  - Draw pile (`_drawPileKey`)
  - Discard pile (`_discardPileKey`)
  - Game board (`_gameBoardKey`)
- Added GlobalKeys for individual cards:
  - MyHand cards: `${playerId}_$index` format
  - Opponent cards: `${playerId}_$index` format
  - Blank slots also have keys to maintain index tracking
- Implemented bounds tracking with:
  - Rate limiting (updates once per 5 seconds)
  - PostFrameCallback to ensure widgets are fully built before reading bounds
  - Automatic cache cleanup for cards that no longer exist
  - Callback system to trigger widget rebuilds when bounds change
- Created visual overlay system:
  - Red borders around all tracked elements (piles and individual cards)
  - Labels showing the key string for each card
  - Uses global screen positions converted to local coordinates
  - Updates automatically when bounds change

**Action ID System:**
- Action declarations now append randomized 6-digit numbers for unique action tracking
- Helper method `_generateActionId()` added to generate random 6-digit IDs (100000-999999)
- All action types updated: `drawn_card`, `play_card`, `same_rank`, `jack_swap`, `queen_peek`

## Next Steps

1. **State Interception System** (Priority):
   - Intercept state updates in unified widget
   - Cache widget's own slice keys prefixed with `prev_state_*`
   - Have actual widgets listen to `prev_state_*` local slices instead of original state
   - Update `prev_state_*` with new state after animations complete
   - This provides time for animations before state updates

2. Define list of possible change types/animations
3. Create animation detection system in widget slices
4. Implement predefined animation library with parameters
5. Create overlay card animation system using cached bounds
6. Add opacity transition logic
7. Integrate with existing card rendering

## Files Modified

- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` - Added `_generateActionId()` helper and updated action declarations
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/functionality/playscreenfunctions.dart` - **NEW FILE** - Centralized bounds tracking and management
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart` - Added GlobalKeys, bounds tracking, overlay system

## Notes

### Animation System Approach

**Simple Non-Position-Tracking Animation with Predefined Animations:**

The system uses a structured approach with predefined animations:

1. **List of Possible Changes** - Define a catalog of change types that can occur (e.g., card drawn, card played, card swapped, etc.)

2. **Change Detection** - When widget slices detect changes in player hands, they identify which type of change occurred

3. **Predefined Animation Selection** - Based on the detected change type, select the appropriate predefined animation from the library

4. **Animation Execution with Parameters** - Execute the predefined animation using parameters such as:
   - Card ID
   - Animation duration
   - Animation curve
   - Source/destination information (if applicable)

5. **Overlay Animation Process**:
   - **Build new card with 0 opacity** - Render the new card with `opacity: 0`
   - **Create overlay card** - An overlay card animates in place on top of the new card position
   - **Animate overlay** - The overlay card performs the predefined animation (e.g., fade in, slide, scale, etc.)
   - **Set opacity to 1** - Once animation completes, set the new card's opacity to 1
   - **Remove overlay card** - Remove the overlay card after the transition is complete

This approach:
- Uses predefined animations for consistency
- Parameterized for flexibility
- Does not require position tracking
- Works with existing widget slice architecture
- Provides smooth visual transitions
- Keeps implementation simple and maintainable

### Action ID System

All action declarations now include randomized 6-digit suffixes (e.g., `drawn_card_846297`, `play_card_123456`) to enable unique action instance tracking in the animation system.

### Bound Tracking System

**Architecture:**
- `PlayScreenFunctions` class centralizes all bounds tracking logic
- Rate-limited updates (5 seconds) to prevent performance issues
- Uses `WidgetsBinding.instance.addPostFrameCallback()` to ensure widgets are fully built before reading bounds
- Automatic cache cleanup removes bounds for cards that no longer exist

**Key Format:**
- MyHand cards: `${playerId}_$index` (e.g., `user123_0`, `user123_1`)
- Opponent cards: `${playerId}_$index` (e.g., `player456_0`, `player456_1`)
- Blank slots also tracked to maintain index consistency

**Overlay System:**
- Visual debugging overlay shows red borders around all tracked elements
- Labels display the key string for easy identification
- Borders update automatically when bounds change
- Uses CustomPainter for efficient rendering

**Cache Management:**
- Tracks bounds for all indices in hand (including empty slots)
- Only clears indices beyond current list length
- Maintains bounds for empty slots as long as they're within valid index range

### State Interception System (Next Phase)

**Approach:**
The unified widget will intercept state updates and maintain a "previous state" cache to enable smooth animations:

1. **State Interception:**
   - Unified widget listens to StateManager changes
   - When state changes detected, cache current state slices with `prev_state_*` prefix
   - Examples: `prev_state_myHand`, `prev_state_opponents`, `prev_state_gameState`

2. **Widget Listening:**
   - Actual widgets (myHand, opponents, etc.) listen to `prev_state_*` slices instead of original state
   - This allows animations to run from old state to new state
   - Widgets render based on previous state while animations execute

3. **State Update Timing:**
   - After animations complete, update `prev_state_*` slices with new state
   - This creates a delay between state change and widget update
   - Provides time window for overlay animations to complete

4. **Benefits:**
   - Animations can reference both old and new state
   - Smooth transitions without flickering
   - Non-blocking - widgets continue to show previous state during animation
   - Can detect what changed by comparing prev_state vs current state

**Implementation Notes:**
- Need to identify which state slices the unified widget manages
- Create local state cache with `prev_state_*` prefix
- Modify widget builders to read from `prev_state_*` instead of direct state
- Add animation completion callbacks to trigger `prev_state_*` updates
- Ensure state synchronization after animations

