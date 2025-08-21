import '../../../tools/logging/logger.dart';

/// Card suit enumeration
enum CardSuit {
  hearts,
  diamonds,
  clubs,
  spades,
  joker,
  special_0,
  special_1,
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
  king(13),
  joker(0),
  power_double_points(0),
  power_skip_turn(0),
  power_protect_card(0),
  power_steal_card(0),
  power_draw_extra(0);

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
  static final Logger _log = Logger();
  
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
      case CardSuit.joker:
        return '🃏';
      case CardSuit.special_0:
        return '⚡';
      case CardSuit.special_1:
        return '🌟';
    }
  }

  /// Get card color (red or black)
  String get color {
    switch (suit) {
      case CardSuit.hearts:
      case CardSuit.diamonds:
        return 'red';
      case CardSuit.clubs:
      case CardSuit.spades:
      case CardSuit.joker:
      case CardSuit.special_0:
      case CardSuit.special_1:
        return 'black';
    }
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

  /// Create card from JSON - backend is the source of truth for all card data
  factory Card.fromJson(Map<String, dynamic> json) {
    try {
      // Parse suit with error handling
      CardSuit suit;
      try {
        final suitStr = json['suit'] as String? ?? 'hearts';
        suit = CardSuit.values.firstWhere((s) => s.name == suitStr);
      } catch (e) {
        _log.error('❌ Failed to parse card suit: ${json['suit']}, available: ${CardSuit.values.map((s) => s.name).join(', ')}');
        _log.error('❌ JSON data: $json');
        throw ArgumentError('Invalid card suit: ${json['suit']}');
      }

      // Parse rank with error handling
      CardRank rank;
      try {
        final rankStr = json['rank'] as String? ?? 'ace';
        rank = CardRank.values.firstWhere((r) => r.name == rankStr);
      } catch (e) {
        _log.error('❌ Failed to parse card rank: ${json['rank']}, available: ${CardRank.values.map((r) => r.name).join(', ')}');
        _log.error('❌ JSON data: $json');
        throw ArgumentError('Invalid card rank: ${json['rank']}');
      }

      // Parse special power with error handling
      SpecialPowerType specialPower;
      try {
        final powerStr = json['specialPower'] as String? ?? 'none';
        specialPower = SpecialPowerType.values.firstWhere((s) => s.name == powerStr);
      } catch (e) {
        _log.warning('⚠️ Failed to parse special power: ${json['specialPower']}, using none as fallback');
        specialPower = SpecialPowerType.none; // fallback for special power is safe
      }

      // IMPORTANT: Always use backend point values - frontend never calculates points
      final int points = json['points'] ?? 0;

      return Card(
        suit: suit,
        rank: rank,
        points: points, // Backend is source of truth for points
        specialPower: specialPower,
        specialPowerDescription: json['specialPowerDescription'],
        specialPowerData: json['specialPowerData'],
      );
    } catch (e) {
      _log.error('❌ Error parsing Card from JSON: $e');
      _log.error('❌ JSON data: $json');
      rethrow;
    }
  }

  // REMOVED: Frontend should never generate cards - only backend creates cards
  // All card data (points, special powers, etc.) comes from backend JSON

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

  // REMOVED: Frontend should never generate decks - only backend creates and manages decks

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