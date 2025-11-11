# Recall Game Development Notes

## Card Animation System - State Change Detection

**Date:** 2025-11-09  
**Priority:** High

### Issue
Ensure that ANY state change in the Recall game is immediately detected and sent to the card position tracker and animation callbacks.

### Current State
The card animation system relies on:
- `CardPositionTracker` to track card positions
- `CardAnimationManager` to detect movements and create animations
- Widgets registering positions via `addPostFrameCallback`

### Required Improvements
1. **State Change Detection**
   - Review all state update paths in `StateManager`
   - Ensure every state change that affects card positions triggers:
     - Position registration in widgets
     - Movement detection in `CardAnimationManager`
     - Animation callbacks

2. **Immediate Callbacks**
   - State changes should trigger position tracking immediately
   - No delays or batching that could miss intermediate states
   - Ensure `addPostFrameCallback` timing doesn't miss rapid state changes

3. **Comprehensive Coverage**
   - All card movements (hand to hand, hand to discard, discard to hand, etc.)
   - All state updates that affect card positions
   - All game phases that involve card movements

### Implementation Checklist
- [ ] Audit all `StateManager.updateModuleState()` calls related to cards
- [ ] Ensure position registration happens synchronously with state updates
- [ ] Add state change listeners that immediately trigger position tracking
- [ ] Test rapid state changes to ensure no movements are missed
- [ ] Verify animation callbacks fire for all state change scenarios

### Related Files
- `lib/modules/recall_game/managers/card_animation_manager.dart`
- `lib/modules/recall_game/utils/card_position_tracker.dart`
- `lib/modules/recall_game/screens/game_play/widgets/card_animation_layer.dart`
- `lib/core/managers/state_manager.dart`
- All card-displaying widgets (MyHandWidget, OpponentsPanelWidget, etc.)

---

## Card Animation System - Queue System for Per-Card Animations

**Date:** 2025-11-09  
**Priority:** Medium

### Issue
When a card is already animating and another animation is requested for the same card, the new animation should be queued rather than ignored or conflicting.

### Requirements
1. **Per-Card Animation Queue**
   - Each card can have a queue of pending animations
   - If a card is currently animating, new animations for that card are queued
   - When the current animation completes, the next animation in the queue starts automatically

2. **Simultaneous Animations**
   - Different cards can animate simultaneously (already supported)
   - Only animations for the same card need to be queued
   - The `_maxConcurrentAnimations` limit applies to different cards, not queued animations for the same card

3. **Queue Management**
   - Queue should be FIFO (First In, First Out)
   - Queue should handle rapid state changes gracefully
   - Queue should prevent animation conflicts (e.g., card moving from A->B then B->C should queue as A->B->C)

### Implementation Details
- Add `Map<String, List<CardAnimation>>` for per-card animation queues
- Modify `detectAndCreateAnimations()` to check if card is already animating
- If animating, add to queue instead of creating new animation
- On animation completion, check queue and start next animation if available
- Update `_maxConcurrentAnimations` logic to account for queued animations

### Implementation Checklist
- [ ] Add per-card animation queue data structure
- [ ] Modify animation creation to check for existing animations
- [ ] Queue new animations for cards that are already animating
- [ ] Auto-start queued animations when current animation completes
- [ ] Handle queue cleanup on animation cancellation
- [ ] Test rapid state changes for the same card
- [ ] Test simultaneous animations for different cards

### Related Files
- `lib/modules/recall_game/managers/card_animation_manager.dart`
- `lib/modules/recall_game/screens/game_play/widgets/card_animation_layer.dart`

