/// Game Event Coordinator for Recall Game
///
/// This module handles all WebSocket event coordination for the Recall game,
/// including event registration, routing, and handling.

import 'package:recall/tools/logging/logger.dart';

const bool LOGGING_SWITCH = false;

class GameEventCoordinator {
  /// Coordinates all WebSocket events for the Recall game
  
  final dynamic gameStateManager;
  List<String> registeredEvents = [];
  
  
  bool handleGameEvent(String sessionId, String eventName, Map<String, dynamic> data) {
    /// Handle incoming game events and route to appropriate handlers
    try {
      Logger().info('Handling game event event_name: $eventName data: $data', isOn: LOGGING_SWITCH);
      // Route to appropriate game state manager method
      if (eventName == 'start_match') {
        return gameStateManager?.onStartMatch(sessionId, data) ?? false;
      }
      if (eventName == 'completed_initial_peek') {
        return gameStateManager?.onCompletedInitialPeek(sessionId, data) ?? false;
      } else if (eventName == 'draw_card') {
        // Add action type to data payload for draw_card events
        final dataWithAction = {...data, 'action': 'draw_from_deck'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'play_card') {
        // Add action type to data payload for play_card events
        final dataWithAction = {...data, 'action': 'play_card'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'discard_card') {
        // Add action type to data payload for discard_card events
        final dataWithAction = {...data, 'action': 'discard_card'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'take_from_discard') {
        // Add action type to data payload for take_from_discard events
        final dataWithAction = {...data, 'action': 'take_from_discard'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'call_recall') {
        // Add action type to data payload for call_recall events
        final dataWithAction = {...data, 'action': 'call_recall'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'same_rank_play') {
        // Add action type to data payload for same_rank_play events
        final dataWithAction = {...data, 'action': 'same_rank_play'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'jack_swap') {
        // Add action type to data payload for jack_swap events
        final dataWithAction = {...data, 'action': 'jack_swap'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'queen_peek') {
        // Add action type to data payload for queen_peek events
        final dataWithAction = {...data, 'action': 'queen_peek'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else {
        Logger().info('Unknown game event: $eventName', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Error handling game event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handlePlayerActionThroughRound(String sessionId, Map<String, dynamic> data) {
    /// Handle player actions through the game round
    try {
      // Get player ID from session
      final playerId = gameStateManager?.getPlayerIdFromSession(sessionId);
      if (playerId == null) {
        Logger().error('Player not found for session: $sessionId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get game state
      final gameState = gameStateManager?.getGameState(playerId);
      if (gameState == null) {
        Logger().error('Game state not found for player: $playerId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get game round
      final gameRound = gameStateManager?.getGameRound(playerId);
      if (gameRound == null) {
        Logger().error('Game round not found for player: $playerId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Handle the action based on type
      final action = data['action'];
      switch (action) {
        case 'draw_from_deck':
          return _handleDrawFromDeck(gameRound, playerId, data);
        case 'play_card':
          return _handlePlayCard(gameRound, playerId, data);
        case 'discard_card':
          return _handleDiscardCard(gameRound, playerId, data);
        case 'take_from_discard':
          return _handleTakeFromDiscard(gameRound, playerId, data);
        case 'call_recall':
          return _handleCallRecall(gameRound, playerId, data);
        case 'same_rank_play':
          return _handleSameRankPlay(gameRound, playerId, data);
        case 'jack_swap':
          return _handleJackSwap(gameRound, playerId, data);
        case 'queen_peek':
          return _handleQueenPeek(gameRound, playerId, data);
        default:
          Logger().error('Unknown action type: $action', isOn: LOGGING_SWITCH);
          return false;
      }
      
    } catch (e) {
      Logger().error('Error handling player action through round: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleDrawFromDeck(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle draw from deck action
    try {
      final result = gameRound.drawCard(playerId);
      if (result['success'] == true) {
        Logger().info('Player $playerId drew card from deck', isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().error('Failed to draw card from deck: ${result['error']}', isOn: LOGGING_SWITCH);
        return false;
      }
    } catch (e) {
      Logger().error('Error handling draw from deck: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handlePlayCard(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle play card action
    try {
      final cardId = data['card_id'];
      if (cardId == null) {
        Logger().error('Card ID not provided for play card action', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final result = gameRound.playCard(playerId, cardId);
      if (result['success'] == true) {
        Logger().info('Player $playerId played card $cardId', isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().error('Failed to play card: ${result['error']}', isOn: LOGGING_SWITCH);
        return false;
      }
    } catch (e) {
      Logger().error('Error handling play card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleDiscardCard(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle discard card action
    try {
      final cardId = data['card_id'];
      if (cardId == null) {
        Logger().error('Card ID not provided for discard card action', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // In a real implementation, this would handle discarding a card
      Logger().info('Player $playerId discarded card $cardId', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      Logger().error('Error handling discard card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleTakeFromDiscard(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle take from discard action
    try {
      final result = gameRound.drawCard(playerId, fromDiscard: true);
      if (result['success'] == true) {
        Logger().info('Player $playerId took card from discard pile', isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().error('Failed to take card from discard pile: ${result['error']}', isOn: LOGGING_SWITCH);
        return false;
      }
    } catch (e) {
      Logger().error('Error handling take from discard: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleCallRecall(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle call recall action
    try {
      // In a real implementation, this would handle calling recall
      Logger().info('Player $playerId called recall', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      Logger().error('Error handling call recall: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleSameRankPlay(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle same rank play action
    try {
      final cardId = data['card_id'];
      if (cardId == null) {
        Logger().error('Card ID not provided for same rank play action', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // In a real implementation, this would handle same rank play
      Logger().info('Player $playerId played same rank card $cardId', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      Logger().error('Error handling same rank play: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleJackSwap(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle jack swap action
    try {
      final card1Id = data['card1_id'];
      final card2Id = data['card2_id'];
      if (card1Id == null || card2Id == null) {
        Logger().error('Card IDs not provided for jack swap action', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // In a real implementation, this would handle jack swap
      Logger().info('Player $playerId swapped cards $card1Id and $card2Id', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      Logger().error('Error handling jack swap: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool _handleQueenPeek(dynamic gameRound, String playerId, Map<String, dynamic> data) {
    /// Handle queen peek action
    try {
      final targetPlayerId = data['target_player_id'];
      final cardId = data['card_id'];
      if (targetPlayerId == null || cardId == null) {
        Logger().error('Target player ID or card ID not provided for queen peek action', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // In a real implementation, this would handle queen peek
      Logger().info('Player $playerId peeked at card $cardId from player $targetPlayerId', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      Logger().error('Error handling queen peek: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  // ========= UTILITY METHODS =========
  
  List<String> getRegisteredEvents() {
    /// Get list of registered events
    return List<String>.from(registeredEvents);
  }

  bool isEventRegistered(String eventName) {
    /// Check if an event is registered
    return registeredEvents.contains(eventName);
  }

  void unregisterAllEvents() {
    /// Unregister all events
    try {
      registeredEvents.clear();
      Logger().info('All events unregistered', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Error unregistering events: $e', isOn: LOGGING_SWITCH);
    }
  }

  Map<String, dynamic> getCoordinatorInfo() {
    /// Get coordinator information
    return {
      'registered_events': registeredEvents,
      'event_count': registeredEvents.length,
      'game_state_manager': gameStateManager != null,
    };
  }

  void dispose() {
    /// Clean up resources
    try {
      unregisterAllEvents();
      Logger().info('GameEventCoordinator disposed', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Error disposing GameEventCoordinator: $e', isOn: LOGGING_SWITCH);
    }
  }
}