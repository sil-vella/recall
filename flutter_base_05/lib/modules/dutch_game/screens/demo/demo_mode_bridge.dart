import 'package:dutch/tools/logging/logger.dart';
import 'demo_functionality.dart';

const bool LOGGING_SWITCH = false; // Enabled for demo debugging

/// Demo Mode Bridge
/// 
/// Bridges player actions to demo-specific functionality.
/// Routes game events to DemoFunctionality instead of backend/WebSocket.
class DemoModeBridge {
  static DemoModeBridge? _instance;
  static DemoModeBridge get instance {
    _instance ??= DemoModeBridge._internal();
    return _instance!;
  }

  DemoModeBridge._internal();

  final Logger _logger = Logger();
  final DemoFunctionality _demoFunctionality = DemoFunctionality.instance;

  /// Handle a game event (called from event emitter in demo mode)
  Future<Map<String, dynamic>> handleEvent(
    String eventType,
    Map<String, dynamic> data,
  ) async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('📨 DemoModeBridge: Handling event $eventType');
      }
      if (LOGGING_SWITCH) {
        _logger.info('📨 DemoModeBridge: Event data: $data');
      }

      // Route to demo functionality
      final result = await _demoFunctionality.handleAction(eventType, data);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DemoModeBridge: Successfully handled event $eventType');
      }
      return result;
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DemoModeBridge: Error handling event $eventType: $e', error: e, stackTrace: stackTrace);
      }
      return {'success': false, 'error': e.toString()};
    }
  }
}

