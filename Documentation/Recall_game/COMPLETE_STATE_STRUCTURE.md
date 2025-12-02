# Complete Recall Game State Structure

This document provides a comprehensive breakdown of the entire nested state structure for the Recall Game module in Flutter Base 05.

## Table of Contents
1. [Top-Level State Structure](#top-level-state-structure)
2. [Games Map Structure](#games-map-structure)
3. [Game Data Structure](#game-data-structure)
4. [Game State Data Structure](#game-state-data-structure)
5. [Player Data Structure](#player-data-structure)
6. [Card Data Structure](#card-data-structure)
7. [Widget Slices](#widget-slices)
8. [User ID and Session Mapping](#user-id-and-session-mapping)
9. [WebSocket Session Data](#websocket-session-data)
10. [State Update Flow](#state-update-flow)

---

## Top-Level State Structure

The main state is stored in `StateManager` under the key `'recall_game'`. It can exist in two forms:

### Legacy Map-Based State (Currently Used)
```dart
Map<String, dynamic> recallGameState = {
  // ============================================
  // CONNECTION STATE
  // ============================================
  'isLoading': bool,                    // Loading operation in progress
  'isConnected': bool,                  // WebSocket connection status
  'currentRoomId': String,              // Current room ID (e.g., 'room_123' or 'practice_room_123')
  'currentRoom': Map<String, dynamic>?, // Current room info (nullable)
  'isInRoom': bool,                     // Whether user is currently in a room

  // ============================================
  // ROOM MANAGEMENT
  // ============================================
  'myCreatedRooms': List<Map<String, dynamic>>,  // Rooms created by current user
  'players': List<Map<String, dynamic>>,         // Legacy players list (deprecated)

  // ============================================
  // GAME STATE
  // ============================================
  'currentGameId': String,              // ID of currently active game
  'games': Map<String, dynamic>,        // Games map (see Games Map Structure below)
  'joinedGames': List<Map<String, dynamic>>,  // List of games user has joined
  'totalJoinedGames': int,              // Total count of joined games
  'joinedGamesTimestamp': String,       // ISO timestamp of last joined games update

  // ============================================
  // UI CONTROL STATE
  // ============================================
  'showCreateRoom': bool,               // Show create room UI
  'showRoomList': bool,                 // Show room list UI

  // ============================================
  // WIDGET SLICES (Computed from games map)
  // ============================================
  'actionBar': Map<String, dynamic>,    // Action bar widget slice
  'statusBar': Map<String, dynamic>,    // Status bar widget slice
  'myHand': Map<String, dynamic>,       // My hand widget slice
  'centerBoard': Map<String, dynamic>,  // Center board widget slice
  'opponentsPanel': Map<String, dynamic>, // Opponents panel widget slice
  'gameInfo': Map<String, dynamic>,     // Game info widget slice
  'joinedGamesSlice': Map<String, dynamic>, // Joined games widget slice

  // ============================================
  // PLAYER-SPECIFIC STATE (Derived from games)
  // ============================================
  'myDrawnCard': Map<String, dynamic>?, // Currently drawn card (nullable)
  'cards_to_peek': List<Map<String, dynamic>>, // Cards available to peek
  'playerStatus': String,               // Current user's player status
  'myScore': int,                       // Current user's score
  'isMyTurn': bool,                     // Whether it's current user's turn
  'myCardsToPeek': List<Map<String, dynamic>>, // Cards user can peek at

  // ============================================
  // GAME METADATA (Derived from games)
  // ============================================
  'gamePhase': String,                  // Current game phase ('waiting', 'playing', 'ended')
  'gameStatus': String,                 // Game status ('inactive', 'active', 'ended')
  'isRoomOwner': bool,                  // Whether current user is room owner
  'isGameActive': bool,                 // Whether game is currently active
  'canPlayCard': bool,                  // Whether user can play a card
  'canCallRecall': bool,                // Whether user can call recall
  'currentPlayer': Map<String, dynamic>?, // Current player whose turn it is (nullable)
  'playerCount': int,                   // Number of players in current game
  'turnNumber': int,                    // Current turn number
  'roundNumber': int,                   // Current round number

  // ============================================
  // TURN EVENTS & ANIMATIONS
  // ============================================
  'turn_events': List<Map<String, dynamic>>, // Turn events for animations

  // ============================================
  // MESSAGES & INSTRUCTIONS
  // ============================================
  'messages': {
    'session': List<Map<String, dynamic>>,  // Session-level messages
    'rooms': Map<String, List<Map<String, dynamic>>>, // Room-specific messages
  },
  'instructions': {
    'isVisible': bool,
    'title': String,
    'content': String,
  },
  'actionError': Map<String, dynamic>?, // Last action error (nullable)

  // ============================================
  // PRACTICE MODE STATE
  // ============================================
  'practiceUser': {                     // Practice mode user data (nullable)
    'isPracticeUser': bool,
    'userId': String,
    'userName': String,
  },

  // ============================================
  // METADATA
  // ============================================
  'lastUpdated': String,                // ISO timestamp of last update
}
```

### Immutable State (Future Migration Target)
```dart
RecallGameState {
  // Connection state
  bool isLoading;
  bool isConnected;
  String currentRoomId;
  bool isInRoom;
  
  // Game state
  String currentGameId;
  GamesMap games;                       // Immutable games map
  List<Map<String, dynamic>> joinedGames;
  int totalJoinedGames;
  
  // Widget slices (computed from games)
  MyHandState myHand;
  CenterBoardState centerBoard;
  OpponentsPanelState opponentsPanel;
  
  // UI state
  List<CardData> cardsToPeek;
  List<Map<String, dynamic>> turnEvents;
  Map<String, dynamic>? actionError;
  Map<String, dynamic> messages;
  Map<String, dynamic> instructions;
  
  // Metadata
  String lastUpdated;
}
```

---

## Games Map Structure

The `games` map is the **Single Source of Truth (SSOT)** for all game data. It's indexed by game ID.

```dart
Map<String, dynamic> games = {
  'game_id_1': {
    // ============================================
    // GAME DATA (SSOT - Single Source of Truth)
    // ============================================
    'gameData': {
      'game_id': String,                // Game ID (same as map key)
      'owner_id': String,               // User ID of room owner
      'game_type': String,              // 'practice' or 'multiplayer'
      'game_name': String?,             // Optional game name
      'max_size': int,                  // Maximum players (typically 4)
      'min_players': int,               // Minimum players (typically 2)
      
      // ============================================
      // GAME STATE (Core game logic state)
      // ============================================
      'game_state': {
        // See Game State Data Structure below
      },
    },
    
    // ============================================
    // WIDGET-SPECIFIC DATA (Derived from gameData)
    // ============================================
    'myHandCards': List<Map<String, dynamic>>,  // Current user's hand cards
    'myDrawnCard': Map<String, dynamic>?,       // Currently drawn card (nullable)
    'isMyTurn': bool,                           // Whether it's current user's turn
    'canPlayCard': bool,                        // Whether user can play a card
    'selectedCardIndex': int,                   // Selected card index (-1 if none)
    'turn_events': List<Map<String, dynamic>>?, // Turn events for animations (optional)
    
    // ============================================
    // GAME METADATA
    // ============================================
    'gameStatus': String,                // 'inactive', 'active', 'ended'
    'isRoomOwner': bool,                 // Whether current user is room owner
    'isInGame': bool,                    // Whether user is in this game
    'joinedAt': String,                  // ISO timestamp when user joined
    'lastUpdated': String,               // ISO timestamp of last update
  },
  
  'game_id_2': { /* same structure */ },
  // ... more games
}
```

---

## Game Data Structure

The `gameData` object contains the complete game information. This is the SSOT for game state.

```dart
Map<String, dynamic> gameData = {
  'game_id': String,                    // Unique game identifier
  'owner_id': String,                   // User ID of the room/game owner
  'game_type': String,                  // 'practice' or 'multiplayer'
  'game_name': String?,                 // Optional game name
  'max_size': int,                      // Maximum number of players (typically 4)
  'min_players': int,                   // Minimum players to start (typically 2)
  
  // ============================================
  // GAME STATE (Core game logic)
  // ============================================
  'game_state': {
    // See Game State Data Structure below
  },
}
```

---

## Game State Data Structure

The `game_state` object contains the core game logic state. This is managed by the backend game engine.

```dart
Map<String, dynamic> game_state = {
  // ============================================
  // GAME PHASE & STATUS
  // ============================================
  'phase': String,                      // 'waiting_for_players', 'dealing_cards', 
                                        // 'player_turn', 'recall_phase', 'game_ended'
  'status': String,                     // 'inactive', 'active', 'ended'
  'gameType': String,                   // 'practice' or 'normal'
  
  // ============================================
  // PLAYERS
  // ============================================
  'players': List<Map<String, dynamic>>, // Array of player objects (see Player Data Structure)
  'currentPlayer': Map<String, dynamic>?, // Current player whose turn it is (nullable)
  'playerCount': int,                   // Number of players
  'maxPlayers': int,                    // Maximum players (typically 4)
  
  // ============================================
  // CARD PILES
  // ============================================
  'discardPile': List<Map<String, dynamic>>, // Discard pile cards (see Card Data Structure)
  'drawPile': List<Map<String, dynamic>>,    // Draw pile cards (may be ID-only for hidden cards)
  'originalDeck': List<Map<String, dynamic>>?, // Original deck (for card lookup, optional)
  
  // ============================================
  // GAME PROGRESSION
  // ============================================
  'recallCalledBy': String?,            // Player ID who called recall (nullable)
  'lastPlayedCard': Map<String, dynamic>?, // Last card played (nullable, see Card Data Structure)
  'winners': List<Map<String, dynamic>>, // Game end winners (empty until game ends)
  
  // ============================================
  // TURN & ROUND TRACKING
  // ============================================
  'turnNumber': int?,                   // Current turn number (optional)
  'roundNumber': int?,                  // Current round number (optional)
  
  // ============================================
  // ADDITIONAL GAME STATE
  // ============================================
  // ... other game-specific fields as needed
}
```

---

## Player Data Structure

Each player in the `game_state.players` array has the following structure:

```dart
Map<String, dynamic> player = {
  // ============================================
  // IDENTIFICATION
  // ============================================
  'id': String,                         // Player ID (matches user ID for human players)
  'name': String,                       // Player display name
  'userId': String?,                    // User ID (for human players, same as id)
  'user_id': String?,                   // Alternative user ID field (legacy)
  
  // ============================================
  // PLAYER TYPE
  // ============================================
  'isHuman': bool,                      // true for human players, false for computer
  'isActive': bool,                     // Whether player is active in game
  'difficulty': String?,                // Computer player difficulty ('easy', 'medium', 'hard')
  
  // ============================================
  // PLAYER STATUS
  // ============================================
  'status': String,                     // 'waiting', 'ready', 'playing', 'finished', etc.
  'isCurrentPlayer': bool?,             // Whether it's this player's turn (optional)
  
  // ============================================
  // HAND & CARDS
  // ============================================
  'hand': List<Map<String, dynamic>>,   // Player's hand cards (see Card Data Structure)
  'drawnCard': Map<String, dynamic>?,   // Currently drawn card (nullable)
  'cardsToPeek': List<Map<String, dynamic>>, // Cards player can peek at
  
  // ============================================
  // KNOWN CARDS (Memory/Information Tracking)
  // ============================================
  'known_cards': {                      // Nested map: playerId -> cardId -> CardData
    'player_id_1': {
      'card_id_1': Map<String, dynamic>, // Card data (see Card Data Structure)
      'card_id_2': Map<String, dynamic>,
    },
    'player_id_2': {
      // ... more known cards
    },
  },
  
  // ============================================
  // COLLECTION & SCORING
  // ============================================
  'collection_rank': String?,           // Collection rank (e.g., 'A', 'K', 'Q')
  'collection_rank_cards': List<Map<String, dynamic>>, // Cards in collection rank
  'points': int,                        // Total points (legacy field)
  'score': int,                         // Total score (preferred field)
  'totalPoints': int,                   // Alternative points field
  
  // ============================================
  // VISIBILITY (Legacy)
  // ============================================
  'visible_cards': List<Map<String, dynamic>>, // Visible cards (legacy, may be deprecated)
}
```

---

## Card Data Structure

Cards are represented with the following structure:

```dart
Map<String, dynamic> card = {
  'cardId': String,                     // Unique card identifier (e.g., 'card_1', 'ace_spades')
  'id': String?,                        // Alternative ID field (legacy, same as cardId)
  'suit': String,                       // Card suit ('hearts', 'diamonds', 'clubs', 'spades', '?' for hidden)
  'rank': String,                       // Card rank ('A', '2'-'10', 'J', 'Q', 'K', '?' for hidden)
  'points': int,                        // Card point value (0-10)
  'specialPower': String?,              // Special power (e.g., 'queen_peek', 'jack_swap', nullable)
}
```

### Hidden Cards
When a card is face-down or not visible to the player, it may be represented as:
```dart
{
  'cardId': 'card_123',
  'suit': '?',
  'rank': '?',
  'points': 0,
}
```

### ID-Only Cards
In some contexts (like draw pile), cards may be represented as ID-only:
```dart
{
  'cardId': 'card_123',
}
```

---

## Widget Slices

Widget slices are computed views of the state optimized for specific widgets. They are automatically recomputed when their dependencies change.

### Action Bar Slice
```dart
Map<String, dynamic> actionBar = {
  'showStartButton': bool,              // Show start game button
  'canPlayCard': bool,                  // Can play a card
  'canCallRecall': bool,                // Can call recall
  'isGameStarted': bool,                // Game is started
}
```

**Dependencies**: `currentGameId`, `games`, `isRoomOwner`, `isGameActive`, `isMyTurn`

### Status Bar Slice
```dart
Map<String, dynamic> statusBar = {
  'currentPhase': String,               // Current game phase
  'turnInfo': String,                   // Turn information string
  'playerCount': int,                   // Number of players
  'gameStatus': String,                 // Game status
  'connectionStatus': String,           // Connection status ('connected' or 'disconnected')
  'playerStatus': String,               // Current user's player status
}
```

**Dependencies**: `currentGameId`, `games`, `gamePhase`, `isGameActive`

### My Hand Slice
```dart
Map<String, dynamic> myHand = {
  'cards': List<Map<String, dynamic>>,  // Cards in hand
  'selectedIndex': int,                 // Selected card index (-1 if none)
  'canSelectCards': bool,               // Can select cards
  'turn_events': List<Map<String, dynamic>>, // Turn events for animations
  'playerStatus': String,               // Current user's player status
}
```

**Dependencies**: `currentGameId`, `games`, `isMyTurn`, `turn_events`

### Center Board Slice
```dart
Map<String, dynamic> centerBoard = {
  'drawPileCount': int,                 // Number of cards in draw pile
  'topDiscard': Map<String, dynamic>?,  // Top discard card (nullable)
  'topDraw': Map<String, dynamic>?,     // Top draw card (nullable)
  'canDrawFromDeck': bool,              // Can draw from deck
  'canTakeFromDiscard': bool,           // Can take from discard pile
  'playerStatus': String,               // Current user's player status
}
```

**Dependencies**: `currentGameId`, `games`, `gamePhase`, `isGameActive`, `discardPile`, `drawPile`

### Opponents Panel Slice
```dart
Map<String, dynamic> opponentsPanel = {
  'opponents': List<Map<String, dynamic>>, // Opponent players (excludes current user)
  'currentTurnIndex': int,              // Index of current player in opponents list (-1 if not found)
  'turn_events': List<Map<String, dynamic>>, // Turn events for animations
  'currentPlayerStatus': String,        // Current player's status
}
```

**Dependencies**: `currentGameId`, `games`, `currentPlayer`, `turn_events`

### Game Info Slice
```dart
Map<String, dynamic> gameInfo = {
  'currentGameId': String,              // Current game ID
  'currentSize': int,                   // Current number of players
  'maxSize': int,                       // Maximum players
  'gamePhase': String,                  // Game phase
  'gameStatus': String,                 // Game status
  'isRoomOwner': bool,                  // Is room owner
  'isInGame': bool,                     // Is in game
}
```

**Dependencies**: `currentGameId`, `games`, `gamePhase`, `isGameActive`

### Joined Games Slice
```dart
Map<String, dynamic> joinedGamesSlice = {
  'games': List<Map<String, dynamic>>,  // List of joined games
  'totalGames': int,                    // Total count
  'timestamp': String,                  // ISO timestamp
  'isLoadingGames': bool,               // Loading state
}
```

**Dependencies**: `joinedGames`, `totalJoinedGames`, `joinedGamesTimestamp`

---

## User ID and Session Mapping

### User ID Resolution

The current user ID is resolved in this order:

1. **Practice Mode**: Check `recall_game.practiceUser.userId` if `practiceUser.isPracticeUser == true`
2. **Multiplayer Mode**: Fall back to `login.userId` from login state

```dart
// Helper function: RecallEventHandlerCallbacks.getCurrentUserId()
String getCurrentUserId() {
  // 1. Check practice user
  final practiceUser = recallGameState['practiceUser'];
  if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
    return practiceUser['userId'];
  }
  
  // 2. Fall back to login state
  final loginState = StateManager().getModuleState('login');
  return loginState['userId'] ?? '';
}
```

### Player ID Mapping

- **Human Players**: `player.id == player.userId == user.id` (all the same)
- **Computer Players**: `player.id` is generated (e.g., 'computer_player_1'), no `userId`

### Session ID Mapping

#### Practice Mode
- Session ID format: `'practice_session_<userId>'`
- User ID extraction: `sessionId.replaceFirst('practice_session_', '')`

#### Multiplayer Mode
- Session ID is provided by WebSocket server
- User ID is retrieved via `server.getUserIdForSession(sessionId)`

---

## WebSocket Session Data

### Session Structure (Backend)

```dart
// Backend session management
Map<String, dynamic> session = {
  'sessionId': String,                  // Unique session identifier
  'userId': String,                     // User ID associated with session
  'roomId': String?,                    // Current room ID (nullable)
  'connectedAt': String,                // ISO timestamp
  'lastActivity': String,               // ISO timestamp
}
```

### Room Structure (Backend)

```dart
Map<String, dynamic> room = {
  'roomId': String,                     // Unique room identifier
  'ownerId': String,                    // User ID of room owner
  'gameId': String,                     // Game ID (same as roomId for recall game)
  'gameType': String,                   // 'practice' or 'multiplayer'
  'maxSize': int,                       // Maximum players
  'players': List<String>,              // List of user IDs in room
  'sessions': List<String>,             // List of session IDs in room
  'createdAt': String,                  // ISO timestamp
  'status': String,                     // 'waiting', 'active', 'ended'
}
```

### Session-to-Player Mapping

The backend maps sessions to players using:

1. **User ID Lookup**: `userId = server.getUserIdForSession(sessionId)`
2. **Player Matching**: Find player in `game_state.players` where `player.userId == userId`
3. **Fallback**: If no match, try matching by room owner

```dart
// Backend helper: GameEventCoordinator._getPlayerIdFromSession()
String? getPlayerIdFromSession(String sessionId, String roomId) {
  // 1. Get user ID from session
  final userId = server.getUserIdForSession(sessionId);
  
  // 2. Find player with matching userId
  final players = gameState['players'];
  for (final player in players) {
    if (player['userId'] == userId || player['user_id'] == userId) {
      return player['id'];
    }
  }
  
  // 3. Fallback: match by room owner
  final ownerId = server.getRoomOwner(roomId);
  if (ownerId == userId) {
    // Find first human player (likely owner)
    for (final player in players) {
      if (player['isHuman'] == true) {
        return player['id'];
      }
    }
  }
  
  return null;
}
```

---

## State Update Flow

### 1. State Update Entry Point

```dart
// Update state via RecallGameStateUpdater
RecallGameStateUpdater.instance.updateState({
  'games': updatedGames,
  'currentGameId': newGameId,
  // ... other updates
});
```

### 2. Validation

State updates are validated by `StateQueueValidator`:
- Schema validation
- Type checking
- Required field validation
- Value constraints

### 3. Widget Slice Computation

After validation, widget slices are recomputed based on dependencies:

```dart
// Only slices with changed dependencies are recomputed
if (changedFields.any(_widgetDependencies['myHand'].contains)) {
  state['myHand'] = _computeMyHandSlice(state);
}
```

### 4. State Manager Update

Final state is stored in `StateManager`:

```dart
StateManager().updateModuleState('recall_game', updatedState);
```

### 5. Widget Rebuild

Widgets listening to state changes automatically rebuild:
- `StreamBuilder` widgets listen to state streams
- Widget slices trigger rebuilds only when their dependencies change

---

## Key Design Principles

### Single Source of Truth (SSOT)
- **Games Map**: `games[gameId].gameData.game_state` is the SSOT for game state
- **Widget Slices**: Computed from SSOT, never stored separately
- **Player Status**: Derived from `game_state.players[]`, not stored separately

### Immutability (Future Migration)
- Current: Map-based state (mutable)
- Target: Immutable state objects (`RecallGameState`, `GamesMap`, `GameData`, etc.)
- Benefits: Predictable updates, easier debugging, better performance

### Dependency Tracking
- Widget slices only recompute when their dependencies change
- Reduces unnecessary rebuilds
- Improves performance

### User ID Resolution
- Practice mode: Uses practice user data
- Multiplayer mode: Uses login state
- Consistent API: `RecallEventHandlerCallbacks.getCurrentUserId()`

---

## Example: Complete State for Active Game

```dart
{
  'isLoading': false,
  'isConnected': true,
  'currentRoomId': 'room_abc123',
  'isInRoom': true,
  'currentGameId': 'room_abc123',
  
  'games': {
    'room_abc123': {
      'gameData': {
        'game_id': 'room_abc123',
        'owner_id': 'user_123',
        'game_type': 'multiplayer',
        'max_size': 4,
        'min_players': 2,
        'game_state': {
          'phase': 'player_turn',
          'status': 'active',
          'gameType': 'normal',
          'players': [
            {
              'id': 'user_123',
              'name': 'Alice',
              'userId': 'user_123',
              'isHuman': true,
              'isActive': true,
              'status': 'playing',
              'hand': [
                {'cardId': 'card_1', 'suit': 'hearts', 'rank': 'A', 'points': 1},
                {'cardId': 'card_2', 'suit': 'spades', 'rank': 'K', 'points': 10},
              ],
              'score': 11,
              'known_cards': {},
            },
            {
              'id': 'computer_player_1',
              'name': 'Computer 1',
              'isHuman': false,
              'isActive': true,
              'status': 'playing',
              'hand': [
                {'cardId': 'card_3', 'suit': '?', 'rank': '?', 'points': 0},
                {'cardId': 'card_4', 'suit': '?', 'rank': '?', 'points': 0},
              ],
              'score': 0,
              'difficulty': 'medium',
            },
          ],
          'currentPlayer': {
            'id': 'user_123',
            'name': 'Alice',
            // ... same structure as player above
          },
          'discardPile': [
            {'cardId': 'card_5', 'suit': 'diamonds', 'rank': '7', 'points': 7},
          ],
          'drawPile': [
            {'cardId': 'card_6'},
            {'cardId': 'card_7'},
          ],
          'recallCalledBy': null,
          'lastPlayedCard': {
            'cardId': 'card_5',
            'suit': 'diamonds',
            'rank': '7',
            'points': 7,
          },
          'winners': [],
          'playerCount': 2,
          'maxPlayers': 4,
        },
      },
      'myHandCards': [
        {'cardId': 'card_1', 'suit': 'hearts', 'rank': 'A', 'points': 1},
        {'cardId': 'card_2', 'suit': 'spades', 'rank': 'K', 'points': 10},
      ],
      'isMyTurn': true,
      'canPlayCard': true,
      'gameStatus': 'active',
      'isRoomOwner': true,
      'isInGame': true,
      'joinedAt': '2024-01-15T10:30:00.000Z',
    },
  },
  
  'myHand': {
    'cards': [
      {'cardId': 'card_1', 'suit': 'hearts', 'rank': 'A', 'points': 1},
      {'cardId': 'card_2', 'suit': 'spades', 'rank': 'K', 'points': 10},
    ],
    'selectedIndex': -1,
    'canSelectCards': true,
    'playerStatus': 'playing',
  },
  
  'gamePhase': 'playing',
  'gameStatus': 'active',
  'isMyTurn': true,
  'playerStatus': 'playing',
  'myScore': 11,
  
  'lastUpdated': '2024-01-15T10:35:00.000Z',
}
```

---

## WebSocket Session ID Storage

### Overview

The WebSocket session ID is **NOT stored in the `recall_game` module state**. Instead, it is stored in the **`websocket` module state** under the `sessionData` field.

### Storage Location

The session ID is stored in the `websocket` module state:

```dart
// WebSocket module state structure
Map<String, dynamic> websocketState = {
  'isConnected': bool,
  'currentRoomId': String?,
  'currentRoomInfo': Map<String, dynamic>?,
  'sessionData': Map<String, dynamic>?,  // Session ID is here
  'joinedRooms': List<Map<String, dynamic>>,
  'totalJoinedRooms': int,
  'joinedRoomsTimestamp': String?,
  'joinedRoomsSessionId': String?,
  'lastUpdated': String,
}
```

### Session Data Structure

When the `connected` event is received, the session data is stored as:

```dart
'sessionData': {
  'session_id': String,        // The WebSocket session ID
  'user_id': String?,          // User ID (if authenticated)
  'status': String,            // Connection status ('connected', etc.)
  'timestamp': String,         // ISO timestamp of connection
  // ... other session metadata from server
}
```

### Accessing Session ID

#### Method 1: Using StateManager Directly

```dart
// Get WebSocket state
final wsState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};

// Get session data
final sessionData = wsState['sessionData'] as Map<String, dynamic>?;

// Extract session ID
final sessionId = sessionData?['session_id'] as String?;
```

#### Method 2: Using WebSocketStateUpdater Helper

```dart
import 'package:recall/core/managers/websockets/websocket_state_validator.dart';

// Get session data using helper
final sessionData = WebSocketStateUpdater.getSessionData();

// Extract session ID
final sessionId = sessionData?['session_id'] as String?;
```

#### Method 3: Direct Socket Access (Runtime Only)

```dart
// In ValidatedEventEmitter or similar
final wsManager = WebSocketManager();
final sessionId = wsManager.socket?.id ?? 'unknown_session';
```

### Practice Mode Session ID

In practice mode, the session ID is also stored in the practice bridge:

```dart
// In PracticeModeBridge
String? _currentSessionId;  // Format: 'practice_session_<userId>'

// Access via getter
final sessionId = practiceModeBridge.currentSessionId;
```

### When Session Data is Updated

The `sessionData` field is updated in the following scenarios:

1. **Connection Established**: When the `connected` event is received, session data is stored
2. **Session Data Event**: When a `session_data` event is received, session data is updated
3. **Connection Lost**: When connection is lost, `sessionData` is cleared to `null`

### Example: Complete WebSocket State with Session ID

```dart
{
  'isConnected': true,
  'currentRoomId': 'room_abc123',
  'currentRoomInfo': {
    'room_id': 'room_abc123',
    'owner_id': 'user_123',
    'max_size': 4,
    'player_count': 2,
  },
  'sessionData': {
    'session_id': '550e8400-e29b-41d4-a716-446655440000',  // UUID v4
    'user_id': 'user_123',
    'status': 'connected',
    'timestamp': '2024-01-15T10:30:00.000Z',
    'client_id': 'flutter_app_1705312200000',
  },
  'joinedRooms': [
    {
      'room_id': 'room_abc123',
      'joined_at': '2024-01-15T10:30:00.000Z',
    },
  ],
  'totalJoinedRooms': 1,
  'joinedRoomsTimestamp': '2024-01-15T10:30:00.000Z',
  'joinedRoomsSessionId': '550e8400-e29b-41d4-a716-446655440000',
  'lastUpdated': '2024-01-15T10:35:00.000Z',
}
```

### Important Notes

1. **Not in recall_game state**: The session ID is **NOT** stored in the `recall_game` module state. It's only in the `websocket` module state.

2. **Session ID vs User ID**: 
   - **Session ID**: Unique per WebSocket connection (UUID v4)
   - **User ID**: Authenticated user identifier (may be same as session ID if not authenticated)

3. **Practice Mode**: In practice mode, session ID format is `'practice_session_<userId>'` and is stored in both the practice bridge and can be derived from the user ID.

4. **Access Pattern**: Always use `WebSocketStateUpdater.getSessionData()` or access via `StateManager().getModuleState('websocket')['sessionData']` for consistent access.

5. **Lifetime**: Session ID exists from connection until disconnect. It's cleared when connection is lost.

---

## Notes

- **Legacy vs Immutable**: The codebase is transitioning from map-based state to immutable state objects. Currently, map-based state is used, but immutable models exist for future migration.
- **Widget Slices**: Always computed from SSOT, never stored as primary data.
- **User ID**: Always use `RecallEventHandlerCallbacks.getCurrentUserId()` for consistent resolution.
- **Player ID**: For human players, player ID equals user ID. For computer players, player ID is generated.
- **Session ID**: Format differs between practice mode (`practice_session_<userId>`) and multiplayer mode (server-provided). **Session ID is stored in `websocket` module state, not in `recall_game` state.**

