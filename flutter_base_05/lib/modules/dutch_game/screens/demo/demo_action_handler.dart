import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../managers/dutch_event_manager.dart';
import '../../managers/dutch_game_state_updater.dart';
import '../../managers/player_action.dart';
import '../../managers/validated_event_emitter.dart';
import '../../practice/practice_mode_bridge.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../utils/game_instructions_provider.dart';
import '../../backend_core/services/game_state_store.dart';
import 'demo_state_setup.dart';
import 'demo_functionality.dart';

const bool LOGGING_SWITCH = false; // Enabled for demo debugging

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
  
  /// Flag to prevent multiple calls to endDemoAction
  static bool _isEndingDemoAction = false;
  
  /// Track initial hand count for collect_rank demo
  static int? _collectRankInitialHandCount;
  
  /// Track sequential demo mode
  static bool _isSequentialDemoMode = false;
  static int _currentSequentialDemoIndex = 0;
  static List<String> _sequentialDemoActions = [];
  
  /// Check if a demo action is currently active
  static bool isDemoActionActive() {
    return _activeDemoActionType != null;
  }
  
  /// Get the currently active demo action type
  static String? getActiveDemoActionType() {
    return _activeDemoActionType;
  }
  
  /// Check if sequential demo mode is active
  static bool isSequentialDemoMode() {
    return _isSequentialDemoMode;
  }
  
  /// Start sequential demo mode - runs all demos one after another
  /// 
  /// This will go through all demo actions in order, automatically moving
  /// from one to the next when each completes.
  Future<void> startSequentialDemos() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Starting sequential demo mode');
      }
      
      // Define the order of demos
      _sequentialDemoActions = [
        'initial_peek',
        'drawing',
        'playing',
        'same_rank',
        'queen_peek',
        'jack_swap',
        'call_dutch',
        'collect_rank',
      ];
      
      // Initialize sequential demo mode
      _isSequentialDemoMode = true;
      _currentSequentialDemoIndex = 0;
      
      // Start the first demo
      final firstActionType = _sequentialDemoActions[_currentSequentialDemoIndex];
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Starting first demo in sequence: $firstActionType');
      }
      
      await startDemoAction(firstActionType);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: Sequential demo mode started'); } } catch (e, stackTrace) { if (LOGGING_SWITCH) {
          _logger.error('❌ DemoActionHandler: Error starting sequential demos: $e',  error: e, stackTrace: stackTrace);
        }
      // Reset sequential mode on error
      _isSequentialDemoMode = false;
      _currentSequentialDemoIndex = 0;
      _sequentialDemoActions = [];
      rethrow;
    }
  }

  /// Start a demo action
  /// 
  /// [actionType] - One of: 'initial_peek', 'drawing', 'playing', 'same_rank', 
  ///                 'queen_peek', 'jack_swap', 'call_dutch', 'collect_rank'
  Future<void> startDemoAction(String actionType) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Starting demo action: $actionType');
      }
      
      // 1. Clear all state FIRST (before setting active demo action)
      // This ensures no leftover state from previous demos can interfere
      await _clearAllState();
      
      // 2. Reset ending flag in case it was left set
      _isEndingDemoAction = false;
      
      // 3. Reset collect_rank initial hand count
      _collectRankInitialHandCount = null;
      
      // 4. Set active demo action type AFTER clearing state
      _activeDemoActionType = actionType;

      // 5. Determine if collection mode is needed
      final isClearAndCollect = actionType == 'collect_rank';

      // 4. Start practice match with showInstructions: true and test deck
      final practiceRoomId = await _startPracticeMatch(
        showInstructions: true,
        isClearAndCollect: isClearAndCollect,
      );

      // 5. Get initial game state
      final gameStateStore = GameStateStore.instance;
      final gameState = gameStateStore.getGameState(practiceRoomId);
      
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Got initial game state, phase = ${gameState['phase']}');
      }

      // 6. Advance game state to action-specific state
      final updatedGameState = await _stateSetup.setupActionState(
        actionType: actionType,
        gameId: practiceRoomId,
        gameState: gameState,
      );

      // 7. Sync state and trigger widget updates
      await _syncGameState(practiceRoomId, updatedGameState);
      
      // For collect_rank demo, set initial hand count after state is set up
      // This must happen BEFORE the user can collect, so we capture the baseline
      if (actionType == 'collect_rank') {
        _setInitialHandCountForCollectRank(updatedGameState);
      }

      // 8. Show instructions for this demo action
      _showDemoInstructions(actionType);

      // 9. Navigate to game play screen
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Navigating to game play screen');
      }
      NavigationManager().navigateTo('/dutch/game-play');

      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: Demo action $actionType started successfully'); } } catch (e, stackTrace) { if (LOGGING_SWITCH) {
          _logger.error('❌ DemoActionHandler: Error starting demo action $actionType: $e',  error: e, stackTrace: stackTrace);
        }
      rethrow;
    }
  }

  /// Clear all state before starting new demo
  /// This must be called BEFORE setting _activeDemoActionType to prevent false completion detection
  /// Uses the same comprehensive clearing logic as clearAllGameStateBeforeNewGame() to ensure
  /// complete cleanup when switching from any mode (practice, WebSocket, or another demo) to a demo
  Future<void> _clearAllState() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🧹 DemoActionHandler: Clearing all state before starting demo');
      }

      // 1. Clear active demo action type FIRST to prevent completion detection
      // This must happen before calling clearAllGameStateBeforeNewGame() to prevent false detection
      _activeDemoActionType = null;

      // 2. Use the same comprehensive clearing logic as used for random join, create/join room, and practice match
      // This ensures complete cleanup when switching from any mode (practice, WebSocket, or another demo) to a demo
      // The method handles:
      // - Cancelling leave game timers
      // - Resetting transport mode to WebSocket (before leaving rooms)
      // - Leaving current game (WebSocket or practice)
      // - Leaving other games in games map
      // - Clearing GameStateStore entries
      // - Ending practice sessions
      // - Clearing practice user data and settings
      // - Clearing all game state
      // - Clearing additional state fields
      await DutchGameHelpers.clearAllGameStateBeforeNewGame();
      
      // 3. Clear demo-specific state fields that aren't covered by clearAllGameStateBeforeNewGame()
      // These are demo-specific and need to be cleared separately
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
        'previousPlayerStatus': null, // CRITICAL: Clear to prevent false completion detection
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: All state cleared successfully before starting demo');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DemoActionHandler: Error clearing state: $e', error: e, stackTrace: stackTrace);
      }
      // Don't rethrow - continue with demo setup
    }
  }

  /// Start practice match with showInstructions and test deck
  Future<String> _startPracticeMatch({
    required bool showInstructions,
    required bool isClearAndCollect,
  }) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Starting practice match (showInstructions: $showInstructions, isClearAndCollect: $isClearAndCollect)');
      }

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

      // Demo matches use medium difficulty by default
      final practiceRoomId = await practiceBridge.startPracticeSession(
        userId: currentUserId,
        maxPlayers: 4,
        minPlayers: 2,
        gameType: 'practice',
        difficulty: 'medium', // Demo matches use medium difficulty
      );

      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Practice room created: $practiceRoomId');
      }

      // Start match with showInstructions and test deck
      // Note: testingModeOverride is handled in backend when showInstructions is true
      // The game is already created by the room_created hook, we just need to start it
      final startMatchAction = PlayerAction.startMatch(
        gameId: practiceRoomId,
        showInstructions: showInstructions,
        isClearAndCollect: isClearAndCollect,
      );

      await startMatchAction.execute();
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Match started with showInstructions: $showInstructions');
      }

      return practiceRoomId;
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DemoActionHandler: Error starting practice match: $e',  error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Sync game state and trigger widget updates
  Future<void> _syncGameState(String gameId, Map<String, dynamic> gameState) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Syncing game state for $gameId');
      }

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

      // IMPORTANT: Do NOT set previousPlayerStatus during initial sync
      // It will be set on the first real state update from the backend
      // Setting it here could cause false completion detection if there's leftover state

      // Trigger game_state_updated event to sync widget slices
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Triggering handleGameStateUpdated for game_id = $gameId');
      }
      DutchEventManager().handleGameStateUpdated({
        'game_id': gameId,
        'game_state': gameState,
        'owner_id': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: Game state synced successfully'); } } catch (e, stackTrace) { if (LOGGING_SWITCH) {
          _logger.error('❌ DemoActionHandler: Error syncing game state: $e',  error: e, stackTrace: stackTrace);
        }
      rethrow;
    }
  }

  /// End a demo action and navigate back to demo screen
  /// 
  /// [actionType] - The demo action type that was completed
  Future<void> endDemoAction(String actionType) async {
    // Prevent multiple calls to endDemoAction
    if (_isEndingDemoAction) {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Already ending demo action, skipping duplicate call');
      }
      return;
    }
    
    _isEndingDemoAction = true;
    
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Ending demo action: $actionType');
      }
      
      // IMPORTANT: Keep _activeDemoActionType set until after navigation
      // This prevents _triggerInstructionsIfNeeded from showing instructions
      // during the delay period or after state updates
      
      // 1. Clear demo-specific state (but keep _activeDemoActionType set)
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
        'previousPlayerStatus': null, // CRITICAL: Clear to prevent false detection on next demo
      });
      
      // 2. Clear all game state immediately to ensure clean slate for next demo
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isNotEmpty) {
        // Remove player from game
        DutchGameHelpers.removePlayerFromGame(gameId: currentGameId);
        
        // Clear from GameStateStore
        final gameStateStore = GameStateStore.instance;
        gameStateStore.clear(currentGameId);
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DemoActionHandler: Cleared GameStateStore for ended demo: $currentGameId');
        }
      }
      
      // 3. End practice session
      final practiceBridge = PracticeModeBridge.instance;
      practiceBridge.endPracticeSession();
      
      // 4. Check if we're in sequential demo mode
      if (_isSequentialDemoMode && _currentSequentialDemoIndex < _sequentialDemoActions.length - 1) {
        // Continue to next demo in sequence
        _currentSequentialDemoIndex++;
        final nextActionType = _sequentialDemoActions[_currentSequentialDemoIndex];
        
        // Clear active demo action type before starting next
        _activeDemoActionType = null;
        
        if (LOGGING_SWITCH) {
          _logger.info('🎮 DemoActionHandler: Continuing sequential demo - moving to: $nextActionType (${_currentSequentialDemoIndex + 1}/${_sequentialDemoActions.length})');
        }
        
        // Wait a bit before starting next demo
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Start the next demo
        await startDemoAction(nextActionType);
        
        if (LOGGING_SWITCH) {
          _logger.info('✅ DemoActionHandler: Sequential demo continued to: $nextActionType');
        }
      } else {
        // End of sequence or not in sequential mode - navigate back to demo screen
        if (_isSequentialDemoMode) {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 DemoActionHandler: Sequential demo sequence completed (${_sequentialDemoActions.length} demos)');
          }
          _isSequentialDemoMode = false;
          _currentSequentialDemoIndex = 0;
          _sequentialDemoActions = [];
        }
      
      // 5. Navigate back to demo screen (non-sequential mode)
      if (LOGGING_SWITCH) {
        _logger.info('🎮 DemoActionHandler: Navigating back to demo screen');
      }
      NavigationManager().navigateTo('/dutch/demo');
      
      // 6. NOW clear active demo action type AFTER navigation
      // This ensures instructions won't show during or after the demo action ends
      _activeDemoActionType = null;
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: Demo action $actionType ended successfully');
      }
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DemoActionHandler: Error ending demo action $actionType: $e',  error: e, stackTrace: stackTrace);
      }
      // Clear active demo action type even on error
      _activeDemoActionType = null;
    } finally {
      // Reset flag to allow future demo actions
      _isEndingDemoAction = false;
    }
  }

  /// Check if an action is completed based on status transition or state changes
  /// 
  /// [actionType] - The demo action type
  /// [previousStatus] - Previous player status
  /// [currentStatus] - Current player status
  /// [gameState] - Optional game state for checking hand count changes (for collect_rank)
  /// Returns true if the action is considered completed
  bool _isActionCompleted(String actionType, String? previousStatus, String? currentStatus, {Map<String, dynamic>? gameState}) {
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
        // Playing completes when status changes from playing_card to same_rank_window (card played)
        // After playing a card, the status transitions to same_rank_window to allow other players to play same rank
        return previousStatus == 'playing_card' && currentStatus == 'same_rank_window';
      
      case 'same_rank':
        // Same rank completes when status changes from same_rank_window to waiting (card played)
        return previousStatus == 'same_rank_window' && currentStatus == 'waiting';
      
      case 'queen_peek':
        // Queen peek completes when status changes from queen_peek to peeking (peek action executed)
        return previousStatus == 'queen_peek' && currentStatus == 'peeking';
      
      case 'jack_swap':
        // Jack swap completes when status changes from jack_swap to waiting or playing_card
        return previousStatus == 'jack_swap' && 
               (currentStatus == 'waiting' || currentStatus == 'playing_card');
      
      case 'call_dutch':
        // Call dutch completes when status changes from playing_card to same_rank_window (after call_final_round and card played)
        return previousStatus == 'playing_card' && currentStatus == 'same_rank_window';
      
      case 'collect_rank':
        // Collect rank completes when a collection card is added to the hand
        // Check if hand count has increased (indicating a card was collected)
        if (gameState != null) {
          try {
            // CRITICAL: If initial hand count hasn't been set yet, don't check for completion
            // This prevents false positives during initial state setup
            if (_collectRankInitialHandCount == null) {
              if (LOGGING_SWITCH) {
                _logger.info('🔍 DemoActionHandler: Initial hand count not set yet, skipping collect_rank completion check');
              }
              return false;
            }
            
            // Get current user ID using the same method as _syncWidgetStatesFromGameState
            // This returns sessionId in practice mode (practice_session_<userId>)
            final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
            final practiceUser = currentState['practiceUser'] as Map<String, dynamic>?;
            String currentUserId = '';
            
            if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
              final practiceUserId = practiceUser['userId']?.toString() ?? '';
              if (practiceUserId.isNotEmpty) {
                // In practice mode, player ID is the sessionId, not the userId
                currentUserId = 'practice_session_$practiceUserId';
              }
            }
            
            if (currentUserId.isEmpty) {
              if (LOGGING_SWITCH) {
                _logger.warning('⚠️ DemoActionHandler: No current user ID found for collect_rank completion check');
              }
              return false;
            }
            
            if (LOGGING_SWITCH) {
              _logger.info('🔍 DemoActionHandler: Checking collect_rank completion - currentUserId: $currentUserId');
            }
            
            // Get players from game state
            final players = gameState['players'] as List<dynamic>? ?? [];
            if (LOGGING_SWITCH) {
              _logger.info('🔍 DemoActionHandler: Found ${players.length} players in game state');
            }
            
            // Find the current user's player
            Map<String, dynamic>? currentPlayer;
            for (final player in players) {
              if (player is Map<String, dynamic>) {
                final playerId = player['id']?.toString() ?? '';
                if (LOGGING_SWITCH) {
                  _logger.info('🔍 DemoActionHandler: Checking player ID: $playerId');
                }
                if (playerId == currentUserId) {
                  currentPlayer = player;
                  if (LOGGING_SWITCH) {
                    _logger.info('✅ DemoActionHandler: Found matching player: $playerId');
                  }
                  break;
                }
              }
            }
            
            if (currentPlayer == null) {
              if (LOGGING_SWITCH) {
                _logger.warning('⚠️ DemoActionHandler: Current user ($currentUserId) not found in players list');
              }
              return false;
            }
            
            // Get hand from player
            final hand = currentPlayer['hand'] as List<dynamic>? ?? [];
            final currentHandCount = hand.length;
            if (LOGGING_SWITCH) {
              _logger.info('🔍 DemoActionHandler: Current hand count: $currentHandCount, Initial hand count: $_collectRankInitialHandCount');
            }
            
            // Check if hand count has increased (card was collected)
            if (currentHandCount > _collectRankInitialHandCount!) {
              if (LOGGING_SWITCH) {
                _logger.info('🎮 DemoActionHandler: Collect rank demo completed - hand count increased from $_collectRankInitialHandCount to $currentHandCount');
              }
              return true;
            }
          } catch (e, stackTrace) {
            if (LOGGING_SWITCH) {
              _logger.error('❌ DemoActionHandler: Error checking collect_rank completion: $e',  error: e, stackTrace: stackTrace);
            }
          }
        }
        return false;
      
      default:
        return false;
    }
  }
  
  /// Set initial hand count for collect_rank demo
  /// This should be called after the demo state is set up
  void _setInitialHandCountForCollectRank(Map<String, dynamic> gameState) {
    try {
      // Get current user ID
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final practiceUser = currentState['practiceUser'] as Map<String, dynamic>?;
      String currentUserId = '';
      
      if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
        final practiceUserId = practiceUser['userId']?.toString() ?? '';
        if (practiceUserId.isNotEmpty) {
          currentUserId = 'practice_session_$practiceUserId';
        }
      }
      
      if (currentUserId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DemoActionHandler: No current user ID found for setting initial hand count');
        }
        return;
      }
      
      // Get players from game state
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Find the current user's player
      for (final player in players) {
        if (player is Map<String, dynamic>) {
          final playerId = player['id']?.toString() ?? '';
          if (playerId == currentUserId) {
            final hand = player['hand'] as List<dynamic>? ?? [];
            _collectRankInitialHandCount = hand.length;
            if (LOGGING_SWITCH) {
              _logger.info('🎮 DemoActionHandler: Set initial hand count for collect_rank demo: $_collectRankInitialHandCount');
            }
            return;
          }
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ DemoActionHandler: Current user ($currentUserId) not found in players list for setting initial hand count');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DemoActionHandler: Error setting initial hand count: $e');
      }
    }
  }

  /// Check if an action is completed (public method for use in event handlers)
  bool isActionCompleted(String actionType, String? previousStatus, String? currentStatus, {Map<String, dynamic>? gameState}) {
    return _isActionCompleted(actionType, previousStatus, currentStatus, gameState: gameState);
  }

  /// Get after-action instruction content for a demo action
  /// 
  /// [actionType] - The demo action type
  /// Returns a map with 'title' and 'content' for the instruction
  Map<String, String> _getAfterActionInstruction(String actionType) {
    switch (actionType) {
      case 'initial_peek':
        return {
          'title': 'Initial Peek Complete',
          'content': 'You peeked at 2 of your cards. The more you know, the better.',
        };
      case 'drawing':
        return {
          'title': 'Card Drawn',
          'content': 'You drew a card from the draw pile and added it to your hand. Time to play a card.',
        };
      case 'playing':
        return {
          'title': 'Card Played',
          'content': 'You played a card from your hand to the discard pile. Players, including you, can now play a card with the same rank if they have one during same rank window.',
        };
      case 'same_rank':
        return {
          'title': 'Wrong Same Rank',
          'content': 'You played a wrong rank during same rank window and was given a penalty card.',
        };
      case 'queen_peek':
        return {
          'title': 'Queen Power Used',
          'content': 'You used the Queen\'s power to peek at a card.',
        };
      case 'jack_swap':
        return {
          'title': 'Jack Power Used',
          'content': 'You used the Jack\'s power to swap two cards. This can help you improve your hand or disrupt opponents.',
        };
      case 'call_dutch':
        return {
          'title': 'Dutch Called',
          'content': 'You called Dutch to signal the final round. All players will get one more turn, then the game ends and points are calculated.',
        };
      case 'collect_rank':
        return {
          'title': 'Rank Collected',
          'content': 'You collected cards of the same rank from the discard pile. Collecting all 4 cards of your rank is one way to win the game. Remember, collections score as one card regardless of how many cards they contain.',
        };
      default:
        return {
          'title': 'Action Complete',
          'content': 'You completed the demo action.',
        };
    }
  }

  /// Show after-action instruction for a completed demo action
  /// 
  /// [actionType] - The demo action type that was completed
  Future<void> showAfterActionInstruction(String actionType) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📚 DemoActionHandler: Showing after-action instruction for: $actionType');
      }
      
      // Wait 2 seconds before showing instruction
      await Future.delayed(const Duration(seconds: 2));
      
      // Get instruction content for this action
      final instruction = _getAfterActionInstruction(actionType);
      
      // Create callback that will execute endDemoAction when instruction is closed
      void onCloseCallback() {
        if (LOGGING_SWITCH) {
          _logger.info('📚 DemoActionHandler: After-action instruction closed - executing endDemoAction');
        }
        endDemoAction(actionType);
      }
      
      // Show the instruction with custom close callback
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync({
        'instructions': {
          'isVisible': true,
          'title': instruction['title'] ?? 'Action Complete',
          'content': instruction['content'] ?? 'You completed the demo action.',
          'key': 'demo_after_${actionType}',
          'hasDemonstration': false,
          'onClose': onCloseCallback, // Custom close action
        },
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: After-action instruction shown for $actionType'); } } catch (e, stackTrace) { if (LOGGING_SWITCH) {
          _logger.error('❌ DemoActionHandler: Error showing after-action instruction: $e',  error: e, stackTrace: stackTrace);
        }
      // Fallback: end demo action if instruction fails
      endDemoAction(actionType);
    }
  }

  /// Show instructions for a demo action
  ///
  /// [actionType] - The demo action type
  void _showDemoInstructions(String actionType) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📚 DemoActionHandler: Showing instructions for demo action: $actionType');
      }

      // Map demo action types to instruction keys and get instructions
      Map<String, dynamic>? instructions;
      switch (actionType) {
        case 'initial_peek':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'initial_peek',
            playerStatus: 'initial_peek',
            isMyTurn: true,
          );
          break;
        case 'drawing':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'playing',
            playerStatus: 'drawing_card',
            isMyTurn: true,
          );
          break;
        case 'playing':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'playing',
            playerStatus: 'playing_card',
            isMyTurn: true,
          );
          break;
        case 'same_rank':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'same_rank_window',
            playerStatus: 'same_rank_window',
            isMyTurn: true,
          );
          break;
        case 'queen_peek':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'playing',
            playerStatus: 'queen_peek',
            isMyTurn: true,
          );
          break;
        case 'jack_swap':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'playing',
            playerStatus: 'jack_swap',
            isMyTurn: true,
          );
          break;
        case 'collect_rank':
          instructions = GameInstructionsProvider.getInstructions(
            gamePhase: 'same_rank_window',
            playerStatus: 'collection_card',
            isMyTurn: true,
          );
          break;
        case 'call_dutch':
          // Get instructions from DemoFunctionality
          final demoInstructions = DemoFunctionality.instance.getInstructionsForPhase('call_dutch');
          if (demoInstructions['isVisible'] == true) {
            instructions = {
              'key': 'call_dutch',
              'title': demoInstructions['title'] ?? 'Call Dutch',
              'content': demoInstructions['paragraph'] ?? '',
              'hasDemonstration': false,
            };
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('📚 DemoActionHandler: call_dutch instructions not available');
            }
          return;
          }
          break;
        default:
          if (LOGGING_SWITCH) {
            _logger.warning('📚 DemoActionHandler: Unknown demo action type: $actionType');
          }
          return;
      }

      if (instructions == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('📚 DemoActionHandler: No instructions found for demo action: $actionType');
        }
        return;
      }

      // Get current dontShowAgain map and set all demo instructions to true (can't be dismissed)
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final instructionsData = currentState['instructions'] as Map<String, dynamic>? ?? {};
      final dontShowAgain = Map<String, bool>.from(
        instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );

      // Set this instruction's dontShowAgain to true (though checkbox is removed, this ensures consistency)
      final instructionKey = instructions['key']?.toString();
      if (instructionKey != null) {
        dontShowAgain[instructionKey] = true;
      }

      // Update state to show instructions
      StateManager().updateModuleState('dutch_game', {
        'instructions': {
          'isVisible': true,
          'title': instructions['title'] ?? 'Game Instructions',
          'content': instructions['content'] ?? '',
          'key': instructionKey ?? '',
          'hasDemonstration': instructions['hasDemonstration'] ?? false,
          'dontShowAgain': dontShowAgain,
        },
      });

      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoActionHandler: Instructions shown for demo action: $actionType'); } } catch (e, stackTrace) { if (LOGGING_SWITCH) {
          _logger.error('❌ DemoActionHandler: Error showing instructions for demo action $actionType: $e',  error: e, stackTrace: stackTrace);
        }
    }
  }
}

