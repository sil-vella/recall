import 'utility.dart';

class GameSetup {
  static void handleCreateGame(
      String gameMode, String username, Function onCreateGame) {
    if (gameMode.isNotEmpty && username.isNotEmpty) {
      final gameData = {'gameMode': gameMode};
      final playerData = {'gameCreatorUsername': username};
      Utility.emitEvent('game_mode_selection',
          {'gameData': gameData, 'playerData': playerData});
      onCreateGame(playerData);
    }
  }

  static void handleCreateSoloGame(
      String gameMode, String numOfOpponents, Function onCreateGame) {
    if (gameMode.isNotEmpty) {
      final gameData = {'gameMode': gameMode, 'numOfOpponents': numOfOpponents};
      final playerData = {'gameCreatorUsername': 'You'};
      Utility.emitEvent('game_mode_selection',
          {'gameData': gameData, 'playerData': playerData});
      onCreateGame(playerData);
    }
  }

  static void multiplayerGameReadyHandler(
      Map<String, dynamic> data,
      Function setShareLink,
      Function setCreatorId,
      Function setGameId,
      Function setGameState) {
    final gameData = data['gameData'];
    final gameRoom = gameData['lobby_rooms']['game_room'];
    final shareLink = gameData['share_link'];
    final gameState = gameData['game_state'];
    final creatorId = gameData['lobby_rooms']['private_room'];

    setShareLink(shareLink);
    setCreatorId(creatorId);
    setGameId(gameRoom);
    setGameState(gameState);
  }
}
