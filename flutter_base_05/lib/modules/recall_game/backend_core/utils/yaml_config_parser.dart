import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../shared_logic/models/card.dart';

/// YAML Configuration Parser for Deck Factory
/// 
/// Reads deck configuration from YAML file and provides
/// structured access to deck composition settings.

class DeckConfig {
  final Map<String, dynamic> _config;
  
  DeckConfig(this._config);
  
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
  
  /// Load configuration from YAML file (Flutter: loads from assets)
  static Future<DeckConfig> fromFile(String filePath) async {
    try {
      // Flutter: map file path to asset path
      String assetPath = filePath;
      if (filePath.contains('deck_config.yaml')) {
        assetPath = 'assets/deck_config.yaml';
      } else if (filePath.contains('computer_player_config.yaml')) {
        assetPath = 'assets/computer_player_config.yaml';
      } else if (filePath.startsWith('assets/')) {
        assetPath = filePath;
      } else {
        // Try to extract filename and map to assets
        final filename = filePath.split('/').last;
        assetPath = 'assets/$filename';
      }
      
      final yamlString = await rootBundle.loadString(assetPath);
      
      final yamlMap = loadYaml(yamlString);
      final convertedMap = _convertYamlMap(yamlMap) as Map<String, dynamic>;
      return DeckConfig(convertedMap);
    } catch (e) {
      throw Exception('Failed to load deck config from $filePath (mapped to assets): $e');
    }
  }
  
  /// Load configuration from YAML string
  static DeckConfig fromString(String yamlString) {
    try {
      final yamlMap = loadYaml(yamlString);
      final convertedMap = _convertYamlMap(yamlMap) as Map<String, dynamic>;
      return DeckConfig(convertedMap);
    } catch (e) {
      throw Exception('Failed to parse deck config from string: $e');
    }
  }
  
  /// Get deck settings
  Map<String, dynamic> get deckSettings => _config['deck_settings'] ?? {};
  
  /// Check if testing mode is enabled
  bool get isTestingMode => deckSettings['testing_mode'] ?? false;
  
  /// Check if jokers should be included
  bool get includeJokers => deckSettings['include_jokers'] ?? true;
  
  /// Get standard deck configuration
  Map<String, dynamic> get standardDeck => _config['standard_deck'] ?? {};
  
  /// Get testing deck configuration
  Map<String, dynamic> get testingDeck => _config['testing_deck'] ?? {};
  
  /// Get current deck configuration (standard or testing)
  Map<String, dynamic> get currentDeck => isTestingMode ? testingDeck : standardDeck;
  
  /// Get suits for current deck
  List<String> get suits => List<String>.from(currentDeck['suits'] ?? []);
  
  /// Get ranks configuration for current deck
  Map<String, dynamic> get ranks => currentDeck['ranks'] ?? {};
  
  /// Get jokers configuration for current deck
  Map<String, dynamic> get jokers => currentDeck['jokers'] ?? {};
  
  /// Get card display configuration
  Map<String, dynamic> get cardDisplay => _config['card_display'] ?? {};
  
  /// Get suit symbols
  Map<String, String> get suitSymbols {
    final symbols = cardDisplay['suits'] ?? {};
    return Map<String, String>.from(symbols);
  }
  
  /// Get rank symbols
  Map<String, String> get rankSymbols {
    final symbols = cardDisplay['ranks'] ?? {};
    return Map<String, String>.from(symbols);
  }
  
  /// Get rank names
  Map<String, String> get rankNames {
    final names = cardDisplay['names'] ?? {};
    return Map<String, String>.from(names);
  }
  
  /// Get special powers configuration
  Map<String, dynamic> get specialPowers => _config['special_powers'] ?? {};
  
  /// Get deck statistics
  Map<String, dynamic> get deckStats => _config['deck_stats'] ?? {};
  
  /// Get current deck statistics
  Map<String, dynamic> get currentDeckStats {
    final stats = deckStats;
    return isTestingMode ? (stats['testing'] ?? {}) : (stats['standard'] ?? {});
  }
  
  /// Build cards from configuration
  List<Card> buildCards(String gameId) {
    final cards = <Card>[];
    
    // Add cards for each suit and rank
    for (final suit in suits) {
      for (final rankEntry in ranks.entries) {
        final rank = rankEntry.key;
        final rankConfig = rankEntry.value as Map<String, dynamic>;
        
        final points = rankConfig['points'] ?? 0;
        final specialPower = rankConfig['special_power'];
        final quantityPerSuit = rankConfig['quantity_per_suit'] ?? 1;
        
        // Add the specified quantity of this rank for this suit
        for (int i = 0; i < quantityPerSuit; i++) {
          final cardId = _generateCardId(gameId, rank, suit, i);
          final card = Card(
            cardId: cardId,
            rank: rank,
            suit: suit,
            points: points,
            specialPower: specialPower,
          );
          cards.add(card);
        }
      }
    }
    
    // Add jokers if enabled
    if (includeJokers) {
      for (final jokerEntry in jokers.entries) {
        final jokerType = jokerEntry.key;
        final jokerConfig = jokerEntry.value as Map<String, dynamic>;
        
        final points = jokerConfig['points'] ?? 0;
        final specialPower = jokerConfig['special_power'];
        final quantityTotal = jokerConfig['quantity_total'] ?? 0;
        final suit = jokerConfig['suit'] ?? 'joker';
        
        for (int i = 0; i < quantityTotal; i++) {
          final cardId = _generateCardId(gameId, jokerType, suit, i);
          final card = Card(
            cardId: cardId,
            rank: jokerType,
            suit: suit,
            points: points,
            specialPower: specialPower,
          );
          cards.add(card);
        }
      }
    }
    
    return cards;
  }
  
  /// Generate unique card ID
  String _generateCardId(String gameId, String rank, String suit, int index) {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final random = (timestamp.hashCode + gameId.hashCode + rank.hashCode + suit.hashCode + index).abs();
    return 'card_${gameId}_${rank}_${suit}_${index}_$random';
  }
  
  /// Validate deck configuration
  Map<String, dynamic> validateConfig() {
    final errors = <String>[];
    final warnings = <String>[];
    
    // Check if required sections exist
    if (!_config.containsKey('deck_settings')) {
      errors.add('Missing deck_settings section');
    }
    
    if (!_config.containsKey('standard_deck')) {
      errors.add('Missing standard_deck section');
    }
    
    if (!_config.containsKey('testing_deck')) {
      errors.add('Missing testing_deck section');
    }
    
    // Validate current deck configuration
    if (this.currentDeck.isEmpty) {
      errors.add('Current deck configuration is empty');
    } else {
      // Check suits
      final suits = this.suits;
      if (suits.isEmpty) {
        errors.add('No suits defined in current deck');
      }
      
      // Check ranks
      final ranks = this.ranks;
      if (ranks.isEmpty) {
        errors.add('No ranks defined in current deck');
      }
      
      // Check jokers if enabled
      if (includeJokers && jokers.isEmpty) {
        warnings.add('Jokers enabled but no joker configuration found');
      }
    }
    
    return {
      'valid': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
    };
  }
  
  /// Get configuration summary
  Map<String, dynamic> getSummary() {
    final stats = currentDeckStats;
    
    return {
      'testing_mode': isTestingMode,
      'include_jokers': includeJokers,
      'suits': suits,
      'ranks_count': ranks.length,
      'jokers_count': jokers.length,
      'expected_total_cards': stats['total_cards'] ?? 0,
      'special_cards': stats['special_cards'] ?? 0,
    };
  }
}
