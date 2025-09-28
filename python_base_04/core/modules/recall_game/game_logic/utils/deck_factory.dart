/// Random Deck Factory for Recall Game
///
/// Builds a per-game shuffled deck with completely random card_ids.
///
/// Each game gets unique, unpredictable card IDs to ensure no patterns
/// can be exploited across different games.

import 'dart:math';
import '../models/card.dart';
import '../../../../../tools/logger/dart_logger/logger.dart';

// Testing switch - set to true for testing deck with more special cards
const bool testingSwitch = true;
const bool LOGGING_SWITCH = true;

class DeckFactory {
  /// Creates a deck with completely random card IDs for a given game_id.
  ///
  /// - Assigns random card_id: Unique random string for each card
  /// - Shuffles deck randomly
  /// - No deterministic patterns or reproducible seeds

  final String gameId;
  final Random _random = Random();

  DeckFactory(this.gameId);

  String _generateRandomCardId() {
    /// Generate a completely random card ID
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomPart = List.generate(12, (index) => chars[_random.nextInt(chars.length)]).join();
    
    // Add a timestamp component for additional uniqueness
    final timestampPart = DateTime.now().microsecondsSinceEpoch.toString().substring(8);
    
    return "card_${randomPart}_$timestampPart";
  }

  List<Card> buildDeck({bool includeJokers = true}) {
    Logger().info('Building deck for game $gameId with ${includeJokers ? "jokers" : "no jokers"}', isOn: LOGGING_SWITCH);
    final deck = CardDeck(includeJokers: includeJokers);

    // Create new cards with random IDs
    final newCards = deck.cards.map((card) => Card(
      rank: card.rank,
      suit: card.suit,
      points: card.points,
      specialPower: card.specialPower,
      cardId: _generateRandomCardId(),
    )).toList();

    // Random shuffle using system random (no seed)
    newCards.shuffle();
    Logger().info('Deck built and shuffled for game $gameId: ${newCards.length} cards', isOn: LOGGING_SWITCH);
    return newCards;
  }
}

class TestingDeckFactory {
  /// Creates a testing deck with more Queens and Jacks for easier special card testing.
  ///
  /// This factory generates a deck with:
  /// - More Queens and Jacks (special cards)
  /// - Fewer numbered cards (2-10)
  /// - Same Kings and Aces as normal deck
  /// - Same Jokers as normal deck

  final String gameId;
  final Random _random = Random();

  TestingDeckFactory(this.gameId);

  String _generateRandomCardId() {
    /// Generate a completely random card ID
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomPart = List.generate(12, (index) => chars[_random.nextInt(chars.length)]).join();
    
    // Add a timestamp component for additional uniqueness
    final timestampPart = DateTime.now().microsecondsSinceEpoch.toString().substring(8);
    
    return "card_${randomPart}_$timestampPart";
  }

  List<Card> buildDeck({bool includeJokers = true}) {
    /// Build a testing deck with more special cards (Queens and Jacks)
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
          rank: 'queen',
          suit: suit,
          points: 10,
          specialPower: 'queen_peek',
          cardId: _generateRandomCardId(),
        );
        cards.add(card);
      }
      
      // Add more Jacks (4 per suit)
      for (int i = 0; i < 4; i++) {
        final card = Card(
          rank: 'jack',
          suit: suit,
          points: 10,
          specialPower: 'jack_swap',
          cardId: _generateRandomCardId(),
        );
        cards.add(card);
      }
      
      // Add fewer numbered cards (only 3, 4, 5)
      for (final rank in ['3', '4', '5']) {
        final points = int.parse(rank);
        final card = Card(
          rank: rank,
          suit: suit,
          points: points,
          specialPower: null,
          cardId: _generateRandomCardId(),
        );
        cards.add(card);
      }
      
      // Add Kings (4 per suit)
      final kingCard = Card(
        rank: 'king',
        suit: suit,
        points: 10,
        specialPower: null,
        cardId: _generateRandomCardId(),
      );
      cards.add(kingCard);
      
      // Add Aces (4 per suit)
      final aceCard = Card(
        rank: 'ace',
        suit: suit,
        points: 1,
        specialPower: null,
        cardId: _generateRandomCardId(),
      );
      cards.add(aceCard);
    }
    
    // Add Jokers if requested
    if (includeJokers) {
      for (int i = 0; i < 2; i++) {
        final card = Card(
          rank: 'joker',
          suit: 'none',
          points: 0,
          specialPower: null,
          cardId: _generateRandomCardId(),
        );
        cards.add(card);
      }
    }
    
    // Random shuffle using system random (no seed)
    cards.shuffle();
    return cards;
  }
}

DeckFactory getDeckFactory(String gameId, {int? seed}) {
  /// Factory function that returns the appropriate deck factory based on testingSwitch
  if (testingSwitch) {
    return DeckFactory(gameId); // Use regular DeckFactory for now
  } else {
    return DeckFactory(gameId);
  }
}
