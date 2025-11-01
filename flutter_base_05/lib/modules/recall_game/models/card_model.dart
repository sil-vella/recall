import 'package:flutter/material.dart';

/// Represents a single card in the Recall game
class CardModel {
  final String cardId;
  final String rank;
  final String suit;
  final int points;
  final String? specialPower;
  final String? ownerId;
  final bool isSelected;
  final bool isFaceDown;

  const CardModel({
    required this.cardId,
    required this.rank,
    required this.suit,
    required this.points,
    this.specialPower,
    this.ownerId,
    this.isSelected = false,
    this.isFaceDown = false,
  });

  /// Create a card from a map (typically from backend/state)
  factory CardModel.fromMap(Map<String, dynamic> map) {
    return CardModel(
      cardId: map['cardId']?.toString() ?? '',
      rank: map['rank']?.toString() ?? '?',
      suit: map['suit']?.toString() ?? '?',
      points: map['points']?.toInt() ?? 0,
      specialPower: map['specialPower']?.toString(),
      ownerId: map['ownerId']?.toString(),
      isSelected: map['isSelected'] ?? false,
      isFaceDown: map['isFaceDown'] ?? false,
    );
  }

  /// Convert card to map for state management
  Map<String, dynamic> toMap() {
    return {
      'cardId': cardId,
      'rank': rank,
      'suit': suit,
      'points': points,
      'specialPower': specialPower,
      'ownerId': ownerId,
      'isSelected': isSelected,
      'isFaceDown': isFaceDown,
    };
  }

  /// Create a copy of this card with updated properties
  CardModel copyWith({
    String? cardId,
    String? rank,
    String? suit,
    int? points,
    String? specialPower,
    String? ownerId,
    bool? isSelected,
    bool? isFaceDown,
  }) {
    return CardModel(
      cardId: cardId ?? this.cardId,
      rank: rank ?? this.rank,
      suit: suit ?? this.suit,
      points: points ?? this.points,
      specialPower: specialPower ?? this.specialPower,
      ownerId: ownerId ?? this.ownerId,
      isSelected: isSelected ?? this.isSelected,
      isFaceDown: isFaceDown ?? this.isFaceDown,
    );
  }

  /// Get the display text for the card
  String get displayText {
    if (rank == 'joker') return 'Joker';
    return '${rank.toUpperCase()} of ${suit.toUpperCase()}';
  }

  /// Get the short display text (e.g., "A♠")
  String get shortDisplayText {
    if (rank == 'joker') return 'J';
    return '$rankSymbol$suitSymbol';
  }

  /// Check if this card has a special power
  bool get hasSpecialPower => specialPower != null && specialPower != 'none';

  /// Check if this is a face card (Jack, Queen, King)
  bool get isFaceCard => ['jack', 'queen', 'king'].contains(rank.toLowerCase());

  /// Check if this is a numbered card (2-10)
  bool get isNumberedCard {
    final rankNum = int.tryParse(rank);
    return rankNum != null && rankNum >= 2 && rankNum <= 10;
  }

  /// Check if this is an Ace
  bool get isAce => rank.toLowerCase() == 'ace';

  /// Check if this card has full data (not just an ID)
  /// Returns true if card has complete rank, suit, and points data
  /// Returns false if only cardId is present (ID-only scenario)
  bool get hasFullData {
    return cardId.isNotEmpty && 
           rank != '?' && 
           suit != '?' && 
           // Treat jokers as full data even though points == 0
           (points > 0 || rank.toLowerCase() == 'joker');
  }

  /// Get the color for this card
  Color get color {
    if (suit.toLowerCase() == 'hearts' || suit.toLowerCase() == 'diamonds') {
      return Colors.red;
    }
    return Colors.black;
  }

  /// Get the suit symbol
  String get suitSymbol {
    switch (suit.toLowerCase()) {
      case 'joker':
        return '★';
      case 'hearts':
        return '♥';
      case 'diamonds':
        return '♦';
      case 'clubs':
        return '♣';
      case 'spades':
        return '♠';
      default:
        return '?';
    }
  }

  /// Get the rank symbol
  String get rankSymbol {
    switch (rank.toLowerCase()) {
      case 'ace':
        return 'A';
      case 'jack':
        return 'J';
      case 'queen':
        return 'Q';
      case 'king':
        return 'K';
      case 'joker':
        return 'J';
      default:
        return rank;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardModel && other.cardId == cardId;
  }

  @override
  int get hashCode => cardId.hashCode;

  @override
  String toString() => 'CardModel($displayText, id: $cardId)';
}
