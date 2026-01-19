import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import '../../../../core/managers/state/state_utils.dart';
import 'card_data.dart';
import 'player_data.dart';

/// Immutable game state data model
/// This represents the core game state (players, piles, current player, etc.)
@immutable
class GameStateData extends ImmutableState with EquatableMixin {
  final List<PlayerData> players;
  final PlayerData? currentPlayer;
  final List<CardData> discardPile;
  final List<CardData> drawPile;
  final String phase;
  final String? dutchCalledBy;
  final CardData? lastPlayedCard;
  final List<Map<String, dynamic>> winners; // Game end winners
  
  const GameStateData({
    required this.players,
    this.currentPlayer,
    required this.discardPile,
    required this.drawPile,
    required this.phase,
    this.dutchCalledBy,
    this.lastPlayedCard,
    required this.winners,
  });
  
  @override
  GameStateData copyWith({
    List<PlayerData>? players,
    PlayerData? currentPlayer,
    List<CardData>? discardPile,
    List<CardData>? drawPile,
    String? phase,
    String? dutchCalledBy,
    CardData? lastPlayedCard,
    List<Map<String, dynamic>>? winners,
  }) {
    return GameStateData(
      players: players ?? this.players,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      discardPile: discardPile ?? this.discardPile,
      drawPile: drawPile ?? this.drawPile,
      phase: phase ?? this.phase,
      dutchCalledBy: dutchCalledBy ?? this.dutchCalledBy,
      lastPlayedCard: lastPlayedCard ?? this.lastPlayedCard,
      winners: winners ?? this.winners,
    );
  }
  
  /// Update a specific player's status immutably
  GameStateData updatePlayerStatus(String playerId, String status) {
    final updatedPlayers = players.map((p) =>
      p.id == playerId ? p.copyWith(status: status) : p
    ).toList();
    
    final updatedCurrentPlayer = currentPlayer?.id == playerId
        ? currentPlayer!.copyWith(status: status)
        : currentPlayer;
    
    return copyWith(
      players: updatedPlayers,
      currentPlayer: updatedCurrentPlayer,
    );
  }
  
  /// Update a specific player immutably
  GameStateData updatePlayer(String playerId, PlayerData Function(PlayerData) updater) {
    final playerIndex = players.indexWhere((p) => p.id == playerId);
    if (playerIndex == -1) return this;
    
    final updatedPlayer = updater(players[playerIndex]);
    final updatedPlayers = updateList(players, playerIndex, updatedPlayer);
    
    final updatedCurrentPlayer = currentPlayer?.id == playerId
        ? updatedPlayer
        : currentPlayer;
    
    return copyWith(
      players: updatedPlayers,
      currentPlayer: updatedCurrentPlayer,
    );
  }
  
  /// Find a player by ID
  PlayerData? findPlayer(String playerId) {
    try {
      return players.firstWhere((p) => p.id == playerId);
    } catch (e) {
      return null;
    }
  }
  
  /// Add card to discard pile
  GameStateData addToDiscardPile(CardData card) {
    return copyWith(
      discardPile: addToList(discardPile, card),
      lastPlayedCard: card,
    );
  }
  
  /// Remove card from draw pile
  GameStateData removeFromDrawPile() {
    if (drawPile.isEmpty) return this;
    return copyWith(drawPile: drawPile.sublist(0, drawPile.length - 1));
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'players': players.map((p) => p.toJson()).toList(),
      if (currentPlayer != null) 'currentPlayer': currentPlayer!.toJson(),
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'drawPile': drawPile.map((c) => c.toJson()).toList(),
      'phase': phase,
      if (dutchCalledBy != null) 'dutchCalledBy': dutchCalledBy,
      if (lastPlayedCard != null) 'lastPlayedCard': lastPlayedCard!.toJson(),
      'winners': winners,
    };
  }
  
  factory GameStateData.fromJson(Map<String, dynamic> json) {
    final playersRaw = json['players'] as List<dynamic>? ?? [];
    final players = playersRaw.map((p) => PlayerData.fromJson(p as Map<String, dynamic>)).toList();
    
    final currentPlayerJson = json['currentPlayer'] as Map<String, dynamic>?;
    final currentPlayer = currentPlayerJson != null ? PlayerData.fromJson(currentPlayerJson) : null;
    
    final discardPileRaw = json['discardPile'] as List<dynamic>? ?? [];
    final discardPile = discardPileRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    final drawPileRaw = json['drawPile'] as List<dynamic>? ?? [];
    final drawPile = drawPileRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    final lastPlayedCardJson = json['lastPlayedCard'] as Map<String, dynamic>?;
    final lastPlayedCard = lastPlayedCardJson != null ? CardData.fromJson(lastPlayedCardJson) : null;
    
    final winnersRaw = json['winners'] as List<dynamic>? ?? [];
    final winners = winnersRaw.map((w) => w as Map<String, dynamic>).toList();
    
    return GameStateData(
      players: players,
      currentPlayer: currentPlayer,
      discardPile: discardPile,
      drawPile: drawPile,
      phase: json['phase'] as String? ?? 'waiting',
      dutchCalledBy: json['dutchCalledBy'] as String?,
      lastPlayedCard: lastPlayedCard,
      winners: winners,
    );
  }
  
  @override
  List<Object?> get props => [
    players, currentPlayer, discardPile, drawPile, phase,
    dutchCalledBy, lastPlayedCard, winners
  ];
  
  @override
  String toString() => 'GameStateData(players=${players.length}, phase=$phase)';
}

