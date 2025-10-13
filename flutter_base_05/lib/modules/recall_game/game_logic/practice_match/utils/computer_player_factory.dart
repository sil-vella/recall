import 'dart:math';
import 'computer_player_config_parser.dart';

/// Factory for creating computer player behavior based on YAML configuration
class ComputerPlayerFactory {
  final ComputerPlayerConfig config;
  final Random _random = Random();

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
    final decisionDelay = config.getDecisionDelay(difficulty);
    final cardSelection = config.getCardSelectionStrategy(difficulty);
    final evaluationWeights = config.getCardEvaluationWeights();
    
    if (availableCards.isEmpty) {
      return {
        'action': 'play_card',
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'No cards available to play',
      };
    }
    
    // Select card based on strategy
    final selectedCard = _selectCard(availableCards, cardSelection, evaluationWeights, gameState);
    
    return {
      'action': 'play_card',
      'card_id': selectedCard,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Selected card using ${cardSelection['strategy'] ?? 'random'} strategy',
    };
  }

  /// Get computer player decision for same rank play event
  Map<String, dynamic> getSameRankPlayDecision(String difficulty, Map<String, dynamic> gameState, List<String> availableCards) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    final playProbability = config.getSameRankPlayProbability(difficulty);
    
    final shouldPlay = _random.nextDouble() < playProbability;
    
    if (!shouldPlay || availableCards.isEmpty) {
      return {
        'action': 'same_rank_play',
        'play': false,
        'card_id': null,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'Decided not to play same rank (${((1 - playProbability) * 100).toStringAsFixed(1)}% probability)',
      };
    }
    
    // Select a card to play
    final selectedCard = availableCards[_random.nextInt(availableCards.length)];
    
    return {
      'action': 'same_rank_play',
      'play': true,
      'card_id': selectedCard,
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Playing same rank card (${(playProbability * 100).toStringAsFixed(1)}% probability)',
    };
  }

  /// Get computer player decision for Jack swap event
  Map<String, dynamic> getJackSwapDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    final jackSwapConfig = config.getSpecialCardConfig(difficulty, 'jack_swap');
    final useProbability = (jackSwapConfig['use_probability'] ?? 0.8).toDouble();
    final targetStrategy = jackSwapConfig['target_strategy'] ?? 'random';
    
    final shouldUse = _random.nextDouble() < useProbability;
    
    if (!shouldUse) {
      return {
        'action': 'jack_swap',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'Decided not to use Jack swap (${((1 - useProbability) * 100).toStringAsFixed(1)}% probability)',
      };
    }
    
    // Select targets based on strategy
    final targets = _selectJackSwapTargets(gameState, playerId, targetStrategy);
    
    return {
      'action': 'jack_swap',
      'use': true,
      'first_card_id': targets['first_card_id'],
      'first_player_id': targets['first_player_id'],
      'second_card_id': targets['second_card_id'],
      'second_player_id': targets['second_player_id'],
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Using Jack swap with $targetStrategy strategy (${(useProbability * 100).toStringAsFixed(1)}% probability)',
    };
  }

  /// Get computer player decision for Queen peek event
  Map<String, dynamic> getQueenPeekDecision(String difficulty, Map<String, dynamic> gameState, String playerId) {
    final decisionDelay = config.getDecisionDelay(difficulty);
    final queenPeekConfig = config.getSpecialCardConfig(difficulty, 'queen_peek');
    final useProbability = (queenPeekConfig['use_probability'] ?? 0.8).toDouble();
    final targetStrategy = queenPeekConfig['target_strategy'] ?? 'random';
    
    final shouldUse = _random.nextDouble() < useProbability;
    
    if (!shouldUse) {
      return {
        'action': 'queen_peek',
        'use': false,
        'delay_seconds': decisionDelay,
        'difficulty': difficulty,
        'reasoning': 'Decided not to use Queen peek (${((1 - useProbability) * 100).toStringAsFixed(1)}% probability)',
      };
    }
    
    // Select target based on strategy
    final target = _selectQueenPeekTarget(gameState, playerId, targetStrategy);
    
    return {
      'action': 'queen_peek',
      'use': true,
      'target_card_id': target['card_id'],
      'target_player_id': target['player_id'],
      'delay_seconds': decisionDelay,
      'difficulty': difficulty,
      'reasoning': 'Using Queen peek with $targetStrategy strategy (${(useProbability * 100).toStringAsFixed(1)}% probability)',
    };
  }

  /// Select a card based on strategy and evaluation weights
  String _selectCard(List<String> availableCards, Map<String, dynamic> cardSelection, Map<String, double> evaluationWeights, Map<String, dynamic> gameState) {
    final strategy = cardSelection['strategy'] ?? 'random';
    
    switch (strategy) {
      case 'random':
        return availableCards[_random.nextInt(availableCards.length)];
        
      case 'points_low':
        // TODO: Implement points-based selection
        return availableCards[_random.nextInt(availableCards.length)];
        
      case 'points_high':
        // TODO: Implement points-based selection
        return availableCards[_random.nextInt(availableCards.length)];
        
      case 'special_power':
        // TODO: Implement special power preference
        return availableCards[_random.nextInt(availableCards.length)];
        
      case 'strategic':
        // TODO: Implement complex strategic evaluation
        return availableCards[_random.nextInt(availableCards.length)];
        
      case 'optimal':
        // TODO: Implement optimal selection
        return availableCards[_random.nextInt(availableCards.length)];
        
      default:
        return availableCards[_random.nextInt(availableCards.length)];
    }
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
