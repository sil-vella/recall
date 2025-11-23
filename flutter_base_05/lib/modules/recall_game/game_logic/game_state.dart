/// Game State Models for Recall Game
///
/// This module defines the game state management system for the Recall card game,
/// including game phases, state transitions, game logic, and WebSocket communication.

import 'package:recall/tools/logging/logger.dart';
import 'models/card.dart';
import 'models/player.dart';

const bool LOGGING_SWITCH = false;

enum GamePhase {
  waitingForPlayers,
  dealingCards,
  initialPeek,
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
  
  final Logger _logger = Logger();
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
  bool _initialized = true; // Flag to prevent tracking during initialization
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
      
      _logger.info('Card ${card.cardId} (${card.rank} of ${card.suit}) added to discard pile', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      _logger.error('Failed to add card to discard pile: $e', isOn: LOGGING_SWITCH);
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
          
          _logger.info('Card $cardId (${removedCard.rank} of ${removedCard.suit}) removed from discard pile', isOn: LOGGING_SWITCH);
          return removedCard;
        }
      }
      
      _logger.warning('Card $cardId not found in discard pile', isOn: LOGGING_SWITCH);
      return null;
    } catch (e) {
      _logger.error('Failed to remove card from discard pile: $e', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Discard pile cleared, ${clearedCards.length} cards removed', isOn: LOGGING_SWITCH);
      return clearedCards;
    } catch (e) {
      _logger.error('Failed to clear discard pile: $e', isOn: LOGGING_SWITCH);
      return [];
    }
  }

  // ========= DRAW PILE MANAGEMENT METHODS =========
  
  Card? drawFromDrawPile() {
    try {
      if (drawPile.isEmpty) {
        _logger.warning('Cannot draw from empty draw pile', isOn: LOGGING_SWITCH);
        return null;
      }
      
      final drawnCard = drawPile.removeLast();
      
      // Manually trigger change detection for draw_pile
      _trackChange('drawPile');
      _sendChangesIfNeeded();
      
      _logger.info('Card ${drawnCard.cardId} (${drawnCard.rank} of ${drawnCard.suit}) drawn from draw pile', isOn: LOGGING_SWITCH);
      return drawnCard;
    } catch (e) {
      _logger.error('Failed to draw from draw pile: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }
  
  Card? drawFromDiscardPile() {
    try {
      if (discardPile.isEmpty) {
        _logger.warning('Cannot draw from empty discard pile', isOn: LOGGING_SWITCH);
        return null;
      }
      
      final drawnCard = discardPile.removeLast();
      
      // Manually trigger change detection for discard_pile
      _trackChange('discardPile');
      _sendChangesIfNeeded();
      
      _logger.info('Card ${drawnCard.cardId} (${drawnCard.rank} of ${drawnCard.suit}) drawn from discard pile', isOn: LOGGING_SWITCH);
      return drawnCard;
    } catch (e) {
      _logger.error('Failed to draw from discard pile: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }
  
  bool addToDrawPile(Card card) {
    try {
      drawPile.add(card);
      
      // Manually trigger change detection for draw_pile
      _trackChange('drawPile');
      _sendChangesIfNeeded();
      
      _logger.info('Card ${card.cardId} (${card.rank} of ${card.suit}) added to draw pile', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      _logger.error('Failed to add card to draw pile: $e', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Updated $updatedCount players\' status to ${status.name}', isOn: LOGGING_SWITCH);
      return updatedCount;
    } catch (e) {
      _logger.error('Failed to update all players status: $e', isOn: LOGGING_SWITCH);
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
          _logger.warning('Player $playerId not found in game', isOn: LOGGING_SWITCH);
        }
      }
      
      // Manually trigger change detection for players
      _trackChange('players');
      _sendChangesIfNeeded();
      
      _logger.info('Updated $updatedCount players\' status to ${status.name}', isOn: LOGGING_SWITCH);
      return updatedCount;
    } catch (e) {
      _logger.error('Failed to update players status by IDs: $e', isOn: LOGGING_SWITCH);
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
        _logger.info('Phase transition: ${_previousPhase!.name} -> ${phase.name}', isOn: LOGGING_SWITCH);
        
        // Special handling for specific phase transitions
        if (_previousPhase == GamePhase.specialPlayWindow && phase == GamePhase.endingRound) {
          _logger.info('🎯 PHASE TRANSITION DETECTED: SPECIAL_PLAY_WINDOW → ENDING_ROUND', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Game ID: $gameId', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Previous phase: ${_previousPhase!.name}', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Current phase: ${phase.name}', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Current player: $currentPlayerId', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Player count: ${players.length}', isOn: LOGGING_SWITCH);
          _logger.info('🎯 Timestamp: ${DateTime.now().toIso8601String()}', isOn: LOGGING_SWITCH);
        }
      }
    } catch (e) {
      _logger.error('❌ Error in _detectPhaseTransitions: $e', isOn: LOGGING_SWITCH);
    }
  }

  // ========= CHANGE TRACKING METHODS =========
  
  void _trackChange(String propertyName) {
    if (_changeTrackingEnabled) {
      _pendingChanges.add(propertyName);
      _logger.info('📝 Tracking change for property: $propertyName', isOn: LOGGING_SWITCH);
      
      // Detect specific phase transitions
      if (propertyName == 'phase') {
        _detectPhaseTransitions();
      }
    }
  }

  void _sendChangesIfNeeded() {
    if (!_changeTrackingEnabled || _pendingChanges.isEmpty) {
      _logger.info('❌ Change tracking disabled or no pending changes', isOn: LOGGING_SWITCH);
      return;
    }

    try {
      _logger.info('🔄 _sendChangesIfNeeded called with ${_pendingChanges.length} pending changes', isOn: LOGGING_SWITCH);
      
      if (appManager != null) {
        // Get coordinator and send partial update
        final coordinator = appManager.gameEventCoordinator;
        if (coordinator != null) {
        final changesList = _pendingChanges.toList();
          _logger.info('=== SENDING PARTIAL UPDATE ===', isOn: LOGGING_SWITCH);
          _logger.info('Game ID: $gameId', isOn: LOGGING_SWITCH);
          _logger.info('Changed properties: $changesList', isOn: LOGGING_SWITCH);
          _logger.info('==============================', isOn: LOGGING_SWITCH);
          
          // Send partial update via coordinator
          coordinator.sendGameStatePartialUpdate(gameId, changesList);
          _logger.info('✅ Partial update sent successfully for properties: $changesList', isOn: LOGGING_SWITCH);
        } else {
          _logger.info('❌ No coordinator found - cannot send partial update', isOn: LOGGING_SWITCH);
        }
      } else {
        _logger.info('❌ No app_manager found - cannot send partial update', isOn: LOGGING_SWITCH);
      }
      
      // Clear pending changes
      _pendingChanges.clear();
      _logger.info('✅ Cleared pending changes', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error in _sendChangesIfNeeded: $e', isOn: LOGGING_SWITCH);
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
    /// Clear the same_rank_data list with auto-change detection.
    /// 
    /// This method ensures that clearing the same_rank_data triggers
    /// the automatic change detection system for WebSocket updates.
    try {
      // Check if same_rank_data property exists and clear it
      // Note: In Dart, we need to implement this differently since we don't have
      // dynamic property addition like Python's hasattr
      _logger.info("Same rank data cleared via custom method", isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('Error clearing same rank data: $e', isOn: LOGGING_SWITCH);
    }
  }

  // ========= CARD LOOKUP METHODS =========
  
  Card? getCardById(String cardId) {
    /// Find a card by its ID anywhere in the game
    /// 
    /// Searches through all game locations:
    /// - All player hands
    /// - Draw pile
    /// - Discard pile
    /// - Pending draws
    /// 
    /// Args:
    ///   cardId: The unique card ID to search for
    /// 
    /// Returns:
    ///   Card?: The card object if found, null otherwise
    
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
    /// 
    /// Args:
    ///   cardId: The unique card ID to search for
    /// 
    /// Returns:
    ///   Map<String, dynamic>?: Location info with keys:
    ///     - 'card': The Card object
    ///     - 'location_type': 'player_hand', 'draw_pile', 'discard_pile', 'pending_draw'
    ///     - 'player_id': Player ID (if in player's possession)
    ///     - 'index': Position in collection (if applicable)
    
    // Search in all player hands
    for (final entry in players.entries) {
      final playerId = entry.key;
      final player = entry.value;
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
    for (final entry in pendingDraws.entries) {
      final playerId = entry.key;
      final card = entry.value;
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
    /// Create a persistent GameRound instance if it doesn't exist
    if (_gameRoundInstance == null) {
      _logger.info('Creating new GameRound instance for game $gameId', isOn: LOGGING_SWITCH);
      // Import GameRound dynamically to avoid circular dependency
      // This will need to be implemented when GameRound class is available
      // _gameRoundInstance = GameRound(this);
    }
    return _gameRoundInstance;
  }
  
  dynamic _gameRoundInstance;

  Player? getCurrentPlayer() {
    /// Get the current player
    if (currentPlayerId != null && players.containsKey(currentPlayerId)) {
      return players[currentPlayerId];
    }
    return null;
  }
}

class GameStateManager {
  /// Manages multiple game states with integrated WebSocket communication
  
  final Logger _logger = Logger();
  Map<String, GameState> activeGames = {}; // game_id -> GameState
  dynamic appManager;
  dynamic websocketManager;
  dynamic gameLogicEngine;
  bool _initialized = false;

  GameStateManager();

  bool initialize(dynamic appManager, dynamic gameLogicEngine) {
    /// Initialize with WebSocket and game engine support
    try {
      this.appManager = appManager;
      websocketManager = appManager?.websocketManager;
      this.gameLogicEngine = gameLogicEngine;
      
      if (websocketManager == null) {
        return false;
      }
      
      // Register hook callbacks for automatic game creation
      _registerHookCallbacks();
      
      _initialized = true;
      _logger.info('GameStateManager initialized successfully', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      _logger.error('Failed to initialize GameStateManager: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  bool get isInitialized => _initialized;

  String createGame({int maxPlayers = 4, int minPlayers = 2, String permission = 'public'}) {
    /// Create a new game
    final gameId = DateTime.now().millisecondsSinceEpoch.toString(); // Simple ID generation
    final gameState = GameState(
      gameId: gameId,
      maxPlayers: maxPlayers,
      minPlayers: minPlayers,
      permission: permission,
      appManager: appManager,
    );
    activeGames[gameId] = gameState;
    return gameId;
  }

  String createGameWithId(String gameId, {int maxPlayers = 4, int minPlayers = 2, String permission = 'public'}) {
    /// Create a new game using a provided identifier (e.g., room_id).
    /// 
    /// This aligns backend game identity with the room identifier used by the
    /// frontend so join/start flows can address the same id across the stack.
    /// If a game with this id already exists, it is returned unchanged.
    final existing = activeGames[gameId];
    if (existing != null) {
      return gameId;
    }
    
    final gameState = GameState(
      gameId: gameId,
      maxPlayers: maxPlayers,
      minPlayers: minPlayers,
      permission: permission,
      appManager: appManager,
    );
    activeGames[gameId] = gameState;
    return gameId;
  }

  GameState? getGame(String gameId) {
    /// Get a game by ID
    return activeGames[gameId];
  }

  bool removeGame(String gameId) {
    /// Remove a game
    if (activeGames.containsKey(gameId)) {
      activeGames.remove(gameId);
      return true;
    }
    return false;
  }

  Map<String, GameState> getAllGames() {
    /// Get all active games
    return Map<String, GameState>.from(activeGames);
  }

  List<Map<String, dynamic>> getAvailableGames() {
    /// Get all public games that are in the waiting for players phase and can be joined
    final availableGames = <Map<String, dynamic>>[];
    
    for (final entry in activeGames.entries) {
      final game = entry.value;
      
      // Only include PUBLIC games that are waiting for players
      if (game.phase == GamePhase.waitingForPlayers && game.permission == 'public') {
        // Convert to Flutter-compatible format
        final gameData = _toFlutterGameData(game);
        availableGames.add(gameData);
      }
    }
    
    return availableGames;
  }

  Map<String, dynamic> _toFlutterGameData(GameState game) {
    /// Convert game state to Flutter format - SINGLE SOURCE OF TRUTH for game data structure
    /// 
    /// This method structures ALL game data that will be sent to the frontend.
    /// The structure MUST match the Flutter frontend schema exactly.
    
    // Get current player data
    Map<String, dynamic>? currentPlayer;
    if (game.currentPlayerId != null && game.players.containsKey(game.currentPlayerId)) {
      currentPlayer = _toFlutterPlayerData(game.players[game.currentPlayerId]!, true);
    }

    // Build complete game data structure matching Flutter schema
    return {
      // Core game identification
      'gameId': game.gameId,
      'gameName': 'Recall Game ${game.gameId}',
      
      // Player information
      'players': game.players.entries.map((entry) => 
        _toFlutterPlayerData(entry.value, entry.key == game.currentPlayerId)
      ).toList(),
      'currentPlayer': currentPlayer,
      'playerCount': game.players.length,
      'maxPlayers': game.maxPlayers,
      'minPlayers': game.minPlayers,
      'activePlayerCount': game.players.values.where((p) => p.isActive).length,
      
      // Game state and phase - send phase value directly without mapping
      'phase': game.phase.name,
      'status': _getGameStatus(game),
      
      // Card piles
      'drawPile': game.drawPile.map((card) => _toFlutterCard(card)).toList(),
      'discardPile': game.discardPile.map((card) => _toFlutterCard(card)).toList(),
      
      // Game timing
      'gameStartTime': game.gameStartTime?.toIso8601String(),
      'lastActivityTime': game.lastActionTime?.toIso8601String(),
      
      // Game completion
      'winner': game.winner,
      'gameEnded': game.gameEnded,
      
      // Room settings
      'permission': game.permission,
      
      // Additional game metadata
      'recallCalledBy': game.recallCalledBy,
      'lastPlayedCard': game.lastPlayedCard != null ? _toFlutterCard(game.lastPlayedCard!) : null,
      'outOfTurnDeadline': game.outOfTurnDeadline?.toIso8601String(),
      'outOfTurnTimeoutSeconds': game.outOfTurnTimeoutSeconds,
    };
  }

  String _getGameStatus(GameState game) {
    /// Get game status based on phase
    final activePhases = ['player_turn', 'same_rank_window', 'ending_round', 'ending_turn', 'recall_called'];
    return activePhases.contains(game.phase.name) ? 'active' : 'inactive';
  }

  Map<String, dynamic> _toFlutterPlayerData(Player player, bool isCurrent) {
    /// Convert player to Flutter format - SINGLE SOURCE OF TRUTH for player data structure
    return {
      'id': player.playerId,
      'name': player.name,
      'type': player.playerType.name.toLowerCase(),
      'hand': player.hand.map((card) => card != null ? _toFlutterCard(card) : null).toList(),
      'visibleCards': player.visibleCards.map((card) => _toFlutterCard(card)).toList(),
      'cardsToPeek': player.cardsToPeek.map((card) => _toFlutterCard(card)).toList(),
      'score': player.calculatePoints(),
      'status': player.status.name.toLowerCase(),
      'isCurrentPlayer': isCurrent,
      'hasCalledRecall': player.hasCalledRecall,
      'drawnCard': player.drawnCard != null ? _toFlutterCard(player.drawnCard!) : null,
    };
  }

  Map<String, dynamic> _toFlutterCard(Card card) {
    /// Convert card to Flutter format
    final rankMapping = {
      '2': 'two', '3': 'three', '4': 'four', '5': 'five',
      '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
    };
    
    return {
      'cardId': card.cardId,
      'suit': card.suit,
      'rank': rankMapping[card.rank] ?? card.rank,
      'points': card.points,
      'displayName': card.toString(),
      'color': ['hearts', 'diamonds'].contains(card.suit) ? 'red' : 'black',
    };
  }

  void _registerHookCallbacks() {
    /// Register hook callbacks for automatic game creation
    try {
      // Register callback for room_created hook
      appManager?.registerHookCallback('room_created', _onRoomCreated);
      
      // Register callback for room_joined hook  
      appManager?.registerHookCallback('room_joined', _onRoomJoined);
      
      // Register callback for room_closed hook
      appManager?.registerHookCallback('room_closed', _onRoomClosed);
      
      // Register callback for leave_room hook
      appManager?.registerHookCallback('leave_room', _onLeaveRoom);
      
    } catch (e) {
      _logger.error('Failed to register hook callbacks: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _onRoomCreated(Map<String, dynamic> roomData) {
    /// Callback for room_created hook - automatically create game
    try {
      final roomId = roomData['room_id'] as String?;
      final maxPlayers = roomData['max_players'] as int? ?? 4;
      final minPlayers = roomData['min_players'] as int? ?? 2;
      final permission = roomData['permission'] as String? ?? 'public';
      
      if (roomId != null) {
        // Create game with room_id as game_id and room permission
        createGameWithId(roomId, maxPlayers: maxPlayers, minPlayers: minPlayers, permission: permission);
        
        // Initialize game state (waiting for players)
        final game = getGame(roomId);
        if (game != null) {
          game.setPhase(GamePhase.waitingForPlayers);
        }
      }
    } catch (e) {
      _logger.error('Failed to handle room created: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _onRoomJoined(Map<String, dynamic> roomData) {
    /// Callback for room_joined hook - handle player joining existing game
    try {
      final roomId = roomData['room_id'] as String?;
      final userId = roomData['user_id'] as String?;
      final sessionId = roomData['session_id'] as String?;
      
      if (roomId == null || userId == null) return;
      
      // Check if game exists for this room
      final game = getGame(roomId);
      if (game == null) return;
      
      // Add player to the game if they don't exist
      if (!game.players.containsKey(userId)) {
        final player = Player(
          playerId: userId,
          name: 'Player_${userId.substring(0, 8)}',
          playerType: PlayerType.human,
        );
        game.addPlayer(player, sessionId: sessionId);
      }
      
      // Set up session mapping for the player
      if (sessionId != null) {
        game.updatePlayerSession(userId, sessionId);
      }
      
    } catch (e) {
      _logger.error('Failed to handle room joined: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _onRoomClosed(Map<String, dynamic> roomData) {
    /// Callback for room_closed hook - cleanup game when room is closed
    try {
      final roomId = roomData['room_id'] as String?;
      
      if (roomId != null && activeGames.containsKey(roomId)) {
        removeGame(roomId);
      }
    } catch (e) {
      _logger.error('Failed to handle room closed: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _onLeaveRoom(Map<String, dynamic> roomData) {
    /// Callback for leave_room hook - handle player leaving game
    try {
      final roomId = roomData['room_id'] as String?;
      final sessionId = roomData['session_id'] as String?;
      final userId = roomData['user_id'] as String?;
      
      if (roomId == null) return;
      
      // Check if game exists for this room
      final game = getGame(roomId);
      if (game == null) return;
      
      // Try to find player by session_id first
      String? playerId;
      if (sessionId != null) {
        playerId = game.getSessionPlayer(sessionId);
      }
      
      // Fallback: try to find player by user_id if session lookup failed
      if (playerId == null && userId != null && game.players.containsKey(userId)) {
        playerId = userId;
      }
      
      // Remove player if found
      if (playerId != null) {
        game.removePlayer(playerId);
        
        // Clean up session mapping
        if (sessionId != null) {
          game.removeSession(sessionId);
        }
      }
      
    } catch (e) {
      _logger.error('Failed to handle leave room: $e', isOn: LOGGING_SWITCH);
    }
  }

  void cleanupEndedGames() {
    /// Remove games that have ended
    final endedGames = <String>[];
    for (final entry in activeGames.entries) {
      if (entry.value.gameEnded) {
        endedGames.add(entry.key);
      }
    }
    
    for (final gameId in endedGames) {
      activeGames.remove(gameId);
    }
  }

  // ========= GAME SETUP HELPER METHODS =========
  
  void _dealCards(GameState game) {
    /// Deal 4 cards to each player - moved from GameActions
    for (final player in game.players.values) {
      for (int i = 0; i < 4; i++) {
        final card = game.deck.drawCard();
        if (card != null) {
          player.addCardToHand(card);
        }
      }
    }
  }

  void _setupPiles(GameState game) {
    /// Set up draw and discard piles - moved from GameActions
    try {
      // Move remaining cards to draw pile
      game.drawPile = List<Card>.from(game.deck.cards);
      game.deck.cards.clear();
      
      // Start discard pile with first card from draw pile
      if (game.drawPile.isNotEmpty) {
        final firstCard = game.drawPile.removeAt(0);
        game.discardPile.add(firstCard);
        _logger.info('Setup piles: ${game.drawPile.length} cards in draw pile, ${game.discardPile.length} cards in discard pile', isOn: LOGGING_SWITCH);
      } else {
        _logger.warning('Warning: No cards in draw pile after dealing', isOn: LOGGING_SWITCH);
      }
      
      // Trigger change detection for both piles
      game._trackChange('drawPile');
      game._trackChange('discardPile');
      game._sendChangesIfNeeded();
      
    } catch (e) {
      _logger.error('Error in _setupPiles: $e', isOn: LOGGING_SWITCH);
    }
  }
}