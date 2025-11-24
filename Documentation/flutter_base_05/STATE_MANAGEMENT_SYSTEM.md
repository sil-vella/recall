# State Management System

## Overview

Flutter Base 05 implements a hybrid state management system that supports both **immutable state patterns** (like Redux/Bloc) and **legacy map-based state** for backward compatibility. The system is designed to provide type safety, efficient change detection, and predictable state updates.

## Core Principles

### 1. Immutability First

The state management system is built around the principle of **immutability**. State objects are never modified directly. Instead, new state objects are created with the desired changes, ensuring:

- **Predictable Updates**: State changes are explicit and traceable
- **Efficient Change Detection**: Reference equality checks are fast and reliable
- **Thread Safety**: Immutable objects are inherently thread-safe
- **Time-Travel Debugging**: Previous states are preserved, enabling debugging

### 2. Hybrid Architecture

The system supports both:

- **Immutable State Objects**: Type-safe, immutable classes extending `ImmutableState`
- **Legacy Map-Based State**: Traditional `Map<String, dynamic>` for modules not yet migrated

This hybrid approach allows gradual migration without breaking existing functionality.

### 3. Efficient Change Detection

The system uses a two-tier change detection strategy:

- **Reference Equality** (fast path): For immutable objects, checks if the reference is identical
- **Structural Equality** (fallback): For maps and when reference equality fails, performs deep comparison

## Architecture Components

### StateManager

The `StateManager` is a singleton that manages all module states in the application. It extends `ChangeNotifier` to notify listeners when state changes.

#### Key Features

- **Module-Based State**: Each module has its own isolated state namespace
- **Type-Safe Access**: Supports both typed immutable state and map-based state retrieval
- **Automatic Change Detection**: Only notifies listeners when state actually changes
- **Backward Compatibility**: Supports legacy map-based state during migration

#### Module State Storage

```dart
class ModuleState {
  final dynamic state; // Can be Map<String, dynamic> OR ImmutableState
  
  ModuleState({required this.state});
  
  bool get isImmutable => state is ImmutableState;
  ImmutableState get asImmutable => state as ImmutableState;
  Map<String, dynamic> get asMap => state as Map<String, dynamic>;
}
```

The `ModuleState` wrapper allows the system to store either immutable state objects or legacy maps, providing flexibility during migration.

### ImmutableState Base Class

All immutable state objects must extend the `ImmutableState` abstract class:

```dart
@immutable
abstract class ImmutableState {
  const ImmutableState();
  
  /// Create a copy with some fields replaced
  ImmutableState copyWith();
  
  /// Convert to JSON-serializable map
  Map<String, dynamic> toJson();
  
  @override
  bool operator ==(Object other);
  
  @override
  int get hashCode;
}
```

#### EquatableMixin

The `EquatableMixin` provides a convenient way to implement equality based on properties:

```dart
@immutable
class MyState extends ImmutableState with EquatableMixin {
  final String name;
  final int age;
  
  const MyState({required this.name, required this.age});
  
  @override
  List<Object?> get props => [name, age];
  
  @override
  MyState copyWith({String? name, int? age}) {
    return MyState(
      name: name ?? this.name,
      age: age ?? this.age,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {'name': name, 'age': age};
  }
}
```

## State Operations

### Registering State

```dart
// Register immutable state
final initialState = MyState(name: 'John', age: 30);
StateManager().registerModuleState('my_module', initialState);

// Register map-based state (legacy)
StateManager().registerModuleState('legacy_module', {
  'key1': 'value1',
  'key2': 'value2',
});
```

### Updating State

#### Immutable State Updates

```dart
// Get current state
final currentState = StateManager().getModuleState<MyState>('my_module');

// Create new state with changes
final newState = currentState.copyWith(name: 'Jane');

// Update state
StateManager().updateModuleState('my_module', newState);
```

The `StateManager` automatically detects if the new state is identical to the current state (via reference or structural equality) and skips unnecessary updates.

#### Map-Based State Updates (Legacy)

```dart
// Update specific keys
StateManager().updateModuleState('legacy_module', {
  'key1': 'new_value',
  'new_key': 'new_value',
});
```

Map updates are merged with existing state, preserving keys not included in the update.

### Retrieving State

```dart
// Get immutable state (type-safe)
final myState = StateManager().getModuleState<MyState>('my_module');

// Get map-based state
final mapState = StateManager().getModuleState<Map<String, dynamic>>('legacy_module');

// Get all module states
final allStates = StateManager().getAllModuleStates();
```

## Change Detection

### How It Works

The `StateManager` uses a sophisticated change detection algorithm:

1. **Reference Equality Check** (for immutable state):
   ```dart
   if (identical(existingState.state, newState)) {
     // No change, skip update
     return;
   }
   ```

2. **Structural Equality Check** (for immutable state):
   ```dart
   if (existingState.state == newState) {
     // No change, skip update
     return;
   }
   ```

3. **Map Merge** (for map-based state):
   - Merges new keys with existing state
   - Only notifies listeners if the merged result is different

### Performance Considerations

- **Reference Equality**: O(1) - extremely fast for identical objects
- **Structural Equality**: O(n) - depends on object size, but only runs when reference equality fails
- **Map Merge**: O(m) - where m is the number of keys being updated

The system is optimized to minimize unnecessary work by checking reference equality first.

## State Utilities

The `state_utils.dart` file provides helper functions for immutable operations:

### List Operations

```dart
// Update item at index
final newList = updateList(list, 0, newItem);

// Update item with function
final newList = updateListWith(list, 0, (item) => item.copyWith(updated: true));

// Add item
final newList = addToList(list, newItem);

// Remove item
final newList = removeFromList(list, 0);
```

### Map Operations

```dart
// Update value
final newMap = updateMap(map, 'key', newValue);

// Update value with function
final newMap = updateMapWith(map, 'key', (value) => value + 1);

// Remove key
final newMap = removeFromMap(map, 'key');
```

### Equality and Hashing

```dart
// Deep equality check
final isEqual = deepEquals(obj1, obj2);

// Hash code for lists
final hash = listHashCode(list);

// Hash code for maps
final hash = mapHashCode(map);
```

## Widget Integration

### Listening to State Changes

Widgets can listen to state changes using `ListenableBuilder`:

```dart
ListenableBuilder(
  listenable: StateManager(),
  builder: (context, _) {
    final state = StateManager().getModuleState<MyState>('my_module');
    return Text(state?.name ?? 'Loading...');
  },
)
```

### Best Practices

1. **Minimize Rebuilds**: Only listen to the specific state you need
2. **Use Type-Safe Access**: Prefer `getModuleState<T>()` over map access
3. **Avoid Direct Mutations**: Always use `copyWith()` or `updateModuleState()`
4. **Batch Updates**: Group related state changes into a single update when possible

## Migration Guide

### From Map-Based to Immutable State

1. **Create Immutable State Class**:
   ```dart
   @immutable
   class MyModuleState extends ImmutableState with EquatableMixin {
     final String data;
     
     const MyModuleState({required this.data});
     
     @override
     List<Object?> get props => [data];
     
     @override
     MyModuleState copyWith({String? data}) {
       return MyModuleState(data: data ?? this.data);
     }
     
     @override
     Map<String, dynamic> toJson() => {'data': data};
   }
   ```

2. **Update Registration**:
   ```dart
   // Before
   StateManager().registerModuleState('my_module', {});
   
   // After
   StateManager().registerModuleState('my_module', MyModuleState(data: ''));
   ```

3. **Update State Updates**:
   ```dart
   // Before
   StateManager().updateModuleState('my_module', {'data': 'new'});
   
   // After
   final current = StateManager().getModuleState<MyModuleState>('my_module');
   StateManager().updateModuleState('my_module', current.copyWith(data: 'new'));
   ```

4. **Update State Retrieval**:
   ```dart
   // Before
   final state = StateManager().getModuleState<Map<String, dynamic>>('my_module');
   final data = state?['data'];
   
   // After
   final state = StateManager().getModuleState<MyModuleState>('my_module');
   final data = state?.data;
   ```

## Benefits

### Type Safety

Immutable state objects provide compile-time type checking, catching errors early:

```dart
// Compile error: 'name' doesn't exist
final name = state.nam; // ❌

// Works correctly
final name = state.name; // ✅
```

### Predictable Updates

State changes are explicit and traceable:

```dart
// Clear intent: creating new state with updated name
final newState = currentState.copyWith(name: 'New Name');
```

### Performance

Efficient change detection minimizes unnecessary rebuilds:

- Reference equality checks are O(1)
- Structural equality only runs when needed
- Widgets only rebuild when state actually changes

### Debugging

Immutable state enables powerful debugging:

- Previous states are preserved
- State changes are explicit and traceable
- Time-travel debugging is possible

## Limitations and Considerations

### Memory Usage

Immutable state creates new objects for each update, which can increase memory usage. However, this is typically negligible compared to the benefits.

### Migration Effort

Migrating from map-based to immutable state requires:
- Creating state classes
- Updating all state access points
- Testing thoroughly

The hybrid system allows gradual migration, reducing risk.

### Backward Compatibility

The system maintains backward compatibility with map-based state, but:
- Map-based state doesn't benefit from type safety
- Change detection is less efficient for maps
- Consider migrating to immutable state for new features

## Future Enhancements

Potential improvements to the state management system:

1. **State Persistence**: Automatic persistence of state to disk
2. **State Time-Travel**: Built-in support for undo/redo
3. **State DevTools**: Visual debugging tools for state
4. **State Middleware**: Intercept and modify state updates
5. **State Selectors**: Efficient derived state computation

## Summary

The Flutter Base 05 state management system provides:

- ✅ **Type Safety**: Compile-time checking with immutable state objects
- ✅ **Efficient Change Detection**: Reference and structural equality checks
- ✅ **Backward Compatibility**: Support for legacy map-based state
- ✅ **Predictable Updates**: Explicit state changes via `copyWith()`
- ✅ **Performance**: Optimized to minimize unnecessary work
- ✅ **Developer Experience**: Clear patterns and utilities

The system is designed to scale with your application while maintaining simplicity and performance.

