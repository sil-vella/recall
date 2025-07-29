import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart' hide Card;
import '../../managers/websockets/websocket_manager.dart';
import '../../managers/websockets/websocket_events.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';
import '../models/game_events.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';

/// Recall Game WebSocket Manager
/// Handles all WebSocket communication for the Recall game
class RecallWebSocketManager {
  static final Logger _log = Logger();
  static final RecallWebSocketManager _instance = RecallWebSocketManager._internal();
  
  factory RecallWebSocketManager() => _instance;
  RecallWebSocketManager._internal();

  // WebSocket manager instance
  final WebSocketManager _wsManager = WebSocketManager.instance;
  
  // State manager for game state
  final StateManager _stateManager = StateManager();
  
  // Event streams for game events
  final StreamController<GameEvent> _gameEventController = StreamController<GameEvent>.broadcast();
  final StreamController<GameState> _gameStateController = StreamController<GameState>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  
  // Current game state
  GameState? _currentGameState;
  String? _currentGameId;
  String? _currentPlayerId;
  
  // Event listeners
  StreamSubscription<WebSocketEvent>? _wsEventSubscription;
  StreamSubscription<MessageEvent>? _wsMessageSubscription;
  StreamSubscription<RoomEvent>? _wsRoomSubscription;
  StreamSubscription<ConnectionStatusEvent>? _wsConnectionSubscription;
  StreamSubscription<ErrorEvent>? _wsErrorSubscription;
  
  // Getters
  GameState? get currentGameState => _currentGameState;
  String? get currentGameId => _currentGameId;
  String? get currentPlayerId => _currentPlayerId;
  bool get isConnected => _wsManager.isConnected;
  
  // Event streams
  Stream<GameEvent> get gameEvents => _gameEventController.stream;
  Stream<GameState> get gameStateUpdates => _gameStateController.stream;
  Stream<String> get errors => _errorController.stream;

  /// Initialize the Recall WebSocket manager
  Future<bool> initialize() async {
    try {
      _log.info('🎮 Initializing Recall WebSocket Manager');
      
      // Ensure WebSocket is connected
      if (!_wsManager.isConnected) {
        final connected = await _wsManager.connect();
        if (!connected) {
          _log.error('❌ Failed to connect WebSocket for Recall game');
          return false;
        }
      }
      
      // Set up event listeners
      _setupEventListeners();
      
      // Register with StateManager
      _registerWithStateManager();
      
      _log.info('✅ Recall WebSocket Manager initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ Error initializing Recall WebSocket Manager: $e');
      return false;
    }
  }

  /// Set up WebSocket event listeners
  void _setupEventListeners() {
    // Listen to WebSocket events
    _wsEventSubscription = _wsManager.events.listen((event) {
      _handleWebSocketEvent(event);
    });
    
    // Listen to WebSocket messages
    _wsMessageSubscription = _wsManager.messages.listen((messageEvent) {
      _handleWebSocketMessage(messageEvent);
    });
    
    // Listen to room events
    _wsRoomSubscription = _wsManager.roomEvents.listen((roomEvent) {
      _handleRoomEvent(roomEvent);
    });
    
    // Listen to connection status
    _wsConnectionSubscription = _wsManager.connectionStatus.listen((connectionEvent) {
      _handleConnectionEvent(connectionEvent);
    });
    
    // Listen to errors
    _wsErrorSubscription = _wsManager.errors.listen((errorEvent) {
      _handleErrorEvent(errorEvent);
    });
    
    _log.info('✅ Recall WebSocket event listeners set up');
  }

  /// Handle WebSocket events
  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event is MessageEvent) {
      _handleWebSocketMessage(event);
    } else if (event is ErrorEvent) {
      _log.error('❌ WebSocket error: ${event.error}');
      _errorController.add(event.error);
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(MessageEvent messageEvent) {
    try {
      final data = jsonDecode(messageEvent.message);
      
      // Check if this is a Recall game event
      if (data['type']?.startsWith('recall_') == true) {
        _handleRecallGameEvent(data);
      }
      
    } catch (e) {
      _log.error('❌ Error parsing WebSocket message: $e');
    }
  }

  /// Handle room events
  void _handleRoomEvent(RoomEvent roomEvent) {
    _log.info('🏠 Room event: ${roomEvent.action} - ${roomEvent.roomId}');
    
    // Handle room-specific events if needed
    switch (roomEvent.action) {
      case 'joined':
        _log.info('✅ Successfully joined room: ${roomEvent.roomId}');
        break;
      case 'left':
        _log.info('👋 Left room: ${roomEvent.roomId}');
        break;
      case 'created':
        _log.info('🏠 Room created: ${roomEvent.roomId}');
        break;
    }
  }

  /// Handle connection events
  void _handleConnectionEvent(ConnectionStatusEvent connectionEvent) {
    _log.info('🔌 Connection event: ${connectionEvent.status}');
    
    switch (connectionEvent.status) {
      case ConnectionStatus.connected:
        _log.info('✅ WebSocket connected');
        break;
      case ConnectionStatus.disconnected:
        _log.info('❌ WebSocket disconnected');
        break;
      case ConnectionStatus.error:
        _log.error('🚨 WebSocket error: ${connectionEvent.error}');
        break;
      default:
        _log.info('🔄 WebSocket status: ${connectionEvent.status}');
    }
  }

  /// Handle error events
  void _handleErrorEvent(ErrorEvent errorEvent) {
    _log.error('❌ WebSocket error: ${errorEvent.error}');
    _errorController.add(errorEvent.error);
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
        case 'error':
          _handleGameError(data);
          break;
        default:
          _log.info('⚠️ Unknown Recall game event: $eventType');
      }
      
    } catch (e) {
      _log.error('❌ Error handling Recall game event: $e');
      _errorController.add('Error handling game event: $e');
    }
  }

  /// Handle game joined event
  void _handleGameJoined(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    final player = Player.fromJson(data['player']);
    
    _currentGameState = gameState;
    _currentGameId = gameState.gameId;
    _currentPlayerId = player.id;
    
    final event = GameJoinedEvent(
      gameId: gameState.gameId,
      player: player,
      gameState: gameState,
      playerId: player.id,
    );
    
    _gameEventController.add(event);
    _gameStateController.add(gameState);
    _updateStateManager();
    
    _log.info('✅ Joined game: ${gameState.gameName}');
  }

  /// Handle game left event
  void _handleGameLeft(Map<String, dynamic> data) {
    final reason = data['reason'] ?? 'Unknown reason';
    
    final event = GameLeftEvent(
      gameId: _currentGameId ?? '',
      reason: reason,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _clearGameState();
    
    _log.info('👋 Left game: $reason');
  }

  /// Handle player joined event
  void _handlePlayerJoined(Map<String, dynamic> data) {
    final player = Player.fromJson(data['player']);
    
    final event = PlayerJoinedEvent(
      gameId: _currentGameId ?? '',
      player: player,
      playerId: player.id,
    );
    
    _gameEventController.add(event);
    _updateGameStateWithPlayer(player);
    
    _log.info('👋 Player joined: ${player.name}');
  }

  /// Handle player left event
  void _handlePlayerLeft(Map<String, dynamic> data) {
    final playerName = data['player_name'] ?? 'Unknown';
    final reason = data['reason'] ?? 'Unknown reason';
    
    final event = PlayerLeftEvent(
      gameId: _currentGameId ?? '',
      playerName: playerName,
      reason: reason,
      playerId: data['player_id'],
    );
    
    _gameEventController.add(event);
    _removePlayerFromGameState(data['player_id']);
    
    _log.info('👋 Player left: $playerName - $reason');
  }

  /// Handle game started event
  void _handleGameStarted(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    
    _currentGameState = gameState;
    
    final event = GameStartedEvent(
      gameId: gameState.gameId,
      gameState: gameState,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _gameStateController.add(gameState);
    _updateStateManager();
    
    _log.info('🎮 Game started: ${gameState.gameName}');
  }

  /// Handle game ended event
  void _handleGameEnded(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    final winner = Player.fromJson(data['winner']);
    
    _currentGameState = gameState;
    
    final event = GameEndedEvent(
      gameId: gameState.gameId,
      finalGameState: gameState,
      winner: winner,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _gameStateController.add(gameState);
    _updateStateManager();
    
    _log.info('🏆 Game ended. Winner: ${winner.name}');
  }

  /// Handle turn changed event
  void _handleTurnChanged(Map<String, dynamic> data) {
    final newCurrentPlayer = Player.fromJson(data['new_current_player']);
    final turnNumber = data['turn_number'] ?? 0;
    
    final event = TurnChangedEvent(
      gameId: _currentGameId ?? '',
      newCurrentPlayer: newCurrentPlayer,
      turnNumber: turnNumber,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _updateGameStateCurrentPlayer(newCurrentPlayer, turnNumber);
    
    _log.info('🔄 Turn changed to: ${newCurrentPlayer.name}');
  }

  /// Handle card played event
  void _handleCardPlayed(Map<String, dynamic> data) {
    final playedCard = Card.fromJson(data['played_card']);
    final player = Player.fromJson(data['player']);
    final targetPlayerId = data['target_player_id'];
    final replacedCard = data['replaced_card'] != null 
        ? Card.fromJson(data['replaced_card'])
        : null;
    
    final event = CardPlayedEvent(
      gameId: _currentGameId ?? '',
      playedCard: playedCard,
      player: player,
      targetPlayerId: targetPlayerId,
      replacedCard: replacedCard,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _updateGameStateAfterCardPlayed(playedCard, player, targetPlayerId, replacedCard);
    
    _log.info('🃏 Card played: ${playedCard.displayName} by ${player.name}');
  }

  /// Handle recall called event
  void _handleRecallCalled(Map<String, dynamic> data) {
    final player = Player.fromJson(data['player']);
    final updatedGameState = GameState.fromJson(data['updated_game_state']);
    
    _currentGameState = updatedGameState;
    
    final event = RecallCalledEvent(
      gameId: updatedGameState.gameId,
      player: player,
      updatedGameState: updatedGameState,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _gameStateController.add(updatedGameState);
    _updateStateManager();
    
    _log.info('📢 Recall called by: ${player.name}');
  }

  /// Handle game state updated event
  void _handleGameStateUpdated(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    
    _currentGameState = gameState;
    
    final event = GameStateUpdatedEvent(
      gameId: gameState.gameId,
      gameState: gameState,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _gameStateController.add(gameState);
    _updateStateManager();
    
    _log.info('🔄 Game state updated');
  }

  /// Handle game error event
  void _handleGameError(Map<String, dynamic> data) {
    final error = data['error'] ?? 'Unknown error';
    final errorCode = data['error_code'];
    
    final event = GameErrorEvent(
      gameId: _currentGameId ?? '',
      error: error,
      errorCode: errorCode,
      playerId: _currentPlayerId,
    );
    
    _gameEventController.add(event);
    _errorController.add(error);
    
    _log.error('❌ Game error: $error');
  }

  /// Join a game
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName) async {
    if (!_wsManager.isConnected) {
      return {'error': 'WebSocket not connected'};
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
      
      _clearGameState();
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

  /// Call recall
  Future<Map<String, dynamic>> callRecall() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
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

  /// Use special power
  Future<Map<String, dynamic>> useSpecialPower(Card card, Map<String, dynamic> powerData) async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
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

  /// Update game state with new player
  void _updateGameStateWithPlayer(Player player) {
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
    
    _gameStateController.add(_currentGameState!);
    _updateStateManager();
  }

  /// Remove player from game state
  void _removePlayerFromGameState(String playerId) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = _currentGameState!.players.where((p) => p.id != playerId).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      lastActivityTime: DateTime.now(),
    );
    
    _gameStateController.add(_currentGameState!);
    _updateStateManager();
  }

  /// Update game state current player
  void _updateGameStateCurrentPlayer(Player newCurrentPlayer, int turnNumber) {
    if (_currentGameState == null) return;
    
    final updatedPlayers = _currentGameState!.players.map((p) {
      return p.copyWith(isCurrentPlayer: p.id == newCurrentPlayer.id);
    }).toList();
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      currentPlayer: newCurrentPlayer,
      turnNumber: turnNumber,
      lastActivityTime: DateTime.now(),
    );
    
    _gameStateController.add(_currentGameState!);
    _updateStateManager();
  }

  /// Update game state after card played
  void _updateGameStateAfterCardPlayed(Card playedCard, Player player, String? targetPlayerId, Card? replacedCard) {
    if (_currentGameState == null) return;
    
    // Update player's hand
    final updatedPlayers = _currentGameState!.players.map((p) {
      if (p.id == player.id) {
        final updatedHand = List<Card>.from(p.hand);
        updatedHand.removeWhere((c) => c == playedCard);
        if (replacedCard != null) {
          updatedHand.add(replacedCard);
        }
        return p.copyWith(hand: updatedHand);
      }
      return p;
    }).toList();
    
    // Update center pile
    final updatedCenterPile = List<Card>.from(_currentGameState!.centerPile);
    updatedCenterPile.add(playedCard);
    
    _currentGameState = _currentGameState!.copyWith(
      players: updatedPlayers,
      centerPile: updatedCenterPile,
      lastActivityTime: DateTime.now(),
    );
    
    _gameStateController.add(_currentGameState!);
    _updateStateManager();
  }

  /// Register with StateManager
  void _registerWithStateManager() {
    _stateManager.registerModuleState("recall_game", {
      "gameId": _currentGameId,
      "playerId": _currentPlayerId,
      "isConnected": _wsManager.isConnected,
      "hasActiveGame": _currentGameState != null,
      "gameState": _currentGameState?.toJson(),
    });
  }

  /// Update StateManager
  void _updateStateManager() {
    _stateManager.updateModuleState("recall_game", {
      "gameId": _currentGameId,
      "playerId": _currentPlayerId,
      "isConnected": _wsManager.isConnected,
      "hasActiveGame": _currentGameState != null,
      "gameState": _currentGameState?.toJson(),
    });
  }

  /// Clear game state
  void _clearGameState() {
    _currentGameState = null;
    _currentGameId = null;
    _currentPlayerId = null;
    _updateStateManager();
  }

  /// Dispose of the manager
  void dispose() {
    _wsEventSubscription?.cancel();
    _wsMessageSubscription?.cancel();
    _wsRoomSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    _wsErrorSubscription?.cancel();
    _gameEventController.close();
    _gameStateController.close();
    _errorController.close();
    _clearGameState();
    
    _log.info('🗑️ Recall WebSocket Manager disposed');
  }
} 