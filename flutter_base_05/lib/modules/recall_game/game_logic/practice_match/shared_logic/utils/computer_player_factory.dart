import '../../shared_imports.dart';

// Platform-specific import - must be imported from outside shared_logic
import '../../utils/computer_player_config_parser.dart';
import 'yaml_rules_engine.dart';

const bool LOGGING_SWITCH = true;

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
  /// Note: YAML decision logic not implemented yet
  /// This method only handles AI decision (use or not)
  Map<String, dynamic> getJackSwapDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    
    // For now, return simple decision (YAML not implemented yet)
    // Future: Will use YAML rules engine to determine if computer should use Jack swap
    // YAML will receive: difficulty, gameState, playerId, eventName='jack_swap'
    return {
      'action': 'jack_swap',
      'use': false, // YAML not implemented yet - will be true/false based on YAML rules
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Jack swap decision (YAML not implemented yet)',
    };
  }

  /// Get computer player decision for Queen peek event
  /// Note: YAML decision logic not implemented yet
  /// This method only handles AI decision (use or not)
  Map<String, dynamic> getQueenPeekDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    
    // For now, return simple decision (YAML not implemented yet)
    // Future: Will use YAML rules engine to determine if computer should use Queen peek
    // YAML will receive: difficulty, gameState, playerId, eventName='queen_peek'
    return {
      'action': 'queen_peek',
      'use': false, // YAML not implemented yet - will be true/false based on YAML rules
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Queen peek decision (YAML not implemented yet)',
    };
  }

  /// Get computer player decision for collect from discard event
  /// Note: Rank matching is done in Dart before this method is called
  /// This method only handles AI decision (collect or not)
  Map<String, dynamic> getCollectFromDiscardDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    
    // For now, return empty decision (YAML not implemented yet)
    // Future: Will use YAML rules to determine if computer should collect
    return {
      'action': 'collect_from_discard',
      'collect': false, // YAML not implemented yet - will be true/false based on YAML rules
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Collect from discard decision (YAML not implemented yet)',
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

  /// Select Jack swap targets based on strategy
  Map<String, dynamic> _selectJackSwapTargets(Map<String, dynamic> gameState, String playerId, String targetStrategy) {
    // TODO: Implement target selection logic based on strategy
    // For now, return placeholder values
    return {
      'first_card_id': 'placeholder_first_card',
      'first_player_id': playerId,
      'second_card_id': 'placeholder_second_card',
      'second_player_id': 'placeholder_target_player',
    };
  }

  /// Select Queen peek target based on strategy
  Map<String, dynamic> _selectQueenPeekTarget(Map<String, dynamic> gameState, String playerId, String targetStrategy) {
    // TODO: Implement target selection logic based on strategy
    // For now, return placeholder values
    return {
      'card_id': 'placeholder_target_card',
      'player_id': 'placeholder_target_player',
    };
  }

  /// Get configuration summary
  Map<String, dynamic> getSummary() => config.getSummary();

  /// Validate configuration
  Map<String, dynamic> validateConfig() => config.validateConfig();
}
