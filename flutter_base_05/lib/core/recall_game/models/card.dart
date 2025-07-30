import 'package:flutter/material.dart' hide Card;
import '../utils/game_constants.dart';

/// Card suit enumeration
enum CardSuit {
  hearts,
  diamonds,
  clubs,
  spades,
}

/// Card rank enumeration
enum CardRank {
  ace(1),
  two(2),
  three(3),
  four(4),
  five(5),
  six(6),
  seven(7),
  eight(8),
  nine(9),
  ten(10),
  jack(11),
  queen(12),
  king(13);

  const CardRank(this.value);
  final int value;
}

/// Special power types for cards
enum SpecialPowerType {
  queen,    // Peek at a card
  jack,     // Switch cards
  addedPower, // Custom special powers
  none,     // No special power
}

/// Card model for the Recall game
class Card {
  final CardSuit suit;
  final CardRank rank;
  final int points;
  final SpecialPowerType specialPower;
  final String? specialPowerDescription;
  final Map<String, dynamic>? specialPowerData;
  
  const Card({
    required this.suit,
    required this.rank,
    required this.points,
    this.specialPower = SpecialPowerType.none,
    this.specialPowerDescription,
    this.specialPowerData,
  });

  /// Get card display name
  String get displayName {
    final rankName = rank.name.substring(0, 1).toUpperCase() + rank.name.substring(1);
    final suitSymbol = _getSuitSymbol();
    return '$rankName$suitSymbol';
  }

  /// Get suit symbol for display
  String _getSuitSymbol() {
    switch (suit) {
      case CardSuit.hearts:
        return '♥';
      case CardSuit.diamonds:
        return '♦';
      case CardSuit.clubs:
        return '♣';
      case CardSuit.spades:
        return '♠';
    }
  }

  /// Get card color (red or black)
  String get color {
    return (suit == CardSuit.hearts || suit == CardSuit.diamonds) ? 'red' : 'black';
  }

  /// Check if card has special power
  bool get hasSpecialPower => specialPower != SpecialPowerType.none;

  /// Check if card can be played out of turn
  bool get canPlayOutOfTurn {
    return hasSpecialPower && 
           (specialPower == SpecialPowerType.queen || 
            specialPower == SpecialPowerType.jack ||
            specialPower == SpecialPowerType.addedPower);
  }

  /// Convert card to JSON
  Map<String, dynamic> toJson() {
    return {
      'suit': suit.name,
      'rank': rank.name,
      'points': points,
      'specialPower': specialPower.name,
      'specialPowerDescription': specialPowerDescription,
      'specialPowerData': specialPowerData,
      'displayName': displayName,
      'color': color,
    };
  }

  /// Create card from JSON
  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(
      suit: CardSuit.values.firstWhere((s) => s.name == json['suit']),
      rank: CardRank.values.firstWhere((r) => r.name == json['rank']),
      points: json['points'],
      specialPower: SpecialPowerType.values.firstWhere((s) => s.name == json['specialPower']),
      specialPowerDescription: json['specialPowerDescription'],
      specialPowerData: json['specialPowerData'],
    );
  }

  /// Create a standard deck of 52 cards
  static List<Card> createStandardDeck() {
    final List<Card> deck = [];
    
    for (final suit in CardSuit.values) {
      for (final rank in CardRank.values) {
        int points = _calculatePoints(rank);
        SpecialPowerType specialPower = _getSpecialPower(rank);
        String? specialPowerDescription = _getSpecialPowerDescription(rank);
        
        deck.add(Card(
          suit: suit,
          rank: rank,
          points: points,
          specialPower: specialPower,
          specialPowerDescription: specialPowerDescription,
        ));
      }
    }
    
    return deck;
  }

  /// Calculate points for a card rank
  static int _calculatePoints(CardRank rank) {
    switch (rank) {
      case CardRank.ace:
        return 1;
      case CardRank.two:
      case CardRank.three:
      case CardRank.four:
      case CardRank.five:
      case CardRank.six:
      case CardRank.seven:
      case CardRank.eight:
      case CardRank.nine:
      case CardRank.ten:
        return rank.value;
      case CardRank.jack:
        return 11;
      case CardRank.queen:
        return 12;
      case CardRank.king:
        return 13;
    }
  }

  /// Get special power for a card rank
  static SpecialPowerType _getSpecialPower(CardRank rank) {
    switch (rank) {
      case CardRank.queen:
        return SpecialPowerType.queen;
      case CardRank.jack:
        return SpecialPowerType.jack;
      default:
        return SpecialPowerType.none;
    }
  }

  /// Get special power description
  static String? _getSpecialPowerDescription(CardRank rank) {
    switch (rank) {
      case CardRank.queen:
        return 'Peek at a card from any player\'s hand';
      case CardRank.jack:
        return 'Switch a card with another player';
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Card &&
        other.suit == suit &&
        other.rank == rank;
  }

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;

  @override
  String toString() {
    return 'Card($displayName, points: $points)';
  }
}

/// Card deck model for managing a collection of cards
class CardDeck {
  List<Card> _cards;

  CardDeck({List<Card>? cards}) : _cards = cards ?? [];

  /// Get all cards in the deck
  List<Card> get cards => List.unmodifiable(_cards);

  /// Get number of cards in deck
  int get length => _cards.length;

  /// Check if deck is empty
  bool get isEmpty => _cards.isEmpty;

  /// Check if deck is not empty
  bool get isNotEmpty => _cards.isNotEmpty;

  /// Shuffle the deck
  void shuffle() {
    _cards.shuffle();
  }

  /// Draw a card from the top of the deck
  Card? drawCard() {
    if (_cards.isEmpty) return null;
    return _cards.removeAt(0);
  }

  /// Draw multiple cards
  List<Card> drawCards(int count) {
    final drawnCards = <Card>[];
    for (int i = 0; i < count && _cards.isNotEmpty; i++) {
      drawnCards.add(_cards.removeAt(0));
    }
    return drawnCards;
  }

  /// Add a card to the bottom of the deck
  void addCard(Card card) {
    _cards.add(card);
  }

  /// Add multiple cards to the deck
  void addCards(List<Card> cards) {
    _cards.addAll(cards);
  }

  /// Clear all cards from the deck
  void clear() {
    _cards.clear();
  }

  /// Create a standard deck and shuffle it
  factory CardDeck.standard() {
    final deck = CardDeck(cards: Card.createStandardDeck());
    deck.shuffle();
    return deck;
  }

  /// Convert deck to JSON
  Map<String, dynamic> toJson() {
    return {
      'cards': _cards.map((card) => card.toJson()).toList(),
    };
  }

  /// Create deck from JSON
  factory CardDeck.fromJson(Map<String, dynamic> json) {
    final cards = (json['cards'] as List)
        .map((cardJson) => Card.fromJson(cardJson))
        .toList();
    return CardDeck(cards: cards);
  }
} 