import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import 'game_state_data.dart';
import 'card_data.dart';

/// Immutable game data model
/// Wraps GameStateData along with metadata about the game
@immutable
class GameData extends ImmutableState with EquatableMixin {
  final String gameId;
  final String gameName;
  final GameStateData gameState;
  final CardData? myDrawnCard; // For human player
  final List<CardData> myHandCards; // For human player (with full data where known)
  final String lastUpdated;
  
  const GameData({
    required this.gameId,
    required this.gameName,
    required this.gameState,
    this.myDrawnCard,
    required this.myHandCards,
    required this.lastUpdated,
  });
  
  @override
  GameData copyWith({
    String? gameId,
    String? gameName,
    GameStateData? gameState,
    CardData? myDrawnCard,
    List<CardData>? myHandCards,
    String? lastUpdated,
  }) {
    return GameData(
      gameId: gameId ?? this.gameId,
      gameName: gameName ?? this.gameName,
      gameState: gameState ?? this.gameState,
      myDrawnCard: myDrawnCard ?? this.myDrawnCard,
      myHandCards: myHandCards ?? this.myHandCards,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
  
  /// Update game state using a function
  GameData updateGameState(GameStateData Function(GameStateData) updater) {
    return copyWith(gameState: updater(gameState));
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'gameName': gameName,
      'gameData': {
        'game_state': gameState.toJson(),
      },
      if (myDrawnCard != null) 'myDrawnCard': myDrawnCard!.toJson(),
      'myHandCards': myHandCards.map((c) => c.toJson()).toList(),
      'lastUpdated': lastUpdated,
    };
  }
  
  factory GameData.fromJson(String gameId, Map<String, dynamic> json) {
    final gameDataInner = json['gameData'] as Map<String, dynamic>? ?? json;
    final gameStateJson = gameDataInner['game_state'] as Map<String, dynamic>? ?? {};
    
    final myDrawnCardJson = json['myDrawnCard'] as Map<String, dynamic>?;
    final myDrawnCard = myDrawnCardJson != null ? CardData.fromJson(myDrawnCardJson) : null;
    
    final myHandCardsRaw = json['myHandCards'] as List<dynamic>? ?? [];
    final myHandCards = myHandCardsRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    return GameData(
      gameId: gameId,
      gameName: json['gameName'] as String? ?? 'Game $gameId',
      gameState: GameStateData.fromJson(gameStateJson),
      myDrawnCard: myDrawnCard,
      myHandCards: myHandCards,
      lastUpdated: json['lastUpdated'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
  
  @override
  List<Object?> get props => [gameId, gameName, gameState, myDrawnCard, myHandCards, lastUpdated];
  
  @override
  String toString() => 'GameData($gameId: $gameName)';
}

