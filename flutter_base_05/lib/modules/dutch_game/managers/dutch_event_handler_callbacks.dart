import 'package:dutch/tools/logging/logger.dart';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/module_manager.dart';
import '../../dutch_game/utils/dutch_game_helpers.dart';
import '../utils/game_instructions_provider.dart';
import '../../../modules/analytics_module/analytics_module.dart';
import '../screens/demo/demo_action_handler.dart';

/// Dedicated event handlers for Dutch game events
/// Contains all the business logic for processing specific event types
class DutchEventHandlerCallbacks {
  static const bool LOGGING_SWITCH = false; // Enabled for initial peek clearing debugging
  static final Logger _logger = Logger();
  
  // Analytics module cache
  static AnalyticsModule? _analyticsModule;

  // ========================================
  // HELPER METHODS TO REDUCE DUPLICATION
  // ========================================
  
  /// Get analytics module instance
  static AnalyticsModule? _getAnalyticsModule() {
    if (_analyticsModule == null) {
      try {
        final moduleManager = ModuleManager();
        _analyticsModule = moduleManager.getModuleByType<AnalyticsModule>();
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.error('Error getting analytics module: $e');
        }
      }
    }
    return _analyticsModule;
  }
  
  /// Track game event
  static Future<void> _trackGameEvent(String eventType, Map<String, dynamic> eventData) async {
    try {
      final analyticsModule = _getAnalyticsModule();
      if (analyticsModule != null) {
        await analyticsModule.trackEvent(
          eventType: eventType,
          eventData: eventData,
        );
      }
    } catch (e) {
      // Silently fail - don't block game events if analytics fails
      if (LOGGING_SWITCH) {
        _logger.error('Error tracking game event: $e');
      }
    }
  }
  
  /// Get current games map from state manager
  static Map<String, dynamic> _getCurrentGamesMap() {
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  }
  
  /// Update a specific game in the games map and sync to global state
  static void _updateGameInMap(String gameId, Map<String, dynamic> updates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // CRITICAL: Preserve gameData if updates don't include it
      // This prevents gameData from being lost or overwritten with empty/null values
      final mergedGame = {
        ...currentGame,
        ...updates,
      };
      
      // CRITICAL: If updates don't include gameData, preserve the existing one
      if (!updates.containsKey('gameData')) {
        mergedGame['gameData'] = currentGameData;
      } else {
        // If updates includes gameData, ensure it has game_id set
        final updatedGameData = updates['gameData'] as Map<String, dynamic>? ?? {};
        if (updatedGameData.isNotEmpty && (updatedGameData['game_id'] == null || updatedGameData['game_id'].toString().isEmpty)) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️  _updateGameInMap: Updated gameData missing game_id for game $gameId - setting it');
          }
          updatedGameData['game_id'] = gameId;
          mergedGame['gameData'] = updatedGameData;
        }
      }
      
      // CRITICAL: Validate that gameData still has game_id after merge
      final finalGameData = mergedGame['gameData'] as Map<String, dynamic>? ?? {};
      if (finalGameData.isEmpty || finalGameData['game_id'] == null || finalGameData['game_id'].toString().isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ _updateGameInMap: Game $gameId has invalid gameData after update - gameData empty: ${finalGameData.isEmpty}, game_id: ${finalGameData['game_id']}');
        }
        // Don't update if gameData is invalid - this prevents corrupting the games map
        return;
      }
      
      currentGames[gameId] = mergedGame;
      
      // Update global state
      DutchGameHelpers.updateUIState({
        'games': currentGames,
      });
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  _updateGameInMap: Game $gameId not found in games map - cannot update');
      }
    }
  }
  
  /// Update game data within a game's gameData structure
  static void _updateGameData(String gameId, Map<String, dynamic> dataUpdates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // Update the game data
      final updatedGameData = Map<String, dynamic>.from(currentGameData);
      updatedGameData.addAll(dataUpdates);
      
      // Update the game with new game data
      _updateGameInMap(gameId, {
        'gameData': updatedGameData,
      });
    }
  }
  
  /// Get current user ID from practice user data or login state
  /// Practice mode stores user data in dutch_game state, multiplayer uses login state
  /// In multiplayer mode, returns sessionId (which is the player ID), not userId
  static String getCurrentUserId() {
    // First check for practice user data (practice mode)
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final practiceUser = dutchGameState['practiceUser'] as Map<String, dynamic>?;
    if (LOGGING_SWITCH) {
      _logger.debug('🔍 getCurrentUserId: Checking practiceUser: $practiceUser');
    }
    if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
      final practiceUserId = practiceUser['userId']?.toString();
      if (practiceUserId != null && practiceUserId.isNotEmpty) {
        // In practice mode, player ID is the sessionId, not the userId
        // SessionId format: practice_session_<userId>
        final practiceSessionId = 'practice_session_$practiceUserId';
        if (LOGGING_SWITCH) {
          _logger.debug('🔍 getCurrentUserId: Returning practice session ID: $practiceSessionId');
        }
        return practiceSessionId;
      }
    }
    
    // Fall back to login state (multiplayer mode)
    // In multiplayer, try to get sessionId from websocket state first
    // Check both camelCase and snake_case keys for compatibility
    final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final sessionData = websocketState['sessionData'] as Map<String, dynamic>?;
    final sessionId = sessionData?['session_id']?.toString() ?? 
                      sessionData?['sessionId']?.toString();
    if (LOGGING_SWITCH) {
      _logger.debug('🔍 getCurrentUserId: Checking sessionId from websocket state (sessionData keys: ${sessionData?.keys.toList()}): $sessionId');
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.debug('🔍 getCurrentUserId: Found sessionId in state: $sessionId');
      }
      return sessionId;
    }
    
    // Try to get sessionId directly from WebSocketManager socket
    try {
      final wsManager = WebSocketManager.instance;
      final directSessionId = wsManager.socket?.id;
      if (LOGGING_SWITCH) {
        _logger.debug('🔍 getCurrentUserId: Checking direct socket ID: $directSessionId');
      }
      if (directSessionId != null && directSessionId.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.debug('🔍 getCurrentUserId: Using direct socket ID: $directSessionId');
        }
        return directSessionId;
      }
    } catch (e) {
      // WebSocketManager might not be initialized, continue to fallback
      if (LOGGING_SWITCH) {
        _logger.debug('🔍 getCurrentUserId: WebSocketManager not available: $e');
      }
    }
    
    // Last resort: use login userId (for backward compatibility)
    // Note: This may not match player IDs in multiplayer mode where player.id = sessionId
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final loginUserId = loginState['userId']?.toString() ?? '';
    if (LOGGING_SWITCH) {
      _logger.warning('⚠️  getCurrentUserId: Falling back to login user ID (this may cause issues in multiplayer): $loginUserId');
    }
    return loginUserId;
  }
  
  /// Check if current user is room owner for a specific game
  static bool _isCurrentUserRoomOwner(Map<String, dynamic> gameData) {
    final ownerId = gameData['owner_id']?.toString();
    if (ownerId == null || ownerId.isEmpty) {
      return false;
    }
    
    // Get current user ID (this returns sessionId in practice mode, sessionId in multiplayer)
    final currentUserId = getCurrentUserId();
    
    // Direct match (works for multiplayer where owner_id is sessionId)
    if (ownerId == currentUserId) {
      return true;
    }
    
    // In practice mode, owner_id is userId but currentUserId is sessionId
    // Check if currentUserId is a practice sessionId and extract userId for comparison
    if (currentUserId.startsWith('practice_session_')) {
      final extractedUserId = currentUserId.replaceFirst('practice_session_', '');
      if (ownerId == extractedUserId) {
        if (LOGGING_SWITCH) {
          _logger.debug('🔍 _isCurrentUserRoomOwner: Practice mode match - ownerId: $ownerId, extractedUserId: $extractedUserId');
        }
        return true;
      }
    }
    
    // Also check if ownerId is a practice sessionId and currentUserId is the userId
    if (ownerId.startsWith('practice_session_')) {
      final extractedOwnerUserId = ownerId.replaceFirst('practice_session_', '');
      // Check if currentUserId matches the extracted userId
      // This handles the case where owner_id might be set to sessionId
      if (currentUserId == extractedOwnerUserId || currentUserId == ownerId) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Add a game to the games map with standard structure
  static void _addGameToMap(String gameId, Map<String, dynamic> gameData, {String? gameStatus}) {
    final currentGames = _getCurrentGamesMap();
    
    // CRITICAL: Validate gameData has required fields before adding
    if (gameData.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  _addGameToMap: Attempted to add game $gameId with empty gameData - skipping');
      }
      return;
    }
    
    // CRITICAL: Ensure game_id is set in gameData (required for joinedGamesSlice computation)
    if (gameData['game_id'] == null || gameData['game_id'].toString().isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  _addGameToMap: gameData missing game_id for game $gameId - setting it');
      }
      gameData['game_id'] = gameId; // Ensure game_id is set
    }
    
    // Determine game status (phase is now managed in main state only)
    final status = gameStatus ?? gameData['game_state']?['status']?.toString() ?? 'inactive';
    
    // Preserve existing joinedAt timestamp if game already exists
    final existingGame = currentGames[gameId] as Map<String, dynamic>?;
    final joinedAt = existingGame?['joinedAt'] ?? DateTime.now().toIso8601String();
    
    // Add/update the game in the games map
    currentGames[gameId] = {
      'gameData': gameData,  // Single source of truth
      // Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice
      'gameStatus': status,
      'isRoomOwner': _isCurrentUserRoomOwner(gameData),
      'isInGame': true,
      'joinedAt': joinedAt,  // Preserve original joinedAt timestamp
      // Removed lastUpdated - causes unnecessary state updates
    };
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ _addGameToMap: Added game $gameId with gameData.game_id=${gameData['game_id']}');
    }
    
    // Update global state
    DutchGameHelpers.updateUIState({
      'games': currentGames,
    });
  }
  
  /// Update main game state (non-game-specific fields)
  static void _updateMainGameState(Map<String, dynamic> updates) {
    DutchGameHelpers.updateUIState(updates);
    // Removed lastUpdated - causes unnecessary state updates
  }

  /// Trigger instructions if showInstructions is enabled and state has changed
  /// 
  /// Checks if instructions should be shown based on game phase and player status,
  /// and updates the instructions state accordingly.
  static void _triggerInstructionsIfNeeded({
    required String gameId,
    required Map<String, dynamic> gameState,
    String? playerStatus,
    bool isMyTurn = false,
  }) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📚 _triggerInstructionsIfNeeded: Called for gameId=$gameId, phase=${gameState['phase']}');
      }
      
      // Skip automatic instruction triggering if a demo action is active
      // Demo logic will handle showing instructions manually
      if (DemoActionHandler.isDemoActionActive()) {
        if (LOGGING_SWITCH) {
          _logger.info('📚 _triggerInstructionsIfNeeded: Demo action active, skipping automatic instruction triggering');
        }
        return;
      }
      
      // Get showInstructions flag from game state
      final showInstructions = gameState['showInstructions'] as bool? ?? false;
      if (LOGGING_SWITCH) {
        _logger.info('📚 _triggerInstructionsIfNeeded: showInstructions from gameState=$showInstructions');
      }
      
      if (!showInstructions) {
        // Instructions disabled, ensure they're hidden
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
        if (currentInstructions['isVisible'] == true) {
          // Hide instructions if they were previously visible
          StateManager().updateModuleState('dutch_game', {
            'instructions': {
              'isVisible': false,
              'title': '',
              'content': '',
              'key': '',
              'dontShowAgain': currentInstructions['dontShowAgain'] ?? {},
            },
          });
        }
        return;
      }

      // Get current game phase
      final rawPhase = gameState['phase']?.toString();
      final gamePhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');

      // Check if game hasn't started yet (waiting phase) - show initial instructions
      // Also check practice settings if showInstructions is not in game state yet
      if (gamePhase == 'waiting') {
        // If showInstructions is not in game state, check practice settings
        bool effectiveShowInstructions = showInstructions;
        if (!showInstructions) {
          final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final practiceSettings = currentState['practiceSettings'] as Map<String, dynamic>?;
          final practiceShowInstructions = practiceSettings?['showInstructions'] as bool? ?? false;
          if (practiceShowInstructions) {
            if (LOGGING_SWITCH) {
              _logger.info('📚 _triggerInstructionsIfNeeded: Using showInstructions from practiceSettings=$practiceShowInstructions');
            }
            effectiveShowInstructions = true;
          }
        }
        if (LOGGING_SWITCH) {
          _logger.info('📚 _triggerInstructionsIfNeeded: In waiting phase, showInstructions=$showInstructions, effectiveShowInstructions=$effectiveShowInstructions');
        }
        
        if (!effectiveShowInstructions) {
          if (LOGGING_SWITCH) {
            _logger.info('📚 _triggerInstructionsIfNeeded: Instructions disabled, skipping');
          }
          return;
        }
        
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final instructionsData = currentState['instructions'] as Map<String, dynamic>? ?? {};
        final dontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        if (LOGGING_SWITCH) {
          _logger.info('📚 _triggerInstructionsIfNeeded: dontShowAgain[initial]=${dontShowAgain[GameInstructionsProvider.KEY_INITIAL]}');
        }
        
        // Show initial instructions if not already marked as "don't show again"
        if (dontShowAgain[GameInstructionsProvider.KEY_INITIAL] != true) {
          // Check if initial instructions are already showing
          final instructionsData = currentState['instructions'] as Map<String, dynamic>? ?? {};
          final currentlyVisible = instructionsData['isVisible'] == true;
          final currentKey = instructionsData['key']?.toString();
          
          // Only show if not already showing
          if (!currentlyVisible || currentKey != GameInstructionsProvider.KEY_INITIAL) {
            final initialInstructions = GameInstructionsProvider.getInitialInstructions();
            StateManager().updateModuleState('dutch_game', {
              'instructions': {
                'isVisible': true,
                'title': initialInstructions['title'] ?? 'Welcome to Dutch!',
                'content': initialInstructions['content'] ?? '',
                'key': initialInstructions['key'] ?? GameInstructionsProvider.KEY_INITIAL,
                'hasDemonstration': initialInstructions['hasDemonstration'] ?? false,
                'dontShowAgain': dontShowAgain,
              },
            });
            if (LOGGING_SWITCH) {
              _logger.info('📚 Initial instructions triggered and state updated');
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('📚 Initial instructions skipped - already showing');
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('📚 Initial instructions skipped - already marked as dontShowAgain');
          }
        }
        return;
      }

      // Get current user's player status (not the current player's status)
      // We need the current user's status to show instructions for their actions
      String? currentUserPlayerStatus = playerStatus;
      if (currentUserPlayerStatus == null) {
        // Get from current user's player in game state
        final players = gameState['players'] as List<dynamic>? ?? [];
        final currentUserId = getCurrentUserId();
        try {
          final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
            (player) => player['id'] == currentUserId,
          );
          currentUserPlayerStatus = myPlayer['status']?.toString();
          if (LOGGING_SWITCH) {
            _logger.info('📚 _triggerInstructionsIfNeeded: Found current user player status=$currentUserPlayerStatus');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('📚 _triggerInstructionsIfNeeded: Current user player not found in players list');
          }
          // Player not found, continue without status
        }
      }

      // Get previous instructions state to check if we should show new instructions
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final previousPhase = currentState['gamePhase']?.toString();
      
      // Get previous current user's player status (from myHand slice or playerStatus in main state)
      // Note: currentPlayerStatus in main state is the current player's status, not current user's
      final myHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      final previousUserPlayerStatus = myHand['playerStatus']?.toString() ?? 
                                       currentState['playerStatus']?.toString();
      
      final dontShowAgain = Map<String, bool>.from(
        (currentState['instructions'] as Map<String, dynamic>?)?['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );

      // Track same rank window triggers for collection card instruction
      int sameRankTriggerCount = currentState['sameRankTriggerCount'] as int? ?? 0;
      if (LOGGING_SWITCH) {
        _logger.info('📚 _triggerInstructionsIfNeeded: Current sameRankTriggerCount=$sameRankTriggerCount, gamePhase=$gamePhase, previousPhase=$previousPhase');
      }
      
      // Check if this is a same rank window phase
      if (gamePhase == 'same_rank_window') {
        // Increment counter ONLY when transitioning INTO same_rank_window (not when already in it)
        // This happens when previousPhase was NOT same_rank_window
        if (previousPhase != 'same_rank_window') {
          sameRankTriggerCount++;
          StateManager().updateModuleState('dutch_game', {
            'sameRankTriggerCount': sameRankTriggerCount,
          });
          if (LOGGING_SWITCH) {
            _logger.info('📚 _triggerInstructionsIfNeeded: Incremented same rank window trigger count=$sameRankTriggerCount (transitioned from $previousPhase to same_rank_window)');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('📚 _triggerInstructionsIfNeeded: Already in same_rank_window phase, not incrementing counter');
          }
        }
        
        // On 5th trigger, show collection card instruction instead of same rank window
        if (sameRankTriggerCount >= 5) {
          if (LOGGING_SWITCH) {
            _logger.info('📚 _triggerInstructionsIfNeeded: Same rank trigger count >= 5, checking collection card instruction');
          }
          // Check if collection card instruction is already dismissed
          if (dontShowAgain[GameInstructionsProvider.KEY_COLLECTION_CARD] != true) {
            if (LOGGING_SWITCH) {
              _logger.info('📚 _triggerInstructionsIfNeeded: Collection card instruction not dismissed, constructing instruction');
            }
            
            // Construct collection card instruction directly (no playerStatus 'collection_card' exists)
            final collectionInstructions = {
              'key': GameInstructionsProvider.KEY_COLLECTION_CARD,
              'title': 'Collection Cards',
              'hasDemonstration': true,
              'content': '''📚 **Collection Cards**

When anyone has played a card with the **same rank** as your **collection card** (the face-up card in your hand), you can collect it!

**How it works:**
• Your collection card is the face-up card in your hand
• If the last played card matches your collection card's rank, you can collect it
• The collected card is placed on top of your collection card (slightly offset to show stacking)
• Collected cards help you build your collection in attempt to collect all 4 cards of your rank and win the game.

**Example:** If your collection card is a 7 of Hearts and a 7 of Diamonds has just played, you can collect it!''',
            };
            
            final instructionKey = collectionInstructions['key'] ?? '';
            final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
            final currentlyVisible = currentInstructions['isVisible'] == true;
            final currentKey = currentInstructions['key']?.toString();
            
            if (LOGGING_SWITCH) {
              _logger.info('📚 _triggerInstructionsIfNeeded: Collection instruction key=$instructionKey, currentlyVisible=$currentlyVisible, currentKey=$currentKey');
            }
            
            // Only update if not already showing this instruction
            if (!currentlyVisible || currentKey != instructionKey) {
              StateManager().updateModuleState('dutch_game', {
                'instructions': {
                  'isVisible': true,
                  'title': collectionInstructions['title'] ?? 'Collection Cards',
                  'content': collectionInstructions['content'] ?? '',
                  'key': instructionKey,
                  'hasDemonstration': collectionInstructions['hasDemonstration'] ?? false,
                  'dontShowAgain': dontShowAgain,
                },
              });
              if (LOGGING_SWITCH) {
                _logger.info('📚 Collection card instruction triggered (5th same rank window, count=$sameRankTriggerCount)');
              }
              return; // Exit early, don't show same rank window instruction
            } else {
              if (LOGGING_SWITCH) {
                _logger.info('📚 Collection card instruction skipped - already showing');
              }
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('📚 Collection card instruction already dismissed, showing same rank window instead');
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('📚 Same rank trigger count ($sameRankTriggerCount) < 5, showing same rank window instruction');
          }
        }
      }

      if (LOGGING_SWITCH) {
        _logger.info('📚 _triggerInstructionsIfNeeded: Current user status=$currentUserPlayerStatus, previous=$previousUserPlayerStatus, isMyTurn=$isMyTurn');
      }

      // Check if instructions should be shown
      final shouldShow = GameInstructionsProvider.shouldShowInstructions(
        showInstructions: showInstructions,
        gamePhase: gamePhase,
        playerStatus: currentUserPlayerStatus,
        isMyTurn: isMyTurn,
        previousPhase: previousPhase,
        previousStatus: previousUserPlayerStatus,
        dontShowAgain: dontShowAgain,
      );
      
      if (LOGGING_SWITCH) {
        _logger.info('📚 _triggerInstructionsIfNeeded: shouldShow=$shouldShow for status=$currentUserPlayerStatus');
      }

      if (shouldShow) {
        // Get instructions content
        final instructions = GameInstructionsProvider.getInstructions(
          gamePhase: gamePhase,
          playerStatus: currentUserPlayerStatus,
          isMyTurn: isMyTurn,
        );

        if (instructions != null) {
          final instructionKey = instructions['key'] ?? '';
          
          // Check if this instruction is already showing
          final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
          final currentlyVisible = currentInstructions['isVisible'] == true;
          final currentKey = currentInstructions['key']?.toString();
          
          // Only update if:
          // 1. No instruction is currently showing, OR
          // 2. The instruction key has changed (different instruction type)
          if (!currentlyVisible || currentKey != instructionKey) {
            // Update instructions state
            StateManager().updateModuleState('dutch_game', {
              'instructions': {
                'isVisible': true,
                'title': instructions['title'] ?? 'Game Instructions',
                'content': instructions['content'] ?? '',
                'key': instructionKey,
                'hasDemonstration': instructions['hasDemonstration'] ?? false,
                'dontShowAgain': dontShowAgain,
              },
            });
            
            if (LOGGING_SWITCH) {
              _logger.info('📚 Instructions triggered: phase=$gamePhase, status=$currentUserPlayerStatus, isMyTurn=$isMyTurn, key=$instructionKey');
            }
          } else {
            _logger.info('📚 Instructions skipped: same instruction already showing (key=$instructionKey)', isOn: LOGGING_SWITCH);
          }
        }
      } else {
        // Don't show instructions, but don't hide if they're already showing
        // (let user close them manually)
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error triggering instructions: $e');
      }
    }
  }

  /// Check if demo action has completed and trigger endDemoAction if needed
  /// 
  /// Checks if:
  /// - Game is a practice game
  /// - showInstructions is enabled
  /// - A demo action is currently active
  /// - Player status has transitioned to indicate action completion
  static void _checkDemoActionCompletion({
    required String gameId,
    required Map<String, dynamic> gameState,
    required String? currentUserPlayerStatus,
  }) {
    try {
      // Get current state once
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      
      // Check if practice game
      final gameType = dutchGameState['gameType']?.toString() ?? '';
      if (gameType != 'practice') {
        return; // Not a practice game, skip demo check
      }

      // Check if showInstructions is enabled
      bool showInstructions = gameState['showInstructions'] as bool? ?? false;
      if (!showInstructions) {
        // Fallback to practice settings
        final practiceSettings = dutchGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool? ?? false;
      }

      if (!showInstructions) {
        return; // Instructions not enabled, skip demo check
      }

      // Check if demo action is active
      if (!DemoActionHandler.isDemoActionActive()) {
        return; // No active demo action
      }

      final activeDemoAction = DemoActionHandler.getActiveDemoActionType();
      if (activeDemoAction == null) {
        return; // No active demo action type
      }

      // Get previous player status from state
      final previousPlayerStatus = dutchGameState['previousPlayerStatus']?.toString();

      // Check if action is completed based on status transition (pass gameState for collect_rank demo)
      final demoHandler = DemoActionHandler.instance;
      final isCompleted = demoHandler.isActionCompleted(
        activeDemoAction,
        previousPlayerStatus,
        currentUserPlayerStatus,
        gameState: gameState,
      );

      if (isCompleted) {
        _logger.info('🎮 _checkDemoActionCompletion: Demo action $activeDemoAction completed (status: $previousPlayerStatus → $currentUserPlayerStatus)', isOn: LOGGING_SWITCH);
        
        // Clear previous status
        StateManager().updateModuleState('dutch_game', {
          'previousPlayerStatus': null,
        });

        // Show after-action instruction for all demo actions
        if (LOGGING_SWITCH) {
          _logger.info('🎮 _checkDemoActionCompletion: Demo action completed - showing after-action instruction');
        }
        demoHandler.showAfterActionInstruction(activeDemoAction);
      } else {
        // Update previous status for next check
        if (currentUserPlayerStatus != null) {
          StateManager().updateModuleState('dutch_game', {
            'previousPlayerStatus': currentUserPlayerStatus,
          });
        }
      }
    } catch (e) {
      _logger.error('Error checking demo action completion: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Sync widget-specific states from game state
  /// Extracts current user's player data and updates widget state slices
  /// This ensures computed slices (like myHand.cards) stay in sync with game_state
  /// [turnEvents] Optional turn_events list to include in games map update for widget slices
  static void _syncWidgetStatesFromGameState(String gameId, Map<String, dynamic> gameState, {List<dynamic>? turnEvents}) {
    try {
      // 🎯 CRITICAL: Verify game exists in games map before updating
      // This prevents stale state updates when user has left the game
      final currentGames = _getCurrentGamesMap();
      if (!currentGames.containsKey(gameId)) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️  _syncWidgetStatesFromGameState: Game $gameId not found in games map - user may have left. Skipping widget state sync.');
        }
        return;
      }
      
      // Get current user ID (checks practice user data first, then login state)
      // In multiplayer mode, this should return sessionId (which is the player ID)
      final currentUserId = getCurrentUserId();
      
      if (LOGGING_SWITCH) {
        _logger.info('🔍 _syncWidgetStatesFromGameState: gameId=$gameId, currentUserId=$currentUserId');
      }
      
      if (currentUserId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️  _syncWidgetStatesFromGameState: No current user ID found');
        }
        return;
      }
      
      // Find player in gameState['players'] matching current user ID
      final players = gameState['players'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 _syncWidgetStatesFromGameState: Found ${players.length} players');
      }
      _logger.info('🔍 _syncWidgetStatesFromGameState: Player IDs: ${players.map((p) => p is Map ? p['id']?.toString() : 'unknown').join(', ')}', isOn: LOGGING_SWITCH);
      
      Map<String, dynamic>? myPlayer;
      
      try {
        myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
          (player) => player['id']?.toString() == currentUserId,
        );
        if (LOGGING_SWITCH) {
          _logger.info('✅ _syncWidgetStatesFromGameState: Found matching player with ID: ${myPlayer['id']}');
        }
      } catch (e) {
        _logger.warning('⚠️  _syncWidgetStatesFromGameState: Current user ($currentUserId) not found in players list. Player IDs: ${players.map((p) => p is Map ? p['id']?.toString() : 'unknown').join(', ')}', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Extract widget-specific data from player
      final hand = myPlayer['hand'] as List<dynamic>? ?? [];
      final cardsToPeek = myPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      final drawnCard = myPlayer['drawnCard'] as Map<String, dynamic>?;
      
      // Check if cardsToPeek contains full card data (for protection mechanism)
      final hasFullCardData = cardsToPeek.isNotEmpty && cardsToPeek.any((card) {
        if (card is Map<String, dynamic>) {
          final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
          final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
          return hasSuit || hasRank;
        }
        return false;
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('🔍 _syncWidgetStatesFromGameState: cardsToPeek.length: ${cardsToPeek.length}, hasFullCardData: $hasFullCardData');
      }
      if (cardsToPeek.isNotEmpty && hasFullCardData) {
        if (LOGGING_SWITCH) {
          _logger.info('🔍 _syncWidgetStatesFromGameState: Full card data detected - storing in protectedCardsToPeek');
        }
        // Store protected data in main state so widgets can access it
        // This persists even when cardsToPeek is cleared
        // Use widget-level timer instead of timestamp in state
        _updateMainGameState({
          'protectedCardsToPeek': cardsToPeek, // Store protected data
          // Removed protectedCardsToPeekTimestamp - widget will use internal timer
        });
      } else if (cardsToPeek.isEmpty) {
        // CRITICAL: Clear protectedCardsToPeek when cardsToPeek is empty
        // This ensures the widget doesn't show stale protected data
        if (LOGGING_SWITCH) {
          _logger.info('🔍 _syncWidgetStatesFromGameState: cardsToPeek is empty - clearing protectedCardsToPeek');
        }
        _updateMainGameState({
          'protectedCardsToPeek': null, // Clear protected data
        });
      }
      
      // Extract score (can be 'points' or 'score' field)
      final score = myPlayer['score'] as int? ?? myPlayer['points'] as int? ?? 0;
      
      // Extract status
      final status = myPlayer['status']?.toString() ?? 'unknown';
      
      // Determine if it's current player's turn
      // Check both gameState['currentPlayer'] and player['isCurrentPlayer']
      final currentPlayerRaw = gameState['currentPlayer'];
      bool isCurrentPlayer = false;
      if (currentPlayerRaw is Map<String, dynamic>) {
        isCurrentPlayer = currentPlayerRaw['id']?.toString() == currentUserId;
      } else if (currentPlayerRaw is String) {
        isCurrentPlayer = currentPlayerRaw == currentUserId;
      } else {
        isCurrentPlayer = myPlayer['isCurrentPlayer'] == true;
      }
      
      // Update games map with widget-specific data
      // Include turn_events if provided (needed for widget slice animations)
      final widgetUpdates = <String, dynamic>{
        'myHandCards': hand,
        'myDrawnCard': drawnCard,
        'isMyTurn': isCurrentPlayer,
      };
      
      // Include turn_events in games map update so widget slices can access them
      if (turnEvents != null) {
        widgetUpdates['turn_events'] = turnEvents;
      }
      
      // Update main game state with player information
      _updateMainGameState({
        'playerStatus': status,
        'myScore': score,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
        'myCardsToPeek': cardsToPeek,
      });
      
      // Apply widget updates to games map
      _updateGameInMap(gameId, widgetUpdates);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ _syncWidgetStatesFromGameState: Synced widget states for game $gameId - hand: ${hand.length} cards, status: $status, isMyTurn: $isCurrentPlayer${turnEvents != null ? ', turn_events: ${turnEvents.length}' : ''}');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _syncWidgetStatesFromGameState: Error syncing widget states: $e');
      }
    }
  }
  
  /// Add a session message to the message board
  /// [showModal] - If true, displays the modal. Only set to true for game end messages.
  static void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data, bool showModal = false}) {
    if (LOGGING_SWITCH) {
      _logger.info('📨 _addSessionMessage: Called with level=$level, title="$title", message="$message", showModal=$showModal');
    }
    final entry = {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Get current session messages
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentMessages = currentState['messages'] as Map<String, dynamic>? ?? {};
    final sessionMessages = List<Map<String, dynamic>>.from(currentMessages['session'] as List<dynamic>? ?? []);
    
    // Add new message
    sessionMessages.add(entry);
    if (sessionMessages.length > 200) sessionMessages.removeAt(0);
    
    // Update state - preserve existing modal fields and only update when showModal is true
    final messagesUpdate = {
      'session': sessionMessages,
      'rooms': currentMessages['rooms'] ?? {},
      // Preserve existing modal fields (isVisible, title, content, type, etc.) if they exist
      if (currentMessages.containsKey('isVisible')) 'isVisible': currentMessages['isVisible'],
      if (currentMessages.containsKey('title')) 'title': currentMessages['title'],
      if (currentMessages.containsKey('content')) 'content': currentMessages['content'],
      if (currentMessages.containsKey('type')) 'type': currentMessages['type'],
      if (currentMessages.containsKey('showCloseButton')) 'showCloseButton': currentMessages['showCloseButton'],
      if (currentMessages.containsKey('autoClose')) 'autoClose': currentMessages['autoClose'],
      if (currentMessages.containsKey('autoCloseDelay')) 'autoCloseDelay': currentMessages['autoCloseDelay'],
    };
    
    // Only show modal for game end messages (when showModal is true)
    // For non-game-end messages, preserve existing modal state
    if (showModal) {
      messagesUpdate['isVisible'] = true;
      messagesUpdate['title'] = title ?? '';
      messagesUpdate['content'] = message ?? '';
      messagesUpdate['type'] = (level ?? 'info');
      messagesUpdate['showCloseButton'] = true;
      messagesUpdate['autoClose'] = false;
      messagesUpdate['autoCloseDelay'] = 3000;
      if (LOGGING_SWITCH) {
        _logger.info('📨 _addSessionMessage: Setting modal visible - title="$title", content="$message", type=$level');
      }
    } else {
      // Don't modify modal fields for non-game-end messages - preserve existing state
      _logger.info('📨 _addSessionMessage: Not showing modal (showModal=false) - message added to session only, modal fields preserved', isOn: LOGGING_SWITCH);
    }
    
    // If showing modal, also ensure gamePhase is set to game_ended in the same update
    if (showModal) {
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGamePhase = currentState['gamePhase']?.toString() ?? '';
      if (currentGamePhase != 'game_ended') {
        if (LOGGING_SWITCH) {
          _logger.info('📨 _addSessionMessage: Also updating gamePhase to game_ended in same update');
        }
        DutchGameHelpers.updateUIState({
          'messages': messagesUpdate,
          'gamePhase': 'game_ended', // Ensure gamePhase is set in same update as modal
        });
      } else {
        DutchGameHelpers.updateUIState({
          'messages': messagesUpdate,
        });
      }
    } else {
      DutchGameHelpers.updateUIState({
        'messages': messagesUpdate,
      });
    }
    if (LOGGING_SWITCH) {
      _logger.info('✅ _addSessionMessage: State updated successfully');
    }
  }

  // ========================================
  // PUBLIC EVENT HANDLERS
  // ========================================

  /// Handle dutch_new_player_joined event
  static void handleDutchNewPlayerJoined(Map<String, dynamic> data) {
    final roomId = data['room_id']?.toString() ?? '';
    final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};

    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(roomId)) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  handleDutchNewPlayerJoined: Game $roomId not found in games map - user may have left. Skipping player join update.');
      }
      return;
    }

    // Update the game data with the new game state using helper method
    _updateGameData(roomId, {
      'game_state': gameState,
    });
    
    // Add session message about new player
    _addSessionMessage(
      level: 'info',
      title: 'Player Joined',
      message: '${joinedPlayer['name']} joined the game',
      data: joinedPlayer,
    );
  }

  /// Handle dutch_joined_games event
  static void handleDutchJoinedGames(Map<String, dynamic> data) {
    // final sessionId = data['session_id']?.toString() ?? '';
    final games = data['games'] as List<dynamic>? ?? [];
    final totalGames = data['total_games'] ?? 0;
    
    // Update the games map with the joined games data using helper methods
    for (final gameData in games) {
      final gameId = gameData['game_id']?.toString() ?? '';
      if (gameId.isNotEmpty) {
        // Add/update the game in the games map using helper method
        _addGameToMap(gameId, gameData);
      }
    }
    
    // Set currentGameId to the first joined game (if any)
    String? currentGameId;
    if (games.isNotEmpty) {
      currentGameId = games.first['game_id']?.toString();
    }
    
    // Update dutch game state with joined games information using helper method
    _updateMainGameState({
      'joinedGames': games.cast<Map<String, dynamic>>(),
      'totalJoinedGames': totalGames,
      // Removed joinedGamesTimestamp - causes unnecessary state updates
      if (currentGameId != null) 'currentGameId': currentGameId,
    });
    
    // Add session message about joined games
    _addSessionMessage(
      level: 'info',
      title: 'Games Updated',
      message: 'You are now in $totalGames game${totalGames != 1 ? 's' : ''}',
      data: {'total_games': totalGames, 'games': games},
    );
  }

  /// Handle game_started event
  static void handleGameStarted(Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      _logger.info('🎮 handleGameStarted: Called for gameId=${data['game_id']}');
    }
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final startedBy = data['started_by']?.toString() ?? '';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  handleGameStarted: Game $gameId not found in games map - user may have left. Skipping game started update.');
      }
      return;
    }
    
    // Extract player data
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Handle currentPlayer - it might be a Map (player object) or String (player ID) or null
    Map<String, dynamic>? currentPlayer;
    final currentPlayerRaw = gameState['currentPlayer'];
    if (currentPlayerRaw is Map<String, dynamic>) {
      currentPlayer = currentPlayerRaw;
    } else if (currentPlayerRaw is String && currentPlayerRaw.isNotEmpty) {
      // If currentPlayer is a string (player ID), find the player object in the players list
      currentPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentPlayerRaw,
        orElse: () => <String, dynamic>{},
      );
      if (currentPlayer.isEmpty) {
        currentPlayer = null;
      }
    } else {
      currentPlayer = null;
    }
    
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    Map<String, dynamic>? myPlayer;
    try {
      myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserId,
      );
    } catch (e) {
      myPlayer = null;
    }
    
    // Extract opponent players (excluding current user)
    final opponents = players.where((player) => player['id'] != currentUserId).toList();
    
    // Update the game data with the new game state using helper method
    _updateGameData(gameId, {
      'game_state': gameState,
    });
    
    // Update the game with game started information using helper method
    _updateGameInMap(gameId, {
      // Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice
      'gameStatus': gameState['status'] ?? 'active',
      'isGameActive': true,
      'isRoomOwner': startedBy == currentUserId,  // ✅ Set ownership based on who started the game
      
      // Update game-specific fields for widget slices
      'drawPileCount': drawPile.length,
      'discardPile': discardPile,
      'opponentPlayers': opponents.cast<Map<String, dynamic>>(),
      'currentPlayerIndex': currentPlayer != null ? players.indexOf(currentPlayer) : -1,
      'myHandCards': myPlayer?['hand'] ?? [],
      'selectedCardIndex': -1,
    });
    
    // 🎯 CRITICAL: Sync widget states from game state to ensure all widget slices are up to date
    // Extract turn_events from game state if available (for animations)
    final turnEvents = gameState['turn_events'] as List<dynamic>?;
    _syncWidgetStatesFromGameState(gameId, gameState, turnEvents: turnEvents);
    
    // Get fresh games map after widget sync (it may have been updated)
    final currentGamesAfterSync = _getCurrentGamesMap();
    
    // Normalize backend phase to UI phase (same logic as handleGameStateUpdated)
    final rawPhase = gameState['phase']?.toString();
    String uiPhase;
    if (rawPhase == 'waiting_for_players') {
      uiPhase = 'waiting';
    } else if (rawPhase == 'game_ended') {
      uiPhase = 'game_ended';
    } else {
      uiPhase = rawPhase ?? 'playing';
    }
    
    // Update main state with gamePhase to ensure status chip and game info widget update correctly
    _updateMainGameState({
      'currentGameId': gameId,  // Ensure currentGameId is set
      'games': currentGamesAfterSync, // Updated games map with widget data synced
      'gamePhase': uiPhase,  // ✅ Update gamePhase so status chip and game info widget reflect correct phase
      'isGameActive': uiPhase != 'game_ended', // Set to false when game has ended
    });
    
    // Trigger instructions if showInstructions is enabled
    // Use getCurrentUserId() to handle practice mode correctly (sessionId vs userId)
    final currentUserIdForInstructions = getCurrentUserId();
    final isMyTurn = currentPlayer?['id']?.toString() == currentUserIdForInstructions;
    
    // Get current user's player status (not the current player's status)
    String? currentUserPlayerStatus;
    try {
      final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserIdForInstructions,
      );
      currentUserPlayerStatus = myPlayer['status']?.toString();
    } catch (e) {
      // Player not found, will be handled in _triggerInstructionsIfNeeded
      currentUserPlayerStatus = null;
    }
    
    _triggerInstructionsIfNeeded(
      gameId: gameId,
      gameState: gameState,
      playerStatus: currentUserPlayerStatus, // Pass current user's player status
      isMyTurn: isMyTurn,
    );
    
    // Add session message about game started
    _addSessionMessage(
      level: 'success',
      title: 'Game Started',
      message: 'Game $gameId has started!',
      data: {
        'game_id': gameId,
        'started_by': startedBy,
        'game_state': gameState,
      },
    );
  }

  /// Handle turn_started event
  static void handleTurnStarted(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    // final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final playerId = data['player_id']?.toString() ?? '';
    final playerStatus = data['player_status']?.toString() ?? 'unknown';
    final turnTimeout = data['turn_timeout'] as int? ?? 30;
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  handleTurnStarted: Game $gameId not found in games map - user may have left. Skipping turn started update.');
      }
      return;
    }
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this turn is for the current user
    final isMyTurn = playerId == currentUserId;
    
    if (isMyTurn) {
      
      // Update UI state to show it's the current user's turn using helper method
      _updateMainGameState({
        'isMyTurn': true,
        'turnTimeout': turnTimeout,
        // Removed turnStartTime - causes unnecessary state updates
        'playerStatus': playerStatus,
        'statusBar': {
          'currentPhase': 'my_turn',
          'turnTimer': turnTimeout,
          // Removed turnStartTime - causes unnecessary state updates
          'playerStatus': playerStatus,
        },
      });
      
      // Add session message about turn started
      _addSessionMessage(
        level: 'info',
        title: 'Your Turn',
        message: 'It\'s your turn! You have $turnTimeout seconds to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'turn_timeout': turnTimeout,
          'is_my_turn': true,
        },
      );
    } else {
      
      // Update UI state to show it's another player's turn using helper method
      _updateMainGameState({
        'isMyTurn': false,
        'statusBar': {
          'currentPhase': 'opponent_turn',
          'currentPlayer': playerId,
        },
      });
      
      // Add session message about opponent's turn
      _addSessionMessage(
        level: 'info',
        title: 'Opponent\'s Turn',
        message: 'It\'s $playerId\'s turn to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'is_my_turn': false,
        },
      );
    }
  }

  /// Handle game_state_updated event
  static void handleGameStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final ownerId = data['owner_id']?.toString(); // Extract owner_id from main payload
    final turnEvents = data['turn_events'] as List<dynamic>? ?? []; // Extract turn_events for animations
    final myCardsToPeekFromEvent = data['myCardsToPeek'] as List<dynamic>?; // Extract root-level myCardsToPeek if present
    
    // 🔍 DEBUG: Check drawnCard data in received game_state
    final players = gameState['players'] as List<dynamic>? ?? [];
    final currentUserId = getCurrentUserId();
    if (LOGGING_SWITCH) {
      _logger.info('🔍 DRAW DEBUG - handleGameStateUpdated: Received game_state_updated for gameId: $gameId, currentUserId: $currentUserId');
    }
    for (final player in players) {
      if (player is Map<String, dynamic>) {
        final playerId = player['id']?.toString() ?? 'unknown';
        final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
        if (drawnCard != null) {
          final rank = drawnCard['rank']?.toString() ?? 'null';
          final suit = drawnCard['suit']?.toString() ?? 'null';
          final isIdOnly = rank == '?' && suit == '?';
          final isCurrentUser = playerId == currentUserId;
          if (LOGGING_SWITCH) {
            _logger.info('🔍 DRAW DEBUG - handleGameStateUpdated: Player $playerId (isCurrentUser: $isCurrentUser) drawnCard - rank: $rank, suit: $suit, isIdOnly: $isIdOnly');
          }
        }
      }
    }
    
    // 🔍 DEBUG: Log the extracted values
    if (LOGGING_SWITCH) {
      _logger.info('🔍 handleGameStateUpdated DEBUG:');
      _logger.info('  gameId: $gameId');
      _logger.info('  ownerId: $ownerId');
      _logger.info('  data keys: ${data.keys.toList()}');
      _logger.info('  turn_events count: ${turnEvents.length}');
      _logger.info('  myCardsToPeekFromEvent: ${myCardsToPeekFromEvent != null ? "${myCardsToPeekFromEvent.length} items" : "null"}');
      if (turnEvents.isNotEmpty) {
        _logger.info('  🔍 JACK SWAP DEBUG - turn_events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
      }
    }
    final roundNumber = data['round_number'] as int? ?? 1;
    final currentPlayer = data['current_player'];
    final currentPlayerStatus = data['current_player_status']?.toString() ?? 'unknown';
    final roundStatus = data['round_status']?.toString() ?? 'active';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Extract pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = drawPile.length;
    final discardPileCount = discardPile.length;
    
    // Extract players list (used for game map update, widget sync handled separately)
    // Note: players is already defined above for debug logging
    
    // Check if game exists in games map, if not add it
    final currentGames = _getCurrentGamesMap();
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    
    // 🎯 CRITICAL: If games map is empty but currentGameId is set, this might be a stale event
    // from a game that was just cleared. Only accept events for the current game or if currentGameId is empty.
    if (currentGames.isEmpty && currentGameId.isNotEmpty && gameId != currentGameId) {
      _logger.warning('⚠️  handleGameStateUpdated: Ignoring stale game_state_updated for $gameId - games map is empty and currentGameId is $currentGameId (likely from cleared game)', isOn: LOGGING_SWITCH);
      return; // Ignore stale events from games that were just cleared
    }
    
    final wasNewGame = !currentGames.containsKey(gameId);
    
    if (wasNewGame) {
      // 🎯 CRITICAL: Only one game should exist in the games map at a time
      // Remove all other games when adding a new game
      if (currentGames.isNotEmpty) {
        _logger.warning('⚠️  handleGameStateUpdated: Removing ${currentGames.length} old game(s) before adding new game $gameId', isOn: LOGGING_SWITCH);
        currentGames.clear(); // Remove all existing games
      }
      // Add the game to the games map with the complete game state.
      // IMPORTANT: Do not overwrite ownership with null. Only include owner_id if present.
      final base = {
        'game_id': gameId,
        'game_state': gameState,
      };
      if (ownerId != null) {
        base['owner_id'] = ownerId;
      }
      _addGameToMap(gameId, base);
      _logger.info('🔍 handleGameStateUpdated: Added new game to map: $gameId (players: ${players.length})', isOn: LOGGING_SWITCH);
      
      // 🎯 CRITICAL: Immediately update the newly added game with additional information
      // This ensures the game has all the data it needs before widget sync
      final currentGamesAfterAdd = _getCurrentGamesMap();
      if (currentGamesAfterAdd.containsKey(gameId)) {
        final updateData = {
          'drawPileCount': drawPileCount,
          'discardPileCount': discardPileCount,
          'discardPile': discardPile,
          'players': players,  // Include all players data
          'turn_events': turnEvents, // Include turn_events for widget slices
        };
        _updateGameInMap(gameId, updateData);
      }
      
      // 🎯 CRITICAL: Get fresh games map after adding and updating (ensures it's in state)
      final updatedGamesAfterAdd = _getCurrentGamesMap();
      
      // 🎯 CRITICAL: Set currentGameId and ensure games map is in main state (important for player 2 joining after match start)
      // Note: currentState and currentGameId are already defined above
      if (LOGGING_SWITCH) {
        _logger.info('🔍 handleGameStateUpdated: currentGameId check - existing: $currentGameId, new gameId: $gameId');
      }
      
      // 🎯 CRITICAL: Set currentGameId and ensure games map is in main state
      // Since we cleared all other games above, this is the only game in the map
      // Note: currentGameId is a String (never null due to ?? ''), so only check isEmpty
      if (currentGameId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('🔍 handleGameStateUpdated: Setting currentGameId to $gameId (was null or empty)');
        }
        _updateMainGameState({
          'currentGameId': gameId,
          'games': updatedGamesAfterAdd, // 🎯 CRITICAL: Ensure games map is in main state
        });
      } else if (currentGameId != gameId) {
        // If currentGameId is different, update it to the new game
        if (LOGGING_SWITCH) {
          _logger.info('🔍 handleGameStateUpdated: Updating currentGameId from $currentGameId to $gameId');
        }
        _updateMainGameState({
          'currentGameId': gameId,
          'games': updatedGamesAfterAdd, // 🎯 CRITICAL: Ensure games map is in main state
        });
      } else {
        // Even if currentGameId matches, ensure games map is updated in main state
        if (LOGGING_SWITCH) {
          _logger.info('🔍 handleGameStateUpdated: currentGameId already set to $currentGameId, updating games map only');
        }
        _updateMainGameState({
          'games': updatedGamesAfterAdd, // 🎯 CRITICAL: Ensure games map is in main state
        });
      }
    } else {
      // 🎯 CRITICAL: Verify game still exists in games map before updating
      // This prevents stale state updates when user has left the game
      final currentGamesForCheck = _getCurrentGamesMap();
      if (!currentGamesForCheck.containsKey(gameId)) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️  handleGameStateUpdated: Game $gameId not found in games map - user may have left. Skipping game state update.');
        }
        return;
      }
      
      // 🎯 CRITICAL: Only one game should exist in the games map at a time
      // If this game is not the currentGameId, remove it and all other games
      final currentStateForCheck = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameIdForCheck = currentStateForCheck['currentGameId']?.toString() ?? '';
      
      if (currentGameIdForCheck.isNotEmpty && currentGameIdForCheck != gameId) {
        // This is a stale game - remove it and keep only the current game
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️  handleGameStateUpdated: Removing stale game $gameId - currentGameId is $currentGameIdForCheck');
        }
        final gamesToUpdate = _getCurrentGamesMap();
        gamesToUpdate.remove(gameId);
        // If the current game is still in the map, keep only that one
        if (gamesToUpdate.containsKey(currentGameIdForCheck)) {
          final currentGameData = gamesToUpdate[currentGameIdForCheck];
          gamesToUpdate.clear();
          gamesToUpdate[currentGameIdForCheck] = currentGameData;
        } else {
          gamesToUpdate.clear();
        }
        DutchGameHelpers.updateUIState({
          'games': gamesToUpdate,
        });
        return; // Don't update stale games
      }
      
      // Update existing game's game_state
      if (LOGGING_SWITCH) {
        _logger.info('🔍 Updating existing game: $gameId');
      }
      _updateGameData(gameId, {
        'game_state': gameState,
      });
      
      // Update owner_id and recalculate isRoomOwner at the top level
      if (ownerId != null) {
        final currentUserId = getCurrentUserId();
        // Use _isCurrentUserRoomOwner to properly handle practice mode (userId vs sessionId)
        final gameDataForOwnerCheck = {'owner_id': ownerId};
        final isOwner = _isCurrentUserRoomOwner(gameDataForOwnerCheck);
        if (LOGGING_SWITCH) {
          _logger.info('🔍 Updating owner_id: $ownerId, currentUserId: $currentUserId');
          _logger.info('🔍 Setting isRoomOwner: $isOwner');
        }
        _updateGameInMap(gameId, {
          'owner_id': ownerId,
          'isRoomOwner': isOwner,
        });
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🔍 ownerId is null, preserving previous ownership');
        }
        // Preserve main state's isRoomOwner when ownerId is missing
        final currentMain = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final prevIsOwner = currentMain['isRoomOwner'] as bool? ?? false;
        _updateMainGameState({'isRoomOwner': prevIsOwner});
      }
    }
    
    // Update the games map with additional information first (needed for widget sync)
    // 🎯 CRITICAL: Only update if this wasn't a new game (new games are already updated above)
    if (!wasNewGame) {
      final updateData = {
        'drawPileCount': drawPileCount,
        'discardPileCount': discardPileCount,
        'discardPile': discardPile,
        'players': players,  // Include all players data
        'turn_events': turnEvents, // Include turn_events for widget slices
      };
      
      _updateGameInMap(gameId, updateData);
    }
    
    // 🎯 CRITICAL: If root-level myCardsToPeek is provided in event, use it directly
    // This ensures we clear myCardsToPeek immediately when backend sends explicit clear
    if (myCardsToPeekFromEvent != null) {
      if (LOGGING_SWITCH) {
        _logger.info('🔍 handleGameStateUpdated: Root-level myCardsToPeek provided in event: ${myCardsToPeekFromEvent.length} items');
      }
      _updateMainGameState({
        'myCardsToPeek': myCardsToPeekFromEvent,
        // Clear protectedCardsToPeek if myCardsToPeek is empty
        if (myCardsToPeekFromEvent.isEmpty) 'protectedCardsToPeek': null,
      });
    }
    
    // 🎯 CRITICAL: Sync widget states from game state FIRST (matches practice mode pattern)
    // This ensures myHandCards, myDrawnCard, playerStatus, etc. are synced from game state
    // Must happen before main state update so widget slices recompute with turn_events
    _syncWidgetStatesFromGameState(gameId, gameState, turnEvents: turnEvents);
    
    // Get fresh games map after widget sync (it may have been updated)
    final currentGamesAfterSync = _getCurrentGamesMap();
    
    // Extract currentPlayer from game state for main state update
    final currentPlayerFromState = gameState['currentPlayer'] as Map<String, dynamic>?;
    
    // Get current user's player status for instructions (not the current player's status)
    // Note: players list and currentUserId are already extracted above for debug logging
    String? currentUserPlayerStatus;
    try {
      final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserId,
      );
      currentUserPlayerStatus = myPlayer['status']?.toString();
      if (LOGGING_SWITCH) {
        _logger.info('📚 handleGameStateUpdated: Current user player status=$currentUserPlayerStatus, currentPlayerStatus=$currentPlayerStatus');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('📚 handleGameStateUpdated: Current user player not found: $e');
      }
      // Player not found, will be handled in _triggerInstructionsIfNeeded
      currentUserPlayerStatus = null;
    }
    
    // Normalize backend phase to UI phase
    final rawPhase = gameState['phase']?.toString();
    if (LOGGING_SWITCH) {
      _logger.info('🔍 handleGameStateUpdated: rawPhase=$rawPhase for gameId=$gameId');
    }
    String uiPhase;
    if (rawPhase == 'waiting_for_players') {
      uiPhase = 'waiting';
    } else if (rawPhase == 'game_ended') {
      uiPhase = 'game_ended';
    } else {
      uiPhase = rawPhase ?? 'playing';
    }
    if (LOGGING_SWITCH) {
      _logger.info('🔍 handleGameStateUpdated: normalized uiPhase=$uiPhase for gameId=$gameId');
    }

    // Extract winners list if game has ended - check both data and gameState
    final winners = data['winners'] as List<dynamic>? ?? gameState['winners'] as List<dynamic>?;
    if (LOGGING_SWITCH) {
      _logger.info('🔍 handleGameStateUpdated: Winners extraction - data.winners=${data['winners']}, gameState.winners=${gameState['winners']}, final winners=${winners?.length ?? 0}');
    }

    // 🎯 CRITICAL: Always ensure currentGameId is set (even for existing games)
    // This is essential for the game play screen to update correctly when match starts
    final currentStateForGameId = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final existingCurrentGameId = currentStateForGameId['currentGameId']?.toString();
    if (existingCurrentGameId != gameId) {
      if (LOGGING_SWITCH) {
        _logger.info('🔍 handleGameStateUpdated: Updating currentGameId from $existingCurrentGameId to $gameId');
      }
    }

    // Check if game just started (phase changed to initial_peek) and deduct coins
    final previousPhase = currentStateForGameId['gamePhase']?.toString();
    final isGameStarting = (previousPhase == null || previousPhase == 'waiting' || previousPhase == 'waiting_for_players') && 
                           (rawPhase == 'initial_peek');
    
    if (isGameStarting) {
      if (LOGGING_SWITCH) {
        _logger.info('💰 handleGameStateUpdated: Game starting - phase changed to initial_peek, checking for coin deduction');
      }
      _handleCoinDeductionOnGameStart(gameId, gameState);
    }
    
    // Track same rank window triggers BEFORE updating state
    // Check if we're transitioning INTO same_rank_window (not already in it)
    if (uiPhase == 'same_rank_window' && previousPhase != 'same_rank_window') {
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      int sameRankTriggerCount = currentState['sameRankTriggerCount'] as int? ?? 0;
      sameRankTriggerCount++;
      if (LOGGING_SWITCH) {
        _logger.info('📚 handleGameStateUpdated: Transitioning INTO same_rank_window - incrementing counter to $sameRankTriggerCount');
      }
      // Update counter in state (will be included in the main state update below)
      StateManager().updateModuleState('dutch_game', {
        'sameRankTriggerCount': sameRankTriggerCount,
      });
    }
    
    // Then update main state with games map, discardPile, currentPlayer, turn_events (matches practice mode pattern)
    // 🎯 CRITICAL: Update gamePhase FIRST so MessagesWidget can check it
    _updateMainGameState({
      'currentGameId': gameId,  // Always set currentGameId (CRITICAL for game play screen to update)
      'games': currentGamesAfterSync, // Updated games map with widget data synced
      'gamePhase': uiPhase, // 🎯 CRITICAL: Set gamePhase before checking for winners modal
      'isGameActive': uiPhase != 'game_ended', // Set to false when game has ended
      'roundNumber': roundNumber,
      'currentPlayer': currentPlayerFromState ?? currentPlayer, // Use currentPlayer from game state if available
      'currentPlayerStatus': currentPlayerStatus,
      'roundStatus': roundStatus,
      'discardPile': discardPile, // Updated discard pile for centerBoard slice
      'turn_events': turnEvents, // Include turn_events for animations (critical for widget slice recomputation)
    });
    if (LOGGING_SWITCH) {
      _logger.info('🔍 handleGameStateUpdated: Updated main state with gamePhase=$uiPhase');
    }
    
    // Trigger instructions if showInstructions is enabled
    final isMyTurn = currentPlayerFromState?['id']?.toString() == currentUserId ||
                     (currentPlayer is Map && currentPlayer['id']?.toString() == currentUserId);
    if (LOGGING_SWITCH) {
      _logger.info('📚 handleGameStateUpdated: Triggering instructions - isMyTurn=$isMyTurn, currentUserStatus=$currentUserPlayerStatus');
    }
    _triggerInstructionsIfNeeded(
      gameId: gameId,
      gameState: gameState,
      playerStatus: currentUserPlayerStatus, // Pass current user's player status, not current player's status
      isMyTurn: isMyTurn,
    );
    
    // Add game to joinedGames list if it's not already there (one-time addition)
    // This ensures games appear in current rooms widget even if joined_games event is delayed
    // Only add if game is in games map (user is actually in the game) and not already in joinedGames
    final currentGamesForJoined = _getCurrentGamesMap();
    if (currentGamesForJoined.containsKey(gameId)) {
      final gameInMap = currentGamesForJoined[gameId] as Map<String, dynamic>? ?? {};
      final gameData = gameInMap['gameData'] as Map<String, dynamic>? ?? {};
      
      // Only proceed if we have valid gameData
      if (gameData.isNotEmpty && gameData['game_id'] != null) {
        // Get current joinedGames list
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentJoinedGames = List<Map<String, dynamic>>.from(currentState['joinedGames'] as List<dynamic>? ?? []);
        
        // Check if this game is already in joinedGames
        final existingIndex = currentJoinedGames.indexWhere((game) => game['game_id'] == gameId);
        
        if (existingIndex < 0) {
          // Game not in joinedGames - add it (one-time addition)
          if (LOGGING_SWITCH) {
            _logger.info('DutchEventHandlerCallbacks: Adding game $gameId to joinedGames list (first time)');
          }
          currentJoinedGames.add(gameData);
          
          // Update joinedGames state
          _updateMainGameState({
            'joinedGames': currentJoinedGames,
            'totalJoinedGames': currentJoinedGames.length,
          });
        }
        // If game already exists in joinedGames, don't update it (prevents duplicates)
      }
    }
    
    // Check for demo action completion
    _checkDemoActionCompletion(
      gameId: gameId,
      gameState: gameState,
      currentUserPlayerStatus: currentUserPlayerStatus,
    );
    
    // Add session message about game state update or game end
    if (LOGGING_SWITCH) {
      _logger.info('🎯 handleGameStateUpdated: Checking game end - uiPhase=$uiPhase, winners=${winners?.length ?? 0}');
    }
    if (uiPhase == 'game_ended' && winners != null && winners.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('🏆 handleGameStateUpdated: Game ended with ${winners.length} winner(s) - triggering winner modal');
      }
      // Game has ended - notify user with winner information and win reason
      final winnerMessages = winners.map((w) {
        if (w is Map<String, dynamic>) {
          final playerName = w['playerName']?.toString() ?? 'Unknown';
          final winType = w['winType']?.toString() ?? 'unknown';
          
          // Format win type into readable text
          String winReason;
          switch (winType) {
            case 'four_of_a_kind':
              winReason = 'Four of a Kind';
              break;
            case 'empty_hand':
              winReason = 'No Cards Left';
              break;
            case 'lowest_points':
              winReason = 'Lowest Points';
              break;
            case 'dutch':
              winReason = 'Dutch Called';
              break;
            default:
              winReason = 'Unknown';
          }
          
          return '$playerName ($winReason)';
        }
        return 'Unknown';
      }).join(', ');
      
      _addSessionMessage(
        level: 'success',
        title: 'Game Ended',
        message: 'Winner(s): $winnerMessages',
        data: {
          'game_id': gameId,
          'winners': winners,
          'game_ended': true,
        },
        showModal: true, // Show modal for game end
      );
      
      // Track game completed event
      final gameMode = gameState['game_mode']?.toString() ?? 'multiplayer';
      final isCurrentUserWinner = winners.any((w) {
        if (w is Map<String, dynamic>) {
          return w['id']?.toString() == currentUserId;
        }
        return false;
      });
      _trackGameEvent('game_completed', {
        'game_id': gameId,
        'game_mode': gameMode,
        'result': isCurrentUserWinner ? 'win' : 'loss',
        'winners_count': winners.length,
      });
      
      // Refresh user stats (including coins) after game ends to update app bar display
      // This ensures the coins display shows the updated balance after winning/losing
      if (LOGGING_SWITCH) {
        _logger.info('🔄 handleGameStateUpdated: Refreshing user stats after game end to update coins display');
      }
      DutchGameHelpers.fetchAndUpdateUserDutchGameData().then((success) {
        if (LOGGING_SWITCH) {
          if (success) {
            _logger.info('✅ handleGameStateUpdated: Successfully refreshed user stats after game end');
          } else {
            _logger.warning('⚠️ handleGameStateUpdated: Failed to refresh user stats after game end');
          }
        }
      });
    } else {
      // Normal game state update - ensure modal is hidden if game hasn't ended
      if (uiPhase != 'game_ended') {
        final currentMessages = StateManager().getModuleState<Map<String, dynamic>>('dutch_game')?['messages'] as Map<String, dynamic>? ?? {};
        if (currentMessages['isVisible'] == true) {
          _logger.info('🎯 handleGameStateUpdated: Hiding modal - game phase is not game_ended (uiPhase=$uiPhase)', isOn: LOGGING_SWITCH);
          DutchGameHelpers.updateUIState({
            'messages': {
              ...currentMessages,
              'isVisible': false,
            },
          });
        }
      }
      
      // Normal game state update
      _addSessionMessage(
        level: 'info',
        title: 'Game State Updated',
        message: 'Round $roundNumber - $currentPlayer is $currentPlayerStatus',
        data: {
          'game_id': gameId,
          'round_number': roundNumber,
          'current_player': currentPlayer,
          'current_player_status': currentPlayerStatus,
          'round_status': roundStatus,
        },
        showModal: false, // Don't show modal for normal updates
      );
    }
  }

  /// Handle game_state_partial_update event
  static void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      _logger.info("handleGameStatePartialUpdate: $data");
    }
    final gameId = data['game_id']?.toString() ?? '';
    final changedProperties = data['changed_properties'] as List<dynamic>? ?? [];
    final partialGameState = data['partial_game_state'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Get current game state to merge with partial updates
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      return; // Game not found, ignore partial update
    }
    
    final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
    final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final currentGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Merge partial updates with current game state
    final updatedGameState = Map<String, dynamic>.from(currentGameState);
    updatedGameState.addAll(partialGameState);
    
    // Update the game data with merged state using helper method
    _updateGameData(gameId, {
      'game_state': updatedGameState,
    });
    
    // Update specific UI fields based on changed properties
    final updates = <String, dynamic>{};
    bool shouldSyncWidgetStates = false;
    
    for (final property in changedProperties) {
      final propName = property.toString();
      
      switch (propName) {
        case 'phase':
          // Update main state only - normalize backend phase to UI phase
          final rawPhase = updatedGameState['phase']?.toString();
          final uiPhase = rawPhase == 'waiting_for_players'
              ? 'waiting'
              : (rawPhase ?? 'playing');
          _updateMainGameState({
            'gamePhase': uiPhase,
          });
          break;
        case 'players':
          // Mark that we need to sync widget states since players changed
          shouldSyncWidgetStates = true;
          break;
        case 'current_player_id':
        case 'currentPlayer':
          // Mark that we need to sync widget states since current player changed
          shouldSyncWidgetStates = true;
          updates['currentPlayer'] = updatedGameState['current_player_id'] ?? updatedGameState['currentPlayer'];
          break;
        case 'draw_pile':
          final drawPile = updatedGameState['drawPile'] as List<dynamic>? ?? [];
          updates['drawPileCount'] = drawPile.length;
          break;
        case 'discard_pile':
          final discardPile = updatedGameState['discardPile'] as List<dynamic>? ?? [];
          updates['discardPileCount'] = discardPile.length;
          updates['discardPile'] = discardPile;
          break;
        case 'dutch_called_by':
          updates['dutchCalledBy'] = updatedGameState['dutch_called_by'];
          // Track Dutch call event
          final gameMode = updatedGameState['game_mode']?.toString() ?? 'multiplayer';
          _trackGameEvent('dutch_called', {
            'game_id': gameId,
            'game_mode': gameMode,
            'called_by': updatedGameState['dutch_called_by']?.toString(),
          });
          break;
        case 'game_ended':
          updates['isGameActive'] = !(updatedGameState['game_ended'] == true);
          break;
        case 'winner':
          updates['winner'] = updatedGameState['winner'];
          break;
      }
    }

    _logger.info("updates: $updates", isOn: LOGGING_SWITCH);
    // Apply UI updates if any
    if (updates.isNotEmpty) {
      _updateGameInMap(gameId, updates);
    }
    
    // 🎯 CRITICAL: Sync widget states if players or currentPlayer changed
    // This ensures computed slices (myHand.cards, etc.) stay in sync
    if (shouldSyncWidgetStates) {
      // Try to get turn_events from current games map if available
      final currentGamesForTurnEvents = _getCurrentGamesMap();
      final currentGameForTurnEvents = currentGamesForTurnEvents[gameId] as Map<String, dynamic>? ?? {};
      final turnEvents = currentGameForTurnEvents['turn_events'] as List<dynamic>?;
      _syncWidgetStatesFromGameState(gameId, updatedGameState, turnEvents: turnEvents);
    }
    
    // Check if game has ended and show winner modal
    final rawPhase = updatedGameState['phase']?.toString();
    final uiPhase = rawPhase == 'waiting_for_players'
        ? 'waiting'
        : (rawPhase == 'game_ended' ? 'game_ended' : (rawPhase ?? 'playing'));
    
    // Extract winners list if game has ended
    final winners = data['winners'] as List<dynamic>? ?? updatedGameState['winners'] as List<dynamic>?;
    
    if (LOGGING_SWITCH) {
      _logger.info('🎯 handleGameStatePartialUpdate: Checking game end - uiPhase=$uiPhase, winners=${winners?.length ?? 0}');
    }
    // Add session message about partial update or game end
    if (uiPhase == 'game_ended' && winners != null && winners.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('🏆 handleGameStatePartialUpdate: Game ended with ${winners.length} winner(s) - triggering winner modal');
      }
      // Game has ended - notify user with winner information and win reason
      final winnerMessages = winners.map((w) {
        if (w is Map<String, dynamic>) {
          final playerName = w['playerName']?.toString() ?? 'Unknown';
          final winType = w['winType']?.toString() ?? 'unknown';
          
          // Format win type into readable text
          String winReason;
          switch (winType) {
            case 'four_of_a_kind':
              winReason = 'Four of a Kind';
              break;
            case 'empty_hand':
              winReason = 'No Cards Left';
              break;
            case 'lowest_points':
              winReason = 'Lowest Points';
              break;
            case 'dutch':
              winReason = 'Dutch Called';
              break;
            default:
              winReason = 'Unknown';
          }
          
          return '$playerName ($winReason)';
        }
        return 'Unknown';
      }).join(', ');
      
      // Update gamePhase and show modal in the same state update to avoid race condition
      if (LOGGING_SWITCH) {
        _logger.info('🏆 handleGameStatePartialUpdate: Updating gamePhase and showing winner modal');
      }
      DutchGameHelpers.updateUIState({
        'gamePhase': 'game_ended', // Ensure gamePhase is set before showing modal
      });
      
      _logger.info('🏆 handleGameStatePartialUpdate: Calling _addSessionMessage with winner info - title="Game Ended", message="Winner(s): $winnerMessages"', isOn: LOGGING_SWITCH);
      
      // Refresh user stats (including coins) after game ends to update app bar display
      // This ensures the coins display shows the updated balance after winning/losing
      if (LOGGING_SWITCH) {
        _logger.info('🔄 handleGameStatePartialUpdate: Refreshing user stats after game end to update coins display');
      }
      DutchGameHelpers.fetchAndUpdateUserDutchGameData().then((success) {
        if (LOGGING_SWITCH) {
          if (success) {
            _logger.info('✅ handleGameStatePartialUpdate: Successfully refreshed user stats after game end');
          } else {
            _logger.warning('⚠️ handleGameStatePartialUpdate: Failed to refresh user stats after game end');
          }
        }
      });
      
      _addSessionMessage(
        level: 'success',
        title: 'Game Ended',
        message: 'Winner(s): $winnerMessages',
        data: {
          'game_id': gameId,
          'winners': winners,
          'game_ended': true,
        },
        showModal: true, // Show modal for game end
      );
    } else {
      // Normal partial update - ensure modal is hidden if game hasn't ended
      if (uiPhase != 'game_ended') {
        final currentMessages = StateManager().getModuleState<Map<String, dynamic>>('dutch_game')?['messages'] as Map<String, dynamic>? ?? {};
        if (currentMessages['isVisible'] == true) {
          _logger.info('🎯 handleGameStatePartialUpdate: Hiding modal - game phase is not game_ended (uiPhase=$uiPhase)', isOn: LOGGING_SWITCH);
          DutchGameHelpers.updateUIState({
            'messages': {
              ...currentMessages,
              'isVisible': false,
            },
          });
        }
      }
      
      // Normal partial update
      _addSessionMessage(
        level: 'info',
        title: 'Game State Updated',
        message: 'Updated: ${changedProperties.join(', ')}',
        data: {
          'game_id': gameId,
          'changed_properties': changedProperties,
          'partial_updates': partialGameState,
        },
        showModal: false, // Don't show modal for normal updates
      );
    }
  }

  /// Handle player_state_updated event
  static void handlePlayerStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final playerId = data['player_id']?.toString() ?? '';
    final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️  handlePlayerStateUpdated: Game $gameId not found in games map - user may have left. Skipping player state update.');
      }
      return;
    }
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this update is for the current user
    final isMyUpdate = playerId == currentUserId;
    
    if (isMyUpdate) {
      
      // Extract player data fields
      final hand = playerData['hand'] as List<dynamic>? ?? [];
      // final visibleCards = playerData['visibleCards'] as List<dynamic>? ?? [];
      final cardsToPeek = playerData['cardsToPeek'] as List<dynamic>? ?? [];
      final drawnCard = playerData['drawnCard'] as Map<String, dynamic>?;
      final score = playerData['score'] as int? ?? 0;
      final status = playerData['status']?.toString() ?? 'unknown';
      final isCurrentPlayer = playerData['isCurrentPlayer'] == true;
      // final hasCalledDutch = playerData['hasCalledDutch'] == true;
      
      // Update the main game state with player information using helper method
      _updateMainGameState({
        'playerStatus': status,
        'myScore': score,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
        'myCardsToPeek': cardsToPeek,
      });
      
      // Update the games map with hand information using helper method
      _updateGameInMap(gameId, {
        'myHandCards': hand,
        'selectedCardIndex': -1,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
      });
      
      // Add session message about player state update
      _addSessionMessage(
        level: 'info',
        title: 'Player State Updated',
        message: 'Hand: ${hand.length} cards, Score: $score, Status: $status',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'hand_size': hand.length,
          'score': score,
          'status': status,
          'is_current_player': isCurrentPlayer,
        },
      );
    } else {
      
      // Get current opponents and update them using helper method
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      if (currentGames.containsKey(gameId)) {
        final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final currentOpponents = currentGameData['opponentPlayers'] as List<dynamic>? ?? [];
        
        // Update opponent information in the games map using helper method
        _updateGameData(gameId, {
          'opponentPlayers': currentOpponents.map((opponent) {
            if (opponent['id'] == playerId) {
              return {
                ...opponent,
                'hand': playerData['hand'] ?? [],
                'score': playerData['score'] ?? 0,
                'status': playerData['status'] ?? 'unknown',
                'hasCalledDutch': playerData['hasCalledDutch'] ?? false,
                'drawnCard': playerData['drawnCard'],
              };
            }
            return opponent;
          }).toList(),
        });
      }
    }
  }

  /// Handle queen_peek_result event
  static void handleQueenPeekResult(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final peekingPlayerId = data['peeking_player_id']?.toString() ?? '';
    final targetPlayerId = data['target_player_id']?.toString() ?? '';
    final peekedCard = data['peeked_card'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this peek result is for the current user
    final isMyPeekResult = peekingPlayerId == currentUserId;
    
    if (isMyPeekResult) {
      // Extract card details
      final cardId = peekedCard['card_id']?.toString() ?? '';
      final cardRank = peekedCard['rank']?.toString() ?? '';
      final cardSuit = peekedCard['suit']?.toString() ?? '';
      final cardPoints = peekedCard['points'] as int? ?? 0;
      final cardColor = peekedCard['color']?.toString() ?? '';
      final cardIndex = peekedCard['index'] as int? ?? -1;
      
      // Add session message about successful peek
      _addSessionMessage(
        level: 'info',
        title: 'Queen Peek Result',
        message: 'You peeked at $targetPlayerId\'s card: $cardRank of $cardSuit ($cardPoints points)',
        data: {
          'game_id': gameId,
          'target_player_id': targetPlayerId,
          'peeked_card': peekedCard,
          'card_details': {
            'id': cardId,
            'rank': cardRank,
            'suit': cardSuit,
            'points': cardPoints,
            'color': cardColor,
            'index': cardIndex,
          },
        },
      );
    } else {
      // This is another player's peek result - we can optionally show a generic message
      // or keep it private (current implementation keeps it private)
      _addSessionMessage(
        level: 'info',
        title: 'Queen Power Used',
        message: '$peekingPlayerId used Queen peek on $targetPlayerId',
        data: {
          'game_id': gameId,
          'peeking_player_id': peekingPlayerId,
          'target_player_id': targetPlayerId,
          'is_my_peek': false,
        },
      );
    }
  }

  /// Handle cards_to_peek event

  /// Handle coin deduction when game starts
  /// Called when game phase changes to initial_peek (game started)
  static Future<void> _handleCoinDeductionOnGameStart(String gameId, Map<String, dynamic> gameState) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('💰 _handleCoinDeductionOnGameStart: Processing coin deduction for game $gameId');
      }
      
      // Get all active players from game state (for both practice and multiplayer)
      final players = (gameState['players'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((p) => (p['isActive'] as bool? ?? true) == true)  // Only active players
          .toList();
      
      if (players.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ _handleCoinDeductionOnGameStart: No active players found');
        }
        return;
      }
      
      // Calculate pot: coin_cost × number_of_active_players (regardless of subscription tier)
      // Default coin cost is 25 (will be tied to match_class in future)
      final coinCost = 25;
      final activePlayerCount = players.length;
      final pot = coinCost * activePlayerCount;
      
      // Store match_class, coin_cost_per_player, and match_pot in game_state
      // This allows the pot to be displayed during gameplay
      // Need to update game_state within gameData, not gameData directly
      final currentGames = _getCurrentGamesMap();
      if (currentGames.containsKey(gameId)) {
        final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final currentGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
        
        // Update game_state with pot information
        final updatedGameState = Map<String, dynamic>.from(currentGameState);
        updatedGameState.addAll({
          'match_class': 'standard', // Placeholder for future match class system
          'coin_cost_per_player': coinCost,
          'match_pot': pot,
        });
        
        // Update gameData with updated game_state
        final updatedGameData = Map<String, dynamic>.from(currentGameData);
        updatedGameData['game_state'] = updatedGameState;
        
        // Update the game
        _updateGameInMap(gameId, {
          'gameData': updatedGameData,
        });
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('💰 _handleCoinDeductionOnGameStart: Calculated pot for game $gameId - coin_cost: $coinCost, players: $activePlayerCount, pot: $pot');
      }
      
      // Skip coin deduction for practice mode games (but pot is still calculated and stored)
      if (gameId.startsWith('practice_room_')) {
        if (LOGGING_SWITCH) {
          _logger.info('💰 _handleCoinDeductionOnGameStart: Skipping coin deduction for practice mode game (pot calculated: $pot)');
        }
        return;
      }
      
      // Check if coins were already deducted for this game (prevent duplicate deductions)
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final coinsDeductedGames = Set<String>.from(currentState['coinsDeductedGames'] as List<dynamic>? ?? []);
      
      if (coinsDeductedGames.contains(gameId)) {
        if (LOGGING_SWITCH) {
          _logger.info('💰 _handleCoinDeductionOnGameStart: Coins already deducted for game $gameId, skipping');
        }
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('💰 _handleCoinDeductionOnGameStart: Found ${players.length} active player(s) for coin deduction');
      }
      
      // Get user IDs for all players
      // Note: Player IDs are sessionIds, but we need user IDs (MongoDB ObjectIds) for the API
      // userId is stored in player objects when they join (from room_created/room_joined events)
      final playerIds = <String>[];
      final currentUserId = getCurrentUserId();
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserMongoId = loginState['userId']?.toString() ?? '';
      
      for (final player in players) {
        final playerSessionId = player['id']?.toString() ?? '';
        if (playerSessionId.isEmpty) continue;
        
        // First, try to get userId from player object (stored when player joins)
        final playerUserId = player['userId']?.toString() ?? player['user_id']?.toString();
        if (playerUserId != null && playerUserId.isNotEmpty) {
          playerIds.add(playerUserId);
          if (LOGGING_SWITCH) {
            _logger.info('💰 _handleCoinDeductionOnGameStart: Added player userId from player object: $playerUserId (sessionId: $playerSessionId)');
          }
        } else {
          // Fallback: If this is the current user and userId not in player object, use login state
          if (playerSessionId == currentUserId && currentUserMongoId.isNotEmpty) {
            playerIds.add(currentUserMongoId);
            if (LOGGING_SWITCH) {
              _logger.info('💰 _handleCoinDeductionOnGameStart: Added current user MongoDB ID from login state: $currentUserMongoId');
            }
          } else {
            // Cannot get userId for this player - log warning but continue
            if (LOGGING_SWITCH) {
              _logger.warning('⚠️ _handleCoinDeductionOnGameStart: Cannot get userId for player $playerSessionId, skipping coin deduction for this player');
            }
          }
        }
      }
      
      if (playerIds.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ _handleCoinDeductionOnGameStart: No valid user IDs found for coin deduction. Players: ${players.length}, User IDs found: 0');
        }
        // Don't return - log error but allow game to continue (backend should have validated coins already)
        return;
      }
      
      // Check if we got user IDs for all players
      if (playerIds.length < players.length) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ _handleCoinDeductionOnGameStart: Only found user IDs for ${playerIds.length} out of ${players.length} players. Some players may not have coins deducted.');
        }
      }
      
      _logger.info('💰 _handleCoinDeductionOnGameStart: Deducting coins for ${playerIds.length} player(s) out of ${players.length} total players', isOn: LOGGING_SWITCH);
      
      // Note: Backend will check each player's subscription_tier and skip deduction for promotional tier
      // We send all player IDs and let the backend handle the tier check per player
      // Use the coin_cost_per_player that was stored in game state (default: 25 coins)
      final requiredCoins = coinCost;
      final result = await DutchGameHelpers.deductGameCoins(
        coins: requiredCoins,
        gameId: gameId,
        playerIds: playerIds,
      );
      
      if (result != null && result['success'] == true) {
        // Mark coins as deducted for this game
        coinsDeductedGames.add(gameId);
        _updateMainGameState({
          'coinsDeductedGames': coinsDeductedGames.toList(),
        });
        
        final updatedPlayers = result['updated_players'] as List<dynamic>? ?? [];
        if (LOGGING_SWITCH) {
          _logger.info('✅ _handleCoinDeductionOnGameStart: Successfully deducted coins for game $gameId. Updated ${updatedPlayers.length} player(s)');
        }
        
        // Check if all players had coins deducted
        if (updatedPlayers.length < playerIds.length) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ _handleCoinDeductionOnGameStart: Only ${updatedPlayers.length} out of ${playerIds.length} players had coins deducted successfully');
          }
        }
      } else {
        final error = result?['error'] ?? 'Unknown error';
        if (LOGGING_SWITCH) {
          _logger.error('❌ _handleCoinDeductionOnGameStart: Failed to deduct coins: $error');
        }
        // Note: Game has already started, so we can't prevent it now
        // The coin check should have happened before game start, so this is a rare edge case
        // Log error for monitoring but allow game to continue
      }
      
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ _handleCoinDeductionOnGameStart: Error processing coin deduction: $e', error: e, stackTrace: stackTrace);
      }
    }
  }

  /// Handle dutch_error event
  static void handleDutchError(Map<String, dynamic> data) {
    final message = data['message']?.toString() ?? 'An error occurred';
    
    // Add session message about the error
    _addSessionMessage(
      level: 'error',
      title: 'Action Error',
      message: message,
      data: data,
    );
    
    // Update state with action error for UI display
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    StateManager().updateModuleState('dutch_game', {
      ...currentState,
      'actionError': {
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch Error: $message');
    }
  }
}
