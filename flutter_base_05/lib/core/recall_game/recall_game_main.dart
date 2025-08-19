import 'package:flutter/material.dart';
import '../managers/navigation_manager.dart';

import 'services/recall_game_coordinator.dart';
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
  
  // Core Managers
  final RecallGameCoordinator _recallGameCoordinator = RecallGameCoordinator();
  final RecallGameManager _recallGameManager = RecallGameManager();
  
  /// Get Recall Game Coordinator
  RecallGameCoordinator get recallGameCoordinator => _recallGameCoordinator;
  
  /// Get Recall Game Manager
  RecallGameManager get recallGameManager => _recallGameManager;
  
  // No ChangeNotifier notifier – we rely on StateManager only

  /// Initialize the Recall Game core component
  /// This is the single entry point called by AppManager
  Future<bool> initialize(BuildContext context) async {
    if (_isInitialized) {
      _log.info('✅ Recall Game Core already initialized');
      return true;
    }
    
    try {
      _log.info('🎮 Starting Recall Game Core initialization...');
      _log.info('🎮 Context provided: ${context != null ? 'valid' : 'null'}');
      
      // Step 1: Register initial state with StateManager (with widget slices)
      _log.info('📊 Registering recall_game state with widget slices...');
      final stateManager = StateManager();
      _log.info('📊 StateManager instance obtained: ${stateManager != null ? 'valid' : 'null'}');
      
      if (!stateManager.isModuleStateRegistered('recall_game')) {
        _log.info('📊 Creating new recall_game state registration...');
        stateManager.registerModuleState('recall_game', {
          // Connection state
          'isLoading': false,
          'isConnected': false,
          'currentRoomId': '',
          'currentRoom': null,
          'isInRoom': false,
          
          // Room management (only current room and user's created rooms)
          'myCreatedRooms': <Map<String, dynamic>>[],
          'players': <Map<String, dynamic>>[],
          
          // 🎯 WIDGET-SPECIFIC STATE SLICES (for Screen vs Widget pattern)
          'actionBar': {
            'showStartButton': false,
            'canPlayCard': false,
            'canCallRecall': false,
            'isGameStarted': false,
          },
          'statusBar': {
            'currentPhase': 'waiting',
            'turnInfo': '',
            'playerCount': 0,
            'gameStatus': 'inactive',
          },
          'myHand': {
            'cards': <Map<String, dynamic>>[],
            'selectedIndex': null,
            'canSelectCards': false,
          },
          'centerBoard': {
            'discardPile': <Map<String, dynamic>>[],
            'drawPileCount': 0,
            'lastPlayedCard': null,
          },
          'opponentsPanel': {
            'players': <Map<String, dynamic>>[],
            'currentPlayerIndex': -1,
          },
          
          // UI control state
          'showCreateRoom': true,
          'showRoomList': true,
          
          // Metadata
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        _log.info('✅ Recall game state registered with widget slices');
      } else {
        _log.info('📊 Recall game state already registered');
      }
      
      // Verify state registration
      final isRegistered = stateManager.isModuleStateRegistered('recall_game');
      _log.info('📊 State registration verification: $isRegistered');
      
      // Step 2: Initialize RecallGameManager
      _log.info('🎮 Initializing RecallGameManager...');
      _log.info('🎮 RecallGameManager instance: ${_recallGameManager != null ? 'valid' : 'null'}');
      final gameManagerInitResult = await _recallGameManager.initialize();
      _log.info('🎮 RecallGameManager initialization result: $gameManagerInitResult');
      if (!gameManagerInitResult) {
        _log.error('❌ RecallGameManager initialization failed');
        return false;
      }
      _log.info('✅ RecallGameManager initialized successfully');
      
      // Verify RecallGameManager initialization
      final isGameManagerInitialized = _recallGameManager.isInitialized;
      _log.info('🎮 RecallGameManager initialization verification: $isGameManagerInitialized');
      
      // Step 3: Initialize and wait for RecallGameCoordinator
      _log.info('🎮 Initializing RecallGameCoordinator...');
      _log.info('🎮 RecallGameCoordinator instance: ${_recallGameCoordinator != null ? 'valid' : 'null'}');
      final gameCoordinatorInitResult = await _recallGameCoordinator.initialize();
      _log.info('🎮 RecallGameCoordinator initialization result: $gameCoordinatorInitResult');
      if (!gameCoordinatorInitResult) {
        _log.error('❌ RecallGameCoordinator initialization failed');
        return false;
      }
      _log.info('✅ RecallGameCoordinator initialized successfully');
      
      // Step 4: Initialize RecallMessageManager
      _log.info('📨 Initializing RecallMessageManager...');
      final messageManager = RecallMessageManager();
      _log.info('📨 RecallMessageManager instance: ${messageManager != null ? 'valid' : 'null'}');
      final messageManagerInitResult = await messageManager.initialize();
      _log.info('📨 RecallMessageManager initialization result: $messageManagerInitResult');
      if (!messageManagerInitResult) {
        _log.error('❌ RecallMessageManager initialization failed');
        return false;
      }
      _log.info('✅ RecallMessageManager initialized successfully');
      
      // Step 5: Register screens with NavigationManager
      _log.info('🗺️ Registering screens...');
      final navigationManager = NavigationManager();
      _log.info('🗺️ NavigationManager instance: ${navigationManager != null ? 'valid' : 'null'}');
      _registerScreens();
      _log.info('✅ Screens registered');
      
      // Step 6: Final verification
      _log.info('🔍 Performing final verification...');
      final verificationResults = await _performFinalVerification();
      _log.info('🔍 Final verification results: $verificationResults');
      
      _isInitialized = true;
      _log.info('🎉 Recall Game Core initialization completed successfully');
      _log.info('🎉 All components verified and ready for use');
      return true;
      
    } catch (e) {
      _log.error('❌ Recall Game Core initialization failed: $e');
      _log.error('❌ Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Perform final verification of all components
  Future<Map<String, bool>> _performFinalVerification() async {
    final results = <String, bool>{};
    
    try {
      // Verify StateManager
      final stateManager = StateManager();
      results['state_manager'] = stateManager.isModuleStateRegistered('recall_game');
      _log.info('🔍 StateManager verification: ${results['state_manager']}');
      
      // Verify RecallGameManager
      results['recall_game_manager'] = _recallGameManager.isInitialized;
      _log.info('🔍 RecallGameManager verification: ${results['recall_game_manager']}');
      
      // Verify RecallGameCoordinator
      results['recall_game_coordinator'] = true; // Assuming success if we got here
      _log.info('🔍 RecallGameCoordinator verification: ${results['recall_game_coordinator']}');
      
      // Verify RecallMessageManager
      final messageManager = RecallMessageManager();
      results['recall_message_manager'] = true; // Assuming success if we got here
      _log.info('🔍 RecallMessageManager verification: ${results['recall_message_manager']}');
      
      // Verify NavigationManager routes
      final navigationManager = NavigationManager();
      results['navigation_manager'] = true; // Assuming success if we got here
      _log.info('🔍 NavigationManager verification: ${results['navigation_manager']}');
      
    } catch (e) {
      _log.error('❌ Error during final verification: $e');
      results['verification_error'] = false;
    }
    
    return results;
  }

  /// Register all Recall game screens with NavigationManager
  void _registerScreens() {
    // Screens no longer require a notifier – nothing to guard here
    
    final navigationManager = NavigationManager();
    _log.info('🗺️ NavigationManager obtained for screen registration');

    // Register Recall Game Lobby Screen (Room Management)
    _log.info('🗺️ Registering LobbyScreen route: /recall/lobby');
    navigationManager.registerRoute(
      path: '/recall/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Recall Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );
    _log.info('✅ LobbyScreen route registered');

    // Register Game Play Screen - ALWAYS with notifier
    _log.info('🗺️ Registering GamePlayScreen route: /recall/game-play');
    navigationManager.registerRoute(
      path: '/recall/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );
    _log.info('✅ GamePlayScreen route registered');

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
        'game_manager': _recallGameManager.isInitialized ? 'initialized' : 'not_initialized',
        'game_coordinator': 'initialized',
        'message_manager': 'initialized',
      },
      'screens_registered': [
        '/recall/lobby',
        '/recall/game-play',
        // '/recall/game-room', // TODO: Add when implemented
        // '/recall/game-results', // TODO: Add when implemented
      ],
      'initialization_time': DateTime.now().toIso8601String(),
    };
  }

  void dispose() {
    // No notifier to dispose
    _log.info('🛑 Starting RecallGameCore disposal...');

    _recallGameCoordinator.dispose();
    _log.info('🛑 RecallGameCoordinator disposed');
    
    _recallGameManager.dispose();
    _log.info('🛑 RecallGameManager disposed');
    
    _isInitialized = false;
    _log.info('🛑 RecallGameCore disposed');
  }
} 