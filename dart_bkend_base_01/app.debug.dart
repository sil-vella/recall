import 'dart:io';
import 'package:dart_game_server/utils/config.dart';
import 'package:dart_game_server/utils/dev_logger.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'lib/server/http_notify_handler.dart';
import 'lib/server/websocket_server.dart';

// ignore: constant_identifier_names — set false when not debugging this entrypoint (release tooling may flip).
const bool LOGGING_SWITCH = true;

void main(List<String> args) async {
  if (LOGGING_SWITCH) {
    customlog('app.debug.dart entry');
  }
  try {
    final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

    // Python Flask URL for validateToken / stats (host dev: same machine as compound launch).
    // SSOT: .env.local PYTHON_API_URL when run via run_dart_ws_to_global_log.sh (sources .env.local).
    final pythonApiUrl = () {
      final fromEnv = Platform.environment['PYTHON_API_URL']?.trim();
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
      return 'http://127.0.0.1:5001';
    }();

    if (LOGGING_SWITCH) {
      final keyLen = Config.pythonServiceKey.length;
      customlog(
        'app.debug.dart: pythonApiUrl=$pythonApiUrl '
        'usePythonServiceKey=${Config.usePythonServiceKey} '
        'DART_BACKEND_SERVICE_KEY=${keyLen > 0 ? "set($keyLen chars)" : "MISSING"}',
      );
    }

    final wsServer = WebSocketServer(pythonApiUrl: pythonApiUrl);

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
