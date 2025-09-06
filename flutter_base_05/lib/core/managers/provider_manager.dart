import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
import 'app_manager.dart';
import 'module_manager.dart';
import 'services_manager.dart';
import 'state_manager.dart';
import 'navigation_manager.dart';
import 'auth_manager.dart';

/// Provider Manager - Centralized provider registration system
/// Allows modules to register their own providers dynamically
class ProviderManager {
  static final Logger _log = Logger();
  static final ProviderManager _instance = ProviderManager._internal();
  
  factory ProviderManager() => _instance;
  ProviderManager._internal();

  // Registry of providers that modules can register
  final List<ChangeNotifierProvider> _registeredProviders = [];
  final Map<String, ChangeNotifierProvider> _namedProviders = {};

  /// Register a provider for a module
  void registerProvider<T extends ChangeNotifier>(
    ChangeNotifierProvider<T> provider, {
    String? name,
  }) {
    _registeredProviders.add(provider);
    
    if (name != null) {
      _namedProviders[name] = provider;
    }
  }

  /// Register a provider with a factory function
  void registerProviderFactory<T extends ChangeNotifier>(
    T Function(BuildContext) factory, {
    String? name,
  }) {
    final provider = ChangeNotifierProvider<T>(create: factory);
    registerProvider(provider, name: name);
  }

  /// Register a provider with a simple create function
  void registerProviderCreate<T extends ChangeNotifier>(
    T Function() create, {
    String? name,
  }) {
    final provider = ChangeNotifierProvider<T>(create: (_) => create());
    registerProvider(provider, name: name);
  }

  /// Register core providers (AppManager, StateManager, etc.)
  void registerCoreProviders() {
    // Register core managers as providers
    registerProviderCreate(
      () => AppManager(),
      name: 'app_manager',
    );
    
    registerProviderCreate(
      () => ModuleManager(),
      name: 'module_manager',
    );
    
    registerProviderCreate(
      () => ServicesManager(),
      name: 'services_manager',
    );
    
    registerProviderCreate(
      () => StateManager(),
      name: 'state_manager',
    );
    
    registerProviderCreate(
      () => NavigationManager(),
      name: 'navigation_manager',
    );
    
    registerProviderCreate(
      () => AuthManager(),
      name: 'auth_manager',
    );
  }

  /// Get all registered providers
  List<ChangeNotifierProvider> get providers => List.unmodifiable(_registeredProviders);

  /// Get a specific named provider
  ChangeNotifierProvider? getNamedProvider(String name) {
    return _namedProviders[name];
  }

  /// Check if a provider is registered
  bool isProviderRegistered<T extends ChangeNotifier>() {
    return _registeredProviders.any((provider) => provider is ChangeNotifierProvider<T>);
  }

  /// Check if a named provider is registered
  bool isNamedProviderRegistered(String name) {
    return _namedProviders.containsKey(name);
  }

  /// Clear all registered providers
  void clearProviders() {
    _registeredProviders.clear();
    _namedProviders.clear();
  }

  /// Get provider count
  int get providerCount => _registeredProviders.length;

  /// Get registered provider names
  List<String> get registeredProviderNames => _namedProviders.keys.toList();

  /// Log all registered providers
  void logRegisteredProviders() {
    // Logging functionality removed
  }
} 