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
  Timer? _sameRankTimer; // Timer for same rank window (5 seconds)
  Timer? _specialCardTimer; // Timer for special card window (10 seconds per card)
  
  // Special card data storage - stores chronological list of special cards played
  // Matches backend's self.special_card_data list (game_round.py line 33)
  final List<Map<String, dynamic>> _specialCardData = [];
  
  // Working copy of special cards for processing (will remove as processed)
  // Matches backend's self.special_card_players list (game_round.py line 686)
  List<Map<String, dynamic>> _specialCardPlayers = [];
  
  PracticeGameRound(this._practiceCoordinator, this._gameId);
  
  /// Initialize the round with the current game state
  /// Replicates backend _initial_peek_timeout() and start_turn() logic
  void initializeRound() {
    try {
      Logger().info('Practice: ===== INITIALIZING ROUND FOR GAME $_gameId =====', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      Logger().info('Practice: Current game state - Players: ${players.length}, Current Player: ${currentPlayer?['name'] ?? 'None'}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: All players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']}, status: ${p['status']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // 1. Clear cards_to_peek for all players (peek phase is over)
      Logger().info('Practice: Step 1 - Clearing cards_to_peek for all players', isOn: LOGGING_SWITCH);
      _clearPeekedCards(gameState);
      
      // 2. Set all players back to WAITING status
      Logger().info('Practice: Step 2 - Setting all players to WAITING status', isOn: LOGGING_SWITCH);
      _setAllPlayersToWaiting(gameState);
      
      // 3. Initialize round state (replicates backend start_turn logic)
      Logger().info('Practice: Step 3 - Initializing round state', isOn: LOGGING_SWITCH);
      _initializeRoundState(gameState);
      
      // 4. Start the first turn (this will set the current player to DRAWING_CARD status)
      Logger().info('Practice: Step 4 - Starting first turn (will select current player)', isOn: LOGGING_SWITCH);
      _startNextTurn();
      
      Logger().info('Practice: ===== ROUND INITIALIZATION COMPLETED SUCCESSFULLY =====', isOn: LOGGING_SWITCH);
      
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
      Logger().info('Practice: Starting next turn...', isOn: LOGGING_SWITCH);
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for _startNextTurn', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayerId = gameState['currentPlayer']?['id'] as String?;
      
      Logger().info('Practice: Current player ID: $currentPlayerId', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Available players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // Find next player
      final nextPlayer = _getNextPlayer(players, currentPlayerId);
      if (nextPlayer == null) {
        Logger().error('Practice: No next player found', isOn: LOGGING_SWITCH);
        return;
      }
      
      Logger().info('Practice: Selected next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
      
      // Reset previous current player's status to waiting (if there was one)
      if (currentPlayerId != null) {
        Logger().info('Practice: Resetting previous current player $currentPlayerId to waiting status', isOn: LOGGING_SWITCH);
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: currentPlayerId, updateMainState: true);
      }
      
      // Update current player
      gameState['currentPlayer'] = nextPlayer;
      Logger().info('Practice: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      // This matches backend behavior where first player status is DRAWING_CARD
      _practiceCoordinator.updatePlayerStatus('drawing_card', playerId: nextPlayer['id'], updateMainState: true, triggerInstructions: true);
      
      // Start turn timer
      _startTurnTimer();
      
      Logger().info('Practice: Started turn for player ${nextPlayer['name']} - status: drawing_card', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to start next turn: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get the next player in rotation
  Map<String, dynamic>? _getNextPlayer(List<Map<String, dynamic>> players, String? currentPlayerId) {
    Logger().info('Practice: _getNextPlayer called with currentPlayerId: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    if (players.isEmpty) {
      Logger().error('Practice: No players available for _getNextPlayer', isOn: LOGGING_SWITCH);
      return null;
    }
    
    if (currentPlayerId == null) {
      Logger().info('Practice: No current player ID - this is the first turn', isOn: LOGGING_SWITCH);
      
      // First turn - find human player and set as current
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        Logger().info('Practice: Found human player: ${humanPlayer['name']} (${humanPlayer['id']}) - setting as current', isOn: LOGGING_SWITCH);
        return humanPlayer;
      } else {
        // Fallback to first player if no human player found
        Logger().warning('Practice: No human player found, using first player as fallback: ${players.first['name']}', isOn: LOGGING_SWITCH);
        return players.first;
      }
    }
    
    Logger().info('Practice: Looking for current player with ID: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    // Find current player index
    final currentIndex = players.indexWhere((p) => p['id'] == currentPlayerId);
    if (currentIndex == -1) {
      Logger().warning('Practice: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
      
      // Current player not found, find human player
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        Logger().info('Practice: Setting human player as current: ${humanPlayer['name']} (${humanPlayer['id']})', isOn: LOGGING_SWITCH);
        return humanPlayer;
      } else {
        // Fallback to first player
        Logger().warning('Practice: No human player found, using first player as fallback: ${players.first['name']}', isOn: LOGGING_SWITCH);
        return players.first;
      }
    }
    
    Logger().info('Practice: Found current player at index $currentIndex: ${players[currentIndex]['name']}', isOn: LOGGING_SWITCH);
    
    // Get next player (wrap around)
    final nextIndex = (currentIndex + 1) % players.length;
    final nextPlayer = players[nextIndex];
    
    Logger().info('Practice: Next player index: $nextIndex, next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
    
    return nextPlayer;
  }
  
  /// Start turn timer
  void _startTurnTimer() {
    _turnTimer?.cancel();
    
    // Get timer settings from practice game configuration
    final turnTimeLimit = _getTurnTimeLimit();
    
    // Only start timer if it's enabled (turnTimeLimit > 0)
    if (turnTimeLimit > 0) {
      _turnTimer = Timer(Duration(seconds: turnTimeLimit), () {
        Logger().info('Practice: Turn timer expired (${turnTimeLimit}s), moving to next player', isOn: LOGGING_SWITCH);
        _handleTurnTimeout();
      });
      Logger().info('Practice: Started turn timer for ${turnTimeLimit} seconds', isOn: LOGGING_SWITCH);
    } else {
      Logger().info('Practice: Turn timer is disabled (no time limit)', isOn: LOGGING_SWITCH);
    }
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
  
  /// Get turn time limit from practice game configuration
  int _getTurnTimeLimit() {
    try {
      // Get the current game state to access timer settings
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().warning('Practice: Game state is null, using default timer (30s)', isOn: LOGGING_SWITCH);
        return 30; // Default fallback
      }
      
      // Get turn time limit from game state (stored during game creation)
      final turnTimeLimit = gameState['turnTimeLimit'] as int? ?? 30;
      
      Logger().info('Practice: Retrieved turn time limit from game state: ${turnTimeLimit}s', isOn: LOGGING_SWITCH);
      return turnTimeLimit;
      
    } catch (e) {
      Logger().error('Practice: Failed to get turn time limit: $e, using default (30s)', isOn: LOGGING_SWITCH);
      return 30; // Default fallback
    }
  }
  


  /// Handle drawing a card from the specified pile (replicates backend _handle_draw_from_pile)
  Future<bool> handleDrawCard(String source) async {
    try {
      Logger().info('Practice: Handling draw card from $source pile', isOn: LOGGING_SWITCH);
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        Logger().error('Practice: Invalid source for draw card: $source', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current player
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      Logger().info('Practice: Drawing card for player $playerId from $source pile', isOn: LOGGING_SWITCH);
      
      // Draw card based on source
      Map<String, dynamic>? drawnCard;
      
      if (source == 'deck') {
        // Draw from draw pile
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          Logger().error('Practice: Cannot draw from empty draw pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        final idOnlyCard = drawPile.removeLast(); // Remove last card (top of pile)
        Logger().info('Practice: Drew card ${idOnlyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
        
        // Convert ID-only card to full card data using the coordinator's method
        drawnCard = _practiceCoordinator.getCardById(gameState, idOnlyCard['cardId']);
        if (drawnCard == null) {
          Logger().error('Practice: Failed to get full card data for ${idOnlyCard['cardId']}', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Check if draw pile is now empty
        if (drawPile.isEmpty) {
          Logger().info('Practice: Draw pile is now empty', isOn: LOGGING_SWITCH);
        }
        
      } else if (source == 'discard') {
        // Take from discard pile
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        if (discardPile.isEmpty) {
          Logger().error('Practice: Cannot draw from empty discard pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        drawnCard = discardPile.removeLast(); // Remove last card (top of pile)
        Logger().info('Practice: Drew card ${drawnCard['cardId']} from discard pile', isOn: LOGGING_SWITCH);
      }
      
      if (drawnCard == null) {
        Logger().error('Practice: Failed to draw card from $source pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the current player's hand
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final playerIndex = players.indexWhere((p) => p['id'] == playerId);
      
      if (playerIndex == -1) {
        Logger().error('Practice: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final player = players[playerIndex];
      final hand = player['hand'] as List<Map<String, dynamic>>? ?? [];
      
      // Add card to player's hand as ID-only (player hands always store ID-only cards)
      // Backend replicates this in player.py add_card_to_hand method
      final idOnlyCard = {'cardId': drawnCard['cardId']};
      hand.add(idOnlyCard);
      
      // Set the drawn card property with FULL CARD DATA (same as backend)
      // This is what allows the frontend to show the front of the card
      player['drawnCard'] = drawnCard;
      
      Logger().info('Practice: Added card ${drawnCard['cardId']} to player $playerId hand as ID-only', isOn: LOGGING_SWITCH);
      
      // Change player status from DRAWING_CARD to PLAYING_CARD
      final statusUpdated = _practiceCoordinator.updatePlayerStatus('playing_card', playerId: playerId, updateMainState: true, triggerInstructions: true);
      if (!statusUpdated) {
        Logger().error('Practice: Failed to update player status to playing_card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Player $playerId status changed from drawing_card to playing_card', isOn: LOGGING_SWITCH);
      
      // Log pile contents after successful draw
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;
      
      Logger().info('Practice: === PILE CONTENTS AFTER DRAW ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Drawn Card: ${drawnCard['cardId']}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: ================================', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling draw card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle playing a card from the player's hand (replicates backend _handle_play_card)
  Future<bool> handlePlayCard(String cardId) async {
    try {
      Logger().info('Practice: Handling play card: $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for play card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for play card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player in the players list
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        Logger().error('Practice: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the card in the player's hand
      final hand = player['hand'] as List<Map<String, dynamic>>? ?? [];
      Map<String, dynamic>? cardToPlay;
      int cardIndex = -1;
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card['cardId'] == cardId) {
          cardToPlay = card;
          cardIndex = i;
          break;
        }
      }
      
      if (cardToPlay == null) {
        Logger().error('Practice: Card $cardId not found in player $playerId hand', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Found card $cardId at index $cardIndex in player $playerId hand', isOn: LOGGING_SWITCH);
      
      // Handle drawn card repositioning BEFORE removing the played card
      final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
      
      // Remove the played card from hand
      hand.removeAt(cardIndex);
      Logger().info('Practice: Removed card $cardId from player $playerId hand', isOn: LOGGING_SWITCH);
      
      // Convert card to full data before adding to discard pile
      // The player's hand contains ID-only cards, but discard pile needs full card data
      final cardToPlayFullData = _practiceCoordinator.getCardById(gameState, cardId);
      if (cardToPlayFullData == null) {
        Logger().error('Practice: Failed to get full data for card $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      Logger().info('Practice: Converted card $cardId to full data for discard pile', isOn: LOGGING_SWITCH);
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      final success = _practiceCoordinator.addToDiscardPile(cardToPlayFullData);
      if (!success) {
        Logger().error('Practice: Failed to add card $cardId to discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      Logger().info('Practice: Successfully added card $cardId to discard pile with full data', isOn: LOGGING_SWITCH);
      
      // Handle drawn card repositioning with smart blank slot system
      if (drawnCard != null && drawnCard['cardId'] != cardId) {
        // The drawn card should fill the blank slot left by the played card
        // The blank slot is at cardIndex (where the played card was)
        Logger().info('Practice: Repositioning drawn card ${drawnCard['cardId']} to index $cardIndex', isOn: LOGGING_SWITCH);
        
        // First, find and remove the drawn card from its original position
        int? originalIndex;
        for (int i = 0; i < hand.length; i++) {
          if (hand[i]['cardId'] == drawnCard['cardId']) {
            originalIndex = i;
            break;
          }
        }
        
        if (originalIndex != null) {
          // Remove the drawn card from its original position
          hand.removeAt(originalIndex);
          Logger().info('Practice: Removed drawn card from original position $originalIndex', isOn: LOGGING_SWITCH);
          
          // Adjust target index if we removed a card before it
          if (originalIndex < cardIndex) {
            cardIndex -= 1;
          }
        }
        
        // Place the drawn card in the blank slot left by the played card
        // IMPORTANT: Convert drawn card to ID-only data when placing in hand (same as backend)
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
          'displayName': 'Card ${drawnCard['cardId']}',
          'color': 'black',
        };
        
        if (cardIndex < hand.length) {
          hand.insert(cardIndex, drawnCardIdOnly);
          Logger().info('Practice: Placed drawn card (ID-only) in blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
        } else {
          hand.add(drawnCardIdOnly);
          Logger().info('Practice: Appended drawn card (ID-only) to end of hand', isOn: LOGGING_SWITCH);
        }
        
        // Clear the drawn card property since it's no longer "drawn"
        player['drawnCard'] = null;
        Logger().info('Practice: Cleared drawn card property after repositioning', isOn: LOGGING_SWITCH);
        
        // Update the main state's myDrawnCard to null (same as backend)
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
        
      } else if (drawnCard != null && drawnCard['cardId'] == cardId) {
        // Clear the drawn card property since it's now in the discard pile
        player['drawnCard'] = null;
        Logger().info('Practice: Cleared drawn card property (played card was the drawn card)', isOn: LOGGING_SWITCH);
        
        // Update the main state's myDrawnCard to null (same as backend)
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
      }
      
      // Log pile contents after successful play
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;

      Logger().info('Practice: === PILE CONTENTS AFTER PLAY ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Played Card: ${cardToPlay['cardId']}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: ================================', isOn: LOGGING_SWITCH);

      // Note: State update is already handled by addToDiscardPile method
      
      // Check if the played card has special powers (Jack/Queen)
      // Replicates backend flow: check special card FIRST (game_round.py line 989)
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': cardToPlayFullData['rank'],
        'suit': cardToPlayFullData['suit']
      });

      // Then trigger same rank window (backend game_round.py line 487)
      // This allows other players to play cards of the same rank out-of-turn
      _handleSameRankWindow();

      // Move to next player (simplified turn management for practice)
      // await _moveToNextPlayer();
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling play card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle same rank play action - validates rank match and moves card to discard pile
  /// Replicates backend's _handle_same_rank_play method in game_round.py lines 1000-1089
  Future<bool> handleSameRankPlay(String playerId, String cardId) async {
    try {
      Logger().info('Practice: Handling same rank play for player $playerId, card $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        Logger().error('Practice: Player $playerId not found for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the card in player's hand
      final hand = player['hand'] as List<dynamic>? ?? [];
      Map<String, dynamic>? playedCard;
      int cardIndex = -1;
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == cardId) {
          playedCard = card;
          cardIndex = i;
          break;
        }
      }
      
      if (playedCard == null) {
        Logger().error('Practice: Card $cardId not found in player $playerId hand for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Found card $cardId for same rank play in player $playerId hand at index $cardIndex', isOn: LOGGING_SWITCH);
      
      // Get full card data
      final playedCardFullData = _practiceCoordinator.getCardById(gameState, cardId);
      if (playedCardFullData == null) {
        Logger().error('Practice: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final cardRank = playedCardFullData['rank']?.toString() ?? '';
      final cardSuit = playedCardFullData['suit']?.toString() ?? '';
      
      // Validate that this is actually a same rank play
      if (!_validateSameRankPlay(gameState, cardRank)) {
        Logger().error('Practice: Same rank validation failed for card $cardId with rank $cardRank', isOn: LOGGING_SWITCH);
        // TODO: Apply penalty - draw a card from the draw pile (future implementation)
        return false;
      }
      
      Logger().info('Practice: Same rank validation passed for card $cardId with rank $cardRank', isOn: LOGGING_SWITCH);
      
      // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
      // Remove card from player's hand
      hand.removeAt(cardIndex);
      Logger().info('Practice: Successfully removed same rank play card $cardId from player $playerId hand', isOn: LOGGING_SWITCH);
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      final success = _practiceCoordinator.addToDiscardPile(playedCardFullData);
      if (!success) {
        Logger().error('Practice: Failed to add card $cardId to discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: ✅ Same rank play successful: $playerId played $cardRank of $cardSuit - card moved to discard pile', isOn: LOGGING_SWITCH);
      
      // Check for special cards (Jack/Queen) and store data if applicable
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': playedCardFullData['rank'],
        'suit': playedCardFullData['suit']
      });
      
      // TODO: Store the play in same_rank_data for tracking (future implementation)
      // For now, we just log the successful play
      Logger().info('Practice: Same rank play data would be stored here (future implementation)', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling same rank play: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Jack swap action - swap two cards between players
  /// Replicates backend's _handle_jack_swap method in game_round.py lines 1199-1265
  Future<bool> handleJackSwap({
    required String firstCardId,
    required String firstPlayerId,
    required String secondCardId,
    required String secondPlayerId,
  }) async {
    try {
      Logger().info('Practice: Handling Jack swap for cards: $firstCardId (player $firstPlayerId) <-> $secondCardId (player $secondPlayerId)', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for Jack swap', isOn: LOGGING_SWITCH);
        return false;
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Validate both players exist
      final firstPlayer = players.firstWhere(
        (p) => p['id'] == firstPlayerId,
        orElse: () => <String, dynamic>{},
      );

      final secondPlayer = players.firstWhere(
        (p) => p['id'] == secondPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (firstPlayer.isEmpty || secondPlayer.isEmpty) {
        Logger().error('Practice: Invalid Jack swap - one or both players not found', isOn: LOGGING_SWITCH);
        return false;
      }

      // Get player hands
      final firstPlayerHand = firstPlayer['hand'] as List<dynamic>? ?? [];
      final secondPlayerHand = secondPlayer['hand'] as List<dynamic>? ?? [];

      // Find the cards in each player's hand
      Map<String, dynamic>? firstCard;
      int? firstCardIndex;
      Map<String, dynamic>? secondCard;
      int? secondCardIndex;

      // Find first card
      for (int i = 0; i < firstPlayerHand.length; i++) {
        final card = firstPlayerHand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == firstCardId) {
          firstCard = card;
          firstCardIndex = i;
          break;
        }
      }

      // Find second card
      for (int i = 0; i < secondPlayerHand.length; i++) {
        final card = secondPlayerHand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == secondCardId) {
          secondCard = card;
          secondCardIndex = i;
          break;
        }
      }

      // Validate cards found
      if (firstCard == null || secondCard == null || firstCardIndex == null || secondCardIndex == null) {
        Logger().error('Practice: Invalid Jack swap - one or both cards not found in players\' hands', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Found cards - First card at index $firstCardIndex in player $firstPlayerId hand, Second card at index $secondCardIndex in player $secondPlayerId hand', isOn: LOGGING_SWITCH);

      // Perform the swap
      firstPlayerHand[firstCardIndex] = secondCard;
      secondPlayerHand[secondCardIndex] = firstCard;

      Logger().info('Practice: Successfully swapped cards: $firstCardId <-> $secondCardId', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Player $firstPlayerId now has card $secondCardId at index $firstCardIndex', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Player $secondPlayerId now has card $firstCardId at index $secondCardIndex', isOn: LOGGING_SWITCH);

      // Update game state to trigger UI updates
      final currentGames = _practiceCoordinator.currentGamesMap;
      _practiceCoordinator.updatePracticeGameState({
        'games': currentGames,
      });

      Logger().info('Practice: Jack swap completed - state updated', isOn: LOGGING_SWITCH);

      return true;

    } catch (e) {
      Logger().error('Practice: Error in handleJackSwap: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Queen peek action - peek at any one card from any player
  /// Replicates backend's _handle_queen_peek method in game_round.py lines 1267-1318
  Future<bool> handleQueenPeek({
    required String peekingPlayerId,
    required String targetCardId,
    required String targetPlayerId,
  }) async {
    try {
      Logger().info('Practice: Handling Queen peek - player $peekingPlayerId peeking at card $targetCardId from player $targetPlayerId', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Find the target player (card owner)
      final targetPlayer = players.firstWhere(
        (p) => p['id'] == targetPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (targetPlayer.isEmpty) {
        Logger().error('Practice: Target player $targetPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      // Find the peeking player (current player using Queen power)
      final peekingPlayer = players.firstWhere(
        (p) => p['id'] == peekingPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (peekingPlayer.isEmpty) {
        Logger().error('Practice: Peeking player $peekingPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      // Find the target card in the target player's hand
      final targetPlayerHand = targetPlayer['hand'] as List<dynamic>? ?? [];
      Map<String, dynamic>? targetCard;

      for (final card in targetPlayerHand) {
        if (card != null && card is Map<String, dynamic> && card['cardId'] == targetCardId) {
          targetCard = card;
          break;
        }
      }

      if (targetCard == null) {
        Logger().error('Practice: Card $targetCardId not found in target player $targetPlayerId hand', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Found target card: ${targetCard['rank']} of ${targetCard['suit']}', isOn: LOGGING_SWITCH);

      // Get full card data (convert from ID-only if needed)
      final fullCardData = _practiceCoordinator.getCardById(gameState, targetCardId);
      if (fullCardData == null) {
        Logger().error('Practice: Failed to get full card data for $targetCardId', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Full card data: ${fullCardData['rank']} of ${fullCardData['suit']} (${fullCardData['points']} points)', isOn: LOGGING_SWITCH);

      // Clear any existing cards_to_peek from previous peeks (backend line 1304)
      final existingCardsToPeek = peekingPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      existingCardsToPeek.clear();
      Logger().info('Practice: Cleared existing cards_to_peek for player $peekingPlayerId', isOn: LOGGING_SWITCH);

      // Add the target card to the peeking player's cards_to_peek list (backend line 1307)
      peekingPlayer['cardsToPeek'] = [fullCardData];
      Logger().info('Practice: Added card ${fullCardData['cardId']} to player $peekingPlayerId cards_to_peek list', isOn: LOGGING_SWITCH);

      // Set player status to PEEKING (backend line 1311)
      peekingPlayer['status'] = 'peeking';
      Logger().info('Practice: Set player $peekingPlayerId status to peeking', isOn: LOGGING_SWITCH);

      // Update main state for the human player
      if (peekingPlayerId == 'practice_user') {
        final currentGames = _practiceCoordinator.currentGamesMap;
        _practiceCoordinator.updatePracticeGameState({
          'playerStatus': 'peeking',
          'myCardsToPeek': [fullCardData],
          'games': currentGames,
        });
        Logger().info('Practice: Updated main state for human player - myCardsToPeek updated', isOn: LOGGING_SWITCH);
      } else {
        // For computer players, just update the games map
        final currentGames = _practiceCoordinator.currentGamesMap;
        _practiceCoordinator.updatePracticeGameState({
          'games': currentGames,
        });
        Logger().info('Practice: Updated games state for computer player', isOn: LOGGING_SWITCH);
      }

      Logger().info('Practice: Queen peek completed successfully', isOn: LOGGING_SWITCH);

      return true;

    } catch (e) {
      Logger().error('Practice: Error in handleQueenPeek: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Validate that the played card has the same rank as the last card in the discard pile
  /// Replicates backend's _validate_same_rank_play method in game_round.py lines 1091-1120
  bool _validateSameRankPlay(Map<String, dynamic> gameState, String cardRank) {
    try {
      // Check if there are any cards in the discard pile
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      
      if (discardPile.isEmpty) {
        Logger().info('Practice: Same rank validation failed: No cards in discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the last card from the discard pile
      final lastCard = discardPile.last as Map<String, dynamic>?;
      if (lastCard == null) {
        Logger().info('Practice: Same rank validation failed: Last card is null', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final lastCardRank = lastCard['rank']?.toString() ?? '';
      
      Logger().info('Practice: Same rank validation: played_card_rank=\'$cardRank\', last_card_rank=\'$lastCardRank\'', isOn: LOGGING_SWITCH);
      
      // Handle special case: first card of the game (no previous card to match)
      if (discardPile.length == 1) {
        Logger().info('Practice: Same rank validation: First card of game, allowing play', isOn: LOGGING_SWITCH);
        return true;
      }
      
      // Check if ranks match (case-insensitive for safety)
      if (cardRank.toLowerCase() == lastCardRank.toLowerCase()) {
        Logger().info('Practice: Same rank validation: Ranks match, allowing play', isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().info('Practice: Same rank validation: Ranks don\'t match, denying play', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Same rank validation error: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Check if a played card has special powers (Jack/Queen) and store data
  /// Replicates backend's _check_special_card method in game_round.py lines 1153-1197
  void _checkSpecialCard(String playerId, Map<String, dynamic> cardData) {
    try {
      final cardId = cardData['cardId']?.toString() ?? 'unknown';
      final cardRank = cardData['rank']?.toString().toLowerCase() ?? 'unknown';
      final cardSuit = cardData['suit']?.toString() ?? 'unknown';
      
      if (cardRank == 'jack') {
        // Store special card data chronologically (not grouped by player)
        final specialCardInfo = {
          'player_id': playerId,
          'card_id': cardId,
          'rank': cardRank,
          'suit': cardSuit,
          'special_power': 'jack_swap',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'description': 'Can switch any two cards between players'
        };
        
        Logger().info('Practice: DEBUG: special_card_data length before adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        Logger().info('Practice: DEBUG: special_card_data length after adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        Logger().info('Practice: Added Jack special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
      } else if (cardRank == 'queen') {
        // Store special card data chronologically (not grouped by player)
        final specialCardInfo = {
          'player_id': playerId,
          'card_id': cardId,
          'rank': cardRank,
          'suit': cardSuit,
          'special_power': 'queen_peek',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'description': 'Can look at one card from any player\'s hand'
        };
        
        Logger().info('Practice: DEBUG: special_card_data length before adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        Logger().info('Practice: DEBUG: special_card_data length after adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        Logger().info('Practice: Added Queen special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
      } else {
        // Not a special card, no action needed
        Logger().info('Practice: Card $cardRank is not a special card', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _checkSpecialCard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle same rank window - sets all players to same_rank_window status
  /// Replicates backend's _handle_same_rank_window method in game_round.py lines 566-585
  void _handleSameRankWindow() {
    try {
      Logger().info('Practice: Starting same rank window - setting all players to same_rank_window status', isOn: LOGGING_SWITCH);
      
      // Use the unified updatePlayerStatus method with playerId = null to update ALL players
      // This will:
      // 1. Update all players' status in the games map
      // 2. Update playerStatus in main state (for MyHandWidget)
      // 3. Update currentPlayer and currentPlayerStatus (for OpponentsPanel)
      // 4. Update isMyTurn (for ActionBar and MyHandWidget)
      // 5. Update games map in main state (for all state slices)
      final success = _practiceCoordinator.updatePlayerStatus(
        'same_rank_window',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false, // Don't trigger instructions for same rank window
      );
      
      if (success) {
        Logger().info('Practice: Successfully set all players to same_rank_window status', isOn: LOGGING_SWITCH);
        
        // Start 5-second timer to automatically end same rank window
        // Matches backend behavior (game_round.py line 579)
        _startSameRankTimer();
      } else {
        Logger().error('Practice: Failed to set all players to same_rank_window status', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _handleSameRankWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Start a 5-second timer for the same rank window
  /// Replicates backend's _start_same_rank_timer method in game_round.py lines 587-597
  void _startSameRankTimer() {
    try {
      Logger().info('Practice: Starting 5-second same rank window timer', isOn: LOGGING_SWITCH);
      
      // Cancel existing timer if any
      _sameRankTimer?.cancel();
      
      // Store timer reference for potential cancellation
      _sameRankTimer = Timer(const Duration(seconds: 5), () {
        _endSameRankWindow();
      });
      
    } catch (e) {
      Logger().error('Practice: Error starting same rank timer: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// End the same rank window and move to next player
  /// Replicates backend's _end_same_rank_window method in game_round.py lines 599-643
  void _endSameRankWindow() {
    try {
      Logger().info('Practice: Ending same rank window - resetting all players to waiting status', isOn: LOGGING_SWITCH);
      
      // TODO: Log same_rank_data if any players played matching cards (future implementation)
      // For now, we just log that window is ending
      Logger().info('Practice: No same rank plays recorded (simplified practice mode)', isOn: LOGGING_SWITCH);
      
      // Update all players' status to WAITING
      final success = _practiceCoordinator.updatePlayerStatus(
        'waiting',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false,
      );
      
      if (success) {
        Logger().info('Practice: Successfully reset all players to waiting status', isOn: LOGGING_SWITCH);
      } else {
        Logger().error('Practice: Failed to reset players to waiting status', isOn: LOGGING_SWITCH);
      }
      
      // TODO: Check if any player has no cards left (automatic win condition)
      // Future implementation - for now, we skip this check
      
      // Check for same rank plays from computer players
      _checkComputerPlayerSameRankPlays();
      
      // Check for special cards and handle them (backend game_round.py line 640)
      _handleSpecialCardsWindow();
      
    } catch (e) {
      Logger().error('Practice: Error ending same rank window: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check for same rank plays from computer players during the same rank window
  /// TODO: Implement computer player AI logic for same rank plays
  void _checkComputerPlayerSameRankPlays() {
    try {
      Logger().info('Practice: Same rank check for computer players still needs to be done', isOn: LOGGING_SWITCH);
      
      // TODO: Implement computer player same rank play logic
      // - Check each computer player's hand for matching rank cards
      // - Decide which computer players should play matching cards
      // - Process computer player same rank plays
      // - Update game state accordingly
      
    } catch (e) {
      Logger().error('Practice: Error in _checkComputerPlayerSameRankPlays: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle special cards window - process each player's special card with 10-second timer
  /// Replicates backend's _handle_special_cards_window method in game_round.py lines 656-694
  void _handleSpecialCardsWindow() {
    try {
      // Check if we have any special cards played
      if (_specialCardData.isEmpty) {
        Logger().info('Practice: No special cards played in this round - moving to next player', isOn: LOGGING_SWITCH);
        // No special cards, go directly to next player
        _moveToNextPlayer();
        return;
      }
      
      Logger().info('Practice: === SPECIAL CARDS WINDOW ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: DEBUG: special_card_data length: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
      
      // Count total special cards (stored chronologically)
      final totalSpecialCards = _specialCardData.length;
      Logger().info('Practice: Found $totalSpecialCards special cards played in chronological order', isOn: LOGGING_SWITCH);
      
      // Log details of all special cards in chronological order
      for (int i = 0; i < _specialCardData.length; i++) {
        final card = _specialCardData[i];
        Logger().info('Practice:   ${i+1}. Player ${card['player_id']}: ${card['rank']} of ${card['suit']} (${card['special_power']})', isOn: LOGGING_SWITCH);
      }
      
      // Create a working copy for processing (we'll remove cards as we process them)
      _specialCardPlayers = List<Map<String, dynamic>>.from(_specialCardData);
      
      Logger().info('Practice: Starting special card processing with ${_specialCardPlayers.length} cards', isOn: LOGGING_SWITCH);
      
      // Start processing the first player's special card
      _processNextSpecialCard();
      
    } catch (e) {
      Logger().error('Practice: Error in _handleSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Process the next player's special card with 10-second timer
  /// Replicates backend's _process_next_special_card method in game_round.py lines 696-739
  void _processNextSpecialCard() {
    try {
      // Check if we've processed all special cards (list is empty)
      if (_specialCardPlayers.isEmpty) {
        Logger().info('Practice: All special cards processed - moving to next player', isOn: LOGGING_SWITCH);
        _endSpecialCardsWindow();
        return;
      }
      
      // Get the first special card data (chronological order)
      final specialData = _specialCardPlayers[0];
      final playerId = specialData['player_id']?.toString() ?? 'unknown';
      final cardRank = specialData['rank']?.toString() ?? 'unknown';
      final cardSuit = specialData['suit']?.toString() ?? 'unknown';
      final specialPower = specialData['special_power']?.toString() ?? 'unknown';
      final description = specialData['description']?.toString() ?? 'No description';
      
      Logger().info('Practice: Processing special card for player $playerId: $cardRank of $cardSuit', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Special Power: $specialPower', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Description: $description', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Remaining cards to process: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      
      // Set player status based on special power
      if (specialPower == 'jack_swap') {
        _practiceCoordinator.updatePlayerStatus('jack_swap', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId status set to jack_swap - 10 second timer started', isOn: LOGGING_SWITCH);
      } else if (specialPower == 'queen_peek') {
        _practiceCoordinator.updatePlayerStatus('queen_peek', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId status set to queen_peek - 10 second timer started', isOn: LOGGING_SWITCH);
      } else {
        Logger().warning('Practice: Unknown special power: $specialPower for player $playerId', isOn: LOGGING_SWITCH);
        // Remove this card and move to next
        _specialCardPlayers.removeAt(0);
        _processNextSpecialCard();
        return;
      }
      
      // Start 10-second timer for this player's special card play
      _specialCardTimer?.cancel();
      _specialCardTimer = Timer(const Duration(seconds: 10), () {
        _onSpecialCardTimerExpired();
      });
      Logger().info('Practice: 10-second timer started for player $playerId\'s $specialPower', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Error in _processNextSpecialCard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Called when the special card timer expires - move to next player or end window
  /// Replicates backend's _on_special_card_timer_expired method in game_round.py lines 741-766
  void _onSpecialCardTimerExpired() {
    try {
      // Reset current player's status to WAITING (if there are still cards to process)
      if (_specialCardPlayers.isNotEmpty) {
        final specialData = _specialCardPlayers[0];
        final playerId = specialData['player_id']?.toString() ?? 'unknown';
        
        // TODO: Get the player and clear their cards_to_peek (Queen peek timer expired)
        // Future implementation
        
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId special card timer expired - status reset to waiting', isOn: LOGGING_SWITCH);
        
        // Remove the processed card from the list
        _specialCardPlayers.removeAt(0);
        Logger().info('Practice: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      }
      
      // Add 1-second delay for visual indication before processing next special card
      Logger().info('Practice: Waiting 1 second before processing next special card...', isOn: LOGGING_SWITCH);
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });
      
    } catch (e) {
      Logger().error('Practice: Error in _onSpecialCardTimerExpired: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// End the special cards window and move to next player
  /// Replicates backend's _end_special_cards_window method in game_round.py lines 768-789
  void _endSpecialCardsWindow() {
    try {
      // Cancel any running timer
      _specialCardTimer?.cancel();
      
      // Clear special card data
      _specialCardData.clear();
      _specialCardPlayers.clear();
      
      Logger().info('Practice: Special cards window ended - cleared all special card data', isOn: LOGGING_SWITCH);
      
      // Now move to the next player
      Logger().info('Practice: Moving to next player after special cards', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
      
    } catch (e) {
      Logger().error('Practice: Error in _endSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Move to the next player (simplified version for practice)
  Future<void> _moveToNextPlayer() async {
    try {
      Logger().info('Practice: Moving to next player', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (currentPlayer == null || players.isEmpty) {
        Logger().error('Practice: No current player or players list for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Set current player status to waiting before moving to next player
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      _practiceCoordinator.updatePlayerStatus('waiting', playerId: currentPlayerId, updateMainState: true);
      Logger().info('Practice: Set current player $currentPlayerId status to waiting', isOn: LOGGING_SWITCH);
      
      // Find current player index
      int currentIndex = -1;
      for (int i = 0; i < players.length; i++) {
        if (players[i]['id'] == currentPlayerId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        Logger().error('Practice: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Move to next player (or first if at end)
      final nextIndex = (currentIndex + 1) % players.length;
      final nextPlayer = players[nextIndex];
      final nextPlayerId = nextPlayer['id']?.toString() ?? '';
      
      // Update current player in game state
      gameState['currentPlayer'] = nextPlayer;
      Logger().info('Practice: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      // Don't call _startNextTurn() because it would call _getNextPlayer() again and skip this player!
      _practiceCoordinator.updatePlayerStatus('drawing_card', playerId: nextPlayerId, updateMainState: true, triggerInstructions: true);
      Logger().info('Practice: Set next player ${nextPlayer['name']} to drawing_card status', isOn: LOGGING_SWITCH);
      
      // Start turn timer for the new player
      _startTurnTimer();
      Logger().info('Practice: Started turn for player ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Error moving to next player: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Dispose of resources
  void dispose() {
    _turnTimer?.cancel();
    _sameRankTimer?.cancel();
    _specialCardTimer?.cancel();
    Logger().info('Practice: PracticeGameRound disposed for game $_gameId', isOn: LOGGING_SWITCH);
  }
}
