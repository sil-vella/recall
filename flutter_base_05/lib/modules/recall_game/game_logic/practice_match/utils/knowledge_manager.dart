import 'dart:math';
import 'package:recall/tools/logging/logger.dart';
import 'computer_player_config_parser.dart';

const bool LOGGING_SWITCH = true;

class KnowledgeManager {
  final ComputerPlayerConfig config;
  final Random _random = Random();
  
  KnowledgeManager(this.config);
  
  /// Update all players' known_cards after a card play event
  /// [players] - List of all players in the game
  /// [playedCardId] - ID of the card that was played
  /// [eventType] - Type of event: 'play', 'same_rank_play'
  void updateAfterCardPlay(List<Map<String, dynamic>> players, String playedCardId, String eventType) {
    Logger().info('KnowledgeManager: Updating knowledge after $eventType - card: $playedCardId', isOn: LOGGING_SWITCH);
    
    for (final player in players) {
      // Skip human players (they manage their own knowledge)
      if (player['isHuman'] == true) continue;
      
      final playerId = player['id'] as String;
      final difficulty = player['difficulty'] as String? ?? 'medium';
      final memoryProb = config.getMemoryProbability(difficulty);
      
      // Probability check: Does this player remember/notice the play?
      if (_random.nextDouble() > memoryProb) {
        Logger().info('KnowledgeManager: Player $playerId forgot the play (${(memoryProb * 100).toInt()}% memory)', isOn: LOGGING_SWITCH);
        continue;
      }
      
      // Update player's known_cards
      _removeCardFromKnownCards(player, playedCardId);
    }
  }
  
  /// Update all players' known_cards after a jack swap event
  /// [players] - List of all players in the game
  /// [card1Id] - ID of first card in swap
  /// [card1OldOwner] - Original owner of card1
  /// [card1NewOwner] - New owner of card1
  /// [card2Id] - ID of second card in swap
  /// [card2OldOwner] - Original owner of card2
  /// [card2NewOwner] - New owner of card2
  void updateAfterJackSwap(
    List<Map<String, dynamic>> players,
    String card1Id, String card1OldOwner, String card1NewOwner,
    String card2Id, String card2OldOwner, String card2NewOwner
  ) {
    Logger().info('KnowledgeManager: Updating knowledge after jack swap', isOn: LOGGING_SWITCH);
    Logger().info('  Card1: $card1Id ($card1OldOwner -> $card1NewOwner)', isOn: LOGGING_SWITCH);
    Logger().info('  Card2: $card2Id ($card2OldOwner -> $card2NewOwner)', isOn: LOGGING_SWITCH);
    
    for (final player in players) {
      // Skip human players
      if (player['isHuman'] == true) continue;
      
      final playerId = player['id'] as String;
      final difficulty = player['difficulty'] as String? ?? 'medium';
      final memoryProb = config.getMemoryProbability(difficulty);
      
      // Probability check
      if (_random.nextDouble() > memoryProb) {
        Logger().info('KnowledgeManager: Player $playerId forgot the swap (${(memoryProb * 100).toInt()}% memory)', isOn: LOGGING_SWITCH);
        continue;
      }
      
      // Update ownership for both cards in player's known_cards
      _updateCardOwnership(player, card1Id, card1OldOwner, card1NewOwner);
      _updateCardOwnership(player, card2Id, card2OldOwner, card2NewOwner);
    }
  }
  
  /// Remove a card from player's known_cards
  void _removeCardFromKnownCards(Map<String, dynamic> player, String cardId) {
    final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
    bool cardRemoved = false;
    
    // Iterate through all player entries in known_cards
    for (final ownerPlayerId in knownCards.keys.toList()) {
      final ownerCards = knownCards[ownerPlayerId];
      if (ownerCards is! Map) continue;
      
      // Check card1
      final card1 = ownerCards['card1'];
      if (card1 != null) {
        final card1Id = card1 is Map ? (card1['cardId'] ?? card1['id']) : card1.toString();
        if (card1Id == cardId) {
          ownerCards['card1'] = null;
          cardRemoved = true;
          Logger().info('KnowledgeManager: Removed card $cardId from ${player['name']} known_cards[$ownerPlayerId].card1', isOn: LOGGING_SWITCH);
        }
      }
      
      // Check card2
      final card2 = ownerCards['card2'];
      if (card2 != null) {
        final card2Id = card2 is Map ? (card2['cardId'] ?? card2['id']) : card2.toString();
        if (card2Id == cardId) {
          ownerCards['card2'] = null;
          cardRemoved = true;
          Logger().info('KnowledgeManager: Removed card $cardId from ${player['name']} known_cards[$ownerPlayerId].card2', isOn: LOGGING_SWITCH);
        }
      }
    }
    
    if (!cardRemoved) {
      Logger().info('KnowledgeManager: Card $cardId not found in ${player['name']} known_cards', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Update card ownership in player's known_cards after jack swap
  void _updateCardOwnership(Map<String, dynamic> player, String cardId, String oldOwner, String newOwner) {
    final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
    
    // Check if card exists in old owner's entry
    final oldOwnerCards = knownCards[oldOwner];
    if (oldOwnerCards is! Map) return;
    
    Map<String, dynamic>? cardToMove;
    String? cardPosition;
    
    // Find card in old owner's cards
    final card1 = oldOwnerCards['card1'];
    if (card1 != null) {
      final card1Id = card1 is Map ? (card1['cardId'] ?? card1['id']) : card1.toString();
      if (card1Id == cardId) {
        cardToMove = card1 is Map ? card1 : null;
        cardPosition = 'card1';
      }
    }
    
    if (cardToMove == null) {
      final card2 = oldOwnerCards['card2'];
      if (card2 != null) {
        final card2Id = card2 is Map ? (card2['cardId'] ?? card2['id']) : card2.toString();
        if (card2Id == cardId) {
          cardToMove = card2 is Map ? card2 : null;
          cardPosition = 'card2';
        }
      }
    }
    
    if (cardToMove == null || cardPosition == null) {
      Logger().info('KnowledgeManager: Card $cardId not found in ${player['name']} known_cards[$oldOwner]', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Remove from old owner
    oldOwnerCards[cardPosition] = null;
    
    // Add to new owner (if not already tracking)
    if (!knownCards.containsKey(newOwner)) {
      knownCards[newOwner] = {'card1': null, 'card2': null};
    }
    
    final newOwnerCards = knownCards[newOwner] as Map<String, dynamic>;
    
    // Add to first available slot
    if (newOwnerCards['card1'] == null) {
      newOwnerCards['card1'] = cardToMove;
    } else if (newOwnerCards['card2'] == null) {
      newOwnerCards['card2'] = cardToMove;
    } else {
      // Both slots full, overwrite card2
      newOwnerCards['card2'] = cardToMove;
    }
    
    Logger().info('KnowledgeManager: Moved card $cardId in ${player['name']} known_cards from $oldOwner to $newOwner', isOn: LOGGING_SWITCH);
  }
}

