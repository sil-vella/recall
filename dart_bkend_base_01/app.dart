import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'lib/server/websocket_server.dart';
import 'lib/utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = true;

void main(List<String> args) async {
  // Initialize logger first
  final logger = Logger();
  logger.initialize();
  
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  
  logger.info('🎮 Initializing Dart Game Server...', isOn: LOGGING_SWITCH);
  
  // Create WebSocket server
  final wsServer = WebSocketServer();
  
  // WebSocket handler
  final handler = webSocketHandler((webSocket) {
    wsServer.handleConnection(webSocket);
  });
  
  // Start server
  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  
  logger.info('✅ Game server running on ws://${server.address.host}:${server.port}', isOn: LOGGING_SWITCH);
  logger.info('📡 Waiting for connections...', isOn: LOGGING_SWITCH);
  
  // Handle shutdown signals
  ProcessSignal.sigint.watch().listen((signal) async {
    logger.info('🛑 Shutting down server...', isOn: LOGGING_SWITCH);
    await server.close(force: true);
    exit(0);
  });
}
