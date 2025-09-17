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
  
  List<Card?> hand = [];
  List<Card> visibleCards = [];
  List<Card> cardsToPeek = [];
  int score = 0;
  PlayerStatus status = PlayerStatus.waiting;
  bool hasCalledRecall = false;
  Card? drawnCard;
  bool isActive = true;
  
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
    if (isDrawnCard) {
      // Add drawn cards to the end
      hand.add(card);
    } else if (isPenaltyCard) {
      // Add penalty cards to the end
      hand.add(card);
    } else {
      // Add regular cards to the end
      hand.add(card);
    }
    
    // Update score
    score = calculatePoints();
    
    // Track change
    _trackChange('hand');
    _trackChange('score');
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
        hand[i] = null; // Create blank slot
        _trackChange('hand');
        _sendChangesIfNeeded();
        return removedCard;
      }
    }
    return null;
  }

  void addCardToPeek(Card card) {
    cardsToPeek.add(card);
    _trackChange('cardsToPeek');
    _sendChangesIfNeeded();
  }

  void clearCardsToPeek() {
    cardsToPeek.clear();
    _trackChange('cardsToPeek');
    _sendChangesIfNeeded();
  }

  bool _shouldCreateBlankSlotAtIndex(int index) {
    // Smart blank slot logic - only create blank slots in the first 4 positions
    // This maintains the original 4-card hand structure
    return index < 4;
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

  void setStatus(PlayerStatus newStatus) {
    if (status != newStatus) {
      status = newStatus;
      _trackChange('status');
      _sendChangesIfNeeded();
    }
  }

  // Status check methods
  bool isPlaying() => status == PlayerStatus.playing;
  bool isReady() => status == PlayerStatus.ready;
  bool isWaiting() => status == PlayerStatus.waiting;
  bool isSameRankWindow() => status == PlayerStatus.sameRankWindow;
  bool isPlayingCard() => status == PlayerStatus.playingCard;
  bool isDrawingCard() => status == PlayerStatus.drawingCard;
  bool isQueenPeek() => status == PlayerStatus.queenPeek;
  bool isJackSwap() => status == PlayerStatus.jackSwap;
  bool isFinished() => status == PlayerStatus.finished;
  bool isDisconnected() => status == PlayerStatus.disconnected;

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

    // Send changes to game state manager if available
    if (gameStateManager != null && gameId != null) {
      // This would trigger a game state update
      // Implementation depends on the game state manager
    }

    _pendingChanges.clear();
  }

  void _triggerGamestatePlayersUpdate() {
    // Trigger a game state update for players
    if (gameStateManager != null && gameId != null) {
      // Implementation depends on the game state manager
    }
  }

  void enableChangeTracking() {
    _changeTrackingEnabled = true;
  }

  void disableChangeTracking() {
    _changeTrackingEnabled = false;
  }

  Map<String, dynamic> toDict() {
    return {
      "player_id": playerId,
      "player_type": playerType.name,
      "name": name,
      "hand": hand.map((card) => card?.toDict()).toList(),
      "visible_cards": visibleCards.map((card) => card.toDict()).toList(),
      "cards_to_peek": cardsToPeek.map((card) => card.toDict()).toList(),
      "score": score,
      "status": status.name,
      "has_called_recall": hasCalledRecall,
      "drawn_card": drawnCard?.toDict(),
      "is_active": isActive,
    };
  }

  factory Player.fromDict(Map<String, dynamic> data) {
    final player = Player(
      playerId: data["player_id"],
      playerType: PlayerType.values.firstWhere((e) => e.name == data["player_type"]),
      name: data["name"],
    );
    
    player.hand = (data["hand"] as List).map((cardData) => 
      cardData != null ? Card.fromDict(cardData) : null
    ).toList();
    
    player.visibleCards = (data["visible_cards"] as List).map((cardData) => 
      Card.fromDict(cardData)
    ).toList();
    
    player.cardsToPeek = (data["cards_to_peek"] as List).map((cardData) => 
      Card.fromDict(cardData)
    ).toList();
    
    player.score = data["score"];
    player.status = PlayerStatus.values.firstWhere((e) => e.name == data["status"]);
    player.hasCalledRecall = data["has_called_recall"];
    player.drawnCard = data["drawn_card"] != null ? Card.fromDict(data["drawn_card"]) : null;
    player.isActive = data["is_active"];
    
    return player;
  }
}

class HumanPlayer extends Player {
  /// Human player class
  
  HumanPlayer(String playerId, String name) : super(
    playerId: playerId,
    playerType: PlayerType.human,
    name: name,
  );

  Map<String, dynamic> makeDecision(Map<String, dynamic> gameState) {
    // Human players make decisions through UI
    return {
      "action": "waiting_for_input",
      "message": "Human player decision required",
    };
  }

  List<String> _getAvailableActions(Map<String, dynamic> gameState) {
    // Return available actions for human player
    return [
      "draw_card",
      "play_card",
      "discard_card",
      "call_recall",
    ];
  }
}

class ComputerPlayer extends Player {
  /// Computer player class with AI decision making
  
  final String difficulty;

  ComputerPlayer(String playerId, String name, {this.difficulty = "medium"}) : super(
    playerId: playerId,
    playerType: PlayerType.computer,
    name: name,
  );

  Map<String, dynamic> makeDecision(Map<String, dynamic> gameState) {
    // AI decision making based on difficulty
    switch (difficulty) {
      case "easy":
        return _makeEasyDecision(gameState);
      case "medium":
        return _makeMediumDecision(gameState);
      case "hard":
        return _makeHardDecision(gameState);
      default:
        return _makeMediumDecision(gameState);
    }
  }

  Map<String, dynamic> _makeEasyDecision(Map<String, dynamic> gameState) {
    // Simple AI - random decisions
    final actions = _getAvailableActions(gameState);
    if (actions.isNotEmpty) {
      final randomAction = actions[DateTime.now().millisecondsSinceEpoch % actions.length];
      return {
        "action": randomAction,
        "confidence": 0.5,
      };
    }
    return {"action": "wait", "confidence": 0.0};
  }

  Map<String, dynamic> _makeMediumDecision(Map<String, dynamic> gameState) {
    // Medium AI - basic strategy
    final bestCard = _selectBestCard(gameState);
    if (bestCard != null) {
      return {
        "action": "play_card",
        "card_id": bestCard.cardId,
        "confidence": 0.7,
      };
    }
    return {"action": "draw_card", "confidence": 0.6};
  }

  Map<String, dynamic> _makeHardDecision(Map<String, dynamic> gameState) {
    // Hard AI - advanced strategy
    final bestCard = _selectBestCard(gameState);
    if (bestCard != null) {
      return {
        "action": "play_card",
        "card_id": bestCard.cardId,
        "confidence": 0.9,
      };
    }
    return {"action": "draw_card", "confidence": 0.8};
  }

  double _evaluateCardValue(Card card, Map<String, dynamic> gameState) {
    // Evaluate card value based on game state
    double value = card.points.toDouble();
    
    // Reduce value for special cards in early game
    if (card.hasSpecialPower()) {
      value *= 0.8;
    }
    
    return value;
  }

  Card? _selectBestCard(Map<String, dynamic> gameState) {
    // Select the best card to play
    final playableCards = hand.where((card) => card != null).cast<Card>().toList();
    if (playableCards.isEmpty) return null;
    
    // Sort by value (ascending for Recall game - lower is better)
    playableCards.sort((a, b) => _evaluateCardValue(a, gameState).compareTo(_evaluateCardValue(b, gameState)));
    
    return playableCards.first;
  }

  bool _shouldCallRecall(Map<String, dynamic> gameState) {
    // Determine if computer should call recall
    final totalPoints = calculatePoints();
    final handSize = hand.where((card) => card != null).length;
    
    // Call recall if hand is small and points are low
    return handSize <= 2 && totalPoints <= 5;
  }

  void _updateKnownFromOtherPlayers(Card card, Map<String, dynamic> gameState) {
    // Update computer's knowledge about other players' cards
    // This would be implemented based on the specific AI strategy
  }

  List<String> _getAvailableActions(Map<String, dynamic> gameState) {
    // Return available actions for computer player
    return [
      "draw_card",
      "play_card",
      "discard_card",
      "call_recall",
    ];
  }
}
