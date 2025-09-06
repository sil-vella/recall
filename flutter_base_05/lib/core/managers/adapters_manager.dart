import '../00_base/adapter_base.dart';
import 'app_manager.dart';
import 'adapter_registry.dart';

/// Manages external service adapters (RevenueCat, etc.)
/// Similar to ModuleManager but for external integrations
class AdaptersManager {
  static final AdaptersManager _instance = AdaptersManager._internal();
  
  final Map<String, AdapterBase> _adapters = {};
  final Map<String, bool> _initializedAdapters = {};
  late AppManager _appManager;
  final AdapterRegistry _adapterRegistry = AdapterRegistry();
  
  factory AdaptersManager() => _instance;
  AdaptersManager._internal();

  /// Initialize adapters manager with AppManager
  void initialize(AppManager appManager) {
    _appManager = appManager;
    
    // Register all adapters from registry
    _adapterRegistry.registerAllAdapters();
    
    // Add all registered adapters to the manager
    for (final adapter in _adapterRegistry.registeredAdapters) {
      _adapters[adapter.adapterKey] = adapter;
      _initializedAdapters[adapter.adapterKey] = false;
    }
    
  }

  /// Register an adapter (for manual registration if needed)
  void registerAdapter(AdapterBase adapter) {
    if (_adapters.containsKey(adapter.adapterKey)) {
      return;
    }
    
    _adapters[adapter.adapterKey] = adapter;
    _initializedAdapters[adapter.adapterKey] = false;
  }

  /// Initialize all registered adapters
  Future<void> initializeAdapters() async {
    // Initialize adapters in dependency order
    final sortedAdapters = _sortAdaptersByDependencies();
    
    for (final adapter in sortedAdapters) {
      try {
        await adapter.initialize(_appManager);
        _initializedAdapters[adapter.adapterKey] = true;
      } catch (e) {
        _initializedAdapters[adapter.adapterKey] = false;
      }
    }
  }

  /// Sort adapters by dependencies
  List<AdapterBase> _sortAdaptersByDependencies() {
    final List<AdapterBase> sorted = [];
    final Set<String> visited = {};
    final Set<String> visiting = {};
    
    void visit(AdapterBase adapter) {
      if (visited.contains(adapter.adapterKey)) return;
      if (visiting.contains(adapter.adapterKey)) {
        throw Exception('Circular dependency detected in adapters');
      }
      
      visiting.add(adapter.adapterKey);
      
      // Visit dependencies first
      for (final depKey in adapter.dependencies) {
        final dep = _adapters[depKey];
        if (dep != null) {
          visit(dep);
        }
      }
      
      visiting.remove(adapter.adapterKey);
      visited.add(adapter.adapterKey);
      sorted.add(adapter);
    }
    
    for (final adapter in _adapters.values) {
      visit(adapter);
    }
    
    return sorted;
  }

  /// Get adapter by key
  AdapterBase? getAdapter(String adapterKey) {
    return _adapters[adapterKey];
  }

  /// Get adapter by type
  T? getAdapterByType<T extends AdapterBase>() {
    for (final adapter in _adapters.values) {
      if (adapter is T) {
        return adapter;
      }
    }
    return null;
  }

  /// Check if adapter is initialized
  bool isAdapterInitialized(String adapterKey) {
    return _initializedAdapters[adapterKey] ?? false;
  }

  /// Get all adapters
  Map<String, AdapterBase> get adapters => Map.unmodifiable(_adapters);

  /// Get health status of all adapters
  Map<String, dynamic> getHealthStatus() {
    final health = <String, dynamic>{};
    
    for (final entry in _adapters.entries) {
      health[entry.key] = entry.value.healthCheck();
    }
    
    return health;
  }

  /// Dispose all adapters
  void dispose() {
    for (final adapter in _adapters.values) {
      adapter.dispose();
    }
    
    _adapters.clear();
    _initializedAdapters.clear();
  }
} 