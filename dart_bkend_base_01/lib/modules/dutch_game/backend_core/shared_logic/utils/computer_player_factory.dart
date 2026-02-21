import '../../../utils/platform/shared_imports.dart';

// Platform-specific import - must be imported from outside shared_logic
import '../../../utils/platform/computer_player_config_parser.dart';
import 'yaml_rules_engine.dart';

const bool LOGGING_SWITCH = true; // Enabled for computer same-rank decision process (getSameRankPlayDecisionByIndex, _selectSameRankCard)

/// Factory for creating computer player behavior based on YAML configuration
class ComputerPlayerFactory {
  final ComputerPlayerConfig config;
  final Random _random = Random();
  final Logger _logger = Logger();

  ComputerPlayerFactory(this.config);
  
  /// Calculate timer-based delay (randomized between 0.4 and 0.8 of timer value)
  /// [timerValue] The timer duration in seconds
  /// Returns delay in seconds (between 0.4 * timerValue and 0.8 * timerValue)
  double _calculateTimerBasedDelay(int timerValue) {
    final minDelay = timerValue * 0.4;
    final maxDelay = timerValue * 0.8;
    final delay = minDelay + (_random.nextDouble() * (maxDelay - minDelay));
    return delay;
  }
  
  /// Check if computer player misses the action (doesn't play)
  /// [difficulty] The difficulty level
  /// Returns true if player misses (should not play), false if should play
  bool _checkMissChance(String difficulty) {
    final missChance = config.getMissChanceToPlay(difficulty);
    return _random.nextDouble() < missChance;
  }

  /// Create factory from YAML file
  static Future<ComputerPlayerFactory> fromFile(String configPath) async {
    final logger = Logger();
    if (LOGGING_SWITCH) {
      logger.info('🏭 ComputerPlayerFactory.fromFile() START - configPath: $configPath');
    }
    
    try {
      final config = await ComputerPlayerConfig.fromFile(configPath);
      
      if (LOGGING_SWITCH) {
        logger.info('🏭 ComputerPlayerFactory: Config loaded successfully');
        final summary = config.getSummary();
        logger.info('🏭 ComputerPlayerFactory: Config summary - difficulties: ${summary['total_difficulties']}, events: ${summary['supported_events']}, version: ${summary['config_version']}');
      }
      
      final factory = ComputerPlayerFactory(config);
      
      if (LOGGING_SWITCH) {
        logger.info('🏭 ComputerPlayerFactory.fromFile() SUCCESS');
      }
      
      return factory;
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        logger.error('🏭 ComputerPlayerFactory.fromFile() ERROR: $e', error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Create factory from YAML string
  static ComputerPlayerFactory fromString(String yamlString) {
    final config = ComputerPlayerConfig.fromString(yamlString);
    return ComputerPlayerFactory(config);
  }

  /// Get computer player decision for draw card event
  Map<String, dynamic> getDrawCardDecision(String difficulty, Map<String, dynamic> gameState) {
    // Get timer config from gameState
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final drawingCardTimeLimit = timerConfig['drawing_card'] ?? 5;
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(drawingCardTimeLimit);
    
    final drawFromDiscardProb = config.getDrawFromDiscardProbability(difficulty);
    
    // Simulate decision making with delay
    final shouldDrawFromDiscard = _random.nextDouble() < drawFromDiscardProb;
    
    return {
      'action': 'draw_card',
      'source': shouldDrawFromDiscard ? 'discard' : 'deck',
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': shouldDrawFromDiscard 
        ? 'Drawing from discard pile (${(drawFromDiscardProb * 100).toStringAsFixed(1)}% probability)'
        : 'Drawing from deck (${((1 - drawFromDiscardProb) * 100).toStringAsFixed(1)}% probability)',
    };
  }

  /// Get computer player decision for play card event
  Map<String, dynamic> getPlayCardDecision(String difficulty, Map<String, dynamic> gameState, List<String> availableCards) {
    // Get player info for logging
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    final playerName = currentPlayer?['name']?.toString() ?? 'unknown';
    final playerRank = currentPlayer?['rank']?.toString() ?? 'unknown';
    
    // Get timer config from gameState (if available) to influence decisions based on time pressure
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final playingCardTimeLimit = timerConfig['playing_card'] ?? 15;
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(playingCardTimeLimit);
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: 🎯 BEFORE YAML PARSING (getPlayCardDecision) - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, AvailableCards: ${availableCards.length}, TimeLimit: ${playingCardTimeLimit}s, Delay: ${decisionDelay.toStringAsFixed(2)}s');
    };
    
    // Check miss chance first (before selecting card)
    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Player $playerName missed play action (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      };
      return {
        'action': 'play_card',
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed play action (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }
    
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final evaluationWeights = config.getCardEvaluationWeights();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: 📋 YAML Config Loaded - Difficulty: $difficulty, DecisionDelay: ${decisionDelay.toStringAsFixed(2)}s, Strategy: ${cardSelection['strategy']}, Weights: $evaluationWeights');
    };
    
    if (availableCards.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No cards available to play');
      };
      return {
        'action': 'play_card',
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No cards available to play',
      };
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Available cards: $availableCards');
    };
    
    // Select card based on strategy
    // Pass timerConfig to _selectCard so it can adjust strategy based on time pressure
    final selectedCard = _selectCard(availableCards, cardSelection, evaluationWeights, gameState, timerConfig: timerConfig);
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: ✅ AFTER YAML PARSING (getPlayCardDecision) - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, SelectedCard: $selectedCard, Strategy: ${cardSelection['strategy']}');
    };
    
    return {
      'action': 'play_card',
      'card_id': selectedCard,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Selected card using ${cardSelection['strategy'] ?? 'random'} strategy',
    };
  }

  /// Get computer player decision for same rank play event with YAML-driven intelligence
  Map<String, dynamic> getSameRankPlayDecision(String difficulty, Map<String, dynamic> gameState, List<String> availableCards) {
    // Get timer config from gameState
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final sameRankTimeLimit = timerConfig['same_rank_window'] ?? 5;
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(sameRankTimeLimit);
    
    // Check miss chance first (before checking play probability)
    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Same rank play missed (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      };
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed same rank play (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }
    
    final playProbability = config.getSameRankPlayProbability(difficulty);
    final wrongRankProbability = config.getWrongRankProbability(difficulty);
    
    // Check if computer player will attempt to play (existing play probability logic)
    final shouldAttempt = _random.nextDouble() < playProbability;
    
    if (!shouldAttempt || availableCards.isEmpty) {
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'Decided not to play same rank (${((1 - playProbability) * 100).toStringAsFixed(1)}% miss probability)',
      };
    }
    
    // Check if computer player will play wrong card (accuracy)
    final willPlayWrong = _random.nextDouble() < wrongRankProbability;
    
    if (willPlayWrong) {
      // Get all cards from hand that are NOT the same rank
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer != null) {
        // Get last card rank from discard pile
        final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
        if (discardPile.isNotEmpty) {
          final lastCard = discardPile.last as Map<String, dynamic>?;
          final targetRank = lastCard?['rank']?.toString() ?? '';
          // Get wrong cards (different rank from known_cards)
          final knownCardsList = _getKnownCardsList(currentPlayer);
          final wrongCards = knownCardsList.where((c) => _getCardRank(c, gameState) != targetRank).toList();
          if (wrongCards.isNotEmpty) {
            final selectedCard = wrongCards[_random.nextInt(wrongCards.length)];
            return {
              'action': 'same_rank_play',
              'play': true,
              'card_id': selectedCard,
              'delay_seconds': decisionDelay,
              'difficulty': difficulty,
              'reasoning': 'Playing WRONG card (inaccuracy: ${(wrongRankProbability * 100).toStringAsFixed(1)}%)',
            };
          }
        }
      }
    }
    
    // Play correct card using YAML rules
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final evaluationWeights = config.getCardEvaluationWeights();
    final selectedCard = _selectSameRankCard(availableCards, cardSelection, evaluationWeights, gameState);
    
    return {
      'action': 'same_rank_play',
      'play': true,
      'card_id': selectedCard,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Playing same rank card using YAML strategy (${(playProbability * 100).toStringAsFixed(1)}% play probability)',
    };
  }

  /// Get computer player same rank decision by index (computer path: uses known_cards handIndex only).
  /// [availableByIndex] list of {handIndex: int, cardId: String} from known_cards same-rank entries.
  /// [wrongRankIndices] hand indices where known_cards has a card of different rank (for wrong-card play).
  /// Returns play and card_index (hand index to play); round will play hand[card_index] (may get penalty if stale).
  Map<String, dynamic> getSameRankPlayDecisionByIndex(
    String difficulty,
    Map<String, dynamic> gameState,
    List<Map<String, dynamic>> availableByIndex,
    List<int> wrongRankIndices,
  ) {
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final sameRankTimeLimit = timerConfig['same_rank_window'] ?? 5;
    final decisionDelay = _calculateTimerBasedDelay(sameRankTimeLimit);

    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Same rank play missed (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      }
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_index': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed same rank play (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }

    final playProbability = config.getSameRankPlayProbability(difficulty);
    final shouldAttempt = _random.nextDouble() < playProbability;

    if (!shouldAttempt || availableByIndex.isEmpty) {
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_index': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'Decided not to play same rank (${((1 - playProbability) * 100).toStringAsFixed(1)}% miss probability)',
      };
    }

    final availableCardIds = availableByIndex.map((e) => e['cardId'] as String? ?? '').where((id) => id.isNotEmpty).toList();
    if (availableCardIds.isEmpty) {
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_index': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No valid same rank cards by index',
      };
    }
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final evaluationWeights = config.getCardEvaluationWeights();
    final selectedCardId = _selectSameRankCard(availableCardIds, cardSelection, evaluationWeights, gameState);
    final selectedEntry = availableByIndex.firstWhere(
      (e) => (e['cardId'] as String? ?? '') == selectedCardId,
      orElse: () => availableByIndex.first,
    );
    final cardIndex = selectedEntry['handIndex'] is int
        ? selectedEntry['handIndex'] as int
        : (selectedEntry['handIndex'] as num?)?.toInt() ?? 0;

    return {
      'action': 'same_rank_play',
      'play': true,
      'card_index': cardIndex,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Playing same rank card using YAML strategy (${(playProbability * 100).toStringAsFixed(1)}% play probability)',
    };
  }

  /// Get computer player decision for Jack swap event
  Map<String, dynamic> getJackSwapDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    // Get player info for logging
    final players = gameState['players'] as List<dynamic>? ?? [];
    final player = players.firstWhere(
      (p) => p['id']?.toString() == playerId,
      orElse: () => <String, dynamic>{},
    );
    final playerName = player['name']?.toString() ?? playerId;
    final playerRank = player['rank']?.toString() ?? 'unknown';
    
    // Get timer config from gameState
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final jackSwapTimeLimit = timerConfig['jack_swap'] ?? 10;
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(jackSwapTimeLimit);
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: 🎯 BEFORE YAML PARSING (getJackSwapDecision) - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, TimeLimit: ${jackSwapTimeLimit}s, Delay: ${decisionDelay.toStringAsFixed(2)}s');
    };
    
    // Check miss chance first
    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Jack swap missed (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      };
      return {
        'action': 'jack_swap',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed Jack swap (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }

    // Jack swap flow: build game data → strategy loop (probability then try strategy; if no valid swap, continue to next) → pass playerIds and cardIds to SSOT.
    final gameData = _prepareSpecialPlayGameData(gameState, playerId, difficulty);
    const jackSwapStrategies = [
      {'id': 'final_round_caller_swap', 'expert': 98, 'hard': 95, 'medium': 85, 'easy': 70},
      {'id': 'collection_three_swap', 'expert': 98, 'hard': 95, 'medium': 85, 'easy': 70},
      {'id': 'one_card_player_priority', 'expert': 98, 'hard': 95, 'medium': 85, 'easy': 70},
      {'id': 'lowest_opponent_higher_own', 'expert': 98, 'hard': 95, 'medium': 85, 'easy': 70},
      {'id': 'random_except_own', 'expert': 98, 'hard': 95, 'medium': 95, 'easy': 90},
    ];

    String? selectedStrategyId;
    String? firstCardId;
    String? firstPlayerId;
    String? secondCardId;
    String? secondPlayerId;

    for (final s in jackSwapStrategies) {
      final strategyId = s['id'] as String?;
      final percent = _jackSwapStrategyPercent(s as Map<String, dynamic>, difficulty);
      final roll = _random.nextDouble() * 100;
      if (roll >= percent) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: Jack swap strategy skipped: $strategyId (roll $roll >= $percent)');
        };
        continue;
      }
      selectedStrategyId = strategyId;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: Jack swap strategy selected: $selectedStrategyId (difficulty: $difficulty, %: $percent, roll: ${roll.toStringAsFixed(1)})');
      };
      final raw = _selectJackSwapTargets(gameData, selectedStrategyId!);
      firstCardId = raw['first_card_id']?.toString();
      firstPlayerId = raw['first_player_id']?.toString();
      secondCardId = raw['second_card_id']?.toString();
      secondPlayerId = raw['second_player_id']?.toString();
      final valid = firstCardId != null && firstCardId.isNotEmpty &&
          firstPlayerId != null && firstPlayerId.isNotEmpty &&
          secondCardId != null && secondCardId.isNotEmpty &&
          secondPlayerId != null && secondPlayerId.isNotEmpty;
      final alreadySwapped = valid && _jackSwapPairAlreadyUsed(gameState, playerId, firstCardId ?? '', secondCardId ?? '');
      if (valid && !alreadySwapped) {
        break;
      }
      // History post-filter: with difficulty-based probability, allow repeating the same pair anyway
      if (valid && alreadySwapped) {
        final allowRepeatPercent = _jackSwapAllowRepeatHistoryPercent(difficulty);
        final repeatRoll = _random.nextDouble() * 100;
        if (repeatRoll < allowRepeatPercent) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: Jack swap repeat allowed by difficulty ($difficulty: $allowRepeatPercent%) - using same pair [$firstCardId, $secondCardId]');
          }
          break;
        }
      }
      if (LOGGING_SWITCH) {
        if (alreadySwapped) {
          _logger.info('Dutch: Jack swap pair [$firstCardId, $secondCardId] already used by $playerId - trying next strategy');
        } else {
          _logger.info('Dutch: Jack swap strategy $selectedStrategyId produced no valid swap - trying next strategy');
        }
      };
    }

    if (firstCardId == null || firstCardId.isEmpty || firstPlayerId == null || firstPlayerId.isEmpty ||
        secondCardId == null || secondCardId.isEmpty || secondPlayerId == null || secondPlayerId.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: No Jack swap strategy produced a valid swap - skipping');
      };
      return {
        'action': 'jack_swap',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': selectedStrategyId != null
            ? 'Jack swap strategy $selectedStrategyId: no valid swap (tried all)'
            : 'No Jack swap strategy selected - skip',
      };
    }

    return {
      'action': 'jack_swap',
      'use': true,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'first_card_id': firstCardId,
      'first_player_id': firstPlayerId,
      'second_card_id': secondCardId,
      'second_player_id': secondPlayerId,
      'reasoning': 'Jack swap strategy: $selectedStrategyId',
    };
  }

  /// Probability (0-100) that the acting player is allowed to repeat a swap pair that's already in their history. Lower for expert, higher for easy.
  int _jackSwapAllowRepeatHistoryPercent(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'expert':
        return 0;
      case 'hard':
        return 2;
      case 'medium':
        return 8;
      case 'easy':
        return 15;
      default:
        return 8;
    }
  }

  /// True if this player already swapped this pair of cards (e.g. in a previous Jack in the same special-cards window).
  bool _jackSwapPairAlreadyUsed(Map<String, dynamic> gameState, String actingPlayerId, String card1Id, String card2Id) {
    final history = gameState['jack_swap_history'] as Map<String, dynamic>?;
    if (history == null) return false;
    final playerSwaps = history[actingPlayerId];
    if (playerSwaps is! Map) return false;
    for (final entry in (playerSwaps as Map<String, dynamic>).entries) {
      final value = entry.value;
      if (value is! List || value.length < 2) continue;
      final a = value[0]?.toString() ?? '';
      final b = value[1]?.toString() ?? '';
      if ((a == card1Id && b == card2Id) || (a == card2Id && b == card1Id)) return true;
    }
    return false;
  }

  /// Get strategy percentage for difficulty (0-100).
  int _jackSwapStrategyPercent(Map<String, dynamic> strategy, String difficulty) {
    final key = difficulty.toLowerCase();
    final v = strategy[key];
    if (v is int) return v.clamp(0, 100);
    if (v is num) return v.toInt().clamp(0, 100);
    return strategy['easy'] as int? ?? 60;
  }

  /// Get computer player decision for Queen peek event
  Map<String, dynamic> getQueenPeekDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    // Get player info for logging
    final players = gameState['players'] as List<dynamic>? ?? [];
    final player = players.firstWhere(
      (p) => p['id']?.toString() == playerId,
      orElse: () => <String, dynamic>{},
    );
    final playerName = player['name']?.toString() ?? playerId;
    final playerRank = player['rank']?.toString() ?? 'unknown';
    
    // Get timer config from gameState
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final queenPeekTimeLimit = timerConfig['queen_peek'] ?? 10;
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(queenPeekTimeLimit);
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: 🎯 BEFORE YAML PARSING (getQueenPeekDecision) - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, TimeLimit: ${queenPeekTimeLimit}s, Delay: ${decisionDelay.toStringAsFixed(2)}s');
    };
    
    // Check miss chance first
    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Queen peek missed (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      };
      return {
        'action': 'queen_peek',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed Queen peek (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareSpecialPlayGameData(gameState, playerId, difficulty);
    
    // Get event config from YAML
    final queenPeekConfig = config.getEventConfig('queen_peek');
    final strategyRules = queenPeekConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: 📋 YAML Config Loaded (queen_peek) - Difficulty: $difficulty, RulesCount: ${strategyRules.length}');
    };
    if (strategyRules.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}');
      };
    }
    
    // Determine shouldPlayOptimal based on difficulty (same pattern as getPlayCardDecision)
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final shouldPlayOptimal = cardSelection['should_play_optimal'] as bool? ?? 
      (difficulty == 'hard' || difficulty == 'expert');
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - shouldPlayOptimal: $shouldPlayOptimal');
    };
    
    // If no strategy rules defined, fallback to simple decision
    if (strategyRules.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - No YAML rules defined, using fallback logic');
      };
      return {
        'action': 'queen_peek',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No YAML rules defined',
      };
    }
    
    // Evaluate rules using YAML rules engine
    final decision = _evaluateSpecialPlayRules(strategyRules, gameData, shouldPlayOptimal, 'queen_peek');
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: ✅ AFTER YAML PARSING (getQueenPeekDecision) - Player: $playerName, Rank: $playerRank, Difficulty: $difficulty, Use: ${decision['use']}, Reasoning: ${decision['reasoning']}');
    };
    
    // Merge decision with timer-based delay and difficulty
    return {
      'action': 'queen_peek',
      'use': decision['use'] as bool? ?? false,
      'target_card_id': decision['target_card_id'] as String?,
      'target_player_id': decision['target_player_id'] as String?,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': decision['reasoning']?.toString() ?? 'Queen peek decision',
    };
  }

  /// Get computer player decision for collect from discard event
  /// Note: Rank matching is done in Dart before this method is called
  /// This method only handles AI decision (collect or not)
  Map<String, dynamic> getCollectFromDiscardDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - getCollectFromDiscardDecision called with difficulty: $difficulty, playerId: $playerId');
    };
    
    // Get timer config from gameState (collect uses same_rank_window timer since it's part of collection phase)
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final collectTimeLimit = timerConfig['same_rank_window'] ?? 5; // Use same_rank_window timer for collection
    
    // Calculate timer-based delay (0.4 to 0.8 of timer)
    final decisionDelay = _calculateTimerBasedDelay(collectTimeLimit);
    
    // Check miss chance first
    if (_checkMissChance(difficulty)) {
      final missChance = config.getMissChanceToPlay(difficulty);
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: ⚠️ MISS CHANCE - Collect from discard missed (${(missChance * 100).toStringAsFixed(1)}% miss chance)');
      };
      return {
        'action': 'collect_from_discard',
        'collect': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'missed': true,
        'reasoning': 'Missed collect from discard (${(missChance * 100).toStringAsFixed(1)}% miss chance)',
      };
    }
    
    // Prepare game data for YAML rules engine (includes discard pile top card)
    final gameData = _prepareSpecialPlayGameData(gameState, playerId, difficulty);
    
    // Add discard pile top card to game data
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    if (discardPile.isNotEmpty) {
      final topCard = discardPile.last as Map<String, dynamic>?;
      if (topCard != null) {
        gameData['discard_pile'] = {
          'top_card': Map<String, dynamic>.from(topCard),
        };
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Added discard pile top card: ${topCard['rank']} of ${topCard['suit']}');
        };
      }
    }
    
    // Get event config from YAML
    final collectConfig = config.getEventConfig('collect_from_discard');
    final strategyRules = collectConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - YAML strategy rules count: ${strategyRules.length}');
    };
    if (strategyRules.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}');
      };
    }
    
    // Determine shouldPlayOptimal based on difficulty (same pattern as other decisions)
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final shouldPlayOptimal = cardSelection['should_play_optimal'] as bool? ?? 
      (difficulty == 'hard' || difficulty == 'expert');
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - shouldPlayOptimal: $shouldPlayOptimal');
    };
    
    // If no strategy rules defined, fallback to simple decision
    if (strategyRules.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - No YAML rules defined, using fallback logic');
      };
      return {
        'action': 'collect_from_discard',
        'collect': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No YAML rules defined',
      };
    }
    
    // Evaluate rules using YAML rules engine
    final decision = _evaluateSpecialPlayRules(strategyRules, gameData, shouldPlayOptimal, 'collect_from_discard');
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - YAML rules engine returned decision: $decision');
    };
    
    // Convert 'use' to 'collect' for consistency with existing code
    final shouldCollect = decision['use'] as bool? ?? false;
    
    // Merge decision with timer-based delay and difficulty
    return {
      'action': 'collect_from_discard',
      'collect': shouldCollect,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': decision['reasoning']?.toString() ?? 'Collect from discard decision',
    };
  }

  /// Select a card based on strategy and evaluation weights
  /// [timerConfig] Optional timer configuration to influence decisions based on time pressure
  String _selectCard(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState, {Map<String, int>? timerConfig}) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _selectCard called with ${availableCards.length} available cards');
    };
    
    // Use timer config to influence decision-making based on time pressure
    // If time is short, prefer simpler/faster strategies
    final playingCardTimeLimit = timerConfig?['playing_card'] ?? 30;
    final isTimePressure = playingCardTimeLimit < 10; // Less than 10 seconds = time pressure
    
    if (isTimePressure) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Time pressure detected (${playingCardTimeLimit}s) - using faster decision strategy');
      };
    }
    
    final strategy = cardSelection['strategy'] ?? 'random';
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Strategy: $strategy, TimeLimit: ${playingCardTimeLimit}s, TimePressure: $isTimePressure');
    };
    
    // Get current player from game state
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    if (currentPlayer == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No current player found, using random fallback');
      };
      return availableCards[_random.nextInt(availableCards.length)];
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Current player: ${currentPlayer['name']}');
    };
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareGameDataForYAML(availableCards, currentPlayer, gameState);
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Game data prepared: ${gameData.keys.join(', ')}');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Available cards: ${gameData['available_cards']}');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Playable cards: ${gameData['playable_cards']}');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Unknown cards: ${gameData['unknown_cards']}');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Known cards: ${gameData['known_cards']}');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Collection cards: ${gameData['collection_cards']}');
    };
    
    // Get YAML rules from config
    final playCardConfig = config.getEventConfig('play_card');
    final strategyRules = playCardConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - YAML strategy rules count: ${strategyRules.length}');
    };
    if (strategyRules.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}');
      };
    }
    
    if (strategyRules.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - No YAML rules defined, using legacy logic');
      };
      // Fallback to old logic if no YAML rules defined
      return _selectCardLegacy(availableCards, cardSelection, evaluationWeights, gameState, timerConfig: timerConfig);
    }
    
    // Determine if we should play optimally
    // Adjust optimal play probability based on time pressure (less time = simpler decisions)
    var optimalPlayProb = _getOptimalPlayProbability(strategy);
    if (isTimePressure) {
      // Reduce optimal play probability under time pressure (favor simpler/faster decisions)
      optimalPlayProb = optimalPlayProb * 0.7; // 30% reduction in optimal play probability
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Time pressure: Reduced optimal play probability from ${_getOptimalPlayProbability(strategy)} to $optimalPlayProb');
      };
    }
    final shouldPlayOptimal = _random.nextDouble() < optimalPlayProb;
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Optimal play probability: $optimalPlayProb, Should play optimal: $shouldPlayOptimal');
    };
    
    // Add timer config to gameData so YAML rules engine can access it
    gameData['timer_config'] = timerConfig;
    gameData['time_pressure'] = isTimePressure;
    gameData['playing_card_time_limit'] = playingCardTimeLimit;
    
    // Execute YAML rules
    final rulesEngine = YamlRulesEngine();
    final result = rulesEngine.executeRules(strategyRules, gameData, shouldPlayOptimal);
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - YAML rules engine returned: $result');
    };
    
    return result;
  }
  
  /// Prepare game data for YAML rules engine
  Map<String, dynamic> _prepareGameDataForYAML(List<String> availableCards, 
                                                Map<String, dynamic> currentPlayer, 
                                                Map<String, dynamic> gameState) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _prepareGameDataForYAML called with ${availableCards.length} available cards');
    };
    
    // Get player's known_cards and collection_rank_cards
    final knownCards = currentPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    final collectionRankCards = currentPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = collectionRankCards.map((c) {
      if (c is Map<String, dynamic>) {
        return c['cardId']?.toString() ?? c['id']?.toString() ?? '';
      }
      return c.toString();
    }).where((id) => id.isNotEmpty).toSet();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Player known_cards: $knownCards');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Player collection_rank_cards: ${collectionRankCards.length} cards');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Collection card IDs: $collectionCardIds');
    };
    
    // Filter out collection rank cards
    final playableCards = availableCards.where((cardId) => !collectionCardIds.contains(cardId)).toList();
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Playable cards (after filtering collection): ${playableCards.length}');
    };
    
    // Extract player's own known card IDs (card-ID-based structure)
    final knownCardIds = <String>{};
    final playerId = currentPlayer['id']?.toString() ?? '';
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
      _logger.info('Dutch: DEBUG - Known card IDs: $knownCardIds');
    };
    
    // Get unknown cards
    final unknownCards = playableCards.where((cardId) => !knownCardIds.contains(cardId)).toList();
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Unknown cards: ${unknownCards.length}');
    };
    
    // Get known playable cards
    final knownPlayableCards = playableCards.where((cardId) => knownCardIds.contains(cardId)).toList();
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Known playable cards: ${knownPlayableCards.length}');
    };
    
    // Filter out null cards and collection cards from all lists
    availableCards.removeWhere((card) => card.toString() == 'null');
    playableCards.removeWhere((card) => card.toString() == 'null');
    unknownCards.removeWhere((card) => card.toString() == 'null');
    knownPlayableCards.removeWhere((card) => card.toString() == 'null');
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - After null filtering - Available: ${availableCards.length}, Playable: ${playableCards.length}, Unknown: ${unknownCards.length}, Known: ${knownPlayableCards.length}');
    };
    
    // Get all cards data for filters
    final allCardsData = <Map<String, dynamic>>[];
    final players = gameState['players'] as List<dynamic>? ?? [];
    for (final player in players) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card is Map<String, dynamic>) {
          allCardsData.add(card);
        }
      }
    }
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - All cards data: ${allCardsData.length} cards');
    };
    
    // Return comprehensive game data
    final result = {
      'available_cards': availableCards,
      'playable_cards': playableCards,
      'unknown_cards': unknownCards,
      'known_cards': knownPlayableCards,
      'collection_cards': collectionCardIds.toList(),
      'all_cards_data': allCardsData,
      'current_player': currentPlayer,
      'game_state': gameState,
    };
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Prepared game data with keys: ${result.keys.join(', ')}');
    };
    
    return result;
  }
  
  /// Legacy card selection (fallback if YAML rules not defined)
  String _selectCardLegacy(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState, {Map<String, int>? timerConfig}) {
    final strategy = cardSelection['strategy'] ?? 'random';
    
    // Get current player from game state
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    if (currentPlayer == null) {
      if (LOGGING_SWITCH) {
        _logger.error('Dutch: No current player found in game state');
      };
        return availableCards[_random.nextInt(availableCards.length)];
    }
    
    // Get player's known_cards and collection_rank_cards
    final knownCards = currentPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    final collectionRankCards = currentPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = collectionRankCards.map((c) {
      if (c is Map<String, dynamic>) {
        return c['cardId']?.toString() ?? c['id']?.toString() ?? '';
      }
      return c.toString();
    }).where((id) => id.isNotEmpty).toSet();
    
    // Filter out collection rank cards from available cards
    final playableCards = availableCards.where((cardId) => !collectionCardIds.contains(cardId)).toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Available cards: ${availableCards.length}, Playable cards: ${playableCards.length}, Collection cards: ${collectionCardIds.length}');
    };
    
    if (playableCards.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: All available cards are collection rank cards, using fallback');
      };
      return availableCards[_random.nextInt(availableCards.length)]; // Fallback if all are collection cards
    }
    
    // Extract known card IDs from known_cards structure
    final knownCardIds = <String>{};
    for (final playerKnownCards in knownCards.values) {
      if (playerKnownCards is Map) {
        if (playerKnownCards['card1'] != null) knownCardIds.add(playerKnownCards['card1'].toString());
        if (playerKnownCards['card2'] != null) knownCardIds.add(playerKnownCards['card2'].toString());
      }
    }
    
    // Strategy 1: Get unknown cards (cards NOT in known_cards)
    final unknownCards = playableCards.where((cardId) => !knownCardIds.contains(cardId)).toList();
    
    // Strategy 2: Get known cards with points (exclude Jacks)
    final knownPlayableCards = playableCards.where((cardId) => knownCardIds.contains(cardId)).toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Unknown cards: ${unknownCards.length}, Known playable cards: ${knownPlayableCards.length}');
    };
    
    // Determine if we should play optimally based on difficulty
    final optimalPlayProb = _getOptimalPlayProbability(strategy);
    final shouldPlayOptimal = _random.nextDouble() < optimalPlayProb;
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Strategy: $strategy, Optimal prob: $optimalPlayProb, Should play optimal: $shouldPlayOptimal');
    };
    
    if (shouldPlayOptimal) {
      // Best option: Random unknown card
      if (unknownCards.isNotEmpty) {
        final selectedCard = unknownCards[_random.nextInt(unknownCards.length)];
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Selected unknown card: $selectedCard');
        };
        return selectedCard;
      }
      
      // Fallback: Highest points from known cards (exclude Jacks)
      if (knownPlayableCards.isNotEmpty) {
        final selectedCard = _selectHighestPointsCard(knownPlayableCards, gameState);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Selected highest points card: $selectedCard');
        };
        return selectedCard;
      }
    }
    
    // Random fallback (for non-optimal play or if strategies fail)
    final selectedCard = playableCards[_random.nextInt(playableCards.length)];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selected random fallback card: $selectedCard');
    };
    return selectedCard;
  }
  
  /// Get probability of playing optimally based on difficulty
  double _getOptimalPlayProbability(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy': return 0.6;
      case 'medium': return 0.8;
      case 'hard': return 0.95;
      case 'expert': return 1.0;
      default: return 0.8;
    }
  }
  
  /// Select card with highest points from given card IDs, excluding Jacks
  String _selectHighestPointsCard(List<String> cardIds, Map<String, dynamic> gameState) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _selectHighestPointsCard called with ${cardIds.length} card IDs');
    };
    
    // Get all cards from game state (drawPile, discardPile, or player hands)
    final allCards = <Map<String, dynamic>>[];
    
    // Extract cards from players' hands
    final players = gameState['players'] as List<dynamic>? ?? [];
    for (final player in players) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card is Map<String, dynamic>) {
          allCards.add(card);
        }
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Found ${allCards.length} total cards in game state');
    };
    
    // Filter to only the cards we're considering
    final candidateCards = allCards.where((card) => cardIds.contains(card['id'])).toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Found ${candidateCards.length} candidate cards');
    };
    
    if (candidateCards.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: No candidate cards found, using random fallback');
      };
      return cardIds[_random.nextInt(cardIds.length)];
    }
    
    // Filter out Jacks
    final nonJackCards = candidateCards.where((card) => card['rank'] != 'jack').toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Found ${nonJackCards.length} non-Jack cards');
    };
    
    if (nonJackCards.isEmpty) {
      // If all are Jacks, return random
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: All candidate cards are Jacks, using random fallback');
      };
      return cardIds[_random.nextInt(cardIds.length)];
    }
    
    // Find card with highest points
    Map<String, dynamic>? highestCard;
    int highestPoints = -1;
    
    for (final card in nonJackCards) {
      final points = card['points'] as int? ?? 0;
      if (points > highestPoints) {
        highestPoints = points;
        highestCard = card;
      }
    }
    
    final selectedCard = highestCard?['id'] ?? cardIds[_random.nextInt(cardIds.length)];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selected highest points card: $selectedCard (points: $highestPoints)');
    };
    return selectedCard;
  }

  /// Select a same rank card using YAML rules engine
  String _selectSameRankCard(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState) {
    // Get current player from game state
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    if (currentPlayer == null) {
      return availableCards[_random.nextInt(availableCards.length)];
    }
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareSameRankGameData(availableCards, currentPlayer, gameState);
    
    // Get YAML rules from config
    final sameRankConfig = config.getEventConfig('same_rank_play');
    final strategyRules = sameRankConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    if (strategyRules.isEmpty) {
      // Fallback to random if no YAML rules defined
      return availableCards[_random.nextInt(availableCards.length)];
    }
    
    // Determine if we should play optimally
    final strategy = cardSelection['strategy'] ?? 'random';
    final optimalPlayProb = _getOptimalPlayProbability(strategy);
    final shouldPlayOptimal = _random.nextDouble() < optimalPlayProb;
    
    // Execute YAML rules
    final rulesEngine = YamlRulesEngine();
    return rulesEngine.executeRules(strategyRules, gameData, shouldPlayOptimal);
  }
  
  /// Prepare game data for same rank play YAML rules
  Map<String, dynamic> _prepareSameRankGameData(List<String> availableCards, Map<String, dynamic> currentPlayer, Map<String, dynamic> gameState) {
    final knownCards = currentPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    
    // Extract player's own known card IDs (card-ID-based structure)
    final knownCardIds = <String>{};
    final playerId = currentPlayer['id']?.toString() ?? '';
    final playerOwnKnownCards = knownCards[playerId] as Map<String, dynamic>?;
    if (playerOwnKnownCards != null) {
      for (final cardId in playerOwnKnownCards.keys) {
        if (cardId.toString().isNotEmpty) {
          knownCardIds.add(cardId.toString());
        }
      }
    }
    
    knownCardIds.remove('');
    knownCardIds.remove(null);
    
    // Split available cards into known and unknown
    final knownSameRankCards = availableCards.where((c) => knownCardIds.contains(c)).toList();
    final unknownSameRankCards = availableCards.where((c) => !knownCardIds.contains(c)).toList();
    
    // Filter out null cards from all same rank card lists
    availableCards.removeWhere((card) => card.toString() == 'null');
    knownSameRankCards.removeWhere((card) => card.toString() == 'null');
    unknownSameRankCards.removeWhere((card) => card.toString() == 'null');
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - After null filtering same rank - Available: ${availableCards.length}, Known: ${knownSameRankCards.length}, Unknown: ${unknownSameRankCards.length}');
    };
    
    // Get all cards data for point calculations
    final allCardsData = <Map<String, dynamic>>[];
    final players = gameState['players'] as List<dynamic>? ?? [];
    for (final player in players) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card is Map<String, dynamic>) {
          allCardsData.add(card);
        }
      }
    }
    
    return {
      'available_same_rank_cards': availableCards,
      'known_same_rank_cards': knownSameRankCards,
      'unknown_same_rank_cards': unknownSameRankCards,
      'all_cards_data': allCardsData,
    };
  }
  
  /// Prepare game data for special play YAML rules engine
  Map<String, dynamic> _prepareSpecialPlayGameData(
    Map<String, dynamic> gameState,
    String actingPlayerId,
    String difficulty,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _prepareSpecialPlayGameData called for player $actingPlayerId, difficulty: $difficulty');
    };
    
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Find acting player
    final actingPlayer = players.firstWhere(
      (p) => p is Map && (p['id']?.toString() ?? '') == actingPlayerId,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>?;
    
    if (actingPlayer == null || actingPlayer.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - Acting player $actingPlayerId not found');
      };
      return {
        'difficulty': difficulty,
        'acting_player_id': actingPlayerId,
        'acting_player': {'hand': [], 'known_cards': {}, 'collection_cards': []},
        'all_players': {},
        'game_state': gameState,
      };
    }
    
    // Extract acting player's hand (ID-only)
    final actingPlayerHand = <String>[];
    final actingPlayerHandRaw = actingPlayer['hand'] as List<dynamic>? ?? [];
    for (final card in actingPlayerHandRaw) {
      if (card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
        if (cardId.isNotEmpty && cardId != 'null') {
          actingPlayerHand.add(cardId);
        }
      } else if (card != null && card.toString() != 'null' && card.toString().isNotEmpty) {
        actingPlayerHand.add(card.toString());
      }
    }
    
    // Extract acting player's known cards (full data)
    final actingPlayerKnownCards = <String, Map<String, dynamic>>{};
    final knownCards = actingPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Acting player known_cards structure: ${knownCards.keys.toList()}');
    };
    
    final actingPlayerKnownCardsRaw = knownCards[actingPlayerId] as Map<String, dynamic>?;
    
    if (actingPlayerKnownCardsRaw != null) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Found known_cards entry for acting player $actingPlayerId with ${actingPlayerKnownCardsRaw.length} cards');
      };
      for (final entry in actingPlayerKnownCardsRaw.entries) {
        final cardId = entry.key.toString();
        if (cardId.isNotEmpty && cardId != 'null') {
          if (entry.value is Map<String, dynamic>) {
            actingPlayerKnownCards[cardId] = Map<String, dynamic>.from(entry.value as Map);
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Added known card: $cardId');
            };
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('Dutch: DEBUG - Known card entry value is not a Map: ${entry.value.runtimeType}');
            };
          }
        }
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No known_cards entry found for acting player $actingPlayerId in known_cards structure');
      };
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Known_cards structure keys: ${knownCards.keys.toList()}');
      };
    }
    
    // Extract acting player's collection cards (full data) - only if collection mode is enabled
    final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? false;
    final actingPlayerCollectionCards = <Map<String, dynamic>>[];
    if (isClearAndCollect) {
      final collectionRankCards = actingPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
      for (final card in collectionRankCards) {
        if (card is Map<String, dynamic>) {
          actingPlayerCollectionCards.add(Map<String, dynamic>.from(card));
        }
      }
    }
    
    // Extract all players' data
    final allPlayersData = <String, Map<String, dynamic>>{};
    for (final player in players) {
      if (player is! Map<String, dynamic>) continue;
      
      final playerId = player['id']?.toString() ?? '';
      if (playerId.isEmpty) continue;
      
      // Extract hand (ID-only)
      final hand = <String>[];
      final handRaw = player['hand'] as List<dynamic>? ?? [];
      for (final card in handRaw) {
        if (card is Map<String, dynamic>) {
          final cardId = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
          if (cardId.isNotEmpty && cardId != 'null') {
            hand.add(cardId);
          }
        } else if (card != null && card.toString() != 'null' && card.toString().isNotEmpty) {
          hand.add(card.toString());
        }
      }
      
      // Extract known card IDs (ID-only)
      final knownCardIds = <String>[];
      final playerKnownCards = player['known_cards'] as Map<String, dynamic>? ?? {};
      final playerOwnKnownCards = playerKnownCards[playerId] as Map<String, dynamic>?;
      if (playerOwnKnownCards != null) {
        for (final cardId in playerOwnKnownCards.keys) {
          if (cardId.toString().isNotEmpty && cardId.toString() != 'null') {
            knownCardIds.add(cardId.toString());
          }
        }
      }
      
      // Extract collection cards (full data) - only if collection mode is enabled
      final collectionCards = <Map<String, dynamic>>[];
      if (isClearAndCollect) {
        final playerCollectionCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
        for (final card in playerCollectionCards) {
          if (card is Map<String, dynamic>) {
            collectionCards.add(Map<String, dynamic>.from(card));
          }
        }
      }
      
      allPlayersData[playerId] = {
        'hand': hand,
        'known_card_ids': knownCardIds,
        'collection_cards': collectionCards,
      };
    }
    
    // Other players (excluding acting) who have exactly 1 card in hand (playable, excl. collection)
    final otherPlayersWithOneCard = <String>[];
    // Other players (excl. acting) who have 3+ cards in collection (only when isClearAndCollect)
    final otherPlayersWithThreeInCollection = <String>[];
    for (final entry in allPlayersData.entries) {
      final pid = entry.key;
      if (pid == actingPlayerId) continue;
      final pdata = entry.value;
      final phand = pdata['hand'] as List<dynamic>? ?? [];
      final pcol = pdata['collection_cards'] as List<dynamic>? ?? [];
      final pcolIds = pcol
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final playableCount = phand.where((id) => !pcolIds.contains(id.toString())).length;
      if (playableCount == 1) {
        otherPlayersWithOneCard.add(pid);
      }
      if (isClearAndCollect && pcol.length >= 3) {
        otherPlayersWithThreeInCollection.add(pid);
      }
    }
    
    // Get acting player's collection rank
    final actingPlayerCollectionRank = actingPlayer['collection_rank']?.toString() ?? '';
    
    final result = {
      'difficulty': difficulty,
      'acting_player_id': actingPlayerId,
      'acting_player': {
        'hand': actingPlayerHand,
        'known_cards': actingPlayerKnownCards,
        'collection_cards': actingPlayerCollectionCards,
        'collection_rank': actingPlayerCollectionRank,
      },
      'all_players': allPlayersData,
      'other_players_with_one_card': otherPlayersWithOneCard,
      'other_players_with_three_in_collection': otherPlayersWithThreeInCollection,
      'game_state': gameState,
      'isClearAndCollect': isClearAndCollect,
    };
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Prepared special play game data:');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG -   Acting player hand: ${actingPlayerHand.length} cards');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG -   Acting player known cards: ${actingPlayerKnownCards.length} cards');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG -   Acting player collection cards: ${actingPlayerCollectionCards.length} cards');
    };
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG -   All players data: ${allPlayersData.length} players');
    };
    
    return result;
  }

  /// Get list of known card IDs from player's known_cards
  List<String> _getKnownCardsList(Map<String, dynamic> playerData) {
    final knownCardIds = <String>[];
    final knownCards = playerData['known_cards'] as Map<String, dynamic>? ?? {};
    
    // Get current player's own known card IDs
    final playerId = playerData['id']?.toString() ?? '';
    final playerOwnKnownCards = knownCards[playerId] as Map<String, dynamic>?;
    if (playerOwnKnownCards != null) {
      for (final cardId in playerOwnKnownCards.keys) {
        if (cardId.toString().isNotEmpty) {
          knownCardIds.add(cardId.toString());
        }
      }
    }
    
    return knownCardIds;
  }
  
  /// Get rank of a card by its ID
  String? _getCardRank(String cardId, Map<String, dynamic> gameState) {
    final players = gameState['players'] as List<dynamic>? ?? [];
    for (final player in players) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card is Map<String, dynamic>) {
          if ((card['id'] == cardId || card['cardId'] == cardId)) {
            return card['rank']?.toString();
          }
        }
      }
    }
    return null;
  }

  /// Get full card data by its ID from gameState
  Map<String, dynamic>? _getCardById(Map<String, dynamic> gameState, String cardId) {
    // First, try to find in originalDeck
    final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
    for (final card in originalDeck) {
      if (card is Map<String, dynamic>) {
        final cardIdInDeck = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
        if (cardIdInDeck == cardId) {
          return Map<String, dynamic>.from(card);
        }
      }
    }
    
    // If not found in originalDeck, try players' hands
    final players = gameState['players'] as List<dynamic>? ?? [];
    for (final player in players) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card is Map<String, dynamic>) {
          final cardIdInHand = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
          if (cardIdInHand == cardId) {
            // If hand card has full data, return it
            if (card['rank'] != null && card['rank'] != '?') {
              return Map<String, dynamic>.from(card);
            }
          }
        }
      }
    }
    
    // Try discard pile
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    for (final card in discardPile) {
      if (card is Map<String, dynamic>) {
        final cardIdInDiscard = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
        if (cardIdInDiscard == cardId) {
          return Map<String, dynamic>.from(card);
        }
      }
    }
    
    // Try draw pile
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    for (final card in drawPile) {
      if (card is Map<String, dynamic>) {
        final cardIdInDraw = card['cardId']?.toString() ?? card['id']?.toString() ?? '';
        if (cardIdInDraw == cardId) {
          return Map<String, dynamic>.from(card);
        }
      }
    }
    
    return null;
  }

  /// Evaluate YAML strategy rules for special play decisions
  Map<String, dynamic> _evaluateSpecialPlayRules(
    List<dynamic> strategyRules,
    Map<String, dynamic> gameData,
    bool shouldPlayOptimal,
    String eventName,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _evaluateSpecialPlayRules called with ${strategyRules.length} rules, shouldPlayOptimal: $shouldPlayOptimal, eventName: $eventName');
    };
    
    if (strategyRules.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - No strategy rules defined, returning use: false');
      };
      return {
        'use': false,
        'reasoning': 'No strategy rules defined',
      };
    }
    
    // Sort rules by priority (ascending, lower priority = evaluated first)
    final sortedRules = List<Map<String, dynamic>>.from(strategyRules)
      ..sort((a, b) => (a['priority'] ?? 999).compareTo(b['priority'] ?? 999));
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Sorted rules by priority: ${sortedRules.map((r) => '${r['name']} (${r['priority']})').join(', ')}');
    };
    
    // Get difficulty for probability-based execution
    final difficulty = gameData['difficulty']?.toString() ?? 'medium';
    
    // Note: We always evaluate rules in priority order, using execution probability to determine which rule executes
    // shouldPlayOptimal only affects the probability thresholds, not whether we evaluate rules
    
    // Evaluate rules in priority order
    for (final rule in sortedRules) {
      final ruleName = rule['name']?.toString() ?? 'unnamed';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Evaluating rule: $ruleName');
      };
      
      final condition = rule['condition'] as Map<String, dynamic>?;
      if (condition != null) {
        final conditionResult = _evaluateSpecialPlayCondition(condition, gameData);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Rule $ruleName condition result: $conditionResult');
        };
        
        if (conditionResult) {
          // Check execution probability based on difficulty
          final executionProb = rule['execution_probability'] as Map<String, dynamic>?;
          if (executionProb != null) {
            final prob = (executionProb[difficulty] as num?)?.toDouble() ?? 1.0;
            final shouldExecute = _random.nextDouble() < prob;
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Rule $ruleName execution probability for $difficulty: $prob, shouldExecute: $shouldExecute');
            };
            
            if (!shouldExecute) {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: DEBUG - Rule $ruleName skipped due to execution probability');
              };
              continue; // Skip this rule and try next one
            }
          }
          
          final action = rule['action'] as Map<String, dynamic>?;
          if (action != null) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Rule $ruleName condition passed, executing action');
            };
            final result = _executeSpecialPlayAction(action, gameData, eventName, ruleName);
            
            // Check if result is valid (has valid targets)
            if (_isValidSpecialPlayResult(result, eventName)) {
              return result;
            } else {
              if (LOGGING_SWITCH) {
                _logger.info('Dutch: DEBUG - Rule $ruleName returned invalid result (no valid targets), trying next rule');
              };
              continue; // Try next rule
            }
          }
        }
      } else {
        // No condition means always true
        // Check execution probability based on difficulty
        final executionProb = rule['execution_probability'] as Map<String, dynamic>?;
        if (executionProb != null) {
          final prob = (executionProb[difficulty] as num?)?.toDouble() ?? 1.0;
          final shouldExecute = _random.nextDouble() < prob;
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Rule $ruleName execution probability for $difficulty: $prob, shouldExecute: $shouldExecute');
          };
          
          if (!shouldExecute) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Rule $ruleName skipped due to execution probability');
            };
            continue; // Skip this rule and try next one
          }
        }
        
        final action = rule['action'] as Map<String, dynamic>?;
        if (action != null) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Rule $ruleName has no condition, executing action');
          };
          final result = _executeSpecialPlayAction(action, gameData, eventName, ruleName);
          
          // Check if result is valid (has valid targets)
          if (_isValidSpecialPlayResult(result, eventName)) {
            return result;
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Rule $ruleName returned invalid result (no valid targets), trying next rule');
            };
            continue; // Try next rule
          }
        }
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - No rules matched, returning use: false');
    };
    
    // Ultimate fallback: return use: false
    return {
      'use': false,
      'reasoning': 'No rules matched',
    };
  }
  
  /// Evaluate a condition for special play rules
  bool _evaluateSpecialPlayCondition(Map<String, dynamic> condition, Map<String, dynamic> gameData) {
    final type = condition['type']?.toString() ?? 'always';
    
    switch (type) {
      case 'always':
        return true;
      
      case 'and':
        final conditions = condition['conditions'] as List<dynamic>? ?? [];
        return conditions.every((c) => _evaluateSpecialPlayCondition(c as Map<String, dynamic>, gameData));
      
      case 'or':
        final conditions = condition['conditions'] as List<dynamic>? ?? [];
        return conditions.any((c) => _evaluateSpecialPlayCondition(c as Map<String, dynamic>, gameData));
      
      case 'not':
        final subCondition = condition['condition'] as Map<String, dynamic>?;
        return subCondition != null ? !_evaluateSpecialPlayCondition(subCondition, gameData) : false;
      
      default:
        // Field-based condition
        return _evaluateSpecialPlayFieldCondition(condition, gameData);
    }
  }
  
  /// Evaluate a field-based condition for special play rules
  bool _evaluateSpecialPlayFieldCondition(Map<String, dynamic> condition, Map<String, dynamic> gameData) {
    final field = condition['field']?.toString();
    final operator = condition['operator']?.toString() ?? 'equals';
    final value = condition['value'];
    
    if (field == null) return false;
    
    // Handle nested field access (e.g., "all_players.playerId.hand")
    dynamic fieldValue = _getNestedFieldValue(gameData, field);
    
    switch (operator) {
      case 'not_empty':
        if (fieldValue is List) return fieldValue.isNotEmpty;
        if (fieldValue is Map) return fieldValue.isNotEmpty;
        return fieldValue != null;
      
      case 'empty':
        if (fieldValue is List) return fieldValue.isEmpty;
        if (fieldValue is Map) return fieldValue.isEmpty;
        return fieldValue == null;
      
      case 'equals':
        return fieldValue == value;
      
      case 'not_equals':
        return fieldValue != value;
      
      case 'greater_than':
        if (fieldValue is num && value is num) return fieldValue > value;
        return false;
      
      case 'less_than':
        if (fieldValue is num && value is num) return fieldValue < value;
        return false;
      
      case 'contains':
        if (fieldValue is List) return fieldValue.contains(value);
        if (fieldValue is String && value is String) return fieldValue.contains(value);
        return false;
      
      case 'length_equals':
        if (fieldValue is List && value is num) return fieldValue.length == value.toInt();
        if (fieldValue is Map && value is num) return fieldValue.length == value.toInt();
        return false;
      
      case 'exists':
        return fieldValue != null;
      
      default:
        return false;
    }
  }
  
  /// Get nested field value from game data (e.g., "all_players.playerId.hand")
  dynamic _getNestedFieldValue(Map<String, dynamic> gameData, String fieldPath) {
    final parts = fieldPath.split('.');
    dynamic current = gameData;
    
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current;
  }
  
  /// Check if a special play result has valid targets
  bool _isValidSpecialPlayResult(Map<String, dynamic> result, String eventName) {
    if (result['use'] != true) {
      return true; // use: false is always valid
    }
    
    if (eventName == 'jack_swap') {
      final firstCardId = result['first_card_id'] as String?;
      final secondCardId = result['second_card_id'] as String?;
      final secondPlayerId = result['second_player_id'] as String?;
      
      // Valid if we have both card IDs and second player ID
      return firstCardId != null && 
             firstCardId.isNotEmpty && 
             secondCardId != null && 
             secondCardId.isNotEmpty &&
             secondPlayerId != null &&
             secondPlayerId.isNotEmpty;
    } else if (eventName == 'queen_peek') {
      final targetCardId = result['target_card_id'] as String?;
      final targetPlayerId = result['target_player_id'] as String?;
      
      // Valid if we have both target card ID and target player ID
      return targetCardId != null && 
             targetCardId.isNotEmpty && 
             targetPlayerId != null &&
             targetPlayerId.isNotEmpty;
    } else if (eventName == 'collect_from_discard') {
      // For collect_from_discard, use: true means we should collect
      // The action execution already validates rank matching
      return true; // Always valid if use: true (rank matching is done in action execution)
    }
    
    return true; // Default to valid for other events
  }
  
  /// Execute a special play action and return decision
  Map<String, dynamic> _executeSpecialPlayAction(
    Map<String, dynamic> action,
    Map<String, dynamic> gameData,
    String eventName,
    String ruleName,
  ) {
    final actionType = action['type']?.toString() ?? 'skip_special_play';
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _executeSpecialPlayAction called with actionType: $actionType, eventName: $eventName, ruleName: $ruleName');
    };
    
    switch (actionType) {
      case 'use_special_play':
        if (eventName == 'jack_swap') {
          // Get target strategy from action
          final targetStrategy = action['target_strategy']?.toString() ?? 'random';
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Executing jack_swap with target strategy: $targetStrategy');
          };
          
          // Select targets based on strategy
          final targets = _selectJackSwapTargets(gameData, targetStrategy);
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Target selection result: $targets');
          };
          
          return {
            'use': true,
            'first_card_id': targets['first_card_id'] as String?,
            'second_card_id': targets['second_card_id'] as String?,
            'first_player_id': targets['first_player_id'] as String? ?? gameData['acting_player_id']?.toString(),
            'second_player_id': targets['second_player_id'] as String?,
            'reasoning': ruleName,
          };
        } else if (eventName == 'queen_peek') {
          // Get target strategy from action
          final targetStrategy = action['target_strategy']?.toString() ?? 'random';
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Executing queen_peek with target strategy: $targetStrategy');
          };
          
          // Select targets based on strategy
          final targets = _selectQueenPeekTargets(gameData, targetStrategy);
          
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Target selection result: $targets');
          };
          
          return {
            'use': true,
            'target_card_id': targets['target_card_id'] as String?,
            'target_player_id': targets['target_player_id'] as String?,
            'reasoning': ruleName,
          };
        }
        return {
          'use': true,
          'reasoning': ruleName,
        };
      
      case 'collect_from_discard':
        // Check if collection mode is enabled
        final isClearAndCollect = gameData['isClearAndCollect'] as bool? ?? false;
        if (!isClearAndCollect) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Collection disabled - isClearAndCollect is false');
          };
          return {
            'use': false,
            'reasoning': 'collection_disabled',
          };
        }
        
        // For collect_from_discard, we need to check if conditions are met
        // Rule 1: Check if player has 3 collection cards and this is the only remaining card with same rank
        // Rule 2: Check if same rank as collection rank (simpler check)
        
        final actingPlayer = gameData['acting_player'] as Map<String, dynamic>? ?? {};
        final actingPlayerCollectionCards = actingPlayer['collection_cards'] as List<dynamic>? ?? [];
        final discardPile = gameData['discard_pile'] as Map<String, dynamic>?;
        final topCard = discardPile?['top_card'] as Map<String, dynamic>?;
        final actingPlayerCollectionRank = actingPlayer['collection_rank']?.toString() ?? '';
        
        if (topCard == null) {
          if (LOGGING_SWITCH) {
            _logger.warning('Dutch: DEBUG - No discard pile top card found, skipping collection');
          };
          return {
            'use': false,
            'reasoning': ruleName,
          };
        }
        
        final topCardRank = topCard['rank']?.toString() ?? '';
        
        // Check if rank matches collection rank
        if (topCardRank.toLowerCase() != actingPlayerCollectionRank.toLowerCase()) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Top card rank $topCardRank does not match collection rank $actingPlayerCollectionRank');
          };
          return {
            'use': false,
            'reasoning': ruleName,
          };
        }
        
        // Rule 1: If player has 3 collection cards and rank matches, collect it (will complete 4 of a kind)
        if (ruleName == 'collect_if_completes_set' && actingPlayerCollectionCards.length == 3) {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Player has 3 collection cards, collecting 4th card to complete set');
          };
          return {
            'use': true,
            'reasoning': ruleName,
          };
        }
        
        // Rule 2: If same rank as collection rank, collect it
        if (ruleName == 'collect_if_same_rank') {
          if (LOGGING_SWITCH) {
            _logger.info('Dutch: DEBUG - Top card rank matches collection rank, collecting it');
          };
          return {
            'use': true,
            'reasoning': ruleName,
          };
        }
        
        // Default: collect if rank matches
        return {
          'use': true,
          'reasoning': ruleName,
        };
      
      case 'skip_collect':
        return {
          'use': false,
          'reasoning': ruleName,
        };
      
      case 'skip_special_play':
        return {
          'use': false,
          'reasoning': ruleName,
        };
      
      default:
        return {
          'use': false,
          'reasoning': 'Unknown action type: $actionType',
        };
    }
  }
  
  /// Select Jack swap targets based on strategy
  Map<String, dynamic> _selectJackSwapTargets(
    Map<String, dynamic> gameData,
    String targetStrategy,
  ) {
    final actingPlayerId = gameData['acting_player_id']?.toString() ?? '';
    final actingPlayer = gameData['acting_player'] as Map<String, dynamic>? ?? {};
    final allPlayers = gameData['all_players'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _selectJackSwapTargets called with strategy: $targetStrategy');
    };
    
    switch (targetStrategy) {
      case 'collection_three_swap':
        // Rule 1: When isClearAndCollect, swap involving players with 3+ in collection (last in list)
        return _selectCollectionThreeSwap(actingPlayerId, gameData);
      
      case 'final_round_caller_swap':
        // Rule: When final round is active, swap with caller: if we know caller's cards, swap our higher with their lower; else swap our highest with any of their cards
        return _selectFinalRoundCallerSwap(actingPlayerId, actingPlayer, allPlayers, gameState);
      
      case 'one_card_player_priority':
        // Rule 2: Swap involving a player who has only 1 card (priority); other card from any other player
        return _selectOneCardPlayerPriority(actingPlayerId, gameData);
      
      case 'lowest_opponent_higher_own':
        // Rule 3: Find lowest opponent card and higher own card
        return _selectLowestOpponentHigherOwn(actingPlayerId, actingPlayer, allPlayers, gameState);
      
      case 'random_except_own':
        // Rule 4 (last): Random swap of 2 cards from other players only (excl. collection, not our hand)
        return _selectRandomExceptOwn(actingPlayerId, allPlayers, gameState);
      
      default:
        // No valid strategy -> return empty so caller skips
        return {
          'first_card_id': null,
          'first_player_id': actingPlayerId,
          'second_card_id': null,
          'second_player_id': null,
        };
    }
  }
  
  /// Rule 1: When isClearAndCollect, swap last collection card(s): 2+ players with 3 in collection -> swap last from each; else swap last from one with any non-collection from another
  Map<String, dynamic> _selectCollectionThreeSwap(String actingPlayerId, Map<String, dynamic> gameData) {
    final isClearAndCollect = gameData['isClearAndCollect'] as bool? ?? false;
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: collection_three_swap - entry actingPlayerId=$actingPlayerId isClearAndCollect=$isClearAndCollect');
    };
    final allPlayers = gameData['all_players'] as Map<String, dynamic>? ?? {};
    final threeInColIds = (gameData['other_players_with_three_in_collection'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((id) => id.isNotEmpty && id != 'null')
        .toList();
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: collection_three_swap - ${threeInColIds.length} players with 3+ in collection: $threeInColIds');
    };
    if (threeInColIds.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap - no players with 3+ in collection, skipping');
      };
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    // Two or more players (excl. acting) have 3 in collection: swap last card from each player's collection list
    if (threeInColIds.length >= 2) {
      threeInColIds.shuffle(_random);
      final firstPlayerId = threeInColIds[0];
      final secondPlayerId = threeInColIds[1];
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap - 2-player path: selected players $firstPlayerId, $secondPlayerId');
      };
      final firstCol = (allPlayers[firstPlayerId] as Map<String, dynamic>? ?? {})['collection_cards'] as List<dynamic>? ?? [];
      final secondCol = (allPlayers[secondPlayerId] as Map<String, dynamic>? ?? {})['collection_cards'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap - collection sizes: $firstPlayerId=${firstCol.length}, $secondPlayerId=${secondCol.length}');
      };
      if (firstCol.isEmpty || secondCol.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: collection_three_swap - one or both collections empty, skipping');
        };
        return {
          'first_card_id': null,
          'first_player_id': actingPlayerId,
          'second_card_id': null,
          'second_player_id': null,
        };
      }
      final firstCard = firstCol.last;
      final secondCard = secondCol.last;
      final firstCardId = firstCard is Map ? (firstCard['cardId'] ?? firstCard['id'] ?? '').toString() : firstCard.toString();
      final secondCardId = secondCard is Map ? (secondCard['cardId'] ?? secondCard['id'] ?? '').toString() : secondCard.toString();
      if (firstCardId.isEmpty || secondCardId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: collection_three_swap - failed to resolve card ids, skipping');
        };
        return {
          'first_card_id': null,
          'first_player_id': actingPlayerId,
          'second_card_id': null,
          'second_player_id': null,
        };
      }
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap (2 players): $firstCardId ($firstPlayerId) <-> $secondCardId ($secondPlayerId)');
      };
      return {
        'first_card_id': firstCardId,
        'first_player_id': firstPlayerId,
        'second_card_id': secondCardId,
        'second_player_id': secondPlayerId,
      };
    }
    // Exactly one player has 3 in collection: swap their last collection card with any non-collection card from any other player (excl. acting)
    final firstPlayerId = threeInColIds[0];
    final firstPlayerData = allPlayers[firstPlayerId] as Map<String, dynamic>? ?? {};
    final firstCol = firstPlayerData['collection_cards'] as List<dynamic>? ?? [];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: collection_three_swap - 1-player path: player $firstPlayerId collection size=${firstCol.length}');
    };
    if (firstCol.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap - single player collection empty, skipping');
      };
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    final firstCard = firstCol.last;
    final firstCardId = firstCard is Map ? (firstCard['cardId'] ?? firstCard['id'] ?? '').toString() : firstCard.toString();
    if (firstCardId.isEmpty) {
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    // Second: any non-collection card from any other player (excl. acting, excl. first player)
    final fromOtherPlayer = <MapEntry<String, String>>[];
    for (final entry in allPlayers.entries) {
      final pid = entry.key;
      if (pid == actingPlayerId || pid == firstPlayerId) continue;
      final pdata = entry.value as Map<String, dynamic>? ?? {};
      final hand = pdata['hand'] as List<dynamic>? ?? [];
      final col = pdata['collection_cards'] as List<dynamic>? ?? [];
      final colIds = col
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final c in hand) {
        final cid = c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : c.toString();
        if (cid.isNotEmpty && cid != 'null' && !colIds.contains(cid)) {
          fromOtherPlayer.add(MapEntry(pid, cid));
        }
      }
    }
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: collection_three_swap - candidate cards from other players: ${fromOtherPlayer.length}');
    };
    if (fromOtherPlayer.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: collection_three_swap - no playable card from other players, skipping');
      };
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    final second = fromOtherPlayer[_random.nextInt(fromOtherPlayer.length)];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: collection_three_swap (1 player): $firstCardId ($firstPlayerId) <-> ${second.value} (${second.key})');
    };
    return {
      'first_card_id': firstCardId,
      'first_player_id': firstPlayerId,
      'second_card_id': second.value,
      'second_player_id': second.key,
    };
  }
  
  /// Rule 2: Select swap involving a player with only 1 card (priority); other card from a different player (excl. acting)
  Map<String, dynamic> _selectOneCardPlayerPriority(String actingPlayerId, Map<String, dynamic> gameData) {
    final allPlayers = gameData['all_players'] as Map<String, dynamic>? ?? {};
    final oneCardPlayerIds = (gameData['other_players_with_one_card'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((id) => id.isNotEmpty && id != 'null')
        .toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - One-card player priority: ${oneCardPlayerIds.length} players with 1 card');
    };
    
    if (oneCardPlayerIds.isEmpty) {
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }

    // When 2+ players have 1 card: swap those two (deterministic, no random)
    if (oneCardPlayerIds.length >= 2) {
      final firstPlayerId = oneCardPlayerIds[0];
      final secondPlayerId = oneCardPlayerIds[1];
      final firstPlayerData = allPlayers[firstPlayerId] as Map<String, dynamic>? ?? {};
      final secondPlayerData = allPlayers[secondPlayerId] as Map<String, dynamic>? ?? {};
      final firstPlayable = _getPlayableCardIds(firstPlayerData);
      final secondPlayable = _getPlayableCardIds(secondPlayerData);
      if (firstPlayable.isNotEmpty && secondPlayable.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: one_card_player_priority - 2 players with 1 card: ${firstPlayable[0]} ($firstPlayerId) <-> ${secondPlayable[0]} ($secondPlayerId)');
        };
        return {
          'first_card_id': firstPlayable[0],
          'first_player_id': firstPlayerId,
          'second_card_id': secondPlayable[0],
          'second_player_id': secondPlayerId,
        };
      }
    }

    // Exactly one player with 1 card: swap their card with a random playable from another player
    oneCardPlayerIds.shuffle(_random);
    final firstPlayerId = oneCardPlayerIds[0];
    final firstPlayerData = allPlayers[firstPlayerId] as Map<String, dynamic>? ?? {};
    final firstHand = firstPlayerData['hand'] as List<dynamic>? ?? [];
    final firstCollection = firstPlayerData['collection_cards'] as List<dynamic>? ?? [];
    final firstColIds = firstCollection
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final firstPlayable = firstHand
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : c.toString())
        .where((id) => id.isNotEmpty && id != 'null' && !firstColIds.contains(id))
        .toList();
    
    if (firstPlayable.isEmpty) {
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    final firstCardId = firstPlayable[0];
    
    // Second card: from any other player (not acting, not first player) with at least 1 playable card
    final fromOtherPlayer = <MapEntry<String, String>>[];
    for (final entry in allPlayers.entries) {
      final pid = entry.key;
      if (pid == actingPlayerId || pid == firstPlayerId) continue;
      final pdata = entry.value as Map<String, dynamic>? ?? {};
      final hand = pdata['hand'] as List<dynamic>? ?? [];
      final col = pdata['collection_cards'] as List<dynamic>? ?? [];
      final colIds = col
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final c in hand) {
        final cid = c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : c.toString();
        if (cid.isNotEmpty && cid != 'null' && !colIds.contains(cid)) {
          fromOtherPlayer.add(MapEntry(pid, cid));
        }
      }
    }
    
    if (fromOtherPlayer.isEmpty) {
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    final second = fromOtherPlayer[_random.nextInt(fromOtherPlayer.length)];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - One-card priority swap: $firstCardId ($firstPlayerId) <-> ${second.value} (${second.key})');
    };
    return {
      'first_card_id': firstCardId,
      'first_player_id': firstPlayerId,
      'second_card_id': second.value,
      'second_player_id': second.key,
    };
  }

  /// Get playable card IDs (hand minus collection) for a player data map.
  List<String> _getPlayableCardIds(Map<String, dynamic> playerData) {
    final hand = playerData['hand'] as List<dynamic>? ?? [];
    final col = playerData['collection_cards'] as List<dynamic>? ?? [];
    final colIds = col
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return hand
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : c.toString())
        .where((id) => id.isNotEmpty && id != 'null' && !colIds.contains(id))
        .toList();
  }
  
  /// Rule: Final round caller swap — when final round is active, swap with the caller.
  /// If we know cards from the caller's hand (in our known_cards): swap our higher-value card with their lower.
  /// If we don't know any caller cards: swap our highest-value card (from known_cards) with any card from their hand.
  /// Uses same points logic as lowest_opponent_higher_own (card['points']).
  Map<String, dynamic> _selectFinalRoundCallerSwap(
    String actingPlayerId,
    Map<String, dynamic> actingPlayer,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
    final callerId = gameState['finalRoundCalledBy']?.toString();
    if (!finalRoundActive || callerId == null || callerId.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: final_round_caller_swap - final round not active or no caller, skipping');
      }
      return _emptyJackSwapResult(actingPlayerId);
    }
    if (callerId == actingPlayerId) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: final_round_caller_swap - we are the caller, skipping');
      }
      return _emptyJackSwapResult(actingPlayerId);
    }

    // Our known cards (own hand) — from gameData acting_player.known_cards
    final ourKnownCards = actingPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    if (ourKnownCards.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: final_round_caller_swap - no known cards for ourselves, skipping');
      }
      return _emptyJackSwapResult(actingPlayerId);
    }

    // Find our highest-point card (same logic as lowest_opponent_higher_own)
    int ourHighestPoints = -1;
    String? ourHighestCardId;
    for (final entry in ourKnownCards.entries) {
      final card = entry.value is Map ? entry.value as Map<String, dynamic> : null;
      if (card != null) {
        final points = card['points'] as int? ?? 0;
        if (points > ourHighestPoints) {
          ourHighestPoints = points;
          ourHighestCardId = entry.key.toString();
        }
      }
    }
    if (ourHighestCardId == null || ourHighestCardId.isEmpty) {
      return _emptyJackSwapResult(actingPlayerId);
    }

    // Do we know any cards from the caller's hand? (our known_cards has caller's id as key)
    final players = gameState['players'] as List<dynamic>? ?? [];
    final actingPlayerFromState = players.firstWhere(
      (p) => p is Map && (p as Map<String, dynamic>)['id']?.toString() == actingPlayerId,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    final ourFullKnownCards = actingPlayerFromState['known_cards'] as Map<String, dynamic>? ?? {};
    final callerKnownCardsRaw = ourFullKnownCards[callerId];
    final callerKnownCards = callerKnownCardsRaw is Map
        ? Map<String, dynamic>.from((callerKnownCardsRaw as Map<String, dynamic>).map((k, v) => MapEntry(k.toString(), v)))
        : <String, dynamic>{};

    if (callerKnownCards.isNotEmpty) {
      // We know caller's cards: find their lowest-point card; swap if our highest > their lowest
      String? theirLowestCardId;
      int theirLowestPoints = 999;
      for (final entry in callerKnownCards.entries) {
        final card = entry.value is Map ? entry.value as Map<String, dynamic> : null;
        if (card != null) {
          final points = card['points'] as int? ?? 0;
          if (points < theirLowestPoints) {
            theirLowestPoints = points;
            theirLowestCardId = entry.key.toString();
          }
        }
      }
      if (theirLowestCardId != null &&
          theirLowestCardId.isNotEmpty &&
          ourHighestPoints > theirLowestPoints) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: final_round_caller_swap - swapping our $ourHighestCardId ($ourHighestPoints pts) with caller $callerId card $theirLowestCardId ($theirLowestPoints pts)');
        }
        return {
          'first_card_id': ourHighestCardId,
          'first_player_id': actingPlayerId,
          'second_card_id': theirLowestCardId,
          'second_player_id': callerId,
        };
      }
    }

    // We don't know caller's cards (or no beneficial swap): swap our highest with any card from caller's hand
    final callerData = allPlayers[callerId] as Map<String, dynamic>? ?? {};
    final callerHand = callerData['hand'] as List<dynamic>? ?? [];
    final collectionCards = callerData['collection_cards'] as List<dynamic>? ?? [];
    final collectionIds = collectionCards
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final playableCallerHand = callerHand
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : c.toString())
        .where((id) => id.isNotEmpty && id != 'null' && !collectionIds.contains(id))
        .toList();
    if (playableCallerHand.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: final_round_caller_swap - caller $callerId has no playable card in hand, skipping');
      }
      return _emptyJackSwapResult(actingPlayerId);
    }
    final theirCardId = playableCallerHand[_random.nextInt(playableCallerHand.length)];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: final_round_caller_swap - no caller cards in known_cards; swapping our $ourHighestCardId with caller $callerId any card $theirCardId');
    }
    return {
      'first_card_id': ourHighestCardId,
      'first_player_id': actingPlayerId,
      'second_card_id': theirCardId,
      'second_player_id': callerId,
    };
  }

  Map<String, dynamic> _emptyJackSwapResult(String actingPlayerId) {
    return {
      'first_card_id': null,
      'first_player_id': actingPlayerId,
      'second_card_id': null,
      'second_player_id': null,
    };
  }
  
  /// Rule 2: Select lowest opponent card and higher own card
  Map<String, dynamic> _selectLowestOpponentHigherOwn(
    String actingPlayerId,
    Map<String, dynamic> actingPlayer,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selecting lowest opponent card and higher own card');
    };
    
    // Get acting player's known cards (full data)
    final actingPlayerKnownCards = actingPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    
    // Find highest point card in acting player's known cards
    Map<String, dynamic>? highestOwnCard;
    int highestOwnPoints = -1;
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Searching for highest point card in acting player\'s known cards (${actingPlayerKnownCards.length} cards)');
    };
    
    for (final entry in actingPlayerKnownCards.entries) {
      final card = entry.value as Map<String, dynamic>?;
      if (card != null) {
        final points = card['points'] as int? ?? 0;
        if (points > highestOwnPoints) {
          highestOwnPoints = points;
          highestOwnCard = card;
        }
      }
    }
    
    if (highestOwnCard == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No known cards for acting player, using fallback');
      };
      return _selectRandomExceptOwn(actingPlayerId, allPlayers, gameState);
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Found highest own card: ${highestOwnCard['cardId']} (${highestOwnPoints} points)');
    };
    
    // Find lowest point card from OUR known_cards about opponents (not opponents' own known_cards).
    // Prepared actingPlayer.known_cards is only our hand; get full known_cards from gameState.
    Map<String, dynamic>? lowestOpponentCard;
    String? lowestOpponentPlayerId;
    int lowestOpponentPoints = 999;
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Searching for lowest point card from our known_cards (opponents we know about)');
    };
    
    final players = gameState['players'] as List<dynamic>? ?? [];
    Map<String, dynamic>? actingPlayerFromState;
    for (final p in players) {
      if (p is Map && (p['id']?.toString() ?? '') == actingPlayerId) {
        actingPlayerFromState = Map<String, dynamic>.from(p);
        break;
      }
    }
    final ourFullKnownCards = actingPlayerFromState != null
        ? (actingPlayerFromState['known_cards'] as Map<String, dynamic>? ?? {})
        : <String, dynamic>{};
    // ourFullKnownCards is keyed by owner player id -> (cardId -> card data)
    for (final entry in ourFullKnownCards.entries) {
      final ownerPlayerId = entry.key.toString();
      if (ownerPlayerId == actingPlayerId) continue; // Skip our own hand (already used for highest own card)
      final cardsWeKnowInThatHand = entry.value is Map
          ? (entry.value as Map).map((k, v) => MapEntry(k.toString(), v as Map<String, dynamic>?))
          : <String, Map<String, dynamic>?>{};
      if (cardsWeKnowInThatHand.isEmpty) continue;
      for (final cardEntry in cardsWeKnowInThatHand.entries) {
        final card = cardEntry.value;
        if (card != null) {
          final points = card['points'] as int? ?? 0;
          if (points < lowestOpponentPoints) {
            lowestOpponentPoints = points;
            lowestOpponentCard = card;
            lowestOpponentPlayerId = ownerPlayerId;
          }
        }
      }
    }
    
    // Check if we found a beneficial swap (opponent card has lower points than own highest card)
    if (lowestOpponentCard != null && lowestOpponentPlayerId != null) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Found lowest opponent card: ${lowestOpponentCard['cardId']} (${lowestOpponentPoints} points) from player $lowestOpponentPlayerId');
      };
      
      if (lowestOpponentPoints < highestOwnPoints) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Beneficial swap found: own card (${highestOwnCard['cardId']}, ${highestOwnPoints} pts) <-> opponent card (${lowestOpponentCard['cardId']}, ${lowestOpponentPoints} pts) from player $lowestOpponentPlayerId');
        };
        
        return {
          'first_card_id': highestOwnCard['cardId']?.toString(),
          'first_player_id': actingPlayerId,
          'second_card_id': lowestOpponentCard['cardId']?.toString(),
          'second_player_id': lowestOpponentPlayerId,
        };
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Opponent card (${lowestOpponentPoints} pts) is not lower than own card (${highestOwnPoints} pts), not beneficial');
        };
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - No opponent cards found in known cards');
      };
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - No beneficial swap found, using fallback');
    };
    return _selectRandomExceptOwn(actingPlayerId, allPlayers, gameState);
  }
  
  /// Rule 4 (last): Random swap of 2 cards from other players only (excl. collection, not our hand)
  Map<String, dynamic> _selectRandomExceptOwn(
    String actingPlayerId,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selecting random 2 cards from other players only (except own hand)');
    };
    
    // Collect (playerId, cardId) for all playable cards from other players (excl. collection)
    final pool = <MapEntry<String, String>>[];
    for (final entry in allPlayers.entries) {
      final playerId = entry.key;
      if (playerId == actingPlayerId) continue;
      final playerData = entry.value as Map<String, dynamic>? ?? {};
      final hand = playerData['hand'] as List<dynamic>? ?? [];
      final collectionCards = playerData['collection_cards'] as List<dynamic>? ?? [];
      final collectionIds = collectionCards
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final card in hand) {
        final cardId = card is Map ? (card['cardId'] ?? card['id'] ?? '').toString() : card.toString();
        if (cardId.isNotEmpty && cardId != 'null' && !collectionIds.contains(cardId)) {
          pool.add(MapEntry(playerId, cardId));
        }
      }
    }
    
    if (pool.length < 2) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - Fewer than 2 playable cards from other players, cannot swap except own');
      };
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    
    // Pick two cards from different players (never same player)
    pool.shuffle(_random);
    final first = pool[0];
    final fromOtherPlayer = pool.where((e) => e.key != first.key).toList();
    if (fromOtherPlayer.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - Only one other player has playable cards, need 2 different players for random_except_own');
      };
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    final second = fromOtherPlayer[_random.nextInt(fromOtherPlayer.length)];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Random except own: ${first.value} (${first.key}) <-> ${second.value} (${second.key})');
    };
    return {
      'first_card_id': first.value,
      'first_player_id': first.key,
      'second_card_id': second.value,
      'second_player_id': second.key,
    };
  }
  
  /// Select Queen peek targets based on strategy
  Map<String, dynamic> _selectQueenPeekTargets(
    Map<String, dynamic> gameData,
    String targetStrategy,
  ) {
    final actingPlayerId = gameData['acting_player_id']?.toString() ?? '';
    final actingPlayer = gameData['acting_player'] as Map<String, dynamic>? ?? {};
    final allPlayers = gameData['all_players'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _selectQueenPeekTargets called with strategy: $targetStrategy');
    };
    
    switch (targetStrategy) {
      case 'own_unknown_cards':
        // Rule 1: Peek at own cards that are not yet in known cards (excluding collection)
        return _selectOwnUnknownCard(actingPlayerId, actingPlayer, gameState);
      
      case 'random_other_player':
        // Rule 2: Random peek at any player's card (excluding their collection cards)
        return _selectRandomOtherPlayerCard(actingPlayerId, allPlayers, gameState);
      
      default:
        // Fallback: random selection
        return _selectRandomOtherPlayerCard(actingPlayerId, allPlayers, gameState);
    }
  }
  
  /// Rule 1: Peek at own cards that are not yet in known cards (excluding collection cards)
  Map<String, dynamic> _selectOwnUnknownCard(
    String actingPlayerId,
    Map<String, dynamic> actingPlayer,
    Map<String, dynamic> gameState,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selecting own unknown card (excluding collection)');
    };
    
    // Get acting player's collection card IDs (to exclude)
    final actingPlayerCollectionCards = actingPlayer['collection_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = actingPlayerCollectionCards
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Acting player has ${collectionCardIds.length} collection cards to exclude');
    };
    
    // Get acting player's hand (excluding collection cards)
    final actingPlayerHand = actingPlayer['hand'] as List<dynamic>? ?? [];
    final playableHand = actingPlayerHand
        .where((cardId) => !collectionCardIds.contains(cardId.toString()))
        .toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Acting player hand: ${actingPlayerHand.length} total, ${playableHand.length} playable (excluding collection)');
    };
    
    if (playableHand.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No playable cards in hand (all are collection cards), returning invalid result');
      };
      return {
        'target_card_id': null,
        'target_player_id': null,
      };
    }
    
    // Get acting player's known card IDs
    final actingPlayerKnownCards = actingPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    final knownCardIds = actingPlayerKnownCards.keys
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Acting player has ${knownCardIds.length} known cards');
    };
    
    // Find cards in hand that are NOT in known cards
    final unknownCards = playableHand
        .where((cardId) => !knownCardIds.contains(cardId.toString()))
        .toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Found ${unknownCards.length} unknown cards in hand (out of ${playableHand.length} playable)');
    };
    
    if (unknownCards.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - All playable cards are already known, returning invalid result');
      };
      return {
        'target_card_id': null,
        'target_player_id': null,
      };
    }
    
    // Select a random unknown card
    final selectedCardId = unknownCards[_random.nextInt(unknownCards.length)].toString();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selected own unknown card: $selectedCardId');
    };
    
    return {
      'target_card_id': selectedCardId,
      'target_player_id': actingPlayerId,
    };
  }
  
  /// Rule 2: Random peek at any player's card (excluding their collection cards)
  Map<String, dynamic> _selectRandomOtherPlayerCard(
    String actingPlayerId,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Selecting random other player card (excluding collection)');
    };
    
    // Get all players (including acting player, but we'll prefer others)
    final allPlayerEntries = allPlayers.entries.toList();
    
    if (allPlayerEntries.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - No players found, returning invalid result');
      };
      return {
        'target_card_id': null,
        'target_player_id': null,
      };
    }
    
    // Shuffle players and try to find one with playable cards
    final shuffledPlayers = List.from(allPlayerEntries)..shuffle(_random);
    
    for (final playerEntry in shuffledPlayers) {
      final playerId = playerEntry.key;
      final playerData = playerEntry.value as Map<String, dynamic>? ?? {};
      
      // Get player's hand
      final playerHand = playerData['hand'] as List<dynamic>? ?? [];
      
      if (playerHand.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Player $playerId has no cards, skipping');
        };
        continue;
      }
      
      // Get player's collection card IDs (to exclude)
      final playerCollectionCards = playerData['collection_cards'] as List<dynamic>? ?? [];
      final collectionCardIds = playerCollectionCards
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      
      // Get playable cards (excluding collection)
      final playableCards = playerHand
          .where((cardId) => !collectionCardIds.contains(cardId.toString()))
          .toList();
      
      if (playableCards.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Player $playerId has no playable cards (all are collection), skipping');
        };
        continue;
      }
      
      // Select a random playable card from this player
      final selectedCardId = playableCards[_random.nextInt(playableCards.length)].toString();
      
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Selected random card: $selectedCardId from player $playerId');
      };
      
      return {
        'target_card_id': selectedCardId,
        'target_player_id': playerId,
      };
    }
    
    // If we get here, no player had playable cards
    if (LOGGING_SWITCH) {
      _logger.warning('Dutch: DEBUG - No players with playable cards found, returning invalid result');
    };
    return {
      'target_card_id': null,
      'target_player_id': null,
    };
  }


  /// Get configuration summary
  Map<String, dynamic> getSummary() => config.getSummary();

  /// Validate configuration
  Map<String, dynamic> validateConfig() => config.validateConfig();
}
