import 'dart:async';

import '../../managers/state_manager.dart';
import '../../managers/websockets/websocket_manager.dart';
import '../../managers/websockets/ws_event_manager.dart';
import '../../../tools/logging/logger.dart';

import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_events.dart';
import '../utils/recall_game_helpers.dart';

/// Recall Game Manager
/// Main orchestrator for the Recall game functionality
class RecallGameManager {
  static final Logger _log = Logger();
  static final RecallGameManager _instance = RecallGameManager._internal();
  
  factory RecallGameManager() => _instance;
  RecallGameManager._internal();

  // Managers
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final StateManager _stateManager = StateManager();
  
  // Current game state (moved from RecallStateManager)
  GameState? _currentGameState;

  // Game state
  bool _isInitialized = false;
  bool _isInitializing = false;  // Add initialization guard
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
  GameState? get currentGameState => _currentGameState;
  bool get hasActiveGame => _currentGameState != null && _currentGameState!.isActive;

  /// Connect to WebSocket when authentication becomes available
  Future<bool> connectWebSocket() async {
    if (_wsManager.isConnected) {
      _log.info('✅ WebSocket already connected');
      return true;
    }
    
    _log.info('🔌 Attempting to connect WebSocket with authentication...');
    final connected = await _wsManager.connect();
    if (connected) {
      _log.info('✅ WebSocket connected successfully');
      return true;
    } else {
      _log.warning('⚠️ WebSocket connection failed, will retry later');
      return false;
    }
  }

  /// Initialize the Recall game manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log.info('✅ Recall Game Manager already initialized');
      return true;
    }
    
    if (_isInitializing) {
      _log.info('⏳ Recall Game Manager initialization already in progress, waiting...');
      // Wait for initialization to complete
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    _isInitializing = true;

    try {
      _log.info('🎮 Initializing Recall Game Manager');
      
      // Check WebSocket connection but don't require it for initialization
      if (!_wsManager.isConnected) {
        _log.info('🔌 WebSocket not connected, will connect later when authentication is available');
        // Don't attempt to connect during initialization - this should happen after auth
      } else {
        _log.info('✅ WebSocket already connected');
      }
      
      // State manager is already initialized globally
      _log.info('📊 Using global StateManager instance');
      
      // Register recall-specific Socket.IO events in one place and fan out via WSEventManager
      _log.info('🔌 Starting Socket.IO event relay setup...');
      try {
        final socket = _wsManager.socket;
        _log.info('🔌 Socket obtained: ${socket != null ? 'not null' : 'null'}');
        if (socket != null) {
          _log.info('🔌 Setting up Socket.IO event relays...');
          // Relay recall_message to WSEventManager custom channel
          socket.on('recall_message', (data) {
            try {
              WSEventManager.instance.triggerCallbacks('recall_message', Map<String, dynamic>.from(data is Map ? data : {}));
            } catch (_) {
              // ignore
            }
          });
          _log.info('🔌 recall_message relay set up');
          
          // Relay room_closed to WSEventManager custom channel
          socket.on('room_closed', (data) {
            try {
              WSEventManager.instance.triggerCallbacks('room_closed', Map<String, dynamic>.from(data is Map ? data : {}));
            } catch (_) {
              // ignore
            }
          });
          _log.info('🔌 room_closed relay set up');
          _log.info('✅ Socket.IO event relays set up');
        } else {
          _log.warning('⚠️ Socket is null, cannot set up event relays');
        }
      } catch (e) {
        _log.error('❌ Error setting up Socket.IO event relays: $e');
        throw e;
      }
      _log.info('✅ Socket.IO event relay setup completed');
      
      // Register with main StateManager
      _log.info('📝 Registering with main StateManager...');
      try {
        _registerWithStateManager();
        _log.info('✅ Registered with main StateManager');
      } catch (e) {
        _log.error('❌ Error registering with StateManager: $e');
        throw e;
      }
      
      _isInitialized = true;
      _isInitializing = false;  // Clear initialization flag
      _log.info('✅ Recall Game Manager initialized successfully');
      
      // Update main state manager to reflect initialization
      _updateMainStateManager();
      _log.info('✅ Updated main StateManager with initialization status');
      
      // NOW set up event listeners after initialization is complete
      _log.info('🎧 Setting up event listeners after initialization...');
      _setupEventListeners();
      _log.info('✅ Event listeners set up after initialization');
      
      return true;
      
    } catch (e) {
      _log.error('❌ Error initializing Recall Game Manager: $e');
      _isInitializing = false;  // Clear initialization flag on error
      return false;
    }
  }

  /// Set up event listeners
  void _setupEventListeners() {
    _log.info('🎧 Setting up recall_event listener...');
    // Listen to recall events from WebSocket manager
    _wsManager.eventManager.onEvent('recall_event', (data) {
      _log.info('🎮 RecallGameManager received recall_event: $data');
      _handleRecallGameEvent(data);
    });
    
    _log.info('🎧 Setting up WebSocket error listener...');
    // Listen to system WebSocket errors
    _wsManager.errors.listen((errorEvent) {
      _log.error('❌ WebSocket error: ${errorEvent.error}');
      _handleGameError(errorEvent.error);
    });
    
    _log.info('✅ Recall Game Manager event listeners set up');
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
    
    updateGameState(gameState);
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
    
    // Update game state with new player if we have current game state
    if (_currentGameState != null) {
      final updatedPlayers = [..._currentGameState!.players, player];
      _currentGameState = _currentGameState!.copyWith(
        players: updatedPlayers,
        lastActivityTime: DateTime.now(),
      );
      _updateMainStateManager();
    }
    
    _log.info('👋 Player joined: ${player.name}');
  }

  /// Handle player left event
  void _handlePlayerLeft(Map<String, dynamic> data) {
    final playerId = data['player_id'];
    
    // Update game state by removing player if we have current game state
    if (_currentGameState != null) {
      final updatedPlayers = _currentGameState!.players.where((p) => p.id != playerId).toList();
      _currentGameState = _currentGameState!.copyWith(
        players: updatedPlayers,
        lastActivityTime: DateTime.now(),
      );
      _updateMainStateManager();
    }
    
    _log.info('👋 Player left: ${data['player_name'] ?? 'Unknown'}');
  }

  /// Handle game started event
  void _handleGameStarted(Map<String, dynamic> data) {
    try {
      _log.info('🎮 Processing game_started event with data: $data');
      
      final gameStateData = data['game_state'];
      _log.info('🎮 Game state data: $gameStateData');
      
      final gameState = GameState.fromJson(gameStateData);
      _log.info('🎮 Successfully parsed GameState: ${gameState.gameName}, phase: ${gameState.phase.name}');
      
      updateGameState(gameState);
      _updateGameStatus(gameState);
      _log.info('🎮 Game started: ${gameState.gameName}');
    } catch (e) {
      _log.error('❌ Error handling game_started event: $e');
      _log.error('❌ Event data: $data');
    }
  }

  /// Handle game ended event
  void _handleGameEnded(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    final winner = Player.fromJson(data['winner']);
    updateGameState(gameState);
    _updateGameStatus(gameState);
    _log.info('🏆 Game ended. Winner: ${winner.name}');
  }

  /// Handle turn changed event
  void _handleTurnChanged(Map<String, dynamic> data) {
    final newCurrentPlayer = Player.fromJson(data['new_current_player']);
    updateCurrentPlayer(newCurrentPlayer);
    _log.info('🔄 Turn changed to: ${newCurrentPlayer.name}');
  }

  /// Handle card played event
  void _handleCardPlayed(Map<String, dynamic> data) {
    final playedCard = Card.fromJson(data['played_card']);
    final player = Player.fromJson(data['player']);
    updatePlayerState(player);
    _log.info('🃏 Card played: ${playedCard.displayName} by ${player.name}');
  }

  /// Handle recall called event
  void _handleRecallCalled(Map<String, dynamic> data) {
    final updatedGameState = GameState.fromJson(data['updated_game_state']);
    updateGameState(updatedGameState);
    _updateGameStatus(updatedGameState);
    _log.info('📢 Recall called by: ${data['player']?['name'] ?? 'Unknown'}');
  }

  /// Handle game state updated event
  void _handleGameStateUpdated(Map<String, dynamic> data) {
    final gameState = GameState.fromJson(data['game_state']);
    updateGameState(gameState);
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
    _stateManager.registerModuleState("recall_game_manager", {
      "isInitialized": _isInitialized,
      "isGameActive": _isGameActive,
      "currentGameId": _currentGameId,
      "currentPlayerId": _currentPlayerId,
      "isConnected": _wsManager.isConnected,
    });
  }

  /// Update game state (moved from RecallStateManager)
  void updateGameState(GameState newGameState) {
    _currentGameState = newGameState;
    _isGameActive = newGameState.isActive;
    _currentGameId = newGameState.gameId;
    
    // Update main StateManager with comprehensive game state
    _updateMainStateManager();
    
    _log.info('🔄 Game state updated: ${newGameState.gameName} - Phase: ${newGameState.phase}');
  }

  /// Update current player (moved from RecallStateManager)
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
    _log.info('🔄 Current player updated: ${currentPlayer.name}');
  }

  /// Update player state (moved from RecallStateManager)
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
    _log.info('🔄 Player state updated: ${updatedPlayer.name}');
  }

  /// Get my player ID (moved from RecallStateManager)
  String? _getMyPlayerId() {
    // This should get the current user's player ID from the session or auth
    // For now, return the stored currentPlayerId
    return _currentPlayerId;
  }

  /// Check if current user is the room owner
  bool _isRoomOwner() {
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    return currentState['isRoomOwner'] == true;
  }

  /// Update main StateManager
  void _updateMainStateManager() {
    _log.info('📊 Updating main StateManager with: initialized=$_isInitialized, active=$_isGameActive, gameId=$_currentGameId, playerId=$_currentPlayerId');
    
    // Get current state to preserve room management data
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    Map<String, dynamic> updatedState = {
      ...currentState, // Preserve existing room management state
      
      // Manager meta state
      'isGameActive': _isGameActive,
      'currentGameId': _currentGameId,
      'currentPlayerId': _currentPlayerId,
      'isConnected': _wsManager.isConnected,
      
      // Metadata
      'lastUpdated': DateTime.now().toIso8601String(),
    };

    // Add comprehensive game state if available
    if (_currentGameState != null) {
      final gameState = _currentGameState!;
      final myPlayerId = _getMyPlayerId();
      final currentUser = myPlayerId != null ? gameState.getPlayerById(myPlayerId) : null;
      final myHand = currentUser?.hand ?? [];
      final myScore = currentUser?.totalScore ?? 0;
      final isMyTurn = currentUser != null && gameState.isPlayerTurn(currentUser.id);
      final canCallRecall = currentUser != null && gameState.canPlayerCallRecall(currentUser.id);
      
      updatedState.addAll({
        // Game state details
        'gamePhase': gameState.phase.name,
        'gameStatus': gameState.status.name,
        'playerCount': gameState.playerCount,
        'turnNumber': gameState.turnNumber,
        'roundNumber': gameState.roundNumber,
        'isMyTurn': isMyTurn,
        'canCallRecall': canCallRecall,

        'myScore': myScore,
        'gameState': gameState.toJson(),
        
        // Update widget-specific state slices
        'actionBar': {
          'showStartButton': !gameState.isActive && _isRoomOwner(),
          'canPlayCard': isMyTurn && myHand.isNotEmpty,
          'canCallRecall': canCallRecall,
          'isGameStarted': gameState.isActive,
        },
        'statusBar': {
          'currentPhase': gameState.phase.name,
          'turnInfo': gameState.currentPlayer != null ? 'Player ${gameState.currentPlayer!.name}\'s turn' : '',
          'playerCount': gameState.playerCount,
          'gameStatus': gameState.status.name,
        },
        'myHand': {
          'cards': myHand.map((card) => card.toJson()).toList(),
          'selectedIndex': null, // This should be managed by UI
          'canSelectCards': isMyTurn,
        },
        'centerBoard': {
          'discardPile': gameState.discardPile.map((card) => card.toJson()).toList(),
          'drawPileCount': gameState.drawPile.length,
          'lastPlayedCard': gameState.discardPile.isNotEmpty ? gameState.discardPile.last.toJson() : null,
        },
        'opponentsPanel': {
          'players': gameState.players.where((p) => p.id != myPlayerId).map((p) => p.toJson()).toList(),
          'currentPlayerIndex': gameState.currentPlayer != null ? 
            gameState.players.indexWhere((p) => p.id == gameState.currentPlayer!.id) : -1,
        },
      });
    } else {
      // No game state yet - set default action bar state for lobby/waiting
      updatedState.addAll({
        'actionBar': {
          'showStartButton': _isRoomOwner(), // Show start button for room owner when no game active
          'canPlayCard': false,
          'canCallRecall': false,
          'isGameStarted': false,
        },
        'statusBar': {
          'currentPhase': 'waiting',
          'turnInfo': '',
          'playerCount': 0,
          'gameStatus': 'waiting',
        },
        'myHand': {
          'cards': [],
          'selectedIndex': null,
          'canSelectCards': false,
        },
        'centerBoard': {
          'discardPile': [],
          'drawPileCount': 0,
          'lastPlayedCard': null,
        },
        'opponentsPanel': {
          'players': [],
          'currentPlayerIndex': -1,
        },
      });
    }
    
    // 🎯 Use validated state updater for comprehensive game state updates
    // Extract only the validated fields that match our schema
    final validatedUpdates = <String, dynamic>{};
    
    // Core validated fields
    if (updatedState.containsKey('isGameActive')) validatedUpdates['isGameActive'] = updatedState['isGameActive'];
    if (updatedState.containsKey('currentGameId')) validatedUpdates['currentGameId'] = updatedState['currentGameId'];
    if (updatedState.containsKey('playerId')) validatedUpdates['playerId'] = updatedState['playerId'];
    if (updatedState.containsKey('isMyTurn')) validatedUpdates['isMyTurn'] = updatedState['isMyTurn'];
    if (updatedState.containsKey('canCallRecall')) validatedUpdates['canCallRecall'] = updatedState['canCallRecall'];
    if (updatedState.containsKey('canPlayCard')) validatedUpdates['canPlayCard'] = updatedState['canPlayCard'];
    if (updatedState.containsKey('gamePhase')) validatedUpdates['gamePhase'] = updatedState['gamePhase'];
    if (updatedState.containsKey('gameStatus')) validatedUpdates['gameStatus'] = updatedState['gameStatus'];
    if (updatedState.containsKey('playerCount')) validatedUpdates['playerCount'] = updatedState['playerCount'];
    if (updatedState.containsKey('turnNumber')) validatedUpdates['turnNumber'] = updatedState['turnNumber'];
    if (updatedState.containsKey('roundNumber')) validatedUpdates['roundNumber'] = updatedState['roundNumber'];
    if (updatedState.containsKey('isConnected')) validatedUpdates['isConnected'] = updatedState['isConnected'];
    
    // Update via validated system
    if (validatedUpdates.isNotEmpty) {
      RecallGameHelpers.updateGameInfo(
        gameId: validatedUpdates['currentGameId'],
        gamePhase: validatedUpdates['gamePhase'],
        gameStatus: validatedUpdates['gameStatus'],
        isGameActive: validatedUpdates['isGameActive'],
        turnNumber: validatedUpdates['turnNumber'],
        roundNumber: validatedUpdates['roundNumber'],
        playerCount: validatedUpdates['playerCount'],
      );
      
      RecallGameHelpers.updatePlayerTurn(
        isMyTurn: validatedUpdates['isMyTurn'] ?? false,
        canPlayCard: validatedUpdates['canPlayCard'] ?? false,
        canCallRecall: validatedUpdates['canCallRecall'] ?? false,
      );
      
      RecallGameHelpers.updateConnectionStatus(
        isConnected: validatedUpdates['isConnected'] ?? false,
      );
    }
    
    // For non-validated fields (widget slices, game state JSON), use direct StateManager temporarily
    // TODO: Add these to validated schema in future iterations
    final nonValidatedUpdates = <String, dynamic>{};
    for (final key in ['actionBar', 'statusBar', 'myHand', 'centerBoard', 'opponentsPanel', 'gameState', 'myScore']) {
      if (updatedState.containsKey(key)) {
        nonValidatedUpdates[key] = updatedState[key];
      }
    }
    
    if (nonValidatedUpdates.isNotEmpty) {
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
      _stateManager.updateModuleState("recall_game", {
        ...currentState,
        ...nonValidatedUpdates,
      });
    }
    
    _log.info('✅ Main StateManager updated using validated system + legacy fields');
  }

  /// Join a game
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName) async {
    if (!_isInitialized) {
      // Attempt to initialize on-demand to avoid race with app startup
      final initialized = await initialize();
      if (!initialized) {
        return {'error': 'Game manager not initialized'};
      }
    }
    
    try {
      _log.info('🎮 Joining game: $gameId as $playerName');
      
      // First join the room (game)
      final joinResult = await _wsManager.joinRoom(gameId, playerName);
      if (joinResult['error'] != null) {
        return joinResult;
      }
      
      // Then send the join game custom event
      final result = await _wsManager.sendCustomEvent('recall_join_game', {
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
      final result = await _wsManager.sendCustomEvent('recall_leave_game', {
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
    
    // Check if it's my turn using current game state
    if (_currentGameState == null) {
      return {'error': 'No active game state'};
    }
    
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null || !_currentGameState!.isPlayerTurn(myPlayerId)) {
      return {'error': 'Not your turn'};
    }
    
    try {
      // 🎯 Use validated event emitter for playing card
      _log.info('🃏 Playing card using validated system: ${card.displayName}');
      
      final result = await RecallGameHelpers.playCard(
        gameId: _currentGameId!,
        cardId: 'card_${card.suit.name}_${card.rank.name}', // Generate card ID from suit and rank
        playerId: _currentPlayerId!,
        replaceIndex: null, // TODO: Add replace index support if needed
      );
      
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
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
    
    // Check if can call recall using current game state
    if (_currentGameState == null) {
      return {'error': 'No active game state'};
    }
    
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null || !_currentGameState!.canPlayerCallRecall(myPlayerId)) {
      return {'error': 'Cannot call recall at this time'};
    }
    
    try {
      // 🎯 Use validated event emitter for calling recall
      _log.info('📢 Calling recall using validated system');
      
      final result = await RecallGameHelpers.callRecall(
        gameId: _currentGameId!,
        playerId: _currentPlayerId!,
      );
      
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
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
      
      final result = await _wsManager.sendCustomEvent('recall_player_action', {
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
    try {
      if (!_isInitialized) {
        final initialized = await initialize();
        if (!initialized) {
          return {'error': 'Game manager not initialized'};
        }
      }
      
      // Auto-join current room if not yet in a game
      if (_currentGameId == null) {
        final wsState = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final currentRoomId = (wsState['currentRoomId'] ?? '').toString();
        if (currentRoomId.isNotEmpty) {
          final login = _stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
          final playerName = (login['username'] ?? login['email'] ?? 'Player').toString();
          _log.info('🔗 Not in a game. Attempting auto-join of room: $currentRoomId as $playerName');
          final joinRes = await joinGame(currentRoomId, playerName);
          if (joinRes['error'] != null) {
            _log.warning('⚠️ Auto-join failed: ${joinRes['error']}');
            return joinRes;
          }
        } else {
          _log.warning('⚠️ StartMatch requested but no current room and no active game');
          return {'error': 'No current room'};
        }
      }

      if (_currentGameId == null) {
        return {'error': 'Not in a game'};
      }

      // Ensure we have a player ID - try to get it from the current game state
      if (_currentPlayerId == null) {
        final gameState = _currentGameState;
        if (gameState != null) {
          // Try to find the current user's player ID from the game state
          final login = _stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
          final playerName = (login['username'] ?? login['email'] ?? 'Player').toString();
          
          final currentUser = gameState.players.where((p) => p.name == playerName).firstOrNull;
          if (currentUser != null) {
            _currentPlayerId = currentUser.id;
            _log.info('🔍 Found player ID from game state: $_currentPlayerId');
          }
        }
        
        // If still no player ID, try to get it from WebSocket session
        if (_currentPlayerId == null) {
          final sessionId = _wsManager.socket?.id;
          if (sessionId != null) {
            _currentPlayerId = sessionId;
            _log.info('🔍 Using session ID as player ID: $_currentPlayerId');
          }
        }
      }

      if (_currentPlayerId == null) {
        _log.warning('⚠️ No player ID available for start match');
        return {'error': 'Player ID not available'};
      }

      // 🎯 Use validated event emitter for starting match
      _log.info('🚀 Starting match using validated system for game: $_currentGameId');
      
      final result = await RecallGameHelpers.startMatch(_currentGameId!);
      return result;
    } catch (e) {
      _log.error('❌ Error starting match: $e');
      return {'error': 'Failed to start match: $e'};
    }
  }

  /// Get current game state
  GameState? getCurrentGameState() {
    return _currentGameState;
  }

  /// Get my hand
  List<Card> getMyHand() {
    if (_currentGameState == null) return [];
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return [];
    final player = _currentGameState!.getPlayerById(myPlayerId);
    return player?.hand ?? [];
  }

  /// Get my score
  int getMyScore() {
    if (_currentGameState == null) return 0;
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return 0;
    final player = _currentGameState!.getPlayerById(myPlayerId);
    return player?.totalScore ?? 0;
  }

  /// Check if it's my turn
  bool get isMyTurn {
    if (_currentGameState == null) return false;
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return false;
    return _currentGameState!.isPlayerTurn(myPlayerId);
  }

  /// Check if I can call recall
  bool get canCallRecall {
    if (_currentGameState == null) return false;
    final myPlayerId = _getMyPlayerId();
    if (myPlayerId == null) return false;
    return _currentGameState!.canPlayerCallRecall(myPlayerId);
  }

  /// Get all players
  List<Player> get allPlayers => _currentGameState?.players ?? [];

  /// Get current player
  Player? get currentPlayer => _currentGameState?.currentPlayer;

  /// Get player by ID
  Player? getPlayerById(String playerId) {
    return _currentGameState?.getPlayerById(playerId);
  }

  /// Clear game state
  void _clearGameState() {
    _currentGameId = null;
    _currentPlayerId = null;
    _isGameActive = false;
    _currentGameState = null;
    
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
      'hasActiveGame': hasActiveGame,
      'isGameFinished': _currentGameState?.isFinished ?? false,
      'isInRecallPhase': _currentGameState?.isInRecallPhase ?? false,
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