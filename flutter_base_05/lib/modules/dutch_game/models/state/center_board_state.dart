import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import 'card_data.dart';

/// Immutable state for CenterBoard widget
@immutable
class CenterBoardState extends ImmutableState with EquatableMixin {
  final List<CardData> discardPile;
  final int drawPileCount;
  final String playerStatus;
  final String gamePhase;
  final bool isGameActive;
  
  const CenterBoardState({
    required this.discardPile,
    required this.drawPileCount,
    required this.playerStatus,
    required this.gamePhase,
    required this.isGameActive,
  });
  
  @override
  CenterBoardState copyWith({
    List<CardData>? discardPile,
    int? drawPileCount,
    String? playerStatus,
    String? gamePhase,
    bool? isGameActive,
  }) {
    return CenterBoardState(
      discardPile: discardPile ?? this.discardPile,
      drawPileCount: drawPileCount ?? this.drawPileCount,
      playerStatus: playerStatus ?? this.playerStatus,
      gamePhase: gamePhase ?? this.gamePhase,
      isGameActive: isGameActive ?? this.isGameActive,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'drawPileCount': drawPileCount,
      'playerStatus': playerStatus,
      'gamePhase': gamePhase,
      'isGameActive': isGameActive,
    };
  }
  
  factory CenterBoardState.fromJson(Map<String, dynamic> json) {
    final discardPileRaw = json['discardPile'] as List<dynamic>? ?? [];
    final discardPile = discardPileRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    return CenterBoardState(
      discardPile: discardPile,
      drawPileCount: json['drawPileCount'] as int? ?? 0,
      playerStatus: json['playerStatus'] as String? ?? 'waiting',
      gamePhase: json['gamePhase'] as String? ?? 'waiting',
      isGameActive: json['isGameActive'] as bool? ?? false,
    );
  }
  
  @override
  List<Object?> get props => [discardPile, drawPileCount, playerStatus, gamePhase, isGameActive];
  
  @override
  String toString() => 'CenterBoardState(discard=${discardPile.length}, draw=$drawPileCount)';
}

