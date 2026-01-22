import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import '../../../../core/managers/state/state_utils.dart';
import 'game_data.dart';

/// Immutable games map model
/// Contains all active games indexed by game ID
@immutable
class GamesMap extends ImmutableState with EquatableMixin {
  final Map<String, GameData> games;
  
  const GamesMap({required this.games});
  
  /// Empty games map
  const GamesMap.empty() : games = const {};
  
  @override
  GamesMap copyWith({Map<String, GameData>? games}) {
    return GamesMap(games: games ?? this.games);
  }
  
  /// Update a specific game immutably
  GamesMap updateGame(String gameId, GameData Function(GameData) updater) {
    if (!games.containsKey(gameId)) return this;
    final updatedGame = updater(games[gameId]!);
    return GamesMap(games: updateMap(games, gameId, updatedGame));
  }
  
  /// Add a new game
  GamesMap addGame(String gameId, GameData game) {
    return GamesMap(games: updateMap(games, gameId, game));
  }
  
  /// Remove a game
  GamesMap removeGame(String gameId) {
    return GamesMap(games: removeFromMap(games, gameId));
  }
  
  /// Get a game by ID
  GameData? getGame(String gameId) {
    return games[gameId];
  }
  
  /// Check if a game exists
  bool hasGame(String gameId) {
    return games.containsKey(gameId);
  }
  
  @override
  Map<String, dynamic> toJson() {
    return games.map((id, game) => MapEntry(id, game.toJson()));
  }
  
  factory GamesMap.fromJson(Map<String, dynamic> json) {
    final games = <String, GameData>{};
    json.forEach((gameId, gameJson) {
      if (gameJson is Map<String, dynamic>) {
        games[gameId] = GameData.fromJson(gameId, gameJson);
      }
    });
    return GamesMap(games: games);
  }
  
  @override
  List<Object?> get props => [games];
  
  @override
  String toString() => 'GamesMap(${games.length} games)';
}

