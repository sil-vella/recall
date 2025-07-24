import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../tools/logging/logger.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/auth_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../managers/navigation_manager.dart';
import '../../../managers/event_bus.dart';
import '../../app_init/app_initializer.dart';

/// Module Orchestrator Base
/// 
/// Base class for all module orchestrators in Flutter.
/// Handles common manager access and orchestrator management.
abstract class ModuleOrchestratorBase {
  static final Logger _log = Logger();
  
  // Access to existing manager instances through AppInitializer
  late AppInitializer _appInitializer;
  
  // Orchestrator registry
  final Map<String, ModuleOrchestratorBase> _orchestrators = {};
  
  /// Initialize the orchestrator with context
  void initialize(BuildContext context) {
    _log.info('🔧 Initializing ${runtimeType.toString()}...');
    
    try {
      // Get existing manager instances from AppInitializer
      _appInitializer = Provider.of<AppInitializer>(context, listen: false);
      
      // Initialize sub-orchestrators
      _initializeSubOrchestrators(context);
      
      // Initialize the specific orchestrator
      _initializeOrchestrator(context);
      
      // Register hooks and routes
      _registerHooks();
      _registerRoutes();
      
      _log.info('✅ ${runtimeType.toString()} initialized successfully');
      
    } catch (e) {
      _log.error('❌ Error initializing ${runtimeType.toString()}: $e');
      rethrow;
    }
  }
  
  /// Initialize sub-orchestrators
  void _initializeSubOrchestrators(BuildContext context) {
    // Override in subclasses to initialize specific orchestrators
    // For example: _registerOrchestrator('in_app_purchases', InAppPurchasesOrchestrator());
  }
  
  /// Initialize the specific orchestrator implementation
  void _initializeOrchestrator(BuildContext context);
  
  /// Register hooks for this orchestrator
  void _registerHooks();
  
  /// Register routes for this orchestrator
  void _registerRoutes();
  
  /// Register a sub-orchestrator
  void _registerOrchestrator(String key, ModuleOrchestratorBase orchestrator) {
    if (_orchestrators.containsKey(key)) {
      _log.error('❌ Orchestrator with key "$key" is already registered.');
      return;
    }
    
    _orchestrators[key] = orchestrator;
    _log.info('✅ Sub-orchestrator registered: $key');
  }
  
  /// Get a sub-orchestrator by key
  ModuleOrchestratorBase? getOrchestrator(String key) {
    final orchestrator = _orchestrators[key];
    if (orchestrator == null) {
      _log.error('❌ Sub-orchestrator "$key" is not registered.');
    }
    return orchestrator;
  }
  
  /// Get all registered sub-orchestrators
  Map<String, ModuleOrchestratorBase> get orchestrators => _orchestrators;
  
  /// Health check for this orchestrator
  Map<String, dynamic> healthCheck() {
    return {
      'orchestrator': runtimeType.toString(),
      'status': 'healthy',
      'sub_orchestrators': _orchestrators.length,
      'details': 'Orchestrator is functioning normally'
    };
  }
  
  /// Get orchestrator status
  Map<String, dynamic> getOrchestratorStatus() {
    final status = {
      'total_orchestrators': _orchestrators.length,
      'initialized_orchestrators': 0,
      'orchestrator_errors': <String, dynamic>{},
      'orchestrators': <String, dynamic>{}
    };
    
    for (final entry in _orchestrators.entries) {
      final key = entry.key;
      final orchestrator = entry.value;
      
      try {
        final healthCheck = orchestrator.healthCheck();
        (status['orchestrators'] as Map<String, dynamic>)[key] = healthCheck;
        
        if (healthCheck['status'] == 'healthy') {
          status['initialized_orchestrators'] = (status['initialized_orchestrators'] as int) + 1;
        } else {
          (status['orchestrator_errors'] as Map<String, dynamic>)[key] = healthCheck['error'] ?? 'Unknown error';
        }
      } catch (e) {
        (status['orchestrator_errors'] as Map<String, dynamic>)[key] = e.toString();
      }
    }
    
    return status;
  }
  
  /// Check if all sub-orchestrators are healthy
  bool checkOrchestratorHealth() {
    final status = getOrchestratorStatus();
    final totalOrchestrators = status['total_orchestrators'] as int;
    final initializedOrchestrators = status['initialized_orchestrators'] as int;
    final errors = status['orchestrator_errors'] as Map<String, dynamic>;
    
    return totalOrchestrators > 0 && 
           initializedOrchestrators == totalOrchestrators && 
           errors.isEmpty;
  }
  
  /// Dispose orchestrator resources
  void dispose() {
    _log.info('🧹 Disposing ${runtimeType.toString()}...');
    
    // Dispose all sub-orchestrators
    for (final orchestrator in _orchestrators.values) {
      try {
        orchestrator.dispose();
      } catch (e) {
        _log.error('❌ Error disposing sub-orchestrator: $e');
      }
    }
    
    // Clear orchestrators
    _orchestrators.clear();
    
    _log.info('✅ ${runtimeType.toString()} disposed successfully');
  }
  
  // Getters for existing manager instances
  HooksManager get hooksManager => _appInitializer.hooksManager;
  StateManager get stateManager => _appInitializer.stateManager;
  AuthManager get authManager => _appInitializer.authManager;
  ServicesManager get servicesManager => _appInitializer.servicesManager;
  NavigationManager get navigationManager => _appInitializer.navigationManager;
  EventBus get eventBus => _appInitializer.eventBus;
} 