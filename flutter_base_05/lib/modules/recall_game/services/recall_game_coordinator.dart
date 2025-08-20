import 'dart:async';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import 'game_service.dart';

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
    
    // Note: Event handling is now delegated to RecallGameManager
    // This coordinator focuses on high-level coordination and service orchestration
    
    _log.info('✅ RecallGameCoordinator event listeners setup delegated to RecallGameManager');
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











  // High-level operations that coordinate services
  Future<Map<String, dynamic>> joinGameAndRoom(String roomId, String playerName) async {
    try {
      _log.info('🎮 Joining game and room: $roomId as $playerName');
      
      // First join the room (this would be handled by RoomService in the future)
      _currentRoomId = roomId;
      
      // Get room data to extract max_players
      final recallState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      
      // Try to get room data from multiple sources
      int maxPlayers = 4; // Default fallback
      
      // First try: myCreatedRooms (if we created this room)
      final myCreatedRooms = recallState['myCreatedRooms'] as List<dynamic>? ?? [];
      final myRoom = myCreatedRooms.firstWhere(
        (room) => room['room_id'] == roomId,
        orElse: () => <String, dynamic>{},
      );
      if (myRoom.isNotEmpty) {
        maxPlayers = myRoom['max_size'] as int? ?? 4;
      } else {
        // Second try: currentRoom (if we're in this room)
        final currentRoom = recallState['currentRoom'] as Map<String, dynamic>?;
        if (currentRoom != null && currentRoom['room_id'] == roomId) {
          maxPlayers = currentRoom['max_size'] as int? ?? 4;
        } else {
          // Third try: get from room list (if we have it)
          final roomList = recallState['roomList'] as List<dynamic>? ?? [];
          final roomFromList = roomList.firstWhere(
            (room) => room['room_id'] == roomId,
            orElse: () => <String, dynamic>{},
          );
          if (roomFromList.isNotEmpty) {
            maxPlayers = roomFromList['max_size'] as int? ?? 4;
          }
        }
      }
      
      // Then join the game with max_players
      final result = await _gameService.joinGame(roomId, playerName, maxPlayers: maxPlayers);
      
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
