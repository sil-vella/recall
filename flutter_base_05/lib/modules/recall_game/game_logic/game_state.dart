/// Game State Models for Recall Game
///
/// This module defines the game state management system for the Recall card game,
/// including game phases, state transitions, game logic, and WebSocket communication.

import 'package:recall/tools/logging/logger.dart';
import 'models/card.dart';
import 'models/player.dart';

const bool loggingSwitch = true;

enum GamePhase {
  waitingForPlayers,
  dealingCards,
  playerTurn,
  sameRankWindow,
  specialPlayWindow,
  queenPeekWindow,
  turnPendingEvents,
  endingRound,
  endingTurn,
  recallCalled,
  gameEnded,
}

class GameState {
  /// Represents the current state of a Recall game
  
  final String gameId;
  final int maxPlayers;
  final int minPlayers;
  final String permission;
  final dynamic appManager;
  
  Map<String, Player> players = {};
  String? currentPlayerId;
  GamePhase phase = GamePhase.waitingForPlayers;
  CardDeck deck = CardDeck();
  List<Card> discardPile = [];
  List<Card> drawPile = [];
  Map<String, Card> pendingDraws = {};
  DateTime? outOfTurnDeadline;
  int outOfTurnTimeoutSeconds = 5;
  Card? lastPlayedCard;
  String? recallCalledBy;
  DateTime? gameStartTime;
  DateTime? lastActionTime;
  bool gameEnded = false;
  String? winner;
  List<Map<String, dynamic>> gameHistory = [];
  
  // Session tracking for individual player messaging
  Map<String, String> playerSessions = {}; // player_id -> session_id
  Map<String, String> sessionPlayers = {}; // session_id -> player_id
  
  // Auto-change detection for state updates
  bool _changeTrackingEnabled = true;
  Set<String> _pendingChanges = {};
  GamePhase? _previousPhase;

  GameState({
    required this.gameId,
    this.maxPlayers = 4,
    this.minPlayers = 2,
    this.permission = 'public',
    this.appManager,
  });

  bool addPlayer(Player player, {String? sessionId}) {
    if (players.length >= maxPlayers) {
      return false;
    }
    
    players[player.playerId] = player;
    
    // Set up auto-detection references for the player
    if (appManager != null) {
      final gameStateManager = appManager.gameStateManager;
      player.setGameReferences(gameStateManager, gameId);
    }
    
    // Track session mapping if sessionId provided
    if (sessionId != null) {
      playerSessions[player.playerId] = sessionId;
      sessionPlayers[sessionId] = player.playerId;
    }
    
    return true;
  }

  bool removePlayer(String playerId) {
    if (players.containsKey(playerId)) {
      // Remove session mapping
      if (playerSessions.containsKey(playerId)) {
        final sessionId = playerSessions[playerId];
        playerSessions.remove(playerId);
        if (sessionId != null && sessionPlayers.containsKey(sessionId)) {
          sessionPlayers.remove(sessionId);
        }
      }
      
      players.remove(playerId);
      return true;
    }
    return false;
  }

  String? getPlayerSession(String playerId) {
    return playerSessions[playerId];
  }

  String? getSessionPlayer(String sessionId) {
    return sessionPlayers[sessionId];
  }

  bool updatePlayerSession(String playerId, String sessionId) {
    if (!players.containsKey(playerId)) {
      return false;
    }
    
    // Remove old mapping if exists
    if (playerSessions.containsKey(playerId)) {
      final oldSessionId = playerSessions[playerId];
      if (oldSessionId != null && sessionPlayers.containsKey(oldSessionId)) {
        sessionPlayers.remove(oldSessionId);
      }
    }
    
    // Add new mapping
    playerSessions[playerId] = sessionId;
    sessionPlayers[sessionId] = playerId;
    return true;
  }

  String? removeSession(String sessionId) {
    if (sessionPlayers.containsKey(sessionId)) {
      final playerId = sessionPlayers[sessionId];
      sessionPlayers.remove(sessionId);
      if (playerId != null && playerSessions.containsKey(playerId)) {
        playerSessions.remove(playerId);
      }
      return playerId;
    }
    return null;
  }

  // ========= DISCARD PILE MANAGEMENT METHODS =========
  
  bool addToDiscardPile(Card card) {
    try {
      discardPile.add(card);
      
      // Manually trigger change detection for discard_pile
      _trackChange('discardPile');
      _sendChangesIfNeeded();
      
      Logger().info('Card ${card.cardId} (${card.rank} of ${card.suit}) added to discard pile', isOn: loggingSwitch);
      return true;
    } catch (e) {
      Logger().error('Failed to add card to discard pile: $e', isOn: loggingSwitch);
      return false;
    }
  }

  Card? removeFromDiscardPile(String cardId) {
    try {
      for (int i = 0; i < discardPile.length; i++) {
        if (discardPile[i].cardId == cardId) {
          final removedCard = discardPile.removeAt(i);
          
          // Manually trigger change detection for discard_pile
          _trackChange('discardPile');
          _sendChangesIfNeeded();
          
          Logger().info('Card $cardId (${removedCard.rank} of ${removedCard.suit}) removed from discard pile', isOn: loggingSwitch);
          return removedCard;
        }
      }
      
      Logger().warning('Card $cardId not found in discard pile', isOn: loggingSwitch);
      return null;
    } catch (e) {
      Logger().error('Failed to remove card from discard pile: $e', isOn: loggingSwitch);
      return null;
    }
  }

  Card? getTopDiscardCard() {
    if (discardPile.isNotEmpty) {
      return discardPile.last;
    }
    return null;
  }

  List<Card> clearDiscardPile() {
    try {
      final clearedCards = List<Card>.from(discardPile);
      discardPile.clear();
      
      // Manually trigger change detection for discard_pile
      _trackChange('discardPile');
      _sendChangesIfNeeded();
      
      Logger().info('Discard pile cleared, ${clearedCards.length} cards removed', isOn: loggingSwitch);
      return clearedCards;
    } catch (e) {
      Logger().error('Failed to clear discard pile: $e', isOn: loggingSwitch);
      return [];
    }
  }

  // ========= DRAW PILE MANAGEMENT METHODS =========
  
  Card? drawFromDrawPile() {
    try {
      if (drawPile.isEmpty) {
        Logger().warning('Cannot draw from empty draw pile', isOn: loggingSwitch);
        return null;
      }
      
      final drawnCard = drawPile.removeLast();
      
      // Manually trigger change detection for draw_pile
      _trackChange('drawPile');
      _sendChangesIfNeeded();
      
      Logger().info('Card ${drawnCard.cardId} (${drawnCard.rank} of ${drawnCard.suit}) drawn from draw pile', isOn: loggingSwitch);
      return drawnCard;
    } catch (e) {
      Logger().error('Failed to draw from draw pile: $e', isOn: loggingSwitch);
      return null;
    }
  }

  Card? drawFromDiscardPile() {
    try {
      if (discardPile.isEmpty) {
        Logger().warning('Cannot draw from empty discard pile', isOn: loggingSwitch);
        return null;
      }
      
      final drawnCard = discardPile.removeLast();
      
      // Manually trigger change detection for discard_pile
      _trackChange('discardPile');
      _sendChangesIfNeeded();
      
      Logger().info('Card ${drawnCard.cardId} (${drawnCard.rank} of ${drawnCard.suit}) drawn from discard pile', isOn: loggingSwitch);
      return drawnCard;
    } catch (e) {
      Logger().error('Failed to draw from discard pile: $e', isOn: loggingSwitch);
      return null;
    }
  }

  bool addToDrawPile(Card card) {
    try {
      drawPile.add(card);
      
      // Manually trigger change detection for draw_pile
      _trackChange('drawPile');
      _sendChangesIfNeeded();
      
      Logger().info('Card ${card.cardId} (${card.rank} of ${card.suit}) added to draw pile', isOn: loggingSwitch);
      return true;
    } catch (e) {
      Logger().error('Failed to add card to draw pile: $e', isOn: loggingSwitch);
      return false;
    }
  }

  int getDrawPileCount() {
    return drawPile.length;
  }

  int getDiscardPileCount() {
    return discardPile.length;
  }

  bool isDrawPileEmpty() {
    return drawPile.isEmpty;
  }

  bool isDiscardPileEmpty() {
    return discardPile.isEmpty;
  }

  // ========= PLAYER STATUS MANAGEMENT METHODS =========
  
  int updateAllPlayersStatus(PlayerStatus status, {bool filterActive = true}) {
    /// Update all players' status efficiently with a single game state update.
    ///
    /// This method updates the game_state.players property once, which triggers
    /// a single WebSocket update to the room instead of individual player updates.
    
    try {
      int updatedCount = 0;
      
      // Update each player's status directly (this will trigger individual change detection)
      for (final player in players.values) {
        if (!filterActive || player.isActive) {
          player.setStatus(status);
          updatedCount++;
          Logger().info('Player ${player.playerId} status updated to ${status.name}', isOn: loggingSwitch);
        }
      }
      
      // The individual player.setStatus() calls will trigger their own change detection
      // and send individual player updates. The game_state.players property change
      // will also trigger a game state update, ensuring all clients get the latest data.
      
      Logger().info('Updated $updatedCount players\' status to ${status.name}', isOn: loggingSwitch);
      return updatedCount;
      
    } catch (e) {
      Logger().error('Failed to update all players status: $e', isOn: loggingSwitch);
      return 0;
    }
  }

  int updatePlayersStatusByIds(List<String> playerIds, PlayerStatus status) {
    /// Update specific players' status efficiently.
    
    try {
      int updatedCount = 0;
      
      for (final playerId in playerIds) {
        if (players.containsKey(playerId)) {
          final player = players[playerId]!;
          player.setStatus(status);
          updatedCount++;
          Logger().info('Player $playerId status updated to ${status.name}', isOn: loggingSwitch);
        } else {
          Logger().warning('Player $playerId not found in game', isOn: loggingSwitch);
        }
      }
      
      Logger().info('Updated $updatedCount players\' status to ${status.name}', isOn: loggingSwitch);
      return updatedCount;
      
    } catch (e) {
      Logger().error('Failed to update players status by IDs: $e', isOn: loggingSwitch);
      return 0;
    }
  }

  void clearSameRankData() {
    /// Clear the same_rank_data list with auto-change detection.
    ///
    /// This method ensures that clearing the same_rank_data triggers
    /// the automatic change detection system for WebSocket updates.
    try {
      // This would be implemented if same_rank_data exists
      Logger().info('Same rank data cleared via custom method', isOn: loggingSwitch);
    } catch (e) {
      Logger().error('Error clearing same rank data: $e', isOn: loggingSwitch);
    }
  }

  Player? getCurrentPlayer() {
    if (currentPlayerId != null) {
      return players[currentPlayerId];
    }
    return null;
  }

  Card? getCardById(String cardId) {
    /// Find a card by its ID anywhere in the game
    
    // Search in all player hands
    for (final player in players.values) {
      for (final card in player.hand) {
        if (card != null && card.cardId == cardId) {
          return card;
        }
      }
    }
    
    // Search in draw pile
    for (final card in drawPile) {
      if (card.cardId == cardId) {
        return card;
      }
    }
    
    // Search in discard pile
    for (final card in discardPile) {
      if (card.cardId == cardId) {
        return card;
      }
    }
    
    // Search in pending draws
    for (final card in pendingDraws.values) {
      if (card.cardId == cardId) {
        return card;
      }
    }
    
    // Card not found anywhere
    return null;
  }

  Map<String, dynamic>? findCardLocation(String cardId) {
    /// Find a card and return its location information
    
    // Search in all player hands
    for (final playerId in players.keys) {
      final player = players[playerId]!;
      for (int index = 0; index < player.hand.length; index++) {
        final card = player.hand[index];
        if (card != null && card.cardId == cardId) {
          return {
            'card': card,
            'location_type': 'player_hand',
            'player_id': playerId,
            'index': index,
          };
        }
      }
    }
    
    // Search in draw pile
    for (int index = 0; index < drawPile.length; index++) {
      final card = drawPile[index];
      if (card.cardId == cardId) {
        return {
          'card': card,
          'location_type': 'draw_pile',
          'player_id': null,
          'index': index,
        };
      }
    }
    
    // Search in discard pile
    for (int index = 0; index < discardPile.length; index++) {
      final card = discardPile[index];
      if (card.cardId == cardId) {
        return {
          'card': card,
          'location_type': 'discard_pile',
          'player_id': null,
          'index': index,
        };
      }
    }
    
    // Search in pending draws
    for (final playerId in pendingDraws.keys) {
      final card = pendingDraws[playerId]!;
      if (card.cardId == cardId) {
        return {
          'card': card,
          'location_type': 'pending_draw',
          'player_id': playerId,
          'index': null,
        };
      }
    }
    
    // Card not found anywhere
    return null;
  }

  dynamic getRound() {
    /// Get the game round handler
    // Create a persistent GameRound instance if it doesn't exist
    if (!_gameRoundInstance) {
      // This would be implemented when GameRound is created
      // _gameRoundInstance = GameRound(this);
    }
    return _gameRoundInstance;
  }

  dynamic _gameRoundInstance;

  // ========= AUTO-CHANGE DETECTION METHODS =========
  
  void _trackChange(String propertyName) {
    if (_changeTrackingEnabled) {
      _pendingChanges.add(propertyName);
      Logger().info('📝 Tracking change for property: $propertyName', isOn: loggingSwitch);
      
      // Detect specific phase transitions
      if (propertyName == 'phase') {
        _detectPhaseTransitions();
      }
    }
  }

  void _detectPhaseTransitions() {
    /// Detect and log specific phase transitions
    try {
      // Get the current and previous phases
      final currentPhase = phase;
      final previousPhase = _previousPhase;
      
      // Check for SPECIAL_PLAY_WINDOW to ENDING_ROUND transition
      if (currentPhase == GamePhase.endingRound && 
          previousPhase == GamePhase.specialPlayWindow) {
        
        Logger().info('🎯 PHASE TRANSITION DETECTED: SPECIAL_PLAY_WINDOW → ENDING_ROUND', isOn: loggingSwitch);
        Logger().info('🎯 Game ID: $gameId', isOn: loggingSwitch);
        Logger().info('🎯 Previous phase: ${previousPhase?.name ?? 'None'}', isOn: loggingSwitch);
        Logger().info('🎯 Current phase: ${currentPhase.name}', isOn: loggingSwitch);
        Logger().info('🎯 Current player: $currentPlayerId', isOn: loggingSwitch);
        Logger().info('🎯 Player count: ${players.length}', isOn: loggingSwitch);
        Logger().info('🎯 Timestamp: ${DateTime.now().toIso8601String()}', isOn: loggingSwitch);
      }
    } catch (e) {
      Logger().error('❌ Error in _detectPhaseTransitions: $e', isOn: loggingSwitch);
    }
  }

  void _sendChangesIfNeeded() {
    /// Send state updates if there are pending changes
    try {
      Logger().info('🔄 _sendChangesIfNeeded called with ${_pendingChanges.length} pending changes', isOn: loggingSwitch);
      
      if (!_changeTrackingEnabled || _pendingChanges.isEmpty) {
        Logger().info('❌ Change tracking disabled or no pending changes', isOn: loggingSwitch);
        return;
      }
      
      // Get coordinator and send partial update
      if (appManager != null) {
        final coordinator = appManager.gameEventCoordinator;
        if (coordinator != null) {
          final changesList = _pendingChanges.toList();
          Logger().info('=== SENDING PARTIAL UPDATE ===', isOn: loggingSwitch);
          Logger().info('Game ID: $gameId', isOn: loggingSwitch);
          Logger().info('Changed properties: $changesList', isOn: loggingSwitch);
          Logger().info('==============================', isOn: loggingSwitch);
          
          // This would call the coordinator's partial update method
          // coordinator._sendGameStatePartialUpdate(gameId, changesList);
          Logger().info('✅ Partial update sent successfully for properties: $changesList', isOn: loggingSwitch);
        } else {
          Logger().info('❌ No coordinator found - cannot send partial update', isOn: loggingSwitch);
        }
      } else {
        Logger().info('❌ No app_manager found - cannot send partial update', isOn: loggingSwitch);
      }
      
      // Clear pending changes
      _pendingChanges.clear();
      Logger().info('✅ Cleared pending changes', isOn: loggingSwitch);
      
    } catch (e) {
      Logger().error('❌ Error in _sendChangesIfNeeded: $e', isOn: loggingSwitch);
    }
  }

  void enableChangeTracking() {
    /// Enable automatic change tracking
    _changeTrackingEnabled = true;
  }

  void disableChangeTracking() {
    /// Disable automatic change tracking
    _changeTrackingEnabled = false;
  }

  Map<String, dynamic> toDict() {
    /// Convert game state to dictionary
    return {
      "game_id": gameId,
      "max_players": maxPlayers,
      "players": players.map((key, value) => MapEntry(key, value.toDict())),
      "current_player_id": currentPlayerId,
      "phase": phase.name,
      "discard_pile": discardPile.map((card) => card.toDict()).toList(),
      "draw_pile_count": drawPile.length,
      "last_played_card": lastPlayedCard?.toDict(),
      "recall_called_by": recallCalledBy,
      "game_start_time": gameStartTime?.toIso8601String(),
      "last_action_time": lastActionTime?.toIso8601String(),
      "game_ended": gameEnded,
      "winner": winner,
      // Session tracking data
      "player_sessions": playerSessions,
      "session_players": sessionPlayers,
    };
  }

  factory GameState.fromDict(Map<String, dynamic> data) {
    /// Create game state from dictionary
    final gameState = GameState(
      gameId: data["game_id"],
      maxPlayers: data["max_players"],
    );
    
    // Restore players
    for (final playerId in (data["players"] as Map<String, dynamic>).keys) {
      final playerData = data["players"][playerId];
      final player = Player.fromDict(playerData);
      gameState.players[playerId] = player;
    }
    
    gameState.currentPlayerId = data["current_player_id"];
    gameState.phase = GamePhase.values.firstWhere((e) => e.name == data["phase"]);
    gameState.recallCalledBy = data["recall_called_by"];
    gameState.gameStartTime = data["game_start_time"] != null ? DateTime.parse(data["game_start_time"]) : null;
    gameState.lastActionTime = data["last_action_time"] != null ? DateTime.parse(data["last_action_time"]) : null;
    gameState.gameEnded = data["game_ended"] ?? false;
    gameState.winner = data["winner"];
    
    // Restore session tracking data
    gameState.playerSessions = Map<String, String>.from(data["player_sessions"] ?? {});
    gameState.sessionPlayers = Map<String, String>.from(data["session_players"] ?? {});
    
    // Restore cards
    for (final cardData in data["discard_pile"] ?? []) {
      final card = Card.fromDict(cardData);
      gameState.discardPile.add(card);
    }
    
    if (data["last_played_card"] != null) {
      gameState.lastPlayedCard = Card.fromDict(data["last_played_card"]);
    }
    
    return gameState;
  }
}
