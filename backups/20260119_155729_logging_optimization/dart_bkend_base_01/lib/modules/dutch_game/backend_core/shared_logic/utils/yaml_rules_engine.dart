import '../../../utils/platform/shared_imports.dart';

const bool LOGGING_SWITCH = false; // Enabled for timer-based delay system and time pressure testing

/// YAML Rules Engine - Generic interpreter for YAML-defined decision rules
class YamlRulesEngine {
  final Random _random = Random();
  final Logger _logger = Logger();
  
  /// Execute YAML rules and return selected card ID
  String executeRules(List<dynamic> rules, Map<String, dynamic> gameData, bool shouldPlayOptimal) {
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - YamlRulesEngine.executeRules called with ${rules.length} rules, shouldPlayOptimal: $shouldPlayOptimal');
    };
    
    // Sort rules by priority
    final sortedRules = List<Map<String, dynamic>>.from(rules)
      ..sort((a, b) => (a['priority'] ?? 999).compareTo(b['priority'] ?? 999));
    
    _logger.info('Dutch: DEBUG - Sorted rules by priority: ${sortedRules.map((r) => '${r['name']} (${r['priority']})').join(', ')}', isOn: LOGGING_SWITCH);
    
    // If not playing optimally, skip to last rule (random fallback)
    if (!shouldPlayOptimal && sortedRules.isNotEmpty) {
      final lastRule = sortedRules.last;
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Not playing optimally, using last rule: ${lastRule['name']}');
      };
      return _executeAction(lastRule['action'], gameData);
    }
    
    // Evaluate rules in priority order
    for (final rule in sortedRules) {
      final ruleName = rule['name'] ?? 'unnamed';
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Evaluating rule: $ruleName');
      };
      
      final condition = rule['condition'] as Map<String, dynamic>?;
      if (condition != null) {
        final conditionResult = _evaluateCondition(condition, gameData);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Rule $ruleName condition result: $conditionResult');
        };
        
        if (conditionResult) {
          final action = rule['action'] as Map<String, dynamic>?;
          if (action != null) {
            if (LOGGING_SWITCH) {
              _logger.info('Dutch: DEBUG - Rule $ruleName condition passed, executing action');
            };
            return _executeAction(action, gameData);
          }
        }
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - No rules matched, using fallback logic');
    };
    
    // Ultimate fallback: random from playable cards
    final playableCards = gameData['playable_cards'] as List<dynamic>? ?? [];
    if (playableCards.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Using playable cards fallback: ${playableCards.length} cards');
      };
      return playableCards[_random.nextInt(playableCards.length)].toString();
    }
    
    // Last resort: random from available cards
    final availableCards = gameData['available_cards'] as List<dynamic>? ?? [];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Using available cards fallback: ${availableCards.length} cards');
    };
    return availableCards[_random.nextInt(availableCards.length)].toString();
  }
  
  /// Evaluate a condition from YAML
  bool _evaluateCondition(Map<String, dynamic> condition, Map<String, dynamic> gameData) {
    final type = condition['type']?.toString() ?? 'always';
    
    switch (type) {
      case 'always':
        return true;
      
      case 'and':
        final conditions = condition['conditions'] as List<dynamic>? ?? [];
        return conditions.every((c) => _evaluateCondition(c as Map<String, dynamic>, gameData));
      
      case 'or':
        final conditions = condition['conditions'] as List<dynamic>? ?? [];
        return conditions.any((c) => _evaluateCondition(c as Map<String, dynamic>, gameData));
      
      case 'not':
        final subCondition = condition['condition'] as Map<String, dynamic>?;
        return subCondition != null ? !_evaluateCondition(subCondition, gameData) : false;
      
      default:
        // Field-based condition
        return _evaluateFieldCondition(condition, gameData);
    }
  }
  
  /// Evaluate a field-based condition
  bool _evaluateFieldCondition(Map<String, dynamic> condition, Map<String, dynamic> gameData) {
    final field = condition['field']?.toString();
    final operator = condition['operator']?.toString() ?? 'equals';
    final value = condition['value'];
    
    if (field == null) return false;
    
    final fieldValue = gameData[field];
    
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
      
      default:
        return false;
    }
  }
  
  /// Execute an action from YAML
  String _executeAction(Map<String, dynamic> action, Map<String, dynamic> gameData) {
    final type = action['type']?.toString() ?? 'select_random';
    final source = action['source']?.toString() ?? 'playable_cards';
    final filters = action['filters'] as List<dynamic>? ?? [];
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - _executeAction called with type: $type, source: $source, filters: ${filters.length}');
    };
    
    // Get source data
    List<dynamic> sourceData = gameData[source] as List<dynamic>? ?? [];
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Initial source data from $source: ${sourceData.length} items');
    };
    
    // CRITICAL: Always filter out null cards and collection cards from any source
    // Get collection card IDs from gameData
    final collectionCardIds = (gameData['collection_cards'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    
    // Filter out nulls and collection cards
    sourceData = sourceData
        .where((cardId) {
          final cardIdStr = cardId.toString();
          // Filter out null cards (null, 'null', or empty strings)
          if (cardIdStr.isEmpty || cardIdStr == 'null') {
            return false;
          }
          // Filter out collection rank cards
          if (collectionCardIds.contains(cardIdStr)) {
            return false;
          }
          return true;
        })
        .toList();
    
    if (LOGGING_SWITCH) {
      _logger.info('Dutch: DEBUG - Source data after null/collection filtering: ${sourceData.length} items');
    };
    
    // Apply filters
    for (final filter in filters) {
      if (filter is Map<String, dynamic>) {
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - Applying filter: ${filter['type']}');
        };
        sourceData = _applyFilter(sourceData, filter, gameData);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - After filter, source data: ${sourceData.length} items');
        };
      }
    }
    
    if (sourceData.isEmpty) {
      // Fallback to playable cards
      sourceData = gameData['playable_cards'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Source data empty, using playable cards fallback: ${sourceData.length} items');
      };
      
      // Filter fallback data too
      sourceData = sourceData
          .where((cardId) {
            final cardIdStr = cardId.toString();
            if (cardIdStr.isEmpty || cardIdStr == 'null') return false;
            if (collectionCardIds.contains(cardIdStr)) return false;
            return true;
          })
          .toList();
    }
    
    if (sourceData.isEmpty) {
      // Last resort: available cards
      sourceData = gameData['available_cards'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('Dutch: DEBUG - Still empty, using available cards fallback: ${sourceData.length} items');
      };
      
      // Filter fallback data too (but this shouldn't be used if playable_cards exists)
      sourceData = sourceData
          .where((cardId) {
            final cardIdStr = cardId.toString();
            if (cardIdStr.isEmpty || cardIdStr == 'null') return false;
            if (collectionCardIds.contains(cardIdStr)) return false;
            return true;
          })
          .toList();
    }
    
    if (sourceData.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('Dutch: DEBUG - All fallbacks failed, no cards available!');
      };
      return ''; // Return empty string to indicate no card available
    }
    
    // Execute action type
    String result;
    switch (type) {
      case 'select_random':
        result = sourceData[_random.nextInt(sourceData.length)].toString();
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - select_random result: $result');
        };
        break;
      
      case 'select_highest_points':
        result = _selectHighestPoints(sourceData, gameData);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - select_highest_points result: $result');
        };
        break;
      
      case 'select_lowest_points':
        result = _selectLowestPoints(sourceData, gameData);
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - select_lowest_points result: $result');
        };
        break;
      
      case 'select_first':
        result = sourceData.first.toString();
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - select_first result: $result');
        };
        break;
      
      case 'select_last':
        result = sourceData.last.toString();
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - select_last result: $result');
        };
        break;
      
      default:
        result = sourceData[_random.nextInt(sourceData.length)].toString();
        if (LOGGING_SWITCH) {
          _logger.info('Dutch: DEBUG - default action result: $result');
        };
        break;
    }
    
    return result;
  }
  
  /// Apply a filter to source data
  List<dynamic> _applyFilter(List<dynamic> data, Map<String, dynamic> filter, Map<String, dynamic> gameData) {
    final type = filter['type']?.toString();
    final value = filter['value'];
    
    switch (type) {
      case 'exclude_rank':
        // Filter out cards with specific rank
        final allCards = gameData['all_cards_data'] as List<dynamic>? ?? [];
        final cardIds = data.map((d) => d.toString()).toSet();
        final filteredCards = allCards.where((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['id']?.toString();
            final rank = card['rank']?.toString();
            return cardIds.contains(cardId) && rank != value;
          }
          return false;
        }).map((card) => (card as Map<String, dynamic>)['id']).toList();
        return filteredCards;
      
      case 'exclude_suit':
        final allCards = gameData['all_cards_data'] as List<dynamic>? ?? [];
        final cardIds = data.map((d) => d.toString()).toSet();
        final filteredCards = allCards.where((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['id']?.toString();
            final suit = card['suit']?.toString();
            return cardIds.contains(cardId) && suit != value;
          }
          return false;
        }).map((card) => (card as Map<String, dynamic>)['id']).toList();
        return filteredCards;
      
      case 'only_rank':
        final allCards = gameData['all_cards_data'] as List<dynamic>? ?? [];
        final cardIds = data.map((d) => d.toString()).toSet();
        final filteredCards = allCards.where((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['id']?.toString();
            final rank = card['rank']?.toString();
            return cardIds.contains(cardId) && rank == value;
          }
          return false;
        }).map((card) => (card as Map<String, dynamic>)['id']).toList();
        return filteredCards;
      
      default:
        return data;
    }
  }
  
  /// Select card with highest points
  String _selectHighestPoints(List<dynamic> cardIds, Map<String, dynamic> gameData) {
    final allCards = gameData['all_cards_data'] as List<dynamic>? ?? [];
    final cardIdSet = cardIds.map((d) => d.toString()).toSet();
    
    final candidateCards = allCards.where((card) {
      if (card is Map<String, dynamic>) {
        final cardId = card['id']?.toString();
        return cardIdSet.contains(cardId);
      }
      return false;
    }).cast<Map<String, dynamic>>().toList();
    
    if (candidateCards.isEmpty) {
      return cardIds[_random.nextInt(cardIds.length)].toString();
    }
    
    Map<String, dynamic>? highestCard;
    int highestPoints = -1;
    
    for (final card in candidateCards) {
      final points = card['points'] as int? ?? 0;
      if (points > highestPoints) {
        highestPoints = points;
        highestCard = card;
      }
    }
    
    return highestCard?['id']?.toString() ?? cardIds[_random.nextInt(cardIds.length)].toString();
  }
  
  /// Select card with lowest points
  String _selectLowestPoints(List<dynamic> cardIds, Map<String, dynamic> gameData) {
    final allCards = gameData['all_cards_data'] as List<dynamic>? ?? [];
    final cardIdSet = cardIds.map((d) => d.toString()).toSet();
    
    final candidateCards = allCards.where((card) {
      if (card is Map<String, dynamic>) {
        final cardId = card['id']?.toString();
        return cardIdSet.contains(cardId);
      }
      return false;
    }).cast<Map<String, dynamic>>().toList();
    
    if (candidateCards.isEmpty) {
      return cardIds[_random.nextInt(cardIds.length)].toString();
    }
    
    Map<String, dynamic>? lowestCard;
    int lowestPoints = 999;
    
    for (final card in candidateCards) {
      final points = card['points'] as int? ?? 0;
      if (points < lowestPoints) {
        lowestPoints = points;
        lowestCard = card;
      }
    }
    
    return lowestCard?['id']?.toString() ?? cardIds[_random.nextInt(cardIds.length)].toString();
  }
}

