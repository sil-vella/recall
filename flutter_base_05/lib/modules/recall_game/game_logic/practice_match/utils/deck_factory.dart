import 'dart:math';
import '../models/card.dart';
import '../models/card_deck.dart';
import 'yaml_config_parser.dart';

/// Random Deck Factory for Recall Game
/// 
/// Builds a per-game shuffled deck with completely random card_ids.
/// Each game gets unique, unpredictable card IDs to ensure no patterns
/// can be exploited across different games.

// Testing switch - set to true for testing deck with more special cards
const bool testingSwitch = true;

/// Creates a deck with completely random card IDs for a given game_id.
/// 
/// - Assigns random card_id: Unique random string for each card
/// - Shuffles deck randomly
/// - No deterministic patterns or reproducible seeds
class DeckFactory {
  final String gameId;
  final Random _random = Random();

  DeckFactory(this.gameId);

  /// Generate a completely random card ID
  String _generateRandomCardId() {
    // Generate a random 12-character alphanumeric string
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomPart = String.fromCharCodes(
      Iterable.generate(12, (_) => chars.codeUnitAt(_random.nextInt(chars.length)))
    );
    
    // Add a timestamp component for additional uniqueness
    final timestampPart = DateTime.now().microsecondsSinceEpoch.toString().substring(8);
    
    return 'card_${randomPart}_$timestampPart';
  }

  /// Build a standard deck with random card IDs
  List<Card> buildDeck({bool includeJokers = true}) {
    final deck = CardDeck(includeJokers: includeJokers);
    
    // Assign completely random IDs to each card
    for (final card in deck.cards) {
      final newCard = card.copyWith(cardId: _generateRandomCardId());
      final index = deck.cards.indexOf(card);
      deck.cards[index] = newCard;
    }
    
    // Random shuffle using system random (no seed)
    deck.shuffle();
    return deck.cards;
  }
}

/// Creates a testing deck with more Queens and Jacks for easier special card testing.
/// 
/// This factory generates a deck with:
/// - More Queens and Jacks (special cards)
/// - Fewer numbered cards (2-10)
/// - Same Kings and Aces as normal deck
/// - Same Jokers as normal deck
class TestingDeckFactory {
  final String gameId;
  final Random _random = Random();

  TestingDeckFactory(this.gameId);

  /// Generate a completely random card ID
  String _generateRandomCardId() {
    // Generate a random 12-character alphanumeric string
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomPart = String.fromCharCodes(
      Iterable.generate(12, (_) => chars.codeUnitAt(_random.nextInt(chars.length)))
    );
    
    // Add a timestamp component for additional uniqueness
    final timestampPart = DateTime.now().microsecondsSinceEpoch.toString().substring(8);
    
    return 'card_${randomPart}_$timestampPart';
  }

  /// Build a testing deck with more special cards (Queens and Jacks)
  List<Card> buildDeck({bool includeJokers = true}) {
    final cards = <Card>[];
    
    // Standard suits
    const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    
    // Testing deck composition:
    // - More Queens and Jacks (4 of each suit = 16 total)
    // - Fewer numbered cards (only 3-5 of each suit = 12 total)
    // - Same Kings and Aces (4 of each suit = 8 total)
    // - Same Jokers (2 total)
    
    for (final suit in suits) {
      // Add more Queens (4 per suit)
      for (int i = 0; i < 4; i++) {
        final card = Card(
          cardId: _generateRandomCardId(),
          rank: 'queen',
          suit: suit,
          points: 10,
          specialPower: 'peek_at_card',
        );
        cards.add(card);
      }
      
      // Add more Jacks (4 per suit)
      for (int i = 0; i < 4; i++) {
        final card = Card(
          cardId: _generateRandomCardId(),
          rank: 'jack',
          suit: suit,
          points: 10,
          specialPower: 'switch_cards',
        );
        cards.add(card);
      }
      
      // Add fewer numbered cards (only 3, 4, 5)
      for (final rank in ['3', '4', '5']) {
        final points = int.parse(rank);
        final card = Card(
          cardId: _generateRandomCardId(),
          rank: rank,
          suit: suit,
          points: points,
          specialPower: null,
        );
        cards.add(card);
      }
      
      // Add Kings (4 per suit)
      final kingCard = Card(
        cardId: _generateRandomCardId(),
        rank: 'king',
        suit: suit,
        points: 10,
        specialPower: null,
      );
      cards.add(kingCard);
      
      // Add Aces (4 per suit)
      final aceCard = Card(
        cardId: _generateRandomCardId(),
        rank: 'ace',
        suit: suit,
        points: 1,
        specialPower: null,
      );
      cards.add(aceCard);
    }
    
    // Add Jokers if requested
    if (includeJokers) {
      for (int i = 0; i < 2; i++) {
        final card = Card(
          cardId: _generateRandomCardId(),
          rank: 'joker',
          suit: 'none',
          points: 0,
          specialPower: null,
        );
        cards.add(card);
      }
    }
    
    // Random shuffle using system random (no seed)
    cards.shuffle();
    return cards;
  }
}

/// Factory function that returns the appropriate deck factory based on testingSwitch
dynamic getDeckFactory(String gameId) {
  if (testingSwitch) {
    return TestingDeckFactory(gameId);
  } else {
    return DeckFactory(gameId);
  }
}

/// YAML-based deck factory that uses configuration file
class YamlDeckFactory {
  final String gameId;
  final DeckConfig config;
  final Random _random = Random();

  YamlDeckFactory(this.gameId, this.config);

  /// Create factory from YAML file
  static Future<YamlDeckFactory> fromFile(String gameId, String configPath) async {
    final config = await DeckConfig.fromFile(configPath);
    return YamlDeckFactory(gameId, config);
  }

  /// Create factory from YAML string
  static YamlDeckFactory fromString(String gameId, String yamlString) {
    final config = DeckConfig.fromString(yamlString);
    return YamlDeckFactory(gameId, config);
  }

  /// Build deck using YAML configuration
  List<Card> buildDeck({bool? includeJokers}) {
    // Override includeJokers if specified
    final shouldIncludeJokers = includeJokers ?? config.includeJokers;
    
    // Build cards from configuration
    final cards = config.buildCards(gameId);
    
    // Filter out jokers if not wanted
    if (!shouldIncludeJokers) {
      cards.removeWhere((card) => card.isJoker);
    }
    
    // Random shuffle using system random (no seed)
    cards.shuffle(_random);
    return cards;
  }

  /// Get configuration summary
  Map<String, dynamic> getSummary() => config.getSummary();

  /// Validate configuration
  Map<String, dynamic> validateConfig() => config.validateConfig();
}

/// Utility functions for deck operations
class DeckUtils {
  /// Convert a list of cards to a list of maps for JSON serialization
  static List<Map<String, dynamic>> cardsToMaps(List<Card> cards) {
    return cards.map((card) => card.toMap()).toList();
  }

  /// Convert a list of maps to a list of cards for JSON deserialization
  static List<Card> mapsToCards(List<Map<String, dynamic>> maps) {
    return maps.map((map) => Card.fromMap(map)).toList();
  }

  /// Get deck statistics
  static Map<String, int> getDeckStats(List<Card> cards) {
    final stats = <String, int>{
      'total': cards.length,
      'queens': 0,
      'jacks': 0,
      'kings': 0,
      'aces': 0,
      'jokers': 0,
      'numbered': 0,
    };

    for (final card in cards) {
      switch (card.rank) {
        case 'queen':
          stats['queens'] = (stats['queens'] ?? 0) + 1;
          break;
        case 'jack':
          stats['jacks'] = (stats['jacks'] ?? 0) + 1;
          break;
        case 'king':
          stats['kings'] = (stats['kings'] ?? 0) + 1;
          break;
        case 'ace':
          stats['aces'] = (stats['aces'] ?? 0) + 1;
          break;
        case 'joker':
          stats['jokers'] = (stats['jokers'] ?? 0) + 1;
          break;
        default:
          if (int.tryParse(card.rank) != null) {
            stats['numbered'] = (stats['numbered'] ?? 0) + 1;
          }
          break;
      }
    }

    return stats;
  }

  /// Print deck statistics for debugging
  static void printDeckStats(List<Card> cards) {
    final stats = getDeckStats(cards);
    print('Deck Statistics:');
    stats.forEach((key, value) {
      print('  $key: $value');
    });
  }
}
