import '../00_base/adapter_base.dart';
import '../ext_plugins_adapters/revenuecat/revenuecat_adapter.dart';

/// Registry for all adapters in the application
/// Automatically registers and manages all adapters
class AdapterRegistry {
  static final AdapterRegistry _instance = AdapterRegistry._internal();
  
  final List<AdapterBase> _registeredAdapters = [];
  
  factory AdapterRegistry() => _instance;
  AdapterRegistry._internal();

  /// Register all adapters automatically
  void registerAllAdapters() {
    // Register RevenueCat adapter
    _registerAdapter(RevenueCatAdapter());
    
    // Add more adapters here as needed
    // _registerAdapter(SomeOtherAdapter());
    // _registerAdapter(AnotherAdapter());
  }

  /// Register a single adapter
  void _registerAdapter(AdapterBase adapter) {
    _registeredAdapters.add(adapter);
  }

  /// Get all registered adapters
  List<AdapterBase> get registeredAdapters => List.unmodifiable(_registeredAdapters);

  /// Get adapter by key
  AdapterBase? getAdapterByKey(String adapterKey) {
    for (final adapter in _registeredAdapters) {
      if (adapter.adapterKey == adapterKey) {
        return adapter;
      }
    }
    return null;
  }

  /// Get adapter by type
  T? getAdapterByType<T extends AdapterBase>() {
    for (final adapter in _registeredAdapters) {
      if (adapter is T) {
        return adapter;
      }
    }
    return null;
  }

  /// Get health status of all adapters
  Map<String, dynamic> getHealthStatus() {
    final health = <String, dynamic>{};
    
    for (final adapter in _registeredAdapters) {
      health[adapter.adapterKey] = adapter.healthCheck();
    }
    
    return health;
  }

  /// Clear all registered adapters (for testing)
  void clear() {
    _registeredAdapters.clear();
  }
} 