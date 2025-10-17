/// Card Models for Recall Game
///
/// This module defines the card system for the Recall card game,
/// including standard cards, special power cards, and point calculations.

enum CardSuit {
  hearts,
  diamonds,
  clubs,
  spades,
}

enum CardRank {
  joker,
  ace,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
}

enum SpecialPowerType {
  peekAtCard,    // Queen
  switchCards,   // Jack
  stealCard,     // Added power card
  drawExtra,     // Added power card
  protectCard,   // Added power card
}

class Card {
  /// Represents a single card in the Recall game
  /// 
  /// Note: cardId is required and should be generated using DeckFactory
  /// for deterministic, game-specific IDs.
  
  final String rank;
  final String suit;
  final int points;
  final String? specialPower;
  final String cardId;
  String? ownerId;

  Card({
    required this.rank,
    required this.suit,
    required this.points,
    this.specialPower,
    String? cardId,
    this.ownerId,
  }) : cardId = _validateCardId(cardId);

  static String _validateCardId(String? cardId) {
    if (cardId == null) {
      throw ArgumentError("card_id is required - use DeckFactory to create cards with proper IDs");
    }
    return cardId;
  }

  @override
  String toString() {
    if (rank == "joker") {
      return "Joker";
    }
    return "${rank[0].toUpperCase()}${rank.substring(1)} of ${suit[0].toUpperCase()}${suit.substring(1)}";
  }

  Map<String, dynamic> toDict() {
    return {
      "card_id": cardId,
      "rank": rank,
      "suit": suit,
      "points": points,
      "special_power": specialPower,
      "owner_id": ownerId,
    };
  }

  factory Card.fromDict(Map<String, dynamic> data) {
    final card = Card(
      rank: data["rank"],
      suit: data["suit"],
      points: data["points"],
      specialPower: data["special_power"],
      cardId: data["card_id"],
      ownerId: data["owner_id"],
    );
    return card;
  }

  int getPointValue() {
    return points;
  }

  bool hasSpecialPower() {
    return specialPower != null;
  }

  bool canPlayOutOfTurn(Card playedCard) {
    return rank == playedCard.rank;
  }
}

class CardDeck {
  /// Represents a deck of cards for the Recall game
  /// 
  /// Note: This class creates cards with temporary IDs. Use DeckFactory
  /// to create properly shuffled decks with deterministic card IDs.
  
  List<Card> cards = [];
  final bool includeJokers;

  CardDeck({this.includeJokers = true}) {
    _initializeDeck();
  }

  void _initializeDeck() {
    // Standard 52-card deck
    final suits = ["hearts", "diamonds", "clubs", "spades"];
    final ranks = ["ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "jack", "queen", "king"];
    
    // Add standard cards
    for (String suit in suits) {
      for (String rank in ranks) {
        final points = _getPointValue(rank, suit);
        final specialPower = _getSpecialPower(rank);
        // Temporary ID - will be replaced by DeckFactory
        final cardId = "temp-$rank-$suit";
        final card = Card(
          rank: rank,
          suit: suit,
          points: points,
          specialPower: specialPower,
          cardId: cardId,
        );
        cards.add(card);
      }
    }
    
    // Add Jokers (0 points)
    if (includeJokers) {
      for (int i = 0; i < 2; i++) {
        final cardId = "temp-joker-$i";
        final card = Card(
          rank: "joker",
          suit: "joker",
          points: 0,
          specialPower: null,
          cardId: cardId,
        );
        cards.add(card);
      }
    }
  }

  int _getPointValue(String rank, String suit) {
    if (rank == "joker") {
      return 0;
    } else if (rank == "ace") {
      return 1;
    } else if (["2", "3", "4", "5", "6", "7", "8", "9", "10"].contains(rank)) {
      return int.parse(rank);
    } else if (["jack", "queen"].contains(rank)) {
      return 10;
    } else if (rank == "king") {
      // Special handling for kings - red kings are 0 points, black kings are 10 points
      if (suit == "hearts" || suit == "diamonds") {
        return 0; // Red kings are 0 points
      } else {
        return 10; // Black kings are 10 points
      }
    } else {
      return 0;
    }
  }

  String? _getSpecialPower(String rank) {
    if (rank == "queen") {
      return "peek_at_card";
    } else if (rank == "jack") {
      return "switch_cards";
    } else {
      return null;
    }
  }


  void shuffle() {
    /// Shuffle the deck - Note: Use DeckFactory for deterministic shuffling
    cards.shuffle();
  }

  Card? drawCard() {
    /// Draw a card from the top of the deck
    if (cards.isNotEmpty) {
      return cards.removeLast();
    }
    return null;
  }

  void addCard(Card card) {
    /// Add a card to the deck
    cards.add(card);
  }

  int getRemainingCount() {
    /// Get the number of cards remaining in the deck
    return cards.length;
  }

  bool isEmpty() {
    /// Check if the deck is empty
    return cards.isEmpty;
  }

  void reset() {
    /// Reset the deck to its original state
    cards.clear();
    _initializeDeck();
  }
}
