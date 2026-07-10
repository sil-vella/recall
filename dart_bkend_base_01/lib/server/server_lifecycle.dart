import 'dart:async';
import 'dart:io';

/// Registers SIGINT/SIGTERM handlers for graceful HTTP server shutdown.
void registerGracefulShutdown(HttpServer server) {
  Future<void> shutdown() async {
    try {
      await server.close(force: false);
    } catch (_) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());
}
