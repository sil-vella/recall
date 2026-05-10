import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'lib/server/http_notify_handler.dart';
import 'lib/server/websocket_server.dart';

Future<void> _appendDartAgentLog(String line) async {
  try {
    final pkgRoot = File(Platform.script.toFilePath()).parent.path;
    final repoRoot = Directory(pkgRoot).parent.path;
    final logPath = '$repoRoot/python_base_04/tools/logger/server.log';
    await Directory(File(logPath).parent.path).create(recursive: true);
    final ts = DateTime.now().toUtc().toIso8601String();
    final shortened = ts.length >= 19 ? ts.substring(0, 19) + 'Z' : ts;
    await File(logPath).writeAsString(
      '$shortened [DART_WS] $line\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

void main(List<String> args) async {
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
    await _appendDartAgentLog(
      'listening address=${server.address.address} port=${server.port}',
    );
    // Handle shutdown signals
    ProcessSignal.sigint.watch().listen((signal) async {
      await server.close(force: true);
      exit(0);
    });
  } catch (e, stackTrace) {
    stderr.writeln('❌ Failed to start Dart Game Server: $e');
    stderr.writeln('Stack trace: $stackTrace');
    await _appendDartAgentLog('ERROR: $e\n$stackTrace');
    exit(1);
  }
}
