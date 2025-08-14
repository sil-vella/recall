import 'package:flutter/foundation.dart';
import 'game_state.dart' as gm;
import 'player.dart';
import 'card.dart';

/// Enumeration of game phases for state management
enum GamePhase {
  idle,           // No active game
  inLobby,        // In room lobby, waiting to start
  starting,       // Game is being initialized
  playing,        // Active game in progress
  paused,         // Game temporarily paused
  ended,          // Game completed
  error           // Error state
}

/// Room information for lobby management
@immutable
class RoomInfo {
  final String id;
  final String name;
  final int playerCount;
  final int maxPlayers;
  final bool isPrivate;
  final String status;
  final DateTime createdAt;
  final List<String> playerNames;

  const RoomInfo({
    required this.id,
    required this.name,
    required this.playerCount,
    required this.maxPlayers,
    this.isPrivate = false,
    this.status = 'waiting',
    required this.createdAt,
    this.playerNames = const [],
  });

  RoomInfo copyWith({
    String? id,
    String? name,
    int? playerCount,
    int? maxPlayers,
    bool? isPrivate,
    String? status,
    DateTime? createdAt,
    List<String>? playerNames,
  }) {
    return RoomInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      playerCount: playerCount ?? this.playerCount,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      isPrivate: isPrivate ?? this.isPrivate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      playerNames: playerNames ?? this.playerNames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'playerCount': playerCount,
      'maxPlayers': maxPlayers,
      'isPrivate': isPrivate,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'playerNames': playerNames,
    };
  }

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      playerCount: json['playerCount'] ?? 0,
      maxPlayers: json['maxPlayers'] ?? 4,
      isPrivate: json['isPrivate'] ?? false,
      status: json['status'] ?? 'waiting',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      playerNames: List<String>.from(json['playerNames'] ?? []),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RoomInfo &&
        other.id == id &&
        other.name == name &&
        other.playerCount == playerCount &&
        other.maxPlayers == maxPlayers &&
        other.isPrivate == isPrivate &&
        other.status == status &&
        listEquals(other.playerNames, playerNames);
  }

  @override
  int get hashCode {
    return Object.hash(id, name, playerCount, maxPlayers, isPrivate, status, playerNames);
  }
}

/// Unified state class - Single Source of Truth for all Recall game state
@immutable
class RecallGameState {
  // Game Domain
  final gm.GameState? gameState;
  final String? currentGameId;
  final GamePhase gamePhase;
  final bool isGameActive;
  final int currentTurnIndex;
  final String? currentPlayerId;

  // Room Domain
  final List<RoomInfo> availableRooms;
  final RoomInfo? currentRoom;
  final String? currentRoomId;
  final bool isInRoom;
  final bool isRoomOwner;

  // Player Domain
  final List<Player> players;
  final Player? currentPlayer;
  final String? myPlayerId;
  final List<Card> myHand;
  final Map<String, List<Card>> playerHands;

  // Network Domain
  final bool isConnected;
  final bool isLoading;
  final String? lastError;
  final DateTime lastUpdated;
  final bool isInitialized;

  // UI State
  final bool showRoomList;
  final bool showCreateRoom;
  final String? selectedRoomId;

  const RecallGameState({
    // Game Domain
    this.gameState,
    this.currentGameId,
    this.gamePhase = GamePhase.idle,
    this.isGameActive = false,
    this.currentTurnIndex = 0,
    this.currentPlayerId,

    // Room Domain
    this.availableRooms = const [],
    this.currentRoom,
    this.currentRoomId,
    this.isInRoom = false,
    this.isRoomOwner = false,

    // Player Domain
    this.players = const [],
    this.currentPlayer,
    this.myPlayerId,
    this.myHand = const [],
    this.playerHands = const {},

    // Network Domain
    this.isConnected = false,
    this.isLoading = false,
    this.lastError,
    required this.lastUpdated,
    this.isInitialized = false,

    // UI State
    this.showRoomList = false,
    this.showCreateRoom = false,
    this.selectedRoomId,
  });

  /// Factory constructor for initial state
  factory RecallGameState.initial() {
    return RecallGameState(
      lastUpdated: DateTime.now(),
    );
  }

  /// Computed Properties
  bool get isMyTurn => currentPlayerId == myPlayerId;
  bool get canStartGame => isInRoom && isRoomOwner && players.length >= 1;
  bool get hasError => lastError != null;
  int get myHandSize => myHand.length;
  int get totalPlayers => players.length;
  bool get isGameInProgress => gamePhase == GamePhase.playing;
  bool get isInLobbyPhase => gamePhase == GamePhase.inLobby;

  /// Get current player from players list
  Player? get currentPlayerFromList {
    if (currentPlayerId == null) return null;
    try {
      return players.firstWhere((p) => p.id == currentPlayerId);
    } catch (e) {
      return null;
    }
  }

  /// Get my player from players list
  Player? get myPlayer {
    if (myPlayerId == null) return null;
    try {
      return players.firstWhere((p) => p.id == myPlayerId);
    } catch (e) {
      return null;
    }
  }

  /// Copy with method for immutable updates
  RecallGameState copyWith({
    // Game Domain
    gm.GameState? gameState,
    String? currentGameId,
    GamePhase? gamePhase,
    bool? isGameActive,
    int? currentTurnIndex,
    String? currentPlayerId,

    // Room Domain
    List<RoomInfo>? availableRooms,
    RoomInfo? currentRoom,
    String? currentRoomId,
    bool? isInRoom,
    bool? isRoomOwner,

    // Player Domain
    List<Player>? players,
    Player? currentPlayer,
    String? myPlayerId,
    List<Card>? myHand,
    Map<String, List<Card>>? playerHands,

    // Network Domain
    bool? isConnected,
    bool? isLoading,
    String? lastError,
    DateTime? lastUpdated,
    bool? isInitialized,

    // UI State
    bool? showRoomList,
    bool? showCreateRoom,
    String? selectedRoomId,

    // Special handling for nullable fields
    bool clearLastError = false,
    bool clearCurrentGameId = false,
    bool clearCurrentRoomId = false,
    bool clearCurrentPlayerId = false,
    bool clearSelectedRoomId = false,
    bool clearCurrentRoom = false,
    bool clearGameState = false,
  }) {
    return RecallGameState(
      // Game Domain
      gameState: clearGameState ? null : (gameState ?? this.gameState),
      currentGameId: clearCurrentGameId ? null : (currentGameId ?? this.currentGameId),
      gamePhase: gamePhase ?? this.gamePhase,
      isGameActive: isGameActive ?? this.isGameActive,
      currentTurnIndex: currentTurnIndex ?? this.currentTurnIndex,
      currentPlayerId: clearCurrentPlayerId ? null : (currentPlayerId ?? this.currentPlayerId),

      // Room Domain
      availableRooms: availableRooms ?? this.availableRooms,
      currentRoom: clearCurrentRoom ? null : (currentRoom ?? this.currentRoom),
      currentRoomId: clearCurrentRoomId ? null : (currentRoomId ?? this.currentRoomId),
      isInRoom: isInRoom ?? this.isInRoom,
      isRoomOwner: isRoomOwner ?? this.isRoomOwner,

      // Player Domain
      players: players ?? this.players,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      myPlayerId: myPlayerId ?? this.myPlayerId,
      myHand: myHand ?? this.myHand,
      playerHands: playerHands ?? this.playerHands,

      // Network Domain
      isConnected: isConnected ?? this.isConnected,
      isLoading: isLoading ?? this.isLoading,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastUpdated: lastUpdated ?? DateTime.now(),
      isInitialized: isInitialized ?? this.isInitialized,

      // UI State
      showRoomList: showRoomList ?? this.showRoomList,
      showCreateRoom: showCreateRoom ?? this.showCreateRoom,
      selectedRoomId: clearSelectedRoomId ? null : (selectedRoomId ?? this.selectedRoomId),
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'currentGameId': currentGameId,
      'gamePhase': gamePhase.name,
      'isGameActive': isGameActive,
      'currentTurnIndex': currentTurnIndex,
      'currentPlayerId': currentPlayerId,
      'availableRooms': availableRooms.map((r) => r.toJson()).toList(),
      'currentRoom': currentRoom?.toJson(),
      'currentRoomId': currentRoomId,
      'isInRoom': isInRoom,
      'isRoomOwner': isRoomOwner,
      'players': players.map((p) => p.toJson()).toList(),
      'myPlayerId': myPlayerId,
      'myHand': myHand.map((c) => c.toJson()).toList(),
      'playerHands': playerHands.map((key, value) => 
          MapEntry(key, value.map((c) => c.toJson()).toList())),
      'isConnected': isConnected,
      'isLoading': isLoading,
      'lastError': lastError,
      'lastUpdated': lastUpdated.toIso8601String(),
      'isInitialized': isInitialized,
      'showRoomList': showRoomList,
      'showCreateRoom': showCreateRoom,
      'selectedRoomId': selectedRoomId,
    };
  }

  /// Factory constructor from JSON
  factory RecallGameState.fromJson(Map<String, dynamic> json) {
    return RecallGameState(
      currentGameId: json['currentGameId'],
      gamePhase: GamePhase.values.firstWhere(
        (e) => e.name == json['gamePhase'], 
        orElse: () => GamePhase.idle,
      ),
      isGameActive: json['isGameActive'] ?? false,
      currentTurnIndex: json['currentTurnIndex'] ?? 0,
      currentPlayerId: json['currentPlayerId'],
      availableRooms: (json['availableRooms'] as List<dynamic>?)
          ?.map((r) => RoomInfo.fromJson(r))
          .toList() ?? [],
      currentRoom: json['currentRoom'] != null 
          ? RoomInfo.fromJson(json['currentRoom']) 
          : null,
      currentRoomId: json['currentRoomId'],
      isInRoom: json['isInRoom'] ?? false,
      isRoomOwner: json['isRoomOwner'] ?? false,
      players: (json['players'] as List<dynamic>?)
          ?.map((p) => Player.fromJson(p))
          .toList() ?? [],
      myPlayerId: json['myPlayerId'],
      myHand: (json['myHand'] as List<dynamic>?)
          ?.map((c) => Card.fromJson(c))
          .toList() ?? [],
      playerHands: (json['playerHands'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(
              key, 
              (value as List<dynamic>).map((c) => Card.fromJson(c)).toList()
          )) ?? {},
      isConnected: json['isConnected'] ?? false,
      isLoading: json['isLoading'] ?? false,
      lastError: json['lastError'],
      lastUpdated: DateTime.tryParse(json['lastUpdated'] ?? '') ?? DateTime.now(),
      isInitialized: json['isInitialized'] ?? false,
      showRoomList: json['showRoomList'] ?? false,
      showCreateRoom: json['showCreateRoom'] ?? false,
      selectedRoomId: json['selectedRoomId'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecallGameState &&
        other.currentGameId == currentGameId &&
        other.gamePhase == gamePhase &&
        other.isGameActive == isGameActive &&
        other.currentTurnIndex == currentTurnIndex &&
        other.currentPlayerId == currentPlayerId &&
        listEquals(other.availableRooms, availableRooms) &&
        other.currentRoom == currentRoom &&
        other.currentRoomId == currentRoomId &&
        other.isInRoom == isInRoom &&
        other.isRoomOwner == isRoomOwner &&
        listEquals(other.players, players) &&
        other.myPlayerId == myPlayerId &&
        listEquals(other.myHand, myHand) &&
        mapEquals(other.playerHands, playerHands) &&
        other.isConnected == isConnected &&
        other.isLoading == isLoading &&
        other.lastError == lastError &&
        other.isInitialized == isInitialized &&
        other.showRoomList == showRoomList &&
        other.showCreateRoom == showCreateRoom &&
        other.selectedRoomId == selectedRoomId;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      currentGameId,
      gamePhase,
      isGameActive,
      currentTurnIndex,
      currentPlayerId,
      availableRooms,
      currentRoom,
      currentRoomId,
      isInRoom,
      isRoomOwner,
      players,
      myPlayerId,
      myHand,
      playerHands,
      isConnected,
      isLoading,
      lastError,
      isInitialized,
      showRoomList,
      showCreateRoom,
      selectedRoomId,
    ]);
  }

  @override
  String toString() {
    return 'RecallGameState('
        'gamePhase: $gamePhase, '
        'isGameActive: $isGameActive, '
        'isInRoom: $isInRoom, '
        'currentRoomId: $currentRoomId, '
        'playersCount: ${players.length}, '
        'isConnected: $isConnected, '
        'isLoading: $isLoading, '
        'hasError: $hasError'
        ')';
  }
}
