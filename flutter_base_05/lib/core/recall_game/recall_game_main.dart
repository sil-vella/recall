import 'package:flutter/material.dart';
import '../managers/navigation_manager.dart';
import '../managers/app_manager.dart';
import 'screens/game_lobby_screen.dart';
import 'managers/recall_websocket_manager.dart';
import 'managers/recall_state_manager.dart';
import 'managers/recall_game_manager.dart';
import '../../tools/logging/logger.dart';

/// Core Recall Game Component
/// Registers all Recall game screens with the navigation system
/// and initializes Recall game managers
class RecallGameCore {
  static final Logger _log = Logger();
  static final RecallGameCore _instance = RecallGameCore._internal();
  
  factory RecallGameCore() => _instance;
  RecallGameCore._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Recall game managers
  late final RecallWebSocketManager _recallWebSocketManager;
  late final RecallStateManager _recallStateManager;
  late final RecallGameManager _recallGameManager;

  /// Get Recall WebSocket Manager
  RecallWebSocketManager get recallWebSocketManager => _recallWebSocketManager;
  
  /// Get Recall State Manager
  RecallStateManager get recallStateManager => _recallStateManager;
  
  /// Get Recall Game Manager
  RecallGameManager get recallGameManager => _recallGameManager;

  /// Initialize the Recall Game core component
  void initialize(BuildContext context) {
    if (_isInitialized) {
      _log.info('⏸️ RecallGameCore already initialized, skipping...');
      return;
    }

    try {
      _log.info('🎮 Initializing Recall Game Core...');
      
      // Initialize Recall game managers
      _initializeManagers();
      
      // Register screens
      _registerScreens();
      
      _isInitialized = true;
      _log.info('✅ RecallGameCore initialized successfully');
      
    } catch (e) {
      _log.error('❌ Error initializing RecallGameCore: $e');
      rethrow;
    }
  }

  /// Initialize Recall game managers
  void _initializeManagers() {
    _log.info('🎮 Initializing Recall game managers...');
    
    // Initialize Recall WebSocket Manager
    _recallWebSocketManager = RecallWebSocketManager();
    _recallWebSocketManager.initialize();
    
    // Initialize Recall State Manager
    _recallStateManager = RecallStateManager();
    
    // Initialize Recall Game Manager
    _recallGameManager = RecallGameManager();
    _recallGameManager.initialize();
    
    _log.info('✅ Recall game managers initialized');
  }

  /// Register all Recall game screens with NavigationManager
  void _registerScreens() {
    final navigationManager = NavigationManager();

    // Register Game Lobby Screen
    navigationManager.registerRoute(
      path: '/recall/lobby',
      screen: (context) => const GameLobbyScreen(),
      drawerTitle: 'Recall Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );

    // TODO: Register additional screens as they are implemented
    // navigationManager.registerRoute(
    //   path: '/recall/game-room',
    //   screen: (context) => const GameRoomScreen(),
    //   drawerTitle: null, // Don't show in drawer
    //   drawerIcon: null,
    //   drawerPosition: 999,
    // );

    // navigationManager.registerRoute(
    //   path: '/recall/game-play',
    //   screen: (context) => const GamePlayScreen(),
    //   drawerTitle: null, // Don't show in drawer
    //   drawerIcon: null,
    //   drawerPosition: 999,
    // );

    // navigationManager.registerRoute(
    //   path: '/recall/game-results',
    //   screen: (context) => const GameResultsScreen(),
    //   drawerTitle: null, // Don't show in drawer
    //   drawerIcon: null,
    //   drawerPosition: 999,
    // );

    _log.info('✅ Recall game screens registered with NavigationManager');
  }

  /// Get health check information
  Map<String, dynamic> healthCheck() {
    return {
      'component': 'recall_game_core',
      'status': _isInitialized ? 'healthy' : 'not_initialized',
      'details': 'Recall Game Core - Manages card game UI and navigation',
      'managers': {
        'websocket_manager': _recallWebSocketManager.isConnected ? 'connected' : 'disconnected',
        'state_manager': 'initialized',
        'game_manager': 'initialized',
      },
      'screens_registered': [
        '/recall/lobby',
        // '/recall/game-room', // TODO: Add when implemented
        // '/recall/game-play', // TODO: Add when implemented
        // '/recall/game-results', // TODO: Add when implemented
      ],
    };
  }

  void dispose() {
    _recallWebSocketManager.dispose();
    _recallStateManager.dispose();
    _recallGameManager.dispose();
    _log.info('🛑 RecallGameCore disposed');
  }
} 