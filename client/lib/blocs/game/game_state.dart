import 'package:equatable/equatable.dart';

class GameState extends Equatable {
  final Map<String, dynamic> preGameState;
  final Map<String, dynamic> activeGamePlayState;
  final Map<String, dynamic> userSection;
  final String gameId;
  final Map<String, dynamic> messageAnimation;
  final Map<String, dynamic> callWindow;

  const GameState({
    required this.preGameState,
    required this.activeGamePlayState,
    required this.userSection,
    required this.gameId,
    required this.messageAnimation,
    required this.callWindow,
  });

  GameState copyWith({
    Map<String, dynamic>? preGameState,
    Map<String, dynamic>? activeGamePlayState,
    Map<String, dynamic>? userSection,
    String? gameId,
    Map<String, dynamic>? messageAnimation,
    Map<String, dynamic>? callWindow,
  }) {
    return GameState(
      preGameState: preGameState ?? this.preGameState,
      activeGamePlayState: activeGamePlayState ?? this.activeGamePlayState,
      userSection: userSection ?? this.userSection,
      gameId: gameId ?? this.gameId,
      messageAnimation: messageAnimation ?? this.messageAnimation,
      callWindow: callWindow ?? this.callWindow,
    );
  }

  @override
  List<Object?> get props => [
        preGameState,
        activeGamePlayState,
        userSection,
        gameId,
        messageAnimation,
        callWindow,
      ];
}

class InitialGameState extends GameState {
  InitialGameState()
      : super(
          preGameState: {
            'gameData': {
              'gameMode': 'solo',
              'gameState': 'pre_game',
              'numOfOpponents': '2',
              'shareLink': null,
            },
            'playerData': {
              'gameCreatorUsername': null,
              'username': null,
              'player_id': null,
              'player_type': null,
            },
          },
          activeGamePlayState: {},
          userSection: {},
          gameId: '',
          messageAnimation: {},
          callWindow: {},
        );
}
