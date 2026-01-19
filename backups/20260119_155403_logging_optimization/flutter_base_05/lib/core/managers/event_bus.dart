import 'dart:async';

/// A type definition for event handlers
typedef EventHandler<T> = void Function(T event);

/// Base class for all events
class Event {
  final DateTime timestamp = DateTime.now();
  
  Event();
  
  factory Event.create() => Event();
}

/// The EventBus manages event streams and subscriptions
class EventBus {
  static final EventBus _instance = EventBus._internal();
  
  factory EventBus() => _instance;
  
  EventBus._internal();

  /// Map of event types to their respective controllers
  final Map<Type, StreamController<Event>> _controllers = {};

  /// Get a stream for a specific event type
  Stream<T> on<T extends Event>() {
    if (!_controllers.containsKey(T)) {
      _controllers[T] = StreamController<T>.broadcast();
    }
    return _controllers[T]!.stream.cast<T>();
  }

  /// Fire an event to all listeners
  void fire(Event event) {
    final Type eventType = event.runtimeType;
    
    if (!_controllers.containsKey(eventType)) {
      return;
    }

    _controllers[eventType]!.add(event);
  }

  /// Subscribe to an event type with a handler
  StreamSubscription<T> subscribe<T extends Event>(EventHandler<T> handler) {
    return on<T>().listen(handler);
  }

  /// Clear all event streams and subscriptions
  void dispose() {
    for (var controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }

  /// Clear a specific event type's stream and subscriptions
  void clearEvent<T extends Event>() {
    if (_controllers.containsKey(T)) {
      _controllers[T]!.close();
      _controllers.remove(T);
    }
  }
} 