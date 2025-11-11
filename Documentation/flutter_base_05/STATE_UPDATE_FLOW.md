# State Update Flow - Single Source of Truth (SSOT)

## Overview

All game state updates in the Recall game system flow through a **Single Source of Truth (SSOT)**: `RecallGameStateUpdater`. This ensures:

1. **Consistent validation** across all state updates
2. **Automatic position saving** for card animations (before state updates)
3. **Widget slice computation** for optimized UI rebuilds
4. **Unified behavior** for both practice games and WebSocket events

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    STATE UPDATE FLOW                            │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────┐         ┌──────────────────────┐
│   Practice Game      │         │  WebSocket Events    │
│   Flow               │         │  Flow                │
└──────────────────────┘         └──────────────────────┘
         │                                 │
         │                                 │
         ▼                                 ▼
┌──────────────────────┐         ┌──────────────────────┐
│ recall_game_round.dart│         │ recall_event_handler │
│                       │         │ _callbacks.dart       │
│ Uses GameStateCallback│         │                       │
└──────────────────────┘         └──────────────────────┘
         │                                 │
         │ _stateCallback.onGameStateChanged()│
         │                                 │
         │                                 │
         ▼                                 ▼
┌─────────────────────────────────────────────────────────┐
│         practice_game.dart (GameStateCallback impl)     │
│                                                         │
│  • onGameStateChanged() → updatePracticeGameState()    │
│  • onPlayerStatusChanged() → updatePlayerStatus()      │
│  • onDiscardPileChanged() → updatePracticeGameState()  │
│  • onActionError() → updatePracticeGameState()         │
└─────────────────────────────────────────────────────────┘
         │                                 │
         │                                 │
         │ updatePracticeGameState()       │ RecallGameHelpers
         │                                 │ .updateUIState()
         │                                 │
         └──────────────┬──────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  RecallGameStateUpdater       │
        │  (SSOT - Single Source)        │
        │                                │
        │  updateState(updates)          │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  StateQueueValidator           │
        │                                │
        │  • Schema validation           │
        │  • Queue management            │
        │  • Sequential processing       │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  _applyValidatedUpdates()      │
        │                                │
        │  1. Save card positions        │
        │     (for animations)           │
        │  2. Compute widget slices     │
        │  3. Update StateManager        │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  StateManager                 │
        │                                │
        │  updateModuleState()          │
        │  → notifyListeners()           │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  UI Widgets (ListenableBuilder)│
        │                                │
        │  • Rebuild only when needed    │
        │  • Use computed slices         │
        └───────────────────────────────┘
```

---

## Flow 1: Practice Game State Updates

### Path: `recall_game_round.dart` → `practice_game.dart` → SSOT

**Step-by-step:**

1. **Game Logic Layer** (`recall_game_round.dart`)
   - Game logic executes (e.g., `handleDrawCard()`, `handlePlayCard()`)
   - Modifies local `gameState` object (in-memory)
   - Calls `_stateCallback.onGameStateChanged(batchedUpdate)`
   - **Never directly updates state** - always uses callback interface

2. **Callback Implementation** (`practice_game.dart`)
   - `onGameStateChanged()` receives updates
   - Calls `updatePracticeGameState(updates)`
   - This is a wrapper that ensures all updates go through SSOT

3. **SSOT Entry Point** (`RecallGameStateUpdater`)
   - `updateState(updates)` is called
   - Delegates to `StateQueueValidator` for validation

4. **Validation Layer** (`StateQueueValidator`)
   - Validates updates against schema
   - Queues updates for sequential processing
   - Calls `_applyValidatedUpdates()` after validation

5. **State Application** (`RecallGameStateUpdater._applyValidatedUpdates()`)
   - **CRITICAL**: Saves card positions BEFORE state update (line 120)
   - Computes widget slices based on changed fields
   - Updates `StateManager` with final state

6. **UI Update**
   - `StateManager` notifies listeners
   - Widgets rebuild using computed slices

**Example:**
```dart
// In recall_game_round.dart
void handleDrawCard(String source) {
  // ... game logic ...
  final batchedUpdate = {
    'games': finalGames, // Contains all modifications
  };
  _stateCallback.onGameStateChanged(batchedUpdate); // ← Uses callback
}

// In practice_game.dart
@override
void onGameStateChanged(Map<String, dynamic> updates) {
  updatePracticeGameState(updates); // ← Routes to SSOT
}

// In practice_game.dart
void updatePracticeGameState(Map<String, dynamic> updates) {
  RecallGameStateUpdater.instance.updateState(updates); // ← SSOT
}
```

---

## Flow 2: WebSocket Events State Updates

### Path: WebSocket → Event Handler → Helper → SSOT

**Step-by-step:**

1. **WebSocket Reception**
   - `WSEventManager` receives `recall_game_event` message
   - Event is validated by `RecallGameEventListenerValidator`
   - Validated event is dispatched to registered handlers

2. **Event Handler** (`recall_event_handler_callbacks.dart`)
   - Handlers like `handleGameStateUpdated()`, `handlePlayerStateUpdated()`, etc.
   - Extract relevant data from event
   - Call helper methods: `_updateMainGameState()` or `_updateGameInMap()`

3. **Helper Methods** (`recall_game_helpers.dart`)
   - `_updateMainGameState()` → `RecallGameHelpers.updateUIState()`
   - `_updateGameInMap()` → `RecallGameHelpers.updateUIState()`
   - Both route to SSOT

4. **SSOT Entry Point** (`RecallGameStateUpdater`)
   - Same path as practice game flow
   - `updateState(updates)` → validation → application

**Example:**
```dart
// In recall_event_handler_callbacks.dart
static void handleGameStateUpdated(Map<String, dynamic> data) {
  // ... extract data ...
  _updateMainGameState({
    'currentGameId': gameId,
    'gamePhase': uiPhase,
    'currentPlayer': currentPlayer,
    'currentPlayerStatus': currentPlayerStatus,
  });
}

static void _updateMainGameState(Map<String, dynamic> updates) {
  RecallGameHelpers.updateUIState(updates); // ← Routes to SSOT
}

// In recall_game_helpers.dart
static void updateUIState(Map<String, dynamic> updates) {
  _stateUpdater.updateState(updates); // ← SSOT
}
```

---

## SSOT: RecallGameStateUpdater

### Responsibilities

1. **Validation** (via `StateQueueValidator`)
   - Schema validation for all state fields
   - Type checking
   - Allowed values validation
   - Queue management for sequential processing

2. **Position Saving** (for animations)
   - **CRITICAL**: Saves card positions BEFORE state update (line 120)
   - Ensures animation system can detect movements
   - Works for both practice games and WebSocket events

3. **Widget Slice Computation**
   - Computes optimized slices for widgets
   - Only rebuilds slices when dependencies change
   - Reduces unnecessary UI rebuilds

4. **State Application**
   - Merges updates with current state
   - Updates `StateManager` with final state
   - Triggers UI rebuilds

### Key Method: `_applyValidatedUpdates()`

```dart
void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
  // 1. Check for actual changes (skip if no changes)
  
  // 2. CRITICAL: Save card positions BEFORE state update
  CardAnimationManager().saveCurrentAsPrevious();
  
  // 3. Merge updates with current state
  final newState = {...currentState, ...validatedUpdates};
  
  // 4. Compute widget slices
  final updatedStateWithSlices = _updateWidgetSlices(...);
  
  // 5. Update StateManager
  _stateManager.updateModuleState('recall_game', updatedStateWithSlices);
}
```

---

## Why SSOT is Critical

### 1. **Consistent Position Saving**
- All state updates (practice + WebSocket) save positions before updating
- Ensures animations work correctly for both flows
- Single point of control prevents inconsistencies

### 2. **Unified Validation**
- All updates validated against same schema
- Prevents invalid state from entering system
- Consistent error handling

### 3. **Optimized UI Updates**
- Widget slices computed once per update
- Only affected widgets rebuild
- Performance optimization centralized

### 4. **Maintainability**
- Single point of change for state update logic
- Easy to add new features (e.g., logging, analytics)
- Clear separation of concerns

---

## State Update Rules

### ✅ DO:
- Always use `RecallGameStateUpdater.instance.updateState()` for game state
- Use `RecallGameHelpers.updateUIState()` for WebSocket events
- Use `updatePracticeGameState()` for practice game updates
- Batch related updates together
- Include all affected fields in single update

### ❌ DON'T:
- Never call `StateManager.updateModuleState()` directly for game state
- Never bypass `RecallGameStateUpdater` for game state updates
- Never update state in `recall_game_round.dart` directly
- Never skip position saving (handled automatically by SSOT)

---

## File Locations

### SSOT Core:
- `lib/modules/recall_game/managers/recall_game_state_updater.dart` - SSOT implementation
- `lib/modules/recall_game/utils/state_queue_validator.dart` - Validation layer
- `lib/modules/recall_game/utils/recall_game_helpers.dart` - Helper methods

### Practice Game Flow:
- `lib/modules/recall_game/game_logic/practice_match/shared_logic/recall_game_round.dart` - Game logic
- `lib/modules/recall_game/game_logic/practice_match/practice_game.dart` - Callback implementation

### WebSocket Event Flow:
- `lib/modules/recall_game/managers/recall_event_handler_callbacks.dart` - Event handlers

---

## Summary

**All state updates converge at `RecallGameStateUpdater.updateState()`, which:**

1. Validates updates via `StateQueueValidator`
2. Saves card positions for animations (BEFORE update)
3. Computes widget slices for optimized UI
4. Updates `StateManager` with final state
5. Triggers UI rebuilds via `notifyListeners()`

This ensures **consistent, validated, and optimized state updates** for both practice games and WebSocket events from the Dart backend.

