import 'dart:async';
import '../../managers/state_manager.dart';
import '../../managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../utils/recall_game_helpers.dart';
import '../utils/recall_event_listener_validator.dart';
import 'game_service.dart';
import 'message_service.dart';

/// Single coordinator for all recall game operations
/// Orchestrates between services and handles WebSocket events and state updates
class RecallGameCoordinator {
  static final Logger _log = Logger();
  static final RecallGameCoordinator _instance = RecallGameCoordinator._internal();
  factory RecallGameCoordinator() => _instance;
  RecallGameCoordinator._internal();

  // Dependencies
  final StateManager _stateManager = StateManager();
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final GameService _gameService = GameService();
  final MessageService _messageService = MessageService();
  
  // State tracking
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _currentGameId;
  String? _currentPlayerId;
  String? _currentRoomId;
  
  // Event listeners
  StreamSubscription<Map<String, dynamic>>? _wsEventSubscription;
  
  // Getters
  bool get isInitialized => _isInitialized;
  String? get currentGameId => _currentGameId;
  String? get currentPlayerId => _currentPlayerId;
  String? get currentRoomId => _currentRoomId;
  bool get isConnected => _wsManager.isConnected;

  /// Initialize the coordinator
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log.info('✅ RecallGameCoordinator already initialized');
      return true;
    }
    
    if (_isInitializing) {
      _log.info('⏳ RecallGameCoordinator initialization already in progress, waiting...');
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    _isInitializing = true;

    try {
      _log.info('🎮 Initializing RecallGameCoordinator');
      
      // Check WebSocket connection
      if (!_wsManager.isConnected) {
        _log.info('🔌 WebSocket not connected, will connect later when authentication is available');
      } else {
        _log.info('✅ WebSocket already connected');
      }
      
      // Set up event listeners
      _setupEventListeners();
      
      // Initialize state tracking
      _initializeStateTracking();
      
      _isInitialized = true;
      _log.info('✅ RecallGameCoordinator initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ RecallGameCoordinator initialization failed: $e');
      _isInitializing = false;
      return false;
    }
  }

  /// Set up WebSocket event listeners
  void _setupEventListeners() {
    _log.info('🎮 Setting up event listeners');
    
    // Use validated event listener for all recall game events
    final eventTypes = [
      'game_joined', 'game_left', 'player_joined', 'player_left',
      'game_started', 'game_ended', 'turn_changed', 'card_played',
      'recall_called', 'game_state_updated', 'error',
      'room_event', 'room_joined', 'room_left', 'room_closed',
      'connection_status', 'message', 'recall_message', 'recall_game_event',
    ];
    
    for (final eventType in eventTypes) {
      RecallGameEventListenerExtension.onEvent(eventType, (data) {
        _log.info('🎮 RecallGameCoordinator received validated event: $eventType');
        _handleWebSocketEvent(eventType, data);
      });
    }
    
    // Also register direct listener for recall_game_event (moved from core WebSocket module)
    final eventListener = _wsManager.eventListener;
    if (eventListener != null) {
      eventListener.registerCustomListener('recall_game_event', (data) {
        _log.info('🎮 RecallGameCoordinator received direct recall_game_event');
        _handleRecallGameEvent(data is Map<String, dynamic> ? data : <String, dynamic>{});
      });
    }
    
    _log.info('✅ RecallGameCoordinator event listeners set up');
  }

  /// Initialize state tracking
  void _initializeStateTracking() {
    // Get current state from StateManager
    final recall = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    _currentGameId = recall['currentGameId'] as String?;
    _currentPlayerId = recall['playerId'] as String?;
    _currentRoomId = recall['currentRoomId'] as String?;
    
    _log.info('🎮 State tracking initialized - Game: $_currentGameId, Player: $_currentPlayerId, Room: $_currentRoomId');
  }

  /// Handle WebSocket events
  void _handleWebSocketEvent(String eventType, Map<String, dynamic> data) {
    try {
      _log.info('🎮 Processing event: $eventType');
      
      // Route events to appropriate handlers
      switch (eventType) {
        case 'game_joined':
        case 'game_started':
        case 'game_ended':
        case 'turn_changed':
        case 'card_played':
        case 'recall_called':
        case 'game_state_updated':
          _handleGameEvent(eventType, data);
          break;
          
        case 'room_event':
        case 'room_joined':
        case 'room_left':
        case 'room_closed':
          _handleRoomEvent(eventType, data);
          break;
          
        case 'message':
        case 'recall_message':
          _handleMessageEvent(eventType, data);
          break;
          
        case 'recall_game_event':
          _handleRecallGameEvent(data);
          break;
          
        case 'connection_status':
          _handleConnectionEvent(eventType, data);
          break;
          
        case 'error':
          _handleErrorEvent(eventType, data);
          break;
          
        default:
          _log.info('⚠️ Unknown event type: $eventType');
      }
      
    } catch (e) {
      _log.error('❌ Error handling WebSocket event: $e');
    }
  }

  /// Handle game-related events
  void _handleGameEvent(String eventType, Map<String, dynamic> data) {
    try {
      // Process message through MessageService
      final message = _messageService.formatGameMessage(eventType, data);
      _messageService.processGameMessage(message);
      
      // Update state based on event type
      switch (eventType) {
        case 'game_joined':
          _handleGameJoined(data);
          break;
        case 'game_started':
          _handleGameStarted(data);
          break;
        case 'game_ended':
          _handleGameEnded(data);
          break;
        case 'game_state_updated':
          _handleGameStateUpdated(data);
          break;
      }
      
    } catch (e) {
      _log.error('❌ Error handling game event: $e');
    }
  }

  /// Handle room-related events
  void _handleRoomEvent(String eventType, Map<String, dynamic> data) {
    try {
      // Process message through MessageService
      final message = _messageService.formatRoomMessage(eventType, data);
      _messageService.processRoomMessage(message);
      
      // Update state based on event type
      switch (eventType) {
        case 'room_joined':
          _handleRoomJoined(data);
          break;
        case 'room_left':
          _handleRoomLeft(data);
          break;
        case 'room_closed':
          _handleRoomClosed(data);
          break;
      }
      
    } catch (e) {
      _log.error('❌ Error handling room event: $e');
    }
  }

  /// Handle message events
  void _handleMessageEvent(String eventType, Map<String, dynamic> data) {
    try {
      // Process message through MessageService
      final message = _messageService.formatSystemMessage(eventType, data);
      _messageService.processSystemMessage(message);
      
    } catch (e) {
      _log.error('❌ Error handling message event: $e');
    }
  }

  /// Handle connection events
  void _handleConnectionEvent(String eventType, Map<String, dynamic> data) {
    try {
      // Process message through MessageService
      final message = _messageService.formatSystemMessage(eventType, data);
      _messageService.processSystemMessage(message);
      
      // Update connection status in state
      final status = data['status'] as String? ?? 'unknown';
      RecallGameHelpers.updateConnectionStatus(isConnected: status == 'connected');
      
    } catch (e) {
      _log.error('❌ Error handling connection event: $e');
    }
  }

  /// Handle error events
  void _handleErrorEvent(String eventType, Map<String, dynamic> data) {
    try {
      // Process message through MessageService
      final message = _messageService.formatSystemMessage(eventType, data);
      _messageService.processSystemMessage(message);
      
    } catch (e) {
      _log.error('❌ Error handling error event: $e');
    }
  }

  /// Handle recall game events (moved from core WebSocket module)
  void _handleRecallGameEvent(Map<String, dynamic> data) {
    _log.info('🎮 [HANDLER-RECALL_GAME_EVENT] Handling recall game event');
    
    try {
      // Extract event type from the recall_game_event payload
      final eventType = data['event_type'] as String?;
      if (eventType == null) {
        _log.warning('⚠️ Recall game event missing event_type: $data');
        return;
      }
      
      _log.info('🎮 Processing recall game event type: $eventType');
      
      // Route to appropriate handler based on event type
      switch (eventType) {
        case 'game_joined':
        case 'game_started':
        case 'game_ended':
        case 'turn_changed':
        case 'card_played':
        case 'recall_called':
        case 'game_state_updated':
          _handleGameEvent(eventType, data);
          break;
          
        case 'room_event':
        case 'room_joined':
        case 'room_left':
        case 'room_closed':
          _handleRoomEvent(eventType, data);
          break;
          
        case 'message':
        case 'recall_message':
          _handleMessageEvent(eventType, data);
          break;
          
        case 'connection_status':
          _handleConnectionEvent(eventType, data);
          break;
          
        case 'error':
          _handleErrorEvent(eventType, data);
          break;
          
        default:
          _log.info('⚠️ Unknown recall game event type: $eventType');
      }
      
      _log.info('✅ Recall game event handled successfully');
    } catch (e) {
      _log.error('❌ Error handling recall game event: $e');
    }
  }

  // Event-specific handlers
  void _handleGameJoined(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String?;
    final playerId = data['player_id'] as String?;
    final gameStateData = data['game_state'] as Map<String, dynamic>?;
    
    if (gameId != null) _currentGameId = gameId;
    if (playerId != null) _currentPlayerId = playerId;
    
    // Update game state if provided
    if (gameStateData != null) {
      try {
        final gameState = GameState.fromJson(gameStateData);
        _updateGameState(gameState);
      } catch (e) {
        _log.error('❌ Error parsing game state from game_joined event: $e');
      }
    }
    
    _log.info('✅ Joined game: $gameId as player: $playerId');
  }

  void _handleGameStarted(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String?;
    if (gameId != null) _currentGameId = gameId;
    
    _log.info('🎮 Game started: $gameId');
  }

  void _handleGameEnded(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String?;
    final winner = data['winner'] as Map<String, dynamic>?;
    final winnerName = winner?['name'] as String? ?? 'Unknown';
    
    _log.info('🏆 Game ended: $gameId, Winner: $winnerName');
  }

  void _handleGameStateUpdated(Map<String, dynamic> data) {
    final gameStateData = data['game_state'] as Map<String, dynamic>?;
    if (gameStateData != null) {
      try {
        final gameState = GameState.fromJson(gameStateData);
        _updateGameState(gameState);
      } catch (e) {
        _log.error('❌ Error parsing game state: $e');
      }
    }
  }

  void _handleRoomJoined(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId != null) _currentRoomId = roomId;
    
    _log.info('🏠 Joined room: $roomId');
  }

  void _handleRoomLeft(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId == _currentRoomId) {
      _currentRoomId = null;
      _currentGameId = null; // Leave game when leaving room
    }
    
    _log.info('👋 Left room: $roomId');
  }

  void _handleRoomClosed(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId == _currentRoomId) {
      _currentRoomId = null;
      _currentGameId = null; // Leave game when room is closed
    }
    
    _log.info('🚪 Room closed: $roomId');
  }

  /// Update game state using validated systems
  void _updateGameState(GameState gameState) {
    if (!_gameService.isValidGameState(gameState)) {
      _log.warning('⚠️ Invalid game state received, ignoring update');
      return;
    }
    
    // Update game info using validated system
    RecallGameHelpers.updateGameInfo(
      gameId: gameState.gameId,
      gamePhase: gameState.phase.name,
      gameStatus: gameState.status.name,
      isGameActive: gameState.isActive,
      turnNumber: gameState.turnNumber,
      roundNumber: gameState.roundNumber,
      playerCount: gameState.players.length,
    );
    
    // Update player turn info
    final myPlayerId = _currentPlayerId;
    if (myPlayerId != null) {
      final isMyTurn = gameState.currentPlayerId == myPlayerId;
      final canPlayCard = _gameService.canPlayerPlayCard(myPlayerId, gameState);
      final canCallRecall = _gameService.canPlayerCallRecall(myPlayerId, gameState);
      
      RecallGameHelpers.updatePlayerTurn(
        isMyTurn: isMyTurn,
        canPlayCard: canPlayCard,
        canCallRecall: canCallRecall,
      );
    }
    
    _log.info('🔄 Game state updated: ${gameState.gameName}');
  }

  // High-level operations that coordinate services
  Future<Map<String, dynamic>> joinGameAndRoom(String roomId, String playerName) async {
    try {
      _log.info('🎮 Joining game and room: $roomId as $playerName');
      
      // First join the room (this would be handled by RoomService in the future)
      _currentRoomId = roomId;
      
      // Then join the game
      final result = await _gameService.joinGame(roomId, playerName);
      
      if (result['error'] == null) {
        _currentGameId = roomId; // In this case, roomId is the gameId
        _currentPlayerId = result['player_id'] as String?;
        
        _log.info('✅ Successfully joined game and room: $roomId');
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error joining game and room: $e');
      return {'error': 'Failed to join game and room: $e'};
    }
  }

  Future<Map<String, dynamic>> startGameInRoom(String roomId) async {
    try {
      _log.info('🎮 Starting game in room: $roomId');
      
      if (_currentGameId != roomId) {
        return {'error': 'Not in the specified room'};
      }
      
      final result = await _gameService.startMatch(roomId);
      
      if (result['error'] == null) {
        _log.info('✅ Successfully started game in room: $roomId');
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error starting game in room: $e');
      return {'error': 'Failed to start game in room: $e'};
    }
  }

  Future<Map<String, dynamic>> playCardInGame(String cardId) async {
    try {
      _log.info('🎮 Playing card in game: $cardId');
      
      if (_currentGameId == null) {
        return {'error': 'Not in a game'};
      }
      
      if (_currentPlayerId == null) {
        return {'error': 'Player ID not available'};
      }
      
      final result = await _gameService.playCard(_currentGameId!, cardId, _currentPlayerId!);
      
      if (result['error'] == null) {
        _log.info('✅ Successfully played card: $cardId');
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Error playing card in game: $e');
      return {'error': 'Failed to play card in game: $e'};
    }
  }

  /// Dispose of resources
  void dispose() {
    _wsEventSubscription?.cancel();
    _isInitialized = false;
    _isInitializing = false;
    _log.info('🗑️ RecallGameCoordinator disposed');
  }
}
