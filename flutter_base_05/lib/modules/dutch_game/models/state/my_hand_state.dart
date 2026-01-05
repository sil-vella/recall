import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import '../../../../core/managers/state/state_utils.dart';
import 'card_data.dart';

/// Immutable state for MyHand widget
@immutable
class MyHandState extends ImmutableState with EquatableMixin {
  final List<CardData> cards;
  final String playerStatus;
  final CardData? drawnCard;
  final bool isMyTurn;
  final int? selectedCardIndex;
  
  const MyHandState({
    required this.cards,
    required this.playerStatus,
    this.drawnCard,
    required this.isMyTurn,
    this.selectedCardIndex,
  });
  
  @override
  MyHandState copyWith({
    List<CardData>? cards,
    String? playerStatus,
    CardData? drawnCard,
    bool? isMyTurn,
    int? selectedCardIndex,
  }) {
    return MyHandState(
      cards: cards ?? this.cards,
      playerStatus: playerStatus ?? this.playerStatus,
      drawnCard: drawnCard ?? this.drawnCard,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      selectedCardIndex: selectedCardIndex ?? this.selectedCardIndex,
    );
  }
  
  /// Update a card in hand
  MyHandState updateCard(int index, CardData card) {
    return copyWith(cards: updateList(cards, index, card));
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'cards': cards.map((c) => c.toJson()).toList(),
      'playerStatus': playerStatus,
      if (drawnCard != null) 'drawnCard': drawnCard!.toJson(),
      'isMyTurn': isMyTurn,
      if (selectedCardIndex != null) 'selectedCardIndex': selectedCardIndex,
    };
  }
  
  factory MyHandState.fromJson(Map<String, dynamic> json) {
    final cardsRaw = json['cards'] as List<dynamic>? ?? [];
    final cards = cardsRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    final drawnCardJson = json['drawnCard'] as Map<String, dynamic>?;
    final drawnCard = drawnCardJson != null ? CardData.fromJson(drawnCardJson) : null;
    
    return MyHandState(
      cards: cards,
      playerStatus: json['playerStatus'] as String? ?? 'waiting',
      drawnCard: drawnCard,
      isMyTurn: json['isMyTurn'] as bool? ?? false,
      selectedCardIndex: json['selectedCardIndex'] as int?,
    );
  }
  
  @override
  List<Object?> get props => [cards, playerStatus, drawnCard, isMyTurn, selectedCardIndex];
  
  @override
  String toString() => 'MyHandState(${cards.length} cards, status=$playerStatus)';
}

