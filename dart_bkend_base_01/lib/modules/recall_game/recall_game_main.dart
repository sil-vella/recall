import '../../server/websocket_server.dart';
import '../../server/room_manager.dart';
import 'coordinator/game_event_coordinator.dart';
import '../../utils/server_logger.dart';

const bool LOGGING_SWITCH = true;

/// Entry point for registering Recall game module components with the server.
class RecallGameModule {
  final WebSocketServer server;
  final RoomManager roomManager;
  late final GameEventCoordinator coordinator;
  final ServerLogger _logger = ServerLogger();

  RecallGameModule(this.server, this.roomManager) {
    coordinator = GameEventCoordinator(roomManager, server);
    _logger.info('RecallGameModule initialized', isOn: LOGGING_SWITCH);
  }
}


