import 'dart:io';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// YAML Configuration Parser for Computer Player Behavior
/// 
/// Reads computer player configuration from YAML file and provides
/// structured access to AI behavior settings.

class ComputerPlayerConfig {
  final Map<String, dynamic> _config;
  
  ComputerPlayerConfig(this._config);
  
  /// Convert YamlMap to Map<String, dynamic> recursively
  static dynamic _convertYamlMap(dynamic yamlData) {
    if (yamlData is Map) {
      return Map<String, dynamic>.from(
        yamlData.map((key, value) => MapEntry(
          key.toString(),
          _convertYamlMap(value),
        )),
      );
    } else if (yamlData is List) {
      return yamlData.map((item) => _convertYamlMap(item)).toList();
    } else {
      return yamlData;
    }
  }
  
  /// Load configuration from YAML file (supports both asset and file system paths)
  static Future<ComputerPlayerConfig> fromFile(String filePath) async {
    try {
      String yamlString;
      
      // Check if it's an asset path
      if (filePath.startsWith('assets/')) {
        yamlString = await rootBundle.loadString(filePath);
      } else {
        // Use file system access for non-asset paths
        final file = File(filePath);
        yamlString = await file.readAsString();
      }
      
      final yamlMap = loadYaml(yamlString);
      final convertedMap = _convertYamlMap(yamlMap) as Map<String, dynamic>;
      return ComputerPlayerConfig(convertedMap);
    } catch (e) {
      throw Exception('Failed to load computer player config from $filePath: $e');
    }
  }
  
  /// Load configuration from YAML string
  static ComputerPlayerConfig fromString(String yamlString) {
    try {
      final yamlMap = loadYaml(yamlString);
      final convertedMap = _convertYamlMap(yamlMap) as Map<String, dynamic>;
      return ComputerPlayerConfig(convertedMap);
    } catch (e) {
      throw Exception('Failed to parse computer player config from string: $e');
    }
  }
  
  /// Get computer player settings
  Map<String, dynamic> get computerSettings => _config['computer_settings'] ?? {};
  
  /// Get all difficulty levels
  Map<String, dynamic> get difficulties => _config['difficulties'] ?? {};
  
  /// Get all events configuration
  Map<String, dynamic> get events => _config['events'] ?? {};
  
  /// Get computer player statistics
  Map<String, dynamic> get computerStats => _config['computer_stats'] ?? {};
  
  /// Get configuration for a specific difficulty level
  Map<String, dynamic> getDifficultyConfig(String difficulty) {
    final difficulties = this.difficulties;
    if (difficulties.containsKey(difficulty)) {
      return difficulties[difficulty] as Map<String, dynamic>;
    }
    return {}; // Return empty config if difficulty not found
  }
  
  /// Get event configuration for a specific event
  Map<String, dynamic> getEventConfig(String eventName) {
    final events = this.events;
    if (events.containsKey(eventName)) {
      return events[eventName] as Map<String, dynamic>;
    }
    return {}; // Return empty config if event not found
  }
  
  /// Get decision delay for a difficulty level
  double getDecisionDelay(String difficulty) {
    final config = getDifficultyConfig(difficulty);
    return (config['decision_delay_seconds'] ?? 1.5).toDouble();
  }
  
  /// Get error rate for a difficulty level
  double getErrorRate(String difficulty) {
    final config = getDifficultyConfig(difficulty);
    return (config['error_rate'] ?? 0.05).toDouble();
  }
  
  /// Get card selection strategy for a difficulty level
  Map<String, dynamic> getCardSelectionStrategy(String difficulty) {
    final config = getDifficultyConfig(difficulty);
    return config['card_selection'] ?? {};
  }
  
  /// Get recall strategy for a difficulty level
  Map<String, dynamic> getRecallStrategy(String difficulty) {
    final config = getDifficultyConfig(difficulty);
    return config['recall_strategy'] ?? {};
  }
  
  /// Get special card configuration for a difficulty level
  Map<String, dynamic> getSpecialCardConfig(String difficulty, String cardType) {
    final config = getDifficultyConfig(difficulty);
    final specialCards = config['special_cards'] ?? {};
    return specialCards[cardType] ?? {};
  }
  
  /// Get draw from discard probability for a difficulty level
  double getDrawFromDiscardProbability(String difficulty) {
    final drawCardConfig = getEventConfig('draw_card');
    final probabilities = drawCardConfig['draw_from_discard_probability'] ?? {};
    return (probabilities[difficulty] ?? 0.5).toDouble();
  }
  
  /// Get same rank play probability for a difficulty level
  double getSameRankPlayProbability(String difficulty) {
    final sameRankConfig = getEventConfig('same_rank_play');
    final probabilities = sameRankConfig['play_probability'] ?? {};
    return (probabilities[difficulty] ?? 0.8).toDouble();
  }
  
  /// Get wrong rank play probability for difficulty
  double getWrongRankProbability(String difficulty) {
    final sameRankConfig = getEventConfig('same_rank_play');
    final probabilities = sameRankConfig['wrong_rank_probability'] ?? {};
    return (probabilities[difficulty] ?? 0.0).toDouble();
  }
  
  /// Get card evaluation weights for play_card event
  Map<String, double> getCardEvaluationWeights() {
    final playCardConfig = getEventConfig('play_card');
    final weights = playCardConfig['card_evaluation_weights'] ?? {};
    return Map<String, double>.from(
      weights.map((key, value) => MapEntry(key.toString(), (value ?? 0.0).toDouble()))
    );
  }
  
  /// Get Jack swap target strategy
  Map<String, dynamic> getJackSwapTargets() {
    final jackSwapConfig = getEventConfig('jack_swap');
    return jackSwapConfig['swap_targets'] ?? {};
  }
  
  /// Get Queen peek target strategy
  Map<String, dynamic> getQueenPeekTargets() {
    final queenPeekConfig = getEventConfig('queen_peek');
    return queenPeekConfig['peek_targets'] ?? {};
  }
  
  /// Get configuration summary
  Map<String, dynamic> getSummary() {
    return {
      'total_difficulties': difficulties.length,
      'supported_events': events.length,
      'config_version': computerStats['config_version'] ?? '1.0',
      'default_difficulty': computerSettings['default_difficulty'] ?? 'medium',
      'decision_delay': computerSettings['decision_delay_seconds'] ?? 1.0,
      'error_rate': computerSettings['error_rate'] ?? 0.05,
    };
  }
  
  /// Validate configuration
  Map<String, dynamic> validateConfig() {
    final errors = <String>[];
    final warnings = <String>[];
    
    // Check required sections
    if (difficulties.isEmpty) {
      errors.add('No difficulty levels defined');
    }
    
    if (events.isEmpty) {
      errors.add('No events configuration defined');
    }
    
    // Check difficulty levels
    for (final difficulty in difficulties.keys) {
      final config = getDifficultyConfig(difficulty);
      if (config.isEmpty) {
        errors.add('Empty configuration for difficulty: $difficulty');
        continue;
      }
      
      // Check required fields
      if (!config.containsKey('decision_delay_seconds')) {
        warnings.add('Missing decision_delay_seconds for difficulty: $difficulty');
      }
      
      if (!config.containsKey('error_rate')) {
        warnings.add('Missing error_rate for difficulty: $difficulty');
      }
      
      if (!config.containsKey('card_selection')) {
        warnings.add('Missing card_selection for difficulty: $difficulty');
      }
    }
    
    return {
      'valid': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
      'difficulty_count': difficulties.length,
      'event_count': events.length,
    };
  }
}
