# Animation System Implementation Plan

**Status**: Planning  
**Created**: January 26, 2026  
**Last Updated**: January 26, 2026

## Objective

Implement a simple, non-position-tracking animation system for card movements in player hands. When widget slices detect changes in player hands, cards will animate smoothly using an overlay approach rather than tracking exact positions.

## Implementation Steps
- [ ] Define list of possible change types/animations
- [ ] Create animation detection system in widget slices
- [ ] Implement predefined animation library with parameters
- [ ] Create overlay card animation system
- [ ] Add opacity transition logic
- [ ] Integrate with existing card rendering

## Current Progress

- Action declarations now append randomized 6-digit numbers for unique action tracking
- Helper method `_generateActionId()` added to generate random 6-digit IDs (100000-999999)
- All action types updated: `drawn_card`, `play_card`, `same_rank`, `jack_swap`, `queen_peek`

## Next Steps

1. Detect hand changes in widget slices
2. Implement overlay card animation system
3. Add opacity transitions

## Files Modified

- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart` - Added `_generateActionId()` helper and updated action declarations

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

