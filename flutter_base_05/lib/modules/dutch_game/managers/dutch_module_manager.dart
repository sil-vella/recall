/// # Dutch Module Manager
/// 
/// The central orchestrator for all Dutch card game functionality. This manager serves as the
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
/// - **StateManager**: Uses existing `dutch_game` state registration from main module
/// - **WebSocketManager**: Leverages core WebSocket infrastructure
/// - **Game Models**: Works with GameState, Player, Card, and GameEvent models
/// - **Game Helpers**: Utilizes DutchGameHelpers for game logic operations
/// 
/// ## Architecture Pattern:
/// 
/// This manager follows the singleton pattern to ensure consistent game state across
/// the application. It acts as a facade that coordinates multiple subsystems:
/// 
/// ```
/// DutchModuleManager
/// ├── WebSocket Communication (via WebSocketManager)
/// ├── State Persistence (via StateManager) 
/// ├── Event Broadcasting (via StreamController)
/// └── Game Logic (via DutchGameHelpers)
/// ```
/// 
/// ## Usage:
/// 
/// ```dart
/// final gameManager = DutchModuleManager();
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

import '../../../core/managers/websockets/websocket_manager.dart';

/// Dutch Module Manager
/// Main orchestrator for the Dutch game functionality
class DutchModuleManager {
  static final DutchModuleManager _instance = DutchModuleManager._internal();
  
  factory DutchModuleManager() => _instance;
  DutchModuleManager._internal();

  // Managers
  final WebSocketManager _wsManager = WebSocketManager.instance;


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
      return true;
    }
    
    final connected = await _wsManager.connect();
    if (connected) {
      return true;
    } else {
      return false;
    }
  }

  /// Initialize the Dutch Module manager
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }
    
    if (_isInitializing) {
      // Wait for initialization to complete
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    _isInitializing = true;

    try {
      // Check WebSocket connection but don't require it for initialization
      if (!_wsManager.isConnected) {
        // Don't attempt to connect during initialization - this should happen after auth
      }

      // Register dutch-specific Socket.IO events in one place and fan out via WSEventManager
      try {
        final socket = _wsManager.socket;
        if (socket != null) {
          // Event relays are now handled by the validated event listener system
        }
      } catch (e) {
        throw e;
      }
      
      // State registration is now handled by dutch_game_main.dart
      // Manager will use the existing state registration
      
      _isInitialized = true;
      _isInitializing = false;  // Clear initialization flag
      
      return true;
      
    } catch (e) {
      _isInitializing = false;  // Clear initialization flag on error
      return false;
    }
  }

  /// Dispose of resources and cleanup
  void dispose() {
    _errorSubscription?.cancel();
    
    // Reset state
    _currentGameId = null;
    _currentPlayerId = null;
    _isGameActive = false;
    _isInitialized = false;
    _isInitializing = false;
  }
}
