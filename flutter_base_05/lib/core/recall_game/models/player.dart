import 'card.dart';

/// Player type enumeration
enum PlayerType {
  human,
  computer,
}

/// Player status enumeration
enum PlayerStatus {
  waiting,    // Waiting for game to start
  ready,      // Ready to play
  playing,    // Currently playing
  finished,   // Game finished
  disconnected, // Disconnected from game
}

/// Base player model
class Player {
  final String id;
  final String name;
  final PlayerType type;
  final List<Card> hand;
  final List<Card> visibleCards;
  final int score;
  final PlayerStatus status;
  final bool isCurrentPlayer;
  final bool hasCalledRecall;
  final DateTime? lastActivity;

  const Player({
    required this.id,
    required this.name,
    required this.type,
    this.hand = const [],
    this.visibleCards = const [],
    this.score = 0,
    this.status = PlayerStatus.waiting,
    this.isCurrentPlayer = false,
    this.hasCalledRecall = false,
    this.lastActivity,
  });

  /// Get total points from hand
  int get handPoints {
    return hand.fold(0, (sum, card) => sum + card.points);
  }

  /// Get total points from visible cards
  int get visiblePoints {
    return visibleCards.fold(0, (sum, card) => sum + card.points);
  }

  /// Get total score (hand + visible)
  int get totalScore => handPoints + visiblePoints;

  /// Get number of cards in hand
  int get handSize => hand.length;

  /// Get number of visible cards
  int get visibleSize => visibleCards.length;

  /// Check if player is human
  bool get isHuman => type == PlayerType.human;

  /// Check if player is computer
  bool get isComputer => type == PlayerType.computer;

  /// Check if player is active (not disconnected)
  bool get isActive => status != PlayerStatus.disconnected;

  /// Check if player can call recall
  bool get canCallRecall => !hasCalledRecall && isActive;

  /// Create a copy with updated properties
  Player copyWith({
    String? id,
    String? name,
    PlayerType? type,
    List<Card>? hand,
    List<Card>? visibleCards,
    int? score,
    PlayerStatus? status,
    bool? isCurrentPlayer,
    bool? hasCalledRecall,
    DateTime? lastActivity,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      hand: hand ?? this.hand,
      visibleCards: visibleCards ?? this.visibleCards,
      score: score ?? this.score,
      status: status ?? this.status,
      isCurrentPlayer: isCurrentPlayer ?? this.isCurrentPlayer,
      hasCalledRecall: hasCalledRecall ?? this.hasCalledRecall,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  /// Convert player to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'hand': hand.map((card) => card.toJson()).toList(),
      'visibleCards': visibleCards.map((card) => card.toJson()).toList(),
      'score': score,
      'status': status.name,
      'isCurrentPlayer': isCurrentPlayer,
      'hasCalledRecall': hasCalledRecall,
      'lastActivity': lastActivity?.toIso8601String(),
      'handPoints': handPoints,
      'visiblePoints': visiblePoints,
      'totalScore': totalScore,
      'handSize': handSize,
      'visibleSize': visibleSize,
    };
  }

  /// Create player from JSON
  factory Player.fromJson(Map<String, dynamic> json) {
    try {
      // Parse type with error handling
      PlayerType type;
      try {
        final typeStr = json['type'] as String? ?? 'human';
        type = PlayerType.values.firstWhere((t) => t.name == typeStr);
      } catch (e) {
        print('⚠️ Failed to parse player type: ${json['type']}, available: ${PlayerType.values.map((t) => t.name).join(', ')}');
        type = PlayerType.human; // fallback
      }

      // Parse status with error handling
      PlayerStatus status;
      try {
        final statusStr = json['status'] as String? ?? 'waiting';
        status = PlayerStatus.values.firstWhere((s) => s.name == statusStr);
      } catch (e) {
        print('⚠️ Failed to parse player status: ${json['status']}, available: ${PlayerStatus.values.map((s) => s.name).join(', ')}');
        status = PlayerStatus.waiting; // fallback
      }

      return Player(
        id: json['id'] ?? 'unknown',
        name: json['name'] ?? 'Unknown Player',
        type: type,
        hand: (json['hand'] as List?)
            ?.map((cardJson) => Card.fromJson(cardJson))
            .toList() ?? [],
        visibleCards: (json['visibleCards'] as List?)
            ?.map((cardJson) => Card.fromJson(cardJson))
            .toList() ?? [],
        score: json['score'] ?? 0,
        status: status,
        isCurrentPlayer: json['isCurrentPlayer'] ?? false,
        hasCalledRecall: json['hasCalledRecall'] ?? false,
        lastActivity: json['lastActivity'] != null 
            ? DateTime.parse(json['lastActivity'])
            : null,
      );
    } catch (e) {
      print('❌ Error parsing Player from JSON: $e');
      print('❌ JSON data: $json');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Player && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Player($name, type: $type, score: $totalScore, status: $status)';
  }
}

/// Human player model
class HumanPlayer extends Player {
  const HumanPlayer({
    required super.id,
    required super.name,
    super.hand = const [],
    super.visibleCards = const [],
    super.score = 0,
    super.status = PlayerStatus.waiting,
    super.isCurrentPlayer = false,
    super.hasCalledRecall = false,
    super.lastActivity,
  }) : super(type: PlayerType.human);

  /// Create human player from base player
  factory HumanPlayer.fromPlayer(Player player) {
    return HumanPlayer(
      id: player.id,
      name: player.name,
      hand: player.hand,
      visibleCards: player.visibleCards,
      score: player.score,
      status: player.status,
      isCurrentPlayer: player.isCurrentPlayer,
      hasCalledRecall: player.hasCalledRecall,
      lastActivity: player.lastActivity,
    );
  }

  @override
  HumanPlayer copyWith({
    String? id,
    String? name,
    PlayerType? type,
    List<Card>? hand,
    List<Card>? visibleCards,
    int? score,
    PlayerStatus? status,
    bool? isCurrentPlayer,
    bool? hasCalledRecall,
    DateTime? lastActivity,
  }) {
    return HumanPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      hand: hand ?? this.hand,
      visibleCards: visibleCards ?? this.visibleCards,
      score: score ?? this.score,
      status: status ?? this.status,
      isCurrentPlayer: isCurrentPlayer ?? this.isCurrentPlayer,
      hasCalledRecall: hasCalledRecall ?? this.hasCalledRecall,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}

/// Computer player model with AI capabilities
class ComputerPlayer extends Player {
  final String aiDifficulty; // 'easy', 'medium', 'hard'
  final Map<String, dynamic> aiPreferences;

  const ComputerPlayer({
    required super.id,
    required super.name,
    this.aiDifficulty = 'medium',
    this.aiPreferences = const {},
    super.hand = const [],
    super.visibleCards = const [],
    super.score = 0,
    super.status = PlayerStatus.waiting,
    super.isCurrentPlayer = false,
    super.hasCalledRecall = false,
    super.lastActivity,
  }) : super(type: PlayerType.computer);

  /// Create computer player from base player
  factory ComputerPlayer.fromPlayer(Player player, {
    String aiDifficulty = 'medium',
    Map<String, dynamic> aiPreferences = const {},
  }) {
    return ComputerPlayer(
      id: player.id,
      name: player.name,
      aiDifficulty: aiDifficulty,
      aiPreferences: aiPreferences,
      hand: player.hand,
      visibleCards: player.visibleCards,
      score: player.score,
      status: player.status,
      isCurrentPlayer: player.isCurrentPlayer,
      hasCalledRecall: player.hasCalledRecall,
      lastActivity: player.lastActivity,
    );
  }

  /// Get AI decision based on current game state
  Map<String, dynamic> getAIDecision({
    required List<Card> playableCards,
    required List<Player> otherPlayers,
    required bool canCallRecall,
    required int gamePhase,
  }) {
    // This will be implemented by the AI service
    return {
      'action': 'play_card',
      'cardIndex': 0,
      'reason': 'AI decision placeholder',
    };
  }

  @override
  ComputerPlayer copyWith({
    String? id,
    String? name,
    PlayerType? type,
    String? aiDifficulty,
    Map<String, dynamic>? aiPreferences,
    List<Card>? hand,
    List<Card>? visibleCards,
    int? score,
    PlayerStatus? status,
    bool? isCurrentPlayer,
    bool? hasCalledRecall,
    DateTime? lastActivity,
  }) {
    return ComputerPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      aiPreferences: aiPreferences ?? this.aiPreferences,
      hand: hand ?? this.hand,
      visibleCards: visibleCards ?? this.visibleCards,
      score: score ?? this.score,
      status: status ?? this.status,
      isCurrentPlayer: isCurrentPlayer ?? this.isCurrentPlayer,
      hasCalledRecall: hasCalledRecall ?? this.hasCalledRecall,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    baseJson['aiDifficulty'] = aiDifficulty;
    baseJson['aiPreferences'] = aiPreferences;
    return baseJson;
  }

  /// Create computer player from JSON
  factory ComputerPlayer.fromJson(Map<String, dynamic> json) {
    final basePlayer = Player.fromJson(json);
    return ComputerPlayer(
      id: basePlayer.id,
      name: basePlayer.name,
      aiDifficulty: json['aiDifficulty'] ?? 'medium',
      aiPreferences: Map<String, dynamic>.from(json['aiPreferences'] ?? {}),
      hand: basePlayer.hand,
      visibleCards: basePlayer.visibleCards,
      score: basePlayer.score,
      status: basePlayer.status,
      isCurrentPlayer: basePlayer.isCurrentPlayer,
      hasCalledRecall: basePlayer.hasCalledRecall,
      lastActivity: basePlayer.lastActivity,
    );
  }
} 