# Animation System Implementation Plan

**Status**: In Progress  
**Created**: January 26, 2026  
**Last Updated**: January 28, 2026

## Objective

Implement a simple, non-position-tracking animation system for card movements in player hands. When widget slices detect changes in player hands, cards will animate smoothly using an overlay approach rather than tracking exact positions.

## Implementation Steps
- [x] Add GlobalKeys and RenderBox tracking for piles (draw pile, discard pile, game board) ✅
- [x] Add GlobalKeys for individual cards in myHand and opponent hands ✅
- [x] Implement bounds tracking system with rate limiting (5 seconds) ✅
- [x] Create PlayScreenFunctions class for centralized bounds management ✅
- [x] Create overlay system with red borders for visual debugging ✅
- [x] Implement cache cleanup for missing cards ✅
- [x] Implement state interception system with prev_state caching ✅
- [x] Replace border overlay with animation overlay layer ✅
- [x] Create Animations utility class for action-to-animation mapping ✅
- [x] Implement smooth card animations using actual CardWidget ✅
- [x] Fix playerId lookup for correct animation targeting ✅
- [x] Add cached state update system with timeout protection ✅
- [x] Update actionData to use cardIndex instead of cardId ✅
- [x] Implement flashCard animation for initial_peek ✅
- [x] Implement flashCard animation for queen_peek ✅
- [x] Create dynamic flashCard animation handler (handles 1+ players, 1+ cards) ✅
- [x] Fix index mismatch issues in initial_peek action declaration ✅
- [x] Fix auto-completion overwriting manually selected cards ✅
- [x] Update queen_peek to use queue format ✅
- [ ] Define remaining animation types (swap, etc.)
- [ ] Implement swap animation handler for jack_swap
- [ ] Add animation parameters tuning
- [ ] Optimize animation performance

## Current Progress

### Completed (January 28, 2026)

**FlashCard Animation System:**
- Implemented `flashCard` animation type for card border flashing
- Created `_triggerFlashCardAnimation()` method with dynamic logic:
  - Handles any number of players (1 or more)
  - Handles any number of cards per player (1 or more)
  - Dynamically extracts card data (card1Data, card2Data, card3Data, etc.)
  - Supports cross-player card peeking (queen_peek can peek at other players' cards)
  - Action-specific processing (initial_peek: all players, queen_peek: single player)
- Mapped `initial_peek` to `flashCard` animation
- Mapped `queen_peek` to `flashCard` animation
- Animation flashes border 3 times using `AppColors.statusPeeking` color
- Border rendered in animation overlay (not on actual widgets)
- Duration: 1500ms with `Curves.easeInOut`

**Initial Peek Implementation:**
- Fixed index mismatch bug: now uses `playerInGamesMap['hand']` instead of `player['hand']` from gameState
- Ensures indices match frontend rendering (gamesMap is source of truth for UI)
- Added extensive logging to verify card IDs at calculated indices
- Fixed auto-completion bug: `_autoCompleteRemainingHumanPlayers` now checks if `cardsToPeek` is already set before overwriting
- Prevents timer from overwriting manually selected cards
- Added safety comments clarifying per-player index calculation

**Queen Peek Implementation:**
- Updated `queen_peek` action to use queue format (consistent with other actions)
- Action now stored as list: `[{'name': 'queen_peek_123456', 'data': {...}}]`
- Works for both human and computer players
- Computer players use decision logic to select target card
- Animation correctly handles single-card peeks (1 card vs 2 cards for initial_peek)

**Testing Configuration:**
- Updated `predefined_hands.yaml` to move all queens from player_0 to players 1-3
- Enables easier testing of queen peek functionality

### Completed (January 27, 2026 - Evening)

**Animation Overlay System:**
- Removed border overlay debugging system
- Created animation overlay layer that shows animated cards during transitions
- Animation overlay uses actual `CardWidget` with real card data (not placeholders)
- Cards smoothly animate from source to destination positions
- Overlay automatically hides when animations complete
- Cards disappear from overlay after animation finishes

**State Interception System:**
- Implemented `_prevStateCache` in unified widget to cache previous state slices
- Widgets now read from `prev_state_*` slices instead of direct state
- State updates are intercepted in `_onStateChanged()` method
- Animations run before state updates, providing smooth transitions
- Added `_isProcessingStateChange` flag to prevent concurrent processing
- Implemented cached state update system:
  - Latest state update attempt is cached (replaces any previous cache)
  - After animations complete, cached state is processed
  - Ensures newest state is always applied after animations

**Animation Timeout Protection:**
- Added 4-second timeout timer for animations
- If animations don't complete in 4 seconds:
  - All active animations are cleared and disposed
  - Animation overlay is hidden
  - State update continues with latest cached state
- Prevents indefinite blocking from stuck animations

**Animations Utility Class:**
- Created `animations.dart` in functionality directory
- Maps action names to `AnimationType` enum
- Provides animation duration and curve configuration
- Validates action data structure
- Prevents duplicate animations with action caching
- Currently supports `moveCard` animation type
- Ready for extension with additional animation types

**Action Data Refinement:**
- Replaced `cardId` with `cardIndex` in all action declarations
- Updated `drawn_card`, `play_card`, `same_rank`, `jack_swap`, `queen_peek` actions
- Aligns with bound tracking system that uses indices
- Enables accurate card position lookup for animations

**PlayerId Lookup Fix:**
- Fixed animation destination bounds lookup
- Now correctly identifies my hand vs opponent hands
- Uses `DutchEventHandlerCallbacks.getCurrentUserId()` for comparison
- Properly retrieves bounds from correct source (my hand or opponent)
- Added extensive logging for debugging playerId matching

**Logging Enhancement:**
- Enabled `LOGGING_SWITCH = false` in unified widget
- Added comprehensive logging throughout animation system:
  - State change processing
  - Animation triggering
  - PlayerId matching
  - Bounds lookup
  - Animation completion
  - Cached state processing

**Extra Empty Slot:**
- Added invisible empty slot at end of both my hand and opponent hands
- Provides space for animations and ensures continuous bound tracking
- Maintains border tracking for this extra slot

### Completed (January 27, 2026 - Morning)

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

1. **Additional Animation Types**:
   - Implement `swap` animation for jack_swap actions
   - Add fade/slide animations for other action types if needed
   - Define animation parameters for each type

2. **Animation Refinement**:
   - Tune animation durations and curves
   - Add scale/rotation effects if needed
   - Optimize animation performance
   - Test with various screen sizes

3. **Error Handling**:
   - Add fallback for missing bounds
   - Handle edge cases (empty hands, missing cards)
   - Improve timeout handling

4. **Testing**:
   - Test with multiple rapid state updates
   - Verify timeout behavior
   - Test with different player counts
   - Verify animations work for all action types

## Files Modified

- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` 
  - Added `_generateActionId()` helper and updated action declarations
  - Replaced `cardId` with `cardIndex` in all action `actionData` payloads
  - Updated `queen_peek` to use queue format (list of actions)
  - Fixed `_clearPlayerAction` to clear all actions including coordinator-declared ones
- `flutter_base_05/lib/modules/dutch_game/backend_core/coordinator/game_event_coordinator.dart`
  - Fixed `_completeInitialPeek` to use `playerInGamesMap['hand']` for index calculation
  - Added extensive logging for index verification
  - Fixed `_autoCompleteRemainingHumanPlayers` to check existing `cardsToPeek` before overwriting
  - Added `_generateActionId()` helper method
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/functionality/playscreenfunctions.dart` - **NEW FILE** - Centralized bounds tracking and management
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/functionality/animations.dart`
  - Added `AnimationType.flashCard` enum value
  - Mapped `initial_peek` to `flashCard` animation
  - Mapped `queen_peek` to `flashCard` animation
  - Updated validation to handle `queen_peek` (only requires card1Data)
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart` 
  - Added GlobalKeys, bounds tracking
  - Removed border overlay, added animation overlay
  - Implemented state interception with prev_state caching
  - Added cached state update system with timeout
  - Fixed playerId lookup for animations
  - Added extra empty slots for animation space
  - Enabled comprehensive logging
  - Implemented `_triggerFlashCardAnimation()` with dynamic logic
  - Added `_buildFlashCardBorders()` for rendering flashing borders
  - Updated `_buildAnimationOverlay()` to handle flashCard animations
- `flutter_base_05/assets/predefined_hands.yaml`
  - Moved all queens from player_0 to players 1-3 for testing

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

### Animation Overlay System (✅ Implemented)

**Architecture:**
- Animation overlay layer replaces border debugging overlay
- Uses `_activeAnimations` map to track active animations by action name
- Each animation stores: animationType, sourceBounds, destBounds, controller, animation, cardData
- Overlay only renders when `_activeAnimations` is not empty

**Animation Execution:**
- `_triggerAnimation()` creates AnimationController and CurvedAnimation
- Gets source bounds (e.g., draw pile) and destination bounds (card in hand)
- Retrieves actual card data from game state for rendering
- Stores animation data and starts controller
- Returns Future that completes when animation finishes

**Card Rendering:**
- Uses actual `CardWidget` with real card data (not placeholders)
- Card size comes from bounds data (prefers destination size)
- For `moveCard` animations: interpolates position from source to destination
- Card stays fully visible during movement (opacity: 1.0)
- Card disappears when animation completes (removed from `_activeAnimations`)

**Animation Types:**
- Currently implemented: 
  - `moveCard` (for drawn_card, play_card actions)
  - `flashCard` (for initial_peek, queen_peek actions)
- Ready for extension: `swap`, `fadeIn`, `fadeOut`, etc.
- Each type has configurable duration and curve

**PlayerId Matching:**
- Correctly identifies my hand vs opponent hands
- Uses `DutchEventHandlerCallbacks.getCurrentUserId()` for comparison
- Retrieves bounds from correct source based on playerId match
- Logs available opponent bounds for debugging

### State Interception System (✅ Implemented)

**Implementation:**
The unified widget intercepts state updates and maintains a "previous state" cache to enable smooth animations:

1. **State Interception:**
   - Unified widget listens to StateManager changes via `_onStateChanged()`
   - Maintains `_prevStateCache` map with `prev_state_*` prefixed keys
   - Initializes cache in `initState()` with `_initializePrevStateCache()`
   - Updates cache after animations complete with `_updatePrevStateCache()`

2. **Widget Listening:**
   - Widgets read from `_getPrevStateDutchGame()` instead of direct state
   - This provides previous state data while animations run
   - Widgets render based on previous state during animation execution

3. **State Update Timing:**
   - `_onStateChanged()` detects actions and triggers animations
   - Waits for all animations to complete with `await Future.wait(animationFutures)`
   - Only after animations complete, updates `prev_state_*` cache
   - Then triggers `setState()` to update UI

4. **Cached State Update System:**
   - If state update arrives while processing, caches it in `_cachedStateUpdate`
   - Latest state always replaces previous cached state
   - After animations complete, processes cached state if present
   - Ensures newest state is always applied

5. **Timeout Protection:**
   - 4-second timer prevents indefinite blocking
   - On timeout: clears animations, hides overlay, continues with state update
   - Processes any cached state after timeout

**Benefits Achieved:**
- ✅ Animations run before state updates
- ✅ Smooth transitions without flickering
- ✅ Non-blocking - widgets show previous state during animation
- ✅ Handles multiple rapid state updates correctly
- ✅ Prevents animation blocking with timeout

### FlashCard Animation System (✅ Implemented - January 28, 2026)

**Implementation:**
- Created reusable `_triggerFlashCardAnimation()` method that handles:
  - **Multiple action types**: `initial_peek` (multi-player, 2 cards each) and `queen_peek` (single-player, 1 card)
  - **Dynamic card extraction**: Automatically finds `card1Data`, `card2Data`, `card3Data`, etc.
  - **Cross-player support**: Handles cases where card is in different player's hand (queen_peek)
  - **Action-specific logic**: 
    - `initial_peek`: Processes all players, prevents duplicate animations
    - `queen_peek`: Processes only triggering player, each action is independent

**Visual Effect:**
- Flashes border 3 times over 1500ms duration
- Uses `AppColors.statusPeeking` (Pink/Magenta) color
- Border width: 4.0, Border radius: 8.0
- Rendered in animation overlay (separate from actual widgets)
- Each flash cycle: fade in → hold → fade out

**Index Calculation Fix:**
- Fixed critical bug where `initial_peek` used wrong hand source
- Now uses `playerInGamesMap['hand']` (from gamesMap) instead of `player['hand']` (from gameState)
- Ensures indices match frontend rendering and bounds lookup
- Added verification logging to confirm card IDs match at calculated indices

**Auto-Completion Fix:**
- Fixed bug where timer auto-completion overwrote manually selected cards
- `_autoCompleteRemainingHumanPlayers` now checks if `cardsToPeek` is already set
- Prevents overwriting user's manual selections

**Queue Format:**
- Updated `queen_peek` to use action queue format (consistent with other actions)
- Actions stored as: `[{'name': 'queen_peek_123456', 'data': {...}}]`
- Enables proper animation processing and action tracking
