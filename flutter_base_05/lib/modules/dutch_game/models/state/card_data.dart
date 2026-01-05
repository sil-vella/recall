import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';

/// Immutable card data model
@immutable
class CardData extends ImmutableState with EquatableMixin {
  final String cardId;
  final String suit;
  final String rank;
  final int points;
  final String? specialPower;
  
  const CardData({
    required this.cardId,
    required this.suit,
    required this.rank,
    required this.points,
    this.specialPower,
  });
  
  /// Create a card with hidden data (face-down card)
  factory CardData.hidden(String cardId) {
    return CardData(
      cardId: cardId,
      suit: '?',
      rank: '?',
      points: 0,
    );
  }
  
  /// Check if this card is face-down (hidden)
  bool get isHidden => suit == '?' && rank == '?';
  
  /// Check if this card has full data (face-up)
  bool get isFaceUp => !isHidden;
  
  @override
  CardData copyWith({
    String? cardId,
    String? suit,
    String? rank,
    int? points,
    String? specialPower,
  }) {
    return CardData(
      cardId: cardId ?? this.cardId,
      suit: suit ?? this.suit,
      rank: rank ?? this.rank,
      points: points ?? this.points,
      specialPower: specialPower ?? this.specialPower,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'cardId': cardId,
      'suit': suit,
      'rank': rank,
      'points': points,
      if (specialPower != null) 'specialPower': specialPower,
    };
  }
  
  factory CardData.fromJson(Map<String, dynamic> json) {
    return CardData(
      cardId: json['cardId'] as String? ?? json['id'] as String? ?? '',
      suit: json['suit'] as String? ?? '?',
      rank: json['rank'] as String? ?? '?',
      points: json['points'] as int? ?? 0,
      specialPower: json['specialPower'] as String?,
    );
  }
  
  @override
  List<Object?> get props => [cardId, suit, rank, points, specialPower];
  
  @override
  String toString() => 'CardData($cardId: $rank of $suit, $points pts)';
}

