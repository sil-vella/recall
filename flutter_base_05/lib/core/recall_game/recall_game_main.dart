import 'package:flutter/material.dart';
import '../managers/navigation_manager.dart';

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
  final RecallGameManager _recallGameManager = RecallGameManager();
  
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
      
      // Step 1: Register initial state with StateManager (with widget slices)
      _log.info('📊 Registering recall_game state with widget slices...');
      final stateManager = StateManager();
      if (!stateManager.isModuleStateRegistered('recall_game')) {
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
      
      // Step 2: RecallStateManager removed - functionality moved to RecallGameManager
      _log.info('📊 RecallStateManager functionality moved to RecallGameManager');
      
      // Step 3: Initialize and wait for RecallGameManager
      _log.info('🎮 Initializing RecallGameManager...');
      final gameManagerInitResult = await _recallGameManager.initialize();
      if (!gameManagerInitResult) {
        _log.error('❌ RecallGameManager initialization failed');
        return false;
      }
      _log.info('✅ RecallGameManager initialized successfully');
      
      // Step 4: Initialize RecallMessageManager
      _log.info('📨 Initializing RecallMessageManager...');
      final messageManagerInitResult = await RecallMessageManager().initialize();
      if (!messageManagerInitResult) {
        _log.error('❌ RecallMessageManager initialization failed');
        return false;
      }
      _log.info('✅ RecallMessageManager initialized successfully');
      
      // Step 5: Register screens with NavigationManager
      _log.info('🗺️ Registering screens...');
      _registerScreens();
      _log.info('✅ Screens registered');
      
      _isInitialized = true;
      _log.info('🎉 Recall Game Core initialization completed successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ Recall Game Core initialization failed: $e');
      return false;
    }
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

    _recallGameManager.dispose();
    _log.info('🛑 RecallGameCore disposed');
  }
} 