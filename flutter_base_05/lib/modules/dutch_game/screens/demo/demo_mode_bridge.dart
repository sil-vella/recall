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

  static bool _interceptPracticeEvents = false;
  static final Set<String> _interceptPracticeEventTypes = {};

  /// Optional hook after an intercepted practice event is handled (demo completion checks).
  static void Function()? onInterceptHandled;

  /// Tutorial demos run on a practice room but queen/jack/call-dutch actions must use
  /// [DemoFunctionality] (practice round requires special_play_window queue state).
  static void configurePracticeIntercept({
    required bool active,
    Set<String>? eventTypes,
  }) {
    _interceptPracticeEvents = active;
    _interceptPracticeEventTypes
      ..clear()
      ..addAll(eventTypes ?? const {});
  }

  /// Returns true when the event was handled locally (practice coordinator skipped).
  static Future<bool> tryInterceptPracticeEvent(
    String eventType,
    Map<String, dynamic> data,
  ) async {
    if (!_interceptPracticeEvents) return false;
    if (!_interceptPracticeEventTypes.contains(eventType)) return false;
    await instance.handleEvent(eventType, data);
    onInterceptHandled?.call();
    return true;
  }

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

