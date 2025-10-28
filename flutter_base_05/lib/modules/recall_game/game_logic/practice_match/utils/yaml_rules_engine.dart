import 'dart:math';
import 'package:recall/tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// YAML Rules Engine - Generic interpreter for YAML-defined decision rules
class YamlRulesEngine {
  final Random _random = Random();
  
  /// Execute YAML rules and return selected card ID
  String executeRules(List<dynamic> rules, Map<String, dynamic> gameData, bool shouldPlayOptimal) {
    Logger().info('Practice: DEBUG - YamlRulesEngine.executeRules called with ${rules.length} rules, shouldPlayOptimal: $shouldPlayOptimal', isOn: LOGGING_SWITCH);
    
    // Sort rules by priority
    final sortedRules = List<Map<String, dynamic>>.from(rules)
      ..sort((a, b) => (a['priority'] ?? 999).compareTo(b['priority'] ?? 999));
    
    Logger().info('Practice: DEBUG - Sorted rules by priority: ${sortedRules.map((r) => '${r['name']} (${r['priority']})').join(', ')}', isOn: LOGGING_SWITCH);
    
    // If not playing optimally, skip to last rule (random fallback)
    if (!shouldPlayOptimal && sortedRules.isNotEmpty) {
      final lastRule = sortedRules.last;
      Logger().info('Practice: DEBUG - Not playing optimally, using last rule: ${lastRule['name']}', isOn: LOGGING_SWITCH);
      return _executeAction(lastRule['action'], gameData);
    }
    
    // Evaluate rules in priority order
    for (final rule in sortedRules) {
      final ruleName = rule['name'] ?? 'unnamed';
      Logger().info('Practice: DEBUG - Evaluating rule: $ruleName', isOn: LOGGING_SWITCH);
      
      final condition = rule['condition'] as Map<String, dynamic>?;
      if (condition != null) {
        final conditionResult = _evaluateCondition(condition, gameData);
        Logger().info('Practice: DEBUG - Rule $ruleName condition result: $conditionResult', isOn: LOGGING_SWITCH);
        
        if (conditionResult) {
          final action = rule['action'] as Map<String, dynamic>?;
          if (action != null) {
            Logger().info('Practice: DEBUG - Rule $ruleName condition passed, executing action', isOn: LOGGING_SWITCH);
            return _executeAction(action, gameData);
          }
        }
      }
    }
    
    Logger().info('Practice: DEBUG - No rules matched, using fallback logic', isOn: LOGGING_SWITCH);
    
    // Ultimate fallback: random from playable cards
    final playableCards = gameData['playable_cards'] as List<dynamic>? ?? [];
    if (playableCards.isNotEmpty) {
      Logger().info('Practice: DEBUG - Using playable cards fallback: ${playableCards.length} cards', isOn: LOGGING_SWITCH);
      return playableCards[_random.nextInt(playableCards.length)].toString();
    }
    
    // Last resort: random from available cards
    final availableCards = gameData['available_cards'] as List<dynamic>? ?? [];
    Logger().info('Practice: DEBUG - Using available cards fallback: ${availableCards.length} cards', isOn: LOGGING_SWITCH);
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
    
    Logger().info('Practice: DEBUG - _executeAction called with type: $type, source: $source, filters: ${filters.length}', isOn: LOGGING_SWITCH);
    
    // Get source data
    List<dynamic> sourceData = gameData[source] as List<dynamic>? ?? [];
    Logger().info('Practice: DEBUG - Initial source data from $source: ${sourceData.length} items', isOn: LOGGING_SWITCH);
    
    // Apply filters
    for (final filter in filters) {
      if (filter is Map<String, dynamic>) {
        Logger().info('Practice: DEBUG - Applying filter: ${filter['type']}', isOn: LOGGING_SWITCH);
        sourceData = _applyFilter(sourceData, filter, gameData);
        Logger().info('Practice: DEBUG - After filter, source data: ${sourceData.length} items', isOn: LOGGING_SWITCH);
      }
    }
    
    if (sourceData.isEmpty) {
      // Fallback to playable cards
      sourceData = gameData['playable_cards'] as List<dynamic>? ?? [];
      Logger().info('Practice: DEBUG - Source data empty, using playable cards fallback: ${sourceData.length} items', isOn: LOGGING_SWITCH);
    }
    
    if (sourceData.isEmpty) {
      // Last resort: available cards
      sourceData = gameData['available_cards'] as List<dynamic>? ?? [];
      Logger().info('Practice: DEBUG - Still empty, using available cards fallback: ${sourceData.length} items', isOn: LOGGING_SWITCH);
    }
    
    if (sourceData.isEmpty) {
      Logger().error('Practice: DEBUG - All fallbacks failed, no cards available!', isOn: LOGGING_SWITCH);
      return 'null'; // This will cause the error we're seeing
    }
    
    // Execute action type
    String result;
    switch (type) {
      case 'select_random':
        result = sourceData[_random.nextInt(sourceData.length)].toString();
        Logger().info('Practice: DEBUG - select_random result: $result', isOn: LOGGING_SWITCH);
        break;
      
      case 'select_highest_points':
        result = _selectHighestPoints(sourceData, gameData);
        Logger().info('Practice: DEBUG - select_highest_points result: $result', isOn: LOGGING_SWITCH);
        break;
      
      case 'select_lowest_points':
        result = _selectLowestPoints(sourceData, gameData);
        Logger().info('Practice: DEBUG - select_lowest_points result: $result', isOn: LOGGING_SWITCH);
        break;
      
      case 'select_first':
        result = sourceData.first.toString();
        Logger().info('Practice: DEBUG - select_first result: $result', isOn: LOGGING_SWITCH);
        break;
      
      case 'select_last':
        result = sourceData.last.toString();
        Logger().info('Practice: DEBUG - select_last result: $result', isOn: LOGGING_SWITCH);
        break;
      
      default:
        result = sourceData[_random.nextInt(sourceData.length)].toString();
        Logger().info('Practice: DEBUG - default action result: $result', isOn: LOGGING_SWITCH);
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

