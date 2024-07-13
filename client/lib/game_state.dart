import 'package:flutter/material.dart';

class GameState with ChangeNotifier {
  Map<String, dynamic> preGameState = {
    'gameData': {
      'gameMode': 'solo',
      'gameState': 'pre_game', // default value to ensure it's not empty
      'gameId': null,
      'numOfOpponents': '2',
      'shareLink': null,
    },
    'playerData': {
      'gameCreatorUsername': null,
      'username': null,
      'player_id': null,
      'player_type': null,
    },
  };
  Map<String, dynamic> activeGamePlayState = {};
  Map<String, dynamic> userSection = {};
  String gameId = '';
  Map<String, dynamic> messageAnimation = {};
  Map<String, dynamic> callWindow = {};

  void updateSection(String section, Map<String, dynamic> updates) {
    switch (section) {
      case 'preGameState':
        preGameState.addAll(updates);
        break;
      case 'activeGamePlayState':
        activeGamePlayState.addAll(updates);
        break;
      case 'userSection':
        userSection.addAll(updates);
        break;
      case 'callWindow':
        callWindow.addAll(updates);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void updateGameData(Map<String, dynamic> updates) {
    preGameState['gameData'] = updates;
    notifyListeners();
  }

  void updatePlayerData(Map<String, dynamic> updates) {
    preGameState['playerData'] = updates;
    notifyListeners();
  }

  void setGameId(String id) {
    gameId = id;
    preGameState['gameData']['gameId'] = id;
    notifyListeners();
  }

  void setMessageAnimation(Map<String, dynamic> data) {
    messageAnimation = data;
    notifyListeners();
  }
}
