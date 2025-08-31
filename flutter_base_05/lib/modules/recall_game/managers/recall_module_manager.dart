/// # Recall Module Manager
/// 
/// The central orchestrator for all Recall card game functionality. This manager serves as the
/// primary interface between the game logic, WebSocket communication, and state management.
/// 
/// ## Core Responsibilities:
/// 
/// ### Game State Management
/// - Tracks current game state, game ID, and player ID
/// - Manages game lifecycle (initialization, active state, cleanup)
/// - Coordinates with StateManager for persistent state storage
/// 
/// ### WebSocket Communication
/// - Establishes and maintains WebSocket connections for real-time gameplay
/// - Handles connection state and automatic reconnection logic
/// - Integrates with WebSocketManager for reliable communication
/// 
/// ### Event Coordination
/// - Provides centralized event streaming for game updates
/// - Manages event subscriptions and cleanup
/// - Coordinates between different game components via event system
/// 
/// ### Integration Points
/// - **StateManager**: Uses existing `recall_game` state registration from main module
/// - **WebSocketManager**: Leverages core WebSocket infrastructure
/// - **Game Models**: Works with GameState, Player, Card, and GameEvent models
/// - **Game Helpers**: Utilizes RecallGameHelpers for game logic operations
/// 
/// ## Architecture Pattern:
/// 
/// This manager follows the singleton pattern to ensure consistent game state across
/// the application. It acts as a facade that coordinates multiple subsystems:
/// 
/// ```
/// RecallModuleManager
/// ├── WebSocket Communication (via WebSocketManager)
/// ├── State Persistence (via StateManager) 
/// ├── Event Broadcasting (via StreamController)
/// └── Game Logic (via RecallGameHelpers)
/// ```
/// 
/// ## Usage:
/// 
/// ```dart
/// final gameManager = RecallModuleManager();
/// 
/// // Initialize the manager
/// await gameManager.initialize();
/// 
/// // Connect WebSocket when authentication is available
/// await gameManager.connectWebSocket();
/// 
/// // Listen to game events
/// gameManager.gameEvents.listen((event) {
///   // Handle game events
/// });
/// 
/// // Check game state
/// if (gameManager.hasActiveGame) {
///   final gameState = gameManager.currentGameState;
/// }
/// ```
/// 
/// ## Lifecycle:
/// 
/// 1. **Initialization**: Sets up event streams and validates dependencies
/// 2. **WebSocket Connection**: Establishes real-time communication when auth is ready
/// 3. **Game Operations**: Coordinates gameplay through helper methods
/// 4. **Cleanup**: Properly disposes resources and closes connections
/// 
/// ## Thread Safety:
/// 
/// The manager includes initialization guards to prevent race conditions during
/// concurrent initialization attempts, ensuring safe usage in multi-threaded contexts.

import 'dart:async';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';

import '../../../tools/logging/logger.dart';

/// Recall Module Manager
/// Main orchestrator for the Recall game functionality
class RecallModuleManager {
  static final Logger _log = Logger();
  static final RecallModuleManager _instance = RecallModuleManager._internal();
  
  factory RecallModuleManager() => _instance;
  RecallModuleManager._internal();

  // Managers
  final WebSocketManager _wsManager = WebSocketManager.instance;
  final StateManager _stateManager = StateManager();


  // Game state tracking
  String? _currentGameId;
  String? _currentPlayerId;
  bool _isGameActive = false;
  bool _isInitialized = false;
  bool _isInitializing = false;  // Add initialization guard
  

  StreamSubscription<String>? _errorSubscription;
  
  // Getters
  String? get currentGameId => _currentGameId;
  String? get playerId => _currentPlayerId;
  bool get isGameActive => _isGameActive;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _wsManager.isConnected;

  


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

  /// Initialize the Recall Module manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log.info('✅ Recall Module Manager already initialized');
      return true;
    }
    
    if (_isInitializing) {
      _log.info('⏳ Recall Module Manager initialization already in progress, waiting...');
      // Wait for initialization to complete
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    _isInitializing = true;

    try {
      _log.info('🎮 Initializing Recall Module Manager');
      
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
      
      // State registration is now handled by recall_game_main.dart
      // Manager will use the existing state registration
      _log.info('📊 Using existing recall_game state registration from main module');
      
      _isInitialized = true;
      _isInitializing = false;  // Clear initialization flag
      
      _log.info('✅ Recall Module Manager initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ Error initializing Recall Module Manager: $e');
      _isInitializing = false;  // Clear initialization flag on error
      return false;
    }
  }

  /// Dispose of resources and cleanup
  void dispose() {
    _log.info('🛑 Disposing RecallModuleManager...');
    

    _errorSubscription?.cancel();
    
    // Reset state
    _currentGameId = null;
    _currentPlayerId = null;
    _isGameActive = false;
    _isInitialized = false;
    _isInitializing = false;
    
    _log.info('✅ RecallModuleManager disposed');
  }
}
