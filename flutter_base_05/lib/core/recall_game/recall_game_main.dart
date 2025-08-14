import 'package:flutter/material.dart';
import '../managers/navigation_manager.dart';
import 'managers/recall_state_manager.dart';
import 'managers/recall_game_manager.dart';
// Removed RecallGameNotifier usage – using StateManager only
import '../managers/state_manager.dart';
// import '../managers/websockets/websocket_manager.dart';
import 'screens/lobby_room/lobby_screen.dart';
import '../../../tools/logging/logger.dart';
import 'managers/recall_message_manager.dart';
import 'screens/game_play/game_play_screen.dart';

/// Core component for Recall Game functionality
/// Manages game initialization, screen registration, and state management
class RecallGameCore {
  static final Logger _log = Logger();
  bool _isInitialized = false;
  
  // Legacy Managers (for backward compatibility during transition)
  final RecallStateManager _recallStateManager = RecallStateManager();
  final RecallGameManager _recallGameManager = RecallGameManager();
  
  /// Get Recall State Manager
  RecallStateManager get recallStateManager => _recallStateManager;
  
  /// Get Recall Game Manager
  RecallGameManager get recallGameManager => _recallGameManager;
  
  // No ChangeNotifier notifier – we rely on StateManager only

  /// Initialize the Recall Game core component
  void initialize(BuildContext context) {
    if (_isInitialized) return;
    
    _log.info('🎮 Initializing Recall Game Core...');
    
    // Register Recall game state in StateManager
    final stateManager = StateManager();
    if (!stateManager.isModuleStateRegistered('recall_game')) {
      stateManager.registerModuleState('recall_game', {
        'isLoading': false,
        'isConnected': false,
        'currentRoomId': '',
        'currentRoom': null,
        'isInRoom': false,
        'rooms': <Map<String, dynamic>>[],
        'myRooms': <Map<String, dynamic>>[],
        'players': <Map<String, dynamic>>[],
        'showCreateRoom': true,
        'showRoomList': true,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    }
    
    // Initialize legacy managers (for backward compatibility)
    _recallStateManager.initialize();
    // Ensure websocket is connected before game manager init to avoid early failures
    // Game manager.initialize() already handles connecting if needed
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
    // Screens no longer require a notifier – nothing to guard here
    
    final navigationManager = NavigationManager();

    // Register Recall Game Lobby Screen (Room Management)
    navigationManager.registerRoute(
      path: '/recall/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Recall Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );

    // Register Game Play Screen - ALWAYS with notifier
    navigationManager.registerRoute(
      path: '/recall/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
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
    // No notifier to dispose
    _recallStateManager.dispose();
    _recallGameManager.dispose();
    _log.info('🛑 RecallGameCore disposed');
  }
} 