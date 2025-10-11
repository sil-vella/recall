/// Practice Game Round Manager for Recall Game
///
/// This class handles the actual gameplay rounds, turn management, and game logic
/// for practice sessions, including turn rotation, card actions, and AI decision making.

import 'dart:async';
import 'package:recall/tools/logging/logger.dart';
import 'practice_game.dart';

const bool LOGGING_SWITCH = false;

class PracticeGameRound {
  final PracticeGameCoordinator _practiceCoordinator;
  final String _gameId;
  Timer? _turnTimer;
  int _turnTimeLimit = 30; // Default 30 seconds per turn
  
  PracticeGameRound(this._practiceCoordinator, this._gameId);
  
  /// Initialize the round with the current game state
  /// Replicates backend _initial_peek_timeout() and start_turn() logic
  void initializeRound() {
    try {
      Logger().info('Practice: Initializing round for game $_gameId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      // 1. Clear cards_to_peek for all players (peek phase is over)
      _clearPeekedCards(gameState);
      
      // 2. Set all players back to WAITING status
      _setAllPlayersToWaiting(gameState);
      
      // 3. Initialize round state (replicates backend start_turn logic)
      _initializeRoundState(gameState);
      
      // 4. Set current player to DRAWING_CARD status (first action is to draw)
      _setCurrentPlayerToDrawing(gameState);
      
      // 5. Start the first turn
      _startNextTurn();
      
      Logger().info('Practice: Round initialization completed successfully', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize round: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clear cards_to_peek for all players (replicates backend logic)
  void _clearPeekedCards(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      int clearedCount = 0;
      
      for (final player in players) {
        if (player['cardsToPeek'] != null && (player['cardsToPeek'] as List).isNotEmpty) {
          player['cardsToPeek'] = <Map<String, dynamic>>[];
          clearedCount++;
        }
      }
      
      Logger().info('Practice: Cleared cards_to_peek for $clearedCount players', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to clear peeked cards: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Set all players to WAITING status (replicates backend logic)
  void _setAllPlayersToWaiting(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      for (final player in players) {
        player['status'] = 'waiting';
      }
      
      Logger().info('Practice: Set ${players.length} players back to WAITING status', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to set players to waiting: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Initialize round state (replicates backend start_turn logic)
  void _initializeRoundState(Map<String, dynamic> gameState) {
    try {
      // Clear same rank data (if exists)
      if (gameState.containsKey('sameRankData')) {
        gameState['sameRankData'] = <String, dynamic>{};
      }
      
      // Clear special card data (if exists)
      if (gameState.containsKey('specialCardData')) {
        gameState['specialCardData'] = <Map<String, dynamic>>[];
      }
      
      // Initialize round timing
      final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
      gameState['roundStartTime'] = currentTime;
      gameState['currentTurnStartTime'] = currentTime;
      gameState['roundStatus'] = 'active';
      gameState['actionsPerformed'] = <Map<String, dynamic>>[];
      
      // Set game phase to PLAYER_TURN (already set in matchStart, but ensure consistency)
      gameState['phase'] = 'player_turn';
      
      Logger().info('Practice: Round state initialized - phase: player_turn, status: active', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize round state: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Set current player to DRAWING_CARD status (replicates backend logic)
  void _setCurrentPlayerToDrawing(Map<String, dynamic> gameState) {
    try {
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (currentPlayer != null) {
        currentPlayer['status'] = 'drawing_card';
        Logger().info('Practice: Player ${currentPlayer['name']} status set to DRAWING_CARD', isOn: LOGGING_SWITCH);
      } else {
        Logger().warning('Practice: No current player found to set to drawing_card status', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to set current player to drawing: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get the current game state from the practice coordinator
  Map<String, dynamic>? _getCurrentGameState() {
    try {
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      return gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
    } catch (e) {
      Logger().error('Practice: Failed to get current game state: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }
  
  /// Start the next player's turn
  void _startNextTurn() {
    try {
      final gameState = _getCurrentGameState();
      if (gameState == null) return;
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayerId = gameState['currentPlayer']?['id'] as String?;
      
      // Find next player
      final nextPlayer = _getNextPlayer(players, currentPlayerId);
      if (nextPlayer == null) {
        Logger().error('Practice: No next player found', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Update current player
      gameState['currentPlayer'] = nextPlayer;
      
      // Set player status to DRAWING_CARD (first action is to draw a card)
      // This matches backend behavior where first player status is DRAWING_CARD
      _practiceCoordinator.updatePlayerStatus('drawing_card', playerId: nextPlayer['id'], updateMainState: true);
      
      // Start turn timer
      _startTurnTimer();
      
      Logger().info('Practice: Started turn for player ${nextPlayer['name']} - status: drawing_card', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to start next turn: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get the next player in rotation
  Map<String, dynamic>? _getNextPlayer(List<Map<String, dynamic>> players, String? currentPlayerId) {
    if (players.isEmpty) return null;
    
    if (currentPlayerId == null) {
      // First turn - start with first player
      return players.first;
    }
    
    // Find current player index
    final currentIndex = players.indexWhere((p) => p['id'] == currentPlayerId);
    if (currentIndex == -1) {
      // Current player not found, start with first
      return players.first;
    }
    
    // Get next player (wrap around)
    final nextIndex = (currentIndex + 1) % players.length;
    return players[nextIndex];
  }
  
  /// Start turn timer
  void _startTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = Timer(Duration(seconds: _turnTimeLimit), () {
      Logger().info('Practice: Turn timer expired, moving to next player', isOn: LOGGING_SWITCH);
      _handleTurnTimeout();
    });
  }
  
  /// Handle turn timeout
  void _handleTurnTimeout() {
    try {
      // Auto-draw a card for the current player

      
      // Move to next player
      _startNextTurn();
      
    } catch (e) {
      Logger().error('Practice: Failed to handle turn timeout: $e', isOn: LOGGING_SWITCH);
    }
  }
  


  /// Dispose of resources
  void dispose() {
    _turnTimer?.cancel();
    Logger().info('Practice: PracticeGameRound disposed for game $_gameId', isOn: LOGGING_SWITCH);
  }
}
