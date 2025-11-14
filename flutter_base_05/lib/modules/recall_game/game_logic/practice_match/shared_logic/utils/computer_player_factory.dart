import '../../shared_imports.dart';

// Platform-specific import - must be imported from outside shared_logic
import '../../utils/computer_player_config_parser.dart';
import 'yaml_rules_engine.dart';

const bool LOGGING_SWITCH = false;

/// Factory for creating computer player behavior based on YAML configuration
class ComputerPlayerFactory {
  final ComputerPlayerConfig config;
  final Random _random = Random();
  final Logger _logger = Logger();

  ComputerPlayerFactory(this.config);

  /// Create factory from YAML file
  static Future<ComputerPlayerFactory> fromFile(String configPath) async {
    final config = await ComputerPlayerConfig.fromFile(configPath);
    return ComputerPlayerFactory(config);
  }

  /// Create factory from YAML string
  static ComputerPlayerFactory fromString(String yamlString) {
    final config = ComputerPlayerConfig.fromString(yamlString);
    return ComputerPlayerFactory(config);
  }

  /// Get computer player decision for draw card event
  Map<String, dynamic> getDrawCardDecision(String difficulty, Map<String, dynamic> gameState) {
    final decisionDelay = config.getDecisionDelay(difficulty);
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
    _logger.info('Recall: DEBUG - getPlayCardDecision called with difficulty: $difficulty, availableCards: ${availableCards.length}', isOn: LOGGING_SWITCH);
    
    final decisionDelay = config.getDecisionDelay(difficulty);
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final evaluationWeights = config.getCardEvaluationWeights();
    
    _logger.info('Recall: DEBUG - Card selection strategy: $cardSelection', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Evaluation weights: $evaluationWeights', isOn: LOGGING_SWITCH);
    
    if (availableCards.isEmpty) {
      _logger.warning('Recall: DEBUG - No cards available to play', isOn: LOGGING_SWITCH);
      return {
        'action': 'play_card',
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No cards available to play',
      };
    }
    
    _logger.info('Recall: DEBUG - Available cards: $availableCards', isOn: LOGGING_SWITCH);
    
    // Select card based on strategy
    final selectedCard = _selectCard(availableCards, cardSelection, evaluationWeights, gameState);
    
    _logger.info('Recall: DEBUG - Selected card: $selectedCard', isOn: LOGGING_SWITCH);
    
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
    final decisionDelay = config.getDecisionDelay(difficulty);
    final playProbability = config.getSameRankPlayProbability(difficulty);
    final wrongRankProbability = config.getWrongRankProbability(difficulty);
    
    // Check if computer player will attempt to play (miss chance)
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

  /// Get computer player decision for Jack swap event
  Map<String, dynamic> getJackSwapDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    _logger.info('Recall: DEBUG - getJackSwapDecision called with difficulty: $difficulty, playerId: $playerId', isOn: LOGGING_SWITCH);
    
    final decisionDelay = config.getDecisionDelay(difficulty);
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareSpecialPlayGameData(gameState, playerId, difficulty);
    
    // Get event config from YAML
    final jackSwapConfig = config.getEventConfig('jack_swap');
    final strategyRules = jackSwapConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    _logger.info('Recall: DEBUG - YAML strategy rules count: ${strategyRules.length}', isOn: LOGGING_SWITCH);
    if (strategyRules.isNotEmpty) {
      _logger.info('Recall: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}', isOn: LOGGING_SWITCH);
    }
    
    // Determine shouldPlayOptimal based on difficulty (same pattern as getPlayCardDecision)
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final shouldPlayOptimal = cardSelection['should_play_optimal'] as bool? ?? 
      (difficulty == 'hard' || difficulty == 'expert');
    
    _logger.info('Recall: DEBUG - shouldPlayOptimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    // If no strategy rules defined, fallback to simple decision
    if (strategyRules.isEmpty) {
      _logger.info('Recall: DEBUG - No YAML rules defined, using fallback logic', isOn: LOGGING_SWITCH);
      return {
        'action': 'jack_swap',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No YAML rules defined',
      };
    }
    
    // Evaluate rules using YAML rules engine
    final decision = _evaluateSpecialPlayRules(strategyRules, gameData, shouldPlayOptimal, 'jack_swap');
    
    _logger.info('Recall: DEBUG - YAML rules engine returned decision: $decision', isOn: LOGGING_SWITCH);
    
    // Merge decision with delay and difficulty
    return {
      'action': 'jack_swap',
      'use': decision['use'] as bool? ?? false,
      'first_card_id': decision['first_card_id'] as String?,
      'first_player_id': decision['first_player_id'] as String? ?? playerId,
      'second_card_id': decision['second_card_id'] as String?,
      'second_player_id': decision['second_player_id'] as String?,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': decision['reasoning']?.toString() ?? 'Jack swap decision',
    };
  }

  /// Get computer player decision for Queen peek event
  Map<String, dynamic> getQueenPeekDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    _logger.info('Recall: DEBUG - getQueenPeekDecision called with difficulty: $difficulty, playerId: $playerId', isOn: LOGGING_SWITCH);
    
    final decisionDelay = config.getDecisionDelay(difficulty);
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareSpecialPlayGameData(gameState, playerId, difficulty);
    
    // Get event config from YAML
    final queenPeekConfig = config.getEventConfig('queen_peek');
    final strategyRules = queenPeekConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    _logger.info('Recall: DEBUG - YAML strategy rules count: ${strategyRules.length}', isOn: LOGGING_SWITCH);
    if (strategyRules.isNotEmpty) {
      _logger.info('Recall: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}', isOn: LOGGING_SWITCH);
    }
    
    // Determine shouldPlayOptimal based on difficulty (same pattern as getPlayCardDecision)
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final shouldPlayOptimal = cardSelection['should_play_optimal'] as bool? ?? 
      (difficulty == 'hard' || difficulty == 'expert');
    
    _logger.info('Recall: DEBUG - shouldPlayOptimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    // If no strategy rules defined, fallback to simple decision
    if (strategyRules.isEmpty) {
      _logger.info('Recall: DEBUG - No YAML rules defined, using fallback logic', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - YAML rules engine returned decision: $decision', isOn: LOGGING_SWITCH);
    
    // Merge decision with delay and difficulty
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
    _logger.info('Recall: DEBUG - getCollectFromDiscardDecision called with difficulty: $difficulty, playerId: $playerId', isOn: LOGGING_SWITCH);
    
    final decisionDelay = config.getDecisionDelay(difficulty);
    
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
        _logger.info('Recall: DEBUG - Added discard pile top card: ${topCard['rank']} of ${topCard['suit']}', isOn: LOGGING_SWITCH);
      }
    }
    
    // Get event config from YAML
    final collectConfig = config.getEventConfig('collect_from_discard');
    final strategyRules = collectConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    _logger.info('Recall: DEBUG - YAML strategy rules count: ${strategyRules.length}', isOn: LOGGING_SWITCH);
    if (strategyRules.isNotEmpty) {
      _logger.info('Recall: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}', isOn: LOGGING_SWITCH);
    }
    
    // Determine shouldPlayOptimal based on difficulty (same pattern as other decisions)
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final shouldPlayOptimal = cardSelection['should_play_optimal'] as bool? ?? 
      (difficulty == 'hard' || difficulty == 'expert');
    
    _logger.info('Recall: DEBUG - shouldPlayOptimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    // If no strategy rules defined, fallback to simple decision
    if (strategyRules.isEmpty) {
      _logger.info('Recall: DEBUG - No YAML rules defined, using fallback logic', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - YAML rules engine returned decision: $decision', isOn: LOGGING_SWITCH);
    
    // Convert 'use' to 'collect' for consistency with existing code
    final shouldCollect = decision['use'] as bool? ?? false;
    
    // Merge decision with delay and difficulty
    return {
      'action': 'collect_from_discard',
      'collect': shouldCollect,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': decision['reasoning']?.toString() ?? 'Collect from discard decision',
    };
  }

  /// Select a card based on strategy and evaluation weights
  String _selectCard(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState) {
    _logger.info('Recall: DEBUG - _selectCard called with ${availableCards.length} available cards', isOn: LOGGING_SWITCH);
    
    final strategy = cardSelection['strategy'] ?? 'random';
    _logger.info('Recall: DEBUG - Strategy: $strategy', isOn: LOGGING_SWITCH);
    
    // Get current player from game state
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    if (currentPlayer == null) {
      _logger.warning('Recall: DEBUG - No current player found, using random fallback', isOn: LOGGING_SWITCH);
      return availableCards[_random.nextInt(availableCards.length)];
    }
    
    _logger.info('Recall: DEBUG - Current player: ${currentPlayer['name']}', isOn: LOGGING_SWITCH);
    
    // Prepare game data for YAML rules engine
    final gameData = _prepareGameDataForYAML(availableCards, currentPlayer, gameState);
    _logger.info('Recall: DEBUG - Game data prepared: ${gameData.keys.join(', ')}', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Available cards: ${gameData['available_cards']}', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Playable cards: ${gameData['playable_cards']}', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Unknown cards: ${gameData['unknown_cards']}', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Known cards: ${gameData['known_cards']}', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Collection cards: ${gameData['collection_cards']}', isOn: LOGGING_SWITCH);
    
    // Get YAML rules from config
    final playCardConfig = config.getEventConfig('play_card');
    final strategyRules = playCardConfig['strategy_rules'] as List<dynamic>? ?? [];
    
    _logger.info('Recall: DEBUG - YAML strategy rules count: ${strategyRules.length}', isOn: LOGGING_SWITCH);
    if (strategyRules.isNotEmpty) {
      _logger.info('Recall: DEBUG - YAML rules: ${strategyRules.map((r) => r['name']).join(', ')}', isOn: LOGGING_SWITCH);
    }
    
    if (strategyRules.isEmpty) {
      _logger.info('Recall: DEBUG - No YAML rules defined, using legacy logic', isOn: LOGGING_SWITCH);
      // Fallback to old logic if no YAML rules defined
      return _selectCardLegacy(availableCards, cardSelection, evaluationWeights, gameState);
    }
    
    // Determine if we should play optimally
    final optimalPlayProb = _getOptimalPlayProbability(strategy);
    final shouldPlayOptimal = _random.nextDouble() < optimalPlayProb;
    
    _logger.info('Recall: DEBUG - Optimal play probability: $optimalPlayProb, Should play optimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    // Execute YAML rules
    final rulesEngine = YamlRulesEngine();
    final result = rulesEngine.executeRules(strategyRules, gameData, shouldPlayOptimal);
    
    _logger.info('Recall: DEBUG - YAML rules engine returned: $result', isOn: LOGGING_SWITCH);
    
    return result;
  }
  
  /// Prepare game data for YAML rules engine
  Map<String, dynamic> _prepareGameDataForYAML(List<String> availableCards, 
                                                Map<String, dynamic> currentPlayer, 
                                                Map<String, dynamic> gameState) {
    _logger.info('Recall: DEBUG - _prepareGameDataForYAML called with ${availableCards.length} available cards', isOn: LOGGING_SWITCH);
    
    // Get player's known_cards and collection_rank_cards
    final knownCards = currentPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    final collectionRankCards = currentPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = collectionRankCards.map((c) {
      if (c is Map<String, dynamic>) {
        return c['cardId']?.toString() ?? c['id']?.toString() ?? '';
      }
      return c.toString();
    }).where((id) => id.isNotEmpty).toSet();
    
    _logger.info('Recall: DEBUG - Player known_cards: $knownCards', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Player collection_rank_cards: ${collectionRankCards.length} cards', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG - Collection card IDs: $collectionCardIds', isOn: LOGGING_SWITCH);
    
    // Filter out collection rank cards
    final playableCards = availableCards.where((cardId) => !collectionCardIds.contains(cardId)).toList();
    _logger.info('Recall: DEBUG - Playable cards (after filtering collection): ${playableCards.length}', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - Known card IDs: $knownCardIds', isOn: LOGGING_SWITCH);
    
    // Get unknown cards
    final unknownCards = playableCards.where((cardId) => !knownCardIds.contains(cardId)).toList();
    _logger.info('Recall: DEBUG - Unknown cards: ${unknownCards.length}', isOn: LOGGING_SWITCH);
    
    // Get known playable cards
    final knownPlayableCards = playableCards.where((cardId) => knownCardIds.contains(cardId)).toList();
    _logger.info('Recall: DEBUG - Known playable cards: ${knownPlayableCards.length}', isOn: LOGGING_SWITCH);
    
    // Filter out null cards and collection cards from all lists
    availableCards.removeWhere((card) => card.toString() == 'null');
    playableCards.removeWhere((card) => card.toString() == 'null');
    unknownCards.removeWhere((card) => card.toString() == 'null');
    knownPlayableCards.removeWhere((card) => card.toString() == 'null');
    _logger.info('Recall: DEBUG - After null filtering - Available: ${availableCards.length}, Playable: ${playableCards.length}, Unknown: ${unknownCards.length}, Known: ${knownPlayableCards.length}', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - All cards data: ${allCardsData.length} cards', isOn: LOGGING_SWITCH);
    
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
    
    _logger.info('Recall: DEBUG - Prepared game data with keys: ${result.keys.join(', ')}', isOn: LOGGING_SWITCH);
    
    return result;
  }
  
  /// Legacy card selection (fallback if YAML rules not defined)
  String _selectCardLegacy(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState) {
    final strategy = cardSelection['strategy'] ?? 'random';
    
    // Get current player from game state
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    if (currentPlayer == null) {
      _logger.error('Recall: No current player found in game state', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - Available cards: ${availableCards.length}, Playable cards: ${playableCards.length}, Collection cards: ${collectionCardIds.length}', isOn: LOGGING_SWITCH);
    
    if (playableCards.isEmpty) {
      _logger.warning('Recall: All available cards are collection rank cards, using fallback', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - Unknown cards: ${unknownCards.length}, Known playable cards: ${knownPlayableCards.length}', isOn: LOGGING_SWITCH);
    
    // Determine if we should play optimally based on difficulty
    final optimalPlayProb = _getOptimalPlayProbability(strategy);
    final shouldPlayOptimal = _random.nextDouble() < optimalPlayProb;
    
    _logger.info('Recall: DEBUG - Strategy: $strategy, Optimal prob: $optimalPlayProb, Should play optimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    if (shouldPlayOptimal) {
      // Best option: Random unknown card
      if (unknownCards.isNotEmpty) {
        final selectedCard = unknownCards[_random.nextInt(unknownCards.length)];
        _logger.info('Recall: DEBUG - Selected unknown card: $selectedCard', isOn: LOGGING_SWITCH);
        return selectedCard;
      }
      
      // Fallback: Highest points from known cards (exclude Jacks)
      if (knownPlayableCards.isNotEmpty) {
        final selectedCard = _selectHighestPointsCard(knownPlayableCards, gameState);
        _logger.info('Recall: DEBUG - Selected highest points card: $selectedCard', isOn: LOGGING_SWITCH);
        return selectedCard;
      }
    }
    
    // Random fallback (for non-optimal play or if strategies fail)
    final selectedCard = playableCards[_random.nextInt(playableCards.length)];
    _logger.info('Recall: DEBUG - Selected random fallback card: $selectedCard', isOn: LOGGING_SWITCH);
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
    _logger.info('Recall: DEBUG - _selectHighestPointsCard called with ${cardIds.length} card IDs', isOn: LOGGING_SWITCH);
    
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
    
    _logger.info('Recall: DEBUG - Found ${allCards.length} total cards in game state', isOn: LOGGING_SWITCH);
    
    // Filter to only the cards we're considering
    final candidateCards = allCards.where((card) => cardIds.contains(card['id'])).toList();
    
    _logger.info('Recall: DEBUG - Found ${candidateCards.length} candidate cards', isOn: LOGGING_SWITCH);
    
    if (candidateCards.isEmpty) {
      _logger.warning('Recall: No candidate cards found, using random fallback', isOn: LOGGING_SWITCH);
      return cardIds[_random.nextInt(cardIds.length)];
    }
    
    // Filter out Jacks
    final nonJackCards = candidateCards.where((card) => card['rank'] != 'jack').toList();
    
    _logger.info('Recall: DEBUG - Found ${nonJackCards.length} non-Jack cards', isOn: LOGGING_SWITCH);
    
    if (nonJackCards.isEmpty) {
      // If all are Jacks, return random
      _logger.warning('Recall: All candidate cards are Jacks, using random fallback', isOn: LOGGING_SWITCH);
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
    _logger.info('Recall: DEBUG - Selected highest points card: $selectedCard (points: $highestPoints)', isOn: LOGGING_SWITCH);
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
    _logger.info('Recall: DEBUG - After null filtering same rank - Available: ${availableCards.length}, Known: ${knownSameRankCards.length}, Unknown: ${unknownSameRankCards.length}', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - _prepareSpecialPlayGameData called for player $actingPlayerId, difficulty: $difficulty', isOn: LOGGING_SWITCH);
    
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Find acting player
    final actingPlayer = players.firstWhere(
      (p) => p is Map && (p['id']?.toString() ?? '') == actingPlayerId,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>?;
    
    if (actingPlayer == null || actingPlayer.isEmpty) {
      _logger.warning('Recall: DEBUG - Acting player $actingPlayerId not found', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - Acting player known_cards structure: ${knownCards.keys.toList()}', isOn: LOGGING_SWITCH);
    
    final actingPlayerKnownCardsRaw = knownCards[actingPlayerId] as Map<String, dynamic>?;
    
    if (actingPlayerKnownCardsRaw != null) {
      _logger.info('Recall: DEBUG - Found known_cards entry for acting player $actingPlayerId with ${actingPlayerKnownCardsRaw.length} cards', isOn: LOGGING_SWITCH);
      for (final entry in actingPlayerKnownCardsRaw.entries) {
        final cardId = entry.key.toString();
        if (cardId.isNotEmpty && cardId != 'null') {
          if (entry.value is Map<String, dynamic>) {
            actingPlayerKnownCards[cardId] = Map<String, dynamic>.from(entry.value as Map);
            _logger.info('Recall: DEBUG - Added known card: $cardId', isOn: LOGGING_SWITCH);
          } else {
            _logger.warning('Recall: DEBUG - Known card entry value is not a Map: ${entry.value.runtimeType}', isOn: LOGGING_SWITCH);
          }
        }
      }
    } else {
      _logger.warning('Recall: DEBUG - No known_cards entry found for acting player $actingPlayerId in known_cards structure', isOn: LOGGING_SWITCH);
      _logger.info('Recall: DEBUG - Known_cards structure keys: ${knownCards.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    // Extract acting player's collection cards (full data)
    final actingPlayerCollectionCards = <Map<String, dynamic>>[];
    final collectionRankCards = actingPlayer['collection_rank_cards'] as List<dynamic>? ?? [];
    for (final card in collectionRankCards) {
      if (card is Map<String, dynamic>) {
        actingPlayerCollectionCards.add(Map<String, dynamic>.from(card));
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
      
      // Extract collection cards (full data)
      final collectionCards = <Map<String, dynamic>>[];
      final playerCollectionCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
      for (final card in playerCollectionCards) {
        if (card is Map<String, dynamic>) {
          collectionCards.add(Map<String, dynamic>.from(card));
        }
      }
      
      allPlayersData[playerId] = {
        'hand': hand,
        'known_card_ids': knownCardIds,
        'collection_cards': collectionCards,
      };
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
      'game_state': gameState,
    };
    
    _logger.info('Recall: DEBUG - Prepared special play game data:', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   Acting player hand: ${actingPlayerHand.length} cards', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   Acting player known cards: ${actingPlayerKnownCards.length} cards', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   Acting player collection cards: ${actingPlayerCollectionCards.length} cards', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   All players data: ${allPlayersData.length} players', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - _evaluateSpecialPlayRules called with ${strategyRules.length} rules, shouldPlayOptimal: $shouldPlayOptimal, eventName: $eventName', isOn: LOGGING_SWITCH);
    
    if (strategyRules.isEmpty) {
      _logger.info('Recall: DEBUG - No strategy rules defined, returning use: false', isOn: LOGGING_SWITCH);
      return {
        'use': false,
        'reasoning': 'No strategy rules defined',
      };
    }
    
    // Sort rules by priority (ascending, lower priority = evaluated first)
    final sortedRules = List<Map<String, dynamic>>.from(strategyRules)
      ..sort((a, b) => (a['priority'] ?? 999).compareTo(b['priority'] ?? 999));
    
    _logger.info('Recall: DEBUG - Sorted rules by priority: ${sortedRules.map((r) => '${r['name']} (${r['priority']})').join(', ')}', isOn: LOGGING_SWITCH);
    
    // Get difficulty for probability-based execution
    final difficulty = gameData['difficulty']?.toString() ?? 'medium';
    
    // Note: We always evaluate rules in priority order, using execution probability to determine which rule executes
    // shouldPlayOptimal only affects the probability thresholds, not whether we evaluate rules
    
    // Evaluate rules in priority order
    for (final rule in sortedRules) {
      final ruleName = rule['name']?.toString() ?? 'unnamed';
      _logger.info('Recall: DEBUG - Evaluating rule: $ruleName', isOn: LOGGING_SWITCH);
      
      final condition = rule['condition'] as Map<String, dynamic>?;
      if (condition != null) {
        final conditionResult = _evaluateSpecialPlayCondition(condition, gameData);
        _logger.info('Recall: DEBUG - Rule $ruleName condition result: $conditionResult', isOn: LOGGING_SWITCH);
        
        if (conditionResult) {
          // Check execution probability based on difficulty
          final executionProb = rule['execution_probability'] as Map<String, dynamic>?;
          if (executionProb != null) {
            final prob = (executionProb[difficulty] as num?)?.toDouble() ?? 1.0;
            final shouldExecute = _random.nextDouble() < prob;
            _logger.info('Recall: DEBUG - Rule $ruleName execution probability for $difficulty: $prob, shouldExecute: $shouldExecute', isOn: LOGGING_SWITCH);
            
            if (!shouldExecute) {
              _logger.info('Recall: DEBUG - Rule $ruleName skipped due to execution probability', isOn: LOGGING_SWITCH);
              continue; // Skip this rule and try next one
            }
          }
          
          final action = rule['action'] as Map<String, dynamic>?;
          if (action != null) {
            _logger.info('Recall: DEBUG - Rule $ruleName condition passed, executing action', isOn: LOGGING_SWITCH);
            final result = _executeSpecialPlayAction(action, gameData, eventName, ruleName);
            
            // Check if result is valid (has valid targets)
            if (_isValidSpecialPlayResult(result, eventName)) {
              return result;
            } else {
              _logger.info('Recall: DEBUG - Rule $ruleName returned invalid result (no valid targets), trying next rule', isOn: LOGGING_SWITCH);
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
          _logger.info('Recall: DEBUG - Rule $ruleName execution probability for $difficulty: $prob, shouldExecute: $shouldExecute', isOn: LOGGING_SWITCH);
          
          if (!shouldExecute) {
            _logger.info('Recall: DEBUG - Rule $ruleName skipped due to execution probability', isOn: LOGGING_SWITCH);
            continue; // Skip this rule and try next one
          }
        }
        
        final action = rule['action'] as Map<String, dynamic>?;
        if (action != null) {
          _logger.info('Recall: DEBUG - Rule $ruleName has no condition, executing action', isOn: LOGGING_SWITCH);
          final result = _executeSpecialPlayAction(action, gameData, eventName, ruleName);
          
          // Check if result is valid (has valid targets)
          if (_isValidSpecialPlayResult(result, eventName)) {
            return result;
          } else {
            _logger.info('Recall: DEBUG - Rule $ruleName returned invalid result (no valid targets), trying next rule', isOn: LOGGING_SWITCH);
            continue; // Try next rule
          }
        }
      }
    }
    
    _logger.info('Recall: DEBUG - No rules matched, returning use: false', isOn: LOGGING_SWITCH);
    
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
    
    _logger.info('Recall: DEBUG - _executeSpecialPlayAction called with actionType: $actionType, eventName: $eventName, ruleName: $ruleName', isOn: LOGGING_SWITCH);
    
    switch (actionType) {
      case 'use_special_play':
        if (eventName == 'jack_swap') {
          // Get target strategy from action
          final targetStrategy = action['target_strategy']?.toString() ?? 'random';
          
          _logger.info('Recall: DEBUG - Executing jack_swap with target strategy: $targetStrategy', isOn: LOGGING_SWITCH);
          
          // Select targets based on strategy
          final targets = _selectJackSwapTargets(gameData, targetStrategy);
          
          _logger.info('Recall: DEBUG - Target selection result: $targets', isOn: LOGGING_SWITCH);
          
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
          
          _logger.info('Recall: DEBUG - Executing queen_peek with target strategy: $targetStrategy', isOn: LOGGING_SWITCH);
          
          // Select targets based on strategy
          final targets = _selectQueenPeekTargets(gameData, targetStrategy);
          
          _logger.info('Recall: DEBUG - Target selection result: $targets', isOn: LOGGING_SWITCH);
          
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
        // For collect_from_discard, we need to check if conditions are met
        // Rule 1: Check if player has 3 collection cards and this is the only remaining card with same rank
        // Rule 2: Check if same rank as collection rank (simpler check)
        
        final actingPlayer = gameData['acting_player'] as Map<String, dynamic>? ?? {};
        final actingPlayerCollectionCards = actingPlayer['collection_cards'] as List<dynamic>? ?? [];
        final discardPile = gameData['discard_pile'] as Map<String, dynamic>?;
        final topCard = discardPile?['top_card'] as Map<String, dynamic>?;
        final actingPlayerCollectionRank = actingPlayer['collection_rank']?.toString() ?? '';
        
        if (topCard == null) {
          _logger.warning('Recall: DEBUG - No discard pile top card found, skipping collection', isOn: LOGGING_SWITCH);
          return {
            'use': false,
            'reasoning': ruleName,
          };
        }
        
        final topCardRank = topCard['rank']?.toString() ?? '';
        
        // Check if rank matches collection rank
        if (topCardRank.toLowerCase() != actingPlayerCollectionRank.toLowerCase()) {
          _logger.info('Recall: DEBUG - Top card rank $topCardRank does not match collection rank $actingPlayerCollectionRank', isOn: LOGGING_SWITCH);
          return {
            'use': false,
            'reasoning': ruleName,
          };
        }
        
        // Rule 1: If player has 3 collection cards and rank matches, collect it (will complete 4 of a kind)
        if (ruleName == 'collect_if_completes_set' && actingPlayerCollectionCards.length == 3) {
          _logger.info('Recall: DEBUG - Player has 3 collection cards, collecting 4th card to complete set', isOn: LOGGING_SWITCH);
          return {
            'use': true,
            'reasoning': ruleName,
          };
        }
        
        // Rule 2: If same rank as collection rank, collect it
        if (ruleName == 'collect_if_same_rank') {
          _logger.info('Recall: DEBUG - Top card rank matches collection rank, collecting it', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - _selectJackSwapTargets called with strategy: $targetStrategy', isOn: LOGGING_SWITCH);
    
    switch (targetStrategy) {
      case 'lowest_opponent_higher_own':
        // Rule 1: Find lowest opponent card and higher own card
        return _selectLowestOpponentHigherOwn(actingPlayerId, actingPlayer, allPlayers, gameState);
      
      case 'random_two_players':
        // Rule 2: Random 2 cards (excluding collection cards) from any 2 other players
        return _selectRandomTwoPlayers(actingPlayerId, actingPlayer, allPlayers, gameState);
      
      default:
        // Fallback: random selection
        return _selectRandomTwoPlayers(actingPlayerId, actingPlayer, allPlayers, gameState);
    }
  }
  
  /// Rule 1: Select lowest opponent card and higher own card
  Map<String, dynamic> _selectLowestOpponentHigherOwn(
    String actingPlayerId,
    Map<String, dynamic> actingPlayer,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    _logger.info('Recall: DEBUG - Selecting lowest opponent card and higher own card', isOn: LOGGING_SWITCH);
    
    // Get acting player's known cards (full data)
    final actingPlayerKnownCards = actingPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    
    // Find highest point card in acting player's known cards
    Map<String, dynamic>? highestOwnCard;
    int highestOwnPoints = -1;
    
    _logger.info('Recall: DEBUG - Searching for highest point card in acting player\'s known cards (${actingPlayerKnownCards.length} cards)', isOn: LOGGING_SWITCH);
    
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
      _logger.warning('Recall: DEBUG - No known cards for acting player, using fallback', isOn: LOGGING_SWITCH);
      return _selectRandomTwoPlayers(actingPlayerId, actingPlayer, allPlayers, gameState);
    }
    
    _logger.info('Recall: DEBUG - Found highest own card: ${highestOwnCard['cardId']} (${highestOwnPoints} points)', isOn: LOGGING_SWITCH);
    
    // Find lowest point card from other players' known cards
    Map<String, dynamic>? lowestOpponentCard;
    String? lowestOpponentPlayerId;
    int lowestOpponentPoints = 999;
    
    _logger.info('Recall: DEBUG - Searching for lowest point card from other players\' known cards (${allPlayers.length - 1} other players)', isOn: LOGGING_SWITCH);
    
    for (final entry in allPlayers.entries) {
      final playerId = entry.key;
      if (playerId == actingPlayerId) continue; // Skip acting player
      
      // Get full card data from game state for this player's known cards
      final players = gameState['players'] as List<dynamic>? ?? [];
      final playerData = players.firstWhere(
        (p) => p is Map && (p['id']?.toString() ?? '') == playerId,
        orElse: () => <String, dynamic>{},
      ) as Map<String, dynamic>?;
      
      if (playerData != null) {
        final playerKnownCards = playerData['known_cards'] as Map<String, dynamic>? ?? {};
        final playerOwnKnownCards = playerKnownCards[playerId] as Map<String, dynamic>?;
        
        if (playerOwnKnownCards != null) {
          for (final cardEntry in playerOwnKnownCards.entries) {
            final card = cardEntry.value as Map<String, dynamic>?;
            if (card != null) {
              final points = card['points'] as int? ?? 0;
              if (points < lowestOpponentPoints) {
                lowestOpponentPoints = points;
                lowestOpponentCard = card;
                lowestOpponentPlayerId = playerId;
              }
            }
          }
        }
      }
    }
    
    // Check if we found a beneficial swap (opponent card has lower points than own highest card)
    if (lowestOpponentCard != null && lowestOpponentPlayerId != null) {
      _logger.info('Recall: DEBUG - Found lowest opponent card: ${lowestOpponentCard['cardId']} (${lowestOpponentPoints} points) from player $lowestOpponentPlayerId', isOn: LOGGING_SWITCH);
      
      if (lowestOpponentPoints < highestOwnPoints) {
        _logger.info('Recall: DEBUG - Beneficial swap found: own card (${highestOwnCard['cardId']}, ${highestOwnPoints} pts) <-> opponent card (${lowestOpponentCard['cardId']}, ${lowestOpponentPoints} pts) from player $lowestOpponentPlayerId', isOn: LOGGING_SWITCH);
        
        return {
          'first_card_id': highestOwnCard['cardId']?.toString(),
          'first_player_id': actingPlayerId,
          'second_card_id': lowestOpponentCard['cardId']?.toString(),
          'second_player_id': lowestOpponentPlayerId,
        };
      } else {
        _logger.info('Recall: DEBUG - Opponent card (${lowestOpponentPoints} pts) is not lower than own card (${highestOwnPoints} pts), not beneficial', isOn: LOGGING_SWITCH);
      }
    } else {
      _logger.info('Recall: DEBUG - No opponent cards found in known cards', isOn: LOGGING_SWITCH);
    }
    
    _logger.info('Recall: DEBUG - No beneficial swap found, using fallback', isOn: LOGGING_SWITCH);
    return _selectRandomTwoPlayers(actingPlayerId, actingPlayer, allPlayers, gameState);
  }
  
  /// Rule 2: Random 2 cards (excluding collection cards) from any 2 other players
  Map<String, dynamic> _selectRandomTwoPlayers(
    String actingPlayerId,
    Map<String, dynamic> actingPlayer,
    Map<String, dynamic> allPlayers,
    Map<String, dynamic> gameState,
  ) {
    _logger.info('Recall: DEBUG - Selecting random 2 cards from 2 other players', isOn: LOGGING_SWITCH);
    
    // Get acting player's collection card IDs (to exclude)
    final actingPlayerCollectionCards = actingPlayer['collection_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = actingPlayerCollectionCards
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    
    _logger.info('Recall: DEBUG - Acting player has ${collectionCardIds.length} collection cards to exclude', isOn: LOGGING_SWITCH);
    
    // Get acting player's hand (excluding collection cards)
    final actingPlayerHand = actingPlayer['hand'] as List<dynamic>? ?? [];
    final playableOwnCards = actingPlayerHand
        .where((cardId) => !collectionCardIds.contains(cardId.toString()))
        .toList();
    
    _logger.info('Recall: DEBUG - Acting player hand: ${actingPlayerHand.length} total, ${playableOwnCards.length} playable (excluding collection)', isOn: LOGGING_SWITCH);
    
    if (playableOwnCards.isEmpty) {
      _logger.warning('Recall: DEBUG - No playable cards for acting player, using fallback', isOn: LOGGING_SWITCH);
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    
    // Get other players (excluding acting player)
    final otherPlayers = allPlayers.entries
        .where((entry) => entry.key != actingPlayerId)
        .toList();
    
    if (otherPlayers.length < 2) {
      _logger.warning('Recall: DEBUG - Not enough other players (need 2, have ${otherPlayers.length}), using single player', isOn: LOGGING_SWITCH);
      // Fallback: use same player twice if only one other player
      if (otherPlayers.isEmpty) {
        return {
          'first_card_id': null,
          'first_player_id': actingPlayerId,
          'second_card_id': null,
          'second_player_id': null,
        };
      }
      
      final otherPlayer = otherPlayers[0];
      final otherPlayerId = otherPlayer.key;
      final otherPlayerData = otherPlayer.value as Map<String, dynamic>? ?? {};
      final otherPlayerHand = otherPlayerData['hand'] as List<dynamic>? ?? [];
      final otherPlayerCollectionCards = otherPlayerData['collection_cards'] as List<dynamic>? ?? [];
      final otherCollectionCardIds = otherPlayerCollectionCards
          .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      
      final playableOtherCards = otherPlayerHand
          .where((cardId) => !otherCollectionCardIds.contains(cardId.toString()))
          .toList();
      
      if (playableOtherCards.isEmpty || playableOwnCards.isEmpty) {
        return {
          'first_card_id': null,
          'first_player_id': actingPlayerId,
          'second_card_id': null,
          'second_player_id': null,
        };
      }
      
      // Select random cards from same player
      final firstCard = playableOwnCards[_random.nextInt(playableOwnCards.length)].toString();
      final secondCard = playableOtherCards[_random.nextInt(playableOtherCards.length)].toString();
      
      return {
        'first_card_id': firstCard,
        'first_player_id': actingPlayerId,
        'second_card_id': secondCard,
        'second_player_id': otherPlayerId,
      };
    }
    
    // Select 1 other player randomly (we'll swap one card from acting player with one card from this player)
    final shuffledPlayers = List.from(otherPlayers)..shuffle(_random);
    final firstOtherPlayer = shuffledPlayers[0];
    
    final firstOtherPlayerId = firstOtherPlayer.key;
    final firstOtherPlayerData = firstOtherPlayer.value as Map<String, dynamic>? ?? {};
    final firstOtherPlayerHand = firstOtherPlayerData['hand'] as List<dynamic>? ?? [];
    final firstOtherPlayerCollectionCards = firstOtherPlayerData['collection_cards'] as List<dynamic>? ?? [];
    final firstOtherCollectionCardIds = firstOtherPlayerCollectionCards
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    
    final playableFirstOtherCards = firstOtherPlayerHand
        .where((cardId) => !firstOtherCollectionCardIds.contains(cardId.toString()))
        .toList();
    
    if (playableOwnCards.isEmpty || playableFirstOtherCards.isEmpty) {
      _logger.warning('Recall: DEBUG - Not enough playable cards, using fallback', isOn: LOGGING_SWITCH);
      return {
        'first_card_id': null,
        'first_player_id': actingPlayerId,
        'second_card_id': null,
        'second_player_id': null,
      };
    }
    
    // Select random cards
    final firstCard = playableOwnCards[_random.nextInt(playableOwnCards.length)].toString();
    final secondCard = playableFirstOtherCards[_random.nextInt(playableFirstOtherCards.length)].toString();
    
    _logger.info('Recall: DEBUG - Selected random swap:', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   First card: $firstCard from acting player $actingPlayerId', isOn: LOGGING_SWITCH);
    _logger.info('Recall: DEBUG -   Second card: $secondCard from other player $firstOtherPlayerId', isOn: LOGGING_SWITCH);
    
    return {
      'first_card_id': firstCard,
      'first_player_id': actingPlayerId,
      'second_card_id': secondCard,
      'second_player_id': firstOtherPlayerId,
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
    
    _logger.info('Recall: DEBUG - _selectQueenPeekTargets called with strategy: $targetStrategy', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - Selecting own unknown card (excluding collection)', isOn: LOGGING_SWITCH);
    
    // Get acting player's collection card IDs (to exclude)
    final actingPlayerCollectionCards = actingPlayer['collection_cards'] as List<dynamic>? ?? [];
    final collectionCardIds = actingPlayerCollectionCards
        .map((c) => c is Map ? (c['cardId'] ?? c['id'] ?? '').toString() : '')
        .where((id) => id.isNotEmpty)
        .toSet();
    
    _logger.info('Recall: DEBUG - Acting player has ${collectionCardIds.length} collection cards to exclude', isOn: LOGGING_SWITCH);
    
    // Get acting player's hand (excluding collection cards)
    final actingPlayerHand = actingPlayer['hand'] as List<dynamic>? ?? [];
    final playableHand = actingPlayerHand
        .where((cardId) => !collectionCardIds.contains(cardId.toString()))
        .toList();
    
    _logger.info('Recall: DEBUG - Acting player hand: ${actingPlayerHand.length} total, ${playableHand.length} playable (excluding collection)', isOn: LOGGING_SWITCH);
    
    if (playableHand.isEmpty) {
      _logger.warning('Recall: DEBUG - No playable cards in hand (all are collection cards), returning invalid result', isOn: LOGGING_SWITCH);
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
    
    _logger.info('Recall: DEBUG - Acting player has ${knownCardIds.length} known cards', isOn: LOGGING_SWITCH);
    
    // Find cards in hand that are NOT in known cards
    final unknownCards = playableHand
        .where((cardId) => !knownCardIds.contains(cardId.toString()))
        .toList();
    
    _logger.info('Recall: DEBUG - Found ${unknownCards.length} unknown cards in hand (out of ${playableHand.length} playable)', isOn: LOGGING_SWITCH);
    
    if (unknownCards.isEmpty) {
      _logger.warning('Recall: DEBUG - All playable cards are already known, returning invalid result', isOn: LOGGING_SWITCH);
      return {
        'target_card_id': null,
        'target_player_id': null,
      };
    }
    
    // Select a random unknown card
    final selectedCardId = unknownCards[_random.nextInt(unknownCards.length)].toString();
    
    _logger.info('Recall: DEBUG - Selected own unknown card: $selectedCardId', isOn: LOGGING_SWITCH);
    
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
    _logger.info('Recall: DEBUG - Selecting random other player card (excluding collection)', isOn: LOGGING_SWITCH);
    
    // Get all players (including acting player, but we'll prefer others)
    final allPlayerEntries = allPlayers.entries.toList();
    
    if (allPlayerEntries.isEmpty) {
      _logger.warning('Recall: DEBUG - No players found, returning invalid result', isOn: LOGGING_SWITCH);
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
        _logger.info('Recall: DEBUG - Player $playerId has no cards, skipping', isOn: LOGGING_SWITCH);
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
        _logger.info('Recall: DEBUG - Player $playerId has no playable cards (all are collection), skipping', isOn: LOGGING_SWITCH);
        continue;
      }
      
      // Select a random playable card from this player
      final selectedCardId = playableCards[_random.nextInt(playableCards.length)].toString();
      
      _logger.info('Recall: DEBUG - Selected random card: $selectedCardId from player $playerId', isOn: LOGGING_SWITCH);
      
      return {
        'target_card_id': selectedCardId,
        'target_player_id': playerId,
      };
    }
    
    // If we get here, no player had playable cards
    _logger.warning('Recall: DEBUG - No players with playable cards found, returning invalid result', isOn: LOGGING_SWITCH);
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
