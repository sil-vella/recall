import 'card.dart';
import 'player.dart';
import 'game_state.dart';

/// Game event types for WebSocket communication
enum GameEventType {
  // Connection events
  gameJoined,
  gameLeft,
  playerJoined,
  playerLeft,
  
  // Game flow events
  gameStarted,
  gameEnded,
  turnChanged,
  roundChanged,
  
  // Player action events
  cardPlayed,
  cardDrawn,
  recallCalled,
  specialPowerUsed,
  
  // State update events
  gameStateUpdated,
  playerStateUpdated,
  
  // Error events
  gameError,
  playerError,
  
  // Custom events
  custom,
}

/// Base game event class
abstract class GameEvent {
  final GameEventType type;
  final String gameId;
  final String? playerId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  GameEvent({
    required this.type,
    required this.gameId,
    this.playerId,
    DateTime? timestamp,
    this.data,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert event to JSON
  Map<String, dynamic> toJson();

  /// Create event from JSON
  factory GameEvent.fromJson(Map<String, dynamic> json) {
    final eventType = GameEventType.values.firstWhere(
      (e) => e.name == json['type'],
    );

    switch (eventType) {
      case GameEventType.gameJoined:
        return GameJoinedEvent.fromJson(json);
      case GameEventType.gameLeft:
        return GameLeftEvent.fromJson(json);
      case GameEventType.playerJoined:
        return PlayerJoinedEvent.fromJson(json);
      case GameEventType.playerLeft:
        return PlayerLeftEvent.fromJson(json);
      case GameEventType.gameStarted:
        return GameStartedEvent.fromJson(json);
      case GameEventType.gameEnded:
        return GameEndedEvent.fromJson(json);
      case GameEventType.turnChanged:
        return TurnChangedEvent.fromJson(json);
      case GameEventType.roundChanged:
        return RoundChangedEvent.fromJson(json);
      case GameEventType.cardPlayed:
        return CardPlayedEvent.fromJson(json);
      case GameEventType.cardDrawn:
        return CardDrawnEvent.fromJson(json);
      case GameEventType.recallCalled:
        return RecallCalledEvent.fromJson(json);
      case GameEventType.specialPowerUsed:
        return SpecialPowerUsedEvent.fromJson(json);
      case GameEventType.gameStateUpdated:
        return GameStateUpdatedEvent.fromJson(json);
      case GameEventType.playerStateUpdated:
        return PlayerStateUpdatedEvent.fromJson(json);
      case GameEventType.gameError:
        return GameErrorEvent.fromJson(json);
      case GameEventType.playerError:
        return PlayerErrorEvent.fromJson(json);
      case GameEventType.custom:
        return CustomGameEvent.fromJson(json);
    }
  }
}

/// Game joined event
class GameJoinedEvent extends GameEvent {
  final Player player;
  final GameState gameState;

  GameJoinedEvent({
    required super.gameId,
    required this.player,
    required this.gameState,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameJoined);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'player': player.toJson(),
      'gameState': gameState.toJson(),
    };
  }

  factory GameJoinedEvent.fromJson(Map<String, dynamic> json) {
    return GameJoinedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      player: Player.fromJson(json['player']),
      gameState: GameState.fromJson(json['gameState']),
    );
  }
}

/// Game left event
class GameLeftEvent extends GameEvent {
  final String reason;

  GameLeftEvent({
    required super.gameId,
    required this.reason,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameLeft);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'reason': reason,
    };
  }

  factory GameLeftEvent.fromJson(Map<String, dynamic> json) {
    return GameLeftEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      reason: json['reason'],
    );
  }
}

/// Player joined event
class PlayerJoinedEvent extends GameEvent {
  final Player player;

  PlayerJoinedEvent({
    required super.gameId,
    required this.player,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.playerJoined);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'player': player.toJson(),
    };
  }

  factory PlayerJoinedEvent.fromJson(Map<String, dynamic> json) {
    return PlayerJoinedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      player: Player.fromJson(json['player']),
    );
  }
}

/// Player left event
class PlayerLeftEvent extends GameEvent {
  final String playerName;
  final String reason;

  PlayerLeftEvent({
    required super.gameId,
    required this.playerName,
    required this.reason,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.playerLeft);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'playerName': playerName,
      'reason': reason,
    };
  }

  factory PlayerLeftEvent.fromJson(Map<String, dynamic> json) {
    return PlayerLeftEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      playerName: json['playerName'],
      reason: json['reason'],
    );
  }
}

/// Game started event
class GameStartedEvent extends GameEvent {
  final GameState gameState;

  GameStartedEvent({
    required super.gameId,
    required this.gameState,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameStarted);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'gameState': gameState.toJson(),
    };
  }

  factory GameStartedEvent.fromJson(Map<String, dynamic> json) {
    return GameStartedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      gameState: GameState.fromJson(json['gameState']),
    );
  }
}

/// Game ended event
class GameEndedEvent extends GameEvent {
  final GameState finalGameState;
  final Player winner;

  GameEndedEvent({
    required super.gameId,
    required this.finalGameState,
    required this.winner,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameEnded);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'finalGameState': finalGameState.toJson(),
      'winner': winner.toJson(),
    };
  }

  factory GameEndedEvent.fromJson(Map<String, dynamic> json) {
    return GameEndedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      finalGameState: GameState.fromJson(json['finalGameState']),
      winner: Player.fromJson(json['winner']),
    );
  }
}

/// Turn changed event
class TurnChangedEvent extends GameEvent {
  final Player newCurrentPlayer;
  final int turnNumber;

  TurnChangedEvent({
    required super.gameId,
    required this.newCurrentPlayer,
    required this.turnNumber,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.turnChanged);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'newCurrentPlayer': newCurrentPlayer.toJson(),
      'turnNumber': turnNumber,
    };
  }

  factory TurnChangedEvent.fromJson(Map<String, dynamic> json) {
    return TurnChangedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      newCurrentPlayer: Player.fromJson(json['newCurrentPlayer']),
      turnNumber: json['turnNumber'],
    );
  }
}

/// Round changed event
class RoundChangedEvent extends GameEvent {
  final int newRoundNumber;
  final GamePhase newPhase;

  RoundChangedEvent({
    required super.gameId,
    required this.newRoundNumber,
    required this.newPhase,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.roundChanged);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'newRoundNumber': newRoundNumber,
      'newPhase': newPhase.name,
    };
  }

  factory RoundChangedEvent.fromJson(Map<String, dynamic> json) {
    return RoundChangedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      newRoundNumber: json['newRoundNumber'],
      newPhase: GamePhase.values.firstWhere((p) => p.name == json['newPhase']),
    );
  }
}

/// Card played event
class CardPlayedEvent extends GameEvent {
  final Card playedCard;
  final Player player;
  final String? targetPlayerId;
  final Card? replacedCard;

  CardPlayedEvent({
    required super.gameId,
    required this.playedCard,
    required this.player,
    this.targetPlayerId,
    this.replacedCard,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.cardPlayed);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'playedCard': playedCard.toJson(),
      'player': player.toJson(),
      'targetPlayerId': targetPlayerId,
      'replacedCard': replacedCard?.toJson(),
    };
  }

  factory CardPlayedEvent.fromJson(Map<String, dynamic> json) {
    return CardPlayedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      playedCard: Card.fromJson(json['playedCard']),
      player: Player.fromJson(json['player']),
      targetPlayerId: json['targetPlayerId'],
      replacedCard: json['replacedCard'] != null 
          ? Card.fromJson(json['replacedCard'])
          : null,
    );
  }
}

/// Card drawn event
class CardDrawnEvent extends GameEvent {
  final Card drawnCard;
  final Player player;

  CardDrawnEvent({
    required super.gameId,
    required this.drawnCard,
    required this.player,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.cardDrawn);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'drawnCard': drawnCard.toJson(),
      'player': player.toJson(),
    };
  }

  factory CardDrawnEvent.fromJson(Map<String, dynamic> json) {
    return CardDrawnEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      drawnCard: Card.fromJson(json['drawnCard']),
      player: Player.fromJson(json['player']),
    );
  }
}

/// Recall called event
class RecallCalledEvent extends GameEvent {
  final Player player;
  final GameState updatedGameState;

  RecallCalledEvent({
    required super.gameId,
    required this.player,
    required this.updatedGameState,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.recallCalled);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'player': player.toJson(),
      'updatedGameState': updatedGameState.toJson(),
    };
  }

  factory RecallCalledEvent.fromJson(Map<String, dynamic> json) {
    return RecallCalledEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      player: Player.fromJson(json['player']),
      updatedGameState: GameState.fromJson(json['updatedGameState']),
    );
  }
}

/// Special power used event
class SpecialPowerUsedEvent extends GameEvent {
  final Card card;
  final Player player;
  final String powerType;
  final Map<String, dynamic> powerData;

  SpecialPowerUsedEvent({
    required super.gameId,
    required this.card,
    required this.player,
    required this.powerType,
    required this.powerData,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.specialPowerUsed);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'card': card.toJson(),
      'player': player.toJson(),
      'powerType': powerType,
      'powerData': powerData,
    };
  }

  factory SpecialPowerUsedEvent.fromJson(Map<String, dynamic> json) {
    return SpecialPowerUsedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      card: Card.fromJson(json['card']),
      player: Player.fromJson(json['player']),
      powerType: json['powerType'],
      powerData: Map<String, dynamic>.from(json['powerData']),
    );
  }
}

/// Game state updated event
class GameStateUpdatedEvent extends GameEvent {
  final GameState gameState;

  GameStateUpdatedEvent({
    required super.gameId,
    required this.gameState,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameStateUpdated);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'gameState': gameState.toJson(),
    };
  }

  factory GameStateUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return GameStateUpdatedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      gameState: GameState.fromJson(json['gameState']),
    );
  }
}

/// Player state updated event
class PlayerStateUpdatedEvent extends GameEvent {
  final Player player;

  PlayerStateUpdatedEvent({
    required super.gameId,
    required this.player,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.playerStateUpdated);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'player': player.toJson(),
    };
  }

  factory PlayerStateUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return PlayerStateUpdatedEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      player: Player.fromJson(json['player']),
    );
  }
}

/// Game error event
class GameErrorEvent extends GameEvent {
  final String error;
  final String? errorCode;

  GameErrorEvent({
    required super.gameId,
    required this.error,
    this.errorCode,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.gameError);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'error': error,
      'errorCode': errorCode,
    };
  }

  factory GameErrorEvent.fromJson(Map<String, dynamic> json) {
    return GameErrorEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      error: json['error'],
      errorCode: json['errorCode'],
    );
  }
}

/// Player error event
class PlayerErrorEvent extends GameEvent {
  final String error;
  final String? errorCode;

  PlayerErrorEvent({
    required super.gameId,
    required this.error,
    this.errorCode,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.playerError);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'error': error,
      'errorCode': errorCode,
    };
  }

  factory PlayerErrorEvent.fromJson(Map<String, dynamic> json) {
    return PlayerErrorEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      error: json['error'],
      errorCode: json['errorCode'],
    );
  }
}

/// Custom game event
class CustomGameEvent extends GameEvent {
  final String customType;
  final Map<String, dynamic> customData;

  CustomGameEvent({
    required super.gameId,
    required this.customType,
    required this.customData,
    super.playerId,
    super.timestamp,
    super.data,
  }) : super(type: GameEventType.custom);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'gameId': gameId,
      'playerId': playerId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'customType': customType,
      'customData': customData,
    };
  }

  factory CustomGameEvent.fromJson(Map<String, dynamic> json) {
    return CustomGameEvent(
      gameId: json['gameId'],
      playerId: json['playerId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
      customType: json['customType'],
      customData: Map<String, dynamic>.from(json['customData']),
    );
  }
} 