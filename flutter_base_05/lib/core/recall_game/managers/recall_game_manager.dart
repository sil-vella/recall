import 'dart:async';
import 'package:flutter/material.dart' hide Card;
import '../../managers/state_manager.dart';
import '../../managers/module_manager.dart';
import '../../../tools/logging/logger.dart';
import 'recall_websocket_manager.dart';
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
  final RecallWebSocketManager _wsManager = RecallWebSocketManager();
  final RecallStateManager _stateManager = RecallStateManager();
  final StateManager _mainStateManager = StateManager();
  final ModuleManager _moduleManager = ModuleManager();

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
      
      // Initialize WebSocket manager
      final wsInitialized = await _wsManager.initialize();
      if (!wsInitialized) {
        _log.error('❌ Failed to initialize WebSocket manager');
        return false;
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
    // Listen to game events
    _gameEventSubscription = _wsManager.gameEvents.listen((event) {
      _handleGameEvent(event);
    });
    
    // Listen to game state updates
    _gameStateSubscription = _wsManager.gameStateUpdates.listen((gameState) {
      _stateManager.updateGameState(gameState);
      _updateGameStatus(gameState);
    });
    
    // Listen to errors
    _errorSubscription = _wsManager.errors.listen((error) {
      _log.error('❌ Recall game error: $error');
      _handleGameError(error);
    });
    
    _log.info('✅ Recall Game Manager event listeners set up');
  }

  /// Handle game events
  void _handleGameEvent(GameEvent event) {
    _log.info('🎮 Handling game event: ${event.type}');
    
    switch (event.type) {
      case GameEventType.gameJoined:
        _handleGameJoined(event as GameJoinedEvent);
        break;
      case GameEventType.gameLeft:
        _handleGameLeft(event as GameLeftEvent);
        break;
      case GameEventType.playerJoined:
        _handlePlayerJoined(event as PlayerJoinedEvent);
        break;
      case GameEventType.playerLeft:
        _handlePlayerLeft(event as PlayerLeftEvent);
        break;
      case GameEventType.gameStarted:
        _handleGameStarted(event as GameStartedEvent);
        break;
      case GameEventType.gameEnded:
        _handleGameEnded(event as GameEndedEvent);
        break;
      case GameEventType.turnChanged:
        _handleTurnChanged(event as TurnChangedEvent);
        break;
      case GameEventType.cardPlayed:
        _handleCardPlayed(event as CardPlayedEvent);
        break;
      case GameEventType.recallCalled:
        _handleRecallCalled(event as RecallCalledEvent);
        break;
      case GameEventType.gameStateUpdated:
        _handleGameStateUpdated(event as GameStateUpdatedEvent);
        break;
      case GameEventType.gameError:
        _handleGameErrorEvent(event as GameErrorEvent);
        break;
      default:
        _log.info('⚠️ Unhandled game event: ${event.type}');
    }
  }

  /// Handle game joined event
  void _handleGameJoined(GameJoinedEvent event) {
    _currentGameId = event.gameId;
    _currentPlayerId = event.player.id;
    _isGameActive = true;
    
    _stateManager.updateGameState(event.gameState);
    _updateGameStatus(event.gameState);
    
    _log.info('✅ Joined game: ${event.gameState.gameName}');
  }

  /// Handle game left event
  void _handleGameLeft(GameLeftEvent event) {
    _clearGameState();
    _log.info('👋 Left game: ${event.reason}');
  }

  /// Handle player joined event
  void _handlePlayerJoined(PlayerJoinedEvent event) {
    _stateManager.addPlayer(event.player);
    _log.info('👋 Player joined: ${event.player.name}');
  }

  /// Handle player left event
  void _handlePlayerLeft(PlayerLeftEvent event) {
    _stateManager.removePlayer(event.playerId ?? '');
    _log.info('👋 Player left: ${event.playerName}');
  }

  /// Handle game started event
  void _handleGameStarted(GameStartedEvent event) {
    _stateManager.updateGameState(event.gameState);
    _updateGameStatus(event.gameState);
    _log.info('🎮 Game started: ${event.gameState.gameName}');
  }

  /// Handle game ended event
  void _handleGameEnded(GameEndedEvent event) {
    _stateManager.updateGameState(event.finalGameState);
    _updateGameStatus(event.finalGameState);
    _log.info('🏆 Game ended. Winner: ${event.winner.name}');
  }

  /// Handle turn changed event
  void _handleTurnChanged(TurnChangedEvent event) {
    _stateManager.updateCurrentPlayer(event.newCurrentPlayer);
    _log.info('🔄 Turn changed to: ${event.newCurrentPlayer.name}');
  }

  /// Handle card played event
  void _handleCardPlayed(CardPlayedEvent event) {
    _stateManager.updatePlayerState(event.player);
    _log.info('🃏 Card played: ${event.playedCard.displayName} by ${event.player.name}');
  }

  /// Handle recall called event
  void _handleRecallCalled(RecallCalledEvent event) {
    _stateManager.updateGameState(event.updatedGameState);
    _updateGameStatus(event.updatedGameState);
    _log.info('📢 Recall called by: ${event.player.name}');
  }

  /// Handle game state updated event
  void _handleGameStateUpdated(GameStateUpdatedEvent event) {
    _stateManager.updateGameState(event.gameState);
    _updateGameStatus(event.gameState);
    _log.info('🔄 Game state updated');
  }

  /// Handle game error event
  void _handleGameErrorEvent(GameErrorEvent event) {
    _log.error('❌ Game error: ${event.error}');
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
    _mainStateManager.updateModuleState("recall_game_manager", {
      "isInitialized": _isInitialized,
      "isGameActive": _isGameActive,
      "currentGameId": _currentGameId,
      "currentPlayerId": _currentPlayerId,
      "isConnected": _wsManager.isConnected,
    });
  }

  /// Join a game
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName) async {
    if (!_isInitialized) {
      return {'error': 'Game manager not initialized'};
    }
    
    try {
      _log.info('🎮 Joining game: $gameId as $playerName');
      
      final result = await _wsManager.joinGame(gameId, playerName);
      
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
      
      final result = await _wsManager.leaveGame();
      
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
      
      final result = await _wsManager.playCard(card, targetPlayerId: targetPlayerId);
      return result;
      
    } catch (e) {
      _log.error('❌ Error playing card: $e');
      return {'error': 'Failed to play card: $e'};
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
      
      final result = await _wsManager.callRecall();
      return result;
      
    } catch (e) {
      _log.error('❌ Error calling recall: $e');
      return {'error': 'Failed to call recall: $e'};
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
      
      final result = await _wsManager.useSpecialPower(card, powerData);
      return result;
      
    } catch (e) {
      _log.error('❌ Error using special power: $e');
      return {'error': 'Failed to use special power: $e'};
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
    
    _wsManager.dispose();
    _stateManager.dispose();
    
    _clearGameState();
    
    _log.info('🗑️ Recall Game Manager disposed');
  }
} 