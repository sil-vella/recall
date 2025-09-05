import '../../../core/managers/state_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/recall_game_helpers.dart';

/// Dedicated event handlers for Recall game events
/// Contains all the business logic for processing specific event types
class RecallEventHandlerCallbacks {
  static final Logger _log = Logger();

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
      
      _log.info('🎯 [HELPER] Updated game $gameId with: ${updates.keys.join(', ')}');
    } else {
      _log.warning('⚠️ [HELPER] Game $gameId not found in current games map');
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
      
      _log.info('🎯 [HELPER] Updated game data for game $gameId with: ${dataUpdates.keys.join(', ')}');
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
  static void _addGameToMap(String gameId, Map<String, dynamic> gameData, {String? gamePhase, String? gameStatus}) {
    final currentGames = _getCurrentGamesMap();
    
    // Determine game phase and status
    final phase = gamePhase ?? gameData['game_state']?['phase']?.toString() ?? 'waiting';
    final status = gameStatus ?? gameData['game_state']?['status']?.toString() ?? 'inactive';
    
    // Add/update the game in the games map
    currentGames[gameId] = {
      'gameData': gameData,  // Single source of truth
      'gamePhase': phase,
      'gameStatus': status,
      'isRoomOwner': _isCurrentUserRoomOwner(gameData),
      'isInGame': true,
      'joinedAt': DateTime.now().toIso8601String(),
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update global state
    RecallGameHelpers.updateUIState({
      'games': currentGames,
    });
    
    _log.info('🎯 [HELPER] Added/updated game $gameId to games map');
  }
  
  /// Update main game state (non-game-specific fields)
  static void _updateMainGameState(Map<String, dynamic> updates) {
    RecallGameHelpers.updateUIState({
      ...updates,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _log.info('🎯 [HELPER] Updated main game state with: ${updates.keys.join(', ')}');
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
    _log.info('🎧 [RECALL] Received recall_new_player_joined event');
    
    final roomId = data['room_id']?.toString() ?? '';
    final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    
    _log.info('🎧 [RECALL] Player ${joinedPlayer['name']} joined room $roomId');
    
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
    _log.info('🎧 [RECALL] Received recall_joined_games event');
    
    final userId = data['user_id']?.toString() ?? '';
    // final sessionId = data['session_id']?.toString() ?? '';
    final games = data['games'] as List<dynamic>? ?? [];
    final totalGames = data['total_games'] ?? 0;
    
    _log.info('🎧 [RECALL] User $userId is in $totalGames games');
    
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
      _log.info('🎧 [RECALL] Setting currentGameId to: $currentGameId');
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
    _log.info('🎧 [RECALL] Received game_started event');
    
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final startedBy = data['started_by']?.toString() ?? '';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    _log.info('🎧 [RECALL] Game $gameId started by $startedBy');
    
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
      'gamePhase': gameState['phase'] ?? 'playing',
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
    
    _log.info('🎮 [GAME_STARTED] Updated game $gameId using helper methods');
    
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
    _log.info('🎧 [RECALL] Received turn_started event');
    
    final gameId = data['game_id']?.toString() ?? '';
    // final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final playerId = data['player_id']?.toString() ?? '';
    final playerStatus = data['player_status']?.toString() ?? 'unknown';
    final turnTimeout = data['turn_timeout'] as int? ?? 30;
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    _log.info('🎧 [RECALL] Turn started for player $playerId in game $gameId (status: $playerStatus, timeout: ${turnTimeout}s)');
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this turn is for the current user
    final isMyTurn = playerId == currentUserId;
    
    if (isMyTurn) {
      _log.info('🎯 [TURN_STARTED] It\'s my turn! Timeout: ${turnTimeout}s');
      
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
      _log.info('🎯 [TURN_STARTED] Turn started for opponent $playerId');
      
      // Update UI state to show it's another player's turn using helper method
      _updateMainGameState({
        'isMyTurn': false,
        'statusBar': {
          'currentPhase': 'opponent_turn',
          'currentPlayerId': playerId,
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
    _log.info('🎧 [RECALL] Received game_state_updated event');
    
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final roundNumber = data['round_number'] as int? ?? 1;
    
    // Get currentPlayer from the game state (Map object) instead of from the root data
    final currentPlayerFromGameState = gameState['currentPlayer'] as Map<String, dynamic>?;
    final currentPlayerId = currentPlayerFromGameState?['id']?.toString() ?? '';
    final currentPlayerName = currentPlayerFromGameState?['name']?.toString() ?? '';
    final currentPlayerStatus = currentPlayerFromGameState?['status']?.toString() ?? 'unknown';
    
    _log.info('🔍 [GAME_STATE_UPDATE] currentPlayerFromGameState: $currentPlayerFromGameState');
    _log.info('🔍 [GAME_STATE_UPDATE] currentPlayerId: $currentPlayerId, currentPlayerName: $currentPlayerName');
    final roundStatus = data['round_status']?.toString() ?? 'active';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    _log.info('🎧 [RECALL] Game state updated for game $gameId - Round: $roundNumber, Current Player: $currentPlayerName ($currentPlayerStatus), Status: $roundStatus');
    
    // Extract pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = drawPile.length;
    final discardPileCount = discardPile.length;
    
    _log.info('🎧 [RECALL] Pile counts - Draw: $drawPileCount, Discard: $discardPileCount');
    
    // Update the main game state with the new information using helper method
    _updateMainGameState({
      'gamePhase': gameState['phase'] ?? 'playing',
      'isGameActive': true,
      'roundNumber': roundNumber,
      'currentPlayer': currentPlayerFromGameState,  // Use the Map object instead of string
      'currentPlayerStatus': currentPlayerStatus,
      'roundStatus': roundStatus,
    });
    
    // Update the games map with pile information using helper method
    _updateGameInMap(gameId, {
      'drawPileCount': drawPileCount,
      'discardPileCount': discardPileCount,
      'discardPile': discardPile,
    });
    
    _log.info('🎯 [GAME_STATE_UPDATE] Updated pile counts for game $gameId - Draw: $drawPileCount, Discard: $discardPileCount');
    
    // Add session message about game state update
    _addSessionMessage(
      level: 'info',
      title: 'Game State Updated',
      message: 'Round $roundNumber - $currentPlayerName is $currentPlayerStatus',
      data: {
        'game_id': gameId,
        'round_number': roundNumber,
        'current_player': currentPlayerFromGameState,
        'current_player_status': currentPlayerStatus,
        'round_status': roundStatus,
      },
    );
  }

  /// Handle player_state_updated event
  static void handlePlayerStateUpdated(Map<String, dynamic> data) {
    _log.info('🎧 [RECALL] Received player_state_updated event');
    
    final gameId = data['game_id']?.toString() ?? '';
    final playerId = data['player_id']?.toString() ?? '';
    final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    _log.info('🎧 [RECALL] Player state updated for player $playerId in game $gameId');
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this update is for the current user
    final isMyUpdate = playerId == currentUserId;
    
    if (isMyUpdate) {
      _log.info('🎯 [PLAYER_STATE_UPDATE] Updating my player state');
      
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
      
      _log.info('✅ [PLAYER_STATE_UPDATE] My player state updated - Hand: ${hand.length} cards, Score: $score, Status: $status, DrawnCard: $drawnCard');
      
      // Debug: Check what the state looks like after update
      final updatedState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final updatedDrawnCard = updatedState['myDrawnCard'];
      _log.info('🔍 [PLAYER_STATE_UPDATE] State after update - myDrawnCard: $updatedDrawnCard');
      
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
      _log.info('👥 [PLAYER_STATE_UPDATE] Updating opponent player state for player $playerId');
      
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
      
      _log.info('✅ [PLAYER_STATE_UPDATE] Opponent player state updated for player $playerId');
    }
  }
}
