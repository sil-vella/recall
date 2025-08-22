import 'dart:async';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';

import '../../../tools/logging/logger.dart';

import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_events.dart';
import '../utils/recall_game_helpers.dart';

import '../../../core/managers/hooks_manager.dart';

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

  // Game state tracking
  String? _currentGameId;
  String? _currentPlayerId;
  bool _isGameActive = false;
  bool _isInitialized = false;
  bool _isInitializing = false;  // Add initialization guard
  
  // Event stream for UI updates (following core WebSocket pattern - single stream)
  final StreamController<GameEvent> _gameEventController = StreamController<GameEvent>.broadcast();
  
  // Event listeners
  StreamSubscription<GameEvent>? _gameEventSubscription;
  StreamSubscription<GameState>? _gameStateSubscription;
  StreamSubscription<String>? _errorSubscription;
  
  // Getters
  String? get currentGameId => _currentGameId;
  String? get playerId => _currentPlayerId;
  bool get isGameActive => _isGameActive;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _wsManager.isConnected;
  GameState? get currentGameState => _currentGameState;
  bool get hasActiveGame => _currentGameState != null && _currentGameState!.isActive;
  
  // Event stream for UI (following core WebSocket pattern - single stream)
  Stream<GameEvent> get gameEvents => _gameEventController.stream;

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
          // Event relays are now handled by the validated event listener system
          _log.info('🔌 Event relays will be set up by validated system');
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
      _stateManager.registerModuleState("recall_game", {
        "isLoading": false,
        "isConnected": false,
        "currentRoomId": "",
        "currentRoom": null,
        "isInRoom": false,
        "myCreatedRooms": [],
        "players": [],
        "actionBar": {
          "showStartButton": false,
          "canPlayCard": false,
          "canCallRecall": false,
          "isGameStarted": false,
        },
        "statusBar": {
          "currentPhase": "waiting",
          "turnInfo": "",
          "playerCount": 0,
          "gameStatus": "inactive",
        },
        "myHand": {
          "cards": [],
          "selectedIndex": null,
          "canSelectCards": false,
        },
        "centerBoard": {
          "discardPile": [],
          "drawPileCount": 0,
          "lastPlayedCard": null,
        },
        "opponentsPanel": {
          "players": [],
          "currentPlayerIndex": -1,
        },
        "showCreateRoom": true,
        "showRoomList": true,
        "lastUpdated": DateTime.now().toIso8601String(),
      });
      
      _isInitialized = true;
      _isInitializing = false;  // Clear initialization flag
      
      // Register hook callbacks for room closure
      _registerHookCallbacks();
      
      _log.info('✅ Recall Game Manager initialized successfully');
      
      // Update main state manager to reflect initialization
      _updateMainStateManager();
      _log.info('✅ Updated main StateManager with initialization status');
      
      // NOW register hooks to set up event listeners when WebSocket is ready
      _log.info('🎣 Registering hooks for WebSocket event listener setup...');
      _registerWebSocketHooks();
      _log.info('✅ WebSocket hooks registered');
      
      return true;
      
    } catch (e) {
      _log.error('❌ Error initializing Recall Game Manager: $e');
      _isInitializing = false;  // Clear initialization flag on error
      return false;
    }
  }

  /// Register WebSocket hooks to set up event listeners when ready
  void _registerWebSocketHooks() {
    _log.info('🎣 [HOOK-REGISTER] Registering WebSocket hooks...');
    
    // Register hook for when WebSocket event listeners are ready
    HooksManager().registerHookWithData('websocket_event_listeners_ready', (hookData) {
      _log.info('🎣 [HOOK-RECEIVED] websocket_event_listeners_ready hook triggered');
      _log.info('🎣 [HOOK-RECEIVED] Hook data: $hookData');
      
      // Now we can safely set up our event listeners
      _setupEventListenersViaHook(hookData);
    });
    
    // Also register for websocket_connected in case we need to re-register after reconnection
    HooksManager().registerHookWithData('websocket_connected', (hookData) {
      _log.info('🎣 [HOOK-RECEIVED] websocket_connected hook triggered');
      _log.info('🎣 [HOOK-RECEIVED] Checking if we need to re-register listeners...');
      
      // Only re-register if we haven't already registered
      // This prevents double registration on reconnection
      if (_needsEventListenerSetup()) {
        _log.info('🎣 [HOOK-RECEIVED] Re-registering listeners after reconnection...');
        _setupEventListenersViaHook(hookData);
      }
    });
    
    _log.info('✅ [HOOK-REGISTER] WebSocket hooks registered successfully');
  }
  
  /// Check if we need to set up event listeners
  bool _needsEventListenerSetup() {
    // Simple check - if we haven't registered listeners yet, we need to
    // In a more complex implementation, you might track registration state
    return true; // For now, always allow re-registration
  }
  
  /// Set up event listeners when called via WebSocket hook
  void _setupEventListenersViaHook(Map<String, dynamic> hookData) {
    _log.info('🎧 [HOOK-SETUP] Setting up event listeners via WebSocket hook...');
    _log.info('🎧 [HOOK-SETUP] Hook data keys: ${hookData.keys.toList()}');
    
    final wsManager = hookData['websocket_manager'] as WebSocketManager?;
    final eventListener = hookData['event_listener'];
    
    if (wsManager == null || eventListener == null) {
      _log.error('❌ [HOOK-SETUP] CRITICAL: Missing websocket_manager or event_listener in hook data');
      return;
    }
    
    _log.info('✅ [HOOK-SETUP] WebSocket components available via hook, proceeding with setup...');
    _setupEventListeners();
  }

  /// Set up event listeners for individual recall game events
  void _setupEventListeners() {
    _log.info('🎧 [RECALL-SETUP] Setting up individual recall game event listeners...');
    
    // Get WebSocket manager instance
    final wsManager = WebSocketManager.instance;
    _log.info('🎧 [RECALL-SETUP] WebSocketManager instance: valid');
    _log.info('🎧 [RECALL-SETUP] WebSocketManager eventListener: ${wsManager.eventListener != null ? 'valid' : 'null'}');
    _log.info('🎧 [RECALL-SETUP] WebSocketManager isConnected: ${wsManager.isConnected}');
    _log.info('🎧 [RECALL-SETUP] WebSocketManager socket ID: ${wsManager.getStatus()['sessionId']}');
    
    if (wsManager.eventListener == null) {
      _log.error('❌ [RECALL-SETUP] CRITICAL: eventListener is null! Cannot register listeners.');
      return;
    }
    
    // Register individual event listeners directly with WebSocket manager
    final eventTypes = [
      'game_joined', 'game_left', 'player_joined', 'player_left',
      'game_started', 'game_ended', 'turn_changed', 'card_played',
      'card_drawn', 'recall_called', 'game_state_updated', 'game_phase_changed',
    ];
    
    _log.info('🎧 [RECALL-SETUP] Registering ${eventTypes.length} event listeners...');
    int registeredCount = 0;
    
    for (final eventType in eventTypes) {
      try {
        _log.info('🎧 [RECALL-SETUP] Registering listener for: $eventType');
        
        wsManager.eventListener?.registerCustomListener(eventType, (data) {
          _log.info('🎮 [RECALL-EVENT] ===== RECALL EVENT RECEIVED =====');
          _log.info('🎮 [RECALL-EVENT] Event type: $eventType');
          _log.info('🎮 [RECALL-EVENT] Data type: ${data.runtimeType}');
          _log.info('🎮 [RECALL-EVENT] Data is Map: ${data is Map}');
          
          if (data is Map) {
            _log.info('🎮 [RECALL-EVENT] Data keys: ${data.keys.toList()}');
          }
          
          // Critical events get full logging
          if (['game_started', 'game_phase_changed'].contains(eventType)) {
            _log.info('🎮 [RECALL-EVENT] CRITICAL EVENT - Full data: $data');
          }
          
          _log.info('🎮 [RECALL-EVENT] Calling _handleRecallGameEvent...');
          
          try {
            _handleRecallGameEvent({
              'event_type': eventType,
              ...(data is Map<String, dynamic> ? data : {}),
            });
            _log.info('✅ [RECALL-EVENT] Successfully handled $eventType');
          } catch (e) {
            _log.error('❌ [RECALL-EVENT] Error handling $eventType: $e');
          }
          
          _log.info('🎮 [RECALL-EVENT] ===== END RECALL EVENT =====');
        });
        
        registeredCount++;
        _log.info('✅ [RECALL-SETUP] Successfully registered listener for: $eventType');
      } catch (e) {
        _log.error('❌ [RECALL-SETUP] Failed to register listener for $eventType: $e');
      }
    }
    
    _log.info('✅ [RECALL-SETUP] Recall Game Manager event listeners set up: $registeredCount/${eventTypes.length} registered');
    
    // Verify registration
    if (registeredCount != eventTypes.length) {
      _log.error('❌ [RECALL-SETUP] WARNING: Not all listeners registered! Expected: ${eventTypes.length}, Got: $registeredCount');
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
        case 'card_drawn':
          _handleCardDrawn(data);
          break;
        case 'recall_called':
          _handleRecallCalled(data);
          break;
        case 'game_state_updated':
          _handleGameStateUpdated(data);
          break;
        case 'game_phase_changed':
          _handleGamePhaseChanged(data);
          break;
        case 'create_room_success':
          _handleCreateRoomSuccess(data);
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
    
    // Add to stream (following core WebSocket pattern)
    final event = GameJoinedEvent(
      gameId: gameState.gameId,
      player: player,
      gameState: gameState,
      playerId: player.id,
    );
    _gameEventController.add(event);
    
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
      
      _log.info('🎮 Updating game state...');
      updateGameState(gameState);
      
      _log.info('🎮 Updating game status...');
      _updateGameStatus(gameState);
      
      // Add to stream (following core WebSocket pattern)
      final event = GameStartedEvent(
        gameId: gameState.gameId,
        gameState: gameState,
        playerId: data['started_by'],
      );
      _gameEventController.add(event);
      
      _log.info('🎮 Game started: ${gameState.gameName}');
      _log.info('🎮 Current game ID: $_currentGameId');
      _log.info('🎮 Is game active: $_isGameActive');
      _log.info('🎮 Game phase: ${gameState.phase.name}');
      _log.info('🎮 Player count: ${gameState.playerCount}');
      
    } catch (e) {
      _log.error('❌ Error handling game_started event: $e');
      _log.error('❌ Event data: $data');
      _log.error('❌ Stack trace: ${StackTrace.current}');
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

  /// Handle card drawn event
  void _handleCardDrawn(Map<String, dynamic> data) {
    try {
      final drawnCardData = data['drawn_card'] as Map<String, dynamic>?;
      final playerId = data['player_id'] as String?;
      final source = data['source'] as String?;
      
      if (drawnCardData == null) {
        _log.error('❌ Card drawn event missing drawn_card data');
        return;
      }
      
      // Convert the drawn card data to Card object
      final drawnCard = Card.fromJson(drawnCardData);
      
      _log.info('🃏 Card drawn: ${drawnCard.displayName} by player $playerId from $source');
      
      // Update the game state with the drawn card information
      // This will be used by the UI to show the drawn card
      if (_currentGameState != null) {
        // Add drawn card info to the game state
        final updatedGameState = _currentGameState!.copyWith(
          lastActivityTime: DateTime.now(),
        );
        
        // Update the main state manager with drawn card info
        RecallGameHelpers.updateDrawnCard(
          drawnCard: drawnCardData,
          source: source,
        );
        
        _log.info('✅ Updated game state with drawn card: ${drawnCard.cardId}');
      }
      
      // Find the player who drew the card
      Player? player;
      if (_currentGameState != null && playerId != null) {
        player = _currentGameState!.players.firstWhere(
          (p) => p.id == playerId,
          orElse: () => Player(id: playerId, name: 'Unknown', type: PlayerType.human),
        );
      }
      
      // Add to stream for UI updates
      if (player != null) {
        final event = CardDrawnEvent(
          gameId: data['game_id'] as String? ?? _currentGameId ?? '',
          drawnCard: drawnCard,
          player: player,
          playerId: playerId,
        );
        _gameEventController.add(event);
      }
      
    } catch (e) {
      _log.error('❌ Error handling card drawn event: $e');
    }
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

  /// Handle create room success event
  void _handleCreateRoomSuccess(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId != null) {
      _log.info('🎉 Create room success: $roomId');
      RecallGameHelpers.setRoomOwnership(
        roomId: roomId,
        isOwner: true,
      );
      _updateMainStateManager();
    }
  }

  /// Handle game error event
  void _handleGameErrorEvent(Map<String, dynamic> data) {
    final error = data['error'] ?? 'Unknown error';
    _log.error('❌ Game error: $error');
    // Handle error appropriately
  }

  /// Handle game phase changed event
  void _handleGamePhaseChanged(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String?;
    final newPhase = data['new_phase'] as String?;
    final currentPlayer = data['current_player'] as String?;
    
    _log.info('🔄 Game phase changed: $newPhase, current player: $currentPlayer');
    
    // Update game phase in state
    RecallGameHelpers.updateGameInfo(
      gameId: gameId,
      gamePhase: newPhase,
    );
    
    // Update player turn info if we have current player
    if (currentPlayer != null) {
      final isMyTurn = currentPlayer == _currentPlayerId;
      RecallGameHelpers.updatePlayerTurn(
        isMyTurn: isMyTurn,
        canPlayCard: isMyTurn && newPhase == 'player_turn',
        canCallRecall: isMyTurn && newPhase == 'player_turn',
      );
    }
    
    // Add to stream (following core WebSocket pattern)
    if (_currentGameState != null) {
      final event = GameStateUpdatedEvent(
        gameId: gameId ?? _currentGameState!.gameId,
        gameState: _currentGameState!,
        playerId: currentPlayer,
      );
      _gameEventController.add(event);
    }
    
    // Update UI slices from current game state
    _updateMainStateManager();
    
    _log.info('✅ Game phase change handled');
  }



  /// Update game status
  void _updateGameStatus(GameState gameState) {
    _isGameActive = gameState.isActive;
    _currentGameId = gameState.gameId;
    
    _updateMainStateManager();
  }

  /// Register with main StateManager using validated updater
  void _registerWithStateManager() {
    // First register the module state
    _stateManager.registerModuleState("recall_game", {
      "isInitialized": false,
      "isGameActive": false,
      "currentGameId": null,
      "playerId": null,
      "isConnected": false,
    });
    
    // Then update with validated system
    RecallGameHelpers.updateUIState({
      'isGameActive': _isGameActive,
      'currentGameId': _currentGameId,
      'playerId': _currentPlayerId,
      'isConnected': _wsManager.isConnected,
      'isInitialized': _isInitialized,
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
    _log.info('📊 Current state keys: ${currentState.keys.toList()}');
    
    Map<String, dynamic> updatedState = {
      ...currentState, // Preserve existing room management state
      
      // Manager meta state
      'isGameActive': _isGameActive,
      'currentGameId': _currentGameId,
      'playerId': _currentPlayerId,
      'isConnected': _wsManager.isConnected,
      
      // Metadata
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    _log.info('📊 Updated state keys: ${updatedState.keys.toList()}');

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
    
    // Update widget slices using validated system
    final widgetSlices = <String, dynamic>{};
    for (final key in ['actionBar', 'statusBar', 'centerBoard', 'opponentsPanel', 'gameState', 'myScore']) {
      if (updatedState.containsKey(key)) {
        widgetSlices[key] = updatedState[key];
      }
    }
    
    if (widgetSlices.isNotEmpty) {
      RecallGameHelpers.updateUIState(widgetSlices);
    }
    
    _log.info('✅ Main StateManager updated using validated system + legacy fields');
    _log.info('📊 Final state update completed at: ${DateTime.now().toIso8601String()}');
  }

  // ========================================
  // DEPRECATED: Business Logic Methods
  // 🚨 These methods should be replaced with GameService delegation
  // 🎯 Use GameService or RecallGameCoordinator instead
  // ========================================

  /// Join a game
  /// ⚠️ DEPRECATED: Use GameService.joinGame() or RecallGameCoordinator.joinGameAndRoom() instead
  Future<Map<String, dynamic>> joinGame(String gameId, String playerName, {int? maxPlayers}) async {
    if (!_isInitialized) {
      // Attempt to initialize on-demand to avoid race with app startup
      final initialized = await initialize();
      if (!initialized) {
        return {'error': 'Game manager not initialized'};
      }
    }
    
    try {
      _log.info('🎮 Joining game: $gameId as $playerName (max players: $maxPlayers)');
      
      // 🎯 Use validated event emitter for join game
      final result = await RecallGameHelpers.joinGame(gameId, playerName, maxPlayers: maxPlayers);
      
      if (result['error'] == null) {
        _currentGameId = gameId;
        _isGameActive = false; // Game is NOT active until start match is called
        
        // Update our game tracking - game is waiting, not active
        RecallGameHelpers.updateActiveGame(
          gameId: gameId,
          gameStatus: 'inactive', // Waiting for start match
          gamePhase: 'waiting',   // Waiting for start match
        );
        
        _updateMainStateManager();
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error joining game: $e');
      return {'error': 'Failed to join game: $e'};
    }
  }

  /// Start a match (activate the game)
  /// ⚠️ DEPRECATED: Use GameService.startMatch() instead
  Future<Map<String, dynamic>> startMatch() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }

    try {
      _log.info('🚀 Starting match: $_currentGameId');
      
      // Send start match event using validated system
      final result = await RecallGameHelpers.startMatch(_currentGameId!);
      
      if (result['error'] == null) {
        _isGameActive = true; // NOW the game becomes active
        
        // Update our game tracking - game is now active
        RecallGameHelpers.updateActiveGame(
          gameId: _currentGameId!,
          gameStatus: 'active',   // Game is now active
          gamePhase: 'playing',   // Game is now playing
        );
        
        _updateMainStateManager();
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error starting match: $e');
      return {'error': 'Failed to start match: $e'};
    }
  }

  /// Leave current game
  /// ⚠️ DEPRECATED: Use GameService.leaveGame() instead
  Future<Map<String, dynamic>> leaveGame() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    
    try {
      _log.info('👋 Leaving game: $_currentGameId');
      
      // Send leave game message using validated system
      final result = await RecallGameHelpers.leaveGame(
        gameId: _currentGameId!,
        reason: 'User left game',
      );
      
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
  /// ⚠️ DEPRECATED: Use GameService.playCard() instead
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
  /// ⚠️ DEPRECATED: Use GameService.drawCard() instead
  Future<Map<String, dynamic>> drawFromDeck() async {
    if (_currentGameId == null) {
      return {'error': 'Not in a game'};
    }
    try {
      _log.info('🂠 Draw from deck using validated system');
      final result = await RecallGameHelpers.drawCard(
        gameId: _currentGameId!,
        playerId: _currentPlayerId!,
        source: 'deck',
      );
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
      _log.info('🂡 Take from discard using validated system');
      final result = await RecallGameHelpers.drawCard(
        gameId: _currentGameId!,
        playerId: _currentPlayerId!,
        source: 'discard',
      );
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
      _log.info('🔁 Replace card at index $replaceIndex with drawn using validated system');
      final result = await RecallGameHelpers.playCard(
        gameId: _currentGameId!,
        playerId: _currentPlayerId!,
        cardId: 'drawn_card',
        replaceIndex: replaceIndex,
      );
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
      _log.info('🃏 Play drawn card using validated system');
      final result = await RecallGameHelpers.playCard(
        gameId: _currentGameId!,
        playerId: _currentPlayerId!,
        cardId: 'drawn_card',
      );
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
      
      // Use validated event emitter
      final result = await RecallGameHelpers.playOutOfTurn(
        gameId: _currentGameId!,
        cardId: card.displayName,
        playerId: _currentPlayerId!,
      );
      
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
      _log.info('✨ Using special power using validated system: ${card.specialPowerDescription}');
      
      final result = await RecallGameHelpers.useSpecialPower(
        gameId: _currentGameId!,
        cardId: card.displayName,
        playerId: _currentPlayerId!,
        powerData: powerData,
      );
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error using special power: $e');
      return {'error': 'Failed to use special power: $e'};
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
    // Update game tracking before clearing local state
    if (_currentGameId != null) {
      RecallGameHelpers.updateActiveGame(
        gameId: _currentGameId!,
        gameStatus: 'inactive',
        gamePhase: 'waiting',
      );
    }
    
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
      'playerId': _currentPlayerId,
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

  /// Register hook callbacks for external events
  void _registerHookCallbacks() {
    try {
      final hooksManager = HooksManager();
      
      _log.info('🎣 Registering hook callbacks for Recall game...');
      
      // Register callback for room_closed hook
      hooksManager.registerHookWithData('room_closed', (data) {
        final roomId = data['room_id'] as String?;
        final reason = data['reason'] as String?;
        
        _log.info('🏠 Room closed hook triggered: $roomId (reason: $reason)');
        
        if (roomId != null) {
          // Remove the game from our active tracking
          RecallGameHelpers.removeActiveGame(roomId);
          _log.info('🗑️ Removed game $roomId from active tracking due to room closure');
          
          // Clear game state if it's the current game
          if (_currentGameId == roomId) {
            _log.info('🎯 Current game room was closed, clearing game state');
            _clearGameState();
          }
          
          // Clean up any ended games
          RecallGameHelpers.cleanupEndedGames();
        }
      }, priority: 5);
      
      _log.info('✅ Hook callbacks registered successfully');
    } catch (e) {
      _log.error('❌ Error registering hook callbacks: $e');
    }
  }

  /// Dispose of the manager
  void dispose() {
    _gameEventSubscription?.cancel();
    _gameStateSubscription?.cancel();
    _errorSubscription?.cancel();
    
    // Close stream controller (following core WebSocket pattern)
    _gameEventController.close();
    
    _stateManager.dispose();
    
    _clearGameState();
    
    _log.info('🗑️ Recall Game Manager disposed');
  }
} 