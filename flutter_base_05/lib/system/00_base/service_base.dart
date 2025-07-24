import '../../tools/logging/logger.dart';

abstract class ServicesBase {
  /// Initialize the service (now asynchronous)
  Future<void> initialize() async {
    Logger().info('${this.runtimeType} initialized.');
  }

  /// Dispose method to clean up resources
  void dispose() {
    Logger().info('${this.runtimeType} disposed.');
  }
}
