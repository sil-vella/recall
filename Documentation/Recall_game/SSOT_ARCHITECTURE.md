# SSOT Architecture: Player Action Routing

## Table of Contents
1. [Overview](#overview)
2. [Architecture Principles](#architecture-principles)
3. [Action Flow Comparison](#action-flow-comparison)
4. [Code Evidence](#code-evidence)
5. [Log Evidence](#log-evidence)
6. [Handler Methods (SSOT)](#handler-methods-ssot)
7. [Decision Layer Differences](#decision-layer-differences)
8. [Benefits](#benefits)
9. [Architecture Diagram](#architecture-diagram)
10. [Summary](#summary)

---

## Overview

The Recall card game implements a **Single Source of Truth (SSOT)** architecture where all player actions (human and computer) route through identical game logic handlers. The only difference between player types is in the **decision-making layer** - humans make manual decisions through the UI, while computers use YAML-based AI logic.

This document provides comprehensive evidence that both player types converge on the same game logic handlers, ensuring consistent rules, validation, and state management across all players.

---

## Architecture Principles

### Core SSOT Design
- **Single Entry Point**: All actions route through [`GameRound._route_action()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L1110-L1175)
- **Shared Handlers**: Identical methods handle validation, state updates, and game flow
- **Consistent Logic**: Same rules apply to all players regardless of type
- **Centralized Updates**: Single `update_known_cards()` method for all players

### Key Benefits
- **Fairness**: Computer players cannot "cheat" with different rules
- **Maintainability**: Changes to game logic update all players automatically
- **Consistency**: Identical validation and state management
- **Testability**: Test handlers once, applies to all player types

---

## Action Flow Comparison

### Human Player Flow
```
Frontend (Flutter) 
  → WebSocket Event (e.g., 'play_card')
    → GameEventCoordinator.handle_game_event() 
      → GameEventCoordinator._handle_player_action_through_round()
        → GameRound.on_player_action()
          → GameRound._route_action()
            → GameRound._handle_play_card() ✅ SSOT
```

### Computer Player Flow
```
GameRound._handle_computer_player_turn()
  → GameRound._handle_computer_action_with_yaml()
    → ComputerPlayerFactory.get_play_card_decision() (YAML decision)
      → GameRound._execute_computer_decision_yaml()
        → GameRound._route_action()
          → GameRound._handle_play_card() ✅ SSOT (Same handler!)
```

**Key Observation**: Both flows converge at `_route_action()` and use identical handler methods.

---

## Code Evidence

### A. Human Player Entry Point

**File**: [`game_event_coordinator.py:61-133`](../../python_base_04/core/modules/recall_game/game_logic/game_event_coordinator.py#L61-L133)

Human actions come through WebSocket events:

```python
def handle_game_event(self, session_id: str, event_name: str, data: dict):
    # Routes all events to game round
    if event_name == 'play_card':
        data_with_action = {**data, 'action': 'play_card'}
        return self._handle_player_action_through_round(session_id, data_with_action)
    # ... other events

def _handle_player_action_through_round(self, session_id: str, data: dict):
    game_round = game.get_round()
    action_result = game_round.on_player_action(session_id, data)  ← Entry to game round
    return action_result
```

### B. Computer Player Entry Point

**File**: [`game_round.py:507-633`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L507-L633)

Computer actions come through turn handler:

```python
def _handle_computer_action_with_yaml(self, computer_player, difficulty, event_name):
    # Get YAML decision
    decision = self._computer_player_factory.get_play_card_decision(...)
    
    # Execute decision using SAME routing as humans
    self._execute_computer_decision_yaml(decision, computer_player, event_name)

def _execute_computer_decision_yaml(self, decision, computer_player, event_name):
    if event_name == 'draw_card':
        # Use existing _route_action logic (same as human players) ← Comment confirms SSOT
        action_data = {'source': source, 'player_id': computer_player.player_id}
        success = self._route_action('draw_from_deck', computer_player.player_id, action_data)
    
    elif event_name == 'play_card':
        # Use existing _route_action logic (same as human players) ← Comment confirms SSOT
        action_data = {'card_id': card_id, 'player_id': computer_player.player_id}
        success = self._route_action('play_card', computer_player.player_id, action_data)
```

### C. Central Router (SSOT Entry)

**File**: [`game_round.py:1110-1175`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L1110-L1175)

Both human and computer actions converge here:

```python
def _route_action(self, action: str, user_id: str, action_data: Dict[str, Any]) -> bool:
    """Route action to appropriate handler and return result"""
    if action == 'draw_from_deck':
        return self._handle_draw_from_pile(user_id, action_data)  ← SSOT
    elif action == 'play_card':
        return self._handle_play_card(user_id, action_data)  ← SSOT
    elif action == 'same_rank_play':
        return self._handle_same_rank_play(user_id, action_data)  ← SSOT
    elif action == 'jack_swap':
        return self._handle_jack_swap(user_id, action_data)  ← SSOT
    elif action == 'queen_peek':
        return self._handle_queen_peek(user_id, action_data)  ← SSOT
```

---

## Log Evidence

### Example 1: Computer Player Draw Card
**Log Lines 633-634** (from actual game session):
```
Routing action: draw_from_deck user_id: computer_room_4cd84e71_0 action_data: {...}
_handle_draw_from_pile called for player computer_room_4cd84e71_0
```

### Example 2: Computer Player Play Card
**Log Lines 744-745** (from actual game session):
```
Routing action: play_card user_id: computer_room_4cd84e71_0 action_data: {...}
PLAY_CARD: Starting play_card action for computer_room_4cd84e71_0
```

### Example 3: Computer Player Same Rank
**Log Lines 968-973** (from actual game session):
```
Found card card_COPaIRIHiL72_89342409 for same rank play in player computer_room_4cd84e71_2 hand
Same rank validation: played_card_rank='jack', last_card_rank='jack'
Same rank validation: Ranks match, allowing play
```

**Key Observation**: The log messages show the **exact same handler methods** being called for computer players as would be called for human players.

---

## Handler Methods (SSOT)

All these handlers are shared between human and computer players:

| Handler Method | Purpose | Location |
|---|---|---|
| [`_handle_draw_from_pile()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L1839) | Draw card from deck/discard | Line 1839 |
| [`_handle_play_card()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L2000) | Play card to discard pile | Line 2000 |
| [`_handle_same_rank_play()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L2179) | Play matching rank card | Line 2179 |
| [`_handle_jack_swap()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L1165) | Execute jack swap special | Referenced |
| [`_handle_queen_peek()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L1167) | Execute queen peek special | Referenced |

### Shared Logic in Each Handler:
1. **Validation**: Card exists, player's turn, valid action
2. **State Updates**: Hand modifications, pile updates
3. **Known Cards Updates**: [`update_known_cards()`](../../python_base_04/core/modules/recall_game/game_logic/game_round.py#L2547) for all players
4. **Special Card Detection**: Check for special powers
5. **Phase Transitions**: Same rank window, special play window
6. **Event Broadcasting**: WebSocket updates to all clients

---

## Decision Layer Differences

### Human Players
- **Decision Source**: User input via Flutter UI
- **Timing**: Manual, user-controlled
- **Process**: 
  1. User clicks button in UI
  2. Frontend sends WebSocket event
  3. Backend receives and routes to handler

### Computer Players
- **Decision Source**: YAML configuration + AI logic
- **Timing**: Automated with delays (1.5s for medium difficulty)
- **Process**:
  1. Turn manager detects computer player
  2. YAML factory analyzes game state
  3. Returns decision (e.g., which card to play)
  4. Decision routed to **same handler** as humans

**File**: [`computer_player_factory.py`](../../python_base_04/core/modules/recall_game/utils/computer_player_factory.py)

```python
def get_play_card_decision(self, difficulty, game_state, available_cards):
    # YAML-based decision making
    # Returns: {'action': 'play_card', 'card_id': 'card_xxx', ...}
    # This decision is then passed to _route_action() - same as human
```

---

## Benefits

### ✅ Consistency
- All players follow identical game rules
- No divergence between human/computer logic
- Single place to fix bugs

### ✅ Maintainability
- Changes to game rules update all players automatically
- No need to sync multiple implementations
- Reduced code duplication

### ✅ Testability
- Test handlers once, applies to all player types
- Computer players validate the same logic humans use
- Easier to verify correctness

### ✅ Fairness
- Computer players can't "cheat" with different rules
- Same validation, same constraints
- Identical state updates

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    DECISION LAYER                            │
│  ┌──────────────────────┐    ┌──────────────────────┐      │
│  │   Human Player       │    │  Computer Player     │      │
│  │   (Manual Input)     │    │  (YAML AI Decision)  │      │
│  └──────────┬───────────┘    └──────────┬───────────┘      │
│             │                           │                    │
│             │  Decision                 │  Decision          │
│             │  (card_id, action)        │  (card_id, action) │
│             └───────────┬───────────────┘                    │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   ROUTING LAYER (SSOT)                       │
│                                                              │
│              GameRound._route_action()                       │
│                                                              │
│  Routes all actions to appropriate handlers regardless      │
│  of whether player is human or computer                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  GAME LOGIC LAYER (SSOT)                     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │_handle_draw_ │  │_handle_play_ │  │_handle_same_ │     │
│  │from_pile()   │  │card()        │  │rank_play()   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                              │
│  • Validation        • State Updates    • Event Broadcasting│
│  • Hand Management   • Known Cards      • Phase Transitions │
│  • Pile Operations   • Special Cards    • Turn Progression  │
└─────────────────────────────────────────────────────────────┘
```

---

## Code Comments Confirming SSOT

The codebase explicitly documents this architecture:

**Line 628**: `# Use existing _route_action logic (same as human players)`
**Line 691**: `# Use existing _route_action logic (same as human players)`  
**Line 759**: `# Wire directly to existing action handlers - computers perform the same actions`

These comments were intentionally added to document the SSOT design.

---

## Summary

**Confirmed**: The Recall game implements a proper SSOT architecture where:

1. ✅ **Human and computer players use identical game logic handlers**
2. ✅ **Only the decision-making layer differs** (manual vs YAML)
3. ✅ **All actions route through `_route_action()` to shared handlers**
4. ✅ **Code comments explicitly document this design**
5. ✅ **Server logs confirm same handlers are called for all players**

The architecture ensures that whether a card is played by a human clicking a button or a computer following YAML rules, the **exact same validation, state updates, and game flow logic** is executed. This is a textbook example of proper SSOT design.

---

## Related Documentation

- [Game Architecture Overview](./recall_game_architecture_documentation.md)
- [WebSocket Module Architecture](./websocket_recall_module_architecture.md)
- [Game Play Documentation](./Game_play.md)
- [Dual Update Pattern](./DUAL_UPDATE_PATTERN.md)

---

*This document serves as the authoritative reference for understanding how the SSOT architecture ensures consistent game logic across all player types in the Recall card game.*
