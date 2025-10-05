import 'package:recall/tools/logging/logger.dart';

import '../../../core/managers/state_manager.dart';
import '../utils/recall_game_helpers.dart';

/// Dedicated event handlers for Recall game events
/// Contains all the business logic for processing specific event types
class RecallEventHandlerCallbacks {
  static const bool LOGGING_SWITCH = true;

  // ========================================
  // HELPER METHODS TO REDUCE DUPLICATION
  // ========================================
  
  /// Get current games map from state manager
  static Map<String, dynamic> _getCurrentGamesMap() {
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  }
  
  /// Update a specific game in the games map and sync to global state
  static void _updateGameInMap(String gameId, Map<String, dynamic> updates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      
      // Merge updates with current game data
      currentGames[gameId] = {
        ...currentGame,
        ...updates,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      // Update global state
      RecallGameHelpers.updateUIState({
        'games': currentGames,
      });
    }
  }
  
  /// Update game data within a game's gameData structure
  static void _updateGameData(String gameId, Map<String, dynamic> dataUpdates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // Update the game data
      final updatedGameData = Map<String, dynamic>.from(currentGameData);
      updatedGameData.addAll(dataUpdates);
      
      // Update the game with new game data
      _updateGameInMap(gameId, {
        'gameData': updatedGameData,
      });
    }
  }
  
  /// Get current user ID from login state
  static String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    return loginState['userId']?.toString() ?? '';
  }
  
  /// Check if current user is room owner for a specific game
  static bool _isCurrentUserRoomOwner(Map<String, dynamic> gameData) {
    final currentUserId = _getCurrentUserId();
    return gameData['owner_id']?.toString() == currentUserId;
  }
  
  /// Add a game to the games map with standard structure
  static void _addGameToMap(String gameId, Map<String, dynamic> gameData, {String? gameStatus}) {
    final currentGames = _getCurrentGamesMap();
    
    // Determine game status (phase is now managed in main state only)
    final status = gameStatus ?? gameData['game_state']?['status']?.toString() ?? 'inactive';
    
    // Preserve existing joinedAt timestamp if game already exists
    final existingGame = currentGames[gameId] as Map<String, dynamic>?;
    final joinedAt = existingGame?['joinedAt'] ?? DateTime.now().toIso8601String();
    
    // Add/update the game in the games map
    currentGames[gameId] = {
      'gameData': gameData,  // Single source of truth
      // Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice
      'gameStatus': status,
      'isRoomOwner': _isCurrentUserRoomOwner(gameData),
      'isInGame': true,
      'joinedAt': joinedAt,  // Preserve original joinedAt timestamp
      // Removed lastUpdated - causes unnecessary state updates
    };
    
    // Update global state
    RecallGameHelpers.updateUIState({
      'games': currentGames,
    });
  }
  
  /// Update main game state (non-game-specific fields)
  static void _updateMainGameState(Map<String, dynamic> updates) {
    RecallGameHelpers.updateUIState(updates);
    // Removed lastUpdated - causes unnecessary state updates
  }

  /// Add a session message to the message board
  static void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Get current session messages
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentMessages = currentState['messages'] as Map<String, dynamic>? ?? {};
    final sessionMessages = List<Map<String, dynamic>>.from(currentMessages['session'] as List<dynamic>? ?? []);
    
    // Add new message
    sessionMessages.add(entry);
    if (sessionMessages.length > 200) sessionMessages.removeAt(0);
    
    // Update state
    RecallGameHelpers.updateUIState({
      'messages': {
        'session': sessionMessages,
        'rooms': currentMessages['rooms'] ?? {},
      },
    });
  }

  // ========================================
  // PUBLIC EVENT HANDLERS
  // ========================================

  /// Handle recall_new_player_joined event
  static void handleRecallNewPlayerJoined(Map<String, dynamic> data) {
    final roomId = data['room_id']?.toString() ?? '';
    final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    
    // Update the game data with the new game state using helper method
    _updateGameData(roomId, {
      'game_state': gameState,
    });
    
    // Add session message about new player
    _addSessionMessage(
      level: 'info',
      title: 'Player Joined',
      message: '${joinedPlayer['name']} joined the game',
      data: joinedPlayer,
    );
  }

  /// Handle recall_joined_games event
  static void handleRecallJoinedGames(Map<String, dynamic> data) {
    // final sessionId = data['session_id']?.toString() ?? '';
    final games = data['games'] as List<dynamic>? ?? [];
    final totalGames = data['total_games'] ?? 0;
    
    // Update the games map with the joined games data using helper methods
    for (final gameData in games) {
      final gameId = gameData['game_id']?.toString() ?? '';
      if (gameId.isNotEmpty) {
        // Add/update the game in the games map using helper method
        _addGameToMap(gameId, gameData);
      }
    }
    
    // Set currentGameId to the first joined game (if any)
    String? currentGameId;
    if (games.isNotEmpty) {
      currentGameId = games.first['game_id']?.toString();
    }
    
    // Update recall game state with joined games information using helper method
    _updateMainGameState({
      'joinedGames': games.cast<Map<String, dynamic>>(),
      'totalJoinedGames': totalGames,
      'joinedGamesTimestamp': DateTime.now().toIso8601String(),
      if (currentGameId != null) 'currentGameId': currentGameId,
    });
    
    // Add session message about joined games
    _addSessionMessage(
      level: 'info',
      title: 'Games Updated',
      message: 'You are now in $totalGames game${totalGames != 1 ? 's' : ''}',
      data: {'total_games': totalGames, 'games': games},
    );
  }

  /// Handle game_started event
  static void handleGameStarted(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final startedBy = data['started_by']?.toString() ?? '';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Extract player data
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Handle currentPlayer - it might be a Map (player object) or String (player ID) or null
    Map<String, dynamic>? currentPlayer;
    final currentPlayerRaw = gameState['currentPlayer'];
    if (currentPlayerRaw is Map<String, dynamic>) {
      currentPlayer = currentPlayerRaw;
    } else if (currentPlayerRaw is String && currentPlayerRaw.isNotEmpty) {
      // If currentPlayer is a string (player ID), find the player object in the players list
      currentPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentPlayerRaw,
        orElse: () => <String, dynamic>{},
      );
      if (currentPlayer.isEmpty) {
        currentPlayer = null;
      }
    } else {
      currentPlayer = null;
    }
    
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    Map<String, dynamic>? myPlayer;
    try {
      myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserId,
      );
    } catch (e) {
      myPlayer = null;
    }
    
    // Extract opponent players (excluding current user)
    final opponents = players.where((player) => player['id'] != currentUserId).toList();
    
    // Update the game data with the new game state using helper method
    _updateGameData(gameId, {
      'game_state': gameState,
    });
    
    // Update the game with game started information using helper method
    _updateGameInMap(gameId, {
      // Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice
      'gameStatus': gameState['status'] ?? 'active',
      'isGameActive': true,
      'isRoomOwner': startedBy == currentUserId,  // ✅ Set ownership based on who started the game
      
      // Update game-specific fields for widget slices
      'drawPileCount': drawPile.length,
      'discardPile': discardPile,
      'opponentPlayers': opponents.cast<Map<String, dynamic>>(),
      'currentPlayerIndex': currentPlayer != null ? players.indexOf(currentPlayer) : -1,
      'myHandCards': myPlayer?['hand'] ?? [],
      'selectedCardIndex': -1,
    });
    
    // Add session message about game started
    _addSessionMessage(
      level: 'success',
      title: 'Game Started',
      message: 'Game $gameId has started!',
      data: {
        'game_id': gameId,
        'started_by': startedBy,
        'game_state': gameState,
      },
    );
  }

  /// Handle turn_started event
  static void handleTurnStarted(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    // final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final playerId = data['player_id']?.toString() ?? '';
    final playerStatus = data['player_status']?.toString() ?? 'unknown';
    final turnTimeout = data['turn_timeout'] as int? ?? 30;
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this turn is for the current user
    final isMyTurn = playerId == currentUserId;
    
    if (isMyTurn) {
      
      // Update UI state to show it's the current user's turn using helper method
      _updateMainGameState({
        'isMyTurn': true,
        'turnTimeout': turnTimeout,
        'turnStartTime': DateTime.now().toIso8601String(),
        'playerStatus': playerStatus,
        'statusBar': {
          'currentPhase': 'my_turn',
          'turnTimer': turnTimeout,
          'turnStartTime': DateTime.now().toIso8601String(),
          'playerStatus': playerStatus,
        },
      });
      
      // Add session message about turn started
      _addSessionMessage(
        level: 'info',
        title: 'Your Turn',
        message: 'It\'s your turn! You have $turnTimeout seconds to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'turn_timeout': turnTimeout,
          'is_my_turn': true,
        },
      );
    } else {
      
      // Update UI state to show it's another player's turn using helper method
      _updateMainGameState({
        'isMyTurn': false,
        'statusBar': {
          'currentPhase': 'opponent_turn',
          'currentPlayer': playerId,
        },
      });
      
      // Add session message about opponent's turn
      _addSessionMessage(
        level: 'info',
        title: 'Opponent\'s Turn',
        message: 'It\'s $playerId\'s turn to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'is_my_turn': false,
        },
      );
    }
  }

  /// Handle game_state_updated event
  static void handleGameStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final ownerId = data['owner_id']?.toString(); // Extract owner_id from main payload
    
    // 🔍 DEBUG: Log the extracted values
    Logger().info('🔍 handleGameStateUpdated DEBUG:', isOn: LOGGING_SWITCH);
    Logger().info('  gameId: $gameId', isOn: LOGGING_SWITCH);
    Logger().info('  ownerId: $ownerId', isOn: LOGGING_SWITCH);
    Logger().info('  data keys: ${data.keys.toList()}', isOn: LOGGING_SWITCH);
    final roundNumber = data['round_number'] as int? ?? 1;
    final currentPlayer = data['current_player'];
    final currentPlayerStatus = data['current_player_status']?.toString() ?? 'unknown';
    final roundStatus = data['round_status']?.toString() ?? 'active';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Extract pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = drawPile.length;
    final discardPileCount = discardPile.length;
    
    // 🎯 CRITICAL: Extract players and find current user's hand
    final players = gameState['players'] as List<dynamic>? ?? [];
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    Map<String, dynamic>? myPlayer;
    try {
      myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserId,
      );
    } catch (e) {
      myPlayer = null;
    }
    
    Logger().info('🔍 handleGameStateUpdated: Found myPlayer: ${myPlayer != null}', isOn: LOGGING_SWITCH);
    if (myPlayer != null) {
      Logger().info('🔍 handleGameStateUpdated: myPlayer hand: ${myPlayer['hand']}', isOn: LOGGING_SWITCH);
    }
    
    // Check if game exists in games map, if not add it
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      // Add the game to the games map with the complete game state (including owner_id)
      _addGameToMap(gameId, {
        'game_id': gameId,
        'game_state': gameState,
        'owner_id': ownerId, // Pass owner_id so _isCurrentUserRoomOwner can access it
      });
    } else {
      // Update existing game's game_state
      Logger().info('🔍 Updating existing game: $gameId', isOn: LOGGING_SWITCH);
      _updateGameData(gameId, {
        'game_state': gameState,
      });
      
      // Update owner_id and recalculate isRoomOwner at the top level
      if (ownerId != null) {
        final currentUserId = _getCurrentUserId();
        Logger().info('🔍 Updating owner_id: $ownerId, currentUserId: $currentUserId', isOn: LOGGING_SWITCH);
        Logger().info('🔍 Setting isRoomOwner: ${ownerId == currentUserId}', isOn: LOGGING_SWITCH);
        _updateGameInMap(gameId, {
          'owner_id': ownerId,
          'isRoomOwner': ownerId == currentUserId,
        });
      } else {
        Logger().info('🔍 ownerId is null, not updating ownership', isOn: LOGGING_SWITCH);
      }
    }
    
    // Update the main game state with the new information using helper method
    _updateMainGameState({
      'currentGameId': gameId,  // Ensure currentGameId is set
      'gamePhase': gameState['phase'] ?? 'playing',
      'isGameActive': true,
      'roundNumber': roundNumber,
      'currentPlayer': currentPlayer,
      'currentPlayerStatus': currentPlayerStatus,
      'roundStatus': roundStatus,
    });
    
    // Also update joinedGames list for lobby widgets (if this is a new game)
    final currentGamesForJoined = _getCurrentGamesMap();
    if (currentGamesForJoined.containsKey(gameId)) {
      final gameInMap = currentGamesForJoined[gameId] as Map<String, dynamic>? ?? {};
      final gameData = gameInMap['gameData'] as Map<String, dynamic>? ?? {};
      
      // Get current joinedGames list
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentJoinedGames = List<Map<String, dynamic>>.from(currentState['joinedGames'] as List<dynamic>? ?? []);
      
      // Check if this game is already in joinedGames
      final existingIndex = currentJoinedGames.indexWhere((game) => game['game_id'] == gameId);
      
      if (existingIndex >= 0) {
        // Update existing game
        currentJoinedGames[existingIndex] = gameData;
      } else {
        // Add new game to joinedGames
        currentJoinedGames.add(gameData);
      }
      
      // Update joinedGames state
      _updateMainGameState({
        'joinedGames': currentJoinedGames,
        'totalJoinedGames': currentJoinedGames.length,
        'joinedGamesTimestamp': DateTime.now().toIso8601String(),
      });
    }
    
    // Update the games map with additional information using helper method
    final updateData = {
      'drawPileCount': drawPileCount,
      'discardPileCount': discardPileCount,
      'discardPile': discardPile,
      'players': players,  // Include all players data
    };
    
    // 🎯 CRITICAL: If we found the current user's player data, extract their hand
    if (myPlayer != null) {
      final myHand = myPlayer['hand'] as List<dynamic>? ?? [];
      updateData['myHandCards'] = myHand;
      Logger().info('🔍 handleGameStateUpdated: Setting myHandCards with ${myHand.length} cards', isOn: LOGGING_SWITCH);
    }
    
    _updateGameInMap(gameId, updateData);
    
    // Add session message about game state update
    _addSessionMessage(
      level: 'info',
      title: 'Game State Updated',
      message: 'Round $roundNumber - $currentPlayer is $currentPlayerStatus',
      data: {
        'game_id': gameId,
        'round_number': roundNumber,
        'current_player': currentPlayer,
        'current_player_status': currentPlayerStatus,
        'round_status': roundStatus,
      },
    );
  }

  /// Handle game_state_partial_update event
  static void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    Logger().info("handleGameStatePartialUpdate: $data", isOn: LOGGING_SWITCH);
    final gameId = data['game_id']?.toString() ?? '';
    final changedProperties = data['changed_properties'] as List<dynamic>? ?? [];
    final partialGameState = data['partial_game_state'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Get current game state to merge with partial updates
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      return; // Game not found, ignore partial update
    }
    
    final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
    final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final currentGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Merge partial updates with current game state
    final updatedGameState = Map<String, dynamic>.from(currentGameState);
    updatedGameState.addAll(partialGameState);
    
    // Update the game data with merged state using helper method
    _updateGameData(gameId, {
      'game_state': updatedGameState,
    });
    
    // Update specific UI fields based on changed properties
    final updates = <String, dynamic>{};
    
    for (final property in changedProperties) {
      final propName = property.toString();
      
      switch (propName) {
        case 'phase':
          // Update main state only - game map phase will be derived from main state
          _updateMainGameState({
            'gamePhase': updatedGameState['phase'] ?? 'playing',
          });
          break;
        case 'current_player_id':
          updates['currentPlayer'] = updatedGameState['current_player_id'];
          break;
        case 'draw_pile':
          final drawPile = updatedGameState['drawPile'] as List<dynamic>? ?? [];
          updates['drawPileCount'] = drawPile.length;
          break;
        case 'discard_pile':
          final discardPile = updatedGameState['discardPile'] as List<dynamic>? ?? [];
          updates['discardPileCount'] = discardPile.length;
          updates['discardPile'] = discardPile;
          break;
        case 'recall_called_by':
          updates['recallCalledBy'] = updatedGameState['recall_called_by'];
          break;
        case 'game_ended':
          updates['isGameActive'] = !(updatedGameState['game_ended'] == true);
          break;
        case 'winner':
          updates['winner'] = updatedGameState['winner'];
          break;
      }
    }

    Logger().info("updates: $updates", isOn: LOGGING_SWITCH);
    // Apply UI updates if any
    if (updates.isNotEmpty) {
      _updateGameInMap(gameId, updates);
    }
    
    // Add session message about partial update
    _addSessionMessage(
      level: 'info',
      title: 'Game State Updated',
      message: 'Updated: ${changedProperties.join(', ')}',
      data: {
        'game_id': gameId,
        'changed_properties': changedProperties,
        'partial_updates': partialGameState,
      },
    );
  }

  /// Handle player_state_updated event
  static void handlePlayerStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final playerId = data['player_id']?.toString() ?? '';
    final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this update is for the current user
    final isMyUpdate = playerId == currentUserId;
    
    if (isMyUpdate) {
      
      // Extract player data fields
      final hand = playerData['hand'] as List<dynamic>? ?? [];
      // final visibleCards = playerData['visibleCards'] as List<dynamic>? ?? [];
      final drawnCard = playerData['drawnCard'] as Map<String, dynamic>?;
      final score = playerData['score'] as int? ?? 0;
      final status = playerData['status']?.toString() ?? 'unknown';
      final isCurrentPlayer = playerData['isCurrentPlayer'] == true;
      // final hasCalledRecall = playerData['hasCalledRecall'] == true;
      
      // Update the main game state with player information using helper method
      _updateMainGameState({
        'playerStatus': status,
        'myScore': score,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
      });
      
      // Update the games map with hand information using helper method
      _updateGameInMap(gameId, {
        'myHandCards': hand,
        'selectedCardIndex': -1,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
      });
      
      // Add session message about player state update
      _addSessionMessage(
        level: 'info',
        title: 'Player State Updated',
        message: 'Hand: ${hand.length} cards, Score: $score, Status: $status',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'hand_size': hand.length,
          'score': score,
          'status': status,
          'is_current_player': isCurrentPlayer,
        },
      );
    } else {
      
      // Get current opponents and update them using helper method
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      if (currentGames.containsKey(gameId)) {
        final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final currentOpponents = currentGameData['opponentPlayers'] as List<dynamic>? ?? [];
        
        // Update opponent information in the games map using helper method
        _updateGameData(gameId, {
          'opponentPlayers': currentOpponents.map((opponent) {
            if (opponent['id'] == playerId) {
              return {
                ...opponent,
                'hand': playerData['hand'] ?? [],
                'score': playerData['score'] ?? 0,
                'status': playerData['status'] ?? 'unknown',
                'hasCalledRecall': playerData['hasCalledRecall'] ?? false,
                'drawnCard': playerData['drawnCard'],
              };
            }
            return opponent;
          }).toList(),
        });
      }
    }
  }

  /// Handle queen_peek_result event
  static void handleQueenPeekResult(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final peekingPlayerId = data['peeking_player_id']?.toString() ?? '';
    final targetPlayerId = data['target_player_id']?.toString() ?? '';
    final peekedCard = data['peeked_card'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this peek result is for the current user
    final isMyPeekResult = peekingPlayerId == currentUserId;
    
    if (isMyPeekResult) {
      // Extract card details
      final cardId = peekedCard['card_id']?.toString() ?? '';
      final cardRank = peekedCard['rank']?.toString() ?? '';
      final cardSuit = peekedCard['suit']?.toString() ?? '';
      final cardPoints = peekedCard['points'] as int? ?? 0;
      final cardColor = peekedCard['color']?.toString() ?? '';
      final cardIndex = peekedCard['index'] as int? ?? -1;
      
      // Add session message about successful peek
      _addSessionMessage(
        level: 'info',
        title: 'Queen Peek Result',
        message: 'You peeked at $targetPlayerId\'s card: $cardRank of $cardSuit ($cardPoints points)',
        data: {
          'game_id': gameId,
          'target_player_id': targetPlayerId,
          'peeked_card': peekedCard,
          'card_details': {
            'id': cardId,
            'rank': cardRank,
            'suit': cardSuit,
            'points': cardPoints,
            'color': cardColor,
            'index': cardIndex,
          },
        },
      );
    } else {
      // This is another player's peek result - we can optionally show a generic message
      // or keep it private (current implementation keeps it private)
      _addSessionMessage(
        level: 'info',
        title: 'Queen Power Used',
        message: '$peekingPlayerId used Queen peek on $targetPlayerId',
        data: {
          'game_id': gameId,
          'peeking_player_id': peekingPlayerId,
          'target_player_id': targetPlayerId,
          'is_my_peek': false,
        },
      );
    }
  }

  /// Handle cards_to_peek event
}
