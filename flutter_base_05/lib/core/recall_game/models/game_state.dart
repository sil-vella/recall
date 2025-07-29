import 'card.dart';
import 'player.dart';

/// Game phase enumeration
enum GamePhase {
  waiting,      // Waiting for players to join
  setup,        // Game setup, dealing cards
  playing,      // Active gameplay
  recall,       // Recall phase (final round)
  finished,     // Game finished, showing results
}

/// Game status enumeration
enum GameStatus {
  active,       // Game is active and playable
  paused,       // Game is paused
  ended,        // Game has ended
  error,        // Game encountered an error
}

/// Game state model representing the current state of a Recall game
class GameState {
  final String gameId;
  final String gameName;
  final List<Player> players;
  final Player? currentPlayer;
  final GamePhase phase;
  final GameStatus status;
  final List<Card> drawPile;
  final List<Card> discardPile;
  final List<Card> centerPile;
  final int turnNumber;
  final int roundNumber;
  final DateTime? gameStartTime;
  final DateTime? lastActivityTime;
  final Map<String, dynamic> gameSettings;
  final Map<String, dynamic>? winner;
  final String? errorMessage;

  const GameState({
    required this.gameId,
    required this.gameName,
    this.players = const [],
    this.currentPlayer,
    this.phase = GamePhase.waiting,
    this.status = GameStatus.active,
    this.drawPile = const [],
    this.discardPile = const [],
    this.centerPile = const [],
    this.turnNumber = 0,
    this.roundNumber = 1,
    this.gameStartTime,
    this.lastActivityTime,
    this.gameSettings = const {},
    this.winner,
    this.errorMessage,
  });

  /// Get current player ID
  String? get currentPlayerId => currentPlayer?.id;

  /// Get number of players
  int get playerCount => players.length;

  /// Get active players (not disconnected)
  List<Player> get activePlayers => players.where((p) => p.isActive).toList();

  /// Get human players
  List<Player> get humanPlayers => players.where((p) => p.isHuman).toList();

  /// Get computer players
  List<Player> get computerPlayers => players.where((p) => p.isComputer).toList();

  /// Get player by ID
  Player? getPlayerById(String playerId) {
    try {
      return players.firstWhere((p) => p.id == playerId);
    } catch (e) {
      return null;
    }
  }

  /// Get current player index
  int get currentPlayerIndex {
    if (currentPlayer == null) return -1;
    return players.indexWhere((p) => p.id == currentPlayer!.id);
  }

  /// Get next player
  Player? get nextPlayer {
    if (players.isEmpty) return null;
    final currentIndex = currentPlayerIndex;
    if (currentIndex == -1) return players.first;
    
    final nextIndex = (currentIndex + 1) % players.length;
    return players[nextIndex];
  }

  /// Check if game is active
  bool get isActive => status == GameStatus.active;

  /// Check if game is finished
  bool get isFinished => phase == GamePhase.finished;

  /// Check if game is in recall phase
  bool get isInRecallPhase => phase == GamePhase.recall;

  /// Check if it's a specific player's turn
  bool isPlayerTurn(String playerId) {
    return currentPlayer?.id == playerId;
  }

  /// Get player's hand
  List<Card> getPlayerHand(String playerId) {
    final player = getPlayerById(playerId);
    return player?.hand ?? [];
  }

  /// Get player's visible cards
  List<Card> getPlayerVisibleCards(String playerId) {
    final player = getPlayerById(playerId);
    return player?.visibleCards ?? [];
  }

  /// Get player's total score
  int getPlayerScore(String playerId) {
    final player = getPlayerById(playerId);
    return player?.totalScore ?? 0;
  }

  /// Check if player can call recall
  bool canPlayerCallRecall(String playerId) {
    final player = getPlayerById(playerId);
    return player?.canCallRecall ?? false;
  }

  /// Get game duration
  Duration? get gameDuration {
    if (gameStartTime == null) return null;
    final endTime = lastActivityTime ?? DateTime.now();
    return endTime.difference(gameStartTime!);
  }

  /// Get formatted game duration
  String get formattedGameDuration {
    final duration = gameDuration;
    if (duration == null) return 'N/A';
    
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  /// Create a copy with updated properties
  GameState copyWith({
    String? gameId,
    String? gameName,
    List<Player>? players,
    Player? currentPlayer,
    GamePhase? phase,
    GameStatus? status,
    List<Card>? drawPile,
    List<Card>? discardPile,
    List<Card>? centerPile,
    int? turnNumber,
    int? roundNumber,
    DateTime? gameStartTime,
    DateTime? lastActivityTime,
    Map<String, dynamic>? gameSettings,
    Map<String, dynamic>? winner,
    String? errorMessage,
  }) {
    return GameState(
      gameId: gameId ?? this.gameId,
      gameName: gameName ?? this.gameName,
      players: players ?? this.players,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      phase: phase ?? this.phase,
      status: status ?? this.status,
      drawPile: drawPile ?? this.drawPile,
      discardPile: discardPile ?? this.discardPile,
      centerPile: centerPile ?? this.centerPile,
      turnNumber: turnNumber ?? this.turnNumber,
      roundNumber: roundNumber ?? this.roundNumber,
      gameStartTime: gameStartTime ?? this.gameStartTime,
      lastActivityTime: lastActivityTime ?? this.lastActivityTime,
      gameSettings: gameSettings ?? this.gameSettings,
      winner: winner ?? this.winner,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Convert game state to JSON
  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'gameName': gameName,
      'players': players.map((p) => p.toJson()).toList(),
      'currentPlayer': currentPlayer?.toJson(),
      'phase': phase.name,
      'status': status.name,
      'drawPile': drawPile.map((c) => c.toJson()).toList(),
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'centerPile': centerPile.map((c) => c.toJson()).toList(),
      'turnNumber': turnNumber,
      'roundNumber': roundNumber,
      'gameStartTime': gameStartTime?.toIso8601String(),
      'lastActivityTime': lastActivityTime?.toIso8601String(),
      'gameSettings': gameSettings,
      'winner': winner,
      'errorMessage': errorMessage,
      'playerCount': playerCount,
      'activePlayerCount': activePlayers.length,
      'gameDuration': formattedGameDuration,
    };
  }

  /// Create game state from JSON
  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      gameId: json['gameId'],
      gameName: json['gameName'],
      players: (json['players'] as List?)
          ?.map((playerJson) => Player.fromJson(playerJson))
          .toList() ?? [],
      currentPlayer: json['currentPlayer'] != null 
          ? Player.fromJson(json['currentPlayer'])
          : null,
      phase: GamePhase.values.firstWhere((p) => p.name == json['phase']),
      status: GameStatus.values.firstWhere((s) => s.name == json['status']),
      drawPile: (json['drawPile'] as List?)
          ?.map((cardJson) => Card.fromJson(cardJson))
          .toList() ?? [],
      discardPile: (json['discardPile'] as List?)
          ?.map((cardJson) => Card.fromJson(cardJson))
          .toList() ?? [],
      centerPile: (json['centerPile'] as List?)
          ?.map((cardJson) => Card.fromJson(cardJson))
          .toList() ?? [],
      turnNumber: json['turnNumber'] ?? 0,
      roundNumber: json['roundNumber'] ?? 1,
      gameStartTime: json['gameStartTime'] != null 
          ? DateTime.parse(json['gameStartTime'])
          : null,
      lastActivityTime: json['lastActivityTime'] != null 
          ? DateTime.parse(json['lastActivityTime'])
          : null,
      gameSettings: Map<String, dynamic>.from(json['gameSettings'] ?? {}),
      winner: json['winner'] != null 
          ? Map<String, dynamic>.from(json['winner'])
          : null,
      errorMessage: json['errorMessage'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameState && other.gameId == gameId;
  }

  @override
  int get hashCode => gameId.hashCode;

  @override
  String toString() {
    return 'GameState($gameName, phase: $phase, players: $playerCount, turn: $turnNumber)';
  }
}

/// Game state manager for managing game state updates
class GameStateManager {
  GameState? _currentGameState;
  final List<Function(GameState)> _stateListeners = [];

  /// Get current game state
  GameState? get currentGameState => _currentGameState;

  /// Check if there's an active game
  bool get hasActiveGame => _currentGameState != null && _currentGameState!.isActive;

  /// Update game state
  void updateGameState(GameState newState) {
    _currentGameState = newState;
    _notifyListeners();
  }

  /// Update specific game state properties
  void updateGameStateProperties({
    List<Player>? players,
    Player? currentPlayer,
    GamePhase? phase,
    GameStatus? status,
    List<Card>? drawPile,
    List<Card>? discardPile,
    List<Card>? centerPile,
    int? turnNumber,
    int? roundNumber,
    Map<String, dynamic>? winner,
    String? errorMessage,
  }) {
    if (_currentGameState == null) return;

    _currentGameState = _currentGameState!.copyWith(
      players: players,
      currentPlayer: currentPlayer,
      phase: phase,
      status: status,
      drawPile: drawPile,
      discardPile: discardPile,
      centerPile: centerPile,
      turnNumber: turnNumber,
      roundNumber: roundNumber,
      lastActivityTime: DateTime.now(),
      winner: winner,
      errorMessage: errorMessage,
    );

    _notifyListeners();
  }

  /// Add state listener
  void addStateListener(Function(GameState) listener) {
    _stateListeners.add(listener);
  }

  /// Remove state listener
  void removeStateListener(Function(GameState) listener) {
    _stateListeners.remove(listener);
  }

  /// Clear all state listeners
  void clearStateListeners() {
    _stateListeners.clear();
  }

  /// Notify all listeners of state change
  void _notifyListeners() {
    if (_currentGameState != null) {
      for (final listener in _stateListeners) {
        listener(_currentGameState!);
      }
    }
  }

  /// Clear current game state
  void clearGameState() {
    _currentGameState = null;
    _notifyListeners();
  }

  /// Get game state as JSON
  Map<String, dynamic>? getGameStateJson() {
    return _currentGameState?.toJson();
  }
} 