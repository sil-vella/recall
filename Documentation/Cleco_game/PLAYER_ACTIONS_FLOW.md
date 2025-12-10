# Player Actions Flow - Complete Documentation

## Overview

This document comprehensively details all player actions available in the Cleco game, their flow from the game play screen through Flutter handling, backend Dart processing, and back to the UI. It covers both practice mode (local Dart backend) and multiplayer mode (WebSocket-based Dart backend) implementations.

**Important:** All gameplay logic is handled by the Dart backend. Python backend does NOT handle gameplay - it only handles authentication, room management, and other non-gameplay services.

---

## Table of Contents

1. [Action Entry Points](#action-entry-points)
2. [Action Types](#action-types)
3. [Complete Action Flow](#complete-action-flow)
4. [Practice vs Multiplayer Differences](#practice-vs-multiplayer-differences)
5. [Flutter Game Handling](#flutter-game-handling)
6. [Backend Dart Handling](#backend-dart-handling)
7. [State Updates and UI Refresh](#state-updates-and-ui-refresh)
8. [Action-Specific Details](#action-specific-details)

---

## Action Entry Points

All player actions originate from the **Game Play Screen** (`game_play_screen.dart`), which contains several interactive widgets:

### Widgets That Trigger Actions

1. **MyHandWidget** (`my_hand_widget.dart`)
   - Card selection and play actions
   - Initial peek card selection
   - Same rank play
   - Jack swap card selection
   - Queen peek card selection

2. **DrawPileWidget** (`draw_pile_widget.dart`)
   - Draw card from draw pile

3. **DiscardPileWidget** (`discard_pile_widget.dart`)
   - Collect card from discard pile (if matches collection rank)

4. **OpponentsPanelWidget** (`opponents_panel_widget.dart`)
   - Queen peek on opponent cards
   - Jack swap on opponent cards

5. **GameInfoWidget** (`game_info_widget.dart`)
   - Start match (practice mode only)

---

## Action Types

### Card Actions

| Action | Event Name | Trigger Location | Status Required |
|--------|-----------|------------------|-----------------|
| **Draw Card** | `draw_card` | DrawPileWidget | `drawing_card` |
| **Play Card** | `play_card` | MyHandWidget | `playing_card` |
| **Same Rank Play** | `same_rank_play` | MyHandWidget | `same_rank_window` |
| **Collect from Discard** | `collect_from_discard` | DiscardPileWidget | Any (except `same_rank_window`, `initial_peek`) |

### Special Actions

| Action | Event Name | Trigger Location | Status Required |
|--------|-----------|------------------|-----------------|
| **Initial Peek** | `completed_initial_peek` | MyHandWidget | `initial_peek` |
| **Queen Peek** | `queen_peek` | MyHandWidget, OpponentsPanelWidget | `queen_peek` |
| **Jack Swap** | `jack_swap` | MyHandWidget, OpponentsPanelWidget | `jack_swap` |

### Game Actions

| Action | Event Name | Trigger Location | Status Required |
|--------|-----------|------------------|-----------------|
| **Start Match** | `start_match` | GameInfoWidget | `waiting` (practice only) |
| **Call Final Round** | `call_final_round` | MyHandWidget | `playing_card` (when game active, player's turn, final round not already active) |

---

## Complete Action Flow

### High-Level Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER INTERACTION (UI)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ MyHandWidget │  │ DrawPile     │  │ DiscardPile  │         │
│  │              │  │ Widget       │  │ Widget       │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                 │
│         └──────────────────┼──────────────────┘                 │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              PLAYER ACTION CREATION (Flutter)                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  PlayerAction.playerDraw()                               │  │
│  │  PlayerAction.playerPlayCard()                           │  │
│  │  PlayerAction.sameRankPlay()                             │  │
│  │  PlayerAction.collectFromDiscard()                       │  │
│  │  PlayerAction.completedInitialPeek()                     │  │
│  │  PlayerAction.queenPeek()                                │  │
│  │  PlayerAction.jackSwap()                                 │  │
│  │  PlayerAction.startMatch()                               │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  PlayerAction.execute()                                  │  │
│  │  - Validates action                                      │  │
│  │  - Builds payload                                        │  │
│  │  - Prevents rapid clicks (local flag)                    │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│           EVENT EMISSION (ClecoGameEventEmitter)                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ClecoGameEventEmitter.emit()                            │  │
│  │  - Validates event structure                             │  │
│  │  - Auto-adds player_id (from sessionId)                  │  │
│  │  - Routes based on transport mode:                       │  │
│  │    • Practice → PracticeModeBridge                       │  │
│  │    • Multiplayer → WebSocketManager                      │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
        ▼                                   ▼
┌───────────────────┐            ┌──────────────────────┐
│  PRACTICE MODE    │            │  MULTIPLAYER MODE    │
│                   │            │                      │
│ PracticeModeBridge│            │ WebSocketManager     │
│ .handleEvent()    │            │ .sendCustomEvent()   │
│                   │            │                      │
│ Routes to:        │            │ Routes to:           │
│ ClecoGameModule   │            │ Dart Backend         │
│ .coordinator      │            │ (via WebSocket)      │
│ .handle()         │            │                      │
└────────┬──────────┘            └──────────┬───────────┘
         │                                  │
         │                                  ▼
         │                    ┌──────────────────────────────┐
         │                    │  Dart Backend WebSocket      │
         │                    │  MessageHandler              │
         │                    │  .handleMessage()            │
         │                    │  - Routes to coordinator     │
         │                    └──────────┬───────────────────┘
         │                               │
         └──────────────┬────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│         BACKEND DART PROCESSING (GameEventCoordinator)          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GameEventCoordinator.handle()                           │  │
│  │  - Routes event to appropriate handler                   │  │
│  │  - Gets/Creates ClecoGameRound instance                 │  │
│  │  - Calls round.handle*() methods                        │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ClecoGameRound.handle*()                                │  │
│  │  - handleDrawCard()                                      │  │
│  │  - handlePlayCard()                                      │  │
│  │  - handleSameRankPlay()                                  │  │
│  │  - handleCollectFromDiscard()                            │  │
│  │  - handleQueenPeek()                                     │  │
│  │  - handleJackSwap()                                      │  │
│  │  - handleCallFinalRound()                                │  │
│  │  - Validates action                                      │  │
│  │  - Updates game state                                    │  │
│  │  - Processes game logic                                  │  │
│  │  - Triggers callbacks                                    │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              STATE UPDATE & VALIDATION                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GameStateCallback.onGameStateChanged()                  │  │
│  │  - StateQueueValidator.enqueueUpdate()                   │  │
│  │  - Validates against schema                              │  │
│  │  - Queues for sequential processing                      │  │
│  │  - Applies validated updates to GameStateStore           │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  StateQueueValidator.processQueue()                      │  │
│  │  - Validates each update against _stateSchema            │  │
│  │  - Processes queue sequentially (prevents race conditions)│ │
│  │  - Calls update handler with validated data              │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              STATE BROADCAST                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ServerGameStateCallbackImpl                             │  │
│  │  - Broadcasts 'game_state_updated' event                 │  │
│  │  - Practice: Routes to ClecoEventManager                 │  │
│  │  - Multiplayer: Broadcasts via Dart WebSocket Server     │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
        ▼                                   ▼
┌───────────────────┐            ┌──────────────────────┐
│  PRACTICE MODE    │            │  MULTIPLAYER MODE    │
│                   │            │                      │
│ ClecoEventManager │            │ Dart WebSocket       │
│ .handle*()        │            │ Server broadcasts    │
│                   │            │ to all players       │
│                   │            │                      │
└────────┬──────────┘            └──────────┬───────────┘
         │                                  │
         └──────────────┬───────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│         FLUTTER EVENT RECEPTION & VALIDATION                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  WebSocketManager receives event                         │  │
│  │  → WSEventListener                                       │  │
│  │    → ClecoGameEventListenerValidator._handleDirectEvent()│ │
│  │      - Validates event type against _eventConfigs        │  │
│  │      - Validates event data against schema               │  │
│  │      - Routes to ClecoEventHandlerCallbacks              │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ClecoEventHandlerCallbacks.handleGameStateUpdated()     │  │
│  │  - Parses game state                                     │  │
│  │  - Updates StateManager                                  │  │
│  │  - Syncs widget state slices                             │  │
│  │  - Triggers UI rebuild                                   │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UI UPDATE (Widgets)                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ MyHandWidget │  │ DrawPile     │  │ DiscardPile  │         │
│  │ (rebuilds)   │  │ Widget       │  │ Widget       │         │
│  │              │  │ (rebuilds)   │  │ (rebuilds)   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Practice vs Multiplayer Differences

### Transport Layer

**Practice Mode:**
- Events routed through `PracticeModeBridge.handleEvent()`
- Directly calls `ClecoGameModule.coordinator.handle()`
- No network latency
- State stored locally in `GameStateStore`
- Player ID format: `practice_session_<userId>`

**Multiplayer Mode:**
- Events routed through `WebSocketManager.sendCustomEvent()`
- Sent to Dart backend via WebSocket
- Dart backend `MessageHandler` receives and routes events
- Dart backend processes gameplay and broadcasts to all players
- Network latency considerations
- State synced via WebSocket
- Player ID format: `sessionId` (UUID)

### Event Flow Differences

| Aspect | Practice Mode | Multiplayer Mode |
|--------|--------------|------------------|
| **Transport** | `PracticeModeBridge` | `WebSocketManager` |
| **Backend** | Local Dart (`ClecoGameModule`) | Remote Dart (WebSocket Server) |
| **State Authority** | Local | Backend (Dart) |
| **Broadcast** | `ClecoEventManager` | Dart WebSocket Server broadcast |
| **Latency** | None | Network-dependent |
| **Player ID** | `practice_session_<userId>` | `sessionId` (UUID) |

### Code Paths

**Practice Mode:**
```
PlayerAction.execute()
  → ClecoGameEventEmitter.emit()
    → PracticeModeBridge.handleEvent()
      → ClecoGameModule.coordinator.handle()
        → ClecoGameRound.handle*()
          → GameStateCallback.onGameStateChanged()
            → ClecoEventManager.handle*()
              → ClecoEventHandlerCallbacks.handle*()
                → StateManager.updateModuleState()
                  → Widget rebuild
```

**Multiplayer Mode:**
```
PlayerAction.execute()
  → ClecoGameEventEmitter.emit()
    → WebSocketManager.sendCustomEvent()
      → Dart Backend WebSocket Server
        → MessageHandler.handleMessage()
          → MessageHandler._handleGameEvent()
            → GameEventCoordinator.handle()
              → ClecoGameRound.handle*()
                → GameStateCallback.onGameStateChanged()
                  → StateQueueValidator.enqueueUpdate()
                    → StateQueueValidator.validateUpdate()
                      → ServerGameStateCallbackImpl broadcasts 'game_state_updated'
                        → WebSocketManager receives event
                          → ClecoGameEventListenerValidator._handleDirectEvent()
                            → ClecoEventHandlerCallbacks.handle*()
                              → StateManager.updateModuleState()
                                → Widget rebuild
```

---

## Flutter Game Handling

### PlayerAction Class

**Location:** `lib/modules/cleco_game/managers/player_action.dart`

**Purpose:** Centralized action creation and execution

**Key Methods:**

1. **Action Creation Methods:**
   - `PlayerAction.playerDraw()` - Create draw card action
   - `PlayerAction.playerPlayCard()` - Create play card action
   - `PlayerAction.sameRankPlay()` - Create same rank play action
   - `PlayerAction.collectFromDiscard()` - Create collect action
   - `PlayerAction.completedInitialPeek()` - Create initial peek action
   - `PlayerAction.queenPeek()` - Create queen peek action
   - `PlayerAction.jackSwap()` - Create jack swap action
   - `PlayerAction.startMatch()` - Create start match action
   - `PlayerAction.callFinalRound()` - Create call final round action

2. **Execution:**
   - `PlayerAction.execute()` - Validates and emits event
   - No optimistic state updates (backend is authoritative)
   - Rapid-click prevention via local widget flags

### ClecoGameEventEmitter

**Location:** `lib/modules/cleco_game/managers/validated_event_emitter.dart`

**Purpose:** Validates and routes events to appropriate transport

**Key Features:**
- Event structure validation against `_allowedEventFields`
- Field-level validation using `ClecoEventFieldSpec`:
  - Type validation (String, int, Map, etc.)
  - Pattern matching (e.g., `game_id` must match `room_xxxxx` or `practice_room_xxxxx`)
  - Range validation (e.g., `max_players`: 2-10)
  - Required field checks
- Auto-adds `player_id` from `sessionId` for player actions
- Routes to `PracticeModeBridge` or `WebSocketManager` based on transport mode

### Widget Action Handlers

#### MyHandWidget

**Card Selection Handler:** `_handleCardSelection()`

**Status-Based Routing:**
- `playing_card` → `PlayerAction.playerPlayCard()`
- `same_rank_window` → `PlayerAction.sameRankPlay()`
- `jack_swap` → `PlayerAction.selectCardForJackSwap()` (two-step)
- `queen_peek` → `PlayerAction.queenPeek()`
- `initial_peek` → `PlayerAction.completedInitialPeek()` (after 2 cards)

**Call Final Round Button:**
- Visible when: `isGameActive && isMyTurn && playerStatus == 'playing_card' && !finalRoundActive && !hasPlayerCalledFinalRound`
- Handler: `_handleCallFinalRound()` creates `PlayerAction.callFinalRound()`

**Rapid-Click Prevention:**
- Uses `_isProcessingAction` flag
- Set to `true` before action execution
- Reset after 500ms delay or on error

#### DrawPileWidget

**Draw Handler:** `_handlePileClick()`

**Validation:**
- Checks `playerStatus == 'drawing_card'`
- Validates `currentGameId` exists
- Creates `PlayerAction.playerDraw(pileType: 'draw_pile')`

#### DiscardPileWidget

**Collect Handler:** `_handlePileClick()`

**Validation:**
- Blocks during `same_rank_window` and `initial_peek` phases
- Validates `currentGameId` exists
- Creates `PlayerAction.collectFromDiscard()`

#### OpponentsPanelWidget

**Card Click Handler:** `_handleCardClick()`

**Status-Based Routing:**
- `queen_peek` → `PlayerAction.queenPeek()`
- `jack_swap` → `PlayerAction.selectCardForJackSwap()`

---

## Backend Dart Handling

### GameEventCoordinator

**Location:** `lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart`

**Purpose:** Routes events to appropriate game round handlers

**Key Methods:**
- `handle()` - Main event router
- `_handleStartMatch()` - Initialize game
- `_handleCompletedInitialPeek()` - Process initial peek

**Event Routing:**
```dart
switch (event) {
  case 'draw_card':
    await round.handleDrawCard(source, playerId: playerId, gamesMap: gamesMap);
    break;
  case 'play_card':
    await round.handlePlayCard(cardId, playerId: playerId, gamesMap: gamesMap);
    break;
  case 'same_rank_play':
    await round.handleSameRankPlay(playerId, cardId, gamesMap: gamesMap);
    break;
  case 'collect_from_discard':
    await round.handleCollectFromDiscard(playerId, gamesMap: gamesMap);
    break;
  case 'queen_peek':
    await round.handleQueenPeek(peekingPlayerId, targetCardId, targetPlayerId, gamesMap: gamesMap);
    break;
  case 'jack_swap':
    await round.handleJackSwap(firstCardId, firstPlayerId, secondCardId, secondPlayerId, gamesMap: gamesMap);
    break;
  case 'completed_initial_peek':
    await _handleCompletedInitialPeek(roomId, round, sessionId, data);
    break;
  case 'call_final_round':
  case 'call_cleco':
    await round.handleCallFinalRound(playerId, gamesMap: gamesMap);
    break;
}
```

### ClecoGameRound

**Location:** `lib/modules/cleco_game/backend_core/shared_logic/cleco_game_round.dart`

**Purpose:** Core game logic and state management

**Key Handler Methods:**

1. **handleDrawCard()**
   - Validates source (`deck` or `discard`)
   - Draws card from appropriate pile
   - Adds to player's hand (end of hand, not blank slots)
   - Sets `drawnCard` property (ID-only for broadcast, full for player)
   - Updates player status to `playing_card`
   - Broadcasts state update

2. **handlePlayCard()**
   - Validates card exists in player's hand
   - Checks if card is collection rank (cannot be played)
   - Handles drawn card repositioning (smart blank slot system)
   - Moves card to discard pile
   - Processes special cards (Queen, Jack, etc.)
   - Updates player status
   - Triggers same rank window or special cards window
   - Broadcasts state update

3. **handleSameRankPlay()**
   - Validates rank match with discard pile top card
   - Moves card to discard pile
   - Updates known_cards for all players
   - Does NOT move to next player (same rank window timer handles it)
   - Broadcasts state update

4. **handleCollectFromDiscard()**
   - Validates discard pile has cards
   - Checks if top card matches player's collection rank
   - Moves card to `collection_rank_cards` list
   - Updates player's collection rank if not set
   - Broadcasts state update

5. **handleQueenPeek()**
   - Validates card exists and belongs to target player
   - Adds card to peeking player's `known_cards`
   - Updates player status
   - Broadcasts state update (card details only to peeking player)

6. **handleJackSwap()**
   - Validates both cards exist
   - Swaps cards between players
   - Updates both players' hands
   - Updates known_cards for all players
   - Updates player status
   - Broadcasts state update

7. **handleCompletedInitialPeek()**
   - Validates exactly 2 card IDs provided
   - Gets full card data from `originalDeck`
   - Selects collection rank card (least points, priority order)
   - Stores non-collection card in `known_cards`
   - Adds collection card to `collection_rank_cards`
   - Updates player status
   - Checks if all players completed peek
   - Starts first turn if all completed
   - Broadcasts state update

8. **handleCallFinalRound()**
   - Validates game is active
   - Validates final round not already active
   - Validates player is active and in game
   - Sets `_finalRoundCaller` to calling player's ID
   - Sets `finalRoundActive` flag to `true`
   - Sets `hasCalledFinalRound` flag for calling player
   - Marks calling player as completed in final round
   - Checks if all active players have already completed their turn
   - If all completed, immediately ends final round and calculates winners
   - Otherwise, allows remaining players one last turn
   - Broadcasts state update with final round status
   - When final round completes, calculates winners based on:
     - Lowest points wins
     - If points tie, fewer cards wins
     - If still tied, final round caller wins (if involved in tie)
   - Sets `winType: 'lowest_points'` for winners (not 'final_round' - the win reason is lowest points, final round is just the game phase)

**State Management:**
- Uses `GameStateCallback` interface for state updates
- Calls `onGameStateChanged()` after each action
- Sanitizes `drawnCard` data before broadcast (ID-only for opponents)
- Maintains `games` map structure: `{gameId: {gameData: {game_state: {...}}}}`

---

## State Updates and UI Refresh

### State Update Flow

1. **Backend Processing:**
   - `ClecoGameRound` updates game state
   - Calls `GameStateCallback.onGameStateChanged()`
   - Passes updated `games` map

2. **State Validation & Queueing:**
   - `StateQueueValidator.enqueueUpdate()` - Adds update to queue
   - `StateQueueValidator.validateUpdate()` - Validates against `_stateSchema`:
     - Field existence checks
     - Type validation
     - Allowed values (e.g., `playerStatus` must be in allowed list)
     - Range validation for numbers
     - Required field checks
   - `StateQueueValidator.processQueue()` - Processes queue sequentially
     - Prevents race conditions
     - Ensures state consistency
     - Calls update handler with validated data

3. **State Application:**
   - `ServerGameStateCallbackImpl` applies validated updates to `GameStateStore`
   - Broadcasts `game_state_updated` event to all players

4. **Event Broadcast:**
   - Practice: `ClecoEventManager.handleGameStateUpdated()`
   - Multiplayer: Dart WebSocket Server broadcasts `game_state_updated` via WebSocket

5. **Flutter Event Reception & Validation:**
   - `WebSocketManager` receives event
   - `WSEventListener` routes to `ClecoGameEventListenerValidator`
   - `ClecoGameEventListenerValidator._handleDirectEvent()`:
     - Validates event type exists in `_eventConfigs`
     - Validates event data against schema (required fields)
     - Routes to `ClecoEventHandlerCallbacks`

6. **Flutter Event Handling:**
   - `ClecoEventHandlerCallbacks.handleGameStateUpdated()`
   - Parses game state
   - Updates `StateManager` module state
   - Syncs widget state slices

7. **Widget State Slices:**
   - `myHand` - Current player's hand data
   - `centerBoard` - Draw/discard pile data
   - `opponentsPanel` - Opponent player data
   - `gameInfo` - Game metadata
   - `gamePhase` - Current game phase
   - `playerStatus` - Current player's status

8. **UI Rebuild:**
   - Widgets use `ListenableBuilder` with `StateManager()`
   - Automatically rebuild when state changes
   - Extract relevant data from state slices

### State Structure

```dart
{
  'cleco_game': {
    'games': {
      'gameId': {
        'gameData': {
          'game_id': 'gameId',
          'game_state': {
            'phase': 'playing',
            'players': [...],
            'currentPlayer': {...},
            'drawPile': [...],
            'discardPile': [...],
            'turn_events': [...],
            ...
          }
        }
      }
    },
    'currentGameId': 'gameId',
    'myHand': {
      'cards': [...],
      'playerStatus': 'playing_card',
      ...
    },
    'centerBoard': {
      'drawPileCount': 42,
      'topDiscard': {...},
      ...
    },
    'opponentsPanel': {
      'opponents': [...],
      ...
    },
    ...
  }
}
```

---

## Action-Specific Details

### 1. Draw Card Action

**Flow:**
1. User clicks draw pile (when `playerStatus == 'drawing_card'`)
2. `DrawPileWidget._handlePileClick()` creates `PlayerAction.playerDraw()`
3. Action executes and emits `draw_card` event
4. Backend `handleDrawCard()` processes:
   - Draws from `deck` or `discard` based on `source`
   - Adds card to end of hand (not blank slots)
   - Sets `drawnCard` property
   - Updates status to `playing_card`
5. State update broadcasts to all players
6. UI shows card in hand with glow effect

**Special Handling:**
- Drawn cards always go to end of hand
- `drawnCard` is ID-only for opponents, full data for drawing player
- After drawing, player must play or replace the drawn card

### 2. Play Card Action

**Flow:**
1. User clicks card in hand (when `playerStatus == 'playing_card'`)
2. `MyHandWidget._handleCardSelection()` creates `PlayerAction.playerPlayCard()`
3. Action executes and emits `play_card` event
4. Backend `handlePlayCard()` processes:
   - Validates card exists and is not collection rank
   - Handles drawn card repositioning (fills blank slots intelligently)
   - Moves card to discard pile
   - Processes special cards (Queen, Jack, etc.)
   - Triggers same rank window or special cards window
5. State update broadcasts
6. UI removes card from hand, shows in discard pile

**Special Handling:**
- Collection rank cards cannot be played
- Drawn card repositioning uses smart blank slot system
- Special cards trigger additional windows (same rank, special cards)

### 3. Same Rank Play Action

**Flow:**
1. User clicks card during `same_rank_window` phase
2. `MyHandWidget._handleCardSelection()` creates `PlayerAction.sameRankPlay()`
3. Action executes and emits `same_rank_play` event
4. Backend `handleSameRankPlay()` processes:
   - Validates rank match with discard pile top
   - Moves card to discard pile
   - Updates known_cards
   - Does NOT move to next player (timer handles it)
5. State update broadcasts
6. UI updates discard pile

**Special Handling:**
- Only available during `same_rank_window` phase
- 5-second window after card play
- Multiple players can play same rank cards
- Timer automatically ends window and moves to next player

### 4. Collect from Discard Action

**Flow:**
1. User clicks discard pile (when top card matches collection rank)
2. `DiscardPileWidget._handlePileClick()` creates `PlayerAction.collectFromDiscard()`
3. Action executes and emits `collect_from_discard` event
4. Backend `handleCollectFromDiscard()` processes:
   - Validates top card matches collection rank
   - Moves card to `collection_rank_cards` list
   - Updates collection rank if not set
5. State update broadcasts
6. UI shows card in collection rank cards (stacked display)

**Special Handling:**
- Only works if top discard card matches player's collection rank
- Blocked during `same_rank_window` and `initial_peek` phases
- Computer players automatically check and collect when possible

### 5. Initial Peek Action

**Flow:**
1. User selects 2 cards during `initial_peek` phase
2. `MyHandWidget._handleCardSelection()` tracks selections
3. After 2 cards selected, creates `PlayerAction.completedInitialPeek()`
4. Action executes and emits `completed_initial_peek` event
5. Backend `_handleCompletedInitialPeek()` processes:
   - Gets full card data from `originalDeck`
   - Selects collection rank card (least points, priority)
   - Stores non-collection card in `known_cards`
   - Adds collection card to `collection_rank_cards`
   - Checks if all players completed
   - Starts first turn if all completed
6. State update broadcasts
7. UI shows collection rank card (stacked)

**Special Handling:**
- Exactly 2 cards must be selected
- Collection rank selection uses priority: least points → ace → numbers → king → queen → jack
- Jokers excluded from collection rank
- Game starts after all players complete peek

### 6. Queen Peek Action

**Flow:**
1. User clicks any card (own or opponent) during `queen_peek` status
2. `MyHandWidget` or `OpponentsPanelWidget` creates `PlayerAction.queenPeek()`
3. Action executes and emits `queen_peek` event
4. Backend `handleQueenPeek()` processes:
   - Validates card exists and belongs to target player
   - Adds card to peeking player's `known_cards`
   - Updates player status
5. State update broadcasts (card details only to peeking player)
6. UI shows peeked card details

**Special Handling:**
- Only available when Queen is played
- Can peek at any player's card
- Card details only visible to peeking player
- Updates known_cards for AI decision making

### 7. Jack Swap Action

**Flow:**
1. User clicks first card during `jack_swap` status
2. `MyHandWidget` or `OpponentsPanelWidget` calls `PlayerAction.selectCardForJackSwap()`
3. User clicks second card
4. `PlayerAction.selectCardForJackSwap()` creates and executes `PlayerAction.jackSwap()`
5. Action executes and emits `jack_swap` event
6. Backend `handleJackSwap()` processes:
   - Validates both cards exist
   - Swaps cards between players
   - Updates both players' hands
   - Updates known_cards for all players
7. State update broadcasts
8. UI shows swapped cards

**Special Handling:**
- Two-step selection process
- Can swap any two cards (own or opponent)
- Both cards must be selected before execution
- Updates known_cards for all players (they see the swap)

### 8. Start Match Action

**Flow:**
1. User clicks "Start Match" button (practice mode, `waiting` phase)
2. `GameInfoWidget._handleStartMatch()` calls `GameCoordinator.startMatch()`
3. `GameCoordinator` creates `PlayerAction.startMatch()`
4. Action executes and emits `start_match` event
5. Backend `_handleStartMatch()` processes:
   - Creates computer players (if needed)
   - Builds deck using `YamlDeckFactory`
   - Deals 4 cards to each player
   - Initializes game state
   - Sets all players to `initial_peek` status
6. State update broadcasts
7. UI shows initial peek phase

**Special Handling:**
- Only available in practice mode
- Only room owner can start match
- Auto-creates computer players to fill to `maxPlayers`
- Uses YAML deck configuration for testing mode support

### 9. Call Final Round Action

**Flow:**
1. User clicks "Call Final Round" button (when game active, player's turn, final round not already active)
2. `MyHandWidget._handleCallFinalRound()` creates `PlayerAction.callFinalRound()`
3. Action executes and emits `call_final_round` event
4. Backend `handleCallFinalRound()` processes:
   - Validates game is active
   - Validates final round not already active
   - Validates player is active and in game
   - Sets `_finalRoundCaller` to calling player's ID
   - Sets `finalRoundActive` flag to `true`
   - Sets `hasCalledFinalRound` flag for calling player
   - Marks calling player as completed in final round
   - Checks if all active players have already completed their turn
   - If all completed, immediately ends final round and calculates winners
   - Otherwise, allows remaining players one last turn
5. State update broadcasts with final round status
6. When final round completes (all active players have had their turn):
   - Calculates points for all active players
   - Sorts by lowest points, then fewer cards
   - Applies tie-breaking: if points and cards tie, final round caller wins (if involved in tie)
   - Sets `winType: 'lowest_points'` for winners
   - Ends game and shows winners modal

**Special Handling:**
- Only available when game is active, it's player's turn, and final round hasn't been called
- Each player can only call final round once
- After calling, all active players get one last turn
- Winner determination uses lowest points (not "final round" as win reason)
- Final round caller only matters for tie-breaking, not as the win reason itself
- Win reason displayed in winners modal: "Lowest Points" (not "Final Round")

---

## Error Handling

### Frontend Error Handling

**Rapid-Click Prevention:**
- Widgets use `_isProcessingAction` flag
- Prevents multiple action executions
- Reset after 500ms delay or on error

**Validation:**
- Status checks before action creation
- Game ID validation
- Card existence checks

**Error Feedback:**
- `SnackBar` messages for user feedback
- Error messages from backend via `cleco_error` event
- Action errors stored in state for display

### Backend Error Handling

**Validation:**
- Card existence validation
- Player status validation
- Game state validation
- Action legality checks

**Error Responses:**
- Sends `{event}_error` event to player
- Includes error message and timestamp
- Does not update game state on error

**State Consistency:**
- All state updates are atomic
- Failed actions do not modify state
- State sanitization before broadcast (security)

---

## Security Considerations

### Card Data Sanitization

**Drawn Cards:**
- Opponents see ID-only format: `{cardId: '...', suit: '?', rank: '?', points: 0}`
- Drawing player sees full data: `{cardId: '...', suit: '...', rank: '...', points: ...}`
- Sanitization happens before every broadcast

**Known Cards:**
- Computer players maintain `known_cards` for AI decisions
- Human players' `known_cards` updated based on game events
- Memory system with probability-based forgetting (difficulty-dependent)

### Validation Layers

**Flutter → Backend (Outgoing Events):**
- `ClecoGameEventEmitter._validateAndParseEventData()`:
  - Validates event type exists in `_allowedEventFields`
  - Validates each field using `ClecoEventFieldSpec`:
    - Type checks (String, int, Map, etc.)
    - Pattern matching (e.g., `game_id`, `card_id` patterns)
    - Range validation (e.g., `max_players`: 2-10)
    - Allowed values (e.g., `source`: 'deck' or 'discard')
  - Auto-injects `player_id` from `sessionId` for player actions

**Backend Processing:**
- `MessageHandler.handleMessage()` - Validates event field exists
- `GameEventCoordinator.handle()`:
  - Validates player is in a room
  - Extracts `player_id` from session (player ID = sessionId)
  - Validates required fields (e.g., `card_id`, `game_id`)
- `ClecoGameRound.handle*()` - Validates action legality:
  - Card existence validation
  - Player status validation
  - Game state validation
  - Action legality checks

**State Updates:**
- `StateQueueValidator.validateUpdate()`:
  - Validates against `_stateSchema`
  - Field existence, type, allowed values, range validation
  - Sequential queue processing prevents race conditions

**Backend → Flutter (Incoming Events):**
- `ClecoGameEventListenerValidator._validateEventData()`:
  - Validates event type exists in `_eventConfigs`
  - Validates required fields are present
  - Schema validation

### Action Validation

**Server-Side Authority:**
- Dart backend validates all actions
- Frontend validation is advisory only
- Backend can reject invalid actions

**Player ID Verification:**
- `player_id` auto-added from `sessionId` by `ClecoGameEventEmitter`
- `GameEventCoordinator._getPlayerIdFromSession()` verifies player exists in game
- Prevents action spoofing

**State Validation:**
- `StateQueueValidator` ensures all state updates are validated
- Sequential processing prevents race conditions
- Schema validation ensures state consistency

---

## Performance Considerations

### State Update Optimization

**Partial Updates:**
- Only changed fields included in updates
- Widget slices minimize rebuild scope
- `ListenableBuilder` only rebuilds when relevant state changes

**Broadcast Efficiency:**
- State sanitization before broadcast
- Only necessary data included
- Efficient serialization

### Action Processing

**Async Processing:**
- All handlers are `async`
- Non-blocking state updates
- Timer-based actions (same rank window, special cards window)

**Computer Player Actions:**
- YAML-based decision making
- Configurable delays
- Efficient AI decision trees

---

## Testing Considerations

### Practice Mode

**Advantages:**
- No network dependency
- Faster iteration
- Easier debugging
- Local state inspection

**Use Cases:**
- Development and testing
- Single-player gameplay
- AI testing
- Rule validation

### Multiplayer Mode

**Advantages:**
- Real network conditions
- Multi-player testing
- WebSocket reliability testing
- Dart backend integration testing

**Use Cases:**
- Production gameplay
- Multi-player scenarios
- Network condition testing
- Dart backend validation

**Note:** Python backend does NOT handle gameplay. It only handles authentication, room management, and other non-gameplay services. All gameplay logic is processed by the Dart backend.

---

## Future Enhancements

### Potential Additions

1. **Call Cleco Action:**
   - Backend logic exists (same as `call_final_round`)
   - Currently uses same handler as `call_final_round`
   - May be renamed or consolidated in future

2. **Replace Drawn Card Action:**
   - Backend logic exists
   - Needs UI implementation
   - Allow replacing drawn card with hand card

3. **Play Drawn Card Action:**
   - Backend logic exists
   - Needs UI implementation
   - Allow playing drawn card directly

4. **Action History:**
   - Track all actions for replay
   - Debugging tool
   - Game analysis

5. **Action Undo (Practice Mode):**
   - Allow undoing actions in practice mode
   - Useful for learning and testing
   - Not available in multiplayer

---

## Summary

The Cleco game player action system is a comprehensive, well-architected flow that handles all game interactions from UI to backend and back. Key features:

- **Centralized Action Management:** `PlayerAction` class provides consistent action creation and execution
- **Transport Abstraction:** Same code works for both practice and multiplayer modes
- **Dart Backend Authority:** All gameplay actions validated and processed by Dart backend (Python does NOT handle gameplay)
- **Multi-Layer Validation:** 
  - Event validation at emission (Flutter)
  - Event validation at reception (Backend)
  - State validation with queue system
  - Schema-based validation throughout
- **State Consistency:** 
  - Sequential queue processing prevents race conditions
  - Atomic state updates with proper sanitization
  - Schema validation ensures state integrity
- **Security:** 
  - Card data sanitization (ID-only for opponents)
  - Player ID verification
  - Server-side action validation
- **Performance:** 
  - Optimized state updates
  - Async processing
  - Sequential queue prevents state conflicts
- **Error Handling:** Comprehensive validation and error feedback at each layer

The system is designed for extensibility, with clear separation of concerns and well-defined interfaces between components. All gameplay logic is handled by the Dart backend, ensuring consistency between practice and multiplayer modes.
