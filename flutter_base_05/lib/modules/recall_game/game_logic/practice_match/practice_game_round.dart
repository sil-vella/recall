/// Practice Game Round Manager for Recall Game
///
/// This class handles the actual gameplay rounds, turn management, and game logic
/// for practice sessions, including turn rotation, card actions, and AI decision making.

import 'dart:async';
import 'dart:math';
import 'package:recall/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';
import 'practice_game.dart';
import 'utils/computer_player_factory.dart';

const bool LOGGING_SWITCH = false;

class PracticeGameRound {
  final PracticeGameCoordinator _practiceCoordinator;
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
  
  PracticeGameRound(this._practiceCoordinator, this._gameId);
  
  /// Initialize the round with the current game state
  /// Replicates backend _initial_peek_timeout() and start_turn() logic
  void initializeRound() {
    try {
      Logger().info('Practice: ===== INITIALIZING ROUND FOR GAME $_gameId =====', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      Logger().info('Practice: Current game state - Players: ${players.length}, Current Player: ${currentPlayer?['name'] ?? 'None'}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: All players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']}, status: ${p['status']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // 1. Clear cards_to_peek for all players (peek phase is over)
      Logger().info('Practice: Step 1 - Clearing cards_to_peek for all players', isOn: LOGGING_SWITCH);
      _clearPeekedCards(gameState);
      
      // 2. Set all players back to WAITING status
      Logger().info('Practice: Step 2 - Setting all players to WAITING status', isOn: LOGGING_SWITCH);
      _setAllPlayersToWaiting(gameState);
      
      // 3. Initialize round state (replicates backend start_turn logic)
      Logger().info('Practice: Step 3 - Initializing round state', isOn: LOGGING_SWITCH);
      _initializeRoundState(gameState);
      
      // 4. Start the first turn (this will set the current player to DRAWING_CARD status)
      Logger().info('Practice: Step 4 - Starting first turn (will select current player)', isOn: LOGGING_SWITCH);
      _startNextTurn();
      
      Logger().info('Practice: ===== ROUND INITIALIZATION COMPLETED SUCCESSFULLY =====', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize round: $e', isOn: LOGGING_SWITCH);
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
      
      Logger().info('Practice: Cleared cards_to_peek for $clearedCount players', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to clear peeked cards: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Set all players to WAITING status (replicates backend logic)
  void _setAllPlayersToWaiting(Map<String, dynamic> gameState) {
    try {
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      for (final player in players) {
        player['status'] = 'waiting';
      }
      
      Logger().info('Practice: Set ${players.length} players back to WAITING status', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to set players to waiting: $e', isOn: LOGGING_SWITCH);
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
      
      Logger().info('Practice: Round state initialized - phase: player_turn, status: active', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize round state: $e', isOn: LOGGING_SWITCH);
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

  
  /// Get the current game state from the practice coordinator
  Map<String, dynamic>? _getCurrentGameState() {
    try {
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      return gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
    } catch (e) {
      Logger().error('Practice: Failed to get current game state: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }
  
  /// Start the next player's turn
  void _startNextTurn() {
    try {
      Logger().info('Practice: Starting next turn...', isOn: LOGGING_SWITCH);
      
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for _startNextTurn', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayerId = gameState['currentPlayer']?['id'] as String?;
      
      Logger().info('Practice: Current player ID: $currentPlayerId', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Available players: ${players.map((p) => '${p['name']} (${p['id']}, isHuman: ${p['isHuman']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      // Find next player
      final nextPlayer = _getNextPlayer(players, currentPlayerId);
      if (nextPlayer == null) {
        Logger().error('Practice: No next player found', isOn: LOGGING_SWITCH);
        return;
      }
      
      Logger().info('Practice: Selected next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
      
      // Reset previous current player's status to waiting (if there was one)
      if (currentPlayerId != null) {
        Logger().info('Practice: Resetting previous current player $currentPlayerId to waiting status', isOn: LOGGING_SWITCH);
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: currentPlayerId, updateMainState: true);
      }
      
      // Update current player
      gameState['currentPlayer'] = nextPlayer;
      Logger().info('Practice: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      // This matches backend behavior where first player status is DRAWING_CARD
      _practiceCoordinator.updatePlayerStatus('drawing_card', playerId: nextPlayer['id'], updateMainState: true, triggerInstructions: true);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        Logger().info('Practice: Computer player detected - triggering computer turn logic', isOn: LOGGING_SWITCH);
        _initComputerTurn(gameState);
      } else {
        Logger().info('Practice: Started turn for human player ${nextPlayer['name']} - status: drawing_card (no timer)', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to start next turn: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Initialize computer player turn logic
  /// This method will handle the complete computer player turn flow
  /// Uses declarative YAML configuration for computer behavior
  void _initComputerTurn(Map<String, dynamic> gameState) async {
    try {
      Logger().info('Practice: ===== INITIALIZING COMPUTER TURN =====', isOn: LOGGING_SWITCH);
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for computer turn', isOn: LOGGING_SWITCH);
        return;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? 'unknown';
      final playerName = currentPlayer['name']?.toString() ?? 'Unknown';
      
      Logger().info('Practice: Computer player $playerName ($playerId) starting turn', isOn: LOGGING_SWITCH);
      
      // Initialize computer player factory if not already done
      if (_computerPlayerFactory == null) {
        try {
          _computerPlayerFactory = await ComputerPlayerFactory.fromFile('assets/computer_player_config.yaml');
          Logger().info('Practice: Computer player factory initialized with YAML config', isOn: LOGGING_SWITCH);
        } catch (e) {
          Logger().error('Practice: Failed to load computer player config, using default behavior: $e', isOn: LOGGING_SWITCH);
          // Continue with default behavior if YAML loading fails
        }
      }
      
      // Get computer player difficulty from game state
      final difficulty = _getComputerDifficulty(gameState, playerId);
      Logger().info('Practice: Computer player difficulty: $difficulty', isOn: LOGGING_SWITCH);
      
      // Determine the current event/action needed
      final eventName = _getCurrentEventName(gameState, playerId);
      Logger().info('Practice: Current event needed: $eventName', isOn: LOGGING_SWITCH);
      
      // Use YAML-based computer player factory for decision making
      if (_computerPlayerFactory != null) {
        _handleComputerActionWithYAML(gameState, playerId, difficulty, eventName);
      } else {
        // Fallback to original logic if YAML not available
        _handleComputerAction(gameState, playerId, difficulty, eventName);
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _initComputerTurn: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Get computer player difficulty from game state
  String _getComputerDifficulty(Map<String, dynamic> gameState, String playerId) {
    try {
      // For now, return a default difficulty
      // Later this will be read from game configuration or player settings
      return 'medium'; // Options: easy, medium, hard, expert
    } catch (e) {
      Logger().error('Practice: Error getting computer difficulty: $e', isOn: LOGGING_SWITCH);
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
          Logger().warning('Practice: Unknown player status for event mapping: $playerStatus', isOn: LOGGING_SWITCH);
          return 'draw_card'; // Default to drawing a card
      }
    } catch (e) {
      Logger().error('Practice: Error getting current event name: $e', isOn: LOGGING_SWITCH);
      return 'draw_card';
    }
  }

  /// Handle computer action using YAML-based configuration
  /// This method uses the computer player factory to make decisions based on YAML config
  void _handleComputerActionWithYAML(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      Logger().info('Practice: DEBUG - _handleComputerActionWithYAML called with event: $eventName', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Handling computer action with YAML - Player: $playerId, Difficulty: $difficulty, Event: $eventName', isOn: LOGGING_SWITCH);
      
      if (_computerPlayerFactory == null) {
        Logger().error('Practice: Computer player factory not initialized', isOn: LOGGING_SWITCH);
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
          Logger().info('Practice: DEBUG - Computer player hand: $hand', isOn: LOGGING_SWITCH);
          final availableCards = hand.map((card) {
            if (card is Map<String, dynamic>) {
              return card['cardId']?.toString() ?? card['id']?.toString() ?? card.toString();
            } else {
              return card.toString();
            }
          }).toList();
          Logger().info('Practice: DEBUG - Available cards after mapping: $availableCards', isOn: LOGGING_SWITCH);
          
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
        default:
          Logger().warning('Practice: Unknown event for computer action: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
          return;
      }
      
      Logger().info('Practice: Computer decision: $decision', isOn: LOGGING_SWITCH);
      
      // Execute decision with delay from YAML config
      final delaySeconds = (decision['delay_seconds'] ?? 1.0).toDouble();
      Timer(Duration(milliseconds: (delaySeconds * 1000).round()), () async {
        await _executeComputerDecision(decision, playerId, eventName);
      });
      
    } catch (e) {
      Logger().error('Practice: Error in _handleComputerActionWithYAML: $e', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
    }
  }

  /// Execute computer player decision based on YAML configuration
  Future<void> _executeComputerDecision(Map<String, dynamic> decision, String playerId, String eventName) async {
    try {
      Logger().info('Practice: Executing computer decision: $decision', isOn: LOGGING_SWITCH);
      
      switch (eventName) {
        case 'draw_card':
          final source = decision['source'] as String?;
          // Convert YAML source to handleDrawCard parameter
          final drawSource = source == 'discard' ? 'discard' : 'deck';
          Logger().info('Practice: Computer drawing from ${source == 'discard' ? 'discard pile' : 'deck'}', isOn: LOGGING_SWITCH);
          
          final success = await handleDrawCard(drawSource);
          if (!success) {
            Logger().error('Practice: Computer player $playerId failed to draw card', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          } else {
            // After successful draw, continue computer turn with play_card action
            Logger().info('Practice: Computer player $playerId successfully drew card, continuing with play_card action', isOn: LOGGING_SWITCH);
            
            // Add a small delay to simulate thinking time
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Continue computer turn with play_card action
            final gameState = _getCurrentGameState();
            if (gameState != null) {
              final difficulty = _getComputerDifficulty(gameState, playerId);
              Logger().info('Practice: DEBUG - About to call _handleComputerActionWithYAML for play_card', isOn: LOGGING_SWITCH);
              _handleComputerActionWithYAML(gameState, playerId, difficulty, 'play_card');
              Logger().info('Practice: DEBUG - _handleComputerActionWithYAML call completed', isOn: LOGGING_SWITCH);
            } else {
              Logger().error('Practice: DEBUG - Game state is null, cannot continue with play_card', isOn: LOGGING_SWITCH);
            }
          }
          break;
          
        case 'play_card':
          final cardId = decision['card_id'] as String?;
          if (cardId != null) {
            final success = await handlePlayCard(cardId);
            if (!success) {
              Logger().error('Practice: Computer player $playerId failed to play card', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            } else {
              Logger().info('Practice: Computer player $playerId successfully played card', isOn: LOGGING_SWITCH);
              // Note: Do NOT call _moveToNextPlayer() here
              // The same rank window (triggered in handlePlayCard) will handle moving to next player
              // Flow: _handleSameRankWindow() -> 5s timer -> _endSameRankWindow() -> _handleSpecialCardsWindow() -> _moveToNextPlayer()
            }
          } else {
            Logger().warning('Practice: No card selected for computer play', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          }
          break;
          
        case 'same_rank_play':
          final shouldPlay = decision['play'] as bool? ?? false;
          if (shouldPlay) {
            final cardId = decision['card_id'] as String?;
            if (cardId != null) {
              final success = await handleSameRankPlay(playerId, cardId);
              if (!success) {
                Logger().error('Practice: Computer player $playerId failed same rank play', isOn: LOGGING_SWITCH);
                _moveToNextPlayer();
              }
            } else {
              Logger().warning('Practice: No card selected for computer same rank play', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          } else {
            Logger().info('Practice: Computer decided not to play same rank', isOn: LOGGING_SWITCH);
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
              Logger().error('Practice: Computer player $playerId failed Jack swap', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          } else {
            Logger().info('Practice: Computer decided not to use Jack swap', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
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
              Logger().error('Practice: Computer player $playerId failed Queen peek', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          } else {
            Logger().info('Practice: Computer decided not to use Queen peek', isOn: LOGGING_SWITCH);
            _moveToNextPlayer();
          }
          break;
          
        default:
          Logger().warning('Practice: Unknown event for computer decision execution: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
      }
      
    } catch (e) {
      Logger().error('Practice: Error executing computer decision: $e', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
    }
  }

  /// Handle computer action using declarative YAML configuration
  void _handleComputerAction(Map<String, dynamic> gameState, String playerId, String difficulty, String eventName) {
    try {
      Logger().info('Practice: Handling computer action - Player: $playerId, Difficulty: $difficulty, Event: $eventName', isOn: LOGGING_SWITCH);
      
      // TODO: Load and parse declarative YAML configuration
      // The YAML will define:
      // - Decision trees for each event type
      // - Difficulty-based behavior variations
      // - Card selection strategies
      // - Special card usage patterns
      
      Logger().info('Practice: Declarative YAML configuration will be implemented here', isOn: LOGGING_SWITCH);
      
      // Wire directly to existing human player methods - computers perform the same actions
      switch (eventName) {
        case 'draw_card':
          // TODO: Use YAML to determine draw source (deck vs discard)
          Timer(const Duration(seconds: 1), () async {
            final success = await handleDrawCard('deck');
            if (!success) {
              Logger().error('Practice: Computer player $playerId failed to draw card', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
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
              Logger().error('Practice: Computer player $playerId failed to play card', isOn: LOGGING_SWITCH);
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
              Logger().error('Practice: Computer player $playerId failed same rank play', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          });
          break;
        case 'jack_swap':
          // TODO: Use YAML to determine Jack swap targets
          Timer(const Duration(seconds: 1), () async {
            // TODO: Get swap targets from YAML configuration
            // For now, use placeholder targets
            final success = await handleJackSwap(
              firstCardId: 'placeholder_first_card',
              firstPlayerId: playerId,
              secondCardId: 'placeholder_second_card',
              secondPlayerId: 'placeholder_target_player',
            );
            if (!success) {
              Logger().error('Practice: Computer player $playerId failed Jack swap', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          });
          break;
        case 'queen_peek':
          // TODO: Use YAML to determine Queen peek target
          Timer(const Duration(seconds: 1), () async {
            // TODO: Get peek target from YAML configuration
            // For now, use placeholder targets
            final success = await handleQueenPeek(
              peekingPlayerId: playerId,
              targetCardId: 'placeholder_target_card',
              targetPlayerId: 'placeholder_target_player',
            );
            if (!success) {
              Logger().error('Practice: Computer player $playerId failed Queen peek', isOn: LOGGING_SWITCH);
              _moveToNextPlayer();
            }
          });
          break;
        default:
          Logger().warning('Practice: Unknown event for computer action: $eventName', isOn: LOGGING_SWITCH);
          _moveToNextPlayer();
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _handleComputerAction: $e', isOn: LOGGING_SWITCH);
    }
  }

  
  /// Get the next player in rotation
  Map<String, dynamic>? _getNextPlayer(List<Map<String, dynamic>> players, String? currentPlayerId) {
    Logger().info('Practice: _getNextPlayer called with currentPlayerId: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    if (players.isEmpty) {
      Logger().error('Practice: No players available for _getNextPlayer', isOn: LOGGING_SWITCH);
      return null;
    }
    
    if (currentPlayerId == null) {
      Logger().info('Practice: No current player ID - this is the first turn', isOn: LOGGING_SWITCH);
      
      // First turn - find human player and set as current
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        Logger().info('Practice: Found human player: ${humanPlayer['name']} (${humanPlayer['id']}) - setting as current', isOn: LOGGING_SWITCH);
        return humanPlayer;
      } else {
        // Fallback to first player if no human player found
        Logger().warning('Practice: No human player found, using first player as fallback: ${players.first['name']}', isOn: LOGGING_SWITCH);
        return players.first;
      }
    }
    
    Logger().info('Practice: Looking for current player with ID: $currentPlayerId', isOn: LOGGING_SWITCH);
    
    // Find current player index
    final currentIndex = players.indexWhere((p) => p['id'] == currentPlayerId);
    if (currentIndex == -1) {
      Logger().warning('Practice: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
      
      // Current player not found, find human player
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isNotEmpty) {
        Logger().info('Practice: Setting human player as current: ${humanPlayer['name']} (${humanPlayer['id']})', isOn: LOGGING_SWITCH);
        return humanPlayer;
      } else {
        // Fallback to first player
        Logger().warning('Practice: No human player found, using first player as fallback: ${players.first['name']}', isOn: LOGGING_SWITCH);
        return players.first;
      }
    }
    
    Logger().info('Practice: Found current player at index $currentIndex: ${players[currentIndex]['name']}', isOn: LOGGING_SWITCH);
    
    // Get next player (wrap around)
    final nextIndex = (currentIndex + 1) % players.length;
    final nextPlayer = players[nextIndex];
    
    Logger().info('Practice: Next player index: $nextIndex, next player: ${nextPlayer['name']} (${nextPlayer['id']}, isHuman: ${nextPlayer['isHuman']})', isOn: LOGGING_SWITCH);
    
    return nextPlayer;
  }


  /// Handle drawing a card from the specified pile (replicates backend _handle_draw_from_pile)
  Future<bool> handleDrawCard(String source) async {
    try {
      Logger().info('Practice: Handling draw card from $source pile', isOn: LOGGING_SWITCH);
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        Logger().error('Practice: Invalid source for draw card: $source', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current player
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for draw card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      Logger().info('Practice: Drawing card for player $playerId from $source pile', isOn: LOGGING_SWITCH);
      
      // Draw card based on source
      Map<String, dynamic>? drawnCard;
      
      if (source == 'deck') {
        // Draw from draw pile
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          Logger().error('Practice: Cannot draw from empty draw pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        final idOnlyCard = drawPile.removeLast(); // Remove last card (top of pile)
        Logger().info('Practice: Drew card ${idOnlyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
        
        // Convert ID-only card to full card data using the coordinator's method
        drawnCard = _practiceCoordinator.getCardById(gameState, idOnlyCard['cardId']);
        if (drawnCard == null) {
          Logger().error('Practice: Failed to get full card data for ${idOnlyCard['cardId']}', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Check if draw pile is now empty
        if (drawPile.isEmpty) {
          Logger().info('Practice: Draw pile is now empty', isOn: LOGGING_SWITCH);
        }
        
      } else if (source == 'discard') {
        // Take from discard pile
        final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
        if (discardPile.isEmpty) {
          Logger().error('Practice: Cannot draw from empty discard pile', isOn: LOGGING_SWITCH);
          return false;
        }
        
        drawnCard = discardPile.removeLast(); // Remove last card (top of pile)
        Logger().info('Practice: Drew card ${drawnCard['cardId']} from discard pile', isOn: LOGGING_SWITCH);
      }
      
      if (drawnCard == null) {
        Logger().error('Practice: Failed to draw card from $source pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the current player's hand
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final playerIndex = players.indexWhere((p) => p['id'] == playerId);
      
      if (playerIndex == -1) {
        Logger().error('Practice: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final player = players[playerIndex];
      final hand = player['hand'] as List<dynamic>? ?? [];
      
      // Add card to player's hand as ID-only (player hands always store ID-only cards)
      // Backend replicates this in player.py add_card_to_hand method
      final idOnlyCard = {'cardId': drawnCard['cardId']};
      
      // Add card to player's hand - look for a blank slot (null) to fill first
      bool filledBlankSlot = false;
      for (int i = 0; i < hand.length; i++) {
        if (hand[i] == null) {
          hand[i] = idOnlyCard;
          filledBlankSlot = true;
          Logger().info('Practice: Filled blank slot at index $i with drawn card', isOn: LOGGING_SWITCH);
          break;
        }
      }
      
      // If no blank slot found, append to the end
      if (!filledBlankSlot) {
        hand.add(idOnlyCard);
        Logger().info('Practice: Added drawn card to end of hand', isOn: LOGGING_SWITCH);
      }
      
      // Set the drawn card property - FULL CARD DATA for human players, ID-only for computer players
      // This is what allows the frontend to show the front of the card (only for human players)
      if (playerId == 'practice_user') {
        player['drawnCard'] = drawnCard; // Full card data for human player
      } else {
        player['drawnCard'] = {'cardId': drawnCard['cardId']}; // ID-only for computer players
      }
      
      Logger().info('Practice: Added card ${drawnCard['cardId']} to player $playerId hand as ID-only', isOn: LOGGING_SWITCH);
      
      // Debug: Log all cards in hand after adding drawn card
      Logger().info('Practice: DEBUG - Player hand after draw:', isOn: LOGGING_SWITCH);
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card == null) {
          Logger().info('Practice: DEBUG -   Index $i: EMPTY SLOT (null)', isOn: LOGGING_SWITCH);
        } else {
          Logger().info('Practice: DEBUG -   Index $i: cardId=${card['cardId']}, hasFullData=${card.containsKey('rank')}', isOn: LOGGING_SWITCH);
        }
      }
      
      // Change player status from DRAWING_CARD to PLAYING_CARD
      final statusUpdated = _practiceCoordinator.updatePlayerStatus('playing_card', playerId: playerId, updateMainState: true, triggerInstructions: true);
      if (!statusUpdated) {
        Logger().error('Practice: Failed to update player status to playing_card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Player $playerId status changed from drawing_card to playing_card', isOn: LOGGING_SWITCH);
      
      // Log pile contents after successful draw
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;
      
      Logger().info('Practice: === PILE CONTENTS AFTER DRAW ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Drawn Card: ${drawnCard['cardId']}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: ================================', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling draw card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle collecting card from discard pile if it matches player's collection rank
  Future<bool> handleCollectFromDiscard(String playerId) async {
    try {
      Logger().info('Practice: Handling collect from discard for player $playerId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Check if game is in restricted phases
      final gamePhase = gameState['gamePhase']?.toString() ?? 'unknown';
      if (gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') {
        Logger().info('Practice: Cannot collect during $gamePhase phase', isOn: LOGGING_SWITCH);
        
        // Show error message
        final stateManager = StateManager();
        final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        stateManager.updateModuleState('recall_game', {
          ...currentState,
          'actionError': {
            'message': 'Cannot collect cards during $gamePhase phase',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        });
        
        return false;
      }
      
      // Get player
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        Logger().error('Practice: Player $playerId not found', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get top card from discard pile
      final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      if (discardPile.isEmpty) {
        Logger().info('Practice: Discard pile is empty', isOn: LOGGING_SWITCH);
        
        final stateManager = StateManager();
        final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        stateManager.updateModuleState('recall_game', {
          ...currentState,
          'actionError': {
            'message': 'Discard pile is empty',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        });
        
        return false;
      }
      
      final topDiscardCard = discardPile.last;
      final topDiscardRank = topDiscardCard['rank']?.toString() ?? '';
      
      // Get player's collection rank
      final playerCollectionRank = player['collection_rank']?.toString() ?? '';
      
      // Check if ranks match
      if (topDiscardRank.toLowerCase() != playerCollectionRank.toLowerCase()) {
        Logger().info('Practice: Card rank $topDiscardRank doesn\'t match collection rank $playerCollectionRank', isOn: LOGGING_SWITCH);
        
        final stateManager = StateManager();
        final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        stateManager.updateModuleState('recall_game', {
          ...currentState,
          'actionError': {
            'message': 'You can only collect cards from the discard pile that match your collection rank',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        });
        
        return false;
      }
      
      // SUCCESS - Remove card from discard pile
      final collectedCard = discardPile.removeLast();
      Logger().info('Practice: Collected card ${collectedCard['cardId']} from discard pile', isOn: LOGGING_SWITCH);
      
      // Add to player's hand as ID-only
      final hand = player['hand'] as List<dynamic>? ?? [];
      hand.add({'cardId': collectedCard['cardId']});
      
      // Add to player's collection_rank_cards (full data)
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      collectionRankCards.add(collectedCard); // Full card data
      
      // Update player's collection_rank to match the collected card's rank
      player['collection_rank'] = collectedCard['rank']?.toString() ?? 'unknown';
      
      Logger().info('Practice: Added card to hand and collection_rank_cards', isOn: LOGGING_SWITCH);
      
      // Trigger state update (no status change, player continues in current state)
      final currentGames = _practiceCoordinator.currentGamesMap;
      
      // Get updated discard pile from game state
      final updatedDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      _practiceCoordinator.updatePracticeGameState({
        'games': currentGames,
        'discardPile': updatedDiscardPile,  // CRITICAL: Update main state discardPile field
      });
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling collect from discard: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle playing a card from the player's hand (replicates backend _handle_play_card)
  Future<bool> handlePlayCard(String cardId) async {
    try {
      Logger().info('Practice: Handling play card: $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for play card', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for play card', isOn: LOGGING_SWITCH);
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
        Logger().error('Practice: Player $playerId not found in players list', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the card in the player's hand
      final hand = player['hand'] as List<dynamic>? ?? [];
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
        Logger().error('Practice: Card $cardId not found in player $playerId hand', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Found card $cardId at index $cardIndex in player $playerId hand', isOn: LOGGING_SWITCH);
      
      // Check if card is in player's collection_rank_cards (cannot be played)
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      for (var collectionCard in collectionRankCards) {
        if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
          Logger().info('Practice: Card $cardId is a collection rank card and cannot be played', isOn: LOGGING_SWITCH);
          
          // Show error message to user
          final stateManager = StateManager();
          final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
          stateManager.updateModuleState('recall_game', {
            ...currentState,
            'actionError': {
              'message': 'This card is your collection rank and cannot be played. Choose another card.',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          });
          
          // CRITICAL: Restore player status to playing_card so they can retry
          _practiceCoordinator.updatePlayerStatus('playing_card', playerId: playerId, updateMainState: true);
          Logger().info('Practice: Restored player $playerId status to playing_card after failed collection rank play', isOn: LOGGING_SWITCH);
          
          return false;
        }
      }
      
      // Handle drawn card repositioning BEFORE removing the played card
      final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
      
      // Check if we should create a blank slot or remove the card entirely
      bool shouldCreateBlankSlot;
      try {
        Logger().info('Practice: About to call _shouldCreateBlankSlotAtIndex for index $cardIndex, hand.length=${hand.length}', isOn: LOGGING_SWITCH);
        shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
        Logger().info('Practice: _shouldCreateBlankSlotAtIndex returned: $shouldCreateBlankSlot', isOn: LOGGING_SWITCH);
      } catch (e) {
        Logger().error('Practice: Error in _shouldCreateBlankSlotAtIndex: $e', isOn: LOGGING_SWITCH);
        rethrow;
      }
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        try {
          Logger().info('Practice: About to set hand[$cardIndex] = null', isOn: LOGGING_SWITCH);
          hand[cardIndex] = null;
          Logger().info('Practice: Created blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
        } catch (e) {
          Logger().error('Practice: Error creating blank slot: $e', isOn: LOGGING_SWITCH);
          rethrow;
        }
      } else {
        // Remove the card entirely and shift remaining cards
        try {
          Logger().info('Practice: About to removeAt($cardIndex)', isOn: LOGGING_SWITCH);
          hand.removeAt(cardIndex);
          Logger().info('Practice: Removed card entirely from index $cardIndex, shifted remaining cards', isOn: LOGGING_SWITCH);
        } catch (e) {
          Logger().error('Practice: Error removing card: $e', isOn: LOGGING_SWITCH);
          rethrow;
        }
      }
      
      // Convert card to full data before adding to discard pile
      // The player's hand contains ID-only cards, but discard pile needs full card data
      Logger().info('Practice: About to get full card data for $cardId', isOn: LOGGING_SWITCH);
      final cardToPlayFullData = _practiceCoordinator.getCardById(gameState, cardId);
      Logger().info('Practice: Got full card data for $cardId', isOn: LOGGING_SWITCH);
      if (cardToPlayFullData == null) {
        Logger().error('Practice: Failed to get full data for card $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      Logger().info('Practice: Converted card $cardId to full data for discard pile', isOn: LOGGING_SWITCH);
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      final success = _practiceCoordinator.addToDiscardPile(cardToPlayFullData);
      if (!success) {
        Logger().error('Practice: Failed to add card $cardId to discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      Logger().info('Practice: Successfully added card $cardId to discard pile with full data', isOn: LOGGING_SWITCH);
      
      // Handle drawn card repositioning with smart blank slot system
      if (drawnCard != null && drawnCard['cardId'] != cardId) {
        // The drawn card should fill the blank slot left by the played card
        // The blank slot is at cardIndex (where the played card was)
        Logger().info('Practice: Repositioning drawn card ${drawnCard['cardId']} to index $cardIndex', isOn: LOGGING_SWITCH);
        
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
            Logger().info('Practice: Created blank slot at original position $originalIndex', isOn: LOGGING_SWITCH);
          } else {
            hand.removeAt(originalIndex);  // Remove entirely
            Logger().info('Practice: Removed card entirely from original position $originalIndex', isOn: LOGGING_SWITCH);
            // Adjust target index if we removed a card before it
            if (originalIndex < cardIndex) {
              cardIndex -= 1;
            }
          }
        }
        
        // Place the drawn card in the blank slot left by the played card
        // IMPORTANT: Convert drawn card to ID-only data when placing in hand (same as backend)
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
          'displayName': 'Card ${drawnCard['cardId']}',
          'color': 'black',
        };
        
        // Apply smart blank slot logic to the target position
        final shouldPlaceInSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
        
        if (shouldPlaceInSlot) {
          // Place it in the blank slot left by the played card
          if (cardIndex < hand.length) {
            hand[cardIndex] = drawnCardIdOnly;
            Logger().info('Practice: Placed drawn card in blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
          } else {
            hand.insert(cardIndex, drawnCardIdOnly);
            Logger().info('Practice: Inserted drawn card at index $cardIndex', isOn: LOGGING_SWITCH);
          }
        } else {
          // The slot shouldn't exist, so append the drawn card to the end
          hand.add(drawnCardIdOnly);
          Logger().info('Practice: Appended drawn card to end of hand (slot $cardIndex should not exist)', isOn: LOGGING_SWITCH);
        }
        
        // Clear the drawn card property since it's no longer "drawn"
        player['drawnCard'] = null;
        Logger().info('Practice: Cleared drawn card property after repositioning', isOn: LOGGING_SWITCH);
        
        // Update the main state's myDrawnCard to null (same as backend)
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
        
      } else if (drawnCard != null && drawnCard['cardId'] == cardId) {
        // Clear the drawn card property since it's now in the discard pile
        player['drawnCard'] = null;
        Logger().info('Practice: Cleared drawn card property (played card was the drawn card)', isOn: LOGGING_SWITCH);
        
        // Update the main state's myDrawnCard to null (same as backend)
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
      }
      
      // Log pile contents after successful play
      final drawPileCount = (gameState['drawPile'] as List?)?.length ?? 0;
      final discardPileCount = (gameState['discardPile'] as List?)?.length ?? 0;

      Logger().info('Practice: === PILE CONTENTS AFTER PLAY ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Draw Pile Count: $drawPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Discard Pile Count: $discardPileCount', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Played Card: ${cardToPlay['cardId']}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: ================================', isOn: LOGGING_SWITCH);

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

      // Update all players' known_cards after successful card play
      updateKnownCards('play_card', playerId, [cardId]);

      // Move to next player (simplified turn management for practice)
      // await _moveToNextPlayer();
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling play card: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle same rank play action - validates rank match and moves card to discard pile
  /// Replicates backend's _handle_same_rank_play method in game_round.py lines 1000-1089
  Future<bool> handleSameRankPlay(String playerId, String cardId) async {
    try {
      Logger().info('Practice: Handling same rank play for player $playerId, card $cardId', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Find the player
      final player = players.firstWhere(
        (p) => p['id'] == playerId,
        orElse: () => <String, dynamic>{},
      );
      
      if (player.isEmpty) {
        Logger().error('Practice: Player $playerId not found for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Find the card in player's hand
      final hand = player['hand'] as List<dynamic>? ?? [];
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
        Logger().error('Practice: Card $cardId not found in player $playerId hand for same rank play', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Found card $cardId for same rank play in player $playerId hand at index $cardIndex', isOn: LOGGING_SWITCH);
      
      // Get full card data
      final playedCardFullData = _practiceCoordinator.getCardById(gameState, cardId);
      if (playedCardFullData == null) {
        Logger().error('Practice: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final cardRank = playedCardFullData['rank']?.toString() ?? '';
      final cardSuit = playedCardFullData['suit']?.toString() ?? '';
      
      // Check if card is in player's collection_rank_cards (cannot be played for same rank)
      final collectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      for (var collectionCard in collectionRankCards) {
        if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
          Logger().info('Practice: Card $cardId is a collection rank card and cannot be played for same rank', isOn: LOGGING_SWITCH);
          
          // Show error message to user via actionError state
          final stateManager = StateManager();
          final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
          stateManager.updateModuleState('recall_game', {
            ...currentState,
            'actionError': {
              'message': 'This card is in your collection and cannot be played for same rank.',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          });
          
          // No status change needed - status will change automatically when same rank window expires
          Logger().info('Practice: Collection rank card rejected - status will auto-expire with same rank window', isOn: LOGGING_SWITCH);
          
          return false;
        }
      }
      
      // Validate that this is actually a same rank play
      if (!_validateSameRankPlay(gameState, cardRank)) {
        Logger().error('Practice: Same rank validation failed for card $cardId with rank $cardRank', isOn: LOGGING_SWITCH);
        
        // Apply penalty: draw a card from the draw pile and add to player's hand
        Logger().info('Practice: Applying penalty for wrong same rank play - drawing card from draw pile', isOn: LOGGING_SWITCH);
        
        final drawPile = gameState['drawPile'] as List<Map<String, dynamic>>? ?? [];
        if (drawPile.isEmpty) {
          Logger().error('Practice: Cannot apply penalty - draw pile is empty', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Draw a card from the draw pile (remove last card)
        final penaltyCard = drawPile.removeLast();
        Logger().info('Practice: Drew penalty card ${penaltyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
        
        // Add penalty card to player's hand as ID-only (same format as regular hand cards)
        final penaltyCardIdOnly = {
          'cardId': penaltyCard['cardId'],
          'suit': '?',           // Face-down: hide suit
          'rank': '?',           // Face-down: hide rank
          'points': 0,           // Face-down: hide points
          'displayName': '?',    // Face-down: hide display name
          'color': 'black',      // Default color for face-down
          'ownerId': playerId,   // Keep owner info
        };
        
        hand.add(penaltyCardIdOnly);
        Logger().info('Practice: Added penalty card ${penaltyCard['cardId']} to player $playerId hand as ID-only', isOn: LOGGING_SWITCH);
        
        // Update player state to reflect the new hand
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
        
        Logger().info('Practice: Penalty applied successfully - player $playerId now has ${hand.length} cards', isOn: LOGGING_SWITCH);
        
        return false;
      }
      
      Logger().info('Practice: Same rank validation passed for card $cardId with rank $cardRank', isOn: LOGGING_SWITCH);
      
      // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
      // Check if we should create a blank slot or remove the card entirely
      final shouldCreateBlankSlot = _shouldCreateBlankSlotAtIndex(hand, cardIndex);
      
      if (shouldCreateBlankSlot) {
        // Replace the card with null (blank slot) to maintain index positions
        hand[cardIndex] = null;
        Logger().info('Practice: Created blank slot at index $cardIndex for same rank play', isOn: LOGGING_SWITCH);
      } else {
        // Remove the card entirely and shift remaining cards
        hand.removeAt(cardIndex);
        Logger().info('Practice: Removed same rank card entirely from index $cardIndex', isOn: LOGGING_SWITCH);
      }
      
      // Add card to discard pile using reusable method (ensures full data and proper state updates)
      final success = _practiceCoordinator.addToDiscardPile(playedCardFullData);
      if (!success) {
        Logger().error('Practice: Failed to add card $cardId to discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: ✅ Same rank play successful: $playerId played $cardRank of $cardSuit - card moved to discard pile', isOn: LOGGING_SWITCH);
      
      // Check for special cards (Jack/Queen) and store data if applicable
      _checkSpecialCard(playerId, {
        'cardId': cardId,
        'rank': playedCardFullData['rank'],
        'suit': playedCardFullData['suit']
      });
      
      // TODO: Store the play in same_rank_data for tracking (future implementation)
      // For now, we just log the successful play
      Logger().info('Practice: Same rank play data would be stored here (future implementation)', isOn: LOGGING_SWITCH);
      
      // Update all players' known_cards after successful same rank play
      updateKnownCards('same_rank_play', playerId, [cardId]);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Error handling same rank play: $e', isOn: LOGGING_SWITCH);
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
      Logger().info('Practice: Handling Jack swap for cards: $firstCardId (player $firstPlayerId) <-> $secondCardId (player $secondPlayerId)', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for Jack swap', isOn: LOGGING_SWITCH);
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
        Logger().error('Practice: Invalid Jack swap - one or both players not found', isOn: LOGGING_SWITCH);
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
        Logger().error('Practice: Invalid Jack swap - one or both cards not found in players\' hands', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Found cards - First card at index $firstCardIndex in player $firstPlayerId hand, Second card at index $secondCardIndex in player $secondPlayerId hand', isOn: LOGGING_SWITCH);

      // Perform the swap
      firstPlayerHand[firstCardIndex] = secondCard;
      secondPlayerHand[secondCardIndex] = firstCard;

      Logger().info('Practice: Successfully swapped cards: $firstCardId <-> $secondCardId', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Player $firstPlayerId now has card $secondCardId at index $firstCardIndex', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Player $secondPlayerId now has card $firstCardId at index $secondCardIndex', isOn: LOGGING_SWITCH);

      // Update game state to trigger UI updates
      final currentGames = _practiceCoordinator.currentGamesMap;
      _practiceCoordinator.updatePracticeGameState({
        'games': currentGames,
      });

      Logger().info('Practice: Jack swap completed - state updated', isOn: LOGGING_SWITCH);

      // Update all players' known_cards after successful Jack swap
      updateKnownCards('jack_swap', firstPlayerId, [firstCardId, secondCardId], swapData: {
        'sourcePlayerId': firstPlayerId,
        'targetPlayerId': secondPlayerId,
      });

      return true;

    } catch (e) {
      Logger().error('Practice: Error in handleJackSwap: $e', isOn: LOGGING_SWITCH);
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
      Logger().info('Practice: Handling Queen peek - player $peekingPlayerId peeking at card $targetCardId from player $targetPlayerId', isOn: LOGGING_SWITCH);

      // Get current game state
      final gameState = _getCurrentGameState();
      if (gameState == null) {
        Logger().error('Practice: Failed to get game state for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];

      // Find the target player (card owner)
      final targetPlayer = players.firstWhere(
        (p) => p['id'] == targetPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (targetPlayer.isEmpty) {
        Logger().error('Practice: Target player $targetPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
        return false;
      }

      // Find the peeking player (current player using Queen power)
      final peekingPlayer = players.firstWhere(
        (p) => p['id'] == peekingPlayerId,
        orElse: () => <String, dynamic>{},
      );

      if (peekingPlayer.isEmpty) {
        Logger().error('Practice: Peeking player $peekingPlayerId not found for Queen peek', isOn: LOGGING_SWITCH);
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
        Logger().error('Practice: Card $targetCardId not found in target player $targetPlayerId hand', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Found target card: ${targetCard['rank']} of ${targetCard['suit']}', isOn: LOGGING_SWITCH);

      // Get full card data (convert from ID-only if needed)
      final fullCardData = _practiceCoordinator.getCardById(gameState, targetCardId);
      if (fullCardData == null) {
        Logger().error('Practice: Failed to get full card data for $targetCardId', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Full card data: ${fullCardData['rank']} of ${fullCardData['suit']} (${fullCardData['points']} points)', isOn: LOGGING_SWITCH);

      // Clear any existing cards_to_peek from previous peeks (backend line 1304)
      final existingCardsToPeek = peekingPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      existingCardsToPeek.clear();
      Logger().info('Practice: Cleared existing cards_to_peek for player $peekingPlayerId', isOn: LOGGING_SWITCH);

      // Add the target card to the peeking player's cards_to_peek list (backend line 1307)
      peekingPlayer['cardsToPeek'] = [fullCardData];
      Logger().info('Practice: Added card ${fullCardData['cardId']} to player $peekingPlayerId cards_to_peek list', isOn: LOGGING_SWITCH);

      // Set player status to PEEKING (backend line 1311)
      peekingPlayer['status'] = 'peeking';
      Logger().info('Practice: Set player $peekingPlayerId status to peeking', isOn: LOGGING_SWITCH);

      // Update main state for the human player
      if (peekingPlayerId == 'practice_user') {
        final currentGames = _practiceCoordinator.currentGamesMap;
        _practiceCoordinator.updatePracticeGameState({
          'playerStatus': 'peeking',
          'myCardsToPeek': [fullCardData],
          'games': currentGames,
        });
        Logger().info('Practice: Updated main state for human player - myCardsToPeek updated', isOn: LOGGING_SWITCH);
      } else {
        // For computer players, just update the games map
        final currentGames = _practiceCoordinator.currentGamesMap;
        _practiceCoordinator.updatePracticeGameState({
          'games': currentGames,
        });
        Logger().info('Practice: Updated games state for computer player', isOn: LOGGING_SWITCH);
      }

      Logger().info('Practice: Queen peek completed successfully', isOn: LOGGING_SWITCH);

      return true;

    } catch (e) {
      Logger().error('Practice: Error in handleQueenPeek: $e', isOn: LOGGING_SWITCH);
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
        Logger().info('Practice: Same rank validation failed: No cards in discard pile', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the last card from the discard pile
      final lastCard = discardPile.last as Map<String, dynamic>?;
      if (lastCard == null) {
        Logger().info('Practice: Same rank validation failed: Last card is null', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final lastCardRank = lastCard['rank']?.toString() ?? '';
      
      Logger().info('Practice: Same rank validation: played_card_rank=\'$cardRank\', last_card_rank=\'$lastCardRank\'', isOn: LOGGING_SWITCH);
      
      // During same rank window, cards must match the rank of the last played card
      // No special cases - the window is triggered by a played card, so there's always a rank to match
      if (cardRank.toLowerCase() == lastCardRank.toLowerCase()) {
        Logger().info('Practice: Same rank validation: Ranks match, allowing play', isOn: LOGGING_SWITCH);
        return true;
      } else {
        Logger().info('Practice: Same rank validation: Ranks don\'t match (played: $cardRank, required: $lastCardRank), denying play', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Same rank validation error: $e', isOn: LOGGING_SWITCH);
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
        
        Logger().info('Practice: DEBUG: special_card_data length before adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        Logger().info('Practice: DEBUG: special_card_data length after adding Jack: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        Logger().info('Practice: Added Jack special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
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
        
        Logger().info('Practice: DEBUG: special_card_data length before adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        _specialCardData.add(specialCardInfo);
        Logger().info('Practice: DEBUG: special_card_data length after adding Queen: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
        Logger().info('Practice: Added Queen special card for player $playerId: $cardRank of $cardSuit (chronological order)', isOn: LOGGING_SWITCH);
        
      } else {
        // Not a special card, no action needed
        Logger().info('Practice: Card $cardRank is not a special card', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _checkSpecialCard: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle same rank window - sets all players to same_rank_window status
  /// Replicates backend's _handle_same_rank_window method in game_round.py lines 566-585
  void _handleSameRankWindow() {
    try {
      Logger().info('Practice: Starting same rank window - setting all players to same_rank_window status', isOn: LOGGING_SWITCH);
      
      // Use the unified updatePlayerStatus method with playerId = null to update ALL players
      // This will:
      // 1. Update all players' status in the games map
      // 2. Update playerStatus in main state (for MyHandWidget)
      // 3. Update currentPlayer and currentPlayerStatus (for OpponentsPanel)
      // 4. Update isMyTurn (for ActionBar and MyHandWidget)
      // 5. Update games map in main state (for all state slices)
      final success = _practiceCoordinator.updatePlayerStatus(
        'same_rank_window',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false, // Don't trigger instructions for same rank window
      );
      
      if (success) {
        Logger().info('Practice: Successfully set all players to same_rank_window status', isOn: LOGGING_SWITCH);
        
        // CRITICAL: Set gamePhase to same_rank_window to match backend behavior
        // Backend sets game_state.phase = GamePhase.SAME_RANK_WINDOW (game_round.py line 906)
        // This ensures collection from discard pile is properly blocked during same rank window
        _practiceCoordinator.updatePracticeGameState({
          'gamePhase': 'same_rank_window',
        });
        Logger().info('Practice: Set gamePhase to same_rank_window', isOn: LOGGING_SWITCH);
        
        // Start 5-second timer to automatically end same rank window
        // Matches backend behavior (game_round.py line 579)
        _startSameRankTimer();
      } else {
        Logger().error('Practice: Failed to set all players to same_rank_window status', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Error in _handleSameRankWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Start a 5-second timer for the same rank window
  /// Replicates backend's _start_same_rank_timer method in game_round.py lines 587-597
  void _startSameRankTimer() {
    try {
      Logger().info('Practice: Starting 5-second same rank window timer', isOn: LOGGING_SWITCH);
      
      // Cancel existing timer if any
      _sameRankTimer?.cancel();
      
      // Store timer reference for potential cancellation
      _sameRankTimer = Timer(const Duration(seconds: 5), () {
        _endSameRankWindow();
      });
      
    } catch (e) {
      Logger().error('Practice: Error starting same rank timer: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// End the same rank window and move to next player
  /// Replicates backend's _end_same_rank_window method in game_round.py lines 599-643
  void _endSameRankWindow() {
    try {
      Logger().info('Practice: Ending same rank window - resetting all players to waiting status', isOn: LOGGING_SWITCH);
      
      // TODO: Log same_rank_data if any players played matching cards (future implementation)
      // For now, we just log that window is ending
      Logger().info('Practice: No same rank plays recorded (simplified practice mode)', isOn: LOGGING_SWITCH);
      
      // Update all players' status to WAITING
      final success = _practiceCoordinator.updatePlayerStatus(
        'waiting',
        playerId: null, // null = update ALL players
        updateMainState: true,
        triggerInstructions: false,
      );
      
      if (success) {
        Logger().info('Practice: Successfully reset all players to waiting status', isOn: LOGGING_SWITCH);
        
        // CRITICAL: Reset gamePhase back to player_turn to match backend behavior
        // Backend transitions to ENDING_TURN phase (game_round.py line 634)
        // For practice game, we use player_turn as the main gameplay phase
        _practiceCoordinator.updatePracticeGameState({
          'gamePhase': 'player_turn',
        });
        Logger().info('Practice: Reset gamePhase to player_turn', isOn: LOGGING_SWITCH);
      } else {
        Logger().error('Practice: Failed to reset players to waiting status', isOn: LOGGING_SWITCH);
      }
      
      // TODO: Check if any player has no cards left (automatic win condition)
      // Future implementation - for now, we skip this check
      
      // Check for same rank plays from computer players
      _checkComputerPlayerSameRankPlays();
      
      // Check for special cards and handle them (backend game_round.py line 640)
      _handleSpecialCardsWindow();
      
    } catch (e) {
      Logger().error('Practice: Error ending same rank window: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Check for same rank plays from computer players during the same rank window
  /// TODO: Implement computer player AI logic for same rank plays
  void _checkComputerPlayerSameRankPlays() {
    try {
      Logger().info('Practice: Same rank check for computer players still needs to be done', isOn: LOGGING_SWITCH);
      
      // TODO: Implement computer player same rank play logic
      // - Check each computer player's hand for matching rank cards
      // - Decide which computer players should play matching cards
      // - Process computer player same rank plays
      // - Update game state accordingly
      
    } catch (e) {
      Logger().error('Practice: Error in _checkComputerPlayerSameRankPlays: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle special cards window - process each player's special card with 10-second timer
  /// Replicates backend's _handle_special_cards_window method in game_round.py lines 656-694
  void _handleSpecialCardsWindow() {
    try {
      // Check if we have any special cards played
      if (_specialCardData.isEmpty) {
        Logger().info('Practice: No special cards played in this round - moving to next player', isOn: LOGGING_SWITCH);
        // No special cards, go directly to next player
        _moveToNextPlayer();
        return;
      }
      
      Logger().info('Practice: === SPECIAL CARDS WINDOW ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: DEBUG: special_card_data length: ${_specialCardData.length}', isOn: LOGGING_SWITCH);
      
      // Count total special cards (stored chronologically)
      final totalSpecialCards = _specialCardData.length;
      Logger().info('Practice: Found $totalSpecialCards special cards played in chronological order', isOn: LOGGING_SWITCH);
      
      // Log details of all special cards in chronological order
      for (int i = 0; i < _specialCardData.length; i++) {
        final card = _specialCardData[i];
        Logger().info('Practice:   ${i+1}. Player ${card['player_id']}: ${card['rank']} of ${card['suit']} (${card['special_power']})', isOn: LOGGING_SWITCH);
      }
      
      // Create a working copy for processing (we'll remove cards as we process them)
      _specialCardPlayers = List<Map<String, dynamic>>.from(_specialCardData);
      
      Logger().info('Practice: Starting special card processing with ${_specialCardPlayers.length} cards', isOn: LOGGING_SWITCH);
      
      // Start processing the first player's special card
      _processNextSpecialCard();
      
    } catch (e) {
      Logger().error('Practice: Error in _handleSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Process the next player's special card with 10-second timer
  /// Replicates backend's _process_next_special_card method in game_round.py lines 696-739
  void _processNextSpecialCard() {
    try {
      // Check if we've processed all special cards (list is empty)
      if (_specialCardPlayers.isEmpty) {
        Logger().info('Practice: All special cards processed - moving to next player', isOn: LOGGING_SWITCH);
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
      
      Logger().info('Practice: Processing special card for player $playerId: $cardRank of $cardSuit', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Special Power: $specialPower', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Description: $description', isOn: LOGGING_SWITCH);
      Logger().info('Practice:   Remaining cards to process: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      
      // Set player status based on special power
      if (specialPower == 'jack_swap') {
        _practiceCoordinator.updatePlayerStatus('jack_swap', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId status set to jack_swap - 10 second timer started', isOn: LOGGING_SWITCH);
      } else if (specialPower == 'queen_peek') {
        _practiceCoordinator.updatePlayerStatus('queen_peek', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId status set to queen_peek - 10 second timer started', isOn: LOGGING_SWITCH);
      } else {
        Logger().warning('Practice: Unknown special power: $specialPower for player $playerId', isOn: LOGGING_SWITCH);
        // Remove this card and move to next
        _specialCardPlayers.removeAt(0);
        _processNextSpecialCard();
        return;
      }
      
      // Start 10-second timer for this player's special card play
      _specialCardTimer?.cancel();
      _specialCardTimer = Timer(const Duration(seconds: 10), () {
        _onSpecialCardTimerExpired();
      });
      Logger().info('Practice: 10-second timer started for player $playerId\'s $specialPower', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Error in _processNextSpecialCard: $e', isOn: LOGGING_SWITCH);
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
            Logger().info('Practice: Cleared cardsToPeek for player $playerId - cards reverted to ID-only', isOn: LOGGING_SWITCH);
            
            // Update main state for human player
            if (playerId == 'practice_user') {
              _practiceCoordinator.updatePracticeGameState({
                'myCardsToPeek': [],
              });
              Logger().info('Practice: Updated main state myCardsToPeek to empty list', isOn: LOGGING_SWITCH);
            }
          }
        }
        
        _practiceCoordinator.updatePlayerStatus('waiting', playerId: playerId, updateMainState: true);
        Logger().info('Practice: Player $playerId special card timer expired - status reset to waiting', isOn: LOGGING_SWITCH);
        
        // Remove the processed card from the list
        _specialCardPlayers.removeAt(0);
        Logger().info('Practice: Removed processed card from list. Remaining cards: ${_specialCardPlayers.length}', isOn: LOGGING_SWITCH);
      }
      
      // Add 1-second delay for visual indication before processing next special card
      Logger().info('Practice: Waiting 1 second before processing next special card...', isOn: LOGGING_SWITCH);
      Timer(const Duration(seconds: 1), () {
        // Process next special card or end window
        _processNextSpecialCard();
      });
      
    } catch (e) {
      Logger().error('Practice: Error in _onSpecialCardTimerExpired: $e', isOn: LOGGING_SWITCH);
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
      
      Logger().info('Practice: Special cards window ended - cleared all special card data', isOn: LOGGING_SWITCH);
      
      // Now move to the next player
      Logger().info('Practice: Moving to next player after special cards', isOn: LOGGING_SWITCH);
      _moveToNextPlayer();
      
    } catch (e) {
      Logger().error('Practice: Error in _endSpecialCardsWindow: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Move to the next player (simplified version for practice)
  Future<void> _moveToNextPlayer() async {
    try {
      Logger().info('Practice: Moving to next player', isOn: LOGGING_SWITCH);
      
      // Get current game state
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameData = currentGames[_gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      
      if (currentPlayer == null || players.isEmpty) {
        Logger().error('Practice: No current player or players list for move to next player', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Set current player status to waiting before moving to next player
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      _practiceCoordinator.updatePlayerStatus('waiting', playerId: currentPlayerId, updateMainState: true);
      Logger().info('Practice: Set current player $currentPlayerId status to waiting', isOn: LOGGING_SWITCH);
      
      // Find current player index
      int currentIndex = -1;
      for (int i = 0; i < players.length; i++) {
        if (players[i]['id'] == currentPlayerId) {
          currentIndex = i;
          break;
        }
      }
      
      if (currentIndex == -1) {
        Logger().error('Practice: Current player $currentPlayerId not found in players list', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Move to next player (or first if at end)
      final nextIndex = (currentIndex + 1) % players.length;
      final nextPlayer = players[nextIndex];
      final nextPlayerId = nextPlayer['id']?.toString() ?? '';
      
      // Update current player in game state
      gameState['currentPlayer'] = nextPlayer;
      Logger().info('Practice: Updated game state currentPlayer to: ${nextPlayer['name']}', isOn: LOGGING_SWITCH);
      
      // Set new current player status to DRAWING_CARD (first action is to draw a card)
      _practiceCoordinator.updatePlayerStatus('drawing_card', playerId: nextPlayerId, updateMainState: true, triggerInstructions: true);
      Logger().info('Practice: Set next player ${nextPlayer['name']} to drawing_card status', isOn: LOGGING_SWITCH);
      
      // Check if this is a computer player and trigger computer turn logic
      final isHuman = nextPlayer['isHuman'] as bool? ?? false;
      if (!isHuman) {
        Logger().info('Practice: Computer player detected - triggering computer turn logic', isOn: LOGGING_SWITCH);
        _initComputerTurn(gameState);
      } else {
        Logger().info('Practice: Started turn for human player ${nextPlayer['name']} - status: drawing_card (no timer)', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Error moving to next player: $e', isOn: LOGGING_SWITCH);
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
      final currentGames = _practiceCoordinator.currentGamesMap;
      final gameId = _gameId;
      if (!currentGames.containsKey(gameId)) return;
      
      final gameData = currentGames[gameId];
      final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
      if (gameState == null) return;
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Process each player's known_cards
      for (final player in players) {
        final playerId = player['id'] as String;
        final difficulty = player['difficulty'] as String? ?? 'medium';
        final isHuman = player['isHuman'] as bool? ?? false;
        
        // Get remember probability based on difficulty
        final rememberProb = _getRememberProbability(difficulty);
        
        // Get player's known_cards
        final knownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
        
        if (eventType == 'play_card' || eventType == 'same_rank_play') {
          _processPlayCardUpdate(knownCards, affectedCardIds, rememberProb);
        } else if (eventType == 'jack_swap' && swapData != null) {
          _processJackSwapUpdate(knownCards, affectedCardIds, swapData, rememberProb);
        }
        
        player['known_cards'] = knownCards;
      }
      
      // Update state
      _practiceCoordinator.updatePracticeGameState({'games': currentGames});
      
      Logger().info('Practice: Updated known_cards for all players after $eventType', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to update known_cards: $e', isOn: LOGGING_SWITCH);
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
    double rememberProb
  ) {
    final random = Random();
    final playedCardId = affectedCardIds.isNotEmpty ? affectedCardIds[0] : null;
    if (playedCardId == null) return;
    
    // Iterate through each tracked player's cards
    final keysToRemove = <String>[];
    for (final entry in knownCards.entries) {
      final trackedPlayerId = entry.key;
      final trackedCards = entry.value as Map<String, dynamic>?;
      if (trackedCards == null) continue;
      
      // Check card1
      final card1 = trackedCards['card1'];
      final card1Id = _extractCardId(card1);
      if (card1Id == playedCardId) {
        // Roll probability: should this player remember the card was played?
        if (random.nextDouble() <= rememberProb) {
          // Remember: remove this card
          trackedCards['card1'] = null;
        }
        // Forget: do nothing, player "forgot" this card was played
      }
      
      // Check card2
      final card2 = trackedCards['card2'];
      final card2Id = _extractCardId(card2);
      if (card2Id == playedCardId) {
        if (random.nextDouble() <= rememberProb) {
          trackedCards['card2'] = null;
        }
      }
      
      // If both cards are now null, remove this player entry
      if (trackedCards['card1'] == null && trackedCards['card2'] == null) {
        keysToRemove.add(trackedPlayerId);
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
      final trackedCards = entry.value as Map<String, dynamic>?;
      if (trackedCards == null) continue;
      
      // Check card1
      final card1 = trackedCards['card1'];
      final card1Id = _extractCardId(card1);
      if (card1Id == cardId1 && trackedPlayerId == sourcePlayerId) {
        if (random.nextDouble() <= rememberProb) {
          // Remember: this card moved to targetPlayerId
          cardsToMove[targetPlayerId] = {'card1': card1};
          trackedCards['card1'] = null;
        }
        // Forget: remove the card
      } else if (card1Id == cardId2 && trackedPlayerId == targetPlayerId) {
        if (random.nextDouble() <= rememberProb) {
          // Remember: this card moved to sourcePlayerId
          cardsToMove[sourcePlayerId] = {'card1': card1};
          trackedCards['card1'] = null;
        }
      }
      
      // Check card2 (same logic)
      final card2 = trackedCards['card2'];
      final card2Id = _extractCardId(card2);
      if (card2Id == cardId1 && trackedPlayerId == sourcePlayerId) {
        if (random.nextDouble() <= rememberProb) {
          cardsToMove[targetPlayerId] = {'card2': card2};
          trackedCards['card2'] = null;
        }
      } else if (card2Id == cardId2 && trackedPlayerId == targetPlayerId) {
        if (random.nextDouble() <= rememberProb) {
          cardsToMove[sourcePlayerId] = {'card2': card2};
          trackedCards['card2'] = null;
        }
      }
      
      // If both cards are now null, remove this player entry
      if (trackedCards['card1'] == null && trackedCards['card2'] == null) {
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
      final cardToMove = entry.value;
      
      if (!knownCards.containsKey(newOwnerId)) {
        knownCards[newOwnerId] = {'card1': null, 'card2': null};
      }
      
      final ownerCards = knownCards[newOwnerId] as Map<String, dynamic>;
      if (ownerCards['card1'] == null) {
        ownerCards['card1'] = cardToMove['card1'] ?? cardToMove['card2'];
      } else if (ownerCards['card2'] == null) {
        ownerCards['card2'] = cardToMove['card1'] ?? cardToMove['card2'];
      }
    }
  }

  /// Extract card ID from card object or string
  String? _extractCardId(dynamic card) {
    if (card == null) return null;
    if (card is String) return card;
    if (card is Map) {
      return card['cardId']?.toString() ?? card['id']?.toString();
    }
    return null;
  }

  /// Dispose of resources
  void dispose() {
    _sameRankTimer?.cancel();
    _specialCardTimer?.cancel();
    Logger().info('Practice: PracticeGameRound disposed for game $_gameId', isOn: LOGGING_SWITCH);
  }
}
