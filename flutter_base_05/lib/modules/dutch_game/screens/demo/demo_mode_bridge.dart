import 'demo_functionality.dart';


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

  final DemoFunctionality _demoFunctionality = DemoFunctionality.instance;

  /// Handle a game event (called from event emitter in demo mode)
  Future<Map<String, dynamic>> handleEvent(
    String eventType,
    Map<String, dynamic> data,
  ) async {
    try {
      
      

      // Route to demo functionality
      final result = await _demoFunctionality.handleAction(eventType, data);
      
      
      return result;
    } catch (e, stackTrace) {
      
      return {'success': false, 'error': e.toString()};
    }
  }
}

