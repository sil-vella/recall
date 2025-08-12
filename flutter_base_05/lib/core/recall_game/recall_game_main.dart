import 'package:flutter/material.dart';
import '../managers/navigation_manager.dart';
import 'managers/recall_state_manager.dart';
import 'managers/recall_game_manager.dart';
import 'screens/lobby_room/lobby_screen.dart';
import '../../../tools/logging/logger.dart';
import 'managers/recall_message_manager.dart';
import 'screens/game_play/game_play_screen.dart';

/// Core component for Recall Game functionality
/// Manages game initialization, screen registration, and state management
class RecallGameCore {
  static final Logger _log = Logger();
  bool _isInitialized = false;
  
  // Managers
  final RecallStateManager _recallStateManager = RecallStateManager();
  final RecallGameManager _recallGameManager = RecallGameManager();

  /// Get Recall State Manager
  RecallStateManager get recallStateManager => _recallStateManager;
  
  /// Get Recall Game Manager
  RecallGameManager get recallGameManager => _recallGameManager;

  /// Initialize the Recall Game core component
  void initialize(BuildContext context) {
    if (_isInitialized) return;
    
    _log.info('🎮 Initializing Recall Game Core...');
    
    // Initialize managers
    _recallStateManager.initialize();
    _recallGameManager.initialize();
    // One-time initialization of Recall message routing
    RecallMessageManager().initialize();
    
    // Register screens
    _registerScreens();
    
    _isInitialized = true;
    _log.info('✅ Recall game managers initialized');
  }

  /// Register all Recall game screens with NavigationManager
  void _registerScreens() {
    final navigationManager = NavigationManager();

    // Register Recall Game Lobby Screen (Room Management)
    navigationManager.registerRoute(
      path: '/recall/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Recall Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );

    // TODO: Register additional screens as they are implemented
    navigationManager.registerRoute(
      path: '/recall/game-play',
      screen: (context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );

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
    _recallStateManager.dispose();
    _recallGameManager.dispose();
    _log.info('🛑 RecallGameCore disposed');
  }
} 