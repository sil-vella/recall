/// Player Models for Recall Game
///
/// This module defines the player system for the Recall card game,
/// including human players, computer players, and AI decision making.

import 'card.dart';

enum PlayerType {
  human,
  computer,
}

enum PlayerStatus {
  waiting,           // Waiting for game to start
  ready,             // Ready to play (waiting for turn)
  playing,           // Currently playing (active turn)
  sameRankWindow,    // Window for out-of-turn same rank plays
  playingCard,       // Player is in the process of playing a card
  drawingCard,       // Player is in the process of drawing a card
  queenPeek,         // Player used queen power to peek at a card
  jackSwap,          // Player used jack power to swap cards
  peeking,           // Player is in peek phase (initial peek, queen peek, etc.)
  initialPeek,       // Player is in initial peek phase (selecting 2 of 4 cards)
  finished,          // Game finished
  disconnected,      // Disconnected from game
  winner,            // Player is the winner of the game
}

class Player {
  /// Base player class for the Recall game
  
  final String playerId;
  final PlayerType playerType;
  final String name;
  
  List<Card?> hand = [];  // 4 cards face down
  List<Card> visibleCards = [];  // Cards player has looked at
  List<Card> knownFromOtherPlayers = [];  // Cards player knows from other players
  int points = 0;
  int cardsRemaining = 4;
  bool isActive = true;
  bool hasCalledRecall = false;
  DateTime? lastActionTime;
  int initialPeeksRemaining = 2;
  List<Card> cardsToPeek = []; // Cards player has peeked at
  PlayerStatus status = PlayerStatus.waiting;  // Player status
  Card? drawnCard;  // Most recently drawn card (Card object)
  
  // Game references for change tracking
  dynamic gameStateManager;
  String? gameId;
  bool _changeTrackingEnabled = true;
  Set<String> _pendingChanges = {};

  Player({
    required this.playerId,
    required this.playerType,
    required this.name,
  });

  void addCardToHand(Card card, {bool isDrawnCard = false, bool isPenaltyCard = false}) {
    card.ownerId = playerId;
    
    // Special handling for drawn cards - always go to the end
    if (isDrawnCard) {
      hand.add(card);
      cardsRemaining = hand.length;
      
      // Manually trigger change detection for hand modification
      _trackChange('hand');
      _sendChangesIfNeeded();
      return;
    }
    
    // For penalty cards and regular cards: look for a blank slot (null) to fill first
    if (isPenaltyCard || !isDrawnCard) {
      for (int i = 0; i < hand.length; i++) {
        if (hand[i] == null) {
          hand[i] = card;
          // Don't update cardsRemaining - we're filling an existing slot
          
          // Manually trigger change detection for hand modification
          _trackChange('hand');
          _sendChangesIfNeeded();
          return;
        }
      }
    }
    
    // If no blank slot found, append to the end
    hand.add(card);
    cardsRemaining = hand.length;
    
    // Manually trigger change detection for hand modification
    _trackChange('hand');
    _sendChangesIfNeeded();
  }

  void setDrawnCard(Card card) {
    drawnCard = card;
    _trackChange('drawnCard');
    _sendChangesIfNeeded();
  }

  Card? getDrawnCard() {
    return drawnCard;
  }

  void clearDrawnCard() {
    drawnCard = null;
    _trackChange('drawnCard');
    _sendChangesIfNeeded();
  }

  Card? removeCardFromHand(String cardId) {
    for (int i = 0; i < hand.length; i++) {
      if (hand[i] != null && hand[i]!.cardId == cardId) {
        final removedCard = hand[i];
        
        // Check if we should create a blank slot or remove the card entirely
        bool shouldCreateBlankSlot = shouldCreateBlankSlotAtIndex(i);
        
        if (shouldCreateBlankSlot) {
          // Replace the card with null (blank slot) to maintain index positions
          hand[i] = null;
        } else {
          // Remove the card entirely and shift remaining cards
          hand.removeAt(i);
        }
        
        // Clear drawn card if the removed card was the drawn card
        if (drawnCard != null && drawnCard!.cardId == cardId) {
          clearDrawnCard();
        }
        
        // Manually trigger change detection for hand modification
        _trackChange('hand');
        _sendChangesIfNeeded();
        
        return removedCard;
      }
    }
    return null;
  }

  void addCardToPeek(Card card) {
    if (!cardsToPeek.contains(card)) {
      cardsToPeek.add(card);
      _trackChange('cardsToPeek');
      _sendChangesIfNeeded();
    }
  }

  void clearCardsToPeek() {
    if (cardsToPeek.isNotEmpty) {
      cardsToPeek.clear();
      _trackChange('cardsToPeek');
      _sendChangesIfNeeded();
    }
  }

  bool shouldCreateBlankSlotAtIndex(int index) {
    // If index is 3 or less, always create a blank slot (maintain initial 4-card structure)
    if (index <= 3) {
      return true;
    }
    
    // For index 4 and beyond, only create blank slot if there are actual cards further up
    // Check if there are any non-null cards at higher indices
    for (int i = index + 1; i < hand.length; i++) {
      if (hand[i] != null) {
        return true;
      }
    }
    
    // No actual cards beyond this index, so remove the card entirely
    return false;
  }

  Card? lookAtCard(String cardId) {
    for (Card? card in hand) {
      if (card != null && card.cardId == cardId) {
        card.isVisible = true;
        if (!visibleCards.contains(card)) {
          visibleCards.add(card);
        }
        _trackChange('visibleCards');
        _sendChangesIfNeeded();
        return card;
      }
    }
    return null;
  }

  Card? lookAtCardByIndex(int index) {
    if (index >= 0 && index < hand.length && hand[index] != null) {
      final card = hand[index]!;
      card.isVisible = true;
      if (!visibleCards.contains(card)) {
        visibleCards.add(card);
      }
      _trackChange('visibleCards');
      _sendChangesIfNeeded();
      return card;
    }
    return null;
  }

  List<Card> getVisibleCards() {
    return hand.where((card) => card != null && card.isVisible).cast<Card>().toList();
  }

  List<Card> getHiddenCards() {
    return hand.where((card) => card != null && !card.isVisible).cast<Card>().toList();
  }

  int calculatePoints() {
    return hand.where((card) => card != null).fold(0, (sum, card) => sum + (card?.points ?? 0));
  }

  void callRecall() {
    hasCalledRecall = true;
    _trackChange('hasCalledRecall');
    _sendChangesIfNeeded();
  }

  void updateStatus(PlayerStatus newStatus) {
    status = newStatus;
    _trackChange('status');
    _sendChangesIfNeeded();
  }

  void updatePoints() {
    points = calculatePoints();
    _trackChange('points');
    _sendChangesIfNeeded();
  }

  void setGameReferences(dynamic gameStateManager, String gameId) {
    this.gameStateManager = gameStateManager;
    this.gameId = gameId;
  }

  void _trackChange(String propertyName) {
    if (_changeTrackingEnabled) {
      _pendingChanges.add(propertyName);
    }
  }

  void _sendChangesIfNeeded() {
    if (!_changeTrackingEnabled || _pendingChanges.isEmpty) {
      return;
    }

    if (gameStateManager != null && gameId != null) {
      // Send player state update
      _pendingChanges.clear();
      
      // In a real implementation, this would send the update via WebSocket
      // For now, we'll just clear the pending changes
    }
  }

  Map<String, dynamic> toDict() {
    return {
      'player_id': playerId,
      'player_type': playerType.name,
      'name': name,
      'hand': hand.map((card) => card?.toDict()).toList(),
      'visible_cards': visibleCards.map((card) => card.toDict()).toList(),
      'known_from_other_players': knownFromOtherPlayers.map((card) => card.toDict()).toList(),
      'points': points,
      'cards_remaining': cardsRemaining,
      'is_active': isActive,
      'has_called_recall': hasCalledRecall,
      'last_action_time': lastActionTime?.toIso8601String(),
      'initial_peeks_remaining': initialPeeksRemaining,
      'cards_to_peek': cardsToPeek.map((card) => card.toDict()).toList(),
      'status': status.name,
      'drawn_card': drawnCard?.toDict(),
    };
  }

  factory Player.fromDict(Map<String, dynamic> data) {
    final player = Player(
      playerId: data['player_id'],
      playerType: PlayerType.values.firstWhere((e) => e.name == data['player_type']),
      name: data['name'],
    );
    
    player.points = data['points'] ?? 0;
    player.cardsRemaining = data['cards_remaining'] ?? 4;
    player.isActive = data['is_active'] ?? true;
    player.hasCalledRecall = data['has_called_recall'] ?? false;
    player.initialPeeksRemaining = data['initial_peeks_remaining'] ?? 2;
    player.status = PlayerStatus.values.firstWhere((e) => e.name == data['status'], orElse: () => PlayerStatus.waiting);
    
    if (data['last_action_time'] != null) {
      player.lastActionTime = DateTime.parse(data['last_action_time']);
    }
    
    if (data['drawn_card'] != null) {
      player.drawnCard = Card.fromDict(data['drawn_card']);
    }
    
    return player;
  }
}

class HumanPlayer extends Player {
  HumanPlayer({
    required String playerId,
    required String name,
  }) : super(
    playerId: playerId,
    playerType: PlayerType.human,
    name: name,
  );
}

class ComputerPlayer extends Player {
  ComputerPlayer({
    required String playerId,
    required String name,
  }) : super(
    playerId: playerId,
    playerType: PlayerType.computer,
    name: name,
  );

  Map<String, dynamic> makeDecision(Map<String, dynamic> gameState) {
    // Simple AI decision making
    // In a real implementation, this would contain sophisticated AI logic
    
    // For now, return a basic decision
    return {
      'action': 'draw_card',
      'confidence': 0.8,
    };
  }

  Map<String, dynamic> chooseCardToPlay(List<Card> availableCards) {
    // Simple AI card selection
    // In a real implementation, this would contain sophisticated AI logic
    
    if (availableCards.isEmpty) {
      return {'action': 'draw_card', 'confidence': 0.8};
    }
    
    // Simple strategy: play the lowest point card
    availableCards.sort((a, b) => a.points.compareTo(b.points));
    final chosenCard = availableCards.first;
    
    return {
      'action': 'play_card',
      'card_id': chosenCard.cardId,
      'confidence': 0.7,
    };
  }

  Map<String, dynamic> chooseCardToPeek(List<Card> availableCards) {
    // Simple AI peek selection
    // In a real implementation, this would contain sophisticated AI logic
    
    if (availableCards.isEmpty) {
      return {'action': 'skip_peek', 'confidence': 0.8};
    }
    
    // Simple strategy: peek at the first available card
    final chosenCard = availableCards.first;
    
    return {
      'action': 'peek_card',
      'card_id': chosenCard.cardId,
      'confidence': 0.6,
    };
  }
}