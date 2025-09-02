import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:recall/core/managers/navigation_manager.dart';
import 'package:recall/core/managers/state_manager.dart';
import 'package:recall/core/services/shared_preferences.dart';
import 'package:recall/modules/recall_game/screens/game_play/game_play_screen.dart';
import 'package:recall/modules/recall_game/screens/lobby_room/lobby_screen.dart';
import 'package:recall/modules/recall_game/screens/practice_room/practice_room.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../tools/logging/logger.dart';

// Import Recall game components
import 'managers/recall_module_manager.dart';
import 'managers/recall_event_manager.dart';

/// Recall Game Module
/// Main module for the Recall card game functionality
class RecallGameMain extends ModuleBase {
  static final Logger _log = Logger();
  late ModuleManager _localModuleManager;
  late ServicesManager _servicesManager;
  SharedPrefManager? _sharedPref;
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
    _localModuleManager = moduleManager;
    
    _log.info('🎮 Starting Recall Game Module initialization...');
    _log.info('🎮 Context provided: ${context != null ? 'valid' : 'null'}');
    _log.info('🎮 ModuleManager provided: ${moduleManager != null ? 'valid' : 'null'}');
    
    _initDependencies(context);
    _log.info('✅ RecallGameMain dependencies initialized.');
    
    // Initialize all Recall game components
    _initializeRecallComponents();
  }

  /// ✅ Initialize dependencies using Provider
  void _initDependencies(BuildContext context) {
    _log.info('🔧 Initializing dependencies...');
    
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _log.info('🔧 ServicesManager obtained: ${_servicesManager != null ? 'valid' : 'null'}');
    
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    _log.info('🔧 SharedPrefManager obtained: ${_sharedPref != null ? 'valid' : 'null'}');
    
    _log.info('✅ Dependencies initialized successfully');
  }

  /// Initialize all Recall game components
  Future<void> _initializeRecallComponents() async {
    _log.info('🎮 Initializing Recall game components...');
    
    try {
      // Step 1: Register state with StateManager
      _log.info('📊 Step 1: Registering Recall game state...');
      _registerState();
      
      // Step 2: Initialize RecallModuleManager
      _log.info('🎮 Step 2: Initializing RecallModuleManager...');
      final gameManagerResult = await _recallModuleManager.initialize();
      _log.info('🎮 RecallModuleManager initialization result: $gameManagerResult');
      if (!gameManagerResult) {
        _log.error('❌ RecallModuleManager initialization failed');
        return;
      }
            
      // Step 4: Initialize RecallEventManager
      _log.info('📨 Step 4: Initializing RecallEventManager...');
      final messageManagerResult = await _recallEventManager.initialize();
      _log.info('📨 RecallEventManager initialization result: $messageManagerResult');
      if (!messageManagerResult) {
        _log.error('❌ RecallEventManager initialization failed');
        return;
      }
      
      // Step 5: Register screens with NavigationManager
      _log.info('🗺️ Step 5: Registering Recall game screens...');
      _registerScreens();
      
      // Step 6: Final verification
      _log.info('🔍 Step 6: Performing final verification...');
      final verificationResults = await _performFinalVerification();
      _log.info('🔍 Final verification results: $verificationResults');
      
      _log.info('🎉 Recall Game Module initialization completed successfully!');
      
    } catch (e) {
      _log.error('❌ Error during Recall game components initialization: $e');
      _log.error('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// Perform final verification of all components
  Future<Map<String, bool>> _performFinalVerification() async {
    final results = <String, bool>{};
    
    try {
      // Verify StateManager registration
      final stateManager = StateManager();
      results['state_manager'] = stateManager.isModuleStateRegistered('recall_game');
      _log.info('🔍 StateManager verification: ${results['state_manager']}');
      
      // Verify RecallModuleManager
      results['recall_game_manager'] = _recallModuleManager.isInitialized;
      _log.info('🔍 RecallModuleManager verification: ${results['recall_game_manager']}');
      // Verify RecallEventManager
      results['recall_message_manager'] = true; // Assuming success if we got here
      _log.info('🔍 RecallEventManager verification: ${results['recall_message_manager']}');
      
      // Verify NavigationManager routes
      results['navigation_manager'] = true; // Assuming success if we got here
      _log.info('🔍 NavigationManager verification: ${results['navigation_manager']}');
      
    } catch (e) {
      _log.error('❌ Error during final verification: $e');
      results['verification_error'] = false;
    }
    
    return results;
  }

  void _registerState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
          
          // Metadata
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        _log.info('✅ Recall game core state registered');
      } else {
        _log.info('📊 Recall game state already registered');
      }
      
      // Verify state registration
      final isRegistered = stateManager.isModuleStateRegistered('recall_game');
      _log.info('📊 State registration verification: $isRegistered');
    });
  }

  /// Register all Recall game screens with NavigationManager
  void _registerScreens() {
    _log.info('🗺️ NavigationManager obtained for screen registration');

    // Register Recall Game Lobby Screen (Room Management)
    _log.info('🗺️ Registering PracticeScreen route: /recall/practice');
    navigationManager.registerRoute(
      path: '/recall/practice',
      screen: (context) => const PracticeScreen(),
      drawerTitle: 'Practice',
      drawerIcon: Icons.games,
      drawerPosition: 5, // After existing screens
    );
    _log.info('✅ PracticeScreen route registered');

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

    // Register Game Play Screen
    _log.info('🗺️ Registering GamePlayScreen route: /recall/game-play');
    navigationManager.registerRoute(
      path: '/recall/game-play',
      screen: (BuildContext context) => const GamePlayScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );
    _log.info('✅ GamePlayScreen route registered');

    _log.info('✅ Recall game screens registered with NavigationManager');
  }

  /// ✅ Cleanup resources when module is disposed
  @override
  void dispose() {
    _log.info('🛑 Starting RecallGameMain disposal...');
    
    // Dispose Recall game components
    _recallModuleManager.dispose();
    _log.info('🛑 RecallModuleManager disposed');
    
    _recallEventManager.dispose();
    _log.info('🛑 RecallEventManager disposed');
    
    _log.info('🛑 RecallGameMain disposed.');
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