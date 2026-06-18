import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../managers/dutch_event_handler_callbacks.dart';
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
import 'demo_mode_bridge.dart';
import '../../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';


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

  /// Both peek cards face-up in module state (required before initial_peek demo modal).
  static bool initialPeekCardsVisibleInState() {
    final dg =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final peek = dg['myCardsToPeek'] as List<dynamic>? ?? [];
    return peek.length >= 2 && DutchGameHelpers.peekListHasFullData(peek);
  }

  /// Re-run completion after [initial_peek_revealed] patches both cards into state.
  void retryDemoCompletionAfterPeekReveal() {
    _notifyStateChangedForDemoCompletion();
  }

  static Future<void> _waitForInitialPeekCardsVisible({
    int maxMs = 4000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
    while (DateTime.now().isBefore(deadline)) {
      if (initialPeekCardsVisibleInState()) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (LOGGING_SWITCH) {
      customlog(
        'demoCompletion: initial_peek wait timed out peek not fully visible',
      );
    }
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
      
      
      // Define the order of demos
      _sequentialDemoActions = [
        'initial_peek',
        'drawing',
        'playing',
        'same_rank',
        'queen_peek',
        'jack_swap',
        'collect_rank',
      ];
      
      // Initialize sequential demo mode
      _isSequentialDemoMode = true;
      _currentSequentialDemoIndex = 0;
      
      // Start the first demo
      final firstActionType = _sequentialDemoActions[_currentSequentialDemoIndex];
      
      
      await startDemoAction(firstActionType);
      
      } catch (e, stackTrace) { 
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
  ///                 'queen_peek', 'jack_swap', 'collect_rank'
  Future<void> startDemoAction(String actionType) async {
    try {
      
      
      // 1. Clear all state FIRST (before setting active demo action)
      // This ensures no leftover state from previous demos can interfere
      await _clearAllState();
      
      // 2. Reset ending flag in case it was left set
      _isEndingDemoAction = false;
      
      // 3. Reset collect_rank initial hand count
      _collectRankInitialHandCount = null;
      
      // 4. Set active demo action type AFTER clearing state
      _activeDemoActionType = actionType;

      DemoModeBridge.onInterceptHandled = _notifyStateChangedForDemoCompletion;
      DemoFunctionality.onDemoStateChanged = _notifyStateChangedForDemoCompletion;
      if (LOGGING_SWITCH) {
        customlog('demoCompletion: startDemoAction type=$actionType callbacks wired');
      }
      DemoModeBridge.configurePracticeIntercept(
        active: true,
        eventTypes: _interceptEventTypesForAction(actionType),
      );

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
      
      

      // 6. Advance game state to action-specific state
      final updatedGameState = await _stateSetup.setupActionState(
        actionType: actionType,
        gameId: practiceRoomId,
        gameState: gameState,
      );

      // 7. Sync state and trigger widget updates
      await _syncGameState(practiceRoomId, updatedGameState, actionType: actionType);
      
      // For collect_rank demo, set initial hand count after state is set up
      // This must happen BEFORE the user can collect, so we capture the baseline
      if (actionType == 'collect_rank') {
        _setInitialHandCountForCollectRank(updatedGameState);
      }

      // 8. Show instructions for this demo action
      _showDemoInstructions(actionType);

      // 9. Navigate to game play screen
      
      NavigationManager().navigateToPush('/dutch/game-play');

      } catch (e, stackTrace) { 
      rethrow;
    }
  }

  /// Clear all state before starting new demo
  /// This must be called BEFORE setting _activeDemoActionType to prevent false completion detection
  /// Uses the same comprehensive clearing logic as clearAllGameStateBeforeNewGame() to ensure
  /// complete cleanup when switching from any mode (practice, WebSocket, or another demo) to a demo
  Future<void> _clearAllState() async {
    try {
      

      // 1. Clear active demo action type FIRST to prevent completion detection
      // This must happen before calling clearAllGameStateBeforeNewGame() to prevent false detection
      _activeDemoActionType = null;
      DemoModeBridge.onInterceptHandled = null;
      DemoFunctionality.onDemoStateChanged = null;
      DemoModeBridge.configurePracticeIntercept(active: false);

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
      
      
    } catch (e, stackTrace) {
      
      // Don't rethrow - continue with demo setup
    }
  }

  /// Start practice match with showInstructions and test deck
  Future<String> _startPracticeMatch({
    required bool showInstructions,
    required bool isClearAndCollect,
  }) async {
    try {
      

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
        customlog(
          'LocalPlayerSeat: demoStart practiceUserId=$currentUserId '
          'expectedSeat=practice_session_$currentUserId roomId=$practiceRoomId',
        );
      }

      return practiceRoomId;
    } catch (e, stackTrace) {
      
      rethrow;
    }
  }

  /// Sync game state and trigger widget updates
  Future<void> _syncGameState(
    String gameId,
    Map<String, dynamic> gameState, {
    String? actionType,
  }) async {
    try {
      

      // Get current user ID
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final practiceUser = currentState['practiceUser'] as Map<String, dynamic>?;
      final practiceUserId = practiceUser?['userId']?.toString() ?? '';
      final seatId = practiceUserId.isNotEmpty
          ? 'practice_session_$practiceUserId'
          : '';

      // Extract and normalize phase
      final rawPhase = gameState['phase']?.toString();
      final uiPhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');

      // Extract game status
      final gameStatus = gameState['status']?.toString() ?? 'active';

      // Get current games map
      final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});

      final players = gameState['players'] as List<dynamic>? ?? [];
      Map<String, dynamic>? humanPlayer;
      for (final p in players) {
        if (p is Map<String, dynamic> && p['isHuman'] == true) {
          humanPlayer = p;
          break;
        }
      }
      if (humanPlayer == null && seatId.isNotEmpty) {
        for (final p in players) {
          if (p is Map<String, dynamic> && p['id']?.toString() == seatId) {
            humanPlayer = p;
            break;
          }
        }
      }

      final playerStatus = humanPlayer?['status']?.toString() ?? 'unknown';
      final myHandCards = humanPlayer?['hand'] as List<dynamic>? ?? [];
      final discardPile =
          gameState['discardPile'] as List<dynamic>? ?? [];

      // Build gameData structure
      final gameData = {
        'game_id': gameId,
        'owner_id': practiceUserId,
        'game_type': 'practice',
        'game_state': gameState,
        'max_size': 4,
        'min_players': 2,
      };

      // Add/update game in games map (widget slices read myHandCards / isMyTurn here)
      games[gameId] = {
        'gameData': gameData,
        'gameStatus': gameStatus,
        'isRoomOwner': true,
        'isInGame': true,
        'isMyTurn': humanPlayer?['isCurrentPlayer'] == true,
        'myHandCards': myHandCards,
        'myDrawnCard': humanPlayer?['drawnCard'],
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

      final demoInstructionsPhase = _demoInstructionsPhaseForAction(actionType);

      // Trigger slice recomputation
      DutchGameHelpers.updateUIState({
        'currentGameId': gameId,
        'games': games,
        'gamePhase': uiPhase,
        'currentPlayer': currentPlayer, // Set top-level currentPlayer for UnifiedGameBoardWidget
        'isMyTurn': humanPlayer?['isCurrentPlayer'] == true,
        'playerStatus': playerStatus,
        'currentPlayerStatus': playerStatus,
        'discardPile': discardPile,
        if (demoInstructionsPhase != null)
          'demoInstructionsPhase': demoInstructionsPhase,
      });

      // Small delay to allow slice recomputation
      await Future.delayed(const Duration(milliseconds: 50));

      // IMPORTANT: Do NOT set previousPlayerStatus during initial sync
      // It will be set on the first real state update from the backend
      // Setting it here could cause false completion detection if there's leftover state

      // Trigger game_state_updated event to sync widget slices
      
      DutchEventManager().handleGameStateUpdated({
        'game_id': gameId,
        'game_state': gameState,
        'owner_id': practiceUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (actionType == 'initial_peek') {
        final dg =
            StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ??
                {};
        final prev = dg['previousPlayerStatus']?.toString();
        if (prev == null || prev.isEmpty) {
          StateManager().updateModuleState('dutch_game', {
            'previousPlayerStatus': 'initial_peek',
          });
          if (LOGGING_SWITCH) {
            customlog('demoCompletion: seeded previousPlayerStatus=initial_peek');
          }
        }
      }

      } catch (e, stackTrace) {
      rethrow;
    }
  }

  Set<String> _interceptEventTypesForAction(String actionType) {
    switch (actionType) {
      case 'queen_peek':
        return const {'queen_peek'};
      case 'jack_swap':
        return const {'jack_swap'};
      default:
        return const {};
    }
  }

  void _notifyStateChangedForDemoCompletion() {
    if (!isDemoActionActive()) {
      if (LOGGING_SWITCH) {
        customlog('demoCompletion: skip no active demo action');
      }
      return;
    }
    final activeDemoAction = getActiveDemoActionType();
    if (activeDemoAction == null) {
      if (LOGGING_SWITCH) {
        customlog('demoCompletion: skip activeDemoActionType null');
      }
      return;
    }

    final dutchGameState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    var previousPlayerStatus =
        dutchGameState['previousPlayerStatus']?.toString();

    Map<String, dynamic>? gameState;
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    if (currentGameId.isNotEmpty) {
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final game = games[currentGameId] as Map<String, dynamic>?;
      gameState = game?['gameData']?['game_state'] as Map<String, dynamic>?;
    }

    // Prefer SSOT roster status (matches [_checkDemoActionCompletion] on game_state_updated)
    var currentUserPlayerStatus =
        dutchGameState['playerStatus']?.toString();
    if (gameState != null) {
      final myPlayer = DutchEventHandlerCallbacks.findLocalPlayerInRoster(
        gameState['players'] as List? ?? [],
      );
      final ssotStatus = myPlayer?['status']?.toString();
      if (ssotStatus != null && ssotStatus.isNotEmpty) {
        currentUserPlayerStatus = ssotStatus;
      }
    }

    // Baseline for initial_peek when sync missed setting previousPlayerStatus
    if (activeDemoAction == 'initial_peek' &&
        (previousPlayerStatus == null || previousPlayerStatus.isEmpty) &&
        currentUserPlayerStatus == 'waiting') {
      previousPlayerStatus = 'initial_peek';
    }

    var completed = isActionCompleted(
      activeDemoAction,
      previousPlayerStatus,
      currentUserPlayerStatus,
      gameState: gameState,
    );

    if (completed &&
        activeDemoAction == 'initial_peek' &&
        !initialPeekCardsVisibleInState()) {
      if (LOGGING_SWITCH) {
        customlog(
          'demoCompletion: defer modal action=initial_peek '
          'waiting for both peek cards in state',
        );
      }
      completed = false;
    }

    if (LOGGING_SWITCH) {
      customlog(
        'demoCompletion: notify action=$activeDemoAction '
        'prev=$previousPlayerStatus current=$currentUserPlayerStatus '
        'completed=$completed gameId=$currentGameId '
        'peekLen=${(dutchGameState['myCardsToPeek'] as List?)?.length ?? 0}',
      );
    }

    if (completed) {
      StateManager().updateModuleState('dutch_game', {
        'previousPlayerStatus': null,
      });
      showAfterActionInstruction(activeDemoAction);
    } else if (currentUserPlayerStatus != null) {
      StateManager().updateModuleState('dutch_game', {
        'previousPlayerStatus': currentUserPlayerStatus,
      });
    }
  }

  String? _demoInstructionsPhaseForAction(String? actionType) {
    switch (actionType) {
      case 'initial_peek':
        return 'initial_peek';
      case 'drawing':
        return 'drawing';
      case 'playing':
        return 'playing';
      case 'same_rank':
        return 'same_rank';
      case 'queen_peek':
        return 'queen_peek';
      case 'jack_swap':
        return 'jack_swap';
      default:
        return null;
    }
  }

  /// End a demo action and navigate back to demo screen
  /// 
  /// [actionType] - The demo action type that was completed
  Future<void> endDemoAction(String actionType) async {
    // Prevent multiple calls to endDemoAction
    if (_isEndingDemoAction) {
      
      return;
    }
    
    _isEndingDemoAction = true;
    
    try {
      
      
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
        
        
        
        // Wait a bit before starting next demo
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Start the next demo
        await startDemoAction(nextActionType);
        
        
      } else {
        // End of sequence or not in sequential mode - navigate back to demo screen
        if (_isSequentialDemoMode) {
          
          _isSequentialDemoMode = false;
          _currentSequentialDemoIndex = 0;
          _sequentialDemoActions = [];
        }
      
      // 5. Navigate back to demo screen (non-sequential mode)
      
      NavigationManager().navigateTo('/dutch/demo');
      
      // 6. NOW clear active demo action type AFTER navigation
      // This ensures instructions won't show during or after the demo action ends
      _activeDemoActionType = null;
      DemoModeBridge.onInterceptHandled = null;
      DemoFunctionality.onDemoStateChanged = null;
      DemoModeBridge.configurePracticeIntercept(active: false);
      
      
      }
    } catch (e, stackTrace) {
      
      // Clear active demo action type even on error
      _activeDemoActionType = null;
      DemoModeBridge.onInterceptHandled = null;
      DemoFunctionality.onDemoStateChanged = null;
      DemoModeBridge.configurePracticeIntercept(active: false);
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
        // Complete after peek reveal timer (peeking -> playing_card)
        return previousStatus == 'peeking' && currentStatus == 'playing_card';
      
      case 'jack_swap':
        // Jack swap completes when status changes from jack_swap to waiting or playing_card
        return previousStatus == 'jack_swap' && 
               (currentStatus == 'waiting' || currentStatus == 'playing_card');
      
      case 'collect_rank':
        // Collect rank completes when a collection card is added to the hand
        // Check if hand count has increased (indicating a card was collected)
        if (gameState != null) {
          try {
            // CRITICAL: If initial hand count hasn't been set yet, don't check for completion
            // This prevents false positives during initial state setup
            if (_collectRankInitialHandCount == null) {
              
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
              
              return false;
            }
            
            
            
            // Get players from game state
            final players = gameState['players'] as List<dynamic>? ?? [];
            
            
            // Find the current user's player
            Map<String, dynamic>? currentPlayer;
            for (final player in players) {
              if (player is Map<String, dynamic>) {
                final playerId = player['id']?.toString() ?? '';
                
                if (playerId == currentUserId) {
                  currentPlayer = player;
                  
                  break;
                }
              }
            }
            
            if (currentPlayer == null) {
              
              return false;
            }
            
            // Get hand from player
            final hand = currentPlayer['hand'] as List<dynamic>? ?? [];
            final currentHandCount = hand.length;
            
            
            // Check if hand count has increased (card was collected)
            if (currentHandCount > _collectRankInitialHandCount!) {
              
              return true;
            }
          } catch (e, stackTrace) {
            
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
            
            return;
          }
        }
      }
      
      
    } catch (e) {
      
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
        customlog('demoCompletion: showAfterActionInstruction start action=$actionType');
      }

      if (actionType == 'initial_peek') {
        await _waitForInitialPeekCardsVisible();
        await Future.delayed(const Duration(milliseconds: 1500));
      } else {
        // Wait before showing instruction
        await Future.delayed(const Duration(seconds: 2));
      }
      
      // Get instruction content for this action
      final instruction = _getAfterActionInstruction(actionType);
      
      // Create callback that will execute endDemoAction when instruction is closed
      void onCloseCallback() {
        
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
        customlog(
          'demoCompletion: instructions visible key=demo_after_$actionType '
          'title=${instruction['title']}',
        );
      }
      
      } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        customlog('demoCompletion: showAfterActionInstruction error $e');
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
        default:
          
          return;
      }

      if (instructions == null) {
        
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

      } catch (e, stackTrace) { 
    }
  }
}

