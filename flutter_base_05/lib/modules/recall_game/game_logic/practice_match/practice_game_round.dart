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
  void initializeRound() {
    try {
      Logger().info('Practice: Initializing round for game $_gameId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Start the first turn
      _startNextTurn();
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize round: $e', isOn: LOGGING_SWITCH);
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
      
      // Update player status
      _practiceCoordinator.updatePlayerStatus('playing', playerId: nextPlayer['id'], updateMainState: true);
      
      // Start turn timer
      _startTurnTimer();
      
      Logger().info('Practice: Started turn for player ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
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
      _drawCard();
      
      // Move to next player
      _startNextTurn();
      
    } catch (e) {
      Logger().error('Practice: Failed to handle turn timeout: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Draw a card for the current player
  void _drawCard() {
    try {
      final gameState = _getCurrentGameState();
      if (gameState == null) return;
      
      final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
      if (drawPile.isEmpty) {
        Logger().warning('Practice: Draw pile is empty, cannot draw card', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Draw top card
      final drawnCard = drawPile.removeAt(0);
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (currentPlayer != null) {
        // Add card to player's hand
        final hand = currentPlayer['hand'] as List<Map<String, dynamic>>? ?? [];
        hand.add(drawnCard);
        currentPlayer['hand'] = hand;
        
        // Set drawn card
        currentPlayer['drawnCard'] = drawnCard;
        
        Logger().info('Practice: Player ${currentPlayer['name']} drew a card', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to draw card: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Play a card from player's hand
  void playCard(String playerId, String cardId) {
    try {
      final gameState = _getCurrentGameState();
      if (gameState == null) return;
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        Logger().error('Practice: Player $playerId not found for play card', isOn: LOGGING_SWITCH);
        return;
      }
      
      final hand = player['hand'] as List<Map<String, dynamic>>? ?? [];
      final cardIndex = hand.indexWhere((card) => card['cardId'] == cardId);
      
      if (cardIndex == -1) {
        Logger().error('Practice: Card $cardId not found in player hand', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Remove card from hand
      final playedCard = hand.removeAt(cardIndex);
      
      // Add to discard pile
      final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      discardPile.add(playedCard);
      gameState['discardPile'] = discardPile;
      
      // Update last played card
      gameState['lastPlayedCard'] = playedCard;
      
      Logger().info('Practice: Player ${player['name']} played card ${playedCard['rank']} of ${playedCard['suit']}', isOn: LOGGING_SWITCH);
      
      // Move to next player
      _startNextTurn();
      
    } catch (e) {
      Logger().error('Practice: Failed to play card: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Dispose of resources
  void dispose() {
    _turnTimer?.cancel();
    Logger().info('Practice: PracticeGameRound disposed for game $_gameId', isOn: LOGGING_SWITCH);
  }
}
