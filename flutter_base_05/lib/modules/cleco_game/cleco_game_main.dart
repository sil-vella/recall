import 'package:flutter/material.dart';
import 'package:cleco/core/managers/navigation_manager.dart';
import 'package:cleco/core/managers/state_manager.dart';
import 'package:cleco/modules/cleco_game/screens/game_play/game_play_screen.dart';
import 'package:cleco/modules/cleco_game/screens/lobby_room/lobby_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../tools/logging/logger.dart';

// Import Cleco game components
import '../cleco_game/managers/cleco_module_manager.dart';
import '../cleco_game/managers/cleco_event_manager.dart';
import '../cleco_game/managers/cleco_game_state_updater.dart';
import '../cleco_game/utils/cleco_game_helpers.dart';

/// Cleco Game Module
/// Main module for the Cleco card game functionality
class ClecoGameMain extends ModuleBase {
  static const bool LOGGING_SWITCH = true; // Enabled for debugging user stats fetching
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
      
      // Step 5: Register hooks for user stats fetching
      _registerHooks();
      
      // Step 6: Register screens with NavigationManager
      _registerScreens();
      
      // Step 7: Fetch user stats if already logged in
      _fetchUserStatsIfLoggedIn();
      
      // Step 8: Final verification
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
          
          // User statistics (from database)
          'userStats': null,
          'userStatsLastUpdated': null,
          
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

  /// Register hooks for fetching user stats
  void _registerHooks() {
    final hooksManager = HooksManager();
    
    // Register hook to fetch user stats when user is fully logged in (after tokens are stored)
    hooksManager.registerHookWithData('auth_login_complete', (data) {
      _logger.info('🎬 ClecoGameMain: auth_login_complete hook triggered - fetching user stats', isOn: LOGGING_SWITCH);
      _fetchUserStats();
    });
    
    _logger.info('🎬 ClecoGameMain: Registered auth_login_complete hook for user stats', isOn: LOGGING_SWITCH);
  }

  /// Fetch user stats if user is already logged in (on module initialization)
  void _fetchUserStatsIfLoggedIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final isLoggedIn = loginState['isLoggedIn'] == true;
      
      if (isLoggedIn) {
        _logger.info('🎬 ClecoGameMain: User is already logged in - fetching user stats', isOn: LOGGING_SWITCH);
        _fetchUserStats();
      } else {
        _logger.info('🎬 ClecoGameMain: User is not logged in - skipping user stats fetch', isOn: LOGGING_SWITCH);
      }
    });
  }

  /// Fetch user cleco game stats from API and update state
  Future<void> _fetchUserStats() async {
    try {
      _logger.info('🎬 ClecoGameMain: Fetching user cleco game stats...', isOn: LOGGING_SWITCH);
      final success = await ClecoGameHelpers.fetchAndUpdateUserClecoGameData();
      if (success) {
        _logger.info('✅ ClecoGameMain: User stats fetched and updated successfully', isOn: LOGGING_SWITCH);
      } else {
        _logger.warning('⚠️ ClecoGameMain: Failed to fetch user stats', isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      _logger.error('❌ ClecoGameMain: Error fetching user stats: $e', isOn: LOGGING_SWITCH);
    }
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