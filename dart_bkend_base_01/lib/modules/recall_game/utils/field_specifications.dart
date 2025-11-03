/// Field specifications for validated events and state updates
/// This file defines the validation rules for all recall game data

/// Exception thrown when event validation fails
class RecallEventException implements Exception {
  final String message;
  final String? eventType;
  final String? fieldName;
  
  RecallEventException(this.message, {this.eventType, this.fieldName});
  
  @override
  String toString() {
    if (eventType != null && fieldName != null) {
      return 'RecallEventException in $eventType.$fieldName: $message';
    } else if (eventType != null) {
      return 'RecallEventException in $eventType: $message';
    }
    return 'RecallEventException: $message';
  }
}

/// Exception thrown when state validation fails
class RecallStateException implements Exception {
  final String message;
  final String? fieldName;
  
  RecallStateException(this.message, {this.fieldName});
  
  @override
  String toString() {
    if (fieldName != null) {
      return 'RecallStateException in $fieldName: $message';
    }
    return 'RecallStateException: $message';
  }
}

/// Specification for validating event fields
class RecallEventFieldSpec {
  final Type type;
  final bool required;
  final List<dynamic>? allowedValues;
  final int? minLength;
  final int? maxLength;
  final int? min;
  final int? max;
  final String? pattern;
  final String? description;
  
  const RecallEventFieldSpec({
    required this.type,
    this.required = true,
    this.allowedValues,
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.pattern,
    this.description,
  });
}

/// Specification for validating state fields
class RecallStateFieldSpec {
  final Type type;
  final bool required;
  final bool nullable;
  final dynamic defaultValue;
  final List<dynamic>? allowedValues;
  final int? min;
  final int? max;
  final String? description;
  
  const RecallStateFieldSpec({
    required this.type,
    this.required = false,
    this.nullable = false,
    this.defaultValue,
    this.allowedValues,
    this.min,
    this.max,
    this.description,
  });
}

/// Validation utilities
class ValidationUtils {
  /// Validate that value matches the expected type
  static bool isValidType(dynamic value, Type expectedType) {
    switch (expectedType) {
      case String:
        return value is String;
      case int:
        return value is int;
      case double:
        return value is double;
      case bool:
        return value is bool;
      case List:
        return value is List;
      case Map:
        return value is Map;
      default:
        return value.runtimeType == expectedType;
    }
  }
  
  /// Validate string against regex pattern
  static bool matchesPattern(String value, String pattern) {
    try {
      final regex = RegExp(pattern);
      return regex.hasMatch(value);
    } catch (e) {
      return false;
    }
  }
  
  /// Validate string length constraints
  static bool isValidLength(String value, {int? minLength, int? maxLength}) {
    if (minLength != null && value.length < minLength) return false;
    if (maxLength != null && value.length > maxLength) return false;
    return true;
  }
  
  /// Validate numeric range constraints
  static bool isValidRange(num value, {num? min, num? max}) {
    if (min != null && value < min) return false;
    if (max != null && value > max) return false;
    return true;
  }
  
  /// Validate value is in allowed list
  static bool isAllowedValue(dynamic value, List<dynamic> allowedValues) {
    return allowedValues.contains(value);
  }
}

