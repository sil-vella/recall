import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../managers/state_manager.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../../../../tools/logging/logger.dart';

/// Recall Game State Manager
/// Manages game state and integrates with the main StateManager
class RecallStateManager {
  static final Logger _log = Logger();
  static final RecallStateManager _instance = RecallStateManager._internal();
  
  factory RecallStateManager() => _instance;
  RecallStateManager._internal();

  // Main state manager
  final StateManager _stateManager = StateManager();
  
  // Current game state
  GameState? _currentGameState;
  
  // State listeners
  final List<Function(GameState)> _stateListeners = [];
  final List<Function(Player)> _playerListeners = [];
  final List<Function(List<Card>)> _handListeners = [];
  
  // Stream controllers for reactive updates
  final StreamController<GameState> _gameStateController = StreamController<GameState>.broadcast();
  final StreamController<Player> _currentPlayerController = StreamController<Player>.broadcast();
  final StreamController<List<Card>> _myHandController = StreamController<List<Card>>.broadcast();
  final StreamController<bool> _isMyTurnController = StreamController<bool>.broadcast();
  final StreamController<bool> _canCallRecallController = StreamController<bool>.broadcast();

  // Getters
  GameState? get currentGameState => _currentGameState;
  bool get hasActiveGame => _currentGameState != null && _currentGameState!.isActive;
  bool get isGameFinished => _currentGameState?.isFinished ?? false;
  bool get isInRecallPhase => _currentGameState?.isInRecallPhase ?? false;
  
  // Streams
  Stream<GameState> get gameStateStream => _gameStateController.stream;
  Stream<Player> get currentPlayerStream => _currentPlayerController.stream;
  Stream<List<Card>> get myHandStream => _myHandController.stream;
  Stream<bool> get isMyTurnStream => _isMyTurnController.stream;
  Stream<bool> get canCallRecallStream => _canCallRecallController.stream;

  /// Initialize the Recall state manager
  void initialize() {
    _log.info('🎮 Initializing Recall State Manager');
    
    // Register with main StateManager
    _registerWithStateManager();
    
    _log.info('✅ Recall State Manager initialized');
  }

  /// Register with main StateManager
  void _registerWithStateManager() {
    _stateManager.registerModuleState("recall_game", {
      // Room management state
      'isInRoom': false,
      'currentRoomId': null,
      'currentRoom': null,
      'rooms': [], // List of available rooms
      'myRooms': [], // List of rooms created by current user
      
      // Game state
      'hasActiveGame': false,
      'gameId': null,
      'currentPlayerId': null,
      'gamePhase': 'waiting',
      'gameStatus': 'active',
      'playerCount': 0,
      'turnNumber': 0,
      'roundNumber': 1,
      'isMyTurn': false,
      'canCallRecall': false,
      'myHand': [],
      'myScore': 0,
      'gameState': null,
      
      // Metadata
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _log.info('📊 Recall game state registered with StateManager');
  }

  /// Update game state
  void updateGameState(GameState newGameState) {
    _currentGameState = newGameState;
    
    // Update main StateManager
    _updateMainStateManager();
    
    // Notify listeners
    _gameStateController.add(newGameState);
    _notifyStateListeners(newGameState);
    
    // Update specific streams
    _updateCurrentPlayerStream();
    _updateMyHandStream();
    _updateTurnStreams();
    
    _log.info('🔄 Game state updated: ${newGameState.gameName} - Phase: ${newGameState.phase}');
  }

  /// Update current player
  void updateCurrentPlayer(Player currentPlayer) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = _currentGameState!.players.map((p) {
      return p.copyWith(isCurrentPlayer: p.id == currentPlayer.id);
    }).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      currentPlayer: currentPlayer,
      lastActivityTime: DateTime.now(),
    );
    
    _updateMainStateManager();
    _currentPlayerController.add(currentPlayer);
    _updateTurnStreams();
  }

  /// Update player state
  void updatePlayerState(Player updatedPlayer) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = _currentGameState!.players.map((p) {
      return p.id == updatedPlayer.id ? updatedPlayer : p;
    }).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      lastActivityTime: DateTime.now(),
    );
    
    _updateMainStateManager();
    _notifyPlayerListeners(updatedPlayer);
    _updateMyHandStream();
    _updateTurnStreams();
  }

  /// Add player to game
  void addPlayer(Player player) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = List<Player>.from(_currentGameState!.players);
    final existingIndex = updatedPlayers.indexWhere((p) => p.id == player.id);
    
    if (existingIndex >= 0) {
      updatedPlayers[existingIndex] = player;
    } else {
      updatedPlayers.add(player);
    }
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      lastActivityTime: DateTime.now(),
    );
    
    _updateMainStateManager();
    _log.info('👋 Player added/updated: ${player.name}');
  }

  /// Remove player from game
  void removePlayer(String playerId) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = _currentGameState!.players.where((p) => p.id != playerId).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      lastActivityTime: DateTime.now(),
    );
    
    _updateMainStateManager();
    _log.info('👋 Player removed: $playerId');
  }

  /// Update my hand
  void updateMyHand(List<Card> newHand) {
    if (_currentGameState == null) return;
    
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return;
    
    final updatedPlayers = _currentGameState!.players.map((p) {
      if (p.id == myPlayerId) {
        return p.copyWith(hand: newHand);
      }
      return p;
    }).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      lastActivityTime: DateTime.now(),
    );
    
    _updateMainStateManager();
    _myHandController.add(newHand);
    _log.info('🃏 My hand updated: ${newHand.length} cards');
  }

  /// Get my player ID
  String? _getMyPlayerId() {
    // This would typically come from the WebSocket manager or auth
    // For now, we'll use the first human player
    final humanPlayers = _currentGameState?.humanPlayers ?? [];
    return humanPlayers.isNotEmpty ? humanPlayers.first.id : null;
  }

  /// Get my hand
  List<Card> getMyHand() {
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return [];
    
    return _currentGameState?.getPlayerHand(myPlayerId) ?? [];
  }

  /// Get my score
  int getMyScore() {
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return 0;
    
    return _currentGameState?.getPlayerScore(myPlayerId) ?? 0;
  }

  /// Check if it's my turn
  bool get isMyTurn {
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return false;
    
    return _currentGameState?.isPlayerTurn(myPlayerId) ?? false;
  }

  /// Check if I can call recall
  bool get canCallRecall {
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return false;
    
    return _currentGameState?.canPlayerCallRecall(myPlayerId) ?? false;
  }

  /// Get current player
  Player? get currentPlayer => _currentGameState?.currentPlayer;

  /// Get all players
  List<Player> get allPlayers => _currentGameState?.players ?? [];

  /// Get active players
  List<Player> get activePlayers => _currentGameState?.activePlayers ?? [];

  /// Get human players
  List<Player> get humanPlayers => _currentGameState?.humanPlayers ?? [];

  /// Get computer players
  List<Player> get computerPlayers => _currentGameState?.computerPlayers ?? [];

  /// Get player by ID
  Player? getPlayerById(String playerId) {
    return _currentGameState?.getPlayerById(playerId);
  }

  /// Update meta/manager info in the shared StateManager under `recall_game`
  void updateManagerMeta({
    bool? gameManagerInitialized,
    bool? isGameActive,
    String? currentGameId,
    String? currentPlayerId,
    bool? isConnected,
  }) {
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final updated = {
      ...currentState,
      if (gameManagerInitialized != null) 'gameManagerInitialized': gameManagerInitialized,
      if (isGameActive != null) 'isGameActive': isGameActive,
      if (currentGameId != null) 'currentGameId': currentGameId,
      if (currentPlayerId != null) 'currentPlayerId': currentPlayerId,
      if (isConnected != null) 'isConnected': isConnected,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    _stateManager.updateModuleState("recall_game", updated);
    _log.info('📊 Updated Recall meta state');
  }

  /// Update main StateManager with current game state
  void _updateMainStateManager() {
    if (_currentGameState == null) return;
    
    final gameState = _currentGameState!;
    final currentPlayerId = gameState.currentPlayerId;
    
    // Get current user's player data
    final currentUser = gameState.getPlayerById(currentPlayerId ?? '');
    final myHand = currentUser?.hand ?? [];
    final myScore = currentUser?.totalScore ?? 0;
    final isMyTurn = currentUser != null && gameState.isPlayerTurn(currentUser.id);
    final canCallRecall = currentUser != null && gameState.canPlayerCallRecall(currentUser.id);
    
    // Get current state to preserve room management data
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    final updatedState = {
      ...currentState, // Preserve existing room management state
      // Game state
      'hasActiveGame': gameState.isActive,
      'gameId': gameState.gameId,
      'currentPlayerId': currentPlayerId,
      'gamePhase': gameState.phase.name,
      'gameStatus': gameState.status.name,
      'playerCount': gameState.playerCount,
      'turnNumber': gameState.turnNumber,
      'roundNumber': gameState.roundNumber,
      'isMyTurn': isMyTurn,
      'canCallRecall': canCallRecall,
      'myHand': myHand.map((card) => card.toJson()).toList(),
      'myScore': myScore,
      'gameState': gameState.toJson(),
      
      // Metadata
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update StateManager - this will trigger StateManager provider notifications
    _stateManager.updateModuleState("recall_game", updatedState);
    _log.info('📊 Updated main StateManager with game state');
  }

  /// Update current player stream
  void _updateCurrentPlayerStream() {
    final currentPlayer = _currentGameState?.currentPlayer;
    if (currentPlayer != null) {
      _currentPlayerController.add(currentPlayer);
    }
  }

  /// Update my hand stream
  void _updateMyHandStream() {
    final myHand = getMyHand();
    _myHandController.add(myHand);
  }

  /// Update turn streams
  void _updateTurnStreams() {
    _isMyTurnController.add(isMyTurn);
    _canCallRecallController.add(canCallRecall);
  }

  /// Add state listener
  void addStateListener(Function(GameState) listener) {
    _stateListeners.add(listener);
  }

  /// Remove state listener
  void removeStateListener(Function(GameState) listener) {
    _stateListeners.remove(listener);
  }

  /// Add player listener
  void addPlayerListener(Function(Player) listener) {
    _playerListeners.add(listener);
  }

  /// Remove player listener
  void removePlayerListener(Function(Player) listener) {
    _playerListeners.remove(listener);
  }

  /// Add hand listener
  void addHandListener(Function(List<Card>) listener) {
    _handListeners.add(listener);
  }

  /// Remove hand listener
  void removeHandListener(Function(List<Card>) listener) {
    _handListeners.remove(listener);
  }

  /// Notify state listeners
  void _notifyStateListeners(GameState gameState) {
    for (final listener in _stateListeners) {
      listener(gameState);
    }
  }

  /// Notify player listeners
  void _notifyPlayerListeners(Player player) {
    for (final listener in _playerListeners) {
      listener(player);
    }
  }

  /// Clear game state
  void clearGameState() {
    _currentGameState = null;
    
    // Update main StateManager
    _stateManager.updateModuleState("recall_game", {
      "hasActiveGame": false,
      "gameId": null,
      "currentPlayerId": null,
      "gamePhase": "waiting",
      "gameStatus": "active",
      "playerCount": 0,
      "turnNumber": 0,
      "roundNumber": 1,
      "isMyTurn": false,
      "canCallRecall": false,
      "myHand": [],
      "myScore": 0,
      "gameState": null,
    });
    
    // Clear streams
    _myHandController.add([]);
    _isMyTurnController.add(false);
    _canCallRecallController.add(false);
    
    _log.info('🗑️ Game state cleared');
  }

  /// Clear all listeners
  void clearListeners() {
    _stateListeners.clear();
    _playerListeners.clear();
    _handListeners.clear();
  }

  /// Dispose of the manager
  void dispose() {
    clearListeners();
    _gameStateController.close();
    _currentPlayerController.close();
    _myHandController.close();
    _isMyTurnController.close();
    _canCallRecallController.close();
    clearGameState();
    
    _log.info('🗑️ Recall State Manager disposed');
  }
} 