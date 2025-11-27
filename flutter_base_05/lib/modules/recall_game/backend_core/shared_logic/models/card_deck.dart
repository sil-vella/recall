import '../../shared_imports.dart';
import 'card.dart';

/// CardDeck model for Recall Game
/// 
/// Represents a deck of cards with standard 52-card deck + 2 jokers
/// or testing deck with modified composition for easier testing.

class CardDeck {
  final List<Card> cards;
  final bool includeJokers;

  CardDeck({this.includeJokers = true}) : cards = [] {
    _initializeDeck();
  }

  /// Initialize the deck with all cards
  void _initializeDeck() {
    cards.clear();
    
    // Standard 52-card deck
    const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    const ranks = ['ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'jack', 'queen', 'king'];
    
    // Add standard cards
    for (final suit in suits) {
      for (final rank in ranks) {
        final points = _getPointValue(rank, suit);
        final specialPower = _getSpecialPower(rank);
        // Temporary ID - will be replaced by DeckFactory
        final cardId = 'temp-$rank-$suit';
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
    
    // Add Jokers (0 points)
    if (includeJokers) {
      for (int i = 0; i < 2; i++) {
        final cardId = 'temp-joker-$i';
        final card = Card(
          cardId: cardId,
          rank: 'joker',
          suit: 'joker',
          points: 0,
          specialPower: null,
        );
        cards.add(card);
      }
    }
  }

  /// Get the point value for a card
  int _getPointValue(String rank, String suit) {
    switch (rank) {
      case 'joker':
        return 0;
      case 'ace':
        return 1;
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
      case '10':
        return int.parse(rank);
      case 'jack':
      case 'queen':
      case 'king':
        return 10;
      default:
        return 0;
    }
  }

  /// Get special power for a card
  String? _getSpecialPower(String rank) {
    switch (rank) {
      case 'queen':
        return 'peek_at_card';
      case 'jack':
        return 'switch_cards';
      default:
        return null;
    }
  }

  /// Draw a card from the deck
  Card? drawCard() {
    if (cards.isEmpty) return null;
    return cards.removeAt(0);
  }

  /// Add a card to the deck
  void addCard(Card card) {
    cards.add(card);
  }

  /// Shuffle the deck
  void shuffle() {
    cards.shuffle();
  }

  /// Get the number of cards in the deck
  int get length => cards.length;

  /// Check if the deck is empty
  bool get isEmpty => cards.isEmpty;

  /// Check if the deck is not empty
  bool get isNotEmpty => cards.isNotEmpty;

  /// Get a copy of all cards without removing them
  List<Card> get allCards => List.unmodifiable(cards);

  /// Convert deck to Map for JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'cards': cards.map((card) => card.toMap()).toList(),
      'includeJokers': includeJokers,
    };
  }

  /// Create deck from Map (JSON deserialization)
  factory CardDeck.fromMap(Map<String, dynamic> map) {
    final deck = CardDeck(includeJokers: map['includeJokers'] ?? true);
    deck.cards.clear();
    
    final cardsList = map['cards'] as List<dynamic>? ?? [];
    for (final cardMap in cardsList) {
      deck.cards.add(Card.fromMap(cardMap as Map<String, dynamic>));
    }
    
    return deck;
  }

  @override
  String toString() => 'CardDeck(${cards.length} cards)';
}
