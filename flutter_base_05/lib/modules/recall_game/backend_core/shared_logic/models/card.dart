import '../../../utils/platform/shared_imports.dart';

/// Card model for Recall Game
/// 
/// Represents a single playing card with all necessary properties
/// for the Recall game mechanics.

class Card {
  final String cardId;
  final String rank;
  final String suit;
  final int points;
  final String? specialPower;

  const Card({
    required this.cardId,
    required this.rank,
    required this.suit,
    required this.points,
    this.specialPower,
  });

  /// Create a copy of this card with updated properties
  Card copyWith({
    String? cardId,
    String? rank,
    String? suit,
    int? points,
    String? specialPower,
  }) {
    return Card(
      cardId: cardId ?? this.cardId,
      rank: rank ?? this.rank,
      suit: suit ?? this.suit,
      points: points ?? this.points,
      specialPower: specialPower ?? this.specialPower,
    );
  }

  /// Convert card to Map for JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'cardId': cardId,
      'rank': rank,
      'suit': suit,
      'points': points,
      'specialPower': specialPower,
    };
  }

  /// Create card from Map (JSON deserialization)
  factory Card.fromMap(Map<String, dynamic> map) {
    return Card(
      cardId: map['cardId'] ?? '',
      rank: map['rank'] ?? '',
      suit: map['suit'] ?? '',
      points: map['points'] ?? 0,
      specialPower: map['specialPower'],
    );
  }

  /// Check if this is a special card (Queen or Jack)
  bool get isSpecialCard => specialPower != null;

  /// Check if this is a Queen (peek power)
  bool get isQueen => rank == 'queen';

  /// Check if this is a Jack (swap power)
  bool get isJack => rank == 'jack';

  /// Check if this is a Joker (0 points)
  bool get isJoker => rank == 'joker';

  /// Check if this is a King
  bool get isKing => rank == 'king';

  /// Check if this is an Ace
  bool get isAce => rank == 'ace';

  /// Get display name for the card
  String get displayName {
    if (isJoker) return 'Joker';
    return '${_capitalize(rank)} of ${_capitalize(suit)}';
  }

  /// Get short display name (e.g., "Q♠", "A♥")
  String get shortDisplayName {
    if (isJoker) return '🃏';
    
    String rankSymbol = _getRankSymbol(rank);
    String suitSymbol = _getSuitSymbol(suit);
    
    return '$rankSymbol$suitSymbol';
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _getRankSymbol(String rank) {
    switch (rank) {
      case 'ace': return 'A';
      case 'jack': return 'J';
      case 'queen': return 'Q';
      case 'king': return 'K';
      default: return rank;
    }
  }

  String _getSuitSymbol(String suit) {
    switch (suit) {
      case 'hearts': return '♥';
      case 'diamonds': return '♦';
      case 'clubs': return '♣';
      case 'spades': return '♠';
      default: return suit;
    }
  }

  @override
  String toString() => displayName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Card && other.cardId == cardId;
  }

  @override
  int get hashCode => cardId.hashCode;
}
