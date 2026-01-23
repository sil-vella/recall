import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'lib/server/websocket_server.dart';
import 'lib/utils/server_logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false; // Enabled for rank-based matching and debugging

void main(List<String> args) async {
  // Initialize logger first
  final logger = Logger();
  logger.initialize();
  
  try {
    final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
    
    if (LOGGING_SWITCH) {
      logger.info('🎮 Initializing Dart Game Server (DEBUG MODE - Local)...');
    }
    
    // Create WebSocket server with localhost URL (for local development)
    final wsServer = WebSocketServer(pythonApiUrl: 'http://localhost:5001');
    
    // WebSocket handler
    final handler = webSocketHandler((webSocket) {
      wsServer.handleConnection(webSocket);
    });
    
    // Start server
    final server = await shelf_io.serve(handler, '0.0.0.0', port);
    
    if (LOGGING_SWITCH) {
      logger.info('✅ Game server running on ws://${server.address.host}:${server.port}');
    }
    if (LOGGING_SWITCH) {
      logger.info('🔗 Python API URL: http://localhost:5001');
    }
    if (LOGGING_SWITCH) {
      logger.info('📡 Waiting for connections...');
    }
    
    // Handle shutdown signals
    ProcessSignal.sigint.watch().listen((signal) async {
      if (LOGGING_SWITCH) {
        logger.info('🛑 Shutting down server...');
      }
      await server.close(force: true);
      exit(0);
    });
  } catch (e, stackTrace) {
    if (LOGGING_SWITCH) {
      logger.error('❌ Failed to start Dart Game Server: $e');
    }
    if (LOGGING_SWITCH) {
      logger.error('Stack trace: $stackTrace');
    }
    stderr.writeln('❌ Failed to start Dart Game Server: $e');
    stderr.writeln('Stack trace: $stackTrace');
    exit(1);
  }
}
