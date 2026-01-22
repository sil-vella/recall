/// Utility functions for immutable state operations
/// 
/// These helpers make it easier to work with immutable collections
/// by providing convenient methods for common operations that return
/// new instances rather than mutating existing ones.

/// Update an item in a list immutably
/// Returns a new list with the item at [index] replaced with [item]
List<T> updateList<T>(List<T> list, int index, T item) {
  if (index < 0 || index >= list.length) {
    throw RangeError.index(index, list, 'index', 'Index out of range');
  }
  
  final newList = List<T>.of(list);
  newList[index] = item;
  return newList;
}

/// Update an item in a list by applying a function
/// Returns a new list with the item at [index] transformed by [updater]
List<T> updateListWith<T>(List<T> list, int index, T Function(T) updater) {
  if (index < 0 || index >= list.length) {
    throw RangeError.index(index, list, 'index', 'Index out of range');
  }
  
  return updateList(list, index, updater(list[index]));
}

/// Add an item to a list immutably
/// Returns a new list with [item] added at the end
List<T> addToList<T>(List<T> list, T item) {
  return [...list, item];
}

/// Insert an item into a list immutably
/// Returns a new list with [item] inserted at [index]
List<T> insertInList<T>(List<T> list, int index, T item) {
  if (index < 0 || index > list.length) {
    throw RangeError.index(index, list, 'index', 'Index out of range');
  }
  
  return [...list.sublist(0, index), item, ...list.sublist(index)];
}

/// Remove an item from a list immutably
/// Returns a new list with the item at [index] removed
List<T> removeFromList<T>(List<T> list, int index) {
  if (index < 0 || index >= list.length) {
    throw RangeError.index(index, list, 'index', 'Index out of range');
  }
  
  return [...list.sublist(0, index), ...list.sublist(index + 1)];
}

/// Remove items from a list that match a predicate
/// Returns a new list with matching items removed
List<T> removeWhere<T>(List<T> list, bool Function(T) test) {
  return list.where((item) => !test(item)).toList();
}

/// Update a value in a map immutably
/// Returns a new map with [key] set to [value]
Map<K, V> updateMap<K, V>(Map<K, V> map, K key, V value) {
  return {...map, key: value};
}

/// Update a value in a map by applying a function
/// Returns a new map with the value at [key] transformed by [updater]
/// If the key doesn't exist, returns the original map
Map<K, V> updateMapWith<K, V>(Map<K, V> map, K key, V Function(V) updater) {
  if (!map.containsKey(key)) return map;
  return updateMap(map, key, updater(map[key] as V));
}

/// Remove a key from a map immutably
/// Returns a new map without [key]
Map<K, V> removeFromMap<K, V>(Map<K, V> map, K key) {
  final newMap = Map<K, V>.of(map);
  newMap.remove(key);
  return newMap;
}

/// Deep equality comparison for dynamic values
/// Handles primitives, lists, maps, and objects with == operator
bool deepEquals(dynamic a, dynamic b) {
  // Handle null cases
  if (a == null) return b == null;
  if (b == null) return false;
  
  // Handle identical references (fast path)
  if (identical(a, b)) return true;
  
  // Handle different types
  if (a.runtimeType != b.runtimeType) return false;
  
  // Handle primitives and objects with == operator
  if (a is! List && a is! Map) {
    return a == b;
  }
  
  // Handle lists
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  
  // Handle maps
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  
  // Fallback to equality operator
  return a == b;
}

/// Calculate hash code for a list (order-dependent)
int listHashCode(List<dynamic> list) {
  return Object.hashAll(list);
}

/// Calculate hash code for a map (order-independent)
int mapHashCode(Map<dynamic, dynamic> map) {
  // For maps, we need order-independent hashing
  // Combine hashes of all entries
  var hash = 0;
  for (final entry in map.entries) {
    // XOR is commutative, so order doesn't matter
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}

/// Deep clone a value (creates new instances of collections)
/// Note: This is mainly for migration purposes - prefer immutable updates
dynamic deepClone(dynamic value) {
  if (value == null) return null;
  
  if (value is List) {
    return value.map((item) => deepClone(item)).toList();
  }
  
  if (value is Map) {
    return value.map((key, val) => MapEntry(key, deepClone(val)));
  }
  
  // Primitives and other objects are returned as-is
  return value;
}

