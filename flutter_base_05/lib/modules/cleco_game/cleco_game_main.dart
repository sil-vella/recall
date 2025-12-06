import 'package:flutter/material.dart';
import 'package:cleco/core/managers/navigation_manager.dart';
import 'package:cleco/core/managers/state_manager.dart';
import 'package:cleco/modules/cleco_game/screens/game_play/game_play_screen.dart';
import 'package:cleco/modules/cleco_game/screens/lobby_room/lobby_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../tools/logging/logger.dart';

// Import Cleco game components
import '../cleco_game/managers/cleco_module_manager.dart';
import '../cleco_game/managers/cleco_event_manager.dart';
import '../cleco_game/managers/cleco_game_state_updater.dart';

/// Cleco Game Module
/// Main module for the Cleco card game functionality
class ClecoGameMain extends ModuleBase {
  static const bool LOGGING_SWITCH = false;
  final Logger _logger = Logger();
  
  final navigationManager = NavigationManager();
  
  // Cleco game components
  final ClecoModuleManager _clecoModuleManager = ClecoModuleManager();
  final ClecoEventManager _clecoEventManager = ClecoEventManager();

  /// Get Cleco Game Manager
  ClecoModuleManager get clecoModuleManager => _clecoModuleManager;
  
  /// Get Cleco Message Manager
  ClecoEventManager get clecoEventManager => _clecoEventManager;
  
  // No ChangeNotifier notifier – we rely on StateManager only

  /// ✅ Constructor with module key and dependencies
  ClecoGameMain() : super("cleco_game_module", dependencies: []);

  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    
    _initDependencies(context);
    
    // Initialize all Cleco game components
    _initializeClecoComponents();
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    // Dependencies initialized
  }

  /// Initialize all Cleco game components
  Future<void> _initializeClecoComponents() async {
    try {
      // Step 0: Initialize singletons FIRST (before anything else)
      // This ensures they're ready before static fields or widgets access them
      _logger.info('🎬 ClecoGameMain: Starting singleton initialization', isOn: LOGGING_SWITCH);
      
      // Access singletons to trigger their initialization
      // ignore: unused_local_variable
      final _ = ClecoGameStateUpdater.instance; // Triggers constructor and handler setup
      
      _logger.info('🎬 ClecoGameMain: Singletons initialized successfully', isOn: LOGGING_SWITCH);
      
      // Step 1: Register state with StateManager
      _registerState();
      
      // Step 2: Initialize ClecoModuleManager
      final gameManagerResult = await _clecoModuleManager.initialize();
      if (!gameManagerResult) {
        return;
      }
            
      // Step 4: Initialize ClecoEventManager
      final messageManagerResult = await _clecoEventManager.initialize();
      if (!messageManagerResult) {
        return;
      }
      
      // Step 5: Register screens with NavigationManager
      _registerScreens();
      
      // Step 6: Final verification
      await _performFinalVerification();
      
    } catch (e) {
      _logger.error('🎬 ClecoGameMain: Error during initialization: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Perform final verification of all components
  Future<Map<String, bool>> _performFinalVerification() async {
    final results = <String, bool>{};
    
    try {
      // Verify StateManager registration
      final stateManager = StateManager();
      results['state_manager'] = stateManager.isModuleStateRegistered('cleco_game');
      
      // Verify ClecoModuleManager
      results['cleco_game_manager'] = _clecoModuleManager.isInitialized;
      // Verify ClecoEventManager
      results['cleco_message_manager'] = true; // Assuming success if we got here
      
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
      
      if (!stateManager.isModuleStateRegistered('cleco_game')) {
        stateManager.registerModuleState('cleco_game', {
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

  /// Register all Cleco game screens with NavigationManager
  void _registerScreens() {
    // Register Cleco Game Lobby Screen (Room Management)
    navigationManager.registerRoute(
      path: '/cleco/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Cleco Game',
      drawerIcon: Icons.games,
      drawerPosition: 6, // After existing screens
    );

    // Register Game Play Screen
    navigationManager.registerRoute(
      path: '/cleco/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );
  }

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    // Dispose Cleco game components
    _clecoModuleManager.dispose();
    
    _clecoEventManager.dispose();
    
    super.dispose();
  }

  /// ✅ Health check override
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': isInitialized ? 'ClecoGameMain is functioning normally' : 'ClecoGameMain not initialized',
      'components': {
        'cleco_game_manager': _clecoModuleManager.isInitialized ? 'healthy' : 'not_initialized',
        'cleco_message_manager': 'initialized',
        'state_manager': 'initialized',
        'navigation_manager': 'initialized',
      },
      'screens_registered': [
        '/cleco/lobby',
        '/cleco/game-play',
      ],
      'initialization_time': DateTime.now().toIso8601String(),
    };
  }
}