import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'lib/server/http_notify_handler.dart';
import 'lib/server/websocket_server.dart';

void main(List<String> args) async {
  try {
    final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

    // Create WebSocket server with Docker service URL (for VPS)
    final wsServer = WebSocketServer(pythonApiUrl: 'http://dutch_flask-external:5001');

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
