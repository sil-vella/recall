import 'package:flutter/material.dart';
import 'package:recall/core/managers/navigation_manager.dart';
import 'package:recall/core/managers/state_manager.dart';
import 'package:recall/modules/recall_game/screens/game_play/game_play_screen.dart';
import 'package:recall/modules/recall_game/screens/lobby_room/lobby_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../tools/logging/logger.dart';

// Import Recall game components
import 'managers/recall_module_manager.dart';
import 'managers/recall_event_manager.dart';
import 'managers/recall_game_state_updater.dart';

/// Recall Game Module
/// Main module for the Recall card game functionality
class RecallGameMain extends ModuleBase {
  static const bool LOGGING_SWITCH = true;
  final Logger _logger = Logger();
  
  final navigationManager = NavigationManager();
  
  // Recall game components
  final RecallModuleManager _recallModuleManager = RecallModuleManager();
  final RecallEventManager _recallEventManager = RecallEventManager();

  /// Get Recall Game Manager
  RecallModuleManager get recallModuleManager => _recallModuleManager;
  
  /// Get Recall Message Manager
  RecallEventManager get recallEventManager => _recallEventManager;
  
  // No ChangeNotifier notifier – we rely on StateManager only

  /// ✅ Constructor with module key and dependencies
  RecallGameMain() : super("recall_game_module", dependencies: []);

  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    
    _initDependencies(context);
    
    // Initialize all Recall game components
    _initializeRecallComponents();
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    // Dependencies initialized
  }

  /// Initialize all Recall game components
  Future<void> _initializeRecallComponents() async {
    try {
      // Step 0: Initialize singletons FIRST (before anything else)
      // This ensures they're ready before static fields or widgets access them
      _logger.info('🎬 RecallGameMain: Starting singleton initialization', isOn: LOGGING_SWITCH);
      
      // Access singletons to trigger their initialization
      // ignore: unused_local_variable
      final _ = RecallGameStateUpdater.instance; // Triggers constructor and handler setup
      
      _logger.info('🎬 RecallGameMain: Singletons initialized successfully', isOn: LOGGING_SWITCH);
      
      // Step 1: Register state with StateManager
      _registerState();
      
      // Step 2: Initialize RecallModuleManager
      final gameManagerResult = await _recallModuleManager.initialize();
      if (!gameManagerResult) {
        return;
      }
            
      // Step 4: Initialize RecallEventManager
      final messageManagerResult = await _recallEventManager.initialize();
      if (!messageManagerResult) {
        return;
      }
      
      // Step 5: Register screens with NavigationManager
      _registerScreens();
      
      // Step 6: Final verification
      await _performFinalVerification();
      
    } catch (e) {
      _logger.error('🎬 RecallGameMain: Error during initialization: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Perform final verification of all components
  Future<Map<String, bool>> _performFinalVerification() async {
    final results = <String, bool>{};
    
    try {
      // Verify StateManager registration
      final stateManager = StateManager();
      results['state_manager'] = stateManager.isModuleStateRegistered('recall_game');
      
      // Verify RecallModuleManager
      results['recall_game_manager'] = _recallModuleManager.isInitialized;
      // Verify RecallEventManager
      results['recall_message_manager'] = true; // Assuming success if we got here
      
      // Verify NavigationManager routes
      results['navigation_manager'] = true; // Assuming success if we got here
      
    } catch (e) {
      results['verification_error'] = false;
    }
    
    return results;
  }

  void _registerState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
          
          // 🎯 NEW: Game-related state for joined games
          'joinedGames': <Map<String, dynamic>>[],
          'totalJoinedGames': 0,
          'joinedGamesTimestamp': '',
          'currentGameId': '',
          'games': <String, dynamic>{},
          
          // UI control state
          'showCreateRoom': true,
          'showRoomList': true,
          
          // Widget slices (will be populated by widgets)
          'actionBar': <String, dynamic>{},
          'statusBar': <String, dynamic>{},
          'myHand': <String, dynamic>{},
          'centerBoard': <String, dynamic>{},
          'opponentsPanel': <String, dynamic>{},
          'myDrawnCard': null,
          'cards_to_peek': <Map<String, dynamic>>[],
          
          // Turn events for animation type hints
          'turn_events': <Map<String, dynamic>>[],
          
          // Metadata
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  /// Register all Recall game screens with NavigationManager
  void _registerScreens() {
    // Register Recall Game Lobby Screen (Room Management)
    navigationManager.registerRoute(
      path: '/recall/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Recall Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );

    // Register Game Play Screen
    navigationManager.registerRoute(
      path: '/recall/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );
  }

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    // Dispose Recall game components
    _recallModuleManager.dispose();
    
    _recallEventManager.dispose();
    
    super.dispose();
  }

  /// ✅ Health check override
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': isInitialized ? 'RecallGameMain is functioning normally' : 'RecallGameMain not initialized',
      'components': {
        'recall_game_manager': _recallModuleManager.isInitialized ? 'healthy' : 'not_initialized',
        'recall_message_manager': 'initialized',
        'state_manager': 'initialized',
        'navigation_manager': 'initialized',
      },
      'screens_registered': [
        '/recall/lobby',
        '/recall/game-play',
      ],
      'initialization_time': DateTime.now().toIso8601String(),
    };
  }
}