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

const bool loggingSwitch = false;

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
      Logger().info('DEBUG: GameRound instance created - special_card_data initialized', isOn: loggingSwitch);
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
        Logger().info('DEBUG: Clearing ${specialCardData.length} special cards in start_turn (phase: ${gameState.phase.name})', isOn: loggingSwitch);
        specialCardData.clear();
        Logger().info('Special card data cleared in start_turn (new turn)', isOn: loggingSwitch);
      } else if (specialCardData.isNotEmpty && gameState.phase == GamePhase.specialPlayWindow) {
        Logger().info('DEBUG: NOT clearing ${specialCardData.length} special cards in start_turn (processing special cards)', isOn: loggingSwitch);
        Logger().info('Special card data NOT cleared in start_turn (processing special cards)', isOn: loggingSwitch);
      } else {
        Logger().info('DEBUG: No special card data to clear in start_turn', isOn: loggingSwitch);
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
          player.setStatus(PlayerStatus.drawingCard);
          Logger().info('Player ${gameState.currentPlayerId} status set to DRAWING_CARD', isOn: loggingSwitch);
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
      Logger().info('Continuing turn in phase: ${gameState.phase.name}', isOn: loggingSwitch);
      if (gameState.appManager != null) {
        final coordinator = gameState.appManager.gameEventCoordinator;
        if (coordinator != null) {
          // coordinator._sendGameStateUpdate(gameState.gameId);
        }
      }

      Logger().info('Continued turn in phase: ${gameState.phase.name}', isOn: loggingSwitch);

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
        Logger().info('No pending events to process', isOn: loggingSwitch);
        gameState.phase = GamePhase.endingRound;
        return;
      }
      
      Logger().info('Processing ${pendingEvents.length} pending events', isOn: loggingSwitch);
      
      // Process each pending event
      for (final event in pendingEvents) {
        final eventType = event['type'];
        final eventData = event['data'];
        final playerId = event['player_id'];
        final timestamp = event['timestamp'];
        
        Logger().info('Processing pending event: $eventType for player $playerId', isOn: loggingSwitch);
        
        // Construct handler method name by appending _handle to the event type
        final handlerMethodName = '_handle_$eventType';
        
        // This would call the appropriate handler method
        // Implementation would depend on the specific event types
      }
      
      // Clear the pending events after processing
      pendingEvents.clear();
      Logger().info('Cleared pending events after processing', isOn: loggingSwitch);
      
      continueTurn();
      
    } catch (e) {
      Logger().error('Error in _checkPendingEventsBeforeEndingRound: $e', isOn: loggingSwitch);
    }
  }

  void _moveToNextPlayer() {
    /// Move to the next player in the game
    try {
      if (gameState.players.isEmpty) {
        return;
      }
      
      // Get list of active player IDs
      final activePlayerIds = gameState.players.entries
          .where((entry) => entry.value.isActive)
          .map((entry) => entry.key)
          .toList();
      
      if (activePlayerIds.isEmpty) {
        return;
      }
      
      // Set current player status to ready before moving to next player
      if (gameState.currentPlayerId != null) {
        final player = gameState.players[gameState.currentPlayerId];
        if (player != null) {
          player.setStatus(PlayerStatus.ready);
          Logger().info('Player ${gameState.currentPlayerId} status set to READY', isOn: loggingSwitch);
        }
      }
      
      // Find current player index
      int currentIndex = -1;
      if (gameState.currentPlayerId != null && activePlayerIds.contains(gameState.currentPlayerId)) {
        currentIndex = activePlayerIds.indexOf(gameState.currentPlayerId!);
      }
      
      // Move to next player (or first if at end)
      final nextIndex = (currentIndex + 1) % activePlayerIds.length;
      final nextPlayerId = activePlayerIds[nextIndex];
      
      // Update current player
      final oldPlayerId = gameState.currentPlayerId;
      gameState.currentPlayerId = nextPlayerId;
      
      // Check if recall has been called
      if (gameState.recallCalledBy != null) {
        // Check if current player is the one who called recall
        if (gameState.currentPlayerId == gameState.recallCalledBy) {
          _handleEndOfMatch();
          return;
        }
      }
      
      // Send turn started event to new player
      startTurn();
      
    } catch (e) {
      // Handle error
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
          'total_points': totalPoints,
        };
      }
      
      // Determine winner based on Recall game rules
      final winnerData = _determineWinner(playerResults);
      
      // Set game phase to GAME_ENDED
      gameState.phase = GamePhase.gameEnded;
      Logger().info('Game phase set to GAME_ENDED', isOn: loggingSwitch);
      
      // Set winner status and log results
      if (winnerData['is_tie'] == true) {
        Logger().info('Game ended in a tie: ${winnerData['winners']}', isOn: loggingSwitch);
        // For ties, set all tied players to FINISHED status
        for (final winnerName in winnerData['winners'] as List<String>) {
          for (final entry in gameState.players.entries) {
            if (entry.value.name == winnerName) {
              entry.value.setStatus(PlayerStatus.finished);
              Logger().info('Player ${entry.value.name} set to FINISHED status (tie)', isOn: loggingSwitch);
            }
          }
        }
      } else {
        final winnerId = winnerData['winner_id'];
        final winnerName = winnerData['winner_name'];
        final winReason = winnerData['win_reason'] ?? 'unknown';
        
        Logger().info('Game ended - Winner: $winnerName (ID: $winnerId) - Reason: $winReason', isOn: loggingSwitch);
        
        // Set winner status
        if (winnerId != null && gameState.players.containsKey(winnerId)) {
          gameState.players[winnerId]!.setStatus(PlayerStatus.winner);
          Logger().info('Player $winnerName set to WINNER status', isOn: loggingSwitch);
        }
        
        // Set all other players to FINISHED status
        for (final entry in gameState.players.entries) {
          if (entry.key != winnerId) {
            entry.value.setStatus(PlayerStatus.finished);
            Logger().info('Player ${entry.value.name} set to FINISHED status', isOn: loggingSwitch);
          }
        }
      }
      
    } catch (e) {
      Logger().error('Error in _handleEndOfMatch: $e', isOn: loggingSwitch);
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
            'winners': <String>[],
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
        final winnerId = lowestPointPlayers.first.key;
        final winnerData = lowestPointPlayers.first.value;
        return {
          'is_tie': false,
          'winner_id': winnerId,
          'winner_name': winnerData['player_name'],
          'win_reason': 'lowest_points',
          'winners': <String>[],
        };
      }
      
      // Rule 4: Multiple players with lowest points - check for recall caller
      final recallCallerId = gameState.recallCalledBy;
      if (recallCallerId != null) {
        // Check if recall caller is among the lowest point players
        for (final entry in lowestPointPlayers) {
          if (entry.key == recallCallerId) {
            return {
              'is_tie': false,
              'winner_id': entry.key,
              'winner_name': entry.value['player_name'],
              'win_reason': 'recall_caller_lowest_points',
              'winners': <String>[],
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
        'winners': winnerNames,
      };
      
    } catch (e) {
      return {
        'is_tie': false,
        'winner_id': null,
        'winner_name': 'Error',
        'win_reason': 'error',
        'winners': <String>[],
      };
    }
  }

  void _logAction(String actionType, Map<String, dynamic> actionData) {
    /// Log an action performed during the round
    final logEntry = {
      "timestamp": DateTime.now().toIso8601String(),
      "action_type": actionType,
      "round_number": roundNumber,
      "data": actionData,
    };
    actionsPerformed.add(logEntry);
    
    // Keep only last 100 actions to prevent memory bloat
    if (actionsPerformed.length > 100) {
      actionsPerformed = actionsPerformed.sublist(actionsPerformed.length - 100);
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
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send turn started event
      // wsManager.sendToSession(sessionId, 'turn_started', turnPayload);
      
    } catch (e) {
      // Handle error
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

  Player? _getPlayer(String playerId) {
    /// Get player object from game state
    try {
      return gameState.players[playerId];
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _buildActionData(Map<String, dynamic> data) {
    /// Build standardized action data from incoming request data
    return {
      'card_id': data['card_id'] ?? (data['card']?['card_id']) ?? (data['card']?['id']),
      'replace_card_id': (data['replace_card']?['card_id']) ?? data['replace_card_id'],
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
      Logger().info('Routing action: $action user_id: $userId action_data: $actionData', isOn: loggingSwitch);
      if (action == 'draw_from_deck') {
        // Log pile contents before drawing
        Logger().info('=== PILE CONTENTS BEFORE DRAW ===', isOn: loggingSwitch);
        Logger().info('Draw Pile Count: ${gameState.drawPile.length}', isOn: loggingSwitch);
        Logger().info('Draw Pile Top 3: ${gameState.drawPile.take(3).map((card) => card.cardId).toList()}', isOn: loggingSwitch);
        Logger().info('Discard Pile Count: ${gameState.discardPile.length}', isOn: loggingSwitch);
        Logger().info('Discard Pile Top 3: ${gameState.discardPile.take(3).map((card) => card.cardId).toList()}', isOn: loggingSwitch);
        Logger().info('=================================', isOn: loggingSwitch);
        return _handleDrawFromPile(userId, actionData);
      } else if (action == 'play_card') {
        final playResult = _handlePlayCard(userId, actionData);
        // Note: _handlePlayCard already calls _checkSpecialCard internally
        final sameRankData = _handleSameRankWindow(actionData);
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

  Map<String, dynamic> _toFlutterGameData() {
    /// Convert game state to Flutter format - delegates to game_state manager
    ///
    /// This method ensures all game data goes through the single source of truth
    /// in the GameStateManager._toFlutterGameData method.
    try {
      // Use the GameStateManager for data conversion since it has the proper method
      if (gameState.appManager != null) {
        final gameStateManager = gameState.appManager.gameStateManager;
        if (gameStateManager != null) {
          // return gameStateManager._toFlutterGameData(gameState);
          return {}; // Placeholder
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

  // =======================================================
  // Player Actions
  // =======================================================

  bool onPlayerAction(String sessionId, Map<String, dynamic> data) {
    /// Handle player actions through the game round
    try {
      final action = data['action'] ?? data['action_type'];
      if (action == null) {
        Logger().info('on_player_action: No action found in data: $data', isOn: loggingSwitch);
        return false;
      }
      
      // Get player ID from session data or request data
      final userId = _extractUserId(sessionId, data);
      Logger().info('on_player_action: action=$action, user_id=$userId', isOn: loggingSwitch);
      
      // Validate player exists before proceeding with any action
      if (!gameState.players.containsKey(userId)) {
        Logger().info('on_player_action: Player $userId not found in game state players: ${gameState.players.keys.toList()}', isOn: loggingSwitch);
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

  // Placeholder methods for action handlers
  bool _handleDrawFromPile(String playerId, Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }

  bool _handlePlayCard(String playerId, Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }

  bool _handleSameRankPlay(String userId, Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }

  bool _handleSameRankWindow(Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }

  bool _handleJackSwap(String userId, Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }

  bool _handleQueenPeek(String userId, Map<String, dynamic> actionData) {
    // Implementation would go here
    return true;
  }
}
