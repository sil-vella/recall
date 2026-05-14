import 'dart:io';
import 'package:dart_game_server/utils/dev_logger.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'lib/server/http_notify_handler.dart';
import 'lib/server/websocket_server.dart';

// ignore: constant_identifier_names — set false when not debugging this entrypoint (release tooling may flip).
const bool LOGGING_SWITCH = true;

void main(List<String> args) async {
  if (LOGGING_SWITCH) {
    devLog('app.debug.dart entry');
  }
  try {
    final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

    // Create WebSocket server with localhost URL (for local development)
    final wsServer = WebSocketServer(pythonApiUrl: 'http://localhost:5001');

    final handler = createHttpAndWebSocketHandler(
      wsServer: wsServer,
      onWebSocket: wsServer.handleConnection,
    );

    // Start server
    final server = await shelf_io.serve(handler, '0.0.0.0', port);
    // Handle shutdown signals
    ProcessSignal.sigint.watch().listen((signal) async {
      await server.close(force: true);
      exit(0);
    });
  } catch (e, stackTrace) {
    stderr.writeln('❌ Failed to start Dart Game Server: $e');
    stderr.writeln('Stack trace: $stackTrace');
    exit(1);
  }
}
