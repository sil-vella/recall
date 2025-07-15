import '../../tools/logging/logger.dart';

/// class ServicesBase - Handles external service interactions
///
/// Handles external service interactions
///
/// Example:
/// ```dart
/// final servicesbase = ServicesBase();
/// ```
///
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
