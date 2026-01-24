/// Dutch Game Round Manager for Dutch Game
///
/// This class handles the actual gameplay rounds, turn management, and game logic
/// for dutch sessions, including turn rotation, card actions, and AI decision making.

import '../../utils/platform/shared_imports.dart';
import '../utils/rank_matcher.dart';
import 'utils/computer_player_factory.dart';
import 'game_state_callback.dart';
import '../services/game_registry.dart';

const bool LOGGING_SWITCH = false; // Enabled for timer-based delay system, miss chance testing, action data tracking, and YAML loading

class DutchGameRound {
  final Logger _logger = Logger();
  final GameStateCallback _stateCallback;
  final String _gameId;
  Timer? _sameRankTimer; // Timer for same rank window (5 seconds)
  Timer? _specialCardTimer; // Timer for special card window (10 seconds per card)
  Timer? _drawActionTimer; // Timer for draw action (applies to both human and CPU)
  Timer? _playActionTimer; // Timer for play action (applies to both human and CPU)
  
  // Unified counter for missed draw and play actions per player
  final Map<String, int> _missedActionCounts = {};
  
  // Computer player factory for YAML-based AI behavior
  ComputerPlayerFactory? _computerPlayerFactory;
  
  // Special card data storage - stores chronological list of special cards played
  // Matches backend's self.special_card_data list (game_round.py line 33)
  final List<Map<String, dynamic>> _specialCardData = [];
  
  // Working copy of special cards for processing (will remove as processed)
  // Matches backend's self.special_card_players list (game_round.py line 686)
  List<Map<String, dynamic>> _specialCardPlayers = [];
  
  // Flag to prevent multiple calls to _endSpecialCardsWindow() due to race conditions
  // When timer expires and jack swap completes simultaneously, both try to end the window
  bool _isEndingSpecialCardsWindow = false;
  
  // Winners list - stores winner information when game ends
  List<Map<String, dynamic>> _winnersList = [];
  
  // Final round caller - stores the player ID who called final round
  String? _finalRoundCaller;
  
  // Track which players have had their turn in the final round
  // Used to determine when final round is complete
  Set<String> _finalRoundPlayersCompleted = {};
  
  // Track if onGameEnded has already been called to prevent duplicate stats updates
  bool _gameEndedCallbackCalled = false;
  
  DutchGameRound(this._stateCallback, this._gameId);

  /// Helper method to clear action data from a specific player or all players
  /// [playerId] If provided, clears action for that player only. If null, clears for all players.
  /// [gamesMap] Optional games map to use instead of reading from state.
  void _clearPlayerAction({String? playerId, Map<String, dynamic>? gamesMap}) {
    try {
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      for (final p in players) {
        if (playerId == null || p['id']?.toString() == playerId) {
          final hadAction = p.containsKey('action');
          final actionType = p['action']?.toString();
          p.remove('action');
          p.remove('actionData');
          if (LOGGING_SWITCH && hadAction) {
            _logger.info('🎬 ACTION_DATA: Cleared action${playerId != null ? ' for player $playerId' : ' for all players'} - previous action: $actionType');
          };
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error clearing player action: $e');
      };
    }
  }

  /// Helper method to sanitize all players' drawnCard data to ID-only format before broadcasting
  /// This prevents opponents from seeing full card data when state updates are broadcast
  /// Should be called before any onGameStateChanged() that broadcasts to all players
  void _sanitizeDrawnCardsInGamesMap(Map<String, dynamic> gamesMap, {String? context}) {
    try {
      final gameData = gamesMap[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      for (final p in players) {
        if (p.containsKey('drawnCard') && p['drawnCard'] != null) {
          final pDrawnCard = p['drawnCard'] as Map<String, dynamic>?;
          if (pDrawnCard != null) {
            final rank = pDrawnCard['rank']?.toString() ?? 'null';
            final suit = pDrawnCard['suit']?.toString() ?? 'null';
            final isFullData = rank != '?' && suit != '?';
            
            if (isFullData) {
              final pId = p['id']?.toString() ?? 'unknown';
              p['drawnCard'] = {
                'cardId': pDrawnCard['cardId'],
                'suit': '?',
                'rank': '?',
                'points': 0,
              };
              if (LOGGING_SWITCH) {
                _logger.info('🔒 SECURITY: Sanitized player $pId drawnCard to ID-only before broadcast${context != null ? ' ($context)' : ''}');
              };
            }
          }
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error sanitizing drawnCards: $e');
      };
    }
  }

  /// Helper method to update player status in games map and broadcast via onGameStateChanged
  /// Replaces onPlayerStatusChanged to avoid redundant broadcasts
  void _updatePlayerStatusInGamesMap(String status, {String? playerId, Map<String, dynamic>? gamesMap}) {
    final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
    final gameId = _gameId;
    
    if (currentGames.containsKey(gameId)) {
      final gameData = currentGames[gameId] as Map<String, dynamic>;
      final gameDataInner = gameData['gameData'] as Map<String, dynamic>?;
      if (gameDataInner != null) {
        final gameStateData = gameDataInner['game_state'] as Map<String, dynamic>?;
        if (gameStateData != null) {
          final players = (gameStateData['players'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
          for (final p in players) {
            if (playerId == null || p['id'] == playerId) {
              p['status'] = status;
            }
          }
        }
      }
    }
    
    // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
    _sanitizeDrawnCardsInGamesMap(currentGames, context: 'update_player_status');
    
    // Broadcast the update with playerStatus in main state
    _stateCallback.onGameStateChanged({
      'games': currentGames,
      'playerStatus': status, // Update main state playerStatus
    });
  }
  
  /// Initialize the round with the current game state
  /// Replicates backend _initial_peek_timeout() and start_turn() logic
  Future<void> initializeRound() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ===== INITIALIZING ROUND FOR GAME $_gameId =====');
      };
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for round initialization');
        };
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Current game state - Players: ${players.length}, Current Player: ${currentPlayer?['name'] ?? 'None'}');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: All players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']}, status: ${p['status']})').join(', ')}');
      };
      
      // 1. Clear cards_to_peek for all players (peek phase is over)
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 1 - Clearing cards_to_peek for all players');
      };
      _clearPeekedCards(gameState);
      
      // 2. Set all players back to WAITING status
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 2 - Setting all players to WAITING status');
      };
      _setAllPlayersToWaiting(gameState);
      
      // 3. Initialize round state (replicates backend start_turn logic)
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 3 - Initializing round state');
      };
      _initializeRoundState(gameState);
      
      // 3.5. Pre-load computer player factory during initialization (safer - before gameplay starts)
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 3.5 - Pre-loading computer player factory');
      };
      await _ensureComputerFactory();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 3.5 - Computer player factory pre-loaded - factory is ${_computerPlayerFactory != null ? "initialized" : "NULL"}');
      };
      
      // 4. Start the first turn (this will set the current player to DRAWING_CARD status)
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Step 4 - Starting first turn (will select current player)');
      };
      _startNextTurn();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ===== ROUND INITIALIZATION COMPLETED SUCCESSFULLY =====');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to initialize round: $e');
      };
    }
  }

  /// Clear cards_to_peek for all players (replicates backend logic)
  void _clearPeekedCards(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      int clearedCount = 0;
      
      for (final player in players) {
        if (player['cardsToPeek'] != null && (player['cardsToPeek'] as List).isNotEmpty) {
          player['cardsToPeek'] = <Map<String, dynamic>>[];
          clearedCount++;
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Cleared cards_to_peek for $clearedCount players');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to clear peeked cards: $e');
      };
    }
  }

  /// Set all players to WAITING status (replicates backend logic)
  void _setAllPlayersToWaiting(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      for (final player in players) {
        player['status'] = 'waiting';
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Set ${players.length} players back to WAITING status');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to set players to waiting: $e');
      };
    }
  }

  /// Initialize round state (replicates backend start_turn logic)
  void _initializeRoundState(Map<String, dynamic> gameState) {
    try {
      // Clear same rank data (if exists)
      if (gameState.containsKey('sameRankData')) {
        gameState['sameRankData'] = <String, dynamic>{};
      }
      
      // Clear special card data (if exists)
      if (gameState.containsKey('specialCardData')) {
        gameState['specialCardData'] = <Map<String, dynamic>>[];
      }
      
      // Initialize round timing
      final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
      gameState['roundStartTime'] = currentTime;
      gameState['currentTurnStartTime'] = currentTime;
      gameState['roundStatus'] = 'active';
      gameState['actionsPerformed'] = <Map<String, dynamic>>[];
      
      // Set game phase to PLAYER_TURN (already set in matchStart, but ensure consistency)
      gameState['phase'] = 'player_turn';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Round state initialized - phase: player_turn, status: active');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to initialize round state: $e');
      };
    }
  }

  /// Determine if we should create a blank slot at the given index
  /// Replicates backend player.py _should_create_blank_slot_at_index() lines 203-218
  bool _shouldCreateBlankSlotAtIndex(List<dynamic> hand, int index) {
    // If index is 3 or less, always create a blank slot (maintain initial 4-card structure)
    if (index <= 3) {
      return true;
    }
    
    // For index 4 and beyond, only create blank slot if there are actual cards further up
    for (int i = index + 1; i < hand.length; i++) {
      if (hand[i] != null) {
        return true;
      }
    }
    
    // No actual cards beyond this index, so remove the card entirely
    return false;
  }

  
  /// Get the missed action count for a player
  int getMissedActionCount(String playerId) {
    return _missedActionCounts[playerId] ?? 0;
  }

  /// Handle when a player reaches the missed action threshold (2 missed actions)
  void _onMissedActionThresholdReached(String playerId) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Player $playerId has reached missed action threshold (2 missed actions)');
    };
    
    // Trigger auto-leave through GameStateCallback
    // The callback implementation will handle multiplayer vs practice distinction
    _stateCallback.triggerLeaveRoom(playerId);
  }
  
  /// Get the current game state from the callback
  Map<String, dynamic>? _getCurrentGameState() {
    try {
      return _stateCallback.getCurrentGameState();
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to get current game state: $e');
      };
      return null;
    }
  }

  /// Get current turn_events list
  /// Returns a copy of the current turn_events list
  List<Map<String, dynamic>> _getCurrentTurnEvents() {
    // Get current turn_events from callback (abstracts state access)
    return _stateCallback.getCurrentTurnEvents();
  }

  /// Create a turn event map
  Map<String, dynamic> _createTurnEvent(String cardId, String actionType) {
    return {
      'cardId': cardId,
      'actionType': actionType,
    };
  }

  /// Add a card to the discard pile
  /// 
  /// NOTE: This method does NOT trigger a state update. The caller is responsible
  /// for batching state updates that include both hand changes and discard pile changes
  /// to ensure widgets rebuild atomically and card position tracking works correctly.
  void _addToDiscardPile(Map<String, dynamic> card) {
    final gameState = _getCurrentGameState();
    if (gameState == null) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Cannot add to discard pile - game state is null');
      };
      return;
    }

    final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
    discardPile.add(card);
    gameState['discardPile'] = discardPile;
    
    // NOTE: State update is NOT triggered here - caller must batch updates
    // This ensures hand and discard pile changes are updated atomically
  }
  
  /// Start the next player's turn
  void _startNextTurn() {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Starting next turn...');
      };
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - ${_winnersList.length} winner(s) found. Preventing turn start.');
        };
        return;
      }
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for _startNextTurn');
        };
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // CRITICAL: Check main state's currentPlayer first (most up-to-date), then fall back to games map
      // This prevents stale state issues when currentPlayer is updated in previous turn
      final mainStateCurrentPlayer = _stateCallback.getMainStateCurrentPlayer();
      final gameStateCurrentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      // Use main state's currentPlayer if available, otherwise use games map
      final currentPlayer = mainStateCurrentPlayer ?? gameStateCurrentPlayer;
      final currentPlayerId = currentPlayer?['id']?.toString();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Current player ID: $currentPlayerId (from ${mainStateCurrentPlayer != null ? 'main state' : 'games map'})');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Available players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']})').join(', ')}');
      };
      
      // Find next player
      final nextPlayer = _getNextPlayer(players, currentPlayerId);
      if (nextPlayer == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: No next player found');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Selected next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})');
      };
      
      // Reset previous current player's status to waiting (if there was one)
      if (currentPlayerId != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Resetting previous current player $currentPlayerId to waiting status');
        };
        _updatePlayerStatusInGamesMap('waiting', playerId: currentPlayerId);
      }
      
      // Update current player in game state (in place for local use)
      gameState['currentPlayer'] = nextPlayer;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Updated game state currentPlayer to: ${nextPlayer['name']}');
      };
      
      // CRITICAL: Create reference to games map to update state
      // The modified gameState is already part of currentGames (in-place modification)
      // The state callback's change detection will handle this properly
      final currentGames = _stateCallback.currentGamesMap;
      
      // CRITICAL: Update currentPlayer in the games map
      // Navigate to game state and update currentPlayer
      final gameId = _gameId;
      if (currentGames.containsKey(gameId)) {
        final gameData = currentGames[gameId] as Map<String, dynamic>;
        final gameDataInner = gameData['gameData'] as Map<String, dynamic>?;
        if (gameDataInner != null) {
          final gameStateData = gameDataInner['game_state'] as Map<String, dynamic>?;
          if (gameStateData != null) {
            // Update currentPlayer in the games map structure
            gameStateData['currentPlayer'] = nextPlayer;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Updated currentPlayer in games map to: ${nextPlayer['name']}');
            };
          }
        }
      }
      
            // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
            _sanitizeDrawnCardsInGamesMap(currentGames, context: 'start_next_turn');
      
            // Clear turn_events for the new turn and update main state's currentPlayer field
            // This ensures handleDrawCardEvent can read the correct currentPlayer even if games map is stale
            _stateCallback.onGameStateChanged({
              'games': currentGames, // Modified games map with new currentPlayer (drawnCard sanitized)
              'currentPlayer': nextPlayer, // Also update main state's currentPlayer field for immediate access
              'turn_events': [], // Clear all turn events for new turn
            });
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Updated games map with new currentPlayer and cleared turn_events for new turn');
            };
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      // This matches backend behavior where first player status is DRAWING_CARD
      // CRITICAL: Pass currentGames to avoid reading stale state - the games map was just updated above
      _updatePlayerStatusInGamesMap('drawing_card', playerId: nextPlayer['id'], gamesMap: currentGames);
      
      // Cancel any existing action timers
      _cancelActionTimers();
      
      // Start draw timer for ALL players (human and CPU)
      // Note: CPU players will still use YAML delays for their actions, but timer acts as a safety timeout
      _startDrawActionTimer(nextPlayer['id']);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Computer player detected - triggering computer turn logic');
        };
        _initComputerTurn(gameState);
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Started turn for human player ${nextPlayer['name']} - status: drawing_card');
        };
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to start next turn: $e');
      };
    }
  }

  /// Initialize computer player turn logic
  /// This method will handle the complete computer player turn flow
  /// Uses declarative YAML configuration for computer behavior
  void _initComputerTurn(Map<String, dynamic> gameState) async {
    try {
      // Check if game has ended - if so, stop computer turn initialization
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - stopping computer turn initialization');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ===== INITIALIZING COMPUTER TURN =====');
      };
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: No current player found for computer turn');
        };
        return;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? 'unknown';
      final playerName = currentPlayer['name']?.toString() ?? 'Unknown';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Computer player $playerName ($playerId) starting turn');
      };
      
      // Initialize computer player factory if not already done
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: About to call _ensureComputerFactory()');
      };
      await _ensureComputerFactory();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: _ensureComputerFactory() completed - factory is ${_computerPlayerFactory != null ? "available" : "NULL"}');
      };
      
      // Get computer player difficulty from game state
      final difficulty = _getComputerDifficulty(gameState, playerId);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Computer player difficulty: $difficulty');
      };
      
      // Determine the current event/action needed
      final eventName = _getCurrentEventName(gameState, playerId);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Current event needed: $eventName');
      };
      
      // Use YAML-based computer player factory for decision making
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: About to call decision method - factory is ${_computerPlayerFactory != null ? "available" : "NULL"}');
      };
      if (_computerPlayerFactory != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Calling _handleComputerActionWithYAML()');
        };
        _handleComputerActionWithYAML(gameState, playerId, difficulty, eventName);
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: Computer player factory is NULL - using fallback _handleComputerAction()');
        };
        // Fallback to original logic if YAML not available
        _handleComputerAction(gameState, playerId, difficulty, eventName);
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _initComputerTurn: $e');
      };
    }
  }

  /// Ensure the YAML-based computer player factory is initialized
  Future<void> _ensureComputerFactory() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: _ensureComputerFactory() START - factory is ${_computerPlayerFactory != null ? "already initialized" : "NULL"}');
      }
      
      if (_computerPlayerFactory == null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Loading computer player config from $COMPUTER_PLAYER_CONFIG_PATH');
          _logger.info('Dutch: About to call ComputerPlayerFactory.fromFile()');
        }
        
        try {
          _computerPlayerFactory = await ComputerPlayerFactory.fromFile(COMPUTER_PLAYER_CONFIG_PATH);
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: ComputerPlayerFactory.fromFile() completed successfully');
            _logger.info('Dutch: Computer player factory initialized with YAML config');
          }
        } catch (e, stackTrace) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Failed to load computer player config, using default behavior: $e', error: e, stackTrace: stackTrace);
          }
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Computer player factory already initialized, skipping load');
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: _ensureComputerFactory() completed - factory is ${_computerPlayerFactory != null ? "initialized" : "NULL"}');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error ensuring computer factory: $e', error: e, stackTrace: stackTrace);
      }
    }
  }

  /// Get computer player difficulty from game state
  /// Maps player rank to YAML difficulty (easy, medium, hard, expert)
  String _getComputerDifficulty(Map<String, dynamic> gameState, String playerId) {
    try {
      // Get players list from game state
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Find the player by ID
      Map<String, dynamic>? player;
      try {
        player = players.firstWhere(
          (p) => p is Map<String, dynamic> && (p['id']?.toString() == playerId),
        ) as Map<String, dynamic>?;
      } catch (e) {
        // Player not found
        player = null;
      }
      
      if (player == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: Player $playerId not found in game state, using default difficulty');
        };
        return 'medium';
      }
      
      // Get player info for logging
      final playerName = player['name']?.toString() ?? playerId;
      final playerRank = player['rank']?.toString();
      final playerLevel = player['level']?.toString();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🎯 BEFORE YAML PARSING - Player: $playerName (ID: $playerId), Rank: $playerRank, Level: $playerLevel');
      };
      
      // Try to get difficulty directly (if already set)
      final difficulty = player['difficulty']?.toString();
      if (difficulty != null && difficulty.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: ✅ Using stored difficulty for player $playerName: $difficulty (from rank: $playerRank)');
        };
        return difficulty;
      }
      
      // If no difficulty, try to map from rank
      if (playerRank != null && playerRank.isNotEmpty) {
        final mappedDifficulty = RankMatcher.rankToDifficulty(playerRank);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: ✅ Mapped rank $playerRank to YAML difficulty $mappedDifficulty for player $playerName');
        };
        return mappedDifficulty;
      }
      
      // Fallback to default
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: ⚠️ No difficulty or rank found for player $playerName, using default difficulty: medium');
      };
      return 'medium';
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: ❌ Error getting computer difficulty: $e');
      };
      return 'medium';
    }
  }

  /// Determine what event/action the computer player needs to perform
  String _getCurrentEventName(Map<String, dynamic> gameState, String playerId) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      final playerStatus = player['status']?.toString() ?? 'unknown';
      
      // Map player status to event names (same as human players)
      switch (playerStatus) {
        case 'drawing_card':
          return 'draw_card';
        case 'playing_card':
          return 'play_card';
        case 'same_rank_window':
          return 'same_rank_play';
        case 'jack_swap':
          return 'jack_swap';
        case 'queen_peek':
          return 'queen_peek';
        default:
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Unknown player status for event mapping: $playerStatus');
          };
          return 'draw_card'; // Default to drawing a card
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error getting current event name: $e');
      };
      return 'draw_card';
    }
  }

  /// Handle computer action using YAML-based configuration
  /// This method uses the computer player factory to make decisions based on YAML config
  void _handleComputerActionWithYAML(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      // Check if game has ended - if so, stop handling computer actions
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - stopping computer action handling for event: $eventName');
        };
        return;
      }
      
      // Get player info for logging
      final players = gameState['players'] as List<dynamic>? ?? [];
      final computerPlayer = players.firstWhere(
        (p) => p['id']?.toString() == playerId,
        orElse: () => <String, dynamic>{},
      );
      final playerName = computerPlayer['name']?.toString() ?? playerId;
      final playerRank = computerPlayer['rank']?.toString() ?? 'unknown';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🎯 BEFORE YAML PARSING - Player: $playerName (ID: $playerId), Rank: $playerRank, Difficulty: $difficulty, Event: $eventName');
      };
      
      if (_computerPlayerFactory == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: ❌ Computer player factory not initialized');
        };
        _moveToNextPlayer();
        return;
      }
      
      // Get decision from YAML-based factory
      Map<String, dynamic> decision;
      switch (eventName) {
        case 'draw_card':
          decision = _computerPlayerFactory!.getDrawCardDecision(difficulty, gameState);
          break;
        case 'play_card':
          // Get available cards from current computer player's hand
          final players = gameState['players'] as List<dynamic>? ?? [];
          final computerPlayer = players.firstWhere(
            (p) => p['id'] == playerId,
            orElse: () => <String, dynamic>{},
          );
          final hand = computerPlayer['hand'] as List<dynamic>? ?? [];
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Computer player hand: $hand');
          };
          
          // Map hand to card IDs, filtering out null cards
          final availableCards = hand
              .where((card) => card != null) // Filter out null cards first
              .map((card) {
            if (card is Map<String, dynamic>) {
              final cardId = card['cardId']?.toString() ?? card['id']?.toString();
              return cardId ?? '';
            } else {
              final cardStr = card.toString();
              return cardStr == 'null' ? '' : cardStr;
            }
          })
              .where((cardId) => cardId.isNotEmpty) // Filter out empty strings (null conversions)
              .toList();
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Available cards after mapping (nulls filtered): $availableCards');
          };
          
          decision = _computerPlayerFactory!.getPlayCardDecision(difficulty, gameState, availableCards);
          break;
        case 'same_rank_play':
          // TODO: Get available cards from game state
          final availableCards = <String>[]; // Placeholder for now
          decision = _computerPlayerFactory!.getSameRankPlayDecision(difficulty, gameState, availableCards);
          break;
        case 'jack_swap':
          decision = _computerPlayerFactory!.getJackSwapDecision(difficulty, gameState, playerId);
          break;
        case 'queen_peek':
          decision = _computerPlayerFactory!.getQueenPeekDecision(difficulty, gameState, playerId);
          break;
        case 'collect_from_discard':
          decision = _computerPlayerFactory!.getCollectFromDiscardDecision(difficulty, gameState, playerId);
          break;
        default:
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Unknown event for computer action: $eventName');
          };
          _moveToNextPlayer();
          return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ✅ AFTER YAML PARSING - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, Decision: ${decision['action']}, Card: ${decision['card_id']}, Reasoning: ${decision['reasoning']}');
      };
      
      // Execute decision with delay from YAML config
      final delaySeconds = (decision['delay_seconds'] ?? 1.0).toDouble();
      Timer(Duration(milliseconds: (delaySeconds * 1000).round()), () async {
        await _executeComputerDecision(decision, playerId, eventName);
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _handleComputerActionWithYAML: $e');
      };
      _moveToNextPlayer();
    }
  }

  /// Execute computer player decision based on YAML configuration
  Future<void> _executeComputerDecision(Map<String, dynamic> decision, String playerId, String eventName) async {
    try {
      // Check if game has ended - if so, stop executing computer decisions
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - stopping computer decision execution for event: $eventName');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Executing computer decision: $decision');
      };
      
      switch (eventName) {
        case 'draw_card':
          final source = decision['source'] as String?;
          // Convert YAML source to handleDrawCard parameter
          final drawSource = source == 'discard' ? 'discard' : 'deck';
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Computer drawing from ${source == 'discard' ? 'discard pile' : 'deck'}');
          };
          
          // CRITICAL: Pass playerId to handleDrawCard to prevent stale state issues
          // This ensures the correct player draws, even if currentPlayer in games map is stale
          final success = await handleDrawCard(drawSource, playerId: playerId);
          if (!success) {
            if (LOGGING_SWITCH) {
              _logger.error('Dutch: Computer player $playerId failed to draw card');
            };
            _moveToNextPlayer();
          } else {
            // Check if game has ended before continuing to play_card action
            if (_isGameEnded()) {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Game has ended after draw - stopping computer turn progression');
              };
              return;
            }
            
            // After successful draw, continue computer turn with play_card action
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId successfully drew card, continuing with play_card action');
            };
            
            // Continue computer turn with play_card action (delay already handled by YAML config)
            final gameState = _getCurrentGameState();
            if (gameState != null) {
              final difficulty = _getComputerDifficulty(gameState, playerId);
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: DEBUG - About to call _handleComputerActionWithYAML for play_card');
              };
              _handleComputerActionWithYAML(gameState, playerId, difficulty, 'play_card');
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: DEBUG - _handleComputerActionWithYAML call completed');
              };
            } else {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: DEBUG - Game state is null, cannot continue with play_card');
              };
            }
          }
          break;
          
        case 'play_card':
          final missed = decision['missed'] as bool? ?? false;
          if (missed) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId missed play action (miss chance)');
            };
            // Increment missed action counter
            _missedActionCounts[playerId] = (_missedActionCounts[playerId] ?? 0) + 1;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Player $playerId missed action count: ${_missedActionCounts[playerId]}');
            };
            // Check if threshold reached (2 missed actions)
            if (_missedActionCounts[playerId] == 2) {
              _onMissedActionThresholdReached(playerId);
            }
            _moveToNextPlayer();
            break;
          }
          
          final cardId = decision['card_id'] as String?;
          if (cardId != null) {
            // CRITICAL: Pass playerId to handlePlayCard to prevent stale state issues
            // This ensures the correct player plays, even if currentPlayer in games map is stale
            final success = await handlePlayCard(cardId, playerId: playerId);
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed to play card');
              };
              _moveToNextPlayer();
            } else {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Computer player $playerId successfully played card');
              };
              // Note: Do NOT call _moveToNextPlayer() here
              // The same rank window (triggered in handlePlayCard) will handle moving to next player
              // Flow: _handleSameRankWindow() -> 5s timer -> _endSameRankWindow() -> _handleSpecialCardsWindow() -> _moveToNextPlayer()
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('Dutch: No card selected for computer play');
            };
            _moveToNextPlayer();
          }
          break;
          
        case 'same_rank_play':
          final missed = decision['missed'] as bool? ?? false;
          if (missed) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId missed same rank play (miss chance)');
            };
            // Move to next player (same rank window continues for other players)
            _moveToNextPlayer();
            break;
          }
          
          final shouldPlay = decision['play'] as bool? ?? false;
          if (shouldPlay) {
            final cardId = decision['card_id'] as String?;
            if (_isValidCardId(cardId) && cardId != null) {
              // cardId is guaranteed non-null after _isValidCardId check
              final success = await handleSameRankPlay(playerId, cardId);
              if (!success) {
                if (LOGGING_SWITCH) {
                  _logger.error('Dutch: Computer player $playerId failed same rank play');
                };
                _moveToNextPlayer();
              }
            } else {
              if (LOGGING_SWITCH) {
                _logger.warning('Dutch: No card selected for computer same rank play');
              };
              _moveToNextPlayer();
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer decided not to play same rank');
            };
            _moveToNextPlayer();
          }
          break;
          
        case 'jack_swap':
          final missed = decision['missed'] as bool? ?? false;
          if (missed) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId missed Jack swap (miss chance)');
            };
            // Reset status and move to next player
            _updatePlayerStatusInGamesMap('waiting', playerId: playerId);
            _moveToNextPlayer();
            break;
          }
          
          final shouldUse = decision['use'] as bool? ?? false;
          if (shouldUse) {
            final success = await handleJackSwap(
              firstCardId: decision['first_card_id'] as String? ?? 'placeholder_first_card',
              firstPlayerId: decision['first_player_id'] as String? ?? playerId,
              secondCardId: decision['second_card_id'] as String? ?? 'placeholder_second_card',
              secondPlayerId: decision['second_player_id'] as String? ?? 'placeholder_target_player',
            );
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed Jack swap');
              };
              // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer decided not to use Jack swap');
            };
            // Note: Timer will continue running and expire naturally - don't cancel it
          }
          break;
          
        case 'queen_peek':
          final missed = decision['missed'] as bool? ?? false;
          if (missed) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId missed Queen peek (miss chance)');
            };
            // Reset status and move to next player
            _updatePlayerStatusInGamesMap('waiting', playerId: playerId);
            _moveToNextPlayer();
            break;
          }
          
          final shouldUse = decision['use'] as bool? ?? false;
          if (shouldUse) {
            final success = await handleQueenPeek(
              peekingPlayerId: playerId,
              targetCardId: decision['target_card_id'] as String? ?? 'placeholder_target_card',
              targetPlayerId: decision['target_player_id'] as String? ?? 'placeholder_target_player',
            );
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed Queen peek');
              };
              // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer decided not to use Queen peek');
            };
            // Note: Timer will continue running and expire naturally - don't cancel it
          }
          break;
          
        case 'collect_from_discard':
          final missed = decision['missed'] as bool? ?? false;
          if (missed) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer player $playerId missed collect from discard (miss chance)');
            };
            // Move to next player (collection skipped)
            _moveToNextPlayer();
            break;
          }
          
          final shouldCollect = decision['collect'] as bool? ?? false;
          if (shouldCollect) {
            // DEBUG: Log the playerId being passed to handleCollectFromDiscard
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Executing collect_from_discard for playerId: $playerId, decision: $decision');
            };
            final success = await handleCollectFromDiscard(playerId);
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed to collect from discard');
              };
              // Note: No status change needed - player continues in current state
            } else {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Computer player $playerId successfully collected from discard');
              };
              // Note: No status change needed - player continues in current state
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Computer decided not to collect from discard');
            };
            // Note: No status change needed - player continues in current state
          }
          break;
          
        default:
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Unknown event for computer decision execution: $eventName');
          };
          _moveToNextPlayer();
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error executing computer decision: $e');
      };
      _moveToNextPlayer();
    }
  }

  /// Handle computer action using declarative YAML configuration
  void _handleComputerAction(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      // Check if game has ended - if so, stop handling computer actions
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - stopping fallback computer action handling for event: $eventName');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling computer action - Player: $playerId, Difficulty: $difficulty, Event: $eventName');
      };
      
      // TODO: Load and parse declarative YAML configuration
      // The YAML will define:
      // - Decision trees for each event type
      // - Difficulty-based behavior variations
      // - Card selection strategies
      // - Special card usage patterns
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Declarative YAML configuration will be implemented here');
      };
      
      // Wire directly to existing human player methods - computers perform the same actions
      switch (eventName) {
        case 'draw_card':
          // TODO: Use YAML to determine draw source (deck vs discard)
          Timer(const Duration(seconds: 1), () async {
            // CRITICAL: Pass playerId to handleDrawCard to prevent stale state issues
            final success = await handleDrawCard('deck', playerId: playerId);
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed to draw card');
              };
              _moveToNextPlayer();
            } else {
              // Check if game has ended before continuing to play_card action
              if (_isGameEnded()) {
                if (LOGGING_SWITCH) {
                  _logger.info('Dutch: Game has ended after draw - stopping fallback computer turn progression');
                };
                return;
              }
              
              // After successful draw, continue computer turn with play_card action
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Computer player $playerId successfully drew card, continuing with play_card action');
              };
              
              // Continue computer turn with play_card action (delay already handled by Timer above)
              final gameState = _getCurrentGameState();
              if (gameState != null) {
                // Try to use YAML-based method if factory is available, otherwise use fallback
                if (_computerPlayerFactory != null) {
                  final difficulty = _getComputerDifficulty(gameState, playerId);
                  if (LOGGING_SWITCH) {
                    _logger.info('Dutch: DEBUG - About to call _handleComputerActionWithYAML for play_card');
                  };
                  _handleComputerActionWithYAML(gameState, playerId, difficulty, 'play_card');
                } else {
                  // Fallback: continue with simple play logic
                  if (LOGGING_SWITCH) {
                    _logger.info('Dutch: DEBUG - Factory not available, using fallback play_card logic');
                  };
                  // Trigger play_card action in fallback
                  Timer(const Duration(seconds: 1), () async {
                    // Get available cards from player's hand
                    final players = gameState['players'] as List<dynamic>? ?? [];
                    final computerPlayer = players.firstWhere(
                      (p) => p['id'] == playerId,
                      orElse: () => <String, dynamic>{},
                    );
                    final hand = computerPlayer['hand'] as List<dynamic>? ?? [];
                    final availableCards = hand
                        .where((card) => card != null)
                        .map((card) {
                      if (card is Map<String, dynamic>) {
                        return card['cardId']?.toString() ?? card['id']?.toString() ?? '';
                      }
                      return card.toString() == 'null' ? '' : card.toString();
                    })
                        .where((cardId) => cardId.isNotEmpty)
                        .toList();
                    
                    if (availableCards.isNotEmpty) {
                      // Play the first available card as a simple fallback
                      final cardId = availableCards.first;
                      if (LOGGING_SWITCH) {
                        _logger.info('Dutch: Fallback - Playing card $cardId');
                      };
                      // CRITICAL: Pass playerId to handlePlayCard to prevent stale state issues
                      final success = await handlePlayCard(cardId, playerId: playerId);
                      if (!success) {
                        if (LOGGING_SWITCH) {
                          _logger.error('Dutch: Computer player $playerId failed to play card');
                        };
                        _moveToNextPlayer();
                      }
                    } else {
                      if (LOGGING_SWITCH) {
                        _logger.warning('Dutch: No cards available for computer player $playerId to play');
                      };
                      _moveToNextPlayer();
                    }
                  });
                }
              } else {
                if (LOGGING_SWITCH) {
                  _logger.error('Dutch: DEBUG - Game state is null, cannot continue with play_card');
                };
              }
            }
          });
          break;
        case 'play_card':
          // TODO: Use YAML to determine which card to play
          Timer(const Duration(seconds: 1), () async {
            // TODO: Get card ID from YAML configuration
            // For now, use a placeholder card ID
            // CRITICAL: Pass playerId to handlePlayCard to prevent stale state issues
            final success = await handlePlayCard('placeholder_card_id', playerId: playerId);
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed to play card');
              };
              _moveToNextPlayer();
            }
          });
          break;
        case 'same_rank_play':
          // TODO: Use YAML to determine same rank play decision
          Timer(const Duration(seconds: 1), () async {
            // TODO: Get card ID from YAML configuration
            // For now, use a placeholder card ID
            final success = await handleSameRankPlay(playerId, 'placeholder_card_id');
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed same rank play');
              };
              _moveToNextPlayer();
            }
          });
          break;
        case 'jack_swap':
          Timer(const Duration(seconds: 1), () async {
            // Fallback: Use placeholder targets (YAML-based flow should be used instead)
            final success = await handleJackSwap(
              firstCardId: 'placeholder_first_card',
              firstPlayerId: playerId,
              secondCardId: 'placeholder_second_card',
              secondPlayerId: 'placeholder_target_player',
            );
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed Jack swap');
              };
              _moveToNextPlayer();
            }
          });
          break;
        case 'queen_peek':
          Timer(const Duration(seconds: 1), () async {
            // Fallback: Use placeholder targets (YAML-based flow should be used instead)
            final success = await handleQueenPeek(
              peekingPlayerId: playerId,
              targetCardId: 'placeholder_target_card',
              targetPlayerId: 'placeholder_target_player',
            );
            if (!success) {
              if (LOGGING_SWITCH) {
                _logger.error('Dutch: Computer player $playerId failed Queen peek');
              };
              _moveToNextPlayer();
            }
          });
          break;
        default:
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Unknown event for computer action: $eventName');
          };
          _moveToNextPlayer();
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _handleComputerAction: $e');
      };
    }
  }

  
  /// Get the next player in rotation
  Map<String, dynamic>? _getNextPlayer(List<Map<String, dynamic>> players, String? currentPlayerId) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: _getNextPlayer called with currentPlayerId: $currentPlayerId');
    };
    
    if (players.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: No players available for _getNextPlayer');
      };
      return null;
    }
    
    if (currentPlayerId == null) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: No current player ID - this is the first turn');
      };
      
      // Check if this is practice mode (practice rooms start with "practice_room_")
      final isPracticeMode = _gameId.startsWith('practice_room_');
      
      if (isPracticeMode) {
        // Practice mode: always select the first opponent player (first non-human player)
        final firstOpponent = players.firstWhere(
          (p) => (p['isHuman'] as bool? ?? true) == false,
          orElse: () => <String, dynamic>{},
        );
        
        if (firstOpponent.isNotEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Practice mode - Selected first opponent as starting player: ${firstOpponent['name']} (${firstOpponent['id']}, isHuman: ${firstOpponent['isHuman']})');
          };
          // Check if computer players can collect from discard pile (first turn)
          _checkComputerPlayerCollectionFromDiscard();
          return firstOpponent;
        } else {
          // Fallback: if no opponent found, use first player
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Practice mode - No opponent player found, using first player as fallback: ${players.first['name']}');
          };
          _checkComputerPlayerCollectionFromDiscard();
          return players.first;
        }
      } else {
        // Regular multiplayer mode: randomly select any player (human or CPU)
      final random = Random();
      final randomIndex = random.nextInt(players.length);
      final randomPlayer = players[randomIndex];
      
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Multiplayer mode - Randomly selected starting player: ${randomPlayer['name']} (${randomPlayer['id']}, isHuman: ${randomPlayer['isHuman']})');
        };
      
      // Check if computer players can collect from discard pile (first turn)
      _checkComputerPlayerCollectionFromDiscard();
      
      return randomPlayer;
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Looking for current player with ID: $currentPlayerId');
    };
    
    // Find current player index
    final currentIndex = players.indexWhere((p) => p['id'] == currentPlayerId);
    if (currentIndex == -1) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: Current player $currentPlayerId not found in players list');
      };
      
      // Current player not found, find human player
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Setting human player as current: ${humanPlayer['name']} (${humanPlayer['id']})');
        };
        return humanPlayer;
      } else {
        // Fallback to first player
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: No human player found, using first player as fallback: ${players.first['name']}');
        };
        return players.first;
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Found current player at index $currentIndex: ${players[currentIndex]['name']}');
    };
    
    // Get next player (wrap around)
    final nextIndex = (currentIndex + 1) % players.length;
    final nextPlayer = players[nextIndex];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Next player index: $nextIndex, next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})');
    };
    
    return nextPlayer;
  }


  /// Handle drawing a card from the specified pile (replicates backend _handle_draw_from_pile)
  /// [playerId] - Optional player ID. If provided, uses this player directly instead of reading from currentPlayer.
  ///              This prevents stale state issues when currentPlayer in games map hasn't been updated yet.
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleDrawCard(String source, {String? playerId, Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling draw card from $source pile');
      };
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Invalid source for draw card: $source');
        };
        return false;
      }
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Game state is null for draw card');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleDrawCard using provided gamesMap (avoiding stale state read)');
        };
      }
      
      // Use provided playerId if available, otherwise read from currentPlayer
      String? actualPlayerId = playerId;
      if (actualPlayerId == null || actualPlayerId.isEmpty) {
        // Fallback to reading from currentPlayer (for backward compatibility with human player calls)
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: No current player found for draw card and no playerId provided');
          };
        return false;
      }
        actualPlayerId = currentPlayer['id']?.toString() ?? '';
      }
      
      if (actualPlayerId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Invalid playerId for draw card');
        };
        return false;
      }
      
      // Clear previous action data for this player
      _clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGames);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Drawing card for player $actualPlayerId from $source pile');
      };
      
      // Draw card based on source
      Map<String, dynamic>? drawnCard;
      
      if (source == 'deck') {
        // Draw from draw pile
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          // Draw pile is empty - reshuffle discard pile (except top card) into draw pile
          final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
          
          if (discardPile.length <= 1) {
            if (LOGGING_SWITCH) {
              _logger.error('Dutch: Cannot reshuffle - draw pile is empty and discard pile has ${discardPile.length} card(s)');
            };
            return false;
          }
          
          // Extract all cards except the last one (top card that's currently showing)
          final topCard = discardPile.last; // Keep this in discard pile
          final cardsToReshuffle = discardPile.sublist(0, discardPile.length - 1);
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Draw pile empty - reshuffling ${cardsToReshuffle.length} cards from discard pile (keeping top card: ${topCard['cardId']})');
          };
          
          // Convert full data cards to ID-only format (draw pile uses ID-only)
          final idOnlyCards = cardsToReshuffle.map((card) => <String, dynamic>{
            'cardId': card['cardId'],
            'suit': '?',      // Face-down: hide suit
            'rank': '?',      // Face-down: hide rank
            'points': 0,      // Face-down: hide points
          }).toList();
          
          // Shuffle the cards
          idOnlyCards.shuffle();
          
          // Add shuffled cards to draw pile
          drawPile.addAll(idOnlyCards);
          gameState['drawPile'] = drawPile;
          
          // Keep only the top card in discard pile
          gameState['discardPile'] = [topCard];
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Reshuffled ${idOnlyCards.length} cards into draw pile. Draw pile now has ${drawPile.length} cards, discard pile has 1 card');
          };
        }
        
        // Now draw from the (potentially reshuffled) draw pile
        // Re-fetch drawPile in case it was reshuffled above
        final currentDrawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (currentDrawPile.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Draw pile is empty after reshuffle check - cannot draw');
          };
          return false;
        }
        
        final idOnlyCard = currentDrawPile.removeLast(); // Remove last card (top of pile)
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Drew card ${idOnlyCard['cardId']} from draw pile');
        };
        
        // Update gameState with modified draw pile
        gameState['drawPile'] = currentDrawPile;
        
        // Convert ID-only card to full card data using the coordinator's method
        drawnCard = _stateCallback.getCardById(gameState, idOnlyCard['cardId']);
        if (drawnCard == null) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Failed to get full card data for ${idOnlyCard['cardId']}');
          };
          return false;
        }
        
        // Check if draw pile is now empty
        if (currentDrawPile.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Draw pile is now empty');
          };
        }
        
      } else if (source == 'discard') {
        // Take from discard pile
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        if (discardPile.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Cannot draw from empty discard pile');
          };
          return false;
        }
        
        drawnCard = discardPile.removeLast(); // Remove last card (top of pile)
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Drew card ${drawnCard['cardId']} from discard pile');
        };
      }
      
      if (drawnCard == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to draw card from $source pile');
        };
        return false;
      }
      
      // Get the current player's hand
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final playerIndex = players.indexWhere((p) => p['id'] == actualPlayerId);
      
      if (playerIndex == -1) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Player $actualPlayerId not found in players list');
        };
        return false;
      }
      
      final player = players[playerIndex];
      final hand = player['hand'] as List<dynamic>? ?? [];
      
      // Add card to player's hand as ID-only (player hands always store ID-only cards)
      // Backend replicates this in player.py add_card_to_hand method
      // Format matches dutch game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
      final idOnlyCard = {
        'cardId': drawnCard['cardId'],
        'suit': '?',      // Face-down: hide suit
        'rank': '?',      // Face-down: hide rank
        'points': 0,      // Face-down: hide points
      };
      
      // IMPORTANT: Drawn cards ALWAYS go to the end of the hand (not in blank slots)
      // This matches backend logic in player.py add_card_to_hand() lines 78-88
      // Blank slots are only filled by penalty cards, not drawn cards
      hand.add(idOnlyCard);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Added drawn card to end of hand (index ${hand.length - 1})');
      };
      
      // Log player state after drawing card
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === AFTER DRAW CARD for $actualPlayerId ===');
      };
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player hand: $handCardIds');
      };
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player known_cards: $knownCards');
      };
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank: $collectionRank');
      };
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank_cards: $collectionCardIds');
      };
      
      // TWO-STEP APPROACH: First broadcast ID-only drawnCard to all players,
      // then send full card details only to the drawing player
      final isHuman = player['isHuman'] as bool? ?? false;
      
      // STEP 1: Set drawnCard to ID-only for ALL players (including human) for initial broadcast
      // This shows all players that a card was drawn without revealing the card details
      final idOnlyDrawnCard = {
          'cardId': drawnCard['cardId'],
        'suit': '?',      // Hide suit
        'rank': '?',      // Hide rank
        'points': 0,      // Hide points
        };
      player['drawnCard'] = idOnlyDrawnCard;
      
      // Add action data for animation system
      player['action'] = 'drawn_card';
      player['actionData'] = {'cardId': drawnCard['cardId']};
      if (LOGGING_SWITCH) {
        _logger.info('🎬 ACTION_DATA: Set drawn_card action for player $actualPlayerId - cardId: ${drawnCard['cardId']}');
      };
      
      // For computer players, also add to known_cards (they need full data for logic)
      if (!isHuman) {
        final knownCardsRaw = player['known_cards'];
        Map<String, dynamic> knownCards;
        if (knownCardsRaw is Map) {
          knownCards = Map<String, dynamic>.from(knownCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
        } else {
          knownCards = {};
        }
        final playerIdKey = actualPlayerId;
        if (!knownCards.containsKey(playerIdKey)) {
          knownCards[playerIdKey] = {};
        }
        knownCards[playerIdKey][drawnCard['cardId']] = {
          'cardId': drawnCard['cardId'],
          'rank': drawnCard['rank'],
          'suit': drawnCard['suit'],
          'points': drawnCard['points'],
          'specialPower': drawnCard['specialPower'],
        };
        player['known_cards'] = knownCards;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Added drawn card ${drawnCard['cardId']} to computer player $actualPlayerId known_cards');
        };
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Added card ${drawnCard['cardId']} to player $actualPlayerId hand as ID-only');
      };
      
      // Debug: Log all cards in hand after adding drawn card
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Player hand after draw:');
      };
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card == null) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG -   Index $i: EMPTY SLOT (null)');
          };
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG -   Index $i: cardId=${card['cardId']}, hasFullData=${card.containsKey('rank')}');
          };
        }
      }
      
      // Add turn event for draw action
      final drawnCardId = drawnCard['cardId']?.toString() ?? '';
      final currentTurnEvents = _getCurrentTurnEvents();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Current turn_events before adding draw event: ${currentTurnEvents.length} events');
      };
      
      final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
        ..add(_createTurnEvent(drawnCardId, 'draw'));
      if (LOGGING_SWITCH) {
        _logger.info(
        'Dutch: Added turn event - cardId: $drawnCardId, actionType: draw, total events: ${turnEvents.length}',
      );
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Turn events being passed to onGameStateChanged: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      
      
      // STEP 1: Broadcast ID-only drawnCard to all players EXCEPT the drawing player
      // This shows other players that a card was drawn without revealing sensitive details
      // The drawing player will receive the complete update in STEP 2
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: STEP 1 - Broadcasting ID-only drawnCard to all players except $actualPlayerId');
      };
      if (source == 'discard') {
        final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        _stateCallback.broadcastGameStateExcept(actualPlayerId, {
          'games': currentGames, // Games map with ID-only drawnCard
          'discardPile': updatedDiscardPile, // Updated discard pile (card removed)
          'turn_events': turnEvents, // Add turn event for animation
        });
      } else {
        // Drawing from deck - only update games (discard pile unchanged)
        _stateCallback.broadcastGameStateExcept(actualPlayerId, {
          'games': currentGames, // Games map with ID-only drawnCard
          'turn_events': turnEvents, // Add turn event for animation
      });
      }
      
      // Cancel draw timer (draw action completed)
      _drawActionTimer?.cancel();
      _drawActionTimer = null;
      
      // STEP 2: If human player, send full card details ONLY to the drawing player
      // This ensures the drawing player receives only one complete state update
      if (isHuman) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: STEP 2 - Sending full drawnCard details to player $actualPlayerId only');
        };
        
        // Update player's drawnCard with full card data and status (player is a reference to the object in currentGames)
        player['drawnCard'] = drawnCard; // Full card data for human player
        player['status'] = 'playing_card'; // Update status to playing_card
        
        // Send full card details only to the drawing player
        // Note: currentGames already contains the updated player with full drawnCard and status
        _stateCallback.sendGameStateToPlayer(actualPlayerId, {
          'games': currentGames, // Games map with full drawnCard and updated status for this player
          'turn_events': turnEvents, // Include turn events
        });
        
        // Clear action immediately after state update is sent
        _clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGames);
      } else {
        // For computer players, update status in games map
        _updatePlayerStatusInGamesMap('playing_card', playerId: actualPlayerId);
        
        // Clear action immediately after status update (for CPU players)
        _clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGames);
      }
      
      // Start play timer for ALL players (human and CPU) if status is playing_card
      _startPlayActionTimer(actualPlayerId);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player $actualPlayerId status changed from drawing_card to playing_card');
      };
      
      // Log pile contents after successful draw
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === PILE CONTENTS AFTER DRAW ===');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Draw Pile Count: $drawPileCount');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Discard Pile Count: $discardPileCount');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Drawn Card: ${drawnCard['cardId']}');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ================================');
      };
      
      // Reset missed action counter on successful draw
      _missedActionCounts[actualPlayerId] = 0;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Reset missed action count for player $actualPlayerId (successful draw)');
      };
      
      return true;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error handling draw card: $e');
      };
      return false;
    }
  }

  /// Handle calling final round - player signals the final round of the game
  /// After final round is called, all players get one last turn, then game ends and winners are calculated
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleCallFinalRound(String playerId, {Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling call final round for player $playerId');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for call final round');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleCallFinalRound using provided gamesMap (avoiding stale state read)');
        };
      }
      
      // Check if game has ended - cannot call final round after game ends
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cannot call final round - game has ended');
        };
        
        _stateCallback.onActionError(
          'Cannot call final round - game has ended',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Check if final round has already been called
      if (_finalRoundCaller != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cannot call final round - already called by $_finalRoundCaller');
        };
        
        _stateCallback.onActionError(
          'Final round has already been called',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Validate player exists and is active
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final player = players.firstWhere(
        (p) => p['id']?.toString() == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Player $playerId not found in players list');
        };
        return false;
      }
      
      final isActive = player['isActive'] as bool? ?? true;
      if (!isActive) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cannot call final round - player $playerId is not active');
        };
        
        _stateCallback.onActionError(
          'Cannot call final round - player is not active',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Set final round caller
      _finalRoundCaller = playerId;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Final round called by player $playerId');
      };
      
      // Clear final round players completed set (will be populated as players complete their turns)
      _finalRoundPlayersCompleted.clear();
      
      // Mark the caller as having completed their turn (they called it after their turn)
      _finalRoundPlayersCompleted.add(playerId);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Marked caller $playerId as completed in final round');
      };
      
      // Update game state to indicate final round is active
      gameState['finalRoundCalledBy'] = playerId;
      gameState['finalRoundActive'] = true;
      
      // Update player's hasCalledFinalRound flag
      player['hasCalledFinalRound'] = true;
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGames, context: 'call_final_round');
      
      // Broadcast state update
      _stateCallback.onGameStateChanged({
        'games': currentGames, // Updated games map with final round info
        'finalRoundCalledBy': playerId,
        'finalRoundActive': true,
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Final round activated - all players will get one last turn');
      };
      
      // Check if all players have already completed their turn (e.g., single-player game or all players already had their turn)
      final activePlayers = players.where((p) => (p['isActive'] as bool? ?? true) == true).toList();  // Default to true if missing
      final activePlayerIds = activePlayers.map((p) => p['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Checking if final round should end immediately. Active players: ${activePlayerIds.length}, Completed: ${_finalRoundPlayersCompleted.length}');
      };
      
      // If all active players have completed their turn, end the game immediately
      if (_finalRoundPlayersCompleted.length >= activePlayerIds.length) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: All players have completed their turn in final round - ending game immediately');
        };
        _endFinalRoundAndCalculateWinners();
        return true;
      }
      
      return true;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error handling call final round: $e');
      };
      return false;
    }
  }

  /// Handle collecting card from discard pile if it matches player's collection rank
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleCollectFromDiscard(String playerId, {Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling collect from discard for player $playerId');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleCollectFromDiscard using provided gamesMap (avoiding stale state read)');
        };
      }
      
      // Check if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      if (!isClearAndCollect) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Collection disabled - isClearAndCollect is false');
        };
        _stateCallback.onActionError(
          'Collection is not enabled in this game mode',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        return false;
      }
      
      // Check if game has ended - prevent collection after game ends
      if (_isGameEnded()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cannot collect - game has ended');
        };
        
        _stateCallback.onActionError(
          'Cannot collect cards - game has ended',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Check if game is in restricted phases
      final gamePhase = gameState['gamePhase']?.toString() ?? 'unknown';
      if (gamePhase == 'same_rank_window' || gamePhase == 'initial_peek' || gamePhase == 'game_ended') {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cannot collect during $gamePhase phase');
        };
        
        // Show error message
        _stateCallback.onActionError(
          'Cannot collect cards during $gamePhase phase',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Get player
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // DEBUG: Log all players' IDs and collection card counts before finding the player
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Looking for playerId: $playerId in players list');
      };
      for (final p in players) {
        final pId = p['id']?.toString() ?? 'unknown';
        final pName = p['name']?.toString() ?? 'unknown';
        final pCollectionCards = p['collection_rank_cards'] as List<dynamic>? ?? [];
        final pCollectionRank = p['collection_rank']?.toString() ?? 'none';
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Player in state: $pName ($pId), collection_rank: $pCollectionRank, collection_cards: ${pCollectionCards.length}');
        };
      }
      
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Player $playerId not found');
        };
        return false;
      }
      
      // DEBUG: Verify we got the correct player
      final foundPlayerId = player['id']?.toString() ?? 'unknown';
      final foundPlayerName = player['name']?.toString() ?? 'unknown';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Found player: $foundPlayerName ($foundPlayerId) - matches requested playerId: ${foundPlayerId == playerId}');
      };
      
      // Get top card from discard pile
      final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      if (discardPile.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Discard pile is empty');
        };
        
        _stateCallback.onActionError(
          'Discard pile is empty',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      final topDiscardCard = discardPile.last;
      final topDiscardRank = topDiscardCard['rank']?.toString() ?? '';
      
      // Get player's collection rank
      final playerCollectionRank = player['collection_rank']?.toString() ?? '';
      
      // DEBUG: Log validation details
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Collect validation - Top discard rank: $topDiscardRank, Player collection rank: $playerCollectionRank, Collection cards count: ${collectionRankCards.length}');
      };
      
      // Check if player already has 4 collection cards (winning condition) - prevent collecting 5th card
      if (collectionRankCards.length >= 4) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player already has ${collectionRankCards.length} collection cards (4 is the maximum for winning) - cannot collect more');
        };
        
        _stateCallback.onActionError(
          'You already have 4 cards of your collection rank - cannot collect more',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // Check if ranks match
      if (topDiscardRank.toLowerCase() != playerCollectionRank.toLowerCase()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Card rank $topDiscardRank doesn\'t match collection rank $playerCollectionRank');
        };
        
        _stateCallback.onActionError(
          'You can only collect cards from the discard pile that match your collection rank',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // DEBUG: Log successful validation
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Collect validation passed - ranks match: $topDiscardRank == $playerCollectionRank');
      };
      
      // Get the card ID of the top discard card before removing it
      final topDiscardCardId = topDiscardCard['cardId']?.toString() ?? '';
      
      // Check if this card is already in the player's collection_rank_cards (shouldn't happen, but safety check)
      final existingCardIds = collectionRankCards.map((c) {
        if (c is Map<String, dynamic>) {
          return c['cardId']?.toString() ?? '';
        }
        return '';
      }).where((id) => id.isNotEmpty).toList();
      
      if (existingCardIds.contains(topDiscardCardId)) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: ERROR - Card $topDiscardCardId is already in player $playerId collection_rank_cards! Preventing duplicate collection.');
        };
        _stateCallback.onActionError(
          'Card is already in your collection',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        return false;
      }
      
      // SUCCESS - Remove card from discard pile
      final collectedCard = discardPile.removeLast();
      final collectedCardId = collectedCard['cardId']?.toString() ?? '';
      
      // Verify the card we removed matches what we expected
      if (collectedCardId != topDiscardCardId) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: ERROR - Card ID mismatch! Expected $topDiscardCardId but removed $collectedCardId from discard pile');
        };
        // This shouldn't happen, but if it does, we should still continue
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Collected card $collectedCardId from discard pile');
      };
      
      // Add to player's hand as ID-only (same format as regular hand cards)
      final hand = player['hand'] as List<dynamic>? ?? [];
      hand.add({
        'cardId': collectedCard['cardId'],
        'suit': '?',      // Face-down: hide suit
        'rank': '?',      // Face-down: hide rank
        'points': 0,      // Face-down: hide points
      });
      
      // Add to player's collection_rank_cards (full data)
      // Reuse collectionRankCards variable declared earlier for debug logging
      collectionRankCards.add(collectedCard); // Full card data
      
      // Update player's collection_rank to match the collected card's rank
      player['collection_rank'] = collectedCard['rank']?.toString() ?? 'unknown';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Added card to hand and collection_rank_cards');
      };
      
      // CRITICAL: Batch state update with both hand and discard pile changes
      // This ensures widgets rebuild atomically and card position tracking works correctly
      // The card is removed from discard pile and added to hand in a single atomic update
      // Use the games map we're working with (currentGames already has modifications)
      
      // Get updated discard pile from game state (card has been removed)
      final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      
      // Add turn event for collect action
      final currentTurnEvents = _getCurrentTurnEvents();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Current turn_events before adding collect event: ${currentTurnEvents.length} events');
      };
      
      final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
        ..add(_createTurnEvent(collectedCardId, 'collect'));
      if (LOGGING_SWITCH) {
        _logger.info(
        'Dutch: Added turn event - cardId: $collectedCardId, actionType: collect, total events: ${turnEvents.length}',
      );
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Turn events being passed to onGameStateChanged: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGames, context: 'collect_from_discard');
      
      _stateCallback.onGameStateChanged({
        'games': currentGames, // Includes updated player hand (card added, drawnCard sanitized)
        'discardPile': updatedDiscardPile,  // Updated discard pile (card removed)
        'turn_events': turnEvents, // Add turn event for animation
      });
      
      // Check if player now has four of a kind (all 4 collection cards for their rank)
      // This is a winning condition - only check if collection mode is enabled
      // Note: isClearAndCollect is already defined earlier in this method
      if (isClearAndCollect && collectionRankCards.length == 4) {
        final playerName = player['name']?.toString() ?? 'Unknown';
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName ($playerId) has collected all 4 cards of rank ${player['collection_rank']} - FOUR OF A KIND WIN!');
        };
        
        // Set all players to waiting status
        _updatePlayerStatusInGamesMap('waiting', playerId: null);
        
        // Add player to winners list
        _winnersList.add({
          'playerId': playerId,
          'playerName': playerName,
          'winType': 'four_of_a_kind',
        });
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Added player $playerName ($playerId) to winners list with winType: four_of_a_kind');
        };
        
        // Trigger game ending check
        _checkGameEnding();
      }
      
      return true;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error handling collect from discard: $e');
      };
      return false;
    }
  }

  /// Handle playing a card from the player's hand (replicates backend _handle_play_card)
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handlePlayCard(String cardId, {String? playerId, Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling play card: $cardId');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handlePlayCard using provided gamesMap (avoiding stale state read)');
        };
      }
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Game state is null for play card');
        };
        return false;
      }
      
      // Use provided playerId if available, otherwise read from currentPlayer
      String? actualPlayerId = playerId;
      if (actualPlayerId == null || actualPlayerId.isEmpty) {
        // Fallback to reading from currentPlayer (for backward compatibility with human player calls)
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: No current player found for play card and no playerId provided');
          };
        return false;
        }
        actualPlayerId = currentPlayer['id']?.toString() ?? '';
      }
      
      if (actualPlayerId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Invalid playerId for play card');
        };
        return false;
      }
      
      // Clear previous action data for this player
      _clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGames);
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player in the players list
      final player = players.firstWhere(
        (p) => p['id'] == actualPlayerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Player $actualPlayerId not found in players list');
        };
        return false;
      }
      
      // Find the card in the player's hand
      // Convert to a list that allows null values for blank slots
      final handRaw = player['hand'] as List<dynamic>? ?? [];
      final hand = List<dynamic>.from(handRaw); // Convert to mutable list to allow nulls
      Map<String, dynamic>? cardToPlay;
      int cardIndex = -1;
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == cardId) {
          cardToPlay = card;
          cardIndex = i;
          break;
        }
      }
      
      if (cardToPlay == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Card $cardId not found in player $playerId hand');
        };
        return false;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found card $cardId at index $cardIndex in player $playerId hand');
      };
      
      // Check if card is in player's collection_rank_cards (cannot be played) - only if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      if (isClearAndCollect) {
        final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        for (var collectionCard in collectionRankCards) {
          if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Card $cardId is a collection rank card and cannot be played');
            };
            
            // Show error message to user
            _stateCallback.onActionError(
              'This card is your collection rank and cannot be played. Choose another card.',
              data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
            );
            
            // CRITICAL: Restore player status to playing_card so they can retry
            _updatePlayerStatusInGamesMap('playing_card', playerId: playerId);
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Restored player $playerId status to playing_card after failed collection rank play');
            };
            
            return false;
          }
        }
      }
      
      // Handle drawn card repositioning BEFORE removing the played card
      final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
      
      // Check if we should create a blank slot or remove the card entirely
      bool shouldCreateBlankSlot;
      try {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: About to call _shouldCreateBlankSlotAtIndex for index $cardIndex, hand.length=${hand.length}');
        };
        shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: _shouldCreateBlankSlotAtIndex returned: $shouldCreateBlankSlot');
        };
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Error in _shouldCreateBlankSlotAtIndex: $e');
        };
        rethrow;
      }
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        try {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: About to set hand[$cardIndex] = null');
          };
          hand[cardIndex] = null;
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Created blank slot at index $cardIndex');
          };
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Error creating blank slot: $e');
          };
          rethrow;
        }
      } else {
        // Remove the card entirely and shift remaining cards
        try {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: About to removeAt($cardIndex)');
          };
          hand.removeAt(cardIndex);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Removed card entirely from index $cardIndex, shifted remaining cards');
          };
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Error removing card: $e');
          };
          rethrow;
        }
      }
      
      // Convert card to full data before adding to discard pile
      // The player's hand contains ID-only cards, but discard pile needs full card data
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: About to get full card data for $cardId');
      };
      final cardToPlayFullData = _stateCallback.getCardById(gameState, cardId);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Got full card data for $cardId');
      };
      if (cardToPlayFullData == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get full data for card $cardId');
        };
        return false;
      }
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Converted card $cardId to full data for discard pile');
      };
      
      // Update player's hand back to game state (hand list was modified with nulls)
      player['hand'] = hand;
      
      // Add action data for animation system (cardIndex captured before removal)
      player['action'] = 'play_card';
      player['actionData'] = {'cardIndex': cardIndex};
      if (LOGGING_SWITCH) {
        _logger.info('🎬 ACTION_DATA: Set play_card action for player $actualPlayerId - cardIndex: $cardIndex');
      };
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      _addToDiscardPile(cardToPlayFullData);
      
      // CRITICAL: Batch state update with both hand and discard pile changes
      // This ensures widgets rebuild atomically and card position tracking works correctly
      // Use the games map we're working with (currentGames already has modifications)
      final currentGamesForPlay = currentGames;
      final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      
      // Add turn events for play action and potential reposition
      final currentTurnEvents = _getCurrentTurnEvents();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Current turn_events before adding play event: ${currentTurnEvents.length} events');
      };
      
      final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
        ..add(_createTurnEvent(cardId, 'play'));
      
      // If drawn card is repositioned, also add reposition event
      if (drawnCard != null && drawnCard['cardId'] != cardId) {
        final drawnCardId = drawnCard['cardId']?.toString() ?? '';
        turnEvents.add(_createTurnEvent(drawnCardId, 'reposition'));
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Added reposition event for drawn card: $drawnCardId');
        };
      }
      
      if (LOGGING_SWITCH) {
        _logger.info(
        'Dutch: Added turn events - play: $cardId${drawnCard != null && drawnCard['cardId'] != cardId ? ', reposition: ${drawnCard['cardId']}' : ''}, total events: ${turnEvents.length}',
      );
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Turn events being passed to onGameStateChanged: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      // This prevents opponents from seeing full card data when a player plays a card
      // The games map may contain full drawnCard data from STEP 2 of draw action
      _sanitizeDrawnCardsInGamesMap(currentGamesForPlay, context: 'play_card');
      
      if (LOGGING_SWITCH) {
        _logger.info('🔍 STATE_UPDATE DEBUG - Sending state update at line 1629 with hand BEFORE reposition');
      };
      if (LOGGING_SWITCH) {
        _logger.info('🔍 STATE_UPDATE DEBUG - Hand at this point: ${hand.map((c) => c is Map ? c['cardId'] : c.toString()).toList()}');
      };
      if (LOGGING_SWITCH) {
        _logger.info('🔍 STATE_UPDATE DEBUG - Turn events: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      _stateCallback.onGameStateChanged({
        'games': currentGamesForPlay, // Games map with modifications (drawnCard sanitized)
        'discardPile': updatedDiscardPile, // Updated discard pile
        'turn_events': turnEvents, // Add turn events for animations
      });
      
      // Clear action immediately after state update is sent
      _clearPlayerAction(playerId: actualPlayerId, gamesMap: currentGamesForPlay);
      
      if (LOGGING_SWITCH) {
        _logger.info('🔍 STATE_UPDATE DEBUG - State update sent. Reposition will happen AFTER this and AFTER _handleSameRankWindow()');
      };
      
      // Log player state after playing card
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === AFTER PLAY CARD for $playerId ===');
      };
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player hand: $handCardIds');
      };
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player known_cards: $knownCards');
      };
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank: $collectionRank');
      };
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank_cards: $collectionCardIds');
      };
      
      // Log pile contents after successful play
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === PILE CONTENTS AFTER PLAY ===');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Draw Pile Count: $drawPileCount');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Discard Pile Count: $discardPileCount');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Played Card: ${cardToPlay['cardId']}');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ================================');
      };
      
      // Check if the played card has special powers (Jack/Queen)
      // Replicates backend flow: check special card FIRST (game_round.py line 989)
      _checkSpecialCard(actualPlayerId, {
        'cardId': cardId,
        'rank': cardToPlayFullData['rank'],
        'suit': cardToPlayFullData['suit']
      });

      // Then trigger same rank window (backend game_round.py line 487)
      // This allows other players to play cards of the same rank out-of-turn
      _handleSameRankWindow();

      // CRITICAL: Update known_cards BEFORE clearing drawnCard property
      // This ensures the just-drawn card detection logic can work properly
      updateKnownCards('play_card', actualPlayerId, [cardId]);
      
      // Check if player's hand is completely empty (including collection cards)
      // If empty, add player to winners list
      final finalHand = player['hand'] as List<dynamic>? ?? [];
      final isEmpty = finalHand.isEmpty || finalHand.every((card) => card == null);
      
      if (isEmpty) {
        final playerName = player['name']?.toString() ?? 'Unknown';
        _winnersList.add({
          'playerId': playerId,
          'playerName': playerName,
          'winType': 'empty_hand',
        });
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName ($playerId) has no cards left - added to winners list');
        };
      }
      
      // Handle drawn card repositioning with smart blank slot system
      // This must happen AFTER updateKnownCards so the detection logic can check drawnCard
      if (drawnCard != null && drawnCard['cardId'] != cardId) {
        // The drawn card should fill the blank slot left by the played card
        // The blank slot is at cardIndex (where the played card was)
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - Repositioning drawn card ${drawnCard['cardId']} to index $cardIndex');
        };
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - This happens AFTER state update at line 1529 and AFTER _handleSameRankWindow()');
        };
        
        // First, find and remove the drawn card from its original position
        int? originalIndex;
        for (int i = 0; i < hand.length; i++) {
          if (hand[i] != null && hand[i] is Map<String, dynamic> && hand[i]['cardId'] == drawnCard['cardId']) {
            originalIndex = i;
            break;
          }
        }
        
        if (originalIndex != null) {
          // Apply smart blank slot logic to the original position
          final shouldKeepOriginalSlot = _shouldCreateBlankSlotAtIndex(hand, originalIndex);
          
          if (shouldKeepOriginalSlot) {
            hand[originalIndex] = null;  // Create blank slot
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Created blank slot at original position $originalIndex');
            };
          } else {
            hand.removeAt(originalIndex);  // Remove entirely
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Removed card entirely from original position $originalIndex');
            };
            // Adjust target index if we removed a card before it
            if (originalIndex < cardIndex) {
              cardIndex -= 1;
            }
          }
        }
        
        // Place the drawn card in the blank slot left by the played card
        // IMPORTANT: Convert drawn card to ID-only data when placing in hand (same as backend)
        // Format matches dutch game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',      // Face-down: hide suit
          'rank': '?',      // Face-down: hide rank
          'points': 0,      // Face-down: hide points
        };
        
        // Apply smart blank slot logic to the target position
        final shouldPlaceInSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
        
        if (shouldPlaceInSlot) {
          // Place it in the blank slot left by the played card
          if (cardIndex < hand.length) {
            hand[cardIndex] = drawnCardIdOnly;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Placed drawn card in blank slot at index $cardIndex');
            };
          } else {
            hand.insert(cardIndex, drawnCardIdOnly);
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Inserted drawn card at index $cardIndex');
            };
          }
        } else {
          // The slot shouldn't exist, so append the drawn card to the end
          hand.add(drawnCardIdOnly);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Appended drawn card to end of hand (slot $cardIndex should not exist)');
          };
        }
        
        // Remove the drawn card property completely since it's no longer "drawn"
        // Using remove() instead of setting to null ensures the property doesn't exist at all
        // This prevents the UI from showing the card as glowing after reposition
        player.remove('drawnCard');
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Removed drawn card property after repositioning');
        };
        
        // Update player's hand back to game state (hand list was modified)
        player['hand'] = hand;
        
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - Hand updated with repositioned card. Hand now: ${hand.map((c) => c is Map ? c['cardId'] : c.toString()).toList()}');
        };
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - CRITICAL: This hand update is NOT sent in a state update! The repositioned hand exists only in memory.');
        };
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - The UI will only see the repositioned hand when the next state update includes the games map.');
        };
        
        // CRITICAL: Send a state update with the repositioned hand so the UI can see it immediately
        // This ensures the repositioned card is visible in the UI, not just in memory
        // Preserve turn_events so the reposition animation can still be triggered
        final currentTurnEventsForReposition = _getCurrentTurnEvents();
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - Sending state update with repositioned hand...');
        };
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - Preserving ${currentTurnEventsForReposition.length} turn_events for animation');
        };
        
        // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting reposition update
        // Even though drawnCard should be cleared at line 1752, defensive sanitization ensures no leaks
        _sanitizeDrawnCardsInGamesMap(currentGames, context: 'reposition');
        
        _stateCallback.onGameStateChanged({
          'games': currentGames, // Games map with repositioned hand (drawnCard sanitized)
          'turn_events': currentTurnEventsForReposition, // Preserve turn_events for reposition animation
        });
        if (LOGGING_SWITCH) {
          _logger.info('🔍 REPOSITION DEBUG - State update sent with repositioned hand and preserved turn_events');
        };
        
        // NOTE: Do NOT update status here - all players already have 'same_rank_window' status
        // set by _handleSameRankWindow() (called earlier). Updating to 'waiting' would overwrite
        // the correct status for the playing player.
        
      } else if (drawnCard != null && drawnCard['cardId'] == cardId) {
        // Remove the drawn card property completely since it's now in the discard pile
        // Using remove() instead of setting to null ensures the property doesn't exist at all
        player.remove('drawnCard');
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Removed drawn card property (played card was the drawn card)');
        };
        
        // NOTE: Do NOT update status here - all players already have 'same_rank_window' status
        // set by _handleSameRankWindow() (called earlier). Updating to 'waiting' would overwrite
        // the correct status for the playing player.
      }

      // Move to next player (simplified turn management for practice)
      // await _moveToNextPlayer();
      
      // Cancel action timers after successful play
      _playActionTimer?.cancel();
      _playActionTimer = null;
      _drawActionTimer?.cancel();
      _drawActionTimer = null;
      
      // Reset missed action count on successful play
      _missedActionCounts[actualPlayerId] = 0;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Reset missed action count for player $actualPlayerId (successful play)');
      };
      
      return true;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error handling play card: $e');
      };
      return false;
    }
  }

  /// Validate card ID is not null, empty, or the string 'null'
  bool _isValidCardId(String? cardId) {
    return cardId != null && cardId != 'null' && cardId.isNotEmpty;
  }

  /// Handle same rank play action - validates rank match and moves card to discard pile
  /// Replicates backend's _handle_same_rank_play method in game_round.py lines 1000-1089
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleSameRankPlay(String playerId, String cardId, {Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling same rank play for player $playerId, card $cardId');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      // Clear previous action data for this player
      _clearPlayerAction(playerId: playerId, gamesMap: currentGames);
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for same rank play');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleSameRankPlay using provided gamesMap (avoiding stale state read)');
        };
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Player $playerId not found for same rank play');
        };
        return false;
      }
      
      // Find the card in player's hand
      // Convert to a list that allows null values for blank slots
      final handRaw = player['hand'] as List<dynamic>? ?? [];
      final hand = List<dynamic>.from(handRaw); // Convert to mutable list to allow nulls
      Map<String, dynamic>? playedCard;
      int cardIndex = -1;
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == cardId) {
          playedCard = card;
          cardIndex = i;
          break;
        }
      }
      
      if (playedCard == null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Card $cardId not found in player $playerId hand for same rank play (likely already played by another player)');
        };
        return false;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found card $cardId for same rank play in player $playerId hand at index $cardIndex');
      };
      
      // Get full card data
      final playedCardFullData = _stateCallback.getCardById(gameState, cardId);
      if (playedCardFullData == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get full card data for $cardId');
        };
        return false;
      }
      
      final cardRank = playedCardFullData['rank']?.toString() ?? '';
      final cardSuit = playedCardFullData['suit']?.toString() ?? '';
      
      // Check if card is in player's collection_rank_cards (cannot be played for same rank) - only if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      if (isClearAndCollect) {
        final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        for (var collectionCard in collectionRankCards) {
          if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Card $cardId is a collection rank card and cannot be played for same rank');
            };
            
            // Show error message to user via actionError state
            _stateCallback.onActionError(
              'This card is in your collection and cannot be played for same rank.',
              data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
            );
            
            // No status change needed - status will change automatically when same rank window expires
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Collection rank card rejected - status will auto-expire with same rank window');
            };
            
            return false;
          }
        }
      }
      
      // Validate that this is actually a same rank play
      if (!_validateSameRankPlay(gameState, cardRank)) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Same rank validation failed for card $cardId with rank $cardRank (expected behavior - player forgot/wrong card)');
        };
        
        // Apply penalty: draw a card from the draw pile and add to player's hand
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Applying penalty for wrong same rank play - drawing card from draw pile');
        };
        
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        
        // Check if draw pile is empty and reshuffle if needed (same logic as regular draw)
        if (drawPile.isEmpty) {
          // Draw pile is empty - reshuffle discard pile (except top card) into draw pile
          if (discardPile.length <= 1) {
            if (LOGGING_SWITCH) {
              _logger.error('Dutch: Cannot apply penalty - draw pile is empty and discard pile has ${discardPile.length} card(s)');
            };
            return false;
          }
          
          // Keep the top card in discard pile, reshuffle the rest
          final topCard = discardPile.last;
          final cardsToReshuffle = discardPile.sublist(0, discardPile.length - 1);
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Draw pile empty during penalty - reshuffling ${cardsToReshuffle.length} cards from discard pile (keeping top card: ${topCard['cardId']})');
          };
          
          // Convert full card data to ID-only for reshuffled cards
          final idOnlyCards = cardsToReshuffle.map((card) => <String, dynamic>{
            'cardId': card['cardId'],
            'suit': '?',
            'rank': '?',
            'points': 0,
          }).toList();
          
          // Shuffle the cards
          idOnlyCards.shuffle();
          
          // Add shuffled cards to draw pile
          drawPile.addAll(idOnlyCards);
          
          // Keep only the top card in discard pile
          gameState['discardPile'] = [topCard];
          
          // Update game state with reshuffled draw pile
          gameState['drawPile'] = drawPile;
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Reshuffled ${idOnlyCards.length} cards into draw pile for penalty. Draw pile now has ${drawPile.length} cards, discard pile has 1 card');
          };
        }
        
        // Re-fetch drawPile in case it was reshuffled above
        final currentDrawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (currentDrawPile.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Draw pile is empty after reshuffle check - cannot apply penalty');
          };
          return false;
        }
        
        // Draw a card from the draw pile (remove last card)
        final penaltyCard = currentDrawPile.removeLast();
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Drew penalty card ${penaltyCard['cardId']} from draw pile');
        };
        
        // Add penalty card to player's hand as ID-only (same format as regular hand cards)
        // Format matches dutch game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
        final penaltyCardIdOnly = {
          'cardId': penaltyCard['cardId'],
          'suit': '?',      // Face-down: hide suit
          'rank': '?',      // Face-down: hide rank
          'points': 0,      // Face-down: hide points
        };
        
        hand.add(penaltyCardIdOnly);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Added penalty card ${penaltyCard['cardId']} to player $playerId hand as ID-only');
        };
        
        // CRITICAL: Persist changes to game state
        player['hand'] = hand;  // Update player's hand with the penalty card
        gameState['drawPile'] = currentDrawPile;  // Update draw pile after removing penalty card (may have been reshuffled)
        
        // Update player state to reflect the new hand and draw pile
        // CRITICAL: Pass currentGames to avoid reading stale state
        _updatePlayerStatusInGamesMap('waiting', playerId: playerId, gamesMap: currentGames);
        
        // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting penalty update
        _sanitizeDrawnCardsInGamesMap(currentGames, context: 'penalty_same_rank');
        
        // Broadcast the updated game state (hand and drawPile changes)
        // Use the games map we're working with (currentGames already has modifications, drawnCard sanitized)
        _stateCallback.onGameStateChanged({
          'games': currentGames,
        });
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Penalty applied successfully - player $playerId now has ${hand.length} cards');
        };
        
        // Return true since using penalty was handled successfully (expected gameplay, not an error)
        return true;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Same rank validation passed for card $cardId with rank $cardRank');
      };
      
      // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
      // Check if we should create a blank slot or remove the card entirely
      final shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        hand[cardIndex] = null;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Created blank slot at index $cardIndex for same rank play');
        };
      } else {
        // Remove the card entirely and shift remaining cards
        hand.removeAt(cardIndex);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Removed same rank card entirely from index $cardIndex');
        };
      }
      
      // Update player's hand back to game state (hand list was modified with nulls)
      player['hand'] = hand;
      
      // Add action data for animation system (cardIndex captured before removal)
      player['action'] = 'same_rank';
      player['actionData'] = {'cardIndex': cardIndex};
      if (LOGGING_SWITCH) {
        _logger.info('🎬 ACTION_DATA: Set same_rank action for player $playerId - cardIndex: $cardIndex');
      };
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      _addToDiscardPile(playedCardFullData);
      
      // CRITICAL: Batch state update with both hand and discard pile changes
      // This ensures widgets rebuild atomically and card position tracking works correctly
      // Use the games map we're working with (currentGames already has modifications)
      final currentGamesForSameRank = currentGames;
      final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      
      // Add turn event for same rank play (actionType is 'play' - same as regular play)
      final currentTurnEvents = _getCurrentTurnEvents();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Current turn_events before adding same rank play event: ${currentTurnEvents.length} events');
      };
      
      final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
        ..add(_createTurnEvent(cardId, 'play'));
      if (LOGGING_SWITCH) {
        _logger.info(
        'Dutch: Added turn event - cardId: $cardId, actionType: play (same rank), total events: ${turnEvents.length}',
      );
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Turn events being passed to onGameStateChanged: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGamesForSameRank, context: 'same_rank_play');
      
      _stateCallback.onGameStateChanged({
        'games': currentGamesForSameRank, // Games map with modifications (drawnCard sanitized)
        'discardPile': updatedDiscardPile, // Updated discard pile
        'turn_events': turnEvents, // Add turn event for animation
      });
      
      // Clear action immediately after state update is sent
      _clearPlayerAction(playerId: playerId, gamesMap: currentGamesForSameRank);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ✅ Same rank play successful: $playerId played $cardRank of $cardSuit - card moved to discard pile');
      };
      
      // Log player state after same rank play
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === AFTER SAME RANK PLAY for $playerId ===');
      };
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player hand: $handCardIds');
      };
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player known_cards: $knownCards');
      };
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank: $collectionRank');
      };
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank_cards: $collectionCardIds');
      };
      
      // Check for special cards (Jack/Queen) and store data if applicable
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': playedCardFullData['rank'],
        'suit': playedCardFullData['suit']
      });
      
      // TODO: Store the play in same_rank_data for tracking (future implementation)
      // For now, we just log the successful play
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Same rank play data would be stored here (future implementation)');
      };
      
      // Update all players' known_cards after successful same rank play
      updateKnownCards('same_rank_play', playerId, [cardId]);
      
      // Check if player's hand is completely empty (including collection cards)
      // If empty, add player to winners list
      final finalHand = player['hand'] as List<dynamic>? ?? [];
      final isEmpty = finalHand.isEmpty || finalHand.every((card) => card == null);
      
      if (isEmpty) {
        final playerName = player['name']?.toString() ?? 'Unknown';
        _winnersList.add({
          'playerId': playerId,
          'playerName': playerName,
          'winType': 'empty_hand',
        });
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName ($playerId) has no cards left - added to winners list');
        };
      }
      
      return true;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error handling same rank play: $e');
      };
      return false;
    }
  }

  /// Handle Jack swap action - swap two cards between players
  /// Replicates backend's _handle_jack_swap method in game_round.py lines 1199-1265
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleJackSwap({
    required String firstCardId,
    required String firstPlayerId,
    required String secondCardId,
    required String secondPlayerId,
    Map<String, dynamic>? gamesMap,
  }) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling Jack swap for cards: $firstCardId (player $firstPlayerId) <-> $secondCardId (player $secondPlayerId)');
      };

      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for Jack swap');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleJackSwap using provided gamesMap (avoiding stale state read)');
        };
      }

      // Clear previous action data for the acting player (currentPlayer who played the Jack)
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      final actingPlayerId = currentPlayer?['id']?.toString();
      if (actingPlayerId != null && actingPlayerId.isNotEmpty) {
        _clearPlayerAction(playerId: actingPlayerId, gamesMap: currentGames);
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Validate both players exist
      // Log all player IDs for debugging
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Validating jack swap players - firstPlayerId: $firstPlayerId (type: ${firstPlayerId.runtimeType}), secondPlayerId: $secondPlayerId (type: ${secondPlayerId.runtimeType})');
      };
      for (final p in players) {
        final pId = p['id'];
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player in state - name: ${p['name']}, id: $pId (type: ${pId.runtimeType}, toString: ${pId?.toString()})');
        };
      }
      
      // Try both direct comparison and toString comparison for robustness
      final firstPlayer = players.firstWhere(
        (p) {
          final pId = p['id'];
          return pId == firstPlayerId || pId?.toString() == firstPlayerId;
        },
        orElse: () => <String, dynamic>{},
      );

      final secondPlayer = players.firstWhere(
        (p) {
          final pId = p['id'];
          return pId == secondPlayerId || pId?.toString() == secondPlayerId;
        },
        orElse: () => <String, dynamic>{},
      );

      if (firstPlayer.isEmpty || secondPlayer.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Invalid Jack swap - one or both players not found. firstPlayerId: $firstPlayerId (found: ${firstPlayer.isNotEmpty}), secondPlayerId: $secondPlayerId (found: ${secondPlayer.isNotEmpty})');
        };
        return false;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Both players validated successfully - firstPlayer: ${firstPlayer['name']} (${firstPlayer['id']}), secondPlayer: ${secondPlayer['name']} (${secondPlayer['id']})');
      };

      // Get player hands
      final firstPlayerHand = firstPlayer['hand'] as List<dynamic>? ?? [];
      final secondPlayerHand = secondPlayer['hand'] as List<dynamic>? ?? [];

      // Find the cards in each player's hand
      Map<String, dynamic>? firstCard;
      int? firstCardIndex;
      Map<String, dynamic>? secondCard;
      int? secondCardIndex;

      // Find first card
      for (int i = 0; i < firstPlayerHand.length; i++) {
        final card = firstPlayerHand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == firstCardId) {
          firstCard = card;
          firstCardIndex = i;
          break;
        }
      }

      // Find second card
      for (int i = 0; i < secondPlayerHand.length; i++) {
        final card = secondPlayerHand[i];
        if (card != null && card is Map<String, dynamic> && card['cardId'] == secondCardId) {
          secondCard = card;
          secondCardIndex = i;
          break;
        }
      }

      // Validate cards found
      if (firstCard == null || secondCard == null || firstCardIndex == null || secondCardIndex == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Invalid Jack swap - one or both cards not found in players\' hands');
        };
        return false;
      }

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found cards - First card at index $firstCardIndex in player $firstPlayerId hand, Second card at index $secondCardIndex in player $secondPlayerId hand');
      };

      // Get full card data for both cards to ensure we have the correct cardId
      final firstCardFullData = _stateCallback.getCardById(gameState, firstCardId);
      final secondCardFullData = _stateCallback.getCardById(gameState, secondCardId);
      
      if (firstCardFullData == null || secondCardFullData == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get full card data for swap - firstCard: ${firstCardFullData != null}, secondCard: ${secondCardFullData != null}');
        };
        return false;
      }

      // Convert swapped cards to ID-only format (player hands always store ID-only cards)
      // Format matches dutch game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
      final firstCardIdOnly = {
        'cardId': firstCardFullData['cardId'],
        'suit': '?',      // Face-down: hide suit
        'rank': '?',      // Face-down: hide rank
        'points': 0,      // Face-down: hide points
      };
      
      final secondCardIdOnly = {
        'cardId': secondCardFullData['cardId'],
        'suit': '?',      // Face-down: hide suit
        'rank': '?',      // Face-down: hide rank
        'points': 0,      // Face-down: hide points
      };

      // Perform the swap with ID-only format
      firstPlayerHand[firstCardIndex] = secondCardIdOnly;
      secondPlayerHand[secondCardIndex] = firstCardIdOnly;
      
      // Add action data for animation system (only to the acting player - currentPlayer who played the Jack)
      // actingPlayerId was already determined earlier when clearing action
      if (actingPlayerId != null && actingPlayerId.isNotEmpty) {
        final actingPlayer = players.firstWhere(
          (p) => p['id']?.toString() == actingPlayerId,
          orElse: () => <String, dynamic>{},
        );
        
        if (actingPlayer.isNotEmpty) {
          actingPlayer['action'] = 'jack_swap';
          actingPlayer['actionData'] = {
            'card1': {'cardIndex': firstCardIndex, 'playerId': firstPlayerId},
            'card2': {'cardIndex': secondCardIndex, 'playerId': secondPlayerId},
          };
          if (LOGGING_SWITCH) {
            _logger.info('🎬 ACTION_DATA: Set jack_swap action for acting player $actingPlayerId - card1: index $firstCardIndex (player $firstPlayerId), card2: index $secondCardIndex (player $secondPlayerId)');
          };
        }
      }

      // Remove swapped cards from their original owner's collection_rank_cards - only if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      if (isClearAndCollect) {
        // Check if firstCardId is in firstPlayer's collection_rank_cards
        final firstPlayerCollectionCards = firstPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
        firstPlayerCollectionCards.removeWhere((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['cardId']?.toString() ?? '';
            if (cardId == firstCardId) {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Removed card $firstCardId from player $firstPlayerId collection_rank_cards (swapped out)');
              };
              return true;
            }
          }
          return false;
        });

        // Check if secondCardId is in secondPlayer's collection_rank_cards
        final secondPlayerCollectionCards = secondPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
        secondPlayerCollectionCards.removeWhere((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['cardId']?.toString() ?? '';
            if (cardId == secondCardId) {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Removed card $secondCardId from player $secondPlayerId collection_rank_cards (swapped out)');
              };
              return true;
            }
          }
          return false;
        });
      }

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Successfully swapped cards: $firstCardId <-> $secondCardId');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player $firstPlayerId now has card $secondCardId at index $firstCardIndex');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player $secondPlayerId now has card $firstCardId at index $secondCardIndex');
      };

      // Update game state to trigger UI updates
      // Use the games map we're working with (currentGames already has modifications)
      
      
      // Add turn events for jack swap (both cards are repositioned)
      final currentTurnEvents = _getCurrentTurnEvents();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Current turn_events before adding jack swap events: ${currentTurnEvents.length} events');
      };
      
      final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
        ..add(_createTurnEvent(firstCardId, 'reposition'))
        ..add(_createTurnEvent(secondCardId, 'reposition'));
      if (LOGGING_SWITCH) {
        _logger.info(
        'Dutch: Added turn events - jack swap: $firstCardId <-> $secondCardId (both reposition), total events: ${turnEvents.length}',
      );
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: 🔍 TURN_EVENTS DEBUG - Turn events being passed to onGameStateChanged: ${turnEvents.map((e) => '${e['cardId']}:${e['actionType']}').join(', ')}');
      };
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGames, context: 'jack_swap');
      
      _stateCallback.onGameStateChanged({
        'games': currentGames, // Games map with modifications (drawnCard sanitized)
        'turn_events': turnEvents, // Add turn events for animations
      });
      
      // Clear action immediately after state update is sent
      if (actingPlayerId != null && actingPlayerId.isNotEmpty) {
        _clearPlayerAction(playerId: actingPlayerId, gamesMap: currentGames);
      }

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Jack swap completed - state updated');
      };

      // Update all players' known_cards after successful Jack swap
      updateKnownCards('jack_swap', firstPlayerId, [firstCardId, secondCardId], swapData: {
        'sourcePlayerId': firstPlayerId,
        'targetPlayerId': secondPlayerId,
      });

      // Action completed successfully - cancel timer and move to next special card
      _specialCardTimer?.cancel();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Cancelled special card timer after Jack swap completion');
      };

      // Check if we're already ending the window (prevent race condition with timer expiration)
      if (_isEndingSpecialCardsWindow) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Special cards window is already ending - skipping processing after Jack swap');
        };
        return true;
      }

      // Set the current player's status to waiting
      // The player who completed the swap is the one in the first entry of _specialCardPlayers
      if (_specialCardPlayers.isNotEmpty) {
        final currentSpecialData = _specialCardPlayers[0];
        final currentPlayerId = currentSpecialData['player_id']?.toString();
        
        if (currentPlayerId != null && currentPlayerId.isNotEmpty) {
          // Set player status to waiting
          _updatePlayerStatusInGamesMap('waiting', playerId: currentPlayerId);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Player $currentPlayerId status set to waiting after Jack swap completion');
          };
          
          // Remove the processed card from the list
          _specialCardPlayers.removeAt(0);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}');
          };
        }
      }

      // Add 1-second delay for visual indication before processing next special card
      // This matches the behavior in _onSpecialCardTimerExpired and prevents the game
      // from appearing halted by immediately processing the next special card
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Waiting 1 second before processing next special card...');
      };
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });

      return true;

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in handleJackSwap: $e');
      };
      return false;
    }
  }

  /// Handle Queen peek action - peek at any one card from any player
  /// Replicates backend's _handle_queen_peek method in game_round.py lines 1267-1318
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<bool> handleQueenPeek({
    required String peekingPlayerId,
    required String targetCardId,
    required String targetPlayerId,
    Map<String, dynamic>? gamesMap,
  }) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Handling Queen peek - player $peekingPlayerId peeking at card $targetCardId from player $targetPlayerId');
      };

      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for Queen peek');
        };
        return false;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: handleQueenPeek using provided gamesMap (avoiding stale state read)');
        };
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Find the target player (card owner)
      final targetPlayer = players.firstWhere(
        (p) => p['id'] == targetPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (targetPlayer.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Target player $targetPlayerId not found for Queen peek');
        };
        return false;
      }

      // Find the peeking player (current player using Queen power)
      final peekingPlayer = players.firstWhere(
        (p) => p['id'] == peekingPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (peekingPlayer.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Peeking player $peekingPlayerId not found for Queen peek');
        };
        return false;
      }

      // Find the target card in the target player's hand OR drawnCard
      // Check drawnCard first (in case card was just drawn and not yet repositioned)
      Map<String, dynamic>? targetCard;
      int? targetCardIndex;
      final drawnCard = targetPlayer['drawnCard'] as Map<String, dynamic>?;
      if (drawnCard != null && drawnCard['cardId'] == targetCardId) {
        targetCard = drawnCard;
        // For drawnCard, use -1 as index (special marker for drawn card)
        targetCardIndex = -1;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Found target card in drawnCard: ${drawnCard['rank']} of ${drawnCard['suit']}');
        };
      }

      // If not found in drawnCard, search in hand
      if (targetCard == null) {
        final targetPlayerHand = targetPlayer['hand'] as List<dynamic>? ?? [];
        for (int i = 0; i < targetPlayerHand.length; i++) {
          final card = targetPlayerHand[i];
          if (card != null && card is Map<String, dynamic> && card['cardId'] == targetCardId) {
            targetCard = card;
            targetCardIndex = i;
            break;
          }
        }
      }

      if (targetCard == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Card $targetCardId not found in target player $targetPlayerId hand or drawnCard');
        };
        return false;
      }

      // Ensure targetCardIndex is set (default to -1 if it's a drawnCard)
      targetCardIndex ??= -1;

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found target card: ${targetCard['rank']} of ${targetCard['suit']} at index $targetCardIndex');
      };
      
      // Clear previous action data for the peeking player
      _clearPlayerAction(playerId: peekingPlayerId, gamesMap: currentGames);

      // Get full card data (convert from ID-only if needed)
      final fullCardData = _stateCallback.getCardById(gameState, targetCardId);
      if (fullCardData == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get full card data for $targetCardId');
        };
        return false;
      }

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Full card data: ${fullCardData['rank']} of ${fullCardData['suit']} (${fullCardData['points']} points)');
      };

      // Clear any existing cards_to_peek from previous peeks (backend line 1304)
      final existingCardsToPeek = peekingPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      existingCardsToPeek.clear();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Cleared existing cards_to_peek for player $peekingPlayerId');
      };

      // Set player status to PEEKING (backend line 1311)
      peekingPlayer['status'] = 'peeking';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Set player $peekingPlayerId status to peeking');
      };

      final isHuman = peekingPlayer['isHuman'] as bool? ?? false;

      // STEP 1: Set cardsToPeek to ID-only format and broadcast to all except peeking player
      final idOnlyCardToPeek = [{
        'cardId': targetCardId,
        'suit': '?',
        'rank': '?',
        'points': 0,
      }];
      peekingPlayer['cardsToPeek'] = idOnlyCardToPeek;
      
      _stateCallback.broadcastGameStateExcept(peekingPlayerId, {
        'games': currentGames,
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: STEP 1 - Broadcast ID-only cardsToPeek to all except player $peekingPlayerId');
      };

      // STEP 2: Set cardsToPeek to full card data and send only to peeking player
      peekingPlayer['cardsToPeek'] = [fullCardData];
      
      // Add action data for animation system (to the peeking player)
      peekingPlayer['action'] = 'queen_peek';
      peekingPlayer['actionData'] = {
        'cardIndex': targetCardIndex,
        'playerId': targetPlayerId,
      };
      if (LOGGING_SWITCH) {
        _logger.info('🎬 ACTION_DATA: Set queen_peek action for player $peekingPlayerId - cardIndex: $targetCardIndex, ownerPlayerId: $targetPlayerId');
      };
      
      if (isHuman) {
        // For human players, also update main state myCardsToPeek
        _stateCallback.sendGameStateToPlayer(peekingPlayerId, {
          'myCardsToPeek': [fullCardData],
          'games': currentGames,
        });
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: STEP 2 - Sent full cardsToPeek data to human player $peekingPlayerId only');
        };
      } else {
        // For computer players, just send games map update
        _stateCallback.sendGameStateToPlayer(peekingPlayerId, {
          'games': currentGames,
        });
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: STEP 2 - Sent full cardsToPeek data to computer player $peekingPlayerId only');
        };
      }
      
      // Clear action immediately after state update is sent
      _clearPlayerAction(playerId: peekingPlayerId, gamesMap: currentGames);

      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Queen peek completed successfully');
      };

      // Update all players' known_cards after successful Queen peek
      // This adds the peeked card to the peeking player's known_cards
      updateKnownCards('queen_peek', peekingPlayerId, [targetCardId], swapData: {
        'targetPlayerId': targetPlayerId,
      });

      return true;

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in handleQueenPeek: $e');
      };
      return false;
    }
  }

  /// Validate that the played card has the same rank as the last card in the discard pile
  /// Replicates backend's _validate_same_rank_play method in game_round.py lines 1091-1120
  bool _validateSameRankPlay(Map<String, dynamic> gameState, String cardRank) {
    try {
      // Check if there are any cards in the discard pile
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      
      if (discardPile.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Same rank validation failed: No cards in discard pile');
        };
        return false;
      }
      
      // Get the last card from the discard pile
      final lastCard = discardPile.last as Map<String, dynamic>?;
      if (lastCard == null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Same rank validation failed: Last card is null');
        };
        return false;
      }
      
      final lastCardRank = lastCard['rank']?.toString() ?? '';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Same rank validation: played_card_rank=\'$cardRank\', last_card_rank=\'$lastCardRank\'');
      };
      
      // During same rank window, cards must match the rank of the last played card
      // No special cases - the window is triggered by a played card, so there's always a rank to match
      if (cardRank.toLowerCase() == lastCardRank.toLowerCase()) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Same rank validation: Ranks match, allowing play');
        };
        return true;
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Same rank validation: Ranks don\'t match (played: $cardRank, required: $lastCardRank), denying play');
        };
        return false;
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Same rank validation error: $e');
      };
      return false;
    }
  }

  /// Check if a played card has special powers (Jack/Queen) and store data
  /// Replicates backend's _check_special_card method in game_round.py lines 1153-1197
  void _checkSpecialCard(String playerId, Map<String, dynamic> cardData) {
    try {
      final cardId = cardData['cardId']?.toString() ?? 'unknown';
      final cardRank = cardData['rank']?.toString().toLowerCase() ?? 'unknown';
      final cardSuit = cardData['suit']?.toString() ?? 'unknown';
      
      if (cardRank == 'jack') {
        // Store special card data chronologically (not grouped by player)
        final specialCardInfo = {
          'player_id': playerId,
          'card_id': cardId,
          'rank': cardRank,
          'suit': cardSuit,
          'special_power': 'jack_swap',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'description': 'Can switch any two cards between players'
        };
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG: special_card_data length before adding Jack: ${_specialCardData.length}');
        };
        _specialCardData.add(specialCardInfo);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG: special_card_data length after adding Jack: ${_specialCardData.length}');
        };
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Added Jack special card for player $playerId: $cardRank of $cardSuit (chronological order)');
        };
        
      } else if (cardRank == 'queen') {
        // Store special card data chronologically (not grouped by player)
        final specialCardInfo = {
          'player_id': playerId,
          'card_id': cardId,
          'rank': cardRank,
          'suit': cardSuit,
          'special_power': 'queen_peek',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          'description': 'Can look at one card from any player\'s hand'
        };
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG: special_card_data length before adding Queen: ${_specialCardData.length}');
        };
        _specialCardData.add(specialCardInfo);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG: special_card_data length after adding Queen: ${_specialCardData.length}');
        };
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Added Queen special card for player $playerId: $cardRank of $cardSuit (chronological order)');
        };
        
      } else {
        // Not a special card, no action needed
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Card $cardRank is not a special card');
        };
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _checkSpecialCard: $e');
      };
    }
  }

  /// Handle same rank window - sets all players to same_rank_window status
  /// Replicates backend's _handle_same_rank_window method in game_round.py lines 566-585
  void _handleSameRankWindow() {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Starting same rank window - setting all players to same_rank_window status');
      };
      
      // Update all players' status to same_rank_window
      _updatePlayerStatusInGamesMap('same_rank_window', playerId: null);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Successfully set all players to same_rank_window status');
      };
      // This ensures collection from discard pile is properly blocked during same rank window
      if (LOGGING_SWITCH) {
        _logger.info('🔍 SAME_RANK_WINDOW DEBUG - Sending state update with ONLY gamePhase, NO turn_events, NO games update');
      };
      _stateCallback.onGameStateChanged({
        'gamePhase': 'same_rank_window',
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Set gamePhase to same_rank_window');
      };
      if (LOGGING_SWITCH) {
        _logger.info('🔍 SAME_RANK_WINDOW DEBUG - This state update does NOT include the repositioned hand or turn_events');
      };
      
      // Start 5-second timer to automatically end same rank window
      // Matches backend behavior (game_round.py line 579)
      _startSameRankTimer();
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _handleSameRankWindow: $e');
      };
    }
  }

  /// Start a phase-based timer for the same rank window
  /// Replicates backend's _start_same_rank_timer method in game_round.py lines 587-597
  void _startSameRankTimer() {
    try {
      // Get timer duration from phase-based configuration
      final config = _stateCallback.getTimerConfig();
      final sameRankTimerDuration = config['turnTimeLimit'] as int? ?? 10;
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Starting ${sameRankTimerDuration}-second same rank window timer (phase-based)');
      };
      
      // Cancel existing timer if any
      _sameRankTimer?.cancel();
      
      // Store timer reference for potential cancellation
      _sameRankTimer = Timer(Duration(seconds: sameRankTimerDuration), () async {
        await _endSameRankWindow();
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error starting same rank timer: $e');
      };
    }
  }

  /// End the same rank window and move to next player
  /// Replicates backend's _end_same_rank_window method in game_round.py lines 599-643
  Future<void> _endSameRankWindow() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Ending same rank window - resetting all players to waiting status');
      };
      
      // TODO: Log same_rank_data if any players played matching cards (future implementation)
      // For now, we just log that window is ending
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: No same rank plays recorded (simplified dutch mode)');
      };
      
      // Update all players' status to WAITING
      _updatePlayerStatusInGamesMap('waiting', playerId: null);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Successfully reset all players to waiting status');
      };
      
      // CRITICAL: Reset gamePhase back to player_turn to match backend behavior
      // Backend transitions to ENDING_TURN phase (game_round.py line 634)
      // For dutch game, we use player_turn as the main gameplay phase
      _stateCallback.onGameStateChanged({
        'gamePhase': 'player_turn',
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Reset gamePhase to player_turn');
      };
      
      // CRITICAL: AWAIT computer same rank plays to complete BEFORE processing special cards
      // This ensures all queens played during same rank window are added to _specialCardData
      // before we start the special cards window
      // Get current games map to pass to avoid stale state
      final currentGamesForSameRank = _stateCallback.currentGamesMap;
      await _checkComputerPlayerSameRankPlays(gamesMap: currentGamesForSameRank);
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      // Winners might be added during same rank plays (empty hand win condition)
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - ${_winnersList.length} winner(s) found after same rank plays. Preventing further game progression.');
        };
        _checkGameEnding();
        return;
      }
      
      // Check if computer players can collect from discard pile
      // Rank matching is done in Dart, then YAML handles AI decision
      // Get current games map to pass to avoid stale state (may have been updated by same rank plays)
      final currentGamesForCollection = _stateCallback.currentGamesMap;
      await _checkComputerPlayerCollectionFromDiscard(gamesMap: currentGamesForCollection);
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      // Winners might be added during collection check (four of a kind win condition)
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - ${_winnersList.length} winner(s) found after collection check. Preventing further game progression.');
        };
        _checkGameEnding();
        return;
      }
      
      // Check for special cards and handle them (backend game_round.py line 640)
      // All same rank special cards are now in the list
      _handleSpecialCardsWindow();
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error ending same rank window: $e');
      };
    }
  }

  /// Check for same rank plays from computer players during the same rank window
  /// Returns a Future that completes when ALL computer same rank plays are done
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  Future<void> _checkComputerPlayerSameRankPlays({Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Processing computer player same rank plays');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      final currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Failed to get game state');
        };
        return;
      }
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: _checkComputerPlayerSameRankPlays using provided gamesMap (avoiding stale state read)');
        };
      }
      
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Get computer players
      final computerPlayers = players.where((p) => 
        p is Map<String, dynamic> && 
        p['isHuman'] == false &&
        p['isActive'] == true
      ).toList();
      
      if (computerPlayers.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: No computer players to process');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found ${computerPlayers.length} computer players');
      };
      
      // Debug: Log computer player details
      for (final player in computerPlayers) {
        final playerId = player['id']?.toString() ?? 'unknown';
        final playerName = player['name']?.toString() ?? 'Unknown';
        final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
        final hand = player['hand'] as List<dynamic>? ?? [];
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Computer player $playerName ($playerId) - hand: ${hand.length} cards, known_cards: ${knownCards.keys.length} players tracked');
        };
      }
      
      // Shuffle for random order
      computerPlayers.shuffle();
      
      // CRITICAL: Create list of futures for all computer plays
      // We must AWAIT all of them before continuing
      final playFutures = <Future<void>>[];
      
      // Process each computer player
      for (final computerPlayer in computerPlayers) {
        final playerId = computerPlayer['id']?.toString() ?? '';
        final difficulty = computerPlayer['difficulty']?.toString() ?? 'medium';
        
        // Add future to list (don't await yet)
        // Pass currentGames to _handleComputerSameRankPlay to avoid stale state
        playFutures.add(_handleComputerSameRankPlay(playerId, difficulty, currentGames));
      }
      
      // AWAIT all computer plays to complete
      await Future.wait(playFutures);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: All computer same rank plays completed');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _checkComputerPlayerSameRankPlays: $e');
      };
    }
  }

  /// Check if computer players can collect from discard pile
  /// Rank matching is done in Dart, then YAML handles AI decision (collect or not)
  /// After each collection, re-checks the top card and continues until no one can collect or decides not to collect
  /// [gamesMap] Optional games map to use instead of reading from state. Use this when called immediately after updating the games map to avoid stale state.
  ///            This function refreshes gamesMap in each loop iteration to get the latest state after collections.
  Future<void> _checkComputerPlayerCollectionFromDiscard({Map<String, dynamic>? gamesMap}) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Checking computer players for collection from discard pile');
      };
      
      // Use provided gamesMap if available (avoids stale state when called immediately after games map update)
      // Otherwise read from state
      Map<String, dynamic> currentGames = gamesMap ?? _stateCallback.currentGamesMap;
      
      if (gamesMap != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: _checkComputerPlayerCollectionFromDiscard using provided gamesMap (avoiding stale state read)');
        };
      }
      
      // Extract gameState from gamesMap
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      var gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Failed to get game state for collection check');
        };
        return;
      }
      
      // Check if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      if (!isClearAndCollect) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Collection disabled - skipping computer player collection check');
        };
        return;
      }
      
      // Get all players
      var players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Get computer players (isHuman == false and isActive == true)
      final computerPlayers = players.where((p) => 
        p['isHuman'] == false &&
        p['isActive'] == true
      ).toList();
      
      if (computerPlayers.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: No computer players to check for collection');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found ${computerPlayers.length} computer players to check');
      };
      
      // Shuffle computer players list to randomize the order
      computerPlayers.shuffle(Random());
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Shuffled computer players list for random collection order');
      };
      
      // Keep checking until no one can collect or decides not to collect
      // This handles cases where multiple cards of the same rank are in the discard pile (from same rank plays)
      bool continueChecking = true;
      int maxIterations = 100; // Safety limit to prevent infinite loops
      int iteration = 0;
      
      while (continueChecking && iteration < maxIterations) {
        iteration++;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Collection check iteration $iteration');
        };
        
        // CRITICAL: Refresh games map in each iteration to get updated state after collections
        // This prevents stale state reads when handleCollectFromDiscard updates the games map
        currentGames = _stateCallback.currentGamesMap;
        final refreshedGameData = currentGames[_gameId];
        final refreshedGameDataInner = refreshedGameData?['gameData'] as Map<String, dynamic>?;
        gameState = refreshedGameDataInner?['game_state'] as Map<String, dynamic>?;
        
        if (gameState == null) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Failed to get game state for collection check iteration');
          };
          continueChecking = false;
          break;
        }
        
        // Refresh players list to get updated player data (collection_rank_cards may have changed)
        players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
        
        // Refresh computer players list from updated players (maintain shuffled order by ID)
        final computerPlayerIds = computerPlayers.map((p) => p['id']?.toString() ?? '').toList();
        final refreshedComputerPlayers = <Map<String, dynamic>>[];
        for (final playerId in computerPlayerIds) {
          final player = players.firstWhere(
            (p) => p['id']?.toString() == playerId,
            orElse: () => <String, dynamic>{},
          );
          if (player.isNotEmpty && player['isHuman'] == false && player['isActive'] == true) {
            refreshedComputerPlayers.add(player);
          }
        }
        
        // Get discard pile - check if not empty
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        if (discardPile.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Discard pile is empty, stopping collection checks');
          };
          continueChecking = false;
          break;
        }
        
        // Get top discard card rank
        final topDiscardCard = discardPile.last;
        final topDiscardRank = topDiscardCard['rank']?.toString() ?? '';
        
        if (topDiscardRank.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Top discard card has no rank, stopping collection checks');
          };
          continueChecking = false;
          break;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Top discard card rank: $topDiscardRank');
        };
        
        // Find the first computer player (in shuffled order) whose collection rank matches the top discard card rank
        Map<String, dynamic>? matchingPlayer;
        for (final computerPlayer in refreshedComputerPlayers) {
          final playerCollectionRank = computerPlayer['collection_rank']?.toString() ?? '';
          
          // Compare with top discard card rank (case-insensitive) - DART LOGIC
          if (playerCollectionRank.toLowerCase() == topDiscardRank.toLowerCase()) {
            matchingPlayer = computerPlayer;
            break; // Found a matching player, stop searching
          }
        }
        
        // If no matching player found, stop checking
        if (matchingPlayer == null) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: No computer player has a collection rank matching $topDiscardRank, stopping collection checks');
          };
          continueChecking = false;
          break;
        }
        
        final playerId = matchingPlayer['id']?.toString() ?? '';
        final playerName = matchingPlayer['name']?.toString() ?? 'Unknown';
        final playerCollectionRank = matchingPlayer['collection_rank']?.toString() ?? '';
        final difficulty = matchingPlayer['difficulty']?.toString() ?? 'medium';
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Found matching player $playerName ($playerId) - collection rank: $playerCollectionRank');
        };
        
        // Get YAML decision (synchronous - decision is made immediately)
        if (_computerPlayerFactory == null) {
          if (LOGGING_SWITCH) {
            _logger.error('Dutch: Computer player factory not initialized');
          };
          continueChecking = false;
          break;
        }
        
        final decision = _computerPlayerFactory!.getCollectFromDiscardDecision(difficulty, gameState, playerId);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: YAML decision for $playerName: $decision');
        };
        
        // Check if player decided to collect
        final shouldCollect = decision['collect'] as bool? ?? false;
        
        if (!shouldCollect) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Player $playerName decided not to collect, stopping collection checks');
          };
          continueChecking = false;
          break;
        }
        
        // Player decided to collect - execute collection immediately (no delay for collection checks)
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName decided to collect, executing collection');
        };
        // Pass currentGames to handleCollectFromDiscard to avoid stale state
        final success = await handleCollectFromDiscard(playerId, gamesMap: currentGames);
        
        if (!success) {
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: Player $playerName failed to collect, stopping collection checks');
          };
          continueChecking = false;
          break;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName successfully collected, checking for more collection opportunities');
        };
        
        // After successful collection, refresh game state and continue checking
        // The loop will check the new top card on the next iteration
        // Small delay to allow state to update
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (iteration >= maxIterations) {
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: Reached max iterations ($maxIterations) in collection check loop, stopping');
        };
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Finished checking computer players for collection from discard pile');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _checkComputerPlayerCollectionFromDiscard: $e');
      };
    }
  }

  /// End the final round and calculate winners based on points
  /// Called when all players have completed their turn in the final round
  /// The final round caller (_finalRoundCaller) gets special tie-breaking logic
  void _endFinalRoundAndCalculateWinners() {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Ending final round and calculating winners. Final round caller: $_finalRoundCaller');
      };
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Cannot end final round - game state is null');
        };
        return;
      }
      
      final players = (gameState['players'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((p) => (p['isActive'] as bool? ?? true) == true)  // Default to true if missing
          .toList();
      
      if (players.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: No active players found for final round calculation');
        };
        return;
      }
      
      // Calculate points for all players
      final playerScores = <String, Map<String, dynamic>>{};
      for (final player in players) {
        final playerId = player['id']?.toString() ?? '';
        final playerName = player['name']?.toString() ?? 'Unknown';
        final hand = player['hand'] as List<dynamic>? ?? [];
        final points = _calculatePlayerPoints(player, gameState);
        final cardCount = hand.length;
        
        playerScores[playerId] = {
          'playerId': playerId,
          'playerName': playerName,
          'points': points,
          'cardCount': cardCount,
        };
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerName ($playerId) - Points: $points, Cards: $cardCount');
        };
      }
      
      // Find winners: lowest points wins, if tie then fewer cards, if still tie then final round caller wins
      final sortedPlayers = playerScores.values.toList()
        ..sort((a, b) {
          // First sort by points (ascending)
          final pointsDiff = (a['points'] as int) - (b['points'] as int);
          if (pointsDiff != 0) return pointsDiff;
          
          // If points are equal, sort by card count (ascending)
          final cardDiff = (a['cardCount'] as int) - (b['cardCount'] as int);
          if (cardDiff != 0) return cardDiff;
          
          // If still equal, final round caller wins
          final aId = a['playerId'] as String;
          final bId = b['playerId'] as String;
          if (aId == _finalRoundCaller) return -1; // a wins
          if (bId == _finalRoundCaller) return 1;  // b wins
          
          return 0; // No preference if neither is caller
        });
      
      // Get the best score (first in sorted list)
      if (sortedPlayers.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: No players to determine winner');
        };
        return;
      }
      
      final bestScore = sortedPlayers.first;
      final bestPoints = bestScore['points'] as int;
      final bestCardCount = bestScore['cardCount'] as int;
      
      // Find all players with the same best score (points and card count)
      final winners = sortedPlayers.where((p) => 
        (p['points'] as int) == bestPoints && 
        (p['cardCount'] as int) == bestCardCount
      ).toList();
      
      // Handle tie-breaking according to game rules:
      // - If points and cards tie: Final round caller wins if involved in tie
      // - Otherwise, it's a draw (all tied players win)
      if (winners.length > 1 && _finalRoundCaller != null) {
        // Check if final round caller is among the tied players
        final callerInTie = winners.any((w) => (w['playerId'] as String) == _finalRoundCaller);
        
        if (callerInTie) {
          // Final round caller is in the tie - they win
          final callerWinner = winners.firstWhere(
            (w) => (w['playerId'] as String) == _finalRoundCaller,
          );
          winners.clear();
          winners.add(callerWinner);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Tie broken - final round caller ${callerWinner['playerName']} wins (was involved in tie)');
          };
        } else {
          // Final round caller is NOT in the tie - it's a draw (all tied players win)
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Tie between ${winners.length} players, but final round caller is not involved - draw (all tied players win)');
          };
        }
      } else if (winners.length == 1) {
        // Single winner - no tie
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Single winner - ${winners.first['playerName']} with ${winners.first['points']} points and ${winners.first['cardCount']} cards');
        };
      }
      
      // Add all winners to winners list
      // Win reason is based on the winning condition (lowest points), not the game phase
      for (final winner in winners) {
        _winnersList.add({
          'playerId': winner['playerId'],
          'playerName': winner['playerName'],
          'winType': 'lowest_points',  // Win reason: lowest points (final round caller only matters for tie-breaking)
          'points': winner['points'],
          'cardCount': winner['cardCount'],
        });
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Final round winner - ${winner['playerName']} (${winner['playerId']}) - Points: ${winner['points']}, Cards: ${winner['cardCount']}, Win Type: lowest_points');
        };
      }
      
      // End the game
      _checkGameEnding();
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error ending final round and calculating winners: $e');
      };
    }
  }

  /// Check if the game should end (unified game ending check)
  /// This method checks for:
  /// 1. Empty hand win condition (player has no cards left)
  /// 2. Final round called (player called final round to end the game)
  /// 3. Final round completion (after final round is called)
  void _checkGameEnding() {
    try {
      // Prevent duplicate processing if onGameEnded has already been called
      if (_gameEndedCallbackCalled) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game ending callback already called, skipping duplicate processing');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Checking if game should end');
      };
      
      // Check if winners list contains any players - if so, game is over
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game is over - ${_winnersList.length} winner(s) found');
        };
        
        // Stop all active timers
        _sameRankTimer?.cancel();
        _sameRankTimer = null;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cancelled same rank timer');
        };
        
        _specialCardTimer?.cancel();
        _specialCardTimer = null;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Cancelled special card timer');
        };
        
        // Set all players to waiting status
        _updatePlayerStatusInGamesMap('waiting', playerId: null);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Set all players to waiting status');
        };
        
        // Update game phase to game_ended and include winners list (must match validator allowed values)
        _stateCallback.onGameStateChanged({
          'gamePhase': 'game_ended',
          'winners': List<Map<String, dynamic>>.from(_winnersList), // Send winners list to frontend
        });
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Set gamePhase to game_ended with ${_winnersList.length} winner(s) - all timers stopped and players set to waiting');
        };
        for (final winner in _winnersList) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Winner - ${winner['playerName']} (${winner['playerId']}) - Win Type: ${winner['winType']}');
          };
        }
        
        // Get all players from current game state for stats update
        final currentGameState = _getCurrentGameState();
        if (currentGameState != null) {
          final players = (currentGameState['players'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          
          // Get match_pot from game state (calculated at game start)
          // Pot is stored in game_state.match_pot (not gameData.match_pot)
          final gamesMap = _stateCallback.currentGamesMap;
          final gameData = gamesMap[_gameId] as Map<String, dynamic>?;
          final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
          final storedGameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
          final matchPot = storedGameState?['match_pot'] as int? ?? 0;
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Game ending - match_pot: $matchPot, winners: ${_winnersList.length}');
          };
          
          // Mark that onGameEnded has been called to prevent duplicate processing
          _gameEndedCallbackCalled = true;
          
          // Call onGameEnded callback to trigger stats update
          // Pass match_pot so it can be included in game_results for winner reward
          _stateCallback.onGameEnded(_winnersList, players, matchPot: matchPot);
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: No winners yet - game continues');
        };
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _checkGameEnding: $e');
      };
    }
  }
  
  /// Calculate total points for a player based on remaining cards
  /// Point calculation based on game rules:
  /// - Numbered Cards (2-10): Points equal to card number
  /// - Ace Cards: 1 point
  /// - Queens & Jacks: 10 points
  /// - Kings (All, including Red King): 10 points
  /// - Joker Cards: 0 points
  /// 
  /// Collection cards are averaged: sum of collection card points / number of collection cards
  /// The average is added once to the total, along with non-collection card points
  int _calculatePlayerPoints(Map<String, dynamic> player, Map<String, dynamic> gameState) {
    try {
      final hand = player['hand'] as List<dynamic>? ?? [];
      int totalPoints = 0;
      int collectionCardPoints = 0;
      int collectionCardCount = 0;
      int nonCollectionCardPoints = 0;
      
      // Get collection rank cards to identify collection cards in hand
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = <String>{};
      for (final collectionCard in collectionRankCards) {
        if (collectionCard is Map<String, dynamic>) {
          final cardId = collectionCard['cardId']?.toString();
          if (cardId != null && cardId.isNotEmpty) {
            collectionCardIds.add(cardId);
          }
        }
      }
      
      // Get original deck to look up full card data
      final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
      
      for (final card in hand) {
        if (card == null) continue; // Skip blank slots
        
        Map<String, dynamic>? fullCard;
        String? cardId;
        
        if (card is Map<String, dynamic>) {
          cardId = card['cardId']?.toString();
          if (cardId != null) {
            // Try to get full card data from original deck
            for (final deckCard in originalDeck) {
              if (deckCard is Map<String, dynamic> && deckCard['cardId']?.toString() == cardId) {
                fullCard = deckCard;
                break;
              }
            }
            // If not found in deck, use card data directly (might already have full data)
            fullCard ??= card;
          } else {
            fullCard = card;
          }
        }
        
        if (fullCard == null) continue;
        
        // Calculate card points
        int cardPoints = 0;
        
        // Get card points (may already be calculated)
        if (fullCard.containsKey('points')) {
          cardPoints = fullCard['points'] as int? ?? 0;
        } else {
          // Calculate points based on rank if not already set
          final rank = fullCard['rank']?.toString().toLowerCase() ?? '';
          
          if (rank == 'joker') {
            cardPoints = 0; // Jokers are 0 points
          } else if (rank == 'ace') {
            cardPoints = 1; // Ace is 1 point
          } else if (rank == 'queen' || rank == 'jack') {
            cardPoints = 10; // Queens and Jacks are 10 points
          } else if (rank == 'king') {
            cardPoints = 10; // All Kings (including Red King) are 10 points
          } else {
            // Numbered cards (2-10): points equal to card number
            final cardNumber = int.tryParse(rank);
            if (cardNumber != null && cardNumber >= 2 && cardNumber <= 10) {
              cardPoints = cardNumber;
            } else {
              if (LOGGING_SWITCH) {
                _logger.warning('Dutch: Unknown card rank for point calculation: $rank');
              };
              cardPoints = 0;
            }
          }
        }
        
        // Check if this card is a collection card
        if (cardId != null && collectionCardIds.contains(cardId)) {
          // This is a collection card - add to collection card points sum
          collectionCardPoints += cardPoints;
          collectionCardCount++;
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Collection card found in hand: $cardId, points: $cardPoints (total collection points: $collectionCardPoints, count: $collectionCardCount)');
          };
        } else {
          // This is a regular card - add to non-collection points
          nonCollectionCardPoints += cardPoints;
        }
      }
      
      // Calculate average of collection cards (if any)
      if (collectionCardCount > 0) {
        final collectionCardAverage = (collectionCardPoints / collectionCardCount).round();
        totalPoints = collectionCardAverage + nonCollectionCardPoints;
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Points calculation - Collection cards: $collectionCardPoints points / $collectionCardCount cards = $collectionCardAverage average, Non-collection: $nonCollectionCardPoints, Total: $totalPoints');
        };
      } else {
        // No collection cards, just use non-collection points
        totalPoints = nonCollectionCardPoints;
      }
      
      return totalPoints;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error calculating player points: $e');
      };
      return 0;
    }
  }

  /// Helper method to check if the game has ended
  /// Returns true if game phase is 'game_ended', false otherwise
  bool _isGameEnded() {
    try {
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        return false;
      }
      final gamePhase = gameState['gamePhase']?.toString() ?? '';
      return gamePhase == 'game_ended';
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error checking if game ended: $e');
      };
      return false;
    }
  }

  /// Handle computer player same rank play decision
  /// Returns a Future that completes when this player's same rank play is done
  /// [gamesMap] Games map to use. Extracts gameState from it to avoid stale state reads.
  Future<void> _handleComputerSameRankPlay(String playerId, String difficulty, Map<String, dynamic> gamesMap) async {
    try {
      // Ensure AI factory is available in this path too
      await _ensureComputerFactory();

      // Extract gameState from gamesMap
      final gameData = gamesMap[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for computer same rank play');
        };
        return;
      }

      // Get available same rank cards for this computer player
      final availableCards = _getAvailableSameRankCards(playerId, gameState);
      
      if (availableCards.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Computer player $playerId has no same rank cards');
        };
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Computer player $playerId has ${availableCards.length} available same rank cards');
      };
      
      // Get YAML decision
      if (_computerPlayerFactory == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: Computer factory not initialized; skipping same rank decision for $playerId');
        };
        return;
      }
      final Map<String, dynamic> decision = _computerPlayerFactory!
          .getSameRankPlayDecision(difficulty, gameState, availableCards);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Computer same rank decision: $decision');
      };
      
      // Execute decision with delay
      if (decision['play'] == true) {
        final delay = decision['delay_seconds'] as double? ?? 1.0;
        // Use delay directly from decision (already randomized in config)
        await Future.delayed(Duration(milliseconds: (delay * 1000).toInt()));
        
        String? cardId = decision['card_id'] as String?;
        // Fallback: pick first available valid card if decision card_id is invalid
        if (!_isValidCardId(cardId)) {
          cardId = availableCards.firstWhere(
            (id) => _isValidCardId(id),
            orElse: () => '',
          );
          if (!_isValidCardId(cardId)) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: No valid cardId for same rank after fallback; skipping play for $playerId');
            };
            return;
          }
        }
        if (_isValidCardId(cardId) && cardId != null) {
          // cardId is guaranteed non-null after _isValidCardId check
          await handleSameRankPlay(playerId, cardId);
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Computer player $playerId same rank play skipped - invalid card ID');
          };
        }
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _handleComputerSameRankPlay: $e');
      };
    }
  }

  /// Get available same rank cards from player's known_cards (excluding collection cards)
  List<String> _getAvailableSameRankCards(String playerId, Map<String, dynamic> gameState) {
    final availableCards = <String>[];
    
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Getting available same rank cards for player $playerId');
      };
      
      // Get discard pile to determine target rank
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      if (discardPile.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Discard pile is empty, no same rank cards possible');
        };
        return availableCards;
      }
      
      final lastCard = discardPile.last as Map<String, dynamic>?;
      final targetRank = lastCard?['rank']?.toString() ?? '';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Target rank for same rank play: $targetRank');
      };
      
      if (targetRank.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Target rank is empty, no same rank cards possible');
        };
        return availableCards;
      }
      
      // Get player
      final players = gameState['players'] as List<dynamic>? ?? [];
      final player = players.firstWhere(
        (p) => p is Map && p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>?;
      
      if (player == null || player.isEmpty) {
        return availableCards;
      }
      
      final hand = player['hand'] as List<dynamic>? ?? [];
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Player $playerId has ${hand.length} cards in hand');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Player $playerId known_cards structure: ${knownCards.keys.toList()}');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Player $playerId collection_rank_cards: ${collectionRankCards.length} cards');
      };
      
      // Get collection card IDs - only exclude collection cards if collection mode is enabled
      final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
      final collectionCardIds = isClearAndCollect
        ? collectionRankCards
            .map((c) => c is Map ? (c['cardId']?.toString() ?? '') : '')
            .where((id) => id.isNotEmpty)
            .toSet()
        : <String>{};
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Collection card IDs: ${collectionCardIds.toList()}');
      };
      
      // Get player's own known card IDs (card-ID-based structure)
      final knownCardIds = <String>{};
      final playerOwnKnownCardsRaw = knownCards[playerId];
      Map<String, dynamic>? playerOwnKnownCards;
      if (playerOwnKnownCardsRaw is Map) {
        playerOwnKnownCards = Map<String, dynamic>.from(playerOwnKnownCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
      }
      if (playerOwnKnownCards != null) {
        for (final cardId in playerOwnKnownCards.keys) {
          if (cardId.toString().isNotEmpty) {
            knownCardIds.add(cardId.toString());
          }
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Known card IDs: ${knownCardIds.toList()}');
      };
      
      // Find matching rank cards in hand
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Checking ${hand.length} cards in hand for matching rank $targetRank');
      };
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card == null || card is! Map<String, dynamic>) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Card at index $i is null or not a map, skipping');
          };
          continue;
        }
        
        final cardId = card['cardId']?.toString() ?? '';
        
        // CRITICAL: Get full card data to check rank (hand contains ID-only cards with rank=?)
        final fullCardData = _stateCallback.getCardById(gameState, cardId);
        if (fullCardData == null) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Failed to get full card data for $cardId, skipping');
          };
          continue;
        }
        
        final cardRank = fullCardData['rank']?.toString() ?? '';
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Card at index $i: id=$cardId, rank=$cardRank (from full data)');
        };
        
        if (cardRank != targetRank) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Card rank $cardRank != target rank $targetRank, skipping');
          };
          continue;
        }
        
        if (!knownCardIds.contains(cardId)) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Card $cardId not in known_cards, skipping');
          };
          continue;
        }
        
        if (collectionCardIds.contains(cardId)) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Card $cardId is a collection card, skipping');
          };
          continue;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Card $cardId is available for same rank play!');
        };
        availableCards.add(cardId);
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Found ${availableCards.length} available same rank cards: ${availableCards.toList()}');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _getAvailableSameRankCards: $e');
      };
    }
    
    return availableCards;
  }

  /// Handle special cards window - process each player's special card with 10-second timer
  /// Replicates backend's _handle_special_cards_window method in game_round.py lines 656-694
  void _handleSpecialCardsWindow() {
    try {
      // Check if we have any special cards played
      if (_specialCardData.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: No special cards played in this round - moving to next player');
        };
        // No special cards, go directly to next player
        _moveToNextPlayer();
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === SPECIAL CARDS WINDOW ===');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG: special_card_data length: ${_specialCardData.length}');
      };
      
      // Reset flag when starting new special cards window
      _isEndingSpecialCardsWindow = false;
      
      // CRITICAL: Set gamePhase to special_play_window to match Python backend behavior
      // This ensures same_rank_window phase is fully ended before special_play_window begins
      // Matches backend's phase transition at game_round.py line 1709
      _stateCallback.onGameStateChanged({
        'gamePhase': 'special_play_window',
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Game phase changed to special_play_window (special cards found)');
      };
      
      // Count total special cards (stored chronologically)
      final totalSpecialCards = _specialCardData.length;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Found $totalSpecialCards special cards played in chronological order');
      };
      
      // Log details of all special cards in chronological order
      for (int i = 0; i < _specialCardData.length; i++) {
        final card = _specialCardData[i];
        if (LOGGING_SWITCH) {
          _logger.info('Dutch:   ${i+1}. Player ${card['player_id']}: ${card['rank']} of ${card['suit']} (${card['special_power']})');
        };
      }
      
      // Create a working copy for processing (we'll remove cards as we process them)
      _specialCardPlayers = List<Map<String, dynamic>>.from(_specialCardData);
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Starting special card processing with ${_specialCardPlayers.length} cards');
      };
      
      // Start processing the first player's special card
      _processNextSpecialCard();
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _handleSpecialCardsWindow: $e');
      };
    }
  }

  /// Process the next player's special card with 10-second timer
  /// Replicates backend's _process_next_special_card method in game_round.py lines 696-739
  void _processNextSpecialCard() {
    try {
      // Check if we're already ending the window (prevent race condition)
      if (_isEndingSpecialCardsWindow) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Special cards window is already ending - skipping duplicate call');
        };
        return;
      }
      
      // Check if we've processed all special cards (list is empty)
      if (_specialCardPlayers.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: All special cards processed - moving to next player');
        };
        _endSpecialCardsWindow();
        return;
      }
      
      // Get the first special card data (chronological order)
      final specialData = _specialCardPlayers[0];
      final playerId = specialData['player_id']?.toString() ?? 'unknown';
      final cardRank = specialData['rank']?.toString() ?? 'unknown';
      final cardSuit = specialData['suit']?.toString() ?? 'unknown';
      final specialPower = specialData['special_power']?.toString() ?? 'unknown';
      final description = specialData['description']?.toString() ?? 'No description';
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Processing special card for player $playerId: $cardRank of $cardSuit');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch:   Special Power: $specialPower');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch:   Description: $description');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch:   Remaining cards to process: ${_specialCardPlayers.length}');
      };
      
      // Set player status based on special power
      if (specialPower == 'jack_swap') {
        _updatePlayerStatusInGamesMap('jack_swap', playerId: playerId);
      } else if (specialPower == 'queen_peek') {
        _updatePlayerStatusInGamesMap('queen_peek', playerId: playerId);
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('Dutch: Unknown special power: $specialPower for player $playerId');
        };
        // Remove this card and move to next
        _specialCardPlayers.removeAt(0);
        _processNextSpecialCard();
        return;
      }
      
      // Check if player is a computer player and trigger decision logic
      final gameState = _getCurrentGameState();
      if (gameState != null) {
        final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
        final player = players.firstWhere(
          (p) => p['id'] == playerId,
          orElse: () => <String, dynamic>{},
        );
        
        // Check if player is computer (isHuman == false)
        final isHuman = player['isHuman'] as bool? ?? true;
        if (!isHuman && specialPower == 'jack_swap') {
          // Get player's difficulty
          final difficulty = player['difficulty']?.toString() ?? 'medium';
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Computer player $playerId detected for jack_swap - triggering decision logic');
          };
          
          // Trigger computer decision logic
          _handleComputerActionWithYAML(gameState, playerId, difficulty, 'jack_swap');
        } else if (!isHuman && specialPower == 'queen_peek') {
          // Get player's difficulty
          final difficulty = player['difficulty']?.toString() ?? 'medium';
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Computer player $playerId detected for queen_peek - triggering decision logic');
          };
          
          // Trigger computer decision logic
          _handleComputerActionWithYAML(gameState, playerId, difficulty, 'queen_peek');
        }
      }
      
      // Get timer duration based on special power type directly (not from state, as state update may not be applied yet)
      // This prevents race condition where getTimerConfig() reads "waiting" status before "queen_peek"/"jack_swap" is applied
      // Use SSOT: ServerGameStateCallbackImpl.getAllTimerValues()
      final allTimerValues = ServerGameStateCallbackImpl.getAllTimerValues();
      int specialCardTimerDuration;
      if (specialPower == 'queen_peek') {
        specialCardTimerDuration = allTimerValues['queen_peek'] ?? 10; // queen_peek timer from SSOT
      } else if (specialPower == 'jack_swap') {
        specialCardTimerDuration = allTimerValues['jack_swap'] ?? 10; // jack_swap timer from SSOT
      } else {
        // Fallback: try to get from config, but use SSOT default as fallback
        final config = _stateCallback.getTimerConfig();
        specialCardTimerDuration = config['turnTimeLimit'] as int? ?? allTimerValues['default'] ?? 30;
      }
      
      // Start phase-based timer for this player's special card play
      _specialCardTimer?.cancel();
      _specialCardTimer = Timer(Duration(seconds: specialCardTimerDuration), () {
        _onSpecialCardTimerExpired();
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ${specialCardTimerDuration}-second timer started for player $playerId\'s $specialPower (phase-based, using direct specialPower value)');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _processNextSpecialCard: $e');
      };
    }
  }

  /// Called when the special card timer expires - move to next player or end window
  /// Replicates backend's _on_special_card_timer_expired method in game_round.py lines 741-766
  void _onSpecialCardTimerExpired() {
    try {
      // Check if we're already ending the window (prevent race condition with jack swap completion)
      if (_isEndingSpecialCardsWindow) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Special cards window is already ending - skipping timer expiration processing');
        };
        return;
      }
      
      // Reset current player's status to WAITING (if there are still cards to process)
      if (_specialCardPlayers.isNotEmpty) {
        final specialData = _specialCardPlayers[0];
        final playerId = specialData['player_id']?.toString() ?? 'unknown';
        
        // Clear cards_to_peek for Queen peek timer expiration
        final gameState = _getCurrentGameState();
        if (gameState != null) {
          final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
          final player = players.firstWhere(
            (p) => p['id'] == playerId,
            orElse: () => <String, dynamic>{},
          );
          
          if (player.isNotEmpty) {
            // Clear the player's cardsToPeek list (revert to ID-only cards)
            player['cardsToPeek'] = [];
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Cleared cardsToPeek for player $playerId - cards reverted to ID-only');
            };
            
            // Update main state for human player
            if (playerId == 'dutch_user') {
              _stateCallback.onGameStateChanged({
                'myCardsToPeek': [],
              });
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: Updated main state myCardsToPeek to empty list');
              };
            }
          }
        }
        
        _updatePlayerStatusInGamesMap('waiting', playerId: playerId);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Player $playerId special card timer expired - status reset to waiting');
        };
        
        // Remove the processed card from the list
        _specialCardPlayers.removeAt(0);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}');
        };
      }
      
      // Add 1-second delay for visual indication before processing next special card
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Waiting 1 second before processing next special card...');
      };
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _onSpecialCardTimerExpired: $e');
      };
    }
  }

  /// End the special cards window and move to next player
  /// Replicates backend's _end_special_cards_window method in game_round.py lines 768-789
  void _endSpecialCardsWindow() {
    try {
      // Prevent multiple calls to this method (race condition protection)
      if (_isEndingSpecialCardsWindow) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Special cards window is already ending - preventing duplicate call');
        };
        return;
      }
      
      // Set flag to prevent duplicate calls
      _isEndingSpecialCardsWindow = true;
      
      // Cancel any running timer
      _specialCardTimer?.cancel();
      
      // Clear special card data
      _specialCardData.clear();
      _specialCardPlayers.clear();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Special cards window ended - cleared all special card data');
      };
      
      // Check if any players have empty collection_rank_cards list after special plays
      // If empty, clear their collection_rank property (they can no longer collect cards)
      _checkAndClearEmptyCollectionRanks();
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - ${_winnersList.length} winner(s) found. Preventing game phase reset and player progression.');
        };
        return;
      }
      
      // CRITICAL: Reset gamePhase back to player_turn before moving to next player
      // This ensures clean phase transitions and matches backend behavior
      _stateCallback.onGameStateChanged({
        'gamePhase': 'player_turn',
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Game phase reset to player_turn after special cards window');
      };
      
      // Now move to the next player
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Moving to next player after special cards');
      };
      _moveToNextPlayer();
      
      // Reset flag after moving to next player (allows new special cards window to start)
      _isEndingSpecialCardsWindow = false;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _endSpecialCardsWindow: $e');
      };
      // Reset flag on error to prevent permanent lock
      _isEndingSpecialCardsWindow = false;
    }
  }

  /// Check if any players have empty collection_rank_cards list and clear collection_rank if so
  /// This should be called after special plays are completed (e.g., after Jack swap)
  void _checkAndClearEmptyCollectionRanks() {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Checking all players for empty collection_rank_cards');
      };
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Failed to get game state for collection rank check');
        };
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Check all players (human and PC)
      for (final player in players) {
        final playerId = player['id']?.toString() ?? '';
        final playerName = player['name']?.toString() ?? 'Unknown';
        final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        
        // Check if collection_rank_cards list is empty
        if (collectionRankCards.isEmpty) {
          final currentCollectionRank = player['collection_rank']?.toString() ?? '';
          
          // Only clear if collection_rank is set (not already empty/null)
          if (currentCollectionRank.isNotEmpty && currentCollectionRank != 'null') {
            player['collection_rank'] = null;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Cleared collection_rank for player $playerName ($playerId) - collection_rank_cards is empty');
            };
          }
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Finished checking all players for empty collection_rank_cards');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error in _checkAndClearEmptyCollectionRanks: $e');
      };
    }
  }

  /// Move to the next player (simplified version for practice)
  /// Public method to move to next player (called from leave_room handler when player is auto-removed)
  Future<void> moveToNextPlayer() async {
    await _moveToNextPlayer();
  }

  Future<void> _moveToNextPlayer() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Moving to next player (with 2 second delay)');
      };
      
      // Add 2 second delay before moving to next player
      await Future.delayed(const Duration(seconds: 2));
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Delay complete, proceeding with move to next player');
      };
      
      // Cancel all action timers at start of move to next player
      _cancelActionTimers();
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Game has ended - ${_winnersList.length} winner(s) found. Preventing game progression.');
        };
        return;
      }
      
      // Get current game state
      final gameState = _getCurrentGameState();
      
      if (gameState == null) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Game state is null for move to next player');
        };
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      // Check if final round is active and if we've completed it
      // This check happens BEFORE moving to next player, so currentPlayer is the one who just finished
      if (_finalRoundCaller != null && currentPlayer != null) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Final round is active (called by $_finalRoundCaller)');
        };
        
        // Mark the current player (who just finished their turn) as completed in final round
        final currentPlayerId = currentPlayer['id']?.toString() ?? '';
        if (currentPlayerId.isNotEmpty) {
          _finalRoundPlayersCompleted.add(currentPlayerId);
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Player $currentPlayerId completed their turn in final round. Completed: ${_finalRoundPlayersCompleted.length}');
          };
        }
        
        // Get all active players to check if final round is complete
        final activePlayers = players.where((p) => (p['isActive'] as bool? ?? true) == true).toList();  // Default to true if missing
        final activePlayerIds = activePlayers.map((p) => p['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
        
        // Check if all active players have completed their turn in the final round
        if (_finalRoundPlayersCompleted.length >= activePlayerIds.length) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Final round complete! All ${activePlayerIds.length} active players have had their turn. Ending game and calculating winners.');
          };
          
          // Final round is complete - end the game and calculate winners based on points
          // The caller (_finalRoundCaller) needs special logic during winner decision
          _endFinalRoundAndCalculateWinners();
          return;
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Final round in progress. ${_finalRoundPlayersCompleted.length}/${activePlayerIds.length} players completed.');
          };
        }
      }
      
      if (currentPlayer == null || players.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: No current player or players list for move to next player');
        };
        return;
      }
      
      // Set current player status to waiting before moving to next player
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      _updatePlayerStatusInGamesMap('waiting', playerId: currentPlayerId);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Set current player $currentPlayerId status to waiting');
      };
      
      // Find current player index
      int currentIndex = -1;
      for (int i = 0; i < players.length; i++) {
        if (players[i]['id'] == currentPlayerId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        if (LOGGING_SWITCH) {
          _logger.error('Dutch: Current player $currentPlayerId not found in players list');
        };
        return;
      }
      
      // Move to next player (or first if at end)
      final nextIndex = (currentIndex + 1) % players.length;
      final nextPlayer = players[nextIndex];
      final nextPlayerId = nextPlayer['id']?.toString() ?? '';
      
      // Update current player in game state
      gameState['currentPlayer'] = nextPlayer;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Updated game state currentPlayer to: ${nextPlayer['name']}');
      };
      
      // CRITICAL: Update currentPlayer in the games map before updating status
      // This ensures we read the correct currentPlayer
      final currentGames = _stateCallback.currentGamesMap;
      
      // Clear all players' action data when moving to next player
      _clearPlayerAction(gamesMap: currentGames);
      
      final gameId = _gameId;
      if (currentGames.containsKey(gameId)) {
        final gameData = currentGames[gameId] as Map<String, dynamic>;
        final gameDataInner = gameData['gameData'] as Map<String, dynamic>?;
        if (gameDataInner != null) {
          final gameStateData = gameDataInner['game_state'] as Map<String, dynamic>?;
          if (gameStateData != null) {
            gameStateData['currentPlayer'] = nextPlayer;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Updated currentPlayer in games map to: ${nextPlayer['name']}');
            };
          }
        }
      }
      
      // Update player status to drawing_card in the games map
      if (currentGames.containsKey(gameId)) {
        final gameData = currentGames[gameId] as Map<String, dynamic>;
        final gameDataInner = gameData['gameData'] as Map<String, dynamic>?;
        if (gameDataInner != null) {
          final gameStateData = gameDataInner['game_state'] as Map<String, dynamic>?;
          if (gameStateData != null) {
            final players = (gameStateData['players'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
            for (final p in players) {
              if (p['id'] == nextPlayerId) {
                p['status'] = 'drawing_card';
                break;
              }
            }
          }
        }
      }
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGames, context: 'start_next_turn');
      
      // CRITICAL: Update state with new currentPlayer and status
      _stateCallback.onGameStateChanged({
        'games': currentGames, // Modified games map with new currentPlayer and status (drawnCard sanitized)
        'currentPlayer': nextPlayer, // Also update main state's currentPlayer field for immediate access
        'playerStatus': 'drawing_card', // Update main state playerStatus
        'turn_events': [], // Clear all turn events for new turn
      });
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Updated games map with new currentPlayer, status, and cleared turn_events for new turn');
      };
      
      // Log player state at start of turn
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: === TURN START for $nextPlayerId ===');
      };
      final hand = nextPlayer['hand'] as List<dynamic>? ?? [];
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player hand: $handCardIds');
      };
      final knownCards = nextPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player known_cards: $knownCards');
      };
      final collectionRank = nextPlayer['collection_rank']?.toString() ?? 'none';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank: $collectionRank');
      };
      final collectionRankCards = nextPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCards.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Player collection_rank_cards: $collectionCardIds');
      };
      
      // Status already updated in games map above, no need for separate call
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Set next player ${nextPlayer['name']} to drawing_card status');
      };
      
      // Start draw timer for ALL players (human and CPU)
      // Note: CPU players will still use YAML delays for their actions, but timer acts as a safety timeout
      _startDrawActionTimer(nextPlayerId);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Computer player detected - triggering computer turn logic');
        };
        _initComputerTurn(gameState);
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Started turn for human player ${nextPlayer['name']} - status: drawing_card');
        };
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error moving to next player: $e');
      };
    }
  }

  /// Update all players' known_cards based on game events
  /// 
  /// This method is called after any card play action to maintain accurate
  /// knowledge tracking for all players (both human and computer).
  /// 
  /// [eventType]: Type of event ('play_card', 'same_rank_play', 'jack_swap')
  /// [actingPlayerId]: ID of the player who performed the action
  /// [affectedCardIds]: List of card IDs involved in the action
  /// [swapData]: Optional data for Jack swap (sourcePlayerId, targetPlayerId)
  void updateKnownCards(
    String eventType, 
    String actingPlayerId, 
    List<String> affectedCardIds,
    {Map<String, String>? swapData}
  ) {
    try {
      final currentGames = _stateCallback.currentGamesMap;
      final gameId = _gameId;
      if (!currentGames.containsKey(gameId)) return;
      
      final gameData = currentGames[gameId];
      final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
      if (gameState == null) return;
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the acting player to check their drawnCard
      final actingPlayer = players.firstWhere(
        (p) => p['id']?.toString() == actingPlayerId,
        orElse: () => <String, dynamic>{},
      );
      
      // Process each player's known_cards
      for (final player in players) {
        final difficulty = player['difficulty'] as String? ?? 'medium';
        
        // Get remember probability based on difficulty
        final rememberProb = _getRememberProbability(difficulty);
        
        // Get player's known_cards
        final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
        
        if (eventType == 'play_card' || eventType == 'same_rank_play') {
          _processPlayCardUpdate(knownCards, affectedCardIds, rememberProb, actingPlayerId, actingPlayer);
        } else if (eventType == 'jack_swap' && swapData != null) {
          _processJackSwapUpdate(knownCards, affectedCardIds, swapData, rememberProb);
        } else if (eventType == 'queen_peek' && swapData != null) {
          _processQueenPeekUpdate(knownCards, affectedCardIds, swapData, actingPlayerId);
        }
        
        player['known_cards'] = knownCards;
      }
      
      // 🔒 CRITICAL: Sanitize all players' drawnCard data to ID-only before broadcasting
      _sanitizeDrawnCardsInGamesMap(currentGames, context: 'update_known_cards');
      
      // Update state to trigger UI updates
      _stateCallback.onGameStateChanged({'games': currentGames});
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Updated known_cards for all players after $eventType');
      };
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Failed to update known_cards: $e');
      };
    }
  }

  /// Get remember probability based on difficulty
  double _getRememberProbability(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy': return 0.70;
      case 'medium': return 0.80;
      case 'hard': return 0.90;
      case 'expert': return 1.0;
      default: return 0.80;
    }
  }

  /// Process known_cards update for play_card or same_rank_play events
  void _processPlayCardUpdate(
    Map<String, dynamic> knownCards,
    List<String> affectedCardIds,
    double rememberProb,
    String actingPlayerId,
    Map<String, dynamic> actingPlayer
  ) {
    final random = Random();
    final playedCardId = affectedCardIds.isNotEmpty ? affectedCardIds[0] : null;
    if (playedCardId == null) return;
    
    // STEP 1: Check if acting player just drew this card - if so, remove immediately (100% certainty)
    final drawnCard = actingPlayer['drawnCard'] as Map<String, dynamic>?;
    final drawnCardId = drawnCard?['cardId']?.toString();
    final isJustDrawnCard = drawnCardId != null && drawnCardId == playedCardId;
    
    if (isJustDrawnCard && knownCards.containsKey(actingPlayerId)) {
      final actingPlayerCardsRaw = knownCards[actingPlayerId];
      if (actingPlayerCardsRaw is Map) {
        final actingPlayerCards = Map<String, dynamic>.from(actingPlayerCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
        actingPlayerCards.remove(playedCardId);
        
        // If acting player has no more tracked cards, remove the entry
        if (actingPlayerCards.isEmpty) {
          knownCards.remove(actingPlayerId);
        } else {
          knownCards[actingPlayerId] = actingPlayerCards;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Removed just-drawn card $playedCardId from $actingPlayerId known_cards (100% certainty)');
        };
      }
    }
    
    // STEP 2: Process all players' tracking with probability (including acting player if not just-drawn)
    // This handles:
    // - Acting player playing non-drawn cards (probability applies)
    // - Other players tracking the played card (probability applies)
    final keysToRemove = <String>[];
    for (final entry in knownCards.entries) {
      final trackedPlayerId = entry.key;
      final trackedCardsRaw = entry.value;
      final trackedCards = trackedCardsRaw is Map ? Map<String, dynamic>.from(trackedCardsRaw.map((k, v) => MapEntry(k.toString(), v))) : null;
      if (trackedCards == null) continue;
      
      // Skip if we already removed this card from acting player above
      if (trackedPlayerId == actingPlayerId && isJustDrawnCard) {
        continue;
      }
      
      // Check if the played card is in this player's known cards (card-ID-based structure)
      if (trackedCards.containsKey(playedCardId)) {
        // Roll probability: should this player remember the card was played?
        if (random.nextDouble() <= rememberProb) {
          // Remember: remove this card
          trackedCards.remove(playedCardId);
        }
        // Forget: do nothing, player "forgot" this card was played
      }
      
      // If no cards remain for this player, mark for removal
      if (trackedCards.isEmpty) {
        keysToRemove.add(trackedPlayerId);
      } else {
        knownCards[trackedPlayerId] = trackedCards;
      }
    }
    
    // Remove empty entries
    for (final key in keysToRemove) {
      knownCards.remove(key);
    }
  }

  /// Process known_cards update for jack_swap event
  void _processJackSwapUpdate(
    Map<String, dynamic> knownCards,
    List<String> affectedCardIds,
    Map<String, String> swapData,
    double rememberProb
  ) {
    final random = Random();
    if (affectedCardIds.length < 2) return;
    
    final cardId1 = affectedCardIds[0];
    final cardId2 = affectedCardIds[1];
    final sourcePlayerId = swapData['sourcePlayerId'];
    final targetPlayerId = swapData['targetPlayerId'];
    
    if (sourcePlayerId == null || targetPlayerId == null) return;
    
    // Track cards that need to be moved
    final cardsToMove = <String, Map<String, dynamic>>{};
    final keysToRemove = <String>[];
    
    // Iterate through each tracked player's cards
    for (final entry in knownCards.entries) {
      final trackedPlayerId = entry.key;
      final trackedCards = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
      if (trackedCards == null) continue;
      
      // Check if cardId1 is in this player's known cards
      if (trackedCards.containsKey(cardId1) && trackedPlayerId == sourcePlayerId) {
        if (random.nextDouble() <= rememberProb) {
          // Remember: this card moved to targetPlayerId
          final cardData = trackedCards.remove(cardId1);
          if (cardData != null) {
            if (!cardsToMove.containsKey(targetPlayerId)) {
              cardsToMove[targetPlayerId] = {};
            }
            cardsToMove[targetPlayerId]![cardId1] = cardData;
          }
        }
      }
      
      // Check if cardId2 is in this player's known cards
      if (trackedCards.containsKey(cardId2) && trackedPlayerId == targetPlayerId) {
        if (random.nextDouble() <= rememberProb) {
          // Remember: this card moved to sourcePlayerId
          final cardData = trackedCards.remove(cardId2);
          if (cardData != null) {
            if (!cardsToMove.containsKey(sourcePlayerId)) {
              cardsToMove[sourcePlayerId] = {};
            }
            cardsToMove[sourcePlayerId]![cardId2] = cardData;
          }
        }
      }
      
      // If no cards remain for this player, mark for removal
      if (trackedCards.isEmpty) {
        keysToRemove.add(trackedPlayerId);
      }
    }
    
    // Remove empty entries
    for (final key in keysToRemove) {
      knownCards.remove(key);
    }
    
    // Add moved cards to new owners
    for (final entry in cardsToMove.entries) {
      final newOwnerId = entry.key;
      final cardsToAdd = entry.value;
      
      if (!knownCards.containsKey(newOwnerId)) {
        knownCards[newOwnerId] = {};
      }
      
      final ownerCardsRaw = knownCards[newOwnerId];
      Map<String, dynamic> ownerCards;
      if (ownerCardsRaw is Map) {
        ownerCards = Map<String, dynamic>.from(ownerCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
      } else {
        ownerCards = {};
      }
      ownerCards.addAll(cardsToAdd);
      knownCards[newOwnerId] = ownerCards;
    }
  }

  /// Process known_cards update for queen_peek event
  void _processQueenPeekUpdate(
    Map<String, dynamic> knownCards,
    List<String> affectedCardIds,
    Map<String, String> swapData,
    String actingPlayerId,
  ) {
    if (affectedCardIds.isEmpty) return;
    
    final peekedCardId = affectedCardIds[0];
    final targetPlayerId = swapData['targetPlayerId'];
    
    if (targetPlayerId == null) return;
    
    // Get the game state to retrieve full card data
    final currentGames = _stateCallback.currentGamesMap;
    final gameId = _gameId;
    if (!currentGames.containsKey(gameId)) return;
    
    final gameData = currentGames[gameId];
    final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
    if (gameState == null) return;
    
    // Get full card data for the peeked card
    final fullCardData = _stateCallback.getCardById(gameState, peekedCardId);
    if (fullCardData == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: Failed to get full card data for peeked card $peekedCardId');
      };
      return;
    }
    
    // Add the peeked card to the peeking player's known_cards
    // actingPlayerId is the peeking player
    if (!knownCards.containsKey(actingPlayerId)) {
      knownCards[actingPlayerId] = <String, dynamic>{};
    }
    
    final peekingPlayerCardsRaw = knownCards[actingPlayerId];
    Map<String, dynamic> peekingPlayerCards;
    if (peekingPlayerCardsRaw is Map) {
      peekingPlayerCards = Map<String, dynamic>.from(peekingPlayerCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
    } else {
      peekingPlayerCards = <String, dynamic>{};
    }
    
    // Add the peeked card to known_cards (peeking player now knows this card)
    peekingPlayerCards[peekedCardId] = fullCardData;
    knownCards[actingPlayerId] = peekingPlayerCards;
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Added peeked card $peekedCardId to player $actingPlayerId known_cards (from player $targetPlayerId)');
    };
  }

  /// Check if timer should be started (timer enabled when instructions are OFF)
  bool _shouldStartTimer() {
    final config = _stateCallback.getTimerConfig();
    return !(config['showInstructions'] as bool? ?? false);
  }

  /// Start draw action timer for a player
  void _startDrawActionTimer(String playerId) {
    // Cancel existing timer if active
    _drawActionTimer?.cancel();
    _drawActionTimer = null;

    if (!_shouldStartTimer()) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Timer disabled (showInstructions=true) - not starting draw timer for player $playerId');
      };
      return;
    }

    final config = _stateCallback.getTimerConfig();
    final turnTimeLimit = config['turnTimeLimit'] as int? ?? 30;

    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Starting draw action timer for player $playerId (${turnTimeLimit}s)');
    };
    _drawActionTimer = Timer(Duration(seconds: turnTimeLimit), () {
      _onDrawActionTimerExpired(playerId);
    });
  }

  /// Start play action timer for a player
  void _startPlayActionTimer(String playerId) {
    // Cancel existing timer if active
    _playActionTimer?.cancel();
    _playActionTimer = null;

    if (!_shouldStartTimer()) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Timer disabled (showInstructions=true) - not starting play timer for player $playerId');
      };
      return;
    }

    final config = _stateCallback.getTimerConfig();
    final turnTimeLimit = config['turnTimeLimit'] as int? ?? 30;

    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Starting play action timer for player $playerId (${turnTimeLimit}s)');
    };
    _playActionTimer = Timer(Duration(seconds: turnTimeLimit), () {
      _onPlayActionTimerExpired(playerId);
    });
  }

  /// Handle draw action timer expiration
  void _onDrawActionTimerExpired(String playerId) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Draw action timer expired for player $playerId - skipping turn');
    };
    
    // Cancel play timer if active (draw expired, no play timer needed)
    _playActionTimer?.cancel();
    _playActionTimer = null;
    
    // Move to next player first (normal flow)
    _moveToNextPlayer();
    
    // Then check missed action threshold and trigger auto-leave if needed
    _missedActionCounts[playerId] = (_missedActionCounts[playerId] ?? 0) + 1;
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Player $playerId missed action count: ${_missedActionCounts[playerId]}');
    };
    
    // Check if threshold reached (2 missed actions)
    if (_missedActionCounts[playerId] == 2) {
      _onMissedActionThresholdReached(playerId);
    }
  }

  /// Handle play action timer expiration
  void _onPlayActionTimerExpired(String playerId) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Play action timer expired for player $playerId - skipping turn (drawn card remains in hand)');
    };
    
    // Cancel draw timer if active
    _drawActionTimer?.cancel();
    _drawActionTimer = null;
    
    // Clear drawnCard property and update player status (similar to handlePlayCard)
    // The drawn card is now in the player's hand, so it's no longer "drawn"
    try {
      final currentGames = _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState != null) {
        final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
        final player = players.firstWhere(
          (p) => p['id'] == playerId,
          orElse: () => <String, dynamic>{},
        );
        
        if (player.isNotEmpty) {
          // Clear drawnCard property (card is now in hand, not "drawn")
          // Remove the key entirely to ensure it's not visible to other players
          if (player.containsKey('drawnCard')) {
            player.remove('drawnCard');
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: Removed drawnCard property for player $playerId (timer expired, card remains in hand)');
            };
          }
          
          // Update player status to waiting
          player['status'] = 'waiting';
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Updated player $playerId status to waiting (timer expired)');
          };
          
          // CRITICAL: Sanitize drawnCard for all players before broadcasting
          // Even though we removed it from the current player, we need to ensure
          // no other players have drawnCard data visible
          for (final p in players) {
            if (p['id'] != playerId && p.containsKey('drawnCard') && p['drawnCard'] != null) {
              final drawnCard = p['drawnCard'] as Map<String, dynamic>?;
              if (drawnCard != null && drawnCard.containsKey('rank') && drawnCard['rank'] != '?') {
                // This player has full drawnCard data - sanitize it to ID-only
                p['drawnCard'] = {
                  'cardId': drawnCard['cardId'],
                  'suit': '?',
                  'rank': '?',
                  'points': 0,
                };
                if (LOGGING_SWITCH) {
                  _logger.info('Dutch: Sanitized drawnCard for player ${p['id']} before broadcast (timer expiration)');
                };
              }
            }
          }
          
          // Broadcast state update to all players (drawnCard is now removed/sanitized)
          _stateCallback.onGameStateChanged({
            'games': currentGames,
          });
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Broadcasted state update after play timer expiration for player $playerId (drawnCard removed/sanitized)');
          };
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: Error clearing drawnCard on play timer expiration: $e');
      };
    }
    
    // Move to next player first (normal flow)
    _moveToNextPlayer();
    
    // Then check missed action threshold and trigger auto-leave if needed
    _missedActionCounts[playerId] = (_missedActionCounts[playerId] ?? 0) + 1;
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: Player $playerId missed action count: ${_missedActionCounts[playerId]}');
    };
    
    // Check if threshold reached (2 missed actions)
    if (_missedActionCounts[playerId] == 2) {
      _onMissedActionThresholdReached(playerId);
    }
  }

  /// Cancel all action timers
  void _cancelActionTimers() {
    _drawActionTimer?.cancel();
    _drawActionTimer = null;
    _playActionTimer?.cancel();
    _playActionTimer = null;
  }

  /// Dispose of resources
  void dispose() {
    _sameRankTimer?.cancel();
    _specialCardTimer?.cancel();
    _cancelActionTimers();
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DutchGameRound disposed for game $_gameId');
    };
  }
}
