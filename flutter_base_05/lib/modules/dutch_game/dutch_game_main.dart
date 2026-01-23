import 'package:flutter/material.dart';
import 'package:dutch/core/managers/navigation_manager.dart';
import 'package:dutch/core/managers/state_manager.dart';
import 'package:dutch/modules/dutch_game/screens/game_play/game_play_screen.dart';
import 'package:dutch/modules/dutch_game/screens/lobby_room/lobby_screen.dart';
import 'package:dutch/modules/dutch_game/screens/demo/demo_screen.dart';
import 'package:dutch/modules/dutch_game/screens/game_rules/game_rules_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../tools/logging/logger.dart';

// Import Dutch game components
import '../dutch_game/managers/dutch_module_manager.dart';
import '../dutch_game/managers/dutch_event_manager.dart';
import '../dutch_game/managers/dutch_game_state_updater.dart';
import '../dutch_game/utils/dutch_game_helpers.dart';
import '../dutch_game/screens/home_screen/features/home_screen_features.dart';

/// Dutch Game Module
/// Main module for the Dutch card game functionality
class DutchGameMain extends ModuleBase {
  static const bool LOGGING_SWITCH = false; // Enabled for testing auto-guest creation flow (auth_login_complete hook)
  final Logger _logger = Logger();
  
  final navigationManager = NavigationManager();
  
  // Dutch game components
  final DutchModuleManager _dutchModuleManager = DutchModuleManager();
  final DutchEventManager _dutchEventManager = DutchEventManager();

  /// Get Dutch Game Manager
  DutchModuleManager get dutchModuleManager => _dutchModuleManager;
  
  /// Get Dutch Message Manager
  DutchEventManager get dutchEventManager => _dutchEventManager;
  
  // No ChangeNotifier notifier – we rely on StateManager only

  /// ✅ Constructor with module key and dependencies
  DutchGameMain() : super("dutch_game_module", dependencies: []);

  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    
    _initDependencies(context);
    
    // Initialize all Dutch game components
    _initializeDutchComponents();
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    // Dependencies initialized
  }

  /// Initialize all Dutch game components
  Future<void> _initializeDutchComponents() async {
    try {
      // Step 0: Initialize singletons FIRST (before anything else)
      // This ensures they're ready before static fields or widgets access them
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameMain: Starting singleton initialization');
      }
      
      // Access singletons to trigger their initialization
      // ignore: unused_local_variable
      final _ = DutchGameStateUpdater.instance; // Triggers constructor and handler setup
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameMain: Singletons initialized successfully');
      }
      
      // Step 1: Register state with StateManager
      _registerState();
      
      // Step 2: Initialize DutchModuleManager
      final gameManagerResult = await _dutchModuleManager.initialize();
      if (!gameManagerResult) {
        return;
      }
            
      // Step 4: Initialize DutchEventManager
      final messageManagerResult = await _dutchEventManager.initialize();
      if (!messageManagerResult) {
        return;
      }
      
      // Step 5: Register hooks for user stats fetching and home screen features
      _registerHooks();
      
      // Step 6: Register screens with NavigationManager
      _registerScreens();
      
      // Step 7: Fetch user stats if already logged in
      _fetchUserStatsIfLoggedIn();
      
      // Step 8: Final verification
      await _performFinalVerification();
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('🎬 DutchGameMain: Error during initialization: $e');
      }
    }
  }

  /// Perform final verification of all components
  Future<Map<String, bool>> _performFinalVerification() async {
    final results = <String, bool>{};
    
    try {
      // Verify StateManager registration
      final stateManager = StateManager();
      results['state_manager'] = stateManager.isModuleStateRegistered('dutch_game');
      
      // Verify DutchModuleManager
      results['dutch_game_manager'] = _dutchModuleManager.isInitialized;
      // Verify DutchEventManager
      results['dutch_message_manager'] = true; // Assuming success if we got here
      
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
      
      if (!stateManager.isModuleStateRegistered('dutch_game')) {
        stateManager.registerModuleState('dutch_game', {
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
          // Removed joinedGamesTimestamp - causes unnecessary state updates
          'currentGameId': '',
          'games': <String, dynamic>{},
          
          // User statistics (from database)
          'userStats': null,
          // Removed userStatsLastUpdated - causes unnecessary state updates
          
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
          // Removed lastUpdated - causes unnecessary state updates
        });
      }
    });
  }

  /// Register hooks for fetching user stats and home screen features
  void _registerHooks() {
    final hooksManager = HooksManager();
    
    // Register hook to fetch user stats when user is fully logged in (after tokens are stored)
    hooksManager.registerHookWithData('auth_login_complete', (data) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameMain: auth_login_complete hook triggered - fetching user stats');
      }
      _fetchUserStats();
    });
    
    // Register hook for home screen to register play button feature
    hooksManager.registerHookWithData('home_screen_main', (data) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameMain: home_screen_main hook triggered - registering play button feature');
      }
      final context = data['context'] as BuildContext?;
      if (context != null) {
        _registerHomeScreenFeatures(context);
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameMain: home_screen_main hook triggered but no context provided');
        }
      }
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameMain: Registered auth_login_complete and home_screen_main hooks');
    }
  }
  
  /// Register home screen features (play button, etc.)
  void _registerHomeScreenFeatures(BuildContext context) {
    try {
      final featureRegistrar = HomeScreenFeatureRegistrar();
      featureRegistrar.registerDutchGamePlayButton(context);
      featureRegistrar.registerDutchGameDemoButton(context);
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameMain: Home screen features registered successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameMain: Error registering home screen features: $e');
      }
    }
  }

  /// Fetch user stats if user is already logged in (on module initialization)
  void _fetchUserStatsIfLoggedIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final isLoggedIn = loginState['isLoggedIn'] == true;
      
      if (isLoggedIn) {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 DutchGameMain: User is already logged in - fetching user stats');
        }
        _fetchUserStats();
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 DutchGameMain: User is not logged in - skipping user stats fetch');
        }
      }
    });
  }

  /// Fetch user dutch game stats from API and update state
  Future<void> _fetchUserStats() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameMain: Fetching user dutch game stats...');
      }
      final success = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (success) {
        if (LOGGING_SWITCH) {
          _logger.info('✅ DutchGameMain: User stats fetched and updated successfully');
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameMain: Failed to fetch user stats');
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameMain: Error fetching user stats: $e');
      }
    }
  }

  /// Register all Dutch game screens with NavigationManager
  void _registerScreens() {
    // Register Dutch Game Lobby Screen (Room Management)
    navigationManager.registerRoute(
      path: '/dutch/lobby',
      screen: (context) => const LobbyScreen(),
      drawerTitle: 'Play',
      drawerIcon: Icons.games,
      drawerPosition: 1, // After Home
    );

    // Register Game Play Screen
    navigationManager.registerRoute(
      path: '/dutch/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Register Demo Screen
    navigationManager.registerRoute(
      path: '/dutch/demo',
      screen: (BuildContext context) => const DemoScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Register Game Rules Screen
    navigationManager.registerRoute(
      path: '/dutch/game-rules',
      screen: (BuildContext context) => const GameRulesScreen(),
      drawerTitle: 'Game Rules',
      drawerIcon: Icons.rule,
      drawerPosition: 1, // Above Account screen (which is 2)
    );
  }

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    // Dispose Dutch game components
    _dutchModuleManager.dispose();
    
    _dutchEventManager.dispose();
    
    super.dispose();
  }

  /// ✅ Health check override
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': isInitialized ? 'DutchGameMain is functioning normally' : 'DutchGameMain not initialized',
      'components': {
        'dutch_game_manager': _dutchModuleManager.isInitialized ? 'healthy' : 'not_initialized',
        'dutch_message_manager': 'initialized',
        'state_manager': 'initialized',
        'navigation_manager': 'initialized',
      },
      'screens_registered': [
        '/dutch/lobby',
        '/dutch/game-play',
        '/dutch/demo',
      ],
      'initialization_time': DateTime.now().toIso8601String(),
    };
  }
}