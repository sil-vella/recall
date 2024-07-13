import '../services/socket_service.dart';

class StartEndGame {
  static void startGame(dynamic activeGameData) {
    SocketService.emitEvent('starting-game', {'activeGameData': activeGameData});
  }

  static void endGame(dynamic activeGameData) {
    SocketService.emitEvent('ending-game', {'activeGameData': activeGameData});
  }
}
