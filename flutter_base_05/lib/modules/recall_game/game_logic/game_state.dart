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
  Map<String, dynamic> sameRankData = {};
  
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
    try {
      int updatedCount = 0;
      
      // Update each player's status directly
      for (String playerId in players.keys) {
        final player = players[playerId]!;
        if (!filterActive || player.isActive) {
          player.updateStatus(status);
          updatedCount++;
        }
      }
      
      // Manually trigger change detection for players
      _trackChange('players');
      _sendChangesIfNeeded();
      
      Logger().info('Updated $updatedCount players\' status to ${status.name}', isOn: loggingSwitch);
      return updatedCount;
    } catch (e) {
      Logger().error('Failed to update all players status: $e', isOn: loggingSwitch);
      return 0;
    }
  }

  int updatePlayersStatusByIds(List<String> playerIds, PlayerStatus status) {
    try {
      int updatedCount = 0;
      
      for (String playerId in playerIds) {
        if (players.containsKey(playerId)) {
          players[playerId]!.updateStatus(status);
          updatedCount++;
        } else {
          Logger().warning('Player $playerId not found in game', isOn: loggingSwitch);
        }
      }
      
      // Manually trigger change detection for players
      _trackChange('players');
      _sendChangesIfNeeded();
      
      Logger().info('Updated $updatedCount players\' status to ${status.name}', isOn: loggingSwitch);
      return updatedCount;
    } catch (e) {
      Logger().error('Failed to update players status by IDs: $e', isOn: loggingSwitch);
      return 0;
    }
  }

  // ========= GAME PHASE MANAGEMENT METHODS =========
  
  void setPhase(GamePhase newPhase) {
    _previousPhase = phase;
    phase = newPhase;
    _trackChange('phase');
    _detectPhaseTransitions();
    _sendChangesIfNeeded();
  }

  void _detectPhaseTransitions() {
    try {
      if (_previousPhase != null) {
        // Log phase transition
        Logger().info('Phase transition: ${_previousPhase!.name} -> ${phase.name}', isOn: loggingSwitch);
        
        // Special handling for specific phase transitions
        if (_previousPhase == GamePhase.specialPlayWindow && phase == GamePhase.endingRound) {
          Logger().info('🎯 PHASE TRANSITION DETECTED: SPECIAL_PLAY_WINDOW → ENDING_ROUND', isOn: loggingSwitch);
          Logger().info('🎯 Game ID: $gameId', isOn: loggingSwitch);
          Logger().info('🎯 Previous phase: ${_previousPhase!.name}', isOn: loggingSwitch);
          Logger().info('🎯 Current phase: ${phase.name}', isOn: loggingSwitch);
          Logger().info('🎯 Current player: $currentPlayerId', isOn: loggingSwitch);
          Logger().info('🎯 Player count: ${players.length}', isOn: loggingSwitch);
          Logger().info('🎯 Timestamp: ${DateTime.now().toIso8601String()}', isOn: loggingSwitch);
        }
      }
    } catch (e) {
      Logger().error('❌ Error in _detectPhaseTransitions: $e', isOn: loggingSwitch);
    }
  }

  // ========= CHANGE TRACKING METHODS =========
  
  void _trackChange(String propertyName) {
    if (_changeTrackingEnabled) {
      _pendingChanges.add(propertyName);
    }
  }

  void _sendChangesIfNeeded() {
    if (!_changeTrackingEnabled || _pendingChanges.isEmpty) {
      return;
    }

    try {
      if (appManager != null) {
        // Send partial update with only changed properties
        final changesList = _pendingChanges.toList();
        
        Logger().info('🔄 _sendChangesIfNeeded called with ${_pendingChanges.length} pending changes', isOn: loggingSwitch);
        
        if (changesList.isNotEmpty) {
          Logger().info('=== SENDING PARTIAL UPDATE ===', isOn: loggingSwitch);
          Logger().info('Game ID: $gameId', isOn: loggingSwitch);
          Logger().info('Changed properties: $changesList', isOn: loggingSwitch);
          Logger().info('==============================', isOn: loggingSwitch);
          
          // In a real implementation, this would send the update via WebSocket
          // For now, we'll just log the changes
          
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

  // ========= GAME CONTROL METHODS =========
  
  void startGame() {
    gameStartTime = DateTime.now();
    setPhase(GamePhase.dealingCards);
    _trackChange('gameStartTime');
    _trackChange('phase');
    _sendChangesIfNeeded();
  }

  void endGame(String winnerId) {
    gameEnded = true;
    winner = winnerId;
    setPhase(GamePhase.gameEnded);
    _trackChange('gameEnded');
    _trackChange('winner');
    _trackChange('phase');
    _sendChangesIfNeeded();
  }

  void callRecall(String playerId) {
    recallCalledBy = playerId;
    setPhase(GamePhase.recallCalled);
    _trackChange('recallCalledBy');
    _trackChange('phase');
    _sendChangesIfNeeded();
  }

  // ========= UTILITY METHODS =========
  
  Map<String, dynamic> toDict() {
    return {
      'game_id': gameId,
      'max_players': maxPlayers,
      'min_players': minPlayers,
      'permission': permission,
      'players': players.map((key, player) => MapEntry(key, player.toDict())),
      'current_player_id': currentPlayerId,
      'phase': phase.name,
      'discard_pile': discardPile.map((card) => card.toDict()).toList(),
      'draw_pile': drawPile.map((card) => card.toDict()).toList(),
      'pending_draws': pendingDraws.map((key, card) => MapEntry(key, card.toDict())),
      'out_of_turn_deadline': outOfTurnDeadline?.toIso8601String(),
      'out_of_turn_timeout_seconds': outOfTurnTimeoutSeconds,
      'last_played_card': lastPlayedCard?.toDict(),
      'recall_called_by': recallCalledBy,
      'game_start_time': gameStartTime?.toIso8601String(),
      'last_action_time': lastActionTime?.toIso8601String(),
      'game_ended': gameEnded,
      'winner': winner,
      'game_history': gameHistory,
      'player_sessions': playerSessions,
      'session_players': sessionPlayers,
    };
  }

  factory GameState.fromDict(Map<String, dynamic> data) {
    final gameState = GameState(
      gameId: data['game_id'],
      maxPlayers: data['max_players'] ?? 4,
      minPlayers: data['min_players'] ?? 2,
      permission: data['permission'] ?? 'public',
    );
    
    gameState.currentPlayerId = data['current_player_id'];
    gameState.phase = GamePhase.values.firstWhere(
      (e) => e.name == data['phase'],
      orElse: () => GamePhase.waitingForPlayers,
    );
    gameState.recallCalledBy = data['recall_called_by'];
    gameState.gameEnded = data['game_ended'] ?? false;
    gameState.winner = data['winner'];
    
    if (data['game_start_time'] != null) {
      gameState.gameStartTime = DateTime.parse(data['game_start_time']);
    }
    if (data['last_action_time'] != null) {
      gameState.lastActionTime = DateTime.parse(data['last_action_time']);
    }
    if (data['out_of_turn_deadline'] != null) {
      gameState.outOfTurnDeadline = DateTime.parse(data['out_of_turn_deadline']);
    }
    
    return gameState;
  }

  void clearSameRankData() {
    /// Clear same rank data
    sameRankData.clear();
  }
}