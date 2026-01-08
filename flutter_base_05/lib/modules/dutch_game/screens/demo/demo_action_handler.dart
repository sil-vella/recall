import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../managers/dutch_event_manager.dart';
import '../../managers/dutch_game_state_updater.dart';
import '../../managers/player_action.dart';
import '../../managers/validated_event_emitter.dart';
import '../../practice/practice_mode_bridge.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../backend_core/services/game_state_store.dart';
import 'demo_state_setup.dart';

const bool LOGGING_SWITCH = true; // Enabled for demo debugging

/// Demo Action Handler
/// 
/// Centralized handler for all demo actions. Each action:
/// - Clears and resets state entirely
/// - Starts a fresh practice match with showInstructions: true and test deck
/// - Sets up game state for the specific action
/// - Navigates to game play screen
class DemoActionHandler {
  static final DemoActionHandler _instance = DemoActionHandler._internal();
  static DemoActionHandler get instance => _instance;
  DemoActionHandler._internal();

  final Logger _logger = Logger();
  final DemoStateSetup _stateSetup = DemoStateSetup();
  
  /// Track the currently active demo action type
  static String? _activeDemoActionType;
  
  /// Check if a demo action is currently active
  static bool isDemoActionActive() {
    return _activeDemoActionType != null;
  }
  
  /// Get the currently active demo action type
  static String? getActiveDemoActionType() {
    return _activeDemoActionType;
  }

  /// Start a demo action
  /// 
  /// [actionType] - One of: 'initial_peek', 'drawing', 'playing', 'same_rank', 
  ///                 'queen_peek', 'jack_swap', 'call_dutch', 'collect_rank'
  Future<void> startDemoAction(String actionType) async {
    try {
      _logger.info('🎮 DemoActionHandler: Starting demo action: $actionType', isOn: LOGGING_SWITCH);
      
      // Set active demo action type
      _activeDemoActionType = actionType;

      // 1. Clear all state
      await _clearAllState();

      // 2. Determine if collection mode is needed
      final isClearAndCollect = actionType == 'collect_rank';

      // 3. Start practice match with showInstructions: true and test deck
      final practiceRoomId = await _startPracticeMatch(
        showInstructions: true,
        isClearAndCollect: isClearAndCollect,
      );

      // 4. Get initial game state
      final gameStateStore = GameStateStore.instance;
      final gameState = gameStateStore.getGameState(practiceRoomId);
      
      _logger.info('🎮 DemoActionHandler: Got initial game state, phase = ${gameState['phase']}', isOn: LOGGING_SWITCH);

      // 5. Advance game state to action-specific state
      final updatedGameState = await _stateSetup.setupActionState(
        actionType: actionType,
        gameId: practiceRoomId,
        gameState: gameState,
      );

      // 6. Sync state and trigger widget updates
      await _syncGameState(practiceRoomId, updatedGameState);

      // 7. Navigate to game play screen
      _logger.info('🎮 DemoActionHandler: Navigating to game play screen', isOn: LOGGING_SWITCH);
      NavigationManager().navigateTo('/dutch/game-play');

      _logger.info('✅ DemoActionHandler: Demo action $actionType started successfully', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DemoActionHandler: Error starting demo action $actionType: $e', 
        error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      rethrow;
    }
  }

  /// Clear all state before starting new demo
  Future<void> _clearAllState() async {
    try {
      _logger.info('🧹 DemoActionHandler: Clearing all state', isOn: LOGGING_SWITCH);

      // Get current game ID if any
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';

      // Remove player from game (clears all game state)
      if (currentGameId.isNotEmpty) {
        DutchGameHelpers.removePlayerFromGame(gameId: currentGameId);
      }

      // End any existing practice session
      final practiceBridge = PracticeModeBridge.instance;
      practiceBridge.endPracticeSession();

      // Clear all state fields
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync({
        'currentGameId': '',
        'currentRoomId': '',
        'isInRoom': false,
        'isRoomOwner': false,
        'isGameActive': false,
        'gamePhase': 'waiting',
        'games': <String, dynamic>{},
        'playerStatus': 'waiting',
        'currentPlayer': null,
        'currentPlayerStatus': 'waiting',
        'roundNumber': 0,
        'discardPile': <Map<String, dynamic>>[],
        'drawPileCount': 0,
        'discardPileCount': 0,
        'turn_events': <Map<String, dynamic>>[],
        'actionText': {
          'isVisible': false,
          'text': '',
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      _logger.info('✅ DemoActionHandler: All state cleared', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ DemoActionHandler: Error clearing state: $e', isOn: LOGGING_SWITCH);
      // Don't rethrow - continue with demo setup
    }
  }

  /// Start practice match with showInstructions and test deck
  Future<String> _startPracticeMatch({
    required bool showInstructions,
    required bool isClearAndCollect,
  }) async {
    try {
      _logger.info('🎮 DemoActionHandler: Starting practice match (showInstructions: $showInstructions, isClearAndCollect: $isClearAndCollect)', isOn: LOGGING_SWITCH);

      // Generate practice mode user data
      final currentUserId = 'demo_user_${DateTime.now().millisecondsSinceEpoch}';
      final practiceUserData = {
        'userId': currentUserId,
        'displayName': 'Demo Player',
        'isPracticeUser': true,
      };

      // Store practice user data and settings in state
      final practiceSettings = {
        'showInstructions': showInstructions,
        'isClearAndCollect': isClearAndCollect,
        'maxPlayers': 4,
        'minPlayers': 2,
      };

      DutchGameHelpers.updateUIState({
        'practiceUser': practiceUserData,
        'practiceSettings': practiceSettings,
      });

      // Switch event emitter to practice mode
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.practice);

      // Initialize and start practice session
      final practiceBridge = PracticeModeBridge.instance;
      await practiceBridge.initialize();

      final practiceRoomId = await practiceBridge.startPracticeSession(
        userId: currentUserId,
        maxPlayers: 4,
        minPlayers: 2,
        gameType: 'practice',
      );

      _logger.info('🎮 DemoActionHandler: Practice room created: $practiceRoomId', isOn: LOGGING_SWITCH);

      // Start match with showInstructions and test deck
      // Note: testingModeOverride is handled in backend when showInstructions is true
      // The game is already created by the room_created hook, we just need to start it
      final startMatchAction = PlayerAction.startMatch(
        gameId: practiceRoomId,
        showInstructions: showInstructions,
        isClearAndCollect: isClearAndCollect,
      );

      await startMatchAction.execute();
      _logger.info('🎮 DemoActionHandler: Match started with showInstructions: $showInstructions', isOn: LOGGING_SWITCH);

      return practiceRoomId;
    } catch (e, stackTrace) {
      _logger.error('❌ DemoActionHandler: Error starting practice match: $e', 
        error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      rethrow;
    }
  }

  /// Sync game state and trigger widget updates
  Future<void> _syncGameState(String gameId, Map<String, dynamic> gameState) async {
    try {
      _logger.info('🎮 DemoActionHandler: Syncing game state for $gameId', isOn: LOGGING_SWITCH);

      // Get current user ID
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final practiceUser = currentState['practiceUser'] as Map<String, dynamic>?;
      final currentUserId = practiceUser?['userId']?.toString() ?? '';

      // Extract and normalize phase
      final rawPhase = gameState['phase']?.toString();
      final uiPhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');

      // Extract game status
      final gameStatus = gameState['status']?.toString() ?? 'active';

      // Get current games map
      final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});

      // Build gameData structure
      final gameData = {
        'game_id': gameId,
        'owner_id': currentUserId,
        'game_type': 'practice',
        'game_state': gameState,
        'max_size': 4,
        'min_players': 2,
      };

      // Add/update game in games map
      games[gameId] = {
        'gameData': gameData,
        'gameStatus': gameStatus,
        'isRoomOwner': true,
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
      };

      // Update critical fields directly
      final dutchStateManager = StateManager();
      final currentDutchState = dutchStateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final updatedDutchState = Map<String, dynamic>.from(currentDutchState);

      updatedDutchState['currentGameId'] = gameId;
      updatedDutchState['currentRoomId'] = gameId;
      updatedDutchState['isInRoom'] = true;
      updatedDutchState['isRoomOwner'] = true;
      updatedDutchState['gameType'] = 'practice';
      updatedDutchState['games'] = games;
      updatedDutchState['gamePhase'] = uiPhase;
      updatedDutchState['currentSize'] = 1;
      updatedDutchState['maxSize'] = 4;
      updatedDutchState['isInGame'] = true;

      // Update StateManager directly
      dutchStateManager.updateModuleState('dutch_game', updatedDutchState);

      // Extract currentPlayer from game state for top-level state
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;

      // Trigger slice recomputation
      DutchGameHelpers.updateUIState({
        'currentGameId': gameId,
        'games': games,
        'gamePhase': uiPhase,
        'currentPlayer': currentPlayer, // Set top-level currentPlayer for UnifiedGameBoardWidget
        'isMyTurn': true, // Ensure isMyTurn is set for demo actions
      });

      // Small delay to allow slice recomputation
      await Future.delayed(const Duration(milliseconds: 50));

      // Initialize previous player status for demo completion detection
      final players = gameState['players'] as List<dynamic>? ?? [];
      String? initialPlayerStatus;
      try {
        final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
          (player) => player['id']?.toString() == currentUserId,
        );
        initialPlayerStatus = myPlayer['status']?.toString();
      } catch (e) {
        // Player not found, will be set on first state update
      }

      // Store initial player status for transition detection
      if (initialPlayerStatus != null) {
        StateManager().updateModuleState('dutch_game', {
          'previousPlayerStatus': initialPlayerStatus,
        });
      }

      // Trigger game_state_updated event to sync widget slices
      _logger.info('🎮 DemoActionHandler: Triggering handleGameStateUpdated for game_id = $gameId', isOn: LOGGING_SWITCH);
      DutchEventManager().handleGameStateUpdated({
        'game_id': gameId,
        'game_state': gameState,
        'owner_id': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('✅ DemoActionHandler: Game state synced successfully', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DemoActionHandler: Error syncing game state: $e', 
        error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      rethrow;
    }
  }

  /// End a demo action and navigate back to demo screen
  /// 
  /// [actionType] - The demo action type that was completed
  Future<void> endDemoAction(String actionType) async {
    try {
      _logger.info('🎮 DemoActionHandler: Ending demo action: $actionType', isOn: LOGGING_SWITCH);
      
      // Clear demo-specific state
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync({
        'actionText': {
          'isVisible': false,
          'text': '',
        },
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
          'key': '',
          'hasDemonstration': false,
        },
        'previousPlayerStatus': null,
      });
      
      // Wait 2-3 seconds to show the result
      await Future.delayed(const Duration(seconds: 2));
      
      // Navigate back to demo screen
      _logger.info('🎮 DemoActionHandler: Navigating back to demo screen', isOn: LOGGING_SWITCH);
      NavigationManager().navigateTo('/dutch/demo');
      
      // Clear active demo action type
      _activeDemoActionType = null;
      
      _logger.info('✅ DemoActionHandler: Demo action $actionType ended successfully', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DemoActionHandler: Error ending demo action $actionType: $e', 
        error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      // Clear active demo action type even on error
      _activeDemoActionType = null;
    }
  }

  /// Check if an action is completed based on status transition
  /// 
  /// [actionType] - The demo action type
  /// [previousStatus] - Previous player status
  /// [currentStatus] - Current player status
  /// Returns true if the action is considered completed
  bool _isActionCompleted(String actionType, String? previousStatus, String? currentStatus) {
    if (previousStatus == null || currentStatus == null) {
      return false;
    }
    
    switch (actionType) {
      case 'initial_peek':
        // Initial peek completes when status changes from initial_peek to waiting or drawing_card
        return previousStatus == 'initial_peek' && 
               (currentStatus == 'waiting' || currentStatus == 'drawing_card');
      
      case 'drawing':
        // Drawing completes when status changes from drawing_card to playing_card (card drawn)
        return previousStatus == 'drawing_card' && currentStatus == 'playing_card';
      
      case 'playing':
        // Playing completes when status changes from playing_card to waiting (card played)
        return previousStatus == 'playing_card' && currentStatus == 'waiting';
      
      case 'same_rank':
        // Same rank completes when status changes from same_rank_window to waiting (card played)
        return previousStatus == 'same_rank_window' && currentStatus == 'waiting';
      
      case 'queen_peek':
        // Queen peek completes when status changes from queen_peek to waiting or playing_card
        return previousStatus == 'queen_peek' && 
               (currentStatus == 'waiting' || currentStatus == 'playing_card');
      
      case 'jack_swap':
        // Jack swap completes when status changes from jack_swap to waiting or playing_card
        return previousStatus == 'jack_swap' && 
               (currentStatus == 'waiting' || currentStatus == 'playing_card');
      
      case 'call_dutch':
        // Call dutch completes when status changes from playing_card to waiting (after call_final_round)
        return previousStatus == 'playing_card' && currentStatus == 'waiting';
      
      case 'collect_rank':
        // Collect rank completes when status changes to waiting (after collect_from_discard)
        return currentStatus == 'waiting' && previousStatus != 'waiting';
      
      default:
        return false;
    }
  }
  
  /// Check if an action is completed (public method for use in event handlers)
  bool isActionCompleted(String actionType, String? previousStatus, String? currentStatus) {
    return _isActionCompleted(actionType, previousStatus, currentStatus);
  }
}

