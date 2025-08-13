import 'dart:async';
import 'dart:convert';
import '../../managers/state_manager.dart';
import '../../managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import 'recall_state_manager.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_events.dart';

/// Recall Game Manager
/// Main orchestrator for the Recall game functionality
class RecallGameManager {
  static final Logger _log = Logger();
  static final RecallGameManager _instance = RecallGameManager._internal();
  
  factory RecallGameManager() => _instance;
  RecallGameManager._internal();

  // Managers
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final RecallStateManager _stateManager = RecallStateManager();
  final StateManager _mainStateManager = StateManager();

  // Game state
  bool _isInitialized = false;
  bool _isGameActive = false;
  String? _currentGameId;
  String? _currentPlayerId;

  // Event listeners
  StreamSubscription<GameEvent>? _gameEventSubscription;
  StreamSubscription<GameState>? _gameStateSubscription;
  StreamSubscription<String>? _errorSubscription;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isGameActive => _isGameActive;
  String? get currentGameId => _currentGameId;
  String? get currentPlayerId => _currentPlayerId;
  bool get isConnected => _wsManager.isConnected;
  GameState? get currentGameState => _stateManager.currentGameState;

  /// Initialize the Recall game manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log.info('✅ Recall Game Manager already initialized');
      return true;
    }

    try {
      _log.info('🎮 Initializing Recall Game Manager');
      
      // Ensure WebSocket is connected
      if (!_wsManager.isConnected) {
        final connected = await _wsManager.connect();
        if (!connected) {
          _log.error('❌ Failed to connect WebSocket');
          return false;
        }
      }
      
      // Initialize state manager
      _stateManager.initialize();
      
      // Set up event listeners
      _setupEventListeners();
      
      // Register with main StateManager
      _registerWithStateManager();
      
      _isInitialized = true;
      _log.info('✅ Recall Game Manager initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ Error initializing Recall Game Manager: $e');
      return false;
    }
  }

  /// Set up event listeners
  void _setupEventListeners() {
    // Listen to system WebSocket events for game events
    _wsManager.messages.listen((messageEvent) {
      _handleWebSocketMessage(messageEvent);
    });
    
    // Listen to system WebSocket errors
    _wsManager.errors.listen((errorEvent) {
      _log.error('❌ WebSocket error: ${errorEvent.error}');
      _handleGameError(errorEvent.error);
    });
    
    _log.info('✅ Recall Game Manager event listeners set up');
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(dynamic messageEvent) {
    try {
      // Parse message and check if it's a Recall game event
      final data = messageEvent.message;
      if (data is String) {
        final jsonData = jsonDecode(data);
        if (jsonData['type']?.startsWith('recall_') == true) {
          _handleRecallGameEvent(jsonData);
        }
      }
    } catch (e) {
      _log.error('❌ Error parsing WebSocket message: $e');
    }
  }

  /// Handle Recall game events
  void _handleRecallGameEvent(Map<String, dynamic> data) {
    try {
      final eventType = data['event_type'];
      final gameId = data['game_id'];
      
      _log.info('🎮 Received Recall game event: $eventType for game: $gameId');
      
      switch (eventType) {
        case 'game_joined':
          _handleGameJoined(data);
          break;
        case 'game_left':
          _handleGameLeft(data);
          break;
        case 'player_joined':
          _handlePlayerJoined(data);
          break;
        case 'player_left':
          _handlePlayerLeft(data);
          break;
        case 'game_started':
          _handleGameStarted(data);
          break;
        case 'game_ended':
          _handleGameEnded(data);
          break;
        case 'turn_changed':
          _handleTurnChanged(data);
          break;
        case 'card_played':
          _handleCardPlayed(data);
          break;
        case 'recall_called':
          _handleRecallCalled(data);
          break;
        case 'game_state_updated':
          _handleGameStateUpdated(data);
          break;
        case 'turn_changed':
          _handleTurnChanged(data);
          break;
        case 'player_joined':
          _handlePlayerJoined(data);
          break;
        case 'player_left':
          _handlePlayerLeft(data);
          break;
        case 'error':
          _handleGameErrorEvent(data);
          break;
        default:
          _log.info('⚠️ Unknown Recall game event: $eventType');
      }
      
    } catch (e) {
      _log.error('❌ Error handling Recall game event: $e');
    }
  }

  /// Handle game joined event
  void _handleGameJoined(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    final player = Player.fromJson(data['player']);
    
    _currentGameId = gameState.gameId;
    _currentPlayerId = player.id;
    _isGameActive = true;
    
    _stateManager.updateGameState(gameState);
    _updateGameStatus(gameState);
    
    _log.info('✅ Joined game: ${gameState.gameName}');
  }

  /// Handle game left event
  void _handleGameLeft(Map<String, dynamic> data) {
    _clearGameState();
    _log.info('👋 Left game: ${data['reason'] ?? 'Unknown reason'}');
  }

  /// Handle player joined event
  void _handlePlayerJoined(Map<String, dynamic> data) {
    final player = Player.fromJson(data['player']);
    _stateManager.addPlayer(player);
    _log.info('👋 Player joined: ${player.name}');
  }

  /// Handle player left event
  void _handlePlayerLeft(Map<String, dynamic> data) {
    final playerId = data['player_id'];
    _stateManager.removePlayer(playerId);
    _log.info('👋 Player left: ${data['player_name'] ?? 'Unknown'}');
  }

  /// Handle game started event
  void _handleGameStarted(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    _stateManager.updateGameState(gameState);
    _updateGameStatus(gameState);
    _log.info('🎮 Game started: ${gameState.gameName}');
  }

  /// Handle game ended event
  void _handleGameEnded(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    final winner = Player.fromJson(data['winner']);
    _stateManager.updateGameState(gameState);
    _updateGameStatus(gameState);
    _log.info('🏆 Game ended. Winner: ${winner.name}');
  }

  /// Handle turn changed event
  void _handleTurnChanged(Map<String, dynamic> data) {
    final newCurrentPlayer = Player.fromJson(data['new_current_player']);
    _stateManager.updateCurrentPlayer(newCurrentPlayer);
    _log.info('🔄 Turn changed to: ${newCurrentPlayer.name}');
  }

  /// Handle card played event
  void _handleCardPlayed(Map<String, dynamic> data) {
    final playedCard = Card.fromJson(data['played_card']);
    final player = Player.fromJson(data['player']);
    _stateManager.updatePlayerState(player);
    _log.info('🃏 Card played: ${playedCard.displayName} by ${player.name}');
  }

  /// Handle recall called event
  void _handleRecallCalled(Map<String, dynamic> data) {
    final updatedGameState = GameState.fromJson(data['updated_game_state']);
    _stateManager.updateGameState(updatedGameState);
    _updateGameStatus(updatedGameState);
    _log.info('📢 Recall called by: ${data['player']?['name'] ?? 'Unknown'}');
  }

  /// Handle game state updated event
  void _handleGameStateUpdated(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    _stateManager.updateGameState(gameState);
    _updateGameStatus(gameState);
    _log.info('🔄 Game state updated');

    // Optional: out-of-turn countdown
    final meta = data['game_state'];
    final outEnds = meta != null ? meta['outOfTurnEndsAt'] : null;
    if (outEnds is num) {
      _log.info('⏱️ Out-of-turn window ends at: $outEnds');
      // UI can read this from state json for banner countdown
    }
  }

  /// Handle game error event
  void _handleGameErrorEvent(Map<String, dynamic> data) {
    final error = data['error'] ?? 'Unknown error';
    _log.error('❌ Game error: $error');
    // Handle error appropriately
  }

  /// Handle general game error
  void _handleGameError(String error) {
    _log.error('❌ General game error: $error');
    // Handle error appropriately
  }

  /// Update game status
  void _updateGameStatus(GameState gameState) {
    _isGameActive = gameState.isActive;
    _currentGameId = gameState.gameId;
    
    _updateMainStateManager();
  }

  /// Register with main StateManager
  void _registerWithStateManager() {
    _mainStateManager.registerModuleState("recall_game_manager", {
      "isInitialized": _isInitialized,
      "isGameActive": _isGameActive,
      "currentGameId": _currentGameId,
      "currentPlayerId": _currentPlayerId,
      "isConnected": _wsManager.isConnected,
    });
  }

  /// Update main StateManager
  void _updateMainStateManager() {
    // Delegate meta updates to RecallStateManager for uniformity
    _stateManager.updateManagerMeta(
      gameManagerInitialized: _isInitialized,
      isGameActive: _isGameActive,
      currentGameId: _currentGameId,
      currentPlayerId: _currentPlayerId,
      isConnected: _wsManager.isConnected,
    );
  }

  /// Join a game
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName) async {
    if (!_isInitialized) {
      return {'error': 'Game manager not initialized'};
    }
    
    try {
      _log.info('🎮 Joining game: $gameId as $playerName');
      
      // First join the room (game)
      final joinResult = await _wsManager.joinRoom(gameId, playerName);
      if (joinResult['error'] != null) {
        return joinResult;
      }
      
      // Then send the join game message
      final result = await _wsManager.sendMessage(gameId, 'recall_join_game', {
        'game_id': gameId,
        'player_name': playerName,
        'session_id': _wsManager.socket?.id,
      });
      
      if (result['error'] == null) {
        _currentGameId = gameId;
        _isGameActive = true;
        _updateMainStateManager();
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error joining game: $e');
      return {'error': 'Failed to join game: $e'};
    }
  }

  /// Leave current game
  Future<Map<String, dynamic>> leaveGame() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    
    try {
      _log.info('👋 Leaving game: $_currentGameId');
      
      // Send leave game message
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_leave_game', {
        'game_id': _currentGameId,
        'player_id': _currentPlayerId,
      });
      
      // Leave the room
      await _wsManager.leaveRoom(_currentGameId!);
      
      if (result['error'] == null) {
        _clearGameState();
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error leaving game: $e');
      return {'error': 'Failed to leave game: $e'};
    }
  }

  /// Play a card
  Future<Map<String, dynamic>> playCard(Card card, {String? targetPlayerId}) async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    
    if (!_stateManager.isMyTurn) {
      return {'error': 'Not your turn'};
    }
    
    try {
      _log.info('🃏 Playing card: ${card.displayName}');
      
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'play_card',
        'card': card.toJson(),
        'target_player_id': targetPlayerId,
        'player_id': _currentPlayerId,
      });
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error playing card: $e');
      return {'error': 'Failed to play card: $e'};
    }
  }

  /// Draw from face-down deck
  Future<Map<String, dynamic>> drawFromDeck() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🂠 Draw from deck');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'draw_from_deck',
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error drawing from deck: $e');
      return {'error': 'Failed to draw from deck: $e'};
    }
  }

  /// Take top card from discard pile
  Future<Map<String, dynamic>> takeFromDiscard() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🂡 Take from discard');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'take_from_discard',
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error taking from discard: $e');
      return {'error': 'Failed to take from discard: $e'};
    }
  }

  /// Replace a card in hand with the drawn card by index
  Future<Map<String, dynamic>> placeDrawnCardReplace(int replaceIndex) async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🔁 Replace card at index $replaceIndex with drawn');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'place_drawn_card_replace',
        'replaceIndex': replaceIndex,
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error replacing with drawn: $e');
      return {'error': 'Failed to replace with drawn: $e'};
    }
  }

  /// Play the drawn card immediately
  Future<Map<String, dynamic>> placeDrawnCardPlay() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🃏 Play drawn card');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'place_drawn_card_play',
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error playing drawn card: $e');
      return {'error': 'Failed to play drawn card: $e'};
    }
  }

  /// Call recall
  Future<Map<String, dynamic>> callRecall() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    
    if (!_stateManager.canCallRecall) {
      return {'error': 'Cannot call recall at this time'};
    }
    
    try {
      _log.info('📢 Calling recall');
      
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'call_recall',
        'player_id': _currentPlayerId,
      });
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error calling recall: $e');
      return {'error': 'Failed to call recall: $e'};
    }
  }

  /// Play out-of-turn
  Future<Map<String, dynamic>> playOutOfTurn(Card card) async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('⚡ Play out-of-turn: ${card.displayName}');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'play_out_of_turn',
        'card': card.toJson(),
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error playing out-of-turn: $e');
      return {'error': 'Failed to play out-of-turn: $e'};
    }
  }

  /// Use special power
  Future<Map<String, dynamic>> useSpecialPower(Card card, Map<String, dynamic> powerData) async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    
    if (!card.hasSpecialPower) {
      return {'error': 'Card has no special power'};
    }
    
    try {
      _log.info('✨ Using special power: ${card.specialPowerDescription}');
      
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_player_action', {
        'action': 'use_special_power',
        'card': card.toJson(),
        'power_data': powerData,
        'player_id': _currentPlayerId,
      });
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error using special power: $e');
      return {'error': 'Failed to use special power: $e'};
    }
  }

  /// Start match (explicit init)
  Future<Map<String, dynamic>> startMatch() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🚀 Starting match for game: $_currentGameId');
      final result = await _wsManager.sendMessage(_currentGameId!, 'recall_start_match', {
        'game_id': _currentGameId,
        'player_id': _currentPlayerId,
      });
      return result;
    } catch (e) {
      _log.error('❌ Error starting match: $e');
      return {'error': 'Failed to start match: $e'};
    }
  }

  /// Get current game state
  GameState? getCurrentGameState() {
    return _stateManager.currentGameState;
  }

  /// Get my hand
  List<Card> getMyHand() {
    return _stateManager.getMyHand();
  }

  /// Get my score
  int getMyScore() {
    return _stateManager.getMyScore();
  }

  /// Check if it's my turn
  bool get isMyTurn => _stateManager.isMyTurn;

  /// Check if I can call recall
  bool get canCallRecall => _stateManager.canCallRecall;

  /// Get all players
  List<Player> get allPlayers => _stateManager.allPlayers;

  /// Get current player
  Player? get currentPlayer => _stateManager.currentPlayer;

  /// Get player by ID
  Player? getPlayerById(String playerId) {
    return _stateManager.getPlayerById(playerId);
  }

  /// Clear game state
  void _clearGameState() {
    _currentGameId = null;
    _currentPlayerId = null;
    _isGameActive = false;
    
    _stateManager.clearGameState();
    _updateMainStateManager();
    
    _log.info('🗑️ Game state cleared');
  }

  /// Get game status
  Map<String, dynamic> getGameStatus() {
    return {
      'isInitialized': _isInitialized,
      'isGameActive': _isGameActive,
      'currentGameId': _currentGameId,
      'currentPlayerId': _currentPlayerId,
      'isConnected': _wsManager.isConnected,
      'hasActiveGame': _stateManager.hasActiveGame,
      'isGameFinished': _stateManager.isGameFinished,
      'isInRecallPhase': _stateManager.isInRecallPhase,
      'isMyTurn': isMyTurn,
      'canCallRecall': canCallRecall,
      'myHandSize': getMyHand().length,
      'myScore': getMyScore(),
      'playerCount': allPlayers.length,
    };
  }

  /// Dispose of the manager
  void dispose() {
    _gameEventSubscription?.cancel();
    _gameStateSubscription?.cancel();
    _errorSubscription?.cancel();
    
    _stateManager.dispose();
    
    _clearGameState();
    
    _log.info('🗑️ Recall Game Manager disposed');
  }
} 