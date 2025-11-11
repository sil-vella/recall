/// Recall Game Round Manager for Recall Game
///
/// This class handles the actual gameplay rounds, turn management, and game logic
/// for recall sessions, including turn rotation, card actions, and AI decision making.

import '../shared_imports.dart';
import 'utils/computer_player_factory.dart';
import 'game_state_callback.dart';

const bool LOGGING_SWITCH = true;

class RecallGameRound {
  final Logger _logger = Logger();
  final GameStateCallback _stateCallback;
  final String _gameId;
  Timer? _sameRankTimer; // Timer for same rank window (5 seconds)
  Timer? _specialCardTimer; // Timer for special card window (10 seconds per card)
  
  // Computer player factory for YAML-based AI behavior
  ComputerPlayerFactory? _computerPlayerFactory;
  
  // Special card data storage - stores chronological list of special cards played
  // Matches backend's self.special_card_data list (game_round.py line 33)
  final List<Map<String, dynamic>> _specialCardData = [];
  
  // Working copy of special cards for processing (will remove as processed)
  // Matches backend's self.special_card_players list (game_round.py line 686)
  List<Map<String, dynamic>> _specialCardPlayers = [];
  
  // Winners list - stores winner information when game ends
  List<Map<String, dynamic>> _winnersList = [];
  
  // Recall caller - stores the player ID who called Recall
  String? _recallCaller;
  
  RecallGameRound(this._stateCallback, this._gameId);
  
  /// Initialize the round with the current game state
  /// Replicates backend _initial_peek_timeout() and start_turn() logic
  void initializeRound() {
    try {
      _logger.info('Recall: ===== INITIALIZING ROUND FOR GAME $_gameId =====', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      _logger.info('Recall: Current game state - Players: ${players.length}, Current Player: ${currentPlayer?['name'] ?? 'None'}', isOn: LOGGING_SWITCH);
      _logger.info('Recall: All players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']}, status: ${p['status']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // 1. Clear cards_to_peek for all players (peek phase is over)
      _logger.info('Recall: Step 1 - Clearing cards_to_peek for all players', isOn: LOGGING_SWITCH);
      _clearPeekedCards(gameState);
      
      // 2. Set all players back to WAITING status
      _logger.info('Recall: Step 2 - Setting all players to WAITING status', isOn: LOGGING_SWITCH);
      _setAllPlayersToWaiting(gameState);
      
      // 3. Initialize round state (replicates backend start_turn logic)
      _logger.info('Recall: Step 3 - Initializing round state', isOn: LOGGING_SWITCH);
      _initializeRoundState(gameState);
      
      // 4. Start the first turn (this will set the current player to DRAWING_CARD status)
      _logger.info('Recall: Step 4 - Starting first turn (will select current player)', isOn: LOGGING_SWITCH);
      _startNextTurn();
      
      _logger.info('Recall: ===== ROUND INITIALIZATION COMPLETED SUCCESSFULLY =====', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Failed to initialize round: $e', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Recall: Cleared cards_to_peek for $clearedCount players', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Failed to clear peeked cards: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Set all players to WAITING status (replicates backend logic)
  void _setAllPlayersToWaiting(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      for (final player in players) {
        player['status'] = 'waiting';
      }
      
      _logger.info('Recall: Set ${players.length} players back to WAITING status', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Failed to set players to waiting: $e', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Recall: Round state initialized - phase: player_turn, status: active', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Failed to initialize round state: $e', isOn: LOGGING_SWITCH);
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

  
  /// Get the current game state from the callback
  Map<String, dynamic>? _getCurrentGameState() {
    try {
      return _stateCallback.getCurrentGameState();
    } catch (e) {
      _logger.error('Recall: Failed to get current game state: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }

  /// Add card to discard pile directly (for use by GameRound)
  /// Updates the discard pile in game state and notifies callback
  void _addToDiscardPile(Map<String, dynamic> card) {
    final gameState = _getCurrentGameState();
    if (gameState == null) {
      _logger.error('Recall: Cannot add to discard pile - game state is null', isOn: LOGGING_SWITCH);
      return;
    }

    final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
    discardPile.add(card);
    gameState['discardPile'] = discardPile;
    
    // Notify callback that discard pile changed
    _stateCallback.onDiscardPileChanged();
  }
  
  /// Start the next player's turn
  void _startNextTurn() {
    try {
      _logger.info('Recall: Starting next turn...', isOn: LOGGING_SWITCH);
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game has ended - ${_winnersList.length} winner(s) found. Preventing turn start.', isOn: LOGGING_SWITCH);
        return;
      }
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for _startNextTurn', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayerId = gameState['currentPlayer']?['id'] as String?;
      
      _logger.info('Recall: Current player ID: $currentPlayerId', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Available players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // Find next player
      final nextPlayer = _getNextPlayer(players, currentPlayerId);
      if (nextPlayer == null) {
        _logger.error('Recall: No next player found', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Selected next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
      
      // Reset previous current player's status to waiting (if there was one)
      if (currentPlayerId != null) {
        _logger.info('Recall: Resetting previous current player $currentPlayerId to waiting status', isOn: LOGGING_SWITCH);
        _stateCallback.onPlayerStatusChanged('waiting', playerId: currentPlayerId, updateMainState: true);
      }
      
      // Update current player
      gameState['currentPlayer'] = nextPlayer;
      _logger.info('Recall: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      // This matches backend behavior where first player status is DRAWING_CARD
      _stateCallback.onPlayerStatusChanged('drawing_card', playerId: nextPlayer['id'], updateMainState: true, triggerInstructions: true);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        _logger.info('Recall: Computer player detected - triggering computer turn logic', isOn: LOGGING_SWITCH);
        _initComputerTurn(gameState);
      } else {
        _logger.info('Recall: Started turn for human player ${nextPlayer['name']} - status: drawing_card (no timer)', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      _logger.error('Recall: Failed to start next turn: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Initialize computer player turn logic
  /// This method will handle the complete computer player turn flow
  /// Uses declarative YAML configuration for computer behavior
  void _initComputerTurn(Map<String, dynamic> gameState) async {
    try {
      // Check if game has ended - if so, stop computer turn initialization
      if (_isGameEnded()) {
        _logger.info('Recall: Game has ended - stopping computer turn initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: ===== INITIALIZING COMPUTER TURN =====', isOn: LOGGING_SWITCH);
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        _logger.error('Recall: No current player found for computer turn', isOn: LOGGING_SWITCH);
        return;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? 'unknown';
      final playerName = currentPlayer['name']?.toString() ?? 'Unknown';
      
      _logger.info('Recall: Computer player $playerName ($playerId) starting turn', isOn: LOGGING_SWITCH);
      
      // Initialize computer player factory if not already done
      await _ensureComputerFactory();
      
      // Get computer player difficulty from game state
      final difficulty = _getComputerDifficulty(gameState, playerId);
      _logger.info('Recall: Computer player difficulty: $difficulty', isOn: LOGGING_SWITCH);
      
      // Determine the current event/action needed
      final eventName = _getCurrentEventName(gameState, playerId);
      _logger.info('Recall: Current event needed: $eventName', isOn: LOGGING_SWITCH);
      
      // Use YAML-based computer player factory for decision making
      if (_computerPlayerFactory != null) {
        _handleComputerActionWithYAML(gameState, playerId, difficulty, eventName);
      } else {
        // Fallback to original logic if YAML not available
        _handleComputerAction(gameState, playerId, difficulty, eventName);
      }
      
    } catch (e) {
      _logger.error('Recall: Error in _initComputerTurn: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Ensure the YAML-based computer player factory is initialized
  Future<void> _ensureComputerFactory() async {
    try {
      if (_computerPlayerFactory == null) {
        try {
          _computerPlayerFactory = await ComputerPlayerFactory.fromFile('assets/computer_player_config.yaml');
          _logger.info('Recall: Computer player factory initialized with YAML config', isOn: LOGGING_SWITCH);
        } catch (e) {
          _logger.error('Recall: Failed to load computer player config, using default behavior: $e', isOn: LOGGING_SWITCH);
        }
      }
    } catch (e) {
      _logger.error('Recall: Error ensuring computer factory: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Get computer player difficulty from game state
  String _getComputerDifficulty(Map<String, dynamic> gameState, String playerId) {
    try {
      // For now, return a default difficulty
      // Later this will be read from game configuration or player settings
      return 'medium'; // Options: easy, medium, hard, expert
    } catch (e) {
      _logger.error('Recall: Error getting computer difficulty: $e', isOn: LOGGING_SWITCH);
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
          _logger.warning('Recall: Unknown player status for event mapping: $playerStatus', isOn: LOGGING_SWITCH);
          return 'draw_card'; // Default to drawing a card
      }
    } catch (e) {
      _logger.error('Recall: Error getting current event name: $e', isOn: LOGGING_SWITCH);
      return 'draw_card';
    }
  }

  /// Handle computer action using YAML-based configuration
  /// This method uses the computer player factory to make decisions based on YAML config
  void _handleComputerActionWithYAML(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      // Check if game has ended - if so, stop handling computer actions
      if (_isGameEnded()) {
        _logger.info('Recall: Game has ended - stopping computer action handling for event: $eventName', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: DEBUG - _handleComputerActionWithYAML called with event: $eventName', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Handling computer action with YAML - Player: $playerId, Difficulty: $difficulty, Event: $eventName', isOn: LOGGING_SWITCH);
      
      if (_computerPlayerFactory == null) {
        _logger.error('Recall: Computer player factory not initialized', isOn: LOGGING_SWITCH);
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
          _logger.info('Recall: DEBUG - Computer player hand: $hand', isOn: LOGGING_SWITCH);
          
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
          
          _logger.info('Recall: DEBUG - Available cards after mapping (nulls filtered): $availableCards', isOn: LOGGING_SWITCH);
          
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
          _logger.warning('Recall: Unknown event for computer action: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
          return;
      }
      
      _logger.info('Recall: Computer decision: $decision', isOn: LOGGING_SWITCH);
      
      // Execute decision with delay from YAML config
      final delaySeconds = (decision['delay_seconds'] ?? 1.0).toDouble();
      Timer(Duration(milliseconds: (delaySeconds * 1000).round()), () async {
        await _executeComputerDecision(decision, playerId, eventName);
      });
      
    } catch (e) {
      _logger.error('Recall: Error in _handleComputerActionWithYAML: $e', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
    }
  }

  /// Execute computer player decision based on YAML configuration
  Future<void> _executeComputerDecision(Map<String, dynamic> decision, String playerId, String eventName) async {
    try {
      // Check if game has ended - if so, stop executing computer decisions
      if (_isGameEnded()) {
        _logger.info('Recall: Game has ended - stopping computer decision execution for event: $eventName', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Executing computer decision: $decision', isOn: LOGGING_SWITCH);
      
      switch (eventName) {
        case 'draw_card':
          final source = decision['source'] as String?;
          // Convert YAML source to handleDrawCard parameter
          final drawSource = source == 'discard' ? 'discard' : 'deck';
          _logger.info('Recall: Computer drawing from ${source == 'discard' ? 'discard pile' : 'deck'}', isOn: LOGGING_SWITCH);
          
          final success = await handleDrawCard(drawSource);
          if (!success) {
            _logger.error('Recall: Computer player $playerId failed to draw card', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          } else {
            // Check if game has ended before continuing to play_card action
            if (_isGameEnded()) {
              _logger.info('Recall: Game has ended after draw - stopping computer turn progression', isOn: LOGGING_SWITCH);
              return;
            }
            
            // After successful draw, continue computer turn with play_card action
            _logger.info('Recall: Computer player $playerId successfully drew card, continuing with play_card action', isOn: LOGGING_SWITCH);
            
            // Continue computer turn with play_card action (delay already handled by YAML config)
            final gameState = _getCurrentGameState();
            if (gameState != null) {
              final difficulty = _getComputerDifficulty(gameState, playerId);
              _logger.info('Recall: DEBUG - About to call _handleComputerActionWithYAML for play_card', isOn: LOGGING_SWITCH);
              _handleComputerActionWithYAML(gameState, playerId, difficulty, 'play_card');
              _logger.info('Recall: DEBUG - _handleComputerActionWithYAML call completed', isOn: LOGGING_SWITCH);
            } else {
              _logger.error('Recall: DEBUG - Game state is null, cannot continue with play_card', isOn: LOGGING_SWITCH);
            }
          }
          break;
          
        case 'play_card':
          final cardId = decision['card_id'] as String?;
          if (cardId != null) {
            final success = await handlePlayCard(cardId);
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed to play card', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            } else {
              _logger.info('Recall: Computer player $playerId successfully played card', isOn: LOGGING_SWITCH);
              // Note: Do NOT call _moveToNextPlayer() here
              // The same rank window (triggered in handlePlayCard) will handle moving to next player
              // Flow: _handleSameRankWindow() -> 5s timer -> _endSameRankWindow() -> _handleSpecialCardsWindow() -> _moveToNextPlayer()
            }
          } else {
            _logger.warning('Recall: No card selected for computer play', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          }
          break;
          
        case 'same_rank_play':
          final shouldPlay = decision['play'] as bool? ?? false;
          if (shouldPlay) {
            final cardId = decision['card_id'] as String?;
            if (_isValidCardId(cardId) && cardId != null) {
              // cardId is guaranteed non-null after _isValidCardId check
              final success = await handleSameRankPlay(playerId, cardId);
              if (!success) {
                _logger.error('Recall: Computer player $playerId failed same rank play', isOn: LOGGING_SWITCH);
                _moveToNextPlayer();
              }
            } else {
              _logger.warning('Recall: No card selected for computer same rank play', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          } else {
            _logger.info('Recall: Computer decided not to play same rank', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          }
          break;
          
        case 'jack_swap':
          final shouldUse = decision['use'] as bool? ?? false;
          if (shouldUse) {
            final success = await handleJackSwap(
              firstCardId: decision['first_card_id'] as String? ?? 'placeholder_first_card',
              firstPlayerId: decision['first_player_id'] as String? ?? playerId,
              secondCardId: decision['second_card_id'] as String? ?? 'placeholder_second_card',
              secondPlayerId: decision['second_player_id'] as String? ?? 'placeholder_target_player',
            );
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed Jack swap', isOn: LOGGING_SWITCH);
              // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
            }
          } else {
            _logger.info('Recall: Computer decided not to use Jack swap', isOn: LOGGING_SWITCH);
            // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
          }
          break;
          
        case 'queen_peek':
          final shouldUse = decision['use'] as bool? ?? false;
          if (shouldUse) {
            final success = await handleQueenPeek(
              peekingPlayerId: playerId,
              targetCardId: decision['target_card_id'] as String? ?? 'placeholder_target_card',
              targetPlayerId: decision['target_player_id'] as String? ?? 'placeholder_target_player',
            );
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed Queen peek', isOn: LOGGING_SWITCH);
              // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
            }
          } else {
            _logger.info('Recall: Computer decided not to use Queen peek', isOn: LOGGING_SWITCH);
            // Note: Don't call _moveToNextPlayer() here - special card window timer will handle it
          }
          break;
          
        case 'collect_from_discard':
          final shouldCollect = decision['collect'] as bool? ?? false;
          if (shouldCollect) {
            // DEBUG: Log the playerId being passed to handleCollectFromDiscard
            _logger.info('Recall: DEBUG - Executing collect_from_discard for playerId: $playerId, decision: $decision', isOn: LOGGING_SWITCH);
            final success = await handleCollectFromDiscard(playerId);
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed to collect from discard', isOn: LOGGING_SWITCH);
              // Note: No status change needed - player continues in current state
            } else {
              _logger.info('Recall: Computer player $playerId successfully collected from discard', isOn: LOGGING_SWITCH);
              // Note: No status change needed - player continues in current state
            }
          } else {
            _logger.info('Recall: Computer decided not to collect from discard', isOn: LOGGING_SWITCH);
            // Note: No status change needed - player continues in current state
          }
          break;
          
        default:
          _logger.warning('Recall: Unknown event for computer decision execution: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
      }
      
    } catch (e) {
      _logger.error('Recall: Error executing computer decision: $e', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
    }
  }

  /// Handle computer action using declarative YAML configuration
  void _handleComputerAction(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      // Check if game has ended - if so, stop handling computer actions
      if (_isGameEnded()) {
        _logger.info('Recall: Game has ended - stopping fallback computer action handling for event: $eventName', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Handling computer action - Player: $playerId, Difficulty: $difficulty, Event: $eventName', isOn: LOGGING_SWITCH);
      
      // TODO: Load and parse declarative YAML configuration
      // The YAML will define:
      // - Decision trees for each event type
      // - Difficulty-based behavior variations
      // - Card selection strategies
      // - Special card usage patterns
      
      _logger.info('Recall: Declarative YAML configuration will be implemented here', isOn: LOGGING_SWITCH);
      
      // Wire directly to existing human player methods - computers perform the same actions
      switch (eventName) {
        case 'draw_card':
          // TODO: Use YAML to determine draw source (deck vs discard)
          Timer(const Duration(seconds: 1), () async {
            final success = await handleDrawCard('deck');
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed to draw card', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            } else {
              // Check if game has ended before continuing to play_card action
              if (_isGameEnded()) {
                _logger.info('Recall: Game has ended after draw - stopping fallback computer turn progression', isOn: LOGGING_SWITCH);
                return;
              }
              
              // After successful draw, continue computer turn with play_card action
              _logger.info('Recall: Computer player $playerId successfully drew card, continuing with play_card action', isOn: LOGGING_SWITCH);
              
              // Continue computer turn with play_card action (delay already handled by Timer above)
              final gameState = _getCurrentGameState();
              if (gameState != null) {
                // Try to use YAML-based method if factory is available, otherwise use fallback
                if (_computerPlayerFactory != null) {
                  final difficulty = _getComputerDifficulty(gameState, playerId);
                  _logger.info('Recall: DEBUG - About to call _handleComputerActionWithYAML for play_card', isOn: LOGGING_SWITCH);
                  _handleComputerActionWithYAML(gameState, playerId, difficulty, 'play_card');
                } else {
                  // Fallback: continue with simple play logic
                  _logger.info('Recall: DEBUG - Factory not available, using fallback play_card logic', isOn: LOGGING_SWITCH);
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
                      _logger.info('Recall: Fallback - Playing card $cardId', isOn: LOGGING_SWITCH);
                      final success = await handlePlayCard(cardId);
                      if (!success) {
                        _logger.error('Recall: Computer player $playerId failed to play card', isOn: LOGGING_SWITCH);
                        _moveToNextPlayer();
                      }
                    } else {
                      _logger.warning('Recall: No cards available for computer player $playerId to play', isOn: LOGGING_SWITCH);
                      _moveToNextPlayer();
                    }
                  });
                }
              } else {
                _logger.error('Recall: DEBUG - Game state is null, cannot continue with play_card', isOn: LOGGING_SWITCH);
              }
            }
          });
          break;
        case 'play_card':
          // TODO: Use YAML to determine which card to play
          Timer(const Duration(seconds: 1), () async {
            // TODO: Get card ID from YAML configuration
            // For now, use a placeholder card ID
            final success = await handlePlayCard('placeholder_card_id');
            if (!success) {
              _logger.error('Recall: Computer player $playerId failed to play card', isOn: LOGGING_SWITCH);
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
              _logger.error('Recall: Computer player $playerId failed same rank play', isOn: LOGGING_SWITCH);
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
              _logger.error('Recall: Computer player $playerId failed Jack swap', isOn: LOGGING_SWITCH);
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
              _logger.error('Recall: Computer player $playerId failed Queen peek', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          });
          break;
        default:
          _logger.warning('Recall: Unknown event for computer action: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
      }
      
    } catch (e) {
      _logger.error('Recall: Error in _handleComputerAction: $e', isOn: LOGGING_SWITCH);
    }
  }

  
  /// Get the next player in rotation
  Map<String, dynamic>? _getNextPlayer(List<Map<String, dynamic>> players, String? currentPlayerId) {
    _logger.info('Recall: _getNextPlayer called with currentPlayerId: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    if (players.isEmpty) {
      _logger.error('Recall: No players available for _getNextPlayer', isOn: LOGGING_SWITCH);
      return null;
    }
    
    if (currentPlayerId == null) {
      _logger.info('Recall: No current player ID - this is the first turn', isOn: LOGGING_SWITCH);
      
      // First turn - randomly select any player (human or CPU)
      final random = Random();
      final randomIndex = random.nextInt(players.length);
      final randomPlayer = players[randomIndex];
      
      _logger.info('Recall: Randomly selected starting player: ${randomPlayer['name']} (${randomPlayer['id']}, isHuman: ${randomPlayer['isHuman']})', isOn: LOGGING_SWITCH);
      
      // Check if computer players can collect from discard pile (first turn)
      _checkComputerPlayerCollectionFromDiscard();
      
      return randomPlayer;
    }
    
    _logger.info('Recall: Looking for current player with ID: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    // Find current player index
    final currentIndex = players.indexWhere((p) => p['id'] == currentPlayerId);
    if (currentIndex == -1) {
      _logger.warning('Recall: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
      
      // Current player not found, find human player
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        _logger.info('Recall: Setting human player as current: ${humanPlayer['name']} (${humanPlayer['id']})', isOn: LOGGING_SWITCH);
        return humanPlayer;
      } else {
        // Fallback to first player
        _logger.warning('Recall: No human player found, using first player as fallback: ${players.first['name']}', isOn: LOGGING_SWITCH);
        return players.first;
      }
    }
    
    _logger.info('Recall: Found current player at index $currentIndex: ${players[currentIndex]['name']}', isOn: LOGGING_SWITCH);
    
    // Get next player (wrap around)
    final nextIndex = (currentIndex + 1) % players.length;
    final nextPlayer = players[nextIndex];
    
    _logger.info('Recall: Next player index: $nextIndex, next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
    
    return nextPlayer;
  }


  /// Handle drawing a card from the specified pile (replicates backend _handle_draw_from_pile)
  Future<bool> handleDrawCard(String source) async {
    try {
      _logger.info('Recall: Handling draw card from $source pile', isOn: LOGGING_SWITCH);
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        _logger.error('Recall: Invalid source for draw card: $source', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current game state
      final gameState = _getCurrentGameState();
      
      if (gameState == null) {
        _logger.error('Recall: Game state is null for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current player
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        _logger.error('Recall: No current player found for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      _logger.info('Recall: Drawing card for player $playerId from $source pile', isOn: LOGGING_SWITCH);
      
      // Draw card based on source
      Map<String, dynamic>? drawnCard;
      
      if (source == 'deck') {
        // Draw from draw pile
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          _logger.error('Recall: Cannot draw from empty draw pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        final idOnlyCard = drawPile.removeLast(); // Remove last card (top of pile)
        _logger.info('Recall: Drew card ${idOnlyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
        
        // Convert ID-only card to full card data using the coordinator's method
        drawnCard = _stateCallback.getCardById(gameState, idOnlyCard['cardId']);
        if (drawnCard == null) {
          _logger.error('Recall: Failed to get full card data for ${idOnlyCard['cardId']}', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Check if draw pile is now empty
        if (drawPile.isEmpty) {
          _logger.info('Recall: Draw pile is now empty', isOn: LOGGING_SWITCH);
        }
        
      } else if (source == 'discard') {
        // Take from discard pile
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        if (discardPile.isEmpty) {
          _logger.error('Recall: Cannot draw from empty discard pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        drawnCard = discardPile.removeLast(); // Remove last card (top of pile)
        _logger.info('Recall: Drew card ${drawnCard['cardId']} from discard pile', isOn: LOGGING_SWITCH);
      }
      
      if (drawnCard == null) {
        _logger.error('Recall: Failed to draw card from $source pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the current player's hand
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final playerIndex = players.indexWhere((p) => p['id'] == playerId);
      
      if (playerIndex == -1) {
        _logger.error('Recall: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final player = players[playerIndex];
      final hand = player['hand'] as List<dynamic>? ?? [];
      
      // Add card to player's hand as ID-only (player hands always store ID-only cards)
      // Backend replicates this in player.py add_card_to_hand method
      // Format matches recall game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
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
      _logger.info('Recall: Added drawn card to end of hand (index ${hand.length - 1})', isOn: LOGGING_SWITCH);
      
      // Log player state after drawing card
      _logger.info('Recall: === AFTER DRAW CARD for $playerId ===', isOn: LOGGING_SWITCH);
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player hand: $handCardIds', isOn: LOGGING_SWITCH);
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      _logger.info('Recall: Player known_cards: $knownCards', isOn: LOGGING_SWITCH);
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      _logger.info('Recall: Player collection_rank: $collectionRank', isOn: LOGGING_SWITCH);
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player collection_rank_cards: $collectionCardIds', isOn: LOGGING_SWITCH);
      
      // Set the drawn card property - FULL CARD DATA for human players, ID-only for computer players
      // This is what allows the frontend to show the front of the card (only for human players)
      final isHuman = player['isHuman'] as bool? ?? false;
      if (isHuman) {
        player['drawnCard'] = drawnCard; // Full card data for human player
      } else {
        player['drawnCard'] = {
          'cardId': drawnCard['cardId'],
          'suit': '?',      // ID-only for computer players
          'rank': '?',
          'points': 0,
        };
        
        // IMPORTANT: Add the drawn card to computer player's known_cards so they can use it for same rank plays
        final knownCardsRaw = player['known_cards'];
        Map<String, dynamic> knownCards;
        if (knownCardsRaw is Map) {
          knownCards = Map<String, dynamic>.from(knownCardsRaw.map((k, v) => MapEntry(k.toString(), v)));
        } else {
          knownCards = {};
        }
        final playerIdKey = playerId;
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
        _logger.info('Recall: Added drawn card ${drawnCard['cardId']} to computer player $playerId known_cards', isOn: LOGGING_SWITCH);
      }
      
      _logger.info('Recall: Added card ${drawnCard['cardId']} to player $playerId hand as ID-only', isOn: LOGGING_SWITCH);
      
      // Debug: Log all cards in hand after adding drawn card
      _logger.info('Recall: DEBUG - Player hand after draw:', isOn: LOGGING_SWITCH);
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card == null) {
          _logger.info('Recall: DEBUG -   Index $i: EMPTY SLOT (null)', isOn: LOGGING_SWITCH);
        } else {
          _logger.info('Recall: DEBUG -   Index $i: cardId=${card['cardId']}, hasFullData=${card.containsKey('rank')}', isOn: LOGGING_SWITCH);
        }
      }
      
      // Change player status from DRAWING_CARD to PLAYING_CARD
      _stateCallback.onPlayerStatusChanged('playing_card', playerId: playerId, updateMainState: true, triggerInstructions: true);
      
      _logger.info('Recall: Player $playerId status changed from drawing_card to playing_card', isOn: LOGGING_SWITCH);
      
      // Log pile contents after successful draw
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;
      
      _logger.info('Recall: === PILE CONTENTS AFTER DRAW ===', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Drawn Card: ${drawnCard['cardId']}', isOn: LOGGING_SWITCH);
      _logger.info('Recall: ================================', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      _logger.error('Recall: Error handling draw card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle collecting card from discard pile if it matches player's collection rank
  Future<bool> handleCollectFromDiscard(String playerId) async {
    try {
      _logger.info('Recall: Handling collect from discard for player $playerId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Check if game is in restricted phases
      final gamePhase = gameState['gamePhase']?.toString() ?? 'unknown';
      if (gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') {
        _logger.info('Recall: Cannot collect during $gamePhase phase', isOn: LOGGING_SWITCH);
        
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
      _logger.info('Recall: DEBUG - Looking for playerId: $playerId in players list', isOn: LOGGING_SWITCH);
      for (final p in players) {
        final pId = p['id']?.toString() ?? 'unknown';
        final pName = p['name']?.toString() ?? 'unknown';
        final pCollectionCards = p['collection_rank_cards'] as List<dynamic>? ?? [];
        final pCollectionRank = p['collection_rank']?.toString() ?? 'none';
        _logger.info('Recall: DEBUG - Player in state: $pName ($pId), collection_rank: $pCollectionRank, collection_cards: ${pCollectionCards.length}', isOn: LOGGING_SWITCH);
      }
      
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        _logger.error('Recall: Player $playerId not found', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // DEBUG: Verify we got the correct player
      final foundPlayerId = player['id']?.toString() ?? 'unknown';
      final foundPlayerName = player['name']?.toString() ?? 'unknown';
      _logger.info('Recall: DEBUG - Found player: $foundPlayerName ($foundPlayerId) - matches requested playerId: ${foundPlayerId == playerId}', isOn: LOGGING_SWITCH);
      
      // Get top card from discard pile
      final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      if (discardPile.isEmpty) {
        _logger.info('Recall: Discard pile is empty', isOn: LOGGING_SWITCH);
        
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
      _logger.info('Recall: DEBUG - Collect validation - Top discard rank: $topDiscardRank, Player collection rank: $playerCollectionRank, Collection cards count: ${collectionRankCards.length}', isOn: LOGGING_SWITCH);
      
      // Check if ranks match
      if (topDiscardRank.toLowerCase() != playerCollectionRank.toLowerCase()) {
        _logger.info('Recall: Card rank $topDiscardRank doesn\'t match collection rank $playerCollectionRank', isOn: LOGGING_SWITCH);
        
        _stateCallback.onActionError(
          'You can only collect cards from the discard pile that match your collection rank',
          data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
        );
        
        return false;
      }
      
      // DEBUG: Log successful validation
      _logger.info('Recall: DEBUG - Collect validation passed - ranks match: $topDiscardRank == $playerCollectionRank', isOn: LOGGING_SWITCH);
      
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
        _logger.error('Recall: ERROR - Card $topDiscardCardId is already in player $playerId collection_rank_cards! Preventing duplicate collection.', isOn: LOGGING_SWITCH);
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
        _logger.error('Recall: ERROR - Card ID mismatch! Expected $topDiscardCardId but removed $collectedCardId from discard pile', isOn: LOGGING_SWITCH);
        // This shouldn't happen, but if it does, we should still continue
      }
      
      _logger.info('Recall: Collected card $collectedCardId from discard pile', isOn: LOGGING_SWITCH);
      
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
      
      _logger.info('Recall: Added card to hand and collection_rank_cards', isOn: LOGGING_SWITCH);
      
      // Trigger state update (no status change, player continues in current state)
      final currentGames = _stateCallback.currentGamesMap;
      
      // Get updated discard pile from game state
      final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      _stateCallback.onGameStateChanged({
        'games': currentGames,
        'discardPile': updatedDiscardPile,  // CRITICAL: Update main state discardPile field
      });
      
      // Check if player now has four of a kind (all 4 collection cards for their rank)
      // This is a winning condition
      if (collectionRankCards.length == 4) {
        final playerName = player['name']?.toString() ?? 'Unknown';
        _logger.info('Recall: Player $playerName ($playerId) has collected all 4 cards of rank ${player['collection_rank']} - FOUR OF A KIND WIN!', isOn: LOGGING_SWITCH);
        
        // Set all players to waiting status
        _stateCallback.onPlayerStatusChanged(
          'waiting',
          playerId: null, // null = update ALL players
          updateMainState: true,
          triggerInstructions: false,
        );
        
        // Add player to winners list
        _winnersList.add({
          'playerId': playerId,
          'playerName': playerName,
          'winType': 'four_of_a_kind',
        });
        
        _logger.info('Recall: Added player $playerName ($playerId) to winners list with winType: four_of_a_kind', isOn: LOGGING_SWITCH);
        
        // Trigger game ending check
        _checkGameEnding();
      }
      
      return true;
      
    } catch (e) {
      _logger.error('Recall: Error handling collect from discard: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle playing a card from the player's hand (replicates backend _handle_play_card)
  Future<bool> handlePlayCard(String cardId) async {
    try {
      _logger.info('Recall: Handling play card: $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final currentGames = _stateCallback.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        _logger.error('Recall: Game state is null for play card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        _logger.error('Recall: No current player found for play card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player in the players list
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        _logger.error('Recall: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
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
        _logger.error('Recall: Card $cardId not found in player $playerId hand', isOn: LOGGING_SWITCH);
        return false;
      }
      
      _logger.info('Recall: Found card $cardId at index $cardIndex in player $playerId hand', isOn: LOGGING_SWITCH);
      
      // Check if card is in player's collection_rank_cards (cannot be played)
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      for (var collectionCard in collectionRankCards) {
        if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
          _logger.info('Recall: Card $cardId is a collection rank card and cannot be played', isOn: LOGGING_SWITCH);
          
          // Show error message to user
          _stateCallback.onActionError(
            'This card is your collection rank and cannot be played. Choose another card.',
            data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
          );
          
          // CRITICAL: Restore player status to playing_card so they can retry
          _stateCallback.onPlayerStatusChanged('playing_card', playerId: playerId, updateMainState: true);
          _logger.info('Recall: Restored player $playerId status to playing_card after failed collection rank play', isOn: LOGGING_SWITCH);
          
          return false;
        }
      }
      
      // Handle drawn card repositioning BEFORE removing the played card
      final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
      
      // Check if we should create a blank slot or remove the card entirely
      bool shouldCreateBlankSlot;
      try {
        _logger.info('Recall: About to call _shouldCreateBlankSlotAtIndex for index $cardIndex, hand.length=${hand.length}', isOn: LOGGING_SWITCH);
        shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
        _logger.info('Recall: _shouldCreateBlankSlotAtIndex returned: $shouldCreateBlankSlot', isOn: LOGGING_SWITCH);
      } catch (e) {
        _logger.error('Recall: Error in _shouldCreateBlankSlotAtIndex: $e', isOn: LOGGING_SWITCH);
        rethrow;
      }
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        try {
          _logger.info('Recall: About to set hand[$cardIndex] = null', isOn: LOGGING_SWITCH);
          hand[cardIndex] = null;
          _logger.info('Recall: Created blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
        } catch (e) {
          _logger.error('Recall: Error creating blank slot: $e', isOn: LOGGING_SWITCH);
          rethrow;
        }
      } else {
        // Remove the card entirely and shift remaining cards
        try {
          _logger.info('Recall: About to removeAt($cardIndex)', isOn: LOGGING_SWITCH);
          hand.removeAt(cardIndex);
          _logger.info('Recall: Removed card entirely from index $cardIndex, shifted remaining cards', isOn: LOGGING_SWITCH);
        } catch (e) {
          _logger.error('Recall: Error removing card: $e', isOn: LOGGING_SWITCH);
          rethrow;
        }
      }
      
      // Convert card to full data before adding to discard pile
      // The player's hand contains ID-only cards, but discard pile needs full card data
      _logger.info('Recall: About to get full card data for $cardId', isOn: LOGGING_SWITCH);
      final cardToPlayFullData = _stateCallback.getCardById(gameState, cardId);
      _logger.info('Recall: Got full card data for $cardId', isOn: LOGGING_SWITCH);
      if (cardToPlayFullData == null) {
        _logger.error('Recall: Failed to get full data for card $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      _logger.info('Recall: Converted card $cardId to full data for discard pile', isOn: LOGGING_SWITCH);
      
      // Update player's hand back to game state (hand list was modified with nulls)
      player['hand'] = hand;
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      _addToDiscardPile(cardToPlayFullData);
      
      // Log player state after playing card
      _logger.info('Recall: === AFTER PLAY CARD for $playerId ===', isOn: LOGGING_SWITCH);
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player hand: $handCardIds', isOn: LOGGING_SWITCH);
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      _logger.info('Recall: Player known_cards: $knownCards', isOn: LOGGING_SWITCH);
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      _logger.info('Recall: Player collection_rank: $collectionRank', isOn: LOGGING_SWITCH);
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player collection_rank_cards: $collectionCardIds', isOn: LOGGING_SWITCH);
      
      // Log pile contents after successful play
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;

      _logger.info('Recall: === PILE CONTENTS AFTER PLAY ===', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Played Card: ${cardToPlay['cardId']}', isOn: LOGGING_SWITCH);
      _logger.info('Recall: ================================', isOn: LOGGING_SWITCH);

      // Note: State update is already handled by addToDiscardPile method
      
      // Check if the played card has special powers (Jack/Queen)
      // Replicates backend flow: check special card FIRST (game_round.py line 989)
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': cardToPlayFullData['rank'],
        'suit': cardToPlayFullData['suit']
      });

      // Then trigger same rank window (backend game_round.py line 487)
      // This allows other players to play cards of the same rank out-of-turn
      _handleSameRankWindow();

      // CRITICAL: Update known_cards BEFORE clearing drawnCard property
      // This ensures the just-drawn card detection logic can work properly
      updateKnownCards('play_card', playerId, [cardId]);
      
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
        _logger.info('Recall: Player $playerName ($playerId) has no cards left - added to winners list', isOn: LOGGING_SWITCH);
      }
      
      // Handle drawn card repositioning with smart blank slot system
      // This must happen AFTER updateKnownCards so the detection logic can check drawnCard
      if (drawnCard != null && drawnCard['cardId'] != cardId) {
        // The drawn card should fill the blank slot left by the played card
        // The blank slot is at cardIndex (where the played card was)
        _logger.info('Recall: Repositioning drawn card ${drawnCard['cardId']} to index $cardIndex', isOn: LOGGING_SWITCH);
        
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
            _logger.info('Recall: Created blank slot at original position $originalIndex', isOn: LOGGING_SWITCH);
          } else {
            hand.removeAt(originalIndex);  // Remove entirely
            _logger.info('Recall: Removed card entirely from original position $originalIndex', isOn: LOGGING_SWITCH);
            // Adjust target index if we removed a card before it
            if (originalIndex < cardIndex) {
              cardIndex -= 1;
            }
          }
        }
        
        // Place the drawn card in the blank slot left by the played card
        // IMPORTANT: Convert drawn card to ID-only data when placing in hand (same as backend)
        // Format matches recall game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
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
            _logger.info('Recall: Placed drawn card in blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
          } else {
            hand.insert(cardIndex, drawnCardIdOnly);
            _logger.info('Recall: Inserted drawn card at index $cardIndex', isOn: LOGGING_SWITCH);
          }
        } else {
          // The slot shouldn't exist, so append the drawn card to the end
          hand.add(drawnCardIdOnly);
          _logger.info('Recall: Appended drawn card to end of hand (slot $cardIndex should not exist)', isOn: LOGGING_SWITCH);
        }
        
        // Clear the drawn card property since it's no longer "drawn"
        player['drawnCard'] = null;
        _logger.info('Recall: Cleared drawn card property after repositioning', isOn: LOGGING_SWITCH);
        
        // Update player's hand back to game state (hand list was modified)
        player['hand'] = hand;
        
        // NOTE: Do NOT update status here - all players already have 'same_rank_window' status
        // set by _handleSameRankWindow() (called earlier). Updating to 'waiting' would overwrite
        // the correct status for the playing player.
        
      } else if (drawnCard != null && drawnCard['cardId'] == cardId) {
        // Clear the drawn card property since it's now in the discard pile
        player['drawnCard'] = null;
        _logger.info('Recall: Cleared drawn card property (played card was the drawn card)', isOn: LOGGING_SWITCH);
        
        // NOTE: Do NOT update status here - all players already have 'same_rank_window' status
        // set by _handleSameRankWindow() (called earlier). Updating to 'waiting' would overwrite
        // the correct status for the playing player.
      }

      // Move to next player (simplified turn management for practice)
      // await _moveToNextPlayer();
      
      return true;
      
    } catch (e) {
      _logger.error('Recall: Error handling play card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Validate card ID is not null, empty, or the string 'null'
  bool _isValidCardId(String? cardId) {
    return cardId != null && cardId != 'null' && cardId.isNotEmpty;
  }

  /// Handle same rank play action - validates rank match and moves card to discard pile
  /// Replicates backend's _handle_same_rank_play method in game_round.py lines 1000-1089
  Future<bool> handleSameRankPlay(String playerId, String cardId) async {
    try {
      _logger.info('Recall: Handling same rank play for player $playerId, card $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        _logger.error('Recall: Player $playerId not found for same rank play', isOn: LOGGING_SWITCH);
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
        _logger.info('Recall: Card $cardId not found in player $playerId hand for same rank play (likely already played by another player)', isOn: LOGGING_SWITCH);
        return false;
      }
      
      _logger.info('Recall: Found card $cardId for same rank play in player $playerId hand at index $cardIndex', isOn: LOGGING_SWITCH);
      
      // Get full card data
      final playedCardFullData = _stateCallback.getCardById(gameState, cardId);
      if (playedCardFullData == null) {
        _logger.error('Recall: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final cardRank = playedCardFullData['rank']?.toString() ?? '';
      final cardSuit = playedCardFullData['suit']?.toString() ?? '';
      
      // Check if card is in player's collection_rank_cards (cannot be played for same rank)
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      for (var collectionCard in collectionRankCards) {
        if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
          _logger.info('Recall: Card $cardId is a collection rank card and cannot be played for same rank', isOn: LOGGING_SWITCH);
          
          // Show error message to user via actionError state
          _stateCallback.onActionError(
            'This card is in your collection and cannot be played for same rank.',
            data: {'timestamp': DateTime.now().millisecondsSinceEpoch},
          );
          
          // No status change needed - status will change automatically when same rank window expires
          _logger.info('Recall: Collection rank card rejected - status will auto-expire with same rank window', isOn: LOGGING_SWITCH);
          
          return false;
        }
      }
      
      // Validate that this is actually a same rank play
      if (!_validateSameRankPlay(gameState, cardRank)) {
        _logger.info('Recall: Same rank validation failed for card $cardId with rank $cardRank (expected behavior - player forgot/wrong card)', isOn: LOGGING_SWITCH);
        
        // Apply penalty: draw a card from the draw pile and add to player's hand
        _logger.info('Recall: Applying penalty for wrong same rank play - drawing card from draw pile', isOn: LOGGING_SWITCH);
        
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          _logger.error('Recall: Cannot apply penalty - draw pile is empty', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Draw a card from the draw pile (remove last card)
        final penaltyCard = drawPile.removeLast();
        _logger.info('Recall: Drew penalty card ${penaltyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
        
        // Add penalty card to player's hand as ID-only (same format as regular hand cards)
        // Format matches recall game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
        final penaltyCardIdOnly = {
          'cardId': penaltyCard['cardId'],
          'suit': '?',      // Face-down: hide suit
          'rank': '?',      // Face-down: hide rank
          'points': 0,      // Face-down: hide points
        };
        
        hand.add(penaltyCardIdOnly);
        _logger.info('Recall: Added penalty card ${penaltyCard['cardId']} to player $playerId hand as ID-only', isOn: LOGGING_SWITCH);
        
        // CRITICAL: Persist changes to game state
        player['hand'] = hand;  // Update player's hand with the penalty card
        gameState['drawPile'] = drawPile;  // Update draw pile after removing penalty card
        
        // Update player state to reflect the new hand and draw pile
        _stateCallback.onPlayerStatusChanged('waiting', playerId: playerId, updateMainState: true);
        
        // Broadcast the updated game state (hand and drawPile changes)
        // Get current games map (should already include our gameState modifications)
        final currentGames = _stateCallback.currentGamesMap;
        _stateCallback.onGameStateChanged({
          'games': currentGames,
        });
        
        _logger.info('Recall: Penalty applied successfully - player $playerId now has ${hand.length} cards', isOn: LOGGING_SWITCH);
        
        // Return true since using penalty was handled successfully (expected gameplay, not an error)
        return true;
      }
      
      _logger.info('Recall: Same rank validation passed for card $cardId with rank $cardRank', isOn: LOGGING_SWITCH);
      
      // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
      // Check if we should create a blank slot or remove the card entirely
      final shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        hand[cardIndex] = null;
        _logger.info('Recall: Created blank slot at index $cardIndex for same rank play', isOn: LOGGING_SWITCH);
      } else {
        // Remove the card entirely and shift remaining cards
        hand.removeAt(cardIndex);
        _logger.info('Recall: Removed same rank card entirely from index $cardIndex', isOn: LOGGING_SWITCH);
      }
      
      // Update player's hand back to game state (hand list was modified with nulls)
      player['hand'] = hand;
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      _addToDiscardPile(playedCardFullData);
      
      _logger.info('Recall: ✅ Same rank play successful: $playerId played $cardRank of $cardSuit - card moved to discard pile', isOn: LOGGING_SWITCH);
      
      // Log player state after same rank play
      _logger.info('Recall: === AFTER SAME RANK PLAY for $playerId ===', isOn: LOGGING_SWITCH);
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player hand: $handCardIds', isOn: LOGGING_SWITCH);
      final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      _logger.info('Recall: Player known_cards: $knownCards', isOn: LOGGING_SWITCH);
      final collectionRank = player['collection_rank']?.toString() ?? 'none';
      _logger.info('Recall: Player collection_rank: $collectionRank', isOn: LOGGING_SWITCH);
      final collectionRankCardsList = player['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCardsList.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player collection_rank_cards: $collectionCardIds', isOn: LOGGING_SWITCH);
      
      // Check for special cards (Jack/Queen) and store data if applicable
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': playedCardFullData['rank'],
        'suit': playedCardFullData['suit']
      });
      
      // TODO: Store the play in same_rank_data for tracking (future implementation)
      // For now, we just log the successful play
      _logger.info('Recall: Same rank play data would be stored here (future implementation)', isOn: LOGGING_SWITCH);
      
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
        _logger.info('Recall: Player $playerName ($playerId) has no cards left - added to winners list', isOn: LOGGING_SWITCH);
      }
      
      return true;
      
    } catch (e) {
      _logger.error('Recall: Error handling same rank play: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Jack swap action - swap two cards between players
  /// Replicates backend's _handle_jack_swap method in game_round.py lines 1199-1265
  Future<bool> handleJackSwap({
    required String firstCardId,
    required String firstPlayerId,
    required String secondCardId,
    required String secondPlayerId,
  }) async {
    try {
      _logger.info('Recall: Handling Jack swap for cards: $firstCardId (player $firstPlayerId) <-> $secondCardId (player $secondPlayerId)', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for Jack swap', isOn: LOGGING_SWITCH);
        return false;
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Validate both players exist
      final firstPlayer = players.firstWhere(
        (p) => p['id'] == firstPlayerId,
        orElse: () => <String, dynamic>{},
      );

      final secondPlayer = players.firstWhere(
        (p) => p['id'] == secondPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (firstPlayer.isEmpty || secondPlayer.isEmpty) {
        _logger.error('Recall: Invalid Jack swap - one or both players not found', isOn: LOGGING_SWITCH);
        return false;
      }

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
        _logger.error('Recall: Invalid Jack swap - one or both cards not found in players\' hands', isOn: LOGGING_SWITCH);
        return false;
      }

      _logger.info('Recall: Found cards - First card at index $firstCardIndex in player $firstPlayerId hand, Second card at index $secondCardIndex in player $secondPlayerId hand', isOn: LOGGING_SWITCH);

      // Get full card data for both cards to ensure we have the correct cardId
      final firstCardFullData = _stateCallback.getCardById(gameState, firstCardId);
      final secondCardFullData = _stateCallback.getCardById(gameState, secondCardId);
      
      if (firstCardFullData == null || secondCardFullData == null) {
        _logger.error('Recall: Failed to get full card data for swap - firstCard: ${firstCardFullData != null}, secondCard: ${secondCardFullData != null}', isOn: LOGGING_SWITCH);
        return false;
      }

      // Convert swapped cards to ID-only format (player hands always store ID-only cards)
      // Format matches recall game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
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

      // Remove swapped cards from their original owner's collection_rank_cards
      // Check if firstCardId is in firstPlayer's collection_rank_cards
      final firstPlayerCollectionCards = firstPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
      firstPlayerCollectionCards.removeWhere((card) {
        if (card is Map<String, dynamic>) {
          final cardId = card['cardId']?.toString() ?? '';
          if (cardId == firstCardId) {
            _logger.info('Recall: Removed card $firstCardId from player $firstPlayerId collection_rank_cards (swapped out)', isOn: LOGGING_SWITCH);
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
            _logger.info('Recall: Removed card $secondCardId from player $secondPlayerId collection_rank_cards (swapped out)', isOn: LOGGING_SWITCH);
            return true;
          }
        }
        return false;
      });

      _logger.info('Recall: Successfully swapped cards: $firstCardId <-> $secondCardId', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Player $firstPlayerId now has card $secondCardId at index $firstCardIndex', isOn: LOGGING_SWITCH);
      _logger.info('Recall: Player $secondPlayerId now has card $firstCardId at index $secondCardIndex', isOn: LOGGING_SWITCH);

      // Update game state to trigger UI updates
      final currentGames = _stateCallback.currentGamesMap;
      _stateCallback.onGameStateChanged({
        'games': currentGames,
      });

      _logger.info('Recall: Jack swap completed - state updated', isOn: LOGGING_SWITCH);

      // Update all players' known_cards after successful Jack swap
      updateKnownCards('jack_swap', firstPlayerId, [firstCardId, secondCardId], swapData: {
        'sourcePlayerId': firstPlayerId,
        'targetPlayerId': secondPlayerId,
      });

      // Action completed successfully - cancel timer and move to next special card
      _specialCardTimer?.cancel();
      _logger.info('Recall: Cancelled special card timer after Jack swap completion', isOn: LOGGING_SWITCH);

      // Set the current player's status to waiting
      // The player who completed the swap is the one in the first entry of _specialCardPlayers
      if (_specialCardPlayers.isNotEmpty) {
        final currentSpecialData = _specialCardPlayers[0];
        final currentPlayerId = currentSpecialData['player_id']?.toString();
        
        if (currentPlayerId != null && currentPlayerId.isNotEmpty) {
          // Set player status to waiting
          _stateCallback.onPlayerStatusChanged('waiting', playerId: currentPlayerId, updateMainState: true);
          _logger.info('Recall: Player $currentPlayerId status set to waiting after Jack swap completion', isOn: LOGGING_SWITCH);
          
          // Remove the processed card from the list
          _specialCardPlayers.removeAt(0);
          _logger.info('Recall: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
        }
      }

      // Add 1-second delay for visual indication before processing next special card
      // This matches the behavior in _onSpecialCardTimerExpired and prevents the game
      // from appearing halted by immediately processing the next special card
      _logger.info('Recall: Waiting 1 second before processing next special card...', isOn: LOGGING_SWITCH);
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });

      return true;

    } catch (e) {
      _logger.error('Recall: Error in handleJackSwap: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Queen peek action - peek at any one card from any player
  /// Replicates backend's _handle_queen_peek method in game_round.py lines 1267-1318
  Future<bool> handleQueenPeek({
    required String peekingPlayerId,
    required String targetCardId,
    required String targetPlayerId,
  }) async {
    try {
      _logger.info('Recall: Handling Queen peek - player $peekingPlayerId peeking at card $targetCardId from player $targetPlayerId', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Find the target player (card owner)
      final targetPlayer = players.firstWhere(
        (p) => p['id'] == targetPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (targetPlayer.isEmpty) {
        _logger.error('Recall: Target player $targetPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      // Find the peeking player (current player using Queen power)
      final peekingPlayer = players.firstWhere(
        (p) => p['id'] == peekingPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (peekingPlayer.isEmpty) {
        _logger.error('Recall: Peeking player $peekingPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      // Find the target card in the target player's hand
      final targetPlayerHand = targetPlayer['hand'] as List<dynamic>? ?? [];
      Map<String, dynamic>? targetCard;

      for (final card in targetPlayerHand) {
        if (card != null && card is Map<String, dynamic> && card['cardId'] == targetCardId) {
          targetCard = card;
          break;
        }
      }

      if (targetCard == null) {
        _logger.error('Recall: Card $targetCardId not found in target player $targetPlayerId hand', isOn: LOGGING_SWITCH);
        return false;
      }

      _logger.info('Recall: Found target card: ${targetCard['rank']} of ${targetCard['suit']}', isOn: LOGGING_SWITCH);

      // Get full card data (convert from ID-only if needed)
      final fullCardData = _stateCallback.getCardById(gameState, targetCardId);
      if (fullCardData == null) {
        _logger.error('Recall: Failed to get full card data for $targetCardId', isOn: LOGGING_SWITCH);
        return false;
      }

      _logger.info('Recall: Full card data: ${fullCardData['rank']} of ${fullCardData['suit']} (${fullCardData['points']} points)', isOn: LOGGING_SWITCH);

      // Clear any existing cards_to_peek from previous peeks (backend line 1304)
      final existingCardsToPeek = peekingPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      existingCardsToPeek.clear();
      _logger.info('Recall: Cleared existing cards_to_peek for player $peekingPlayerId', isOn: LOGGING_SWITCH);

      // Add the target card to the peeking player's cards_to_peek list (backend line 1307)
      peekingPlayer['cardsToPeek'] = [fullCardData];
      _logger.info('Recall: Added card ${fullCardData['cardId']} to player $peekingPlayerId cards_to_peek list', isOn: LOGGING_SWITCH);

      // Set player status to PEEKING (backend line 1311)
      peekingPlayer['status'] = 'peeking';
      _logger.info('Recall: Set player $peekingPlayerId status to peeking', isOn: LOGGING_SWITCH);

      // Update main state for the human player (check isHuman field instead of 'recall_user')
      final isHuman = peekingPlayer['isHuman'] as bool? ?? false;
      if (isHuman) {
        final currentGames = _stateCallback.currentGamesMap;
        _stateCallback.onGameStateChanged({
          'playerStatus': 'peeking',
          'myCardsToPeek': [fullCardData],
          'games': currentGames,
        });
        _logger.info('Recall: Updated main state for human player - myCardsToPeek updated', isOn: LOGGING_SWITCH);
      } else {
        // For computer players, just update the games map
        final currentGames = _stateCallback.currentGamesMap;
        _stateCallback.onGameStateChanged({
          'games': currentGames,
        });
        _logger.info('Recall: Updated games state for computer player', isOn: LOGGING_SWITCH);
      }

      _logger.info('Recall: Queen peek completed successfully', isOn: LOGGING_SWITCH);

      // Update all players' known_cards after successful Queen peek
      // This adds the peeked card to the peeking player's known_cards
      updateKnownCards('queen_peek', peekingPlayerId, [targetCardId], swapData: {
        'targetPlayerId': targetPlayerId,
      });

      return true;

    } catch (e) {
      _logger.error('Recall: Error in handleQueenPeek: $e', isOn: LOGGING_SWITCH);
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
        _logger.info('Recall: Same rank validation failed: No cards in discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the last card from the discard pile
      final lastCard = discardPile.last as Map<String, dynamic>?;
      if (lastCard == null) {
        _logger.info('Recall: Same rank validation failed: Last card is null', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final lastCardRank = lastCard['rank']?.toString() ?? '';
      
      _logger.info('Recall: Same rank validation: played_card_rank=\'$cardRank\', last_card_rank=\'$lastCardRank\'', isOn: LOGGING_SWITCH);
      
      // During same rank window, cards must match the rank of the last played card
      // No special cases - the window is triggered by a played card, so there's always a rank to match
      if (cardRank.toLowerCase() == lastCardRank.toLowerCase()) {
        _logger.info('Recall: Same rank validation: Ranks match, allowing play', isOn: LOGGING_SWITCH);
        return true;
      } else {
        _logger.info('Recall: Same rank validation: Ranks don\'t match (played: $cardRank, required: $lastCardRank), denying play', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      _logger.error('Recall: Same rank validation error: $e', isOn: LOGGING_SWITCH);
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
        
        _logger.info('Recall: DEBUG: special_card_data length before adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        _logger.info('Recall: DEBUG: special_card_data length after adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _logger.info('Recall: Added Jack special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
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
        
        _logger.info('Recall: DEBUG: special_card_data length before adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        _logger.info('Recall: DEBUG: special_card_data length after adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _logger.info('Recall: Added Queen special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
      } else {
        // Not a special card, no action needed
        _logger.info('Recall: Card $cardRank is not a special card', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      _logger.error('Recall: Error in _checkSpecialCard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle same rank window - sets all players to same_rank_window status
  /// Replicates backend's _handle_same_rank_window method in game_round.py lines 566-585
  void _handleSameRankWindow() {
    try {
      _logger.info('Recall: Starting same rank window - setting all players to same_rank_window status', isOn: LOGGING_SWITCH);
      
      // Use the unified updatePlayerStatus method with playerId = null to update ALL players
      // This will:
      // 1. Update all players' status in the games map
      // 2. Update playerStatus in main state (for MyHandWidget)
      // 3. Update currentPlayer and currentPlayerStatus (for OpponentsPanel)
      // 4. Update isMyTurn (for ActionBar and MyHandWidget)
      // 5. Update games map in main state (for all state slices)
      _stateCallback.onPlayerStatusChanged(
        'same_rank_window',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false, // Don't trigger instructions for same rank window
      );
      
      _logger.info('Recall: Successfully set all players to same_rank_window status', isOn: LOGGING_SWITCH);
      // This ensures collection from discard pile is properly blocked during same rank window
      _stateCallback.onGameStateChanged({
        'gamePhase': 'same_rank_window',
      });
      _logger.info('Recall: Set gamePhase to same_rank_window', isOn: LOGGING_SWITCH);
      
      // Start 5-second timer to automatically end same rank window
      // Matches backend behavior (game_round.py line 579)
      _startSameRankTimer();
      
    } catch (e) {
      _logger.error('Recall: Error in _handleSameRankWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Start a 5-second timer for the same rank window
  /// Replicates backend's _start_same_rank_timer method in game_round.py lines 587-597
  void _startSameRankTimer() {
    try {
      _logger.info('Recall: Starting 5-second same rank window timer', isOn: LOGGING_SWITCH);
      
      // Cancel existing timer if any
      _sameRankTimer?.cancel();
      
      // Store timer reference for potential cancellation
      _sameRankTimer = Timer(const Duration(seconds: 5), () async {
        await _endSameRankWindow();
      });
      
    } catch (e) {
      _logger.error('Recall: Error starting same rank timer: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// End the same rank window and move to next player
  /// Replicates backend's _end_same_rank_window method in game_round.py lines 599-643
  Future<void> _endSameRankWindow() async {
    try {
      _logger.info('Recall: Ending same rank window - resetting all players to waiting status', isOn: LOGGING_SWITCH);
      
      // TODO: Log same_rank_data if any players played matching cards (future implementation)
      // For now, we just log that window is ending
      _logger.info('Recall: No same rank plays recorded (simplified recall mode)', isOn: LOGGING_SWITCH);
      
      // Update all players' status to WAITING
      _stateCallback.onPlayerStatusChanged(
        'waiting',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false,
      );
      
      _logger.info('Recall: Successfully reset all players to waiting status', isOn: LOGGING_SWITCH);
      
      // CRITICAL: Reset gamePhase back to player_turn to match backend behavior
      // Backend transitions to ENDING_TURN phase (game_round.py line 634)
      // For recall game, we use player_turn as the main gameplay phase
      _stateCallback.onGameStateChanged({
        'gamePhase': 'player_turn',
      });
      _logger.info('Recall: Reset gamePhase to player_turn', isOn: LOGGING_SWITCH);
      
      // CRITICAL: AWAIT computer same rank plays to complete BEFORE processing special cards
      // This ensures all queens played during same rank window are added to _specialCardData
      // before we start the special cards window
      await _checkComputerPlayerSameRankPlays();
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      // Winners might be added during same rank plays (empty hand win condition)
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game has ended - ${_winnersList.length} winner(s) found after same rank plays. Preventing further game progression.', isOn: LOGGING_SWITCH);
        _checkGameEnding();
        return;
      }
      
      // Check if computer players can collect from discard pile
      // Rank matching is done in Dart, then YAML handles AI decision
      await _checkComputerPlayerCollectionFromDiscard();
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      // Winners might be added during collection check (four of a kind win condition)
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game has ended - ${_winnersList.length} winner(s) found after collection check. Preventing further game progression.', isOn: LOGGING_SWITCH);
        _checkGameEnding();
        return;
      }
      
      // Check for special cards and handle them (backend game_round.py line 640)
      // All same rank special cards are now in the list
      _handleSpecialCardsWindow();
      
    } catch (e) {
      _logger.error('Recall: Error ending same rank window: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check for same rank plays from computer players during the same rank window
  /// Returns a Future that completes when ALL computer same rank plays are done
  Future<void> _checkComputerPlayerSameRankPlays() async {
    try {
      _logger.info('Recall: Processing computer player same rank plays', isOn: LOGGING_SWITCH);
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.info('Recall: Failed to get game state', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Get computer players
      final computerPlayers = players.where((p) => 
        p is Map<String, dynamic> && 
        p['isHuman'] == false &&
        p['isActive'] == true
      ).toList();
      
      if (computerPlayers.isEmpty) {
        _logger.info('Recall: No computer players to process', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Found ${computerPlayers.length} computer players', isOn: LOGGING_SWITCH);
      
      // Debug: Log computer player details
      for (final player in computerPlayers) {
        final playerId = player['id']?.toString() ?? 'unknown';
        final playerName = player['name']?.toString() ?? 'Unknown';
        final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
        final hand = player['hand'] as List<dynamic>? ?? [];
        _logger.info('Recall: Computer player $playerName ($playerId) - hand: ${hand.length} cards, known_cards: ${knownCards.keys.length} players tracked', isOn: LOGGING_SWITCH);
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
        playFutures.add(_handleComputerSameRankPlay(playerId, difficulty, gameState));
      }
      
      // AWAIT all computer plays to complete
      await Future.wait(playFutures);
      
      _logger.info('Recall: All computer same rank plays completed', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Error in _checkComputerPlayerSameRankPlays: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check if computer players can collect from discard pile
  /// Rank matching is done in Dart, then YAML handles AI decision (collect or not)
  /// After each collection, re-checks the top card and continues until no one can collect or decides not to collect
  Future<void> _checkComputerPlayerCollectionFromDiscard() async {
    try {
      _logger.info('Recall: Checking computer players for collection from discard pile', isOn: LOGGING_SWITCH);
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.info('Recall: Failed to get game state for collection check', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Get all players
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Get computer players (isHuman == false and isActive == true)
      final computerPlayers = players.where((p) => 
        p['isHuman'] == false &&
        p['isActive'] == true
      ).toList();
      
      if (computerPlayers.isEmpty) {
        _logger.info('Recall: No computer players to check for collection', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Found ${computerPlayers.length} computer players to check', isOn: LOGGING_SWITCH);
      
      // Shuffle computer players list to randomize the order
      computerPlayers.shuffle(Random());
      _logger.info('Recall: Shuffled computer players list for random collection order', isOn: LOGGING_SWITCH);
      
      // Keep checking until no one can collect or decides not to collect
      // This handles cases where multiple cards of the same rank are in the discard pile (from same rank plays)
      bool continueChecking = true;
      int maxIterations = 100; // Safety limit to prevent infinite loops
      int iteration = 0;
      
      while (continueChecking && iteration < maxIterations) {
        iteration++;
        _logger.info('Recall: Collection check iteration $iteration', isOn: LOGGING_SWITCH);
        
        // Refresh game state in each iteration to get updated discard pile after collections
        final currentGameState = _getCurrentGameState();
        if (currentGameState == null) {
          _logger.info('Recall: Failed to get game state for collection check iteration', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        // Update gameState reference to use fresh state
        final gameState = currentGameState;
        
        // Refresh players list to get updated player data (collection_rank_cards may have changed)
        final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
        
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
          _logger.info('Recall: Discard pile is empty, stopping collection checks', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        // Get top discard card rank
        final topDiscardCard = discardPile.last;
        final topDiscardRank = topDiscardCard['rank']?.toString() ?? '';
        
        if (topDiscardRank.isEmpty) {
          _logger.info('Recall: Top discard card has no rank, stopping collection checks', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        _logger.info('Recall: Top discard card rank: $topDiscardRank', isOn: LOGGING_SWITCH);
        
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
          _logger.info('Recall: No computer player has a collection rank matching $topDiscardRank, stopping collection checks', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        final playerId = matchingPlayer['id']?.toString() ?? '';
        final playerName = matchingPlayer['name']?.toString() ?? 'Unknown';
        final playerCollectionRank = matchingPlayer['collection_rank']?.toString() ?? '';
        final difficulty = matchingPlayer['difficulty']?.toString() ?? 'medium';
        
        _logger.info('Recall: Found matching player $playerName ($playerId) - collection rank: $playerCollectionRank', isOn: LOGGING_SWITCH);
        
        // Get YAML decision (synchronous - decision is made immediately)
        if (_computerPlayerFactory == null) {
          _logger.error('Recall: Computer player factory not initialized', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        final decision = _computerPlayerFactory!.getCollectFromDiscardDecision(difficulty, gameState, playerId);
        _logger.info('Recall: YAML decision for $playerName: $decision', isOn: LOGGING_SWITCH);
        
        // Check if player decided to collect
        final shouldCollect = decision['collect'] as bool? ?? false;
        
        if (!shouldCollect) {
          _logger.info('Recall: Player $playerName decided not to collect, stopping collection checks', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        // Player decided to collect - execute collection immediately (no delay for collection checks)
        _logger.info('Recall: Player $playerName decided to collect, executing collection', isOn: LOGGING_SWITCH);
        final success = await handleCollectFromDiscard(playerId);
        
        if (!success) {
          _logger.warning('Recall: Player $playerName failed to collect, stopping collection checks', isOn: LOGGING_SWITCH);
          continueChecking = false;
          break;
        }
        
        _logger.info('Recall: Player $playerName successfully collected, checking for more collection opportunities', isOn: LOGGING_SWITCH);
        
        // After successful collection, refresh game state and continue checking
        // The loop will check the new top card on the next iteration
        // Small delay to allow state to update
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (iteration >= maxIterations) {
        _logger.warning('Recall: Reached max iterations ($maxIterations) in collection check loop, stopping', isOn: LOGGING_SWITCH);
      }
      
      _logger.info('Recall: Finished checking computer players for collection from discard pile', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Error in _checkComputerPlayerCollectionFromDiscard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check if the game should end (unified game ending check)
  /// This method checks for:
  /// 1. Empty hand win condition (player has no cards left)
  /// 2. Recall called (player called Recall to end the game)
  /// 3. Final round completion (after Recall is called)
  void _checkGameEnding() {
    try {
      _logger.info('Recall: Checking if game should end', isOn: LOGGING_SWITCH);
      
      // Check if winners list contains any players - if so, game is over
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game is over - ${_winnersList.length} winner(s) found', isOn: LOGGING_SWITCH);
        
        // Stop all active timers
        _sameRankTimer?.cancel();
        _sameRankTimer = null;
        _logger.info('Recall: Cancelled same rank timer', isOn: LOGGING_SWITCH);
        
        _specialCardTimer?.cancel();
        _specialCardTimer = null;
        _logger.info('Recall: Cancelled special card timer', isOn: LOGGING_SWITCH);
        
        // Set all players to waiting status
        _stateCallback.onPlayerStatusChanged(
          'waiting',
          playerId: null, // null = update ALL players
          updateMainState: true,
          triggerInstructions: false,
        );
        _logger.info('Recall: Set all players to waiting status', isOn: LOGGING_SWITCH);
        
        // Update game phase to game_ended (must match validator allowed values)
        _stateCallback.onGameStateChanged({
          'gamePhase': 'game_ended',
        });
        
        _logger.info('Recall: Set gamePhase to game_ended - all timers stopped and players set to waiting', isOn: LOGGING_SWITCH);
        
        // TODO: Future implementation
        // - Calculate points for all players if Recall was called
        // - Determine winner based on points and card count
        // - Display winner information
      } else {
        _logger.info('Recall: No winners yet - game continues', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      _logger.error('Recall: Error in _checkGameEnding: $e', isOn: LOGGING_SWITCH);
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
      _logger.error('Recall: Error checking if game ended: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle computer player same rank play decision
  /// Returns a Future that completes when this player's same rank play is done
  Future<void> _handleComputerSameRankPlay(String playerId, String difficulty, Map<String, dynamic> gameState) async {
    try {
      // Ensure AI factory is available in this path too
      await _ensureComputerFactory();

      // Get available same rank cards for this computer player
      final availableCards = _getAvailableSameRankCards(playerId, gameState);
      
      if (availableCards.isEmpty) {
        _logger.info('Recall: Computer player $playerId has no same rank cards', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('Recall: Computer player $playerId has ${availableCards.length} available same rank cards', isOn: LOGGING_SWITCH);
      
      // Get YAML decision
      if (_computerPlayerFactory == null) {
        _logger.warning('Recall: Computer factory not initialized; skipping same rank decision for $playerId', isOn: LOGGING_SWITCH);
        return;
      }
      final Map<String, dynamic> decision = _computerPlayerFactory!
          .getSameRankPlayDecision(difficulty, gameState, availableCards);
      _logger.info('Recall: Computer same rank decision: $decision', isOn: LOGGING_SWITCH);
      
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
            _logger.info('Recall: No valid cardId for same rank after fallback; skipping play for $playerId', isOn: LOGGING_SWITCH);
            return;
          }
        }
        if (_isValidCardId(cardId) && cardId != null) {
          // cardId is guaranteed non-null after _isValidCardId check
          await handleSameRankPlay(playerId, cardId);
        } else {
          _logger.info('Recall: Computer player $playerId same rank play skipped - invalid card ID', isOn: LOGGING_SWITCH);
        }
      }
      
    } catch (e) {
      _logger.error('Recall: Error in _handleComputerSameRankPlay: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Get available same rank cards from player's known_cards (excluding collection cards)
  List<String> _getAvailableSameRankCards(String playerId, Map<String, dynamic> gameState) {
    final availableCards = <String>[];
    
    try {
      _logger.info('Recall: DEBUG - Getting available same rank cards for player $playerId', isOn: LOGGING_SWITCH);
      
      // Get discard pile to determine target rank
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      if (discardPile.isEmpty) {
        _logger.info('Recall: DEBUG - Discard pile is empty, no same rank cards possible', isOn: LOGGING_SWITCH);
        return availableCards;
      }
      
      final lastCard = discardPile.last as Map<String, dynamic>?;
      final targetRank = lastCard?['rank']?.toString() ?? '';
      
      _logger.info('Recall: DEBUG - Target rank for same rank play: $targetRank', isOn: LOGGING_SWITCH);
      
      if (targetRank.isEmpty) {
        _logger.info('Recall: DEBUG - Target rank is empty, no same rank cards possible', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Recall: DEBUG - Player $playerId has ${hand.length} cards in hand', isOn: LOGGING_SWITCH);
      _logger.info('Recall: DEBUG - Player $playerId known_cards structure: ${knownCards.keys.toList()}', isOn: LOGGING_SWITCH);
      _logger.info('Recall: DEBUG - Player $playerId collection_rank_cards: ${collectionRankCards.length} cards', isOn: LOGGING_SWITCH);
      
      // Get collection card IDs
      final collectionCardIds = collectionRankCards
        .map((c) => c is Map ? (c['cardId']?.toString() ?? '') : '')
        .where((id) => id.isNotEmpty)
        .toSet();
      
      _logger.info('Recall: DEBUG - Collection card IDs: ${collectionCardIds.toList()}', isOn: LOGGING_SWITCH);
      
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
      
      _logger.info('Recall: DEBUG - Known card IDs: ${knownCardIds.toList()}', isOn: LOGGING_SWITCH);
      
      // Find matching rank cards in hand
      _logger.info('Recall: DEBUG - Checking ${hand.length} cards in hand for matching rank $targetRank', isOn: LOGGING_SWITCH);
      
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card == null || card is! Map<String, dynamic>) {
          _logger.info('Recall: DEBUG - Card at index $i is null or not a map, skipping', isOn: LOGGING_SWITCH);
          continue;
        }
        
        final cardId = card['cardId']?.toString() ?? '';
        
        // CRITICAL: Get full card data to check rank (hand contains ID-only cards with rank=?)
        final fullCardData = _stateCallback.getCardById(gameState, cardId);
        if (fullCardData == null) {
          _logger.info('Recall: DEBUG - Failed to get full card data for $cardId, skipping', isOn: LOGGING_SWITCH);
          continue;
        }
        
        final cardRank = fullCardData['rank']?.toString() ?? '';
        
        _logger.info('Recall: DEBUG - Card at index $i: id=$cardId, rank=$cardRank (from full data)', isOn: LOGGING_SWITCH);
        
        if (cardRank != targetRank) {
          _logger.info('Recall: DEBUG - Card rank $cardRank != target rank $targetRank, skipping', isOn: LOGGING_SWITCH);
          continue;
        }
        
        if (!knownCardIds.contains(cardId)) {
          _logger.info('Recall: DEBUG - Card $cardId not in known_cards, skipping', isOn: LOGGING_SWITCH);
          continue;
        }
        
        if (collectionCardIds.contains(cardId)) {
          _logger.info('Recall: DEBUG - Card $cardId is a collection card, skipping', isOn: LOGGING_SWITCH);
          continue;
        }
        
        _logger.info('Recall: DEBUG - Card $cardId is available for same rank play!', isOn: LOGGING_SWITCH);
        availableCards.add(cardId);
      }
      
      _logger.info('Recall: DEBUG - Found ${availableCards.length} available same rank cards: ${availableCards.toList()}', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Error in _getAvailableSameRankCards: $e', isOn: LOGGING_SWITCH);
    }
    
    return availableCards;
  }

  /// Handle special cards window - process each player's special card with 10-second timer
  /// Replicates backend's _handle_special_cards_window method in game_round.py lines 656-694
  void _handleSpecialCardsWindow() {
    try {
      // Check if we have any special cards played
      if (_specialCardData.isEmpty) {
        _logger.info('Recall: No special cards played in this round - moving to next player', isOn: LOGGING_SWITCH);
        // No special cards, go directly to next player
        _moveToNextPlayer();
        return;
      }
      
      _logger.info('Recall: === SPECIAL CARDS WINDOW ===', isOn: LOGGING_SWITCH);
      _logger.info('Recall: DEBUG: special_card_data length: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
      
      // CRITICAL: Set gamePhase to special_play_window to match Python backend behavior
      // This ensures same_rank_window phase is fully ended before special_play_window begins
      // Matches backend's phase transition at game_round.py line 1709
      _stateCallback.onGameStateChanged({
        'gamePhase': 'special_play_window',
      });
      _logger.info('Recall: Game phase changed to special_play_window (special cards found)', isOn: LOGGING_SWITCH);
      
      // Count total special cards (stored chronologically)
      final totalSpecialCards = _specialCardData.length;
      _logger.info('Recall: Found $totalSpecialCards special cards played in chronological order', isOn: LOGGING_SWITCH);
      
      // Log details of all special cards in chronological order
      for (int i = 0; i < _specialCardData.length; i++) {
        final card = _specialCardData[i];
        _logger.info('Recall:   ${i+1}. Player ${card['player_id']}: ${card['rank']} of ${card['suit']} (${card['special_power']})', isOn: LOGGING_SWITCH);
      }
      
      // Create a working copy for processing (we'll remove cards as we process them)
      _specialCardPlayers = List<Map<String, dynamic>>.from(_specialCardData);
      
      _logger.info('Recall: Starting special card processing with ${_specialCardPlayers.length} cards', isOn: LOGGING_SWITCH);
      
      // Start processing the first player's special card
      _processNextSpecialCard();
      
    } catch (e) {
      _logger.error('Recall: Error in _handleSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Process the next player's special card with 10-second timer
  /// Replicates backend's _process_next_special_card method in game_round.py lines 696-739
  void _processNextSpecialCard() {
    try {
      // Check if we've processed all special cards (list is empty)
      if (_specialCardPlayers.isEmpty) {
        _logger.info('Recall: All special cards processed - moving to next player', isOn: LOGGING_SWITCH);
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
      
      _logger.info('Recall: Processing special card for player $playerId: $cardRank of $cardSuit', isOn: LOGGING_SWITCH);
      _logger.info('Recall:   Special Power: $specialPower', isOn: LOGGING_SWITCH);
      _logger.info('Recall:   Description: $description', isOn: LOGGING_SWITCH);
      _logger.info('Recall:   Remaining cards to process: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      
      // Set player status based on special power
      if (specialPower == 'jack_swap') {
        _stateCallback.onPlayerStatusChanged('jack_swap', playerId: playerId, updateMainState: true);
        _logger.info('Recall: Player $playerId status set to jack_swap - 10 second timer started', isOn: LOGGING_SWITCH);
      } else if (specialPower == 'queen_peek') {
        _stateCallback.onPlayerStatusChanged('queen_peek', playerId: playerId, updateMainState: true);
        _logger.info('Recall: Player $playerId status set to queen_peek - 10 second timer started', isOn: LOGGING_SWITCH);
      } else {
        _logger.warning('Recall: Unknown special power: $specialPower for player $playerId', isOn: LOGGING_SWITCH);
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
          
          _logger.info('Recall: Computer player $playerId detected for jack_swap - triggering decision logic', isOn: LOGGING_SWITCH);
          
          // Trigger computer decision logic
          _handleComputerActionWithYAML(gameState, playerId, difficulty, 'jack_swap');
        } else if (!isHuman && specialPower == 'queen_peek') {
          // Get player's difficulty
          final difficulty = player['difficulty']?.toString() ?? 'medium';
          
          _logger.info('Recall: Computer player $playerId detected for queen_peek - triggering decision logic', isOn: LOGGING_SWITCH);
          
          // Trigger computer decision logic
          _handleComputerActionWithYAML(gameState, playerId, difficulty, 'queen_peek');
        }
      }
      
      // Start 10-second timer for this player's special card play
      _specialCardTimer?.cancel();
      _specialCardTimer = Timer(const Duration(seconds: 10), () {
        _onSpecialCardTimerExpired();
      });
      _logger.info('Recall: 10-second timer started for player $playerId\'s $specialPower', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Error in _processNextSpecialCard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Called when the special card timer expires - move to next player or end window
  /// Replicates backend's _on_special_card_timer_expired method in game_round.py lines 741-766
  void _onSpecialCardTimerExpired() {
    try {
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
            _logger.info('Recall: Cleared cardsToPeek for player $playerId - cards reverted to ID-only', isOn: LOGGING_SWITCH);
            
            // Update main state for human player
            if (playerId == 'recall_user') {
              _stateCallback.onGameStateChanged({
                'myCardsToPeek': [],
              });
              _logger.info('Recall: Updated main state myCardsToPeek to empty list', isOn: LOGGING_SWITCH);
            }
          }
        }
        
        _stateCallback.onPlayerStatusChanged('waiting', playerId: playerId, updateMainState: true);
        _logger.info('Recall: Player $playerId special card timer expired - status reset to waiting', isOn: LOGGING_SWITCH);
        
        // Remove the processed card from the list
        _specialCardPlayers.removeAt(0);
        _logger.info('Recall: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      }
      
      // Add 1-second delay for visual indication before processing next special card
      _logger.info('Recall: Waiting 1 second before processing next special card...', isOn: LOGGING_SWITCH);
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });
      
    } catch (e) {
      _logger.error('Recall: Error in _onSpecialCardTimerExpired: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// End the special cards window and move to next player
  /// Replicates backend's _end_special_cards_window method in game_round.py lines 768-789
  void _endSpecialCardsWindow() {
    try {
      // Cancel any running timer
      _specialCardTimer?.cancel();
      
      // Clear special card data
      _specialCardData.clear();
      _specialCardPlayers.clear();
      
      _logger.info('Recall: Special cards window ended - cleared all special card data', isOn: LOGGING_SWITCH);
      
      // Check if any players have empty collection_rank_cards list after special plays
      // If empty, clear their collection_rank property (they can no longer collect cards)
      _checkAndClearEmptyCollectionRanks();
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game has ended - ${_winnersList.length} winner(s) found. Preventing game phase reset and player progression.', isOn: LOGGING_SWITCH);
        return;
      }
      
      // CRITICAL: Reset gamePhase back to player_turn before moving to next player
      // This ensures clean phase transitions and matches backend behavior
      _stateCallback.onGameStateChanged({
        'gamePhase': 'player_turn',
      });
      _logger.info('Recall: Game phase reset to player_turn after special cards window', isOn: LOGGING_SWITCH);
      
      // Now move to the next player
      _logger.info('Recall: Moving to next player after special cards', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
      
    } catch (e) {
      _logger.error('Recall: Error in _endSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check if any players have empty collection_rank_cards list and clear collection_rank if so
  /// This should be called after special plays are completed (e.g., after Jack swap)
  void _checkAndClearEmptyCollectionRanks() {
    try {
      _logger.info('Recall: Checking all players for empty collection_rank_cards', isOn: LOGGING_SWITCH);
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        _logger.error('Recall: Failed to get game state for collection rank check', isOn: LOGGING_SWITCH);
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
            _logger.info('Recall: Cleared collection_rank for player $playerName ($playerId) - collection_rank_cards is empty', isOn: LOGGING_SWITCH);
          }
        }
      }
      
      _logger.info('Recall: Finished checking all players for empty collection_rank_cards', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Error in _checkAndClearEmptyCollectionRanks: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Move to the next player (simplified version for practice)
  Future<void> _moveToNextPlayer() async {
    try {
      _logger.info('Recall: Moving to next player', isOn: LOGGING_SWITCH);
      
      // Check if game has ended (winners exist) - prevent progression if game is over
      if (_winnersList.isNotEmpty) {
        _logger.info('Recall: Game has ended - ${_winnersList.length} winner(s) found. Preventing game progression.', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Get current game state
      final gameState = _getCurrentGameState();
      
      if (gameState == null) {
        _logger.error('Recall: Game state is null for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (currentPlayer == null || players.isEmpty) {
        _logger.error('Recall: No current player or players list for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Set current player status to waiting before moving to next player
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      _stateCallback.onPlayerStatusChanged('waiting', playerId: currentPlayerId, updateMainState: true);
      _logger.info('Recall: Set current player $currentPlayerId status to waiting', isOn: LOGGING_SWITCH);
      
      // Find current player index
      int currentIndex = -1;
      for (int i = 0; i < players.length; i++) {
        if (players[i]['id'] == currentPlayerId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        _logger.error('Recall: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Move to next player (or first if at end)
      final nextIndex = (currentIndex + 1) % players.length;
      final nextPlayer = players[nextIndex];
      final nextPlayerId = nextPlayer['id']?.toString() ?? '';
      
      // Update current player in game state
      gameState['currentPlayer'] = nextPlayer;
      _logger.info('Recall: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Log player state at start of turn
      _logger.info('Recall: === TURN START for $nextPlayerId ===', isOn: LOGGING_SWITCH);
      final hand = nextPlayer['hand'] as List<dynamic>? ?? [];
      final handCardIds = hand.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player hand: $handCardIds', isOn: LOGGING_SWITCH);
      final knownCards = nextPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      _logger.info('Recall: Player known_cards: $knownCards', isOn: LOGGING_SWITCH);
      final collectionRank = nextPlayer['collection_rank']?.toString() ?? 'none';
      _logger.info('Recall: Player collection_rank: $collectionRank', isOn: LOGGING_SWITCH);
      final collectionRankCards = nextPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = collectionRankCards.map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? 'unknown') : c.toString()).toList();
      _logger.info('Recall: Player collection_rank_cards: $collectionCardIds', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      _stateCallback.onPlayerStatusChanged('drawing_card', playerId: nextPlayerId, updateMainState: true, triggerInstructions: true);
      _logger.info('Recall: Set next player ${nextPlayer['name']} to drawing_card status', isOn: LOGGING_SWITCH);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        _logger.info('Recall: Computer player detected - triggering computer turn logic', isOn: LOGGING_SWITCH);
        _initComputerTurn(gameState);
      } else {
        _logger.info('Recall: Started turn for human player ${nextPlayer['name']} - status: drawing_card (no timer)', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      _logger.error('Recall: Error moving to next player: $e', isOn: LOGGING_SWITCH);
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
      
      // Update state
      _stateCallback.onGameStateChanged({'games': currentGames});
      
      _logger.info('Recall: Updated known_cards for all players after $eventType', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Recall: Failed to update known_cards: $e', isOn: LOGGING_SWITCH);
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
        
        _logger.info('Recall: Removed just-drawn card $playedCardId from $actingPlayerId known_cards (100% certainty)', isOn: LOGGING_SWITCH);
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
      _logger.warning('Recall: Failed to get full card data for peeked card $peekedCardId', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: Added peeked card $peekedCardId to player $actingPlayerId known_cards (from player $targetPlayerId)', isOn: LOGGING_SWITCH);
  }

  /// Dispose of resources
  void dispose() {
    _sameRankTimer?.cancel();
    _specialCardTimer?.cancel();
    _logger.info('Recall: RecallGameRound disposed for game $_gameId', isOn: LOGGING_SWITCH);
  }
}
