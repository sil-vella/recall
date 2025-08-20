import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:recall/core/managers/navigation_manager.dart';
import 'package:recall/core/managers/state_manager.dart';
import 'package:recall/core/services/shared_preferences.dart';
import 'package:recall/modules/recall_game/screens/game_play/game_play_screen.dart';
import 'package:recall/modules/recall_game/screens/lobby_room/lobby_screen.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../tools/logging/logger.dart';

/// Template for creating new modules
/// 
/// Usage:
/// 1. Copy this file to your new module directory
/// 2. Rename the class to your module name
/// 3. Implement required methods
/// 4. Add your module-specific functionality
class RecallGameMain extends ModuleBase {
  static final Logger _log = Logger();
  late ModuleManager _localModuleManager;
  late ServicesManager _servicesManager;
  SharedPrefManager? _sharedPref;
  final navigationManager = NavigationManager();

  /// ✅ Constructor with module key and dependencies
  RecallGameMain() : super("recall_game_module", dependencies: []);

  /// ✅ Initialize module with context and module manager
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _localModuleManager = moduleManager;
    _initDependencies(context);
    _log.info('✅ RecallGameMain initialized with context.');
    _registerState();

  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    // Add other dependencies as needed
    // Example: _otherModule = _localModuleManager.getModuleByType<OtherModule>();
        // Initialize login state in StateManager after the current frame

  }

  void _registerState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = StateManager();
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
    });
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

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    _log.info('🗑 RecallGameMain disposed.');
    super.dispose();
  }

  /// ✅ Example method - add your module-specific methods below
  Future<Map<String, dynamic>> exampleMethod(BuildContext context) async {
    try {
      _log.info('🔧 RecallGameMain example method called');
      return {"success": "Example method executed successfully"};
    } catch (e) {
      _log.error('❌ Error in example method: $e');
      return {"error": "Example method failed: $e"};
    }
  }

  /// ✅ Example health check override
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': moduleKey,
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'details': isInitialized ? 'RecallGameMain is functioning normally' : 'RecallGameMain not initialized',
      'custom_metric': 'example_value'
    };
  }
}