import 'package:flutter/foundation.dart';
import '../../../../core/managers/state/immutable_state.dart';
import 'games_map.dart';
import 'my_hand_state.dart';
import 'center_board_state.dart';
import 'opponents_panel_state.dart';
import 'card_data.dart';

/// Main immutable state for the entire Recall Game module
/// This is the Single Source of Truth (SSOT) for all recall game state
@immutable
class RecallGameState extends ImmutableState with EquatableMixin {
  // Connection state
  final bool isLoading;
  final bool isConnected;
  final String currentRoomId;
  final bool isInRoom;
  
  // Game state
  final String currentGameId;
  final GamesMap games;
  final List<Map<String, dynamic>> joinedGames;
  final int totalJoinedGames;
  
  // Widget slices (computed from games)
  final MyHandState myHand;
  final CenterBoardState centerBoard;
  final OpponentsPanelState opponentsPanel;
  
  // UI state
  final List<CardData> cardsToPeek;
  final List<Map<String, dynamic>> turnEvents;
  final Map<String, dynamic>? actionError;
  final Map<String, dynamic> messages;
  final Map<String, dynamic> instructions;
  
  // Metadata
  final String lastUpdated;
  
  const RecallGameState({
    required this.isLoading,
    required this.isConnected,
    required this.currentRoomId,
    required this.isInRoom,
    required this.currentGameId,
    required this.games,
    required this.joinedGames,
    required this.totalJoinedGames,
    required this.myHand,
    required this.centerBoard,
    required this.opponentsPanel,
    required this.cardsToPeek,
    required this.turnEvents,
    this.actionError,
    required this.messages,
    required this.instructions,
    required this.lastUpdated,
  });
  
  /// Create an initial empty state
  factory RecallGameState.initial() {
    return RecallGameState(
      isLoading: false,
      isConnected: false,
      currentRoomId: '',
      isInRoom: false,
      currentGameId: '',
      games: const GamesMap.empty(),
      joinedGames: const [],
      totalJoinedGames: 0,
      myHand: MyHandState(
        cards: const [],
        playerStatus: 'waiting',
        isMyTurn: false,
      ),
      centerBoard: CenterBoardState(
        discardPile: const [],
        drawPileCount: 0,
        playerStatus: 'waiting',
        gamePhase: 'waiting',
        isGameActive: false,
      ),
      opponentsPanel: OpponentsPanelState(
        opponents: const [],
        currentPlayerStatus: 'waiting',
      ),
      cardsToPeek: const [],
      turnEvents: const [],
      messages: const {'session': [], 'rooms': {}},
      instructions: const {'isVisible': false, 'title': '', 'content': ''},
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
  
  @override
  RecallGameState copyWith({
    bool? isLoading,
    bool? isConnected,
    String? currentRoomId,
    bool? isInRoom,
    String? currentGameId,
    GamesMap? games,
    List<Map<String, dynamic>>? joinedGames,
    int? totalJoinedGames,
    MyHandState? myHand,
    CenterBoardState? centerBoard,
    OpponentsPanelState? opponentsPanel,
    List<CardData>? cardsToPeek,
    List<Map<String, dynamic>>? turnEvents,
    Map<String, dynamic>? actionError,
    Map<String, dynamic>? messages,
    Map<String, dynamic>? instructions,
    String? lastUpdated,
  }) {
    return RecallGameState(
      isLoading: isLoading ?? this.isLoading,
      isConnected: isConnected ?? this.isConnected,
      currentRoomId: currentRoomId ?? this.currentRoomId,
      isInRoom: isInRoom ?? this.isInRoom,
      currentGameId: currentGameId ?? this.currentGameId,
      games: games ?? this.games,
      joinedGames: joinedGames ?? this.joinedGames,
      totalJoinedGames: totalJoinedGames ?? this.totalJoinedGames,
      myHand: myHand ?? this.myHand,
      centerBoard: centerBoard ?? this.centerBoard,
      opponentsPanel: opponentsPanel ?? this.opponentsPanel,
      cardsToPeek: cardsToPeek ?? this.cardsToPeek,
      turnEvents: turnEvents ?? this.turnEvents,
      actionError: actionError ?? this.actionError,
      messages: messages ?? this.messages,
      instructions: instructions ?? this.instructions,
      lastUpdated: lastUpdated ?? DateTime.now().toIso8601String(),
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'isLoading': isLoading,
      'isConnected': isConnected,
      'currentRoomId': currentRoomId,
      'isInRoom': isInRoom,
      'currentGameId': currentGameId,
      'games': games.toJson(),
      'joinedGames': joinedGames,
      'totalJoinedGames': totalJoinedGames,
      'myHand': myHand.toJson(),
      'centerBoard': centerBoard.toJson(),
      'opponentsPanel': opponentsPanel.toJson(),
      'cards_to_peek': cardsToPeek.map((c) => c.toJson()).toList(),
      'turn_events': turnEvents,
      if (actionError != null) 'actionError': actionError,
      'messages': messages,
      'instructions': instructions,
      'lastUpdated': lastUpdated,
    };
  }
  
  factory RecallGameState.fromJson(Map<String, dynamic> json) {
    final gamesJson = json['games'] as Map<String, dynamic>? ?? {};
    final games = GamesMap.fromJson(gamesJson);
    
    final joinedGamesRaw = json['joinedGames'] as List<dynamic>? ?? [];
    final joinedGames = joinedGamesRaw.map((g) => g as Map<String, dynamic>).toList();
    
    final myHandJson = json['myHand'] as Map<String, dynamic>? ?? {};
    final myHand = MyHandState.fromJson(myHandJson);
    
    final centerBoardJson = json['centerBoard'] as Map<String, dynamic>? ?? {};
    final centerBoard = CenterBoardState.fromJson(centerBoardJson);
    
    final opponentsPanelJson = json['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponentsPanel = OpponentsPanelState.fromJson(opponentsPanelJson);
    
    final cardsToPeekRaw = json['cards_to_peek'] as List<dynamic>? ?? [];
    final cardsToPeek = cardsToPeekRaw.map((c) => CardData.fromJson(c as Map<String, dynamic>)).toList();
    
    final turnEventsRaw = json['turn_events'] as List<dynamic>? ?? [];
    final turnEvents = turnEventsRaw.map((e) => e as Map<String, dynamic>).toList();
    
    return RecallGameState(
      isLoading: json['isLoading'] as bool? ?? false,
      isConnected: json['isConnected'] as bool? ?? false,
      currentRoomId: json['currentRoomId'] as String? ?? '',
      isInRoom: json['isInRoom'] as bool? ?? false,
      currentGameId: json['currentGameId'] as String? ?? '',
      games: games,
      joinedGames: joinedGames,
      totalJoinedGames: json['totalJoinedGames'] as int? ?? 0,
      myHand: myHand,
      centerBoard: centerBoard,
      opponentsPanel: opponentsPanel,
      cardsToPeek: cardsToPeek,
      turnEvents: turnEvents,
      actionError: json['actionError'] as Map<String, dynamic>?,
      messages: json['messages'] as Map<String, dynamic>? ?? {'session': [], 'rooms': {}},
      instructions: json['instructions'] as Map<String, dynamic>? ?? {'isVisible': false, 'title': '', 'content': ''},
      lastUpdated: json['lastUpdated'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
  
  @override
  List<Object?> get props => [
    isLoading, isConnected, currentRoomId, isInRoom, currentGameId,
    games, joinedGames, totalJoinedGames, myHand, centerBoard, opponentsPanel,
    cardsToPeek, turnEvents, actionError, messages, instructions, lastUpdated
  ];
  
  @override
  String toString() => 'RecallGameState(game=$currentGameId, ${games.games.length} games)';
}

