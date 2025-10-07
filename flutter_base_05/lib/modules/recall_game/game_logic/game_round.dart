/// Game Round for Recall Game
///
/// This module defines the GameRound class which serves as the entry point
/// for all gameplay during a round, managing round state and coordinating
/// with game actions.

import 'dart:async';
import 'package:recall/tools/logging/logger.dart';
import 'game_state.dart';
import 'models/player.dart';
import 'models/card.dart';

const bool LOGGING_SWITCH = true;

class GameRound {
  /// Manages a single round of gameplay in the Recall game
  
  final GameState gameState;
  int roundNumber = 1;
  DateTime? roundStartTime;
  DateTime? roundEndTime;
  DateTime? currentTurnStartTime;
  int turnTimeoutSeconds = 30; // 30 seconds per turn
  List<Map<String, dynamic>> actionsPerformed = [];

  Map<String, dynamic> sameRankData = {}; // player_id -> same_rank_data
  List<Map<String, dynamic>> specialCardData = []; // chronological list of special cards
  Timer? sameRankTimer; // Timer for same rank window
  Timer? specialCardTimer; // Timer for special card window
  List<Map<String, dynamic>> specialCardPlayers = []; // List of players who played special cards

  List<Map<String, dynamic>> pendingEvents = []; // List of pending events to process before ending round

  String roundStatus = "waiting"; // waiting, active, paused, completed
  
  // Timed rounds configuration
  bool timedRoundsEnabled = false;
  int roundTimeLimitSeconds = 300; // 5 minutes default
  int? roundTimeRemaining;
  
  // WebSocket manager reference for sending events
  dynamic websocketManager;

  GameRound(this.gameState) {
    Logger().info('DEBUG: GameRound instance created - special_card_data initialized', isOn: LOGGING_SWITCH);
    websocketManager = gameState.appManager?.websocketManager;
  }

  Map<String, dynamic> startTurn() {
    /// Start a new round of gameplay
    try {
      // Clear same rank data
      if (sameRankData.isNotEmpty) {
        sameRankData.clear();
      }
      
      // Only clear special card data if we're not in the middle of processing special cards
      // This prevents clearing data during special card processing
      if (specialCardData.isNotEmpty && gameState.phase != GamePhase.specialPlayWindow) {
        Logger().info('DEBUG: Clearing ${specialCardData.length} special cards in start_turn (phase: ${gameState.phase.name})', isOn: LOGGING_SWITCH);
        specialCardData.clear();
        Logger().info('Special card data cleared in start_turn (new turn)', isOn: LOGGING_SWITCH);
      } else if (specialCardData.isNotEmpty && gameState.phase == GamePhase.specialPlayWindow) {
        Logger().info('DEBUG: NOT clearing ${specialCardData.length} special cards in start_turn (processing special cards)', isOn: LOGGING_SWITCH);
        Logger().info('Special card data NOT cleared in start_turn (processing special cards)', isOn: LOGGING_SWITCH);
      } else {
        Logger().info('DEBUG: No special card data to clear in start_turn', isOn: LOGGING_SWITCH);
      }
      
      // Initialize round state
      roundStartTime = DateTime.now();
      currentTurnStartTime = roundStartTime;
      roundStatus = "active";
      actionsPerformed = [];

      gameState.phase = GamePhase.playerTurn;
      
      // Set current player status to drawing_card (they need to draw a card)
      if (gameState.currentPlayerId != null) {
        final player = gameState.players[gameState.currentPlayerId];
        if (player != null) {
          player.updateStatus(PlayerStatus.drawingCard);
          Logger().info('Player ${gameState.currentPlayerId} status set to DRAWING_CARD', isOn: LOGGING_SWITCH);
        }
      }
      
      // Initialize timed rounds if enabled
      if (timedRoundsEnabled) {
        roundTimeRemaining = roundTimeLimitSeconds;
      }
      
      // Log round start
      _logAction("round_started", {
        "round_number": roundNumber,
        "current_player": gameState.currentPlayerId,
        "player_count": gameState.players.length,
      });
      
      // Update turn start time
      currentTurnStartTime = DateTime.now();
      
      // Send game state update to all players
      if (gameState.appManager != null) {
        final coordinator = gameState.appManager.gameEventCoordinator;
        if (coordinator != null) {
          // coordinator._sendGameStateUpdate(gameState.gameId);
        }
      }
      
      // Send turn started event to current player
      _sendTurnStartedEvent();
      
      return {
        "success": true,
        "round_number": roundNumber,
        "round_start_time": roundStartTime!.toIso8601String(),
        "current_player": gameState.currentPlayerId,
        "game_phase": gameState.phase.name,
        "player_count": gameState.players.length,
      };
      
    } catch (e) {
      return {"error": "Failed to start round: $e"};
    }
  }

  bool continueTurn() {
    /// Complete the current round after a player action
    try {
      Logger().info('Continuing turn in phase: ${gameState.phase.name}', isOn: LOGGING_SWITCH);
      if (gameState.appManager != null) {
        final coordinator = gameState.appManager.gameEventCoordinator;
        if (coordinator != null) {
          // coordinator._sendGameStateUpdate(gameState.gameId);
        }
      }

      Logger().info('Continued turn in phase: ${gameState.phase.name}', isOn: LOGGING_SWITCH);

      if (gameState.phase == GamePhase.turnPendingEvents) {
        _checkPendingEventsBeforeEndingRound();
      }
      
      if (gameState.phase == GamePhase.endingRound) {
        _moveToNextPlayer();
      }
      
      return true;
      
    } catch (e) {
      return false;
    }
  }

  void _checkPendingEventsBeforeEndingRound() {
    /// Check if we have pending events to process (like queen peek pause so the user can see the card)
    try {
      if (pendingEvents.isEmpty) {
        Logger().info('No pending events to process', isOn: LOGGING_SWITCH);
        gameState.phase = GamePhase.endingRound;
        return;
      }
      
      // Process pending events
      for (final event in pendingEvents) {
        _processPendingEvent(event);
      }
      
      // Clear processed events
      pendingEvents.clear();
      
    } catch (e) {
      Logger().error('Error checking pending events: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _processPendingEvent(Map<String, dynamic> event) {
    /// Process a single pending event
    try {
      final eventType = event['type'];
      final eventData = event['data'];
      
      switch (eventType) {
        case 'queen_peek_pause':
          // Pause to show the peeked card
          _handleQueenPeekPause(eventData);
          break;
        case 'jack_swap_pause':
          // Pause to show the swapped cards
          _handleJackSwapPause(eventData);
          break;
        default:
          Logger().info('Unknown pending event type: $eventType', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      Logger().error('Error processing pending event: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _handleQueenPeekPause(Map<String, dynamic> data) {
    /// Handle queen peek pause event
    try {
      final playerId = data['player_id'];
      final cardId = data['card_id'];
      
      Logger().info('Queen peek pause for player $playerId, card $cardId', isOn: LOGGING_SWITCH);
      
      // In a real implementation, this would show the card to the player
      // and wait for them to acknowledge before continuing
      
    } catch (e) {
      Logger().error('Error handling queen peek pause: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _handleJackSwapPause(Map<String, dynamic> data) {
    /// Handle jack swap pause event
    try {
      final playerId = data['player_id'];
      final card1Id = data['card1_id'];
      final card2Id = data['card2_id'];
      
      Logger().info('Jack swap pause for player $playerId, cards $card1Id and $card2Id', isOn: LOGGING_SWITCH);
      
      // In a real implementation, this would show the swapped cards
      // and wait for players to acknowledge before continuing
      
    } catch (e) {
      Logger().error('Error handling jack swap pause: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _moveToNextPlayer() {
    /// Move to the next player in the game
    try {
      final playerIds = gameState.players.keys.toList();
      if (playerIds.isEmpty) {
        Logger().error('No players in game', isOn: LOGGING_SWITCH);
        return;
      }
      
      final currentIndex = playerIds.indexOf(gameState.currentPlayerId ?? '');
      final nextIndex = (currentIndex + 1) % playerIds.length;
      final nextPlayerId = playerIds[nextIndex];
      
      // Update current player
      gameState.currentPlayerId = nextPlayerId;
      
      // Update player statuses
      gameState.updateAllPlayersStatus(PlayerStatus.ready);
      if (gameState.players.containsKey(nextPlayerId)) {
        gameState.players[nextPlayerId]!.updateStatus(PlayerStatus.playing);
      }
      
      // Update game phase
      gameState.phase = GamePhase.playerTurn;
      
      Logger().info('Moved to next player: $nextPlayerId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Error moving to next player: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _sendTurnStartedEvent() {
    /// Send turn started event to current player
    try {
      // Get WebSocket manager through the game state's app manager
      if (gameState.appManager == null) {
        return;
      }
      
      final wsManager = gameState.appManager.websocketManager;
      if (wsManager == null) {
        return;
      }
      
      final currentPlayerId = gameState.currentPlayerId;
      if (currentPlayerId == null) {
        return;
      }
      
      // Get player session ID
      final sessionId = _getPlayerSessionId(currentPlayerId);
      if (sessionId == null) {
        return;
      }
      
      // Get current player object to access their status
      final currentPlayer = gameState.players[currentPlayerId];
      final playerStatus = currentPlayer?.status.name ?? "unknown";
      
      // Create turn started payload
      final turnPayload = {
        'event_type': 'turn_started',
        'game_id': gameState.gameId,
        'game_state': _toFlutterGameData(),
        'player_id': currentPlayerId,
        'player_status': playerStatus,
        'turn_timeout': turnTimeoutSeconds,
        'is_my_turn': true, // Add missing field that frontend expects
        'timestamp': DateTime.now().toIso8601String()
      };
      
      // Send turn started event
      wsManager.sendToSession(sessionId, 'turn_started', turnPayload);
      
    } catch (e) {
      Logger().error('Error sending turn started event: $e', isOn: LOGGING_SWITCH);
    }
  }

  String? _getPlayerSessionId(String playerId) {
    /// Get session ID for a player
    try {
      // Access the player sessions directly from game state
      return gameState.getPlayerSession(playerId);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _toFlutterGameData() {
    /// Convert game state to Flutter format - delegates to game_state manager
    /// 
    /// This method ensures all game data goes through the single source of truth
    /// in the GameStateManager._to_flutter_game_data method.
    try {
      // Use the GameStateManager for data conversion since it has the proper method
      if (gameState.appManager != null) {
        final gameStateManager = gameState.appManager?.gameStateManager;
        if (gameStateManager != null) {
          return gameStateManager.toFlutterGameData(gameState);
        } else {
          return {};
        }
      } else {
        return {};
      }
    } catch (e) {
      return {};
    }
  }

  void _logAction(String action, Map<String, dynamic> data) {
    /// Log a game action
    try {
      final actionData = {
        'action': action,
        'timestamp': DateTime.now().toIso8601String(),
        'round_number': roundNumber,
        'data': data,
      };
      
      actionsPerformed.add(actionData);
      
      Logger().info('Action logged: $action', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Error logging action: $e', isOn: LOGGING_SWITCH);
    }
  }

  // ========= CARD PLAY METHODS =========
  
  Map<String, dynamic> playCard(String playerId, String cardId) {
    /// Play a card from a player's hand
    try {
      final player = gameState.players[playerId];
      if (player == null) {
        return {"error": "Player not found"};
      }
      
      final card = player.removeCardFromHand(cardId);
      if (card == null) {
        return {"error": "Card not found in player's hand"};
      }
      
      // Add card to discard pile
      gameState.addToDiscardPile(card);
      gameState.lastPlayedCard = card;
      
      // Update player status
      player.updateStatus(PlayerStatus.playingCard);
      
      // Log the action
      _logAction("card_played", {
        "player_id": playerId,
        "card_id": cardId,
        "card_rank": card.rank,
        "card_suit": card.suit,
      });
      
      // Special card effects are handled in _checkSpecialCard method
      
      return {
        "success": true,
        "card": card.toDict(),
        "player_id": playerId,
      };
      
    } catch (e) {
      return {"error": "Failed to play card: $e"};
    }
  }


  bool _handleQueenPeek(String userId, Map<String, dynamic> actionData) {
    /// Handle Queen peek action - peek at any one card from any player
    try {
      Logger().info('Handling Queen peek for player $userId with data: $actionData', isOn: LOGGING_SWITCH);
      
      // Extract data from action
      final cardId = actionData['card_id'];
      final ownerId = actionData['ownerId']; // Note: using ownerId as per frontend changes
      
      if (cardId == null || ownerId == null) {
        Logger().error('Missing required data for queen peek: card_id=$cardId, ownerId=$ownerId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the target player and card
      final targetPlayer = _getPlayer(ownerId);
      if (targetPlayer == null) {
        Logger().error('Target player $ownerId not found for queen peek', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the card in the target player's hand
      Card? targetCard;
      for (final card in targetPlayer.hand) {
        if (card != null && card.cardId == cardId) {
          targetCard = card;
          break;
        }
      }
      
      if (targetCard == null) {
        Logger().error('Card $cardId not found in target player $ownerId hand', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the current player (the one doing the peek)
      final currentPlayer = _getPlayer(userId);
      if (currentPlayer == null) {
        Logger().error('Current player $userId not found for queen peek', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Clear any existing cards from previous peeks
      currentPlayer.clearCardsToPeek();
      
      // Add the card to the current player's cards_to_peek list
      currentPlayer.addCardToPeek(targetCard);
      Logger().info('Added card $cardId to player $userId cards_to_peek list', isOn: LOGGING_SWITCH);
      
      // Set player status to PEEKING
      currentPlayer.updateStatus(PlayerStatus.peeking);
      Logger().info('Set player $userId status to PEEKING', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Error in _handleQueenPeek: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleJackSwap(String userId, Map<String, dynamic> actionData) {
    /// Handle Jack swap action - swap two cards between players
    try {
      Logger().info('Handling Jack swap for player $userId with data: $actionData', isOn: LOGGING_SWITCH);
      
      // Extract card information from action data
      final firstCardId = actionData['first_card_id'];
      final firstPlayerId = actionData['first_player_id'];
      final secondCardId = actionData['second_card_id'];
      final secondPlayerId = actionData['second_player_id'];
      
      // Validate required data
      if (firstCardId == null || firstPlayerId == null || secondCardId == null || secondPlayerId == null) {
        Logger().error('Invalid Jack swap data - missing required fields', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Validate both players exist
      if (!gameState.players.containsKey(firstPlayerId) || !gameState.players.containsKey(secondPlayerId)) {
        Logger().error('Invalid Jack swap - one or both players not found', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get player objects
      final firstPlayer = gameState.players[firstPlayerId]!;
      final secondPlayer = gameState.players[secondPlayerId]!;
      
      // Find the cards in each player's hand
      Card? firstCard;
      int? firstCardIndex;
      Card? secondCard;
      int? secondCardIndex;
      
      // Find first card
      for (int i = 0; i < firstPlayer.hand.length; i++) {
        final card = firstPlayer.hand[i];
        if (card != null && card.cardId == firstCardId) {
          firstCard = card;
          firstCardIndex = i;
          break;
        }
      }
      
      // Find second card
      for (int i = 0; i < secondPlayer.hand.length; i++) {
        final card = secondPlayer.hand[i];
        if (card != null && card.cardId == secondCardId) {
          secondCard = card;
          secondCardIndex = i;
          break;
        }
      }
      
      // Validate cards found
      if (firstCard == null || secondCard == null || firstCardIndex == null || secondCardIndex == null) {
        Logger().error('Invalid Jack swap - one or both cards not found in players\' hands', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Perform the swap
      firstPlayer.hand[firstCardIndex] = secondCard;
      secondPlayer.hand[secondCardIndex] = firstCard;
      
      // Update card ownership
      firstCard.ownerId = firstPlayerId;
      secondCard.ownerId = secondPlayerId;
      
      Logger().info('Successfully swapped cards: ${firstCard.cardId} <-> ${secondCard.cardId}', isOn: LOGGING_SWITCH);
      Logger().info('Player $firstPlayerId now has: ${firstPlayer.hand.map((card) => card?.cardId ?? 'None').toList()}', isOn: LOGGING_SWITCH);
      Logger().info('Player $secondPlayerId now has: ${secondPlayer.hand.map((card) => card?.cardId ?? 'None').toList()}', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Error in _handleJackSwap: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  // ========= CARD DRAW METHODS =========
  
  Map<String, dynamic> drawCard(String playerId, {bool fromDiscard = false}) {
    /// Draw a card for a player
    try {
      final player = gameState.players[playerId];
      if (player == null) {
        return {"error": "Player not found"};
      }
      
      Card? drawnCard;
      if (fromDiscard) {
        drawnCard = gameState.drawFromDiscardPile();
      } else {
        drawnCard = gameState.drawFromDrawPile();
      }
      
      if (drawnCard == null) {
        return {"error": "No cards available to draw"};
      }
      
      // Add card to player's hand
      player.addCardToHand(drawnCard, isDrawnCard: true);
      player.setDrawnCard(drawnCard);
      
      // Update player status
      player.updateStatus(PlayerStatus.drawingCard);
      
      // Log the action
      _logAction("card_drawn", {
        "player_id": playerId,
        "card_id": drawnCard.cardId,
        "from_discard": fromDiscard,
      });
      
      return {
        "success": true,
        "card": drawnCard.toDict(),
        "player_id": playerId,
      };
      
    } catch (e) {
      return {"error": "Failed to draw card: $e"};
    }
  }

  // ========= GAME CONTROL METHODS =========
  
  void endRound() {
    /// End the current round
    try {
      roundEndTime = DateTime.now();
      roundStatus = "completed";
      
      // Log round end
      _logAction("round_ended", {
        "round_number": roundNumber,
        "duration": roundEndTime!.difference(roundStartTime!).inSeconds,
      });
      
      Logger().info('Round $roundNumber ended', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Error ending round: $e', isOn: LOGGING_SWITCH);
    }
  }

  void startNextRound() {
    /// Start the next round
    try {
      roundNumber++;
      roundStatus = "waiting";
      roundStartTime = null;
      roundEndTime = null;
      currentTurnStartTime = null;
      actionsPerformed.clear();
      
      Logger().info('Starting round $roundNumber', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Error starting next round: $e', isOn: LOGGING_SWITCH);
    }
  }

  // ========= UTILITY METHODS =========
  
  Map<String, dynamic> getRoundInfo() {
    /// Get current round information
    return {
      'round_number': roundNumber,
      'round_status': roundStatus,
      'round_start_time': roundStartTime?.toIso8601String(),
      'round_end_time': roundEndTime?.toIso8601String(),
      'current_turn_start_time': currentTurnStartTime?.toIso8601String(),
      'turn_timeout_seconds': turnTimeoutSeconds,
      'actions_performed': actionsPerformed,
      'timed_rounds_enabled': timedRoundsEnabled,
      'round_time_limit_seconds': roundTimeLimitSeconds,
      'round_time_remaining': roundTimeRemaining,
    };
  }

  // =======================================================
  // Player Actions
  // =======================================================

  bool onPlayerAction(String sessionId, Map<String, dynamic> data) {
    /// Handle player actions through the game round
    try {
      final action = data['action'] ?? data['action_type'];
      if (action == null) {
        Logger().info('on_player_action: No action found in data: $data', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get player ID from session data or request data
      final userId = _extractUserId(sessionId, data);
      Logger().info('on_player_action: action=$action, user_id=$userId', isOn: LOGGING_SWITCH);
      
      // Validate player exists before proceeding with any action
      if (!gameState.players.containsKey(userId)) {
        Logger().info('on_player_action: Player $userId not found in game state players: ${gameState.players.keys.toList()}', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Build action data for the round
      final actionData = _buildActionData(data);
      
      // Route to appropriate action handler based on action type and wait for completion
      final actionResult = _routeAction(action, userId, actionData);
      
      // Update game state timestamp after successful action
      if (actionResult) {
        gameState.lastActionTime = DateTime.now();
      }
      
      // Return the round completion result
      return true;
      
    } catch (e) {
      return false;
    }
  }

  Map<String, dynamic> _buildActionData(Map<String, dynamic> data) {
    /// Build standardized action data from incoming request data
    return {
      'card_id': data['card_id'] ?? (data['card'] ?? {})['card_id'] ?? (data['card'] ?? {})['id'],
      'replace_card_id': (data['replace_card'] ?? {})['card_id'] ?? data['replace_card_id'],
      'replace_index': data['replaceIndex'],
      'power_data': data['power_data'],
      'indices': data['indices'] ?? [],
      'source': data['source'], // For draw actions (deck/discard)
      // Jack swap specific fields
      'first_card_id': data['first_card_id'],
      'first_player_id': data['first_player_id'],
      'second_card_id': data['second_card_id'],
      'second_player_id': data['second_player_id'],
      // Queen peek specific fields
      'queen_peek_card_id': data['card_id'],
      'queen_peek_player_id': data['player_id'],
      'ownerId': data['ownerId'], // Card owner ID for queen peek
    };
  }

  String _extractUserId(String sessionId, Map<String, dynamic> data) {
    /// Extract user ID from session data or request data
    try {
      final sessionData = websocketManager?.getSessionData(sessionId) ?? {};
      return (sessionData['user_id'] ?? data['user_id'] ?? data['player_id'] ?? sessionId).toString();
    } catch (e) {
      return sessionId;
    }
  }

  bool _routeAction(String action, String userId, Map<String, dynamic> actionData) {
    /// Route action to appropriate handler and return result
    try {
      Logger().info("Routing action: $action user_id: $userId action_data: $actionData", isOn: LOGGING_SWITCH);
      if (action == 'draw_from_deck') {
        // Log pile contents before drawing
        Logger().info("=== PILE CONTENTS BEFORE DRAW ===", isOn: LOGGING_SWITCH);
        Logger().info("Draw Pile Count: ${gameState.drawPile.length}", isOn: LOGGING_SWITCH);
        Logger().info("Draw Pile Top 3: ${gameState.drawPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
        Logger().info("Discard Pile Count: ${gameState.discardPile.length}", isOn: LOGGING_SWITCH);
        Logger().info("Discard Pile Top 3: ${gameState.discardPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
        Logger().info("=================================", isOn: LOGGING_SWITCH);
        return _handleDrawFromPile(userId, actionData);
      } else if (action == 'play_card') {
        final playResult = _handlePlayCard(userId, actionData);
        // Note: _handle_play_card already calls _check_special_card internally
        _handleSameRankWindow(actionData);
        return playResult;
      } else if (action == 'same_rank_play') {
        return _handleSameRankPlay(userId, actionData);
      } else if (action == 'discard_card') {
        return true; // Placeholder - will be False when implemented
      } else if (action == 'take_from_discard') {
        return true; // Placeholder - will be False when implemented
      } else if (action == 'call_recall') {
        return true; // Placeholder - will be False when implemented
      } else if (action == 'jack_swap') {
        return _handleJackSwap(userId, actionData);
      } else if (action == 'queen_peek') {
        return _handleQueenPeek(userId, actionData);
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  bool _handleDrawFromPile(String playerId, Map<String, dynamic> actionData) {
    /// Handle drawing a card from the deck or discard pile
    try {
      Logger().info("_handle_draw_from_pile called for player $playerId with action_data $actionData", isOn: LOGGING_SWITCH);
      // Get the source pile (deck or discard)
      final source = actionData['source'];
      if (source == null) {
        return false;
      }
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        return false;
      }
      
      // Player validation already done in on_player_action
      final player = _getPlayer(playerId);
      if (player == null) {
        return false;
      }
      
      // Draw card based on source using custom methods with auto change detection
      Card? drawnCard;
      
      if (source == 'deck') {
        // Draw from draw pile using custom method
        drawnCard = gameState.drawFromDrawPile();
        if (drawnCard == null) {
          Logger().error("Failed to draw from draw pile for player $playerId", isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Check if draw pile is now empty (special game logic)
        if (gameState.isDrawPileEmpty()) {
          Logger().info("Draw pile is now empty", isOn: LOGGING_SWITCH);
        }
        
      } else if (source == 'discard') {
        // Take from discard pile using custom method
        drawnCard = gameState.drawFromDiscardPile();
        if (drawnCard == null) {
          Logger().error("Failed to draw from discard pile for player $playerId", isOn: LOGGING_SWITCH);
          return false;
        }
      }
      
      if (drawnCard != null) {
        // Add card to player's hand (drawn cards always go to the end)
        player.addCardToHand(drawnCard, isDrawnCard: true);
        
        // Set the drawn card property
        player.setDrawnCard(drawnCard);
      } else {
        Logger().error("Failed to draw card for player $playerId", isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Change player status from DRAWING_CARD to PLAYING_CARD after successful draw
      player.updateStatus(PlayerStatus.playingCard);
      Logger().info("Player $playerId status changed from DRAWING_CARD to PLAYING_CARD", isOn: LOGGING_SWITCH);
      
      // Log pile contents after successful draw using helper methods
      Logger().info("=== PILE CONTENTS AFTER DRAW ===", isOn: LOGGING_SWITCH);
      Logger().info("Draw Pile Count: ${gameState.getDrawPileCount()}", isOn: LOGGING_SWITCH);
      Logger().info("Draw Pile Top 3: ${gameState.drawPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
      Logger().info("Discard Pile Count: ${gameState.getDiscardPileCount()}", isOn: LOGGING_SWITCH);
      Logger().info("Discard Pile Top 3: ${gameState.discardPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
      Logger().info("Drawn Card: ${drawnCard.cardId}", isOn: LOGGING_SWITCH);
      Logger().info("=================================", isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      return false;
    }
  }

  bool _handlePlayCard(String playerId, Map<String, dynamic> actionData) {
    /// Handle playing a card from the player's hand
    try {
      // Extract key information from action_data
      final cardId = actionData['card_id'] ?? 'unknown';
      
      // Player validation already done in on_player_action
      final player = _getPlayer(playerId);
      if (player == null) {
        return false;
      }
      
      // Find the card in the player's hand
      Card? cardToPlay;
      int cardIndex = -1;
      
      for (int i = 0; i < player.hand.length; i++) {
        final card = player.hand[i];
        if (card != null && card.cardId == cardId) {
          cardToPlay = card;
          cardIndex = i;
          break;
        }
      }
      
      if (cardToPlay == null) {
        Logger().error("Card $cardId not found in player $playerId hand", isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info("Found card $cardId at index $cardIndex in player $playerId hand", isOn: LOGGING_SWITCH);
      
      // Handle drawn card repositioning BEFORE removing the played card
      final drawnCard = player.getDrawnCard();
      
      if (drawnCard != null && drawnCard.cardId != cardId) {
        // The played card was NOT the drawn card, so we need to reposition the drawn card
        // This will be handled after the card is removed
      }
      
      // Use the proper method to remove card with change detection
      Logger().info("About to call remove_card_from_hand for card $cardId", isOn: LOGGING_SWITCH);
      try {
        final removedCard = player.removeCardFromHand(cardId);
        if (removedCard == null) {
          Logger().error("Failed to remove card $cardId from player $playerId hand", isOn: LOGGING_SWITCH);
          return false;
        }
        Logger().info("Successfully removed card $cardId from player $playerId hand", isOn: LOGGING_SWITCH);
      } catch (e) {
        Logger().error("Exception in remove_card_from_hand: $e", isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Add card to discard pile using custom method with auto change detection
      if (!gameState.addToDiscardPile(cardToPlay)) {
        Logger().error("Failed to add card $cardId to discard pile", isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Handle drawn card repositioning with smart blank slot system
      if (drawnCard != null && drawnCard.cardId != cardId) {
        // The drawn card should fill the blank slot left by the played card
        // The blank slot is at card_index (where the played card was)
        Logger().info("Repositioning drawn card ${drawnCard.cardId} to index $cardIndex", isOn: LOGGING_SWITCH);
        
        // First, find and remove the drawn card from its original position
        int? originalIndex;
        for (int i = 0; i < player.hand.length; i++) {
          final card = player.hand[i];
          if (card != null && card.cardId == drawnCard.cardId) {
            originalIndex = i;
            break;
          }
        }
        
        if (originalIndex != null) {
          // Apply smart blank slot logic to the original position
          final shouldKeepOriginalSlot = player.shouldCreateBlankSlotAtIndex(originalIndex);
          
          if (shouldKeepOriginalSlot) {
            player.hand[originalIndex] = null; // Create blank slot
            Logger().info("Created blank slot at original position $originalIndex", isOn: LOGGING_SWITCH);
          } else {
            player.hand.removeAt(originalIndex); // Remove entirely
            Logger().info("Removed card entirely from original position $originalIndex", isOn: LOGGING_SWITCH);
            // Adjust target index if we removed a card before it
            if (originalIndex < cardIndex) {
              cardIndex -= 1;
            }
          }
        }
        
        // Apply smart blank slot logic to the target position
        final shouldPlaceInSlot = player.shouldCreateBlankSlotAtIndex(cardIndex);
        
        if (shouldPlaceInSlot) {
          // Place it in the blank slot left by the played card
          player.hand[cardIndex] = drawnCard;
          Logger().info("Placed drawn card in blank slot at index $cardIndex", isOn: LOGGING_SWITCH);
        } else {
          // The slot shouldn't exist, so append the drawn card to the end
          player.hand.add(drawnCard);
          Logger().info("Appended drawn card to end of hand (slot $cardIndex shouldn't exist)", isOn: LOGGING_SWITCH);
        }
        
        // IMPORTANT: After repositioning, the drawn card becomes a regular hand card
        // Clear the drawn card property since it's no longer "drawn"
        player.clearDrawnCard();
        
        Logger().info("After repositioning: hand slots = ${player.hand.map((card) => card?.cardId ?? 'None').toList()}", isOn: LOGGING_SWITCH);
        
      } else if (drawnCard != null && drawnCard.cardId == cardId) {
        // Clear the drawn card property since it's now in the discard pile
        player.clearDrawnCard();
      }
      
      // Log pile contents after successful play
      Logger().info("=== PILE CONTENTS AFTER PLAY ===", isOn: LOGGING_SWITCH);
      Logger().info("Draw Pile Count: ${gameState.drawPile.length}", isOn: LOGGING_SWITCH);
      Logger().info("Draw Pile Top 3: ${gameState.drawPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
      Logger().info("Discard Pile Count: ${gameState.discardPile.length}", isOn: LOGGING_SWITCH);
      Logger().info("Discard Pile Top 3: ${gameState.discardPile.take(3).map((card) => card.cardId).toList()}", isOn: LOGGING_SWITCH);
      Logger().info("Played Card: ${cardToPlay.cardId}", isOn: LOGGING_SWITCH);
      Logger().info("=================================", isOn: LOGGING_SWITCH);
      
      // Check if the played card has special powers (Jack/Queen)
      _checkSpecialCard(playerId, {
        'card_id': cardId,
        'rank': cardToPlay.rank,
        'suit': cardToPlay.suit
      });
      
      return true;
      
    } catch (e) {
      return false;
    }
  }

  Player? _getPlayer(String playerId) {
    /// Get player object from game state
    try {
      return gameState.players[playerId];
    } catch (e) {
      return null;
    }
  }

  void _checkSpecialCard(String playerId, Map<String, dynamic> cardData) {
    /// Check if a played card has special powers (Jack/Queen) and set player status accordingly
    try {
      // Extract card details from cardData
      final cardId = cardData['card_id'] ?? 'unknown';
      final cardRank = cardData['rank'] ?? 'unknown';
      final cardSuit = cardData['suit'] ?? 'unknown';
      
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
        Logger().info("DEBUG: special_card_data length before adding Jack: ${specialCardData.length}", isOn: LOGGING_SWITCH);
        specialCardData.add(specialCardInfo);
        Logger().info("DEBUG: special_card_data length after adding Jack: ${specialCardData.length}", isOn: LOGGING_SWITCH);
        Logger().info("Added Jack special card for player $playerId: $cardRank of $cardSuit (chronological order)", isOn: LOGGING_SWITCH);
        
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
        Logger().info("DEBUG: special_card_data length before adding Queen: ${specialCardData.length}", isOn: LOGGING_SWITCH);
        specialCardData.add(specialCardInfo);
        Logger().info("DEBUG: special_card_data length after adding Queen: ${specialCardData.length}", isOn: LOGGING_SWITCH);
        Logger().info("Added Queen special card for player $playerId: $cardRank of $cardSuit (chronological order)", isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error("Error in _check_special_card: $e", isOn: LOGGING_SWITCH);
    }
  }

  bool _handleSameRankWindow(Map<String, dynamic> actionData) {
    /// Handle same rank window action - sets all players to same_rank_window status
    try {
      Logger().info("Starting same rank window - setting all players to SAME_RANK_WINDOW status", isOn: LOGGING_SWITCH);
      
      // Set game state phase to SAME_RANK_WINDOW
      gameState.phase = GamePhase.sameRankWindow;
      
      // Update all players' status to SAME_RANK_WINDOW efficiently (single game state update)
      final updatedCount = gameState.updateAllPlayersStatus(PlayerStatus.sameRankWindow, filterActive: true);
      Logger().info("Updated $updatedCount players' status to SAME_RANK_WINDOW", isOn: LOGGING_SWITCH);
      
      // Set 5-second timer to automatically end same rank window
      _startSameRankTimer();
      
      return true;
      
    } catch (e) {
      Logger().error("Error in _handle_same_rank_window: $e", isOn: LOGGING_SWITCH);
      return false;
    }
  }

  void _startSameRankTimer() {
    /// Start a 5-second timer for the same rank window
    try {
      // Store timer reference for potential cancellation
      sameRankTimer = Timer(Duration(seconds: 5), _endSameRankWindow);
      
    } catch (e) {
      // Handle error silently
    }
  }

  void _endSameRankWindow() {
    /// End the same rank window and transition to ENDING_ROUND phase
    try {
      Logger().info("Ending same rank window - resetting all players to WAITING status", isOn: LOGGING_SWITCH);
      
      // Log the same_rank_data before clearing it
      if (sameRankData.isNotEmpty) {
        Logger().info("Same rank plays recorded: ${sameRankData.length} players", isOn: LOGGING_SWITCH);
        for (final entry in sameRankData.entries) {
          final playerId = entry.key;
          final playData = entry.value;
          Logger().info("Player $playerId played: ${playData['rank']} of ${playData['suit']}", isOn: LOGGING_SWITCH);
        }
      } else {
        Logger().info("No same rank plays recorded", isOn: LOGGING_SWITCH);
      }
      
      // Update all players' status to WAITING efficiently (single game state update)
      final updatedCount = gameState.updateAllPlayersStatus(PlayerStatus.waiting, filterActive: true);
      Logger().info("Updated $updatedCount players' status to WAITING", isOn: LOGGING_SWITCH);
      
      // Check if any player has no cards left (automatic win condition)
      for (final entry in gameState.players.entries) {
        final playerId = entry.key;
        final player = entry.value;
        if (!player.isActive) {
          continue;
        }
        
        // Count actual cards (excluding None/blank slots)
        final actualCards = player.hand.where((card) => card != null).toList();
        final cardCount = actualCards.length;
        
        if (cardCount == 0) {
          Logger().info("Player $playerId (${player.name}) has no cards left - triggering end of match", isOn: LOGGING_SWITCH);
          _handleEndOfMatch();
          return; // Exit early since game is ending
        }
      }
      
      // Clear same_rank_data after changing game phase using custom method
      gameState.clearSameRankData();
      
      // Send game state update to all players
      if (gameState.appManager != null) {
        final coordinator = gameState.appManager.gameEventCoordinator;
        if (coordinator != null) {
          // coordinator._sendGameStateUpdate(gameState.gameId);
        }
      }

      // Check for special cards and handle them
      _handleSpecialCardsWindow();
      
    } catch (e) {
      // Handle error silently
    }
  }

  void _handleSpecialCardsWindow() {
    /// Handle special cards window - process each player's special card with 10-second timer
    try {
      // Check if we have any special cards played
      if (specialCardData.isEmpty) {
        Logger().info("No special cards played in this round - transitioning directly to ENDING_ROUND", isOn: LOGGING_SWITCH);
        // No special cards, go directly to ENDING_ROUND
        gameState.phase = GamePhase.endingRound;
        Logger().info("Game phase changed to ENDING_ROUND (no special cards)", isOn: LOGGING_SWITCH);
        // Continue with normal turn flow since there are no special cards to process
        continueTurn();
        return;
      }
      
      // We have special cards, transition to SPECIAL_PLAY_WINDOW
      gameState.phase = GamePhase.specialPlayWindow;
      Logger().info("Game phase changed to SPECIAL_PLAY_WINDOW (special cards found)", isOn: LOGGING_SWITCH);
      
      Logger().info("=== SPECIAL CARDS WINDOW ===", isOn: LOGGING_SWITCH);
      Logger().info("DEBUG: special_card_data length: ${specialCardData.length}", isOn: LOGGING_SWITCH);
      Logger().info("DEBUG: Current game phase: ${gameState.phase.name}", isOn: LOGGING_SWITCH);
      
      // Count total special cards (now stored chronologically)
      final totalSpecialCards = specialCardData.length;
      Logger().info("Found $totalSpecialCards special cards played in chronological order", isOn: LOGGING_SWITCH);
      
      // Log details of all special cards in chronological order
      for (int i = 0; i < specialCardData.length; i++) {
        final card = specialCardData[i];
        Logger().info("  ${i+1}. Player ${card['player_id']}: ${card['rank']} of ${card['suit']} (${card['special_power']})", isOn: LOGGING_SWITCH);
      }
      
      // Create a working copy for processing (we'll remove cards as we process them)
      specialCardPlayers = List.from(specialCardData);
      
      Logger().info("Starting special card processing with ${specialCardPlayers.length} cards", isOn: LOGGING_SWITCH);
               
      // Start processing the first player's special card
      _processNextSpecialCard();
      
    } catch (e) {
      Logger().error("Error in _handle_special_cards_window: $e", isOn: LOGGING_SWITCH);
    }
  }

  void _processNextSpecialCard() {
    /// Process the next player's special card with 10-second timer
    try {
      // Check if we've processed all special cards (list is empty)
      if (specialCardPlayers.isEmpty) {
        Logger().info("All special cards processed - transitioning to ENDING_ROUND", isOn: LOGGING_SWITCH);
        _endSpecialCardsWindow();
        return;
      }
      
      // Get the first special card data (chronological order)
      final specialData = specialCardPlayers[0];
      final playerId = specialData['player_id'] ?? 'unknown';
      
      final cardRank = specialData['rank'] ?? 'unknown';
      final cardSuit = specialData['suit'] ?? 'unknown';
      final specialPower = specialData['special_power'] ?? 'unknown';
      final description = specialData['description'] ?? 'No description';
      
      Logger().info("Processing special card for player $playerId: $cardRank of $cardSuit", isOn: LOGGING_SWITCH);
      Logger().info("  Special Power: $specialPower", isOn: LOGGING_SWITCH);
      Logger().info("  Description: $description", isOn: LOGGING_SWITCH);
      Logger().info("  Remaining cards to process: ${specialCardPlayers.length}", isOn: LOGGING_SWITCH);
      
      // Set player status based on special power
      if (specialPower == 'jack_swap') {
        // Use the efficient batch update method to set player status
        gameState.updatePlayersStatusByIds([playerId], PlayerStatus.jackSwap);
        Logger().info("Player $playerId status set to JACK_SWAP - 10 second timer started", isOn: LOGGING_SWITCH);
      } else if (specialPower == 'queen_peek') {
        // Use the efficient batch update method to set player status
        gameState.updatePlayersStatusByIds([playerId], PlayerStatus.queenPeek);
        Logger().info("Player $playerId status set to PEEKING - 10 second timer started", isOn: LOGGING_SWITCH);
      } else {
        Logger().info("Unknown special power: $specialPower for player $playerId", isOn: LOGGING_SWITCH);
        // Remove this card and move to next
        specialCardPlayers.removeAt(0);
      }
      
      // Start 10-second timer for this player's special card play
      specialCardTimer = Timer(Duration(seconds: 10), _onSpecialCardTimerExpired);
      Logger().info("10-second timer started for player $playerId's $specialPower", isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error("Error in _process_next_special_card: $e", isOn: LOGGING_SWITCH);
    }
  }

  void _onSpecialCardTimerExpired() {
    /// Called when the special card timer expires - move to next player or end window
    try {
      // Reset current player's status to WAITING (if there are still cards to process)
      if (specialCardPlayers.isNotEmpty) {
        final specialData = specialCardPlayers[0];
        final playerId = specialData['player_id'] ?? 'unknown';
        gameState.updatePlayersStatusByIds([playerId], PlayerStatus.waiting);
        Logger().info("Player $playerId special card timer expired - status reset to WAITING", isOn: LOGGING_SWITCH);
        
        // Remove the processed card from the list
        specialCardPlayers.removeAt(0);
        Logger().info("Removed processed card from list. Remaining cards: ${specialCardPlayers.length}", isOn: LOGGING_SWITCH);
      }
      
      // Process next special card or end window
      _processNextSpecialCard();
      
    } catch (e) {
      Logger().error("Error in _on_special_card_timer_expired: $e", isOn: LOGGING_SWITCH);
    }
  }

  void _endSpecialCardsWindow() {
    /// End the special cards window and transition to ENDING_ROUND
    try {
      // Cancel any running timer
      cancelSpecialCardTimer();
      
      // Clear special card data
      if (specialCardData.isNotEmpty) {
        specialCardData.clear();
        Logger().info("Special card data cleared", isOn: LOGGING_SWITCH);
      }
      
      // Reset special card processing variables
      specialCardPlayers = [];
      
      // Transition to ENDING_ROUND phase
      gameState.phase = GamePhase.turnPendingEvents;
  
      // Now that special cards window is complete, continue with normal turn flow
      // This will move to the next player since we're no longer in SPECIAL_PLAY_WINDOW
      continueTurn();
      
    } catch (e) {
      Logger().error("Error in _end_special_cards_window: $e", isOn: LOGGING_SWITCH);
    }
  }

  void cancelSpecialCardTimer() {
    /// Cancel the special card timer if it's running
    try {
      if (specialCardTimer != null) {
        specialCardTimer!.cancel();
        specialCardTimer = null;
        Logger().info("Special card timer cancelled", isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      Logger().error("Error cancelling special card timer: $e", isOn: LOGGING_SWITCH);
    }
  }

  bool _handleSameRankPlay(String userId, Map<String, dynamic> actionData) {
    /// Handle same rank play action - validates rank match and stores the play in same_rank_data for multiple players
    try {
      // Extract card details from action_data
      final cardId = actionData['card_id'] ?? 'unknown';
      
      // Get player and find the card to get its rank and suit
      final player = gameState.players[userId];
      if (player == null) {
        return false;
      }
      
      // Find the card in player's hand
      Card? playedCard;
      for (final card in player.hand) {
        if (card != null && card.cardId == cardId) {
          playedCard = card;
          break;
        }
      }
      
      if (playedCard == null) {
        Logger().error("Card $cardId not found in player $userId hand for same rank play", isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info("Found card $cardId for same rank play in player $userId hand", isOn: LOGGING_SWITCH);
      
      final cardRank = playedCard.rank;
      final cardSuit = playedCard.suit;
      
      // Validate that this is actually a same rank play
      if (!_validateSameRankPlay(cardRank)) {
        // Apply penalty: draw a card from the draw pile
        final penaltyCard = _applySameRankPenalty(userId);
        if (penaltyCard != null) {
          // Penalty applied
        }
        
        return false;
      }
      
      // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
      // Use the proper method to remove card with change detection
      Logger().info("About to call remove_card_from_hand for same rank play card $cardId", isOn: LOGGING_SWITCH);
      try {
        final removedCard = player.removeCardFromHand(cardId);
        if (removedCard == null) {
          Logger().error("Failed to remove card $cardId from player $userId hand", isOn: LOGGING_SWITCH);
          return false;
        }
        Logger().info("Successfully removed same rank play card $cardId from player $userId hand", isOn: LOGGING_SWITCH);
      } catch (e) {
        Logger().error("Exception in remove_card_from_hand for same rank play: $e", isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Add card to discard pile using custom method with auto change detection
      if (!gameState.addToDiscardPile(playedCard)) {
        Logger().error("Failed to add card $cardId to discard pile", isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info("✅ Same rank play successful: $userId played $cardRank of $cardSuit - card moved to discard pile", isOn: LOGGING_SWITCH);
      
      // Check for special cards (Jack/Queen) and store data if applicable
      // Pass the correct card data structure to _check_special_card
      final cardData = {
        'card_id': cardId,
        'rank': cardRank,
        'suit': cardSuit
      };
      _checkSpecialCard(userId, cardData);
      
      // Create play data structure
      final playData = {
        'player_id': userId,
        'card_id': cardId,
        'rank': cardRank,      // Use 'rank' to match Card model
        'suit': cardSuit,      // Use 'suit' to match Card model
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        'play_order': sameRankData.length + 1  // Track order of plays
      };
      
      // Store the play in same_rank_data
      sameRankData[userId] = playData;
      
      return true;
      
    } catch (e) {
      return false;
    }
  }

  bool _validateSameRankPlay(String cardRank) {
    /// Validate that the played card has the same rank as the last card in the discard pile
    try {
      // Check if there are any cards in the discard pile
      if (gameState.discardPile.isEmpty) {
        Logger().info("Same rank validation failed: No cards in discard pile", isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the last card from the discard pile
      final lastCard = gameState.discardPile.last;
      final lastCardRank = lastCard.rank;
      
      Logger().info("Same rank validation: played_card_rank='$cardRank', last_card_rank='$lastCardRank'", isOn: LOGGING_SWITCH);
      
      // Handle special case: first card of the game (no previous card to match)
      if (gameState.discardPile.length == 1) {
        Logger().info("Same rank validation: First card of game, allowing play", isOn: LOGGING_SWITCH);
        return true;
      }
      
      // Check if ranks match (case-insensitive for safety)
      if (cardRank.toLowerCase() == lastCardRank.toLowerCase()) {
        Logger().info("Same rank validation: Ranks match, allowing play", isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().info("Same rank validation: Ranks don't match, denying play", isOn: LOGGING_SWITCH);
        return false;
      }
        
    } catch (e) {
      Logger().error("Same rank validation error: $e", isOn: LOGGING_SWITCH);
      return false;
    }
  }

  Card? _applySameRankPenalty(String playerId) {
    /// Apply penalty for invalid same rank play - draw a card from the draw pile
    try {
      // Check if draw pile has cards
      if (gameState.drawPile.isEmpty) {
        return null;
      }
      
      // Get player object
      final player = _getPlayer(playerId);
      if (player == null) {
        return null;
      }
      
      // Draw penalty card from draw pile using custom method with auto change detection
      final penaltyCard = gameState.drawFromDrawPile();
      if (penaltyCard == null) {
        Logger().error("Failed to draw penalty card from draw pile for player $playerId", isOn: LOGGING_SWITCH);
        return null;
      }
      
      // Add penalty card to player's hand
      player.addCardToHand(penaltyCard, isPenaltyCard: true);
      
      // Update player status to indicate they received a penalty
      player.updateStatus(PlayerStatus.waiting); // Reset to waiting after penalty
      Logger().info("Player $playerId status reset to WAITING after penalty", isOn: LOGGING_SWITCH);
      
      return penaltyCard;
      
    } catch (e) {
      return null;
    }
  }


  void _handleEndOfMatch() {
    /// Handle the end of the match
    try {
      // Collect all player data for scoring
      final playerResults = <String, Map<String, dynamic>>{};
      
      for (final entry in gameState.players.entries) {
        final playerId = entry.key;
        final player = entry.value;
        if (!player.isActive) {
          continue;
        }
          
        // Get hand cards (filter out None values for consistency)
        final handCards = player.hand.where((card) => card != null).cast<Card>().toList();
        final cardCount = handCards.length;
        
        // Calculate total points
        final totalPoints = handCards.fold(0, (sum, card) => sum + card.points);
        
        // Store player data
        playerResults[playerId] = {
          'player_id': playerId,
          'player_name': player.name,
          'hand_cards': handCards.map((card) => card.toDict()).toList(),
          'card_count': cardCount,
          'total_points': totalPoints
        };
      }
      
      // Determine winner based on Recall game rules
      final winnerData = _determineWinner(playerResults);
      
      // Set game phase to GAME_ENDED
      gameState.phase = GamePhase.gameEnded;
      Logger().info("Game phase set to GAME_ENDED", isOn: LOGGING_SWITCH);
      
      // Set winner status and log results
      if (winnerData['is_tie'] == true) {
        Logger().info("Game ended in a tie: ${winnerData['winners']}", isOn: LOGGING_SWITCH);
        // For ties, set all tied players to FINISHED status
        final winners = winnerData['winners'] as List<String>? ?? [];
        for (final winnerName in winners) {
          for (final entry in gameState.players.entries) {
            final player = entry.value;
            if (player.name == winnerName) {
              player.updateStatus(PlayerStatus.finished);
              Logger().info("Player ${player.name} set to FINISHED status (tie)", isOn: LOGGING_SWITCH);
            }
          }
        }
      } else {
        final winnerId = winnerData['winner_id'];
        final winnerName = winnerData['winner_name'];
        final winReason = winnerData['win_reason'] ?? 'unknown';
        
        Logger().info("Game ended - Winner: $winnerName (ID: $winnerId) - Reason: $winReason", isOn: LOGGING_SWITCH);
        
        // Set winner status
        if (winnerId != null && gameState.players.containsKey(winnerId)) {
          gameState.players[winnerId]!.updateStatus(PlayerStatus.winner);
          Logger().info("Player $winnerName set to WINNER status", isOn: LOGGING_SWITCH);
        }
        
        // Set all other players to FINISHED status
        for (final entry in gameState.players.entries) {
          final player = entry.value;
          if (entry.key != winnerId) {
            player.updateStatus(PlayerStatus.finished);
            Logger().info("Player ${player.name} set to FINISHED status", isOn: LOGGING_SWITCH);
          }
        }
      }
      
      // TODO: Send results to all players
      
    } catch (e) {
      Logger().error("Error in _handle_end_of_match: $e", isOn: LOGGING_SWITCH);
    }
  }

  Map<String, dynamic> _determineWinner(Map<String, Map<String, dynamic>> playerResults) {
    /// Determine the winner based on Recall game rules
    try {
      // Rule 1: Check for player with 0 cards (automatic win)
      for (final entry in playerResults.entries) {
        final playerId = entry.key;
        final data = entry.value;
        if (data['card_count'] == 0) {
          return {
            'is_tie': false,
            'winner_id': playerId,
            'winner_name': data['player_name'],
            'win_reason': 'no_cards',
            'winners': <String>[]
          };
        }
      }
      
      // Rule 2: Find player(s) with lowest points
      final minPoints = playerResults.values.map((data) => data['total_points'] as int).reduce((a, b) => a < b ? a : b);
      final lowestPointPlayers = playerResults.entries
          .where((entry) => entry.value['total_points'] == minPoints)
          .toList();
      
      // Rule 3: If only one player with lowest points, they win
      if (lowestPointPlayers.length == 1) {
        final winnerId = lowestPointPlayers[0].key;
        final winnerData = lowestPointPlayers[0].value;
        return {
          'is_tie': false,
          'winner_id': winnerId,
          'winner_name': winnerData['player_name'],
          'win_reason': 'lowest_points',
          'winners': <String>[]
        };
      }
      
      // Rule 4: Multiple players with lowest points - check for recall caller
      final recallCallerId = gameState.recallCalledBy;
      if (recallCallerId != null) {
        // Check if recall caller is among the lowest point players
        for (final entry in lowestPointPlayers) {
          final playerId = entry.key;
          final data = entry.value;
          if (playerId == recallCallerId) {
            return {
              'is_tie': false,
              'winner_id': playerId,
              'winner_name': data['player_name'],
              'win_reason': 'recall_caller_lowest_points',
              'winners': <String>[]
            };
          }
        }
      }
      
      // Rule 5: Multiple players with lowest points, none are recall callers - TIE
      final winnerNames = lowestPointPlayers.map((entry) => entry.value['player_name'] as String).toList();
      return {
        'is_tie': true,
        'winner_id': null,
        'winner_name': null,
        'win_reason': 'tie_lowest_points',
        'winners': winnerNames
      };
      
    } catch (e) {
      return {
        'is_tie': false,
        'winner_id': null,
        'winner_name': 'Error',
        'win_reason': 'error',
        'winners': <String>[]
      };
    }
  }

  void dispose() {
    /// Clean up resources
    try {
      sameRankTimer?.cancel();
      specialCardTimer?.cancel();
      
      Logger().info('GameRound disposed', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Error disposing GameRound: $e', isOn: LOGGING_SWITCH);
    }
  }
}