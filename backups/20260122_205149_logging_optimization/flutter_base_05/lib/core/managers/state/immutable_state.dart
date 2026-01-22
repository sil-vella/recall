import 'package:flutter/foundation.dart';

/// Base class for all immutable state objects
/// 
/// All state in the application should extend this class to ensure:
/// - Immutability (enforced by @immutable annotation)
/// - Proper equality comparison
/// - Type-safe state updates via copyWith()
/// - JSON serialization support
@immutable
abstract class ImmutableState {
  const ImmutableState();
  
  /// Create a copy of this state with some fields replaced
  /// Subclasses MUST implement this method
  ImmutableState copyWith();
  
  /// Convert this state to a JSON-serializable map
  /// Subclasses MUST implement this method
  Map<String, dynamic> toJson();
  
  /// Create an instance from a JSON map
  /// Subclasses SHOULD implement a static fromJson method
  /// Example: static LoginState fromJson(Map<String, dynamic> json) => ...
  
  @override
  bool operator ==(Object other);
  
  @override
  int get hashCode;
}

/// Helper mixin for implementing equality based on props
/// 
/// Usage:
/// ```dart
/// @immutable
/// class MyState extends ImmutableState with EquatableMixin {
///   final String name;
///   final int age;
///   
///   const MyState({required this.name, required this.age});
///   
///   @override
///   List<Object?> get props => [name, age];
/// }
/// ```
mixin EquatableMixin on ImmutableState {
  /// Properties to use for equality comparison
  List<Object?> get props;
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    
    final otherEquatable = other as EquatableMixin;
    final myProps = props;
    final otherProps = otherEquatable.props;
    
    if (myProps.length != otherProps.length) return false;
    
    for (var i = 0; i < myProps.length; i++) {
      if (myProps[i] != otherProps[i]) return false;
    }
    
    return true;
  }
  
  @override
  int get hashCode {
    return Object.hashAll(props);
  }
}

