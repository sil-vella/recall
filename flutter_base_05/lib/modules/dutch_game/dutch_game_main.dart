import 'package:flutter/material.dart';
import 'package:dutch/core/managers/navigation_manager.dart';
import 'package:dutch/core/managers/state_manager.dart';
import 'package:dutch/modules/dutch_game/screens/game_play/game_play_screen.dart';
import 'package:dutch/modules/dutch_game/screens/lobby_room/lobby_screen.dart';
import 'package:dutch/modules/dutch_game/screens/demo/demo_screen.dart';
import 'package:dutch/modules/dutch_game/screens/demo/video_tutorial_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../utils/consts/theme_consts.dart';

// Import Dutch game components
import '../dutch_game/managers/dutch_module_manager.dart';
import '../dutch_game/managers/dutch_event_manager.dart';
import '../dutch_game/managers/dutch_game_state_updater.dart';
import '../dutch_game/utils/dutch_game_helpers.dart';
import '../dutch_game/screens/game_play/utils/dutch_anim_runtime.dart';
import '../dutch_game/screens/home_screen/features/home_screen_features.dart';
import '../../screens/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../../screens/coin_purchase_screen/coin_purchase_screen.dart';
import '../dutch_game/screens/shop/dutch_cosmetics_shop_screen.dart';
import '../dutch_game/screens/admin_tournaments_screen/admin_tournaments_screen.dart';
import '../dutch_game/screens/leaderboard/leaderboard_screen.dart';
import '../dutch_game/screens/leaderboard/leaderboard_history_screen.dart';
import '../dutch_game/screens/achievements/achievements_screen.dart';

/// Dutch Game Module
/// Main module for the Dutch card game functionality
class DutchGameMain extends ModuleBase {
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
      
      
      // Access singletons to trigger their initialization
      // ignore: unused_local_variable
      final _ = DutchGameStateUpdater.instance; // Triggers constructor and handler setup
      
      
      
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

          // Stable ref for discovery/debug only — anim queue/rects live in [DutchAnimRuntime.instance], not StateManager.
          'animRuntime': DutchAnimRuntime.instance,
          
          // Metadata
          // Removed lastUpdated - causes unnecessary state updates
        });
      }
    });
  }

  /// Register hooks for fetching user stats and home screen features
  void _registerHooks() {
    final hooksManager = HooksManager();
    
    // Interactive login / registration (LoginModule after tokens stored)
    hooksManager.registerHookWithData('auth_login_complete', (data) {
      
      _fetchUserStats();
    });

    // Session restore and any path that sets AuthStatus.loggedIn via handleAuthState
    // (HooksManager replays to late registrants via _triggeredHooksData.)
    hooksManager.registerHookWithData('auth_login_success', (data) {
      
      _fetchUserStats();
    });
    
    // Register hook for home screen to register play button feature
    hooksManager.registerHookWithData('home_screen_main', (data) {
      
      final context = data['context'] as BuildContext?;
      if (context != null) {
        _registerHomeScreenFeatures(context);
      } else {
        
      }
    });
    
    
  }
  
  /// Register home screen features (play button, etc.)
  void _registerHomeScreenFeatures(BuildContext context) {
    try {
      final featureRegistrar = HomeScreenFeatureRegistrar();
      featureRegistrar.registerDutchGamePlayButton(context);
      featureRegistrar.registerDutchGameDemoButton(context);
      
    } catch (e) {
      
    }
  }

  /// Fetch user stats if user is already logged in (on module initialization)
  void _fetchUserStatsIfLoggedIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final isLoggedIn = loginState['isLoggedIn'] == true;
      
      if (isLoggedIn) {
        
        _fetchUserStats();
      } else {
        
      }
    });
  }

  /// Fetch user dutch game stats from API and update state
  Future<void> _fetchUserStats() async {
    try {
      
      final success = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (success) {
        
      } else {
        
      }
    } catch (e) {
      
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
      drawerPosition: 10, // After Home; unique positions avoid path-only tie-break
    );

    // Register Game Play Screen
    navigationManager.registerRoute(
      path: '/dutch/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Register Demo Screen (drawer: "Learn How", between Play and My Account)
    navigationManager.registerRoute(
      path: '/dutch/demo',
      screen: (BuildContext context) => const DemoScreen(),
      drawerTitle: 'Learn How',
      drawerIcon: Icons.school,
      drawerPosition: 30,
    );

    // Register Video Tutorial Screen (from Demo screen)
    navigationManager.registerRoute(
      path: '/dutch/video-tutorial',
      screen: (BuildContext context) => const VideoTutorialScreen(),
      drawerTitle: null,
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Register Admin Dashboard (admin-only, no drawer entry; reached from Account screen)
    navigationManager.registerRoute(
      path: '/admin/dashboard',
      screen: (BuildContext context) => const AdminDashboardScreen(),
      drawerTitle: null,
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Register Admin Tournaments (admin-only, no drawer entry; reached from Admin Dashboard)
    navigationManager.registerRoute(
      path: '/admin/tournaments',
      screen: (BuildContext context) => const AdminTournamentsScreen(),
      drawerTitle: null,
      drawerIcon: null,
      drawerPosition: 999,
    );

    // Leaderboard before Buy coins; My Account is drawerPosition 60 in NavigationManager.
    navigationManager.registerRoute(
      path: '/dutch/leaderboard',
      screen: (BuildContext context) => const LeaderboardScreen(),
      drawerTitle: 'Leaderboard',
      drawerIcon: Icons.emoji_events,
      drawerPosition: 40,
    );

    navigationManager.registerRoute(
      path: '/dutch/leaderboard/history',
      screen: (BuildContext context) => const LeaderboardHistoryScreen(),
      drawerTitle: null,
      drawerIcon: null,
      drawerPosition: 999,
    );

    navigationManager.registerRoute(
      path: '/dutch/achievements',
      screen: (BuildContext context) => const AchievementsScreen(),
      drawerTitle: 'Achievements',
      drawerIcon: Icons.workspace_premium,
      drawerPosition: 45,
    );

    navigationManager.registerRoute(
      path: '/coin-purchase',
      screen: (BuildContext context) => const CoinPurchaseScreen(),
      drawerTitle: 'Buy coins',
      drawerIcon: Icons.monetization_on,
      drawerPosition: 50,
    );
    navigationManager.registerRoute(
      path: '/dutch-customize',
      screen: (BuildContext context) {
        
        try {
          return const DutchCustomizeScreen();
        } catch (e) {
          
          return Scaffold(
            body: Center(
              child: Text(
                'Customize screen failed to open.',
                style: AppTextStyles.bodyMedium(),
              ),
            ),
          );
        }
      },
      drawerTitle: 'Customize',
      drawerIcon: Icons.palette_outlined,
      drawerPosition: 55,
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