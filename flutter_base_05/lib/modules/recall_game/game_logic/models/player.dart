/// Player Models for Recall Game
///
/// This module defines the player system for the Recall card game,
/// including human players, computer players, and AI decision making.

import 'card.dart';
import '../../../../tools/logging/logger.dart';

// Logging switch for this module
const bool LOGGING_SWITCH = true;

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
    return List.from(visibleCards);
  }

  List<Card> getHiddenCards() {
    return hand.where((card) => card != null && !visibleCards.contains(card)).cast<Card>().toList();
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

  void setStatus(PlayerStatus newStatus) {
    /// Set player status - alias for updateStatus to match Python version
    updateStatus(newStatus);
  }

  // ========= STATUS CHECKING METHODS =========
  
  bool isPlaying() {
    /// Check if player is currently playing (active turn)
    return status == PlayerStatus.playing;
  }

  bool isReady() {
    /// Check if player is ready (waiting for turn)
    return status == PlayerStatus.ready;
  }

  bool isWaiting() {
    /// Check if player is waiting (game not started)
    return status == PlayerStatus.waiting;
  }

  bool isSameRankWindow() {
    /// Check if player is in same rank window (can play out-of-turn)
    return status == PlayerStatus.sameRankWindow;
  }

  bool isPlayingCard() {
    /// Check if player is in process of playing a card
    return status == PlayerStatus.playingCard;
  }

  bool isDrawingCard() {
    /// Check if player is in process of drawing a card
    return status == PlayerStatus.drawingCard;
  }

  bool isQueenPeek() {
    /// Check if player is in queen peek status (used queen power)
    return status == PlayerStatus.queenPeek;
  }

  bool isJackSwap() {
    /// Check if player is in jack swap status (used jack power)
    return status == PlayerStatus.jackSwap;
  }

  bool isPeeking() {
    /// Check if player is in peeking phase
    return status == PlayerStatus.peeking;
  }

  bool isInitialPeek() {
    /// Check if player is in initial peek phase
    return status == PlayerStatus.initialPeek;
  }

  bool isFinished() {
    /// Check if player has finished the game
    return status == PlayerStatus.finished;
  }

  bool isDisconnected() {
    /// Check if player is disconnected
    return status == PlayerStatus.disconnected;
  }

  bool isWinner() {
    /// Check if player is the winner
    return status == PlayerStatus.winner;
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

  void enableChangeTracking() {
    /// Enable automatic change tracking
    _changeTrackingEnabled = true;
  }

  void disableChangeTracking() {
    /// Disable automatic change tracking
    _changeTrackingEnabled = false;
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

    if (gameStateManager == null || gameId == null) {
      return;
    }

    try {
      Logger().info('🔄 Player _sendChangesIfNeeded called with ${_pendingChanges.length} pending changes', isOn: LOGGING_SWITCH);
      Logger().info('=== SENDING PLAYER UPDATE ===', isOn: LOGGING_SWITCH);
      Logger().info('Player ID: $playerId', isOn: LOGGING_SWITCH);
      Logger().info('Changed properties: ${_pendingChanges.toList()}', isOn: LOGGING_SWITCH);
      Logger().info('=============================', isOn: LOGGING_SWITCH);
      
      // Get the coordinator from the game state manager
      if (gameStateManager.appManager != null) {
        final coordinator = gameStateManager.appManager.gameEventCoordinator;
        if (coordinator != null) {
          // Send player state update using existing coordinator method
          coordinator.sendPlayerStateUpdate(gameId!, playerId);
          Logger().info('Player update sent successfully for properties: ${_pendingChanges.toList()}', isOn: LOGGING_SWITCH);
          
          // Also trigger GameState players property change detection
          _triggerGamestatePlayersUpdate();
        } else {
          Logger().info('No coordinator found for player update', isOn: LOGGING_SWITCH);
        }
      } else {
        Logger().info('No app_manager found for player update', isOn: LOGGING_SWITCH);
      }
      
      // Clear pending changes
      _pendingChanges.clear();
      
    } catch (e) {
      Logger().error('Error in player _sendChangesIfNeeded: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _triggerGamestatePlayersUpdate() {
    /// Trigger GameState players property change detection to send room-wide update
    try {
      Logger().info('🔄 Triggering GameState players property update for player: $playerId', isOn: LOGGING_SWITCH);
      
      // Get the game state from the game state manager
      try {
        // Use reflection or try-catch to call methods dynamically
        final gameState = gameStateManager.getGame?.call(gameId);
        if (gameState != null) {
          // Try to call the change tracking methods
          gameState._trackChange?.call('players');
          gameState._sendChangesIfNeeded?.call();
          Logger().info('✅ GameState players property update triggered successfully', isOn: LOGGING_SWITCH);
        } else {
          Logger().info('❌ GameState not found', isOn: LOGGING_SWITCH);
        }
      } catch (e) {
        Logger().info('❌ GameStateManager method call failed: $e', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('❌ Error triggering GameState players update: $e', isOn: LOGGING_SWITCH);
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

  Map<String, dynamic> makeDecision(Map<String, dynamic> gameState) {
    /// Human players make decisions through WebSocket events
    // This will be handled by WebSocket events from the frontend
    return {
      'player_id': playerId,
      'decision_type': 'waiting_for_human_input',
      'available_actions': _getAvailableActions(gameState),
    };
  }

  List<String> _getAvailableActions(Map<String, dynamic> gameState) {
    /// Get available actions for the human player
    final actions = <String>[];
    
    if (gameState['current_player_id'] == playerId) {
      actions.add('play_card');
      actions.add('draw_from_discard');
      actions.add('call_recall');
    }
    
    // Check for out-of-turn plays
    if (gameState['last_played_card'] != null) {
      // This would need to be implemented based on game rules
      // For now, just add the action if there's a last played card
      actions.add('play_out_of_turn');
    }
    
    return actions;
  }
}

class ComputerPlayer extends Player {
  final String difficulty;
  
  ComputerPlayer({
    required String playerId,
    required String name,
    this.difficulty = "medium",
  }) : super(
    playerId: playerId,
    playerType: PlayerType.computer,
    name: name,
  );

  Map<String, dynamic> makeDecision(Map<String, dynamic> gameState) {
    /// Make AI decision based on game state using built-in logic
    
    // Use built-in AI logic methods
    final bestCard = _selectBestCard(gameState);
    final shouldCallRecall = _shouldCallRecall(gameState);
    
    if (shouldCallRecall) {
      return {
        'action': 'call_recall',
        'reason': 'AI decided to call recall (difficulty: $difficulty)',
        'player_id': playerId,
      };
    }
    
    if (bestCard != null) {
      // Find the card index in hand
      final cardIndex = hand.indexWhere((card) => card != null && card.cardId == bestCard.cardId);
      return {
        'action': 'play_card',
        'card_index': cardIndex != -1 ? cardIndex : 0,
        'reason': 'AI selected best card (difficulty: $difficulty)',
        'player_id': playerId,
      };
    }
    
    // Fallback: play first card
    return {
      'action': 'play_card',
      'card_index': 0,
      'reason': 'AI fallback decision (difficulty: $difficulty)',
      'player_id': playerId,
    };
  }

  double _evaluateCardValue(Card card, Map<String, dynamic> gameState) {
    /// Evaluate the value of a card in the current game state
    double baseValue = card.points.toDouble();
    
    // Factor in special powers
    if (card.hasSpecialPower()) {
      baseValue -= 2; // Prefer special power cards
    }
    
    // Factor in game progression
    if (gameState['recall_called'] == true) {
      // In final round, minimize points
      return -baseValue;
    } else {
      // During normal play, balance points and utility
      return -baseValue * 0.7 + (card.hasSpecialPower() ? 10 : 0);
    }
  }

  Card? _selectBestCard(Map<String, dynamic> gameState) {
    /// Select the best card to play
    final validCards = hand.where((card) => card != null).cast<Card>().toList();
    if (validCards.isEmpty) {
      return null;
    }
    
    // Evaluate all cards
    final cardValues = <MapEntry<Card, double>>[];
    for (final card in validCards) {
      final value = _evaluateCardValue(card, gameState);
      cardValues.add(MapEntry(card, value));
    }
    
    // Sort by value (best first)
    cardValues.sort((a, b) => b.value.compareTo(a.value));
    
    return cardValues.isNotEmpty ? cardValues.first.key : null;
  }

  bool _shouldCallRecall(Map<String, dynamic> gameState) {
    /// Determine if the computer should call Recall
    if (hasCalledRecall) {
      return false;
    }
    
    // Calculate current position
    final totalPoints = calculatePoints();
    final cardsRemaining = hand.where((card) => card != null).length;
    
    // Simple AI logic - call Recall if in good position
    if (cardsRemaining <= 1 && totalPoints <= 5) {
      return true;
    }
    
    if (cardsRemaining <= 2 && totalPoints <= 3) {
      return true;
    }
    
    return false;
  }

  void updateKnownFromOtherPlayers(Card card, Map<String, dynamic> gameState) {
    /// Update the player's known cards from other players list
    if (!knownFromOtherPlayers.any((c) => c.cardId == card.cardId)) {
      knownFromOtherPlayers.add(card);
    }
  }
}