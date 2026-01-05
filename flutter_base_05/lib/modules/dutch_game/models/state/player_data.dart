import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import '../../../../core/managers/state/state_utils.dart';
import 'card_data.dart';

/// Immutable player data model
@immutable
class PlayerData extends ImmutableState with EquatableMixin {
  final String id;
  final String name;
  final bool isHuman;
  final bool isActive;
  final String status;
  final List<CardData> hand;
  final CardData? drawnCard;
  final Map<String, Map<String, CardData>> knownCards; // playerId -> cardId -> CardData
  final String? collectionRank;
  final List<CardData> collectionRankCards;
  final int totalPoints;
  final String? difficulty; // For computer players
  
  const PlayerData({
    required this.id,
    required this.name,
    required this.isHuman,
    required this.isActive,
    required this.status,
    required this.hand,
    this.drawnCard,
    required this.knownCards,
    this.collectionRank,
    required this.collectionRankCards,
    required this.totalPoints,
    this.difficulty,
  });
  
  @override
  PlayerData copyWith({
    String? id,
    String? name,
    bool? isHuman,
    bool? isActive,
    String? status,
    List<CardData>? hand,
    CardData? drawnCard,
    Map<String, Map<String, CardData>>? knownCards,
    String? collectionRank,
    List<CardData>? collectionRankCards,
    int? totalPoints,
    String? difficulty,
  }) {
    return PlayerData(
      id: id ?? this.id,
      name: name ?? this.name,
      isHuman: isHuman ?? this.isHuman,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      hand: hand ?? this.hand,
      drawnCard: drawnCard ?? this.drawnCard,
      knownCards: knownCards ?? this.knownCards,
      collectionRank: collectionRank ?? this.collectionRank,
      collectionRankCards: collectionRankCards ?? this.collectionRankCards,
      totalPoints: totalPoints ?? this.totalPoints,
      difficulty: difficulty ?? this.difficulty,
    );
  }
  
  /// Update card in hand at specific index
  PlayerData updateHandCard(int index, CardData card) {
    return copyWith(hand: updateList(hand, index, card));
  }
  
  /// Add card to hand
  PlayerData addCardToHand(CardData card) {
    return copyWith(hand: addToList(hand, card));
  }
  
  /// Remove card from hand at index
  PlayerData removeCardFromHand(int index) {
    return copyWith(hand: removeFromList(hand, index));
  }
  
  /// Update known cards for a specific player and card
  PlayerData updateKnownCard(String playerId, String cardId, CardData card) {
    final updatedKnown = Map<String, Map<String, CardData>>.from(knownCards);
    if (!updatedKnown.containsKey(playerId)) {
      updatedKnown[playerId] = {};
    }
    updatedKnown[playerId] = {...updatedKnown[playerId]!, cardId: card};
    return copyWith(knownCards: updatedKnown);
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isHuman': isHuman,
      'isActive': isActive,
      'status': status,
      'hand': hand.map((c) => c.toJson()).toList(),
      if (drawnCard != null) 'drawnCard': drawnCard!.toJson(),
      'known_cards': knownCards.map((pid, cards) => 
        MapEntry(pid, cards.map((cid, card) => MapEntry(cid, card.toJson())))
      ),
      if (collectionRank != null) 'collection_rank': collectionRank,
      'collection_rank_cards': collectionRankCards.map((c) => c.toJson()).toList(),
      'totalPoints': totalPoints,
      if (difficulty != null) 'difficulty': difficulty,
    };
  }
  
  factory PlayerData.fromJson(Map<String, dynamic> json) {
    // Parse hand
    final handRaw = json['hand'] as List<dynamic>? ?? [];
    final hand = handRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    // Parse drawnCard
    final drawnCardJson = json['drawnCard'] as Map<String, dynamic>?;
    final drawnCard = drawnCardJson != null ? CardData.fromJson(drawnCardJson) : null;
    
    // Parse known_cards
    final knownCardsRaw = json['known_cards'] as Map<String, dynamic>? ?? {};
    final knownCards = <String, Map<String, CardData>>{};
    knownCardsRaw.forEach((pid, cardsMap) {
      if (cardsMap is Map) {
        knownCards[pid] = <String, CardData>{};
        (cardsMap as Map<String, dynamic>).forEach((cid, cardJson) {
          if (cardJson is Map) {
            knownCards[pid]![cid] = CardData.fromJson(cardJson as Map<String, dynamic>);
          }
        });
      }
    });
    
    // Parse collection_rank_cards
    final collectionRankCardsRaw = json['collection_rank_cards'] as List<dynamic>? ?? [];
    final collectionRankCards = collectionRankCardsRaw
        .map((c) => CardData.fromJson(c as Map<String, dynamic>))
        .toList();
    
    return PlayerData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isHuman: json['isHuman'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      status: json['status'] as String? ?? 'waiting',
      hand: hand,
      drawnCard: drawnCard,
      knownCards: knownCards,
      collectionRank: json['collection_rank'] as String?,
      collectionRankCards: collectionRankCards,
      totalPoints: json['totalPoints'] as int? ?? 0,
      difficulty: json['difficulty'] as String?,
    );
  }
  
  @override
  List<Object?> get props => [
    id, name, isHuman, isActive, status, hand, drawnCard,
    knownCards, collectionRank, collectionRankCards, totalPoints, difficulty
  ];
  
  @override
  String toString() => 'PlayerData($id: $name, status=$status, cards=${hand.length})';
}

