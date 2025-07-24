import 'package:flutter/material.dart';
import '../../../tools/logging/logger.dart';
import 'app_initializer.dart';

/// Health Checker
/// 
/// This class handles health checking for all application components.
/// It provides methods to check the health of managers, modules, and other critical system components.
class HealthChecker {
  static final Logger _log = Logger();
  
  final AppInitializer appInitializer;
  
  HealthChecker(this.appInitializer) {
    _log.info('HealthChecker created');
  }
  
  /// Check if all managers are healthy
  bool checkManagersHealth() {
    _log.info('🔍 Checking managers health...');
    
    try {
      final managers = [
        appInitializer.hooksManager,
        appInitializer.authManager,
        appInitializer.stateManager,
        appInitializer.servicesManager,
        appInitializer.navigationManager,
        appInitializer.eventBus,
      ];
      
      for (final manager in managers) {
        if (manager == null) {
          _log.error('❌ Manager is null');
          return false;
        }
      }
      
      _log.info('✅ All managers are healthy');
      return true;
      
    } catch (e) {
      _log.error('❌ Managers health check failed: $e');
      return false;
    }
  }
  
  /// Check orchestrator health
  Map<String, dynamic> checkOrchestratorHealth() {
    _log.info('🔍 Checking orchestrator health...');
    
    try {
      final status = appInitializer.getOrchestratorStatus();
      final isHealthy = appInitializer.checkOrchestratorHealth();
      
      if (isHealthy) {
        _log.info('✅ All orchestrators are healthy');
      } else {
        _log.warning('⚠️ Some orchestrators are unhealthy');
      }
      
      return {
        'status': isHealthy ? 'healthy' : 'unhealthy',
        'details': status,
      };
      
    } catch (e) {
      _log.error('❌ Orchestrator health check failed: $e');
      return {
        'status': 'error',
        'error': e.toString(),
      };
    }
  }
  
  /// Check module health by key
  Map<String, dynamic> checkModuleHealth(String moduleKey) {
    _log.info('🔍 Checking module health: $moduleKey');
    
    try {
      final orchestrator = appInitializer.getOrchestrator(moduleKey);
      
      if (orchestrator == null) {
        return {
          'status': 'unhealthy',
          'reason': 'Module orchestrator not found',
          'module_key': moduleKey,
        };
      }
      
      final healthCheck = orchestrator.healthCheck();
      return healthCheck;
      
    } catch (e) {
      _log.error('❌ Module health check failed for $moduleKey: $e');
      return {
        'status': 'error',
        'error': e.toString(),
        'module_key': moduleKey,
      };
    }
  }
  
  /// Check all modules health
  Map<String, dynamic> checkAllModulesHealth() {
    _log.info('🔍 Checking all modules health...');
    
    final results = <String, dynamic>{};
    final orchestrators = appInitializer.orchestrators;
    
    for (final entry in orchestrators.entries) {
      final key = entry.key;
      results[key] = checkModuleHealth(key);
    }
    
    final healthyCount = results.values.where((r) => r['status'] == 'healthy').length;
    final totalCount = results.length;
    
    _log.info('📊 Module health summary: $healthyCount/$totalCount healthy');
    
    return {
      'total_modules': totalCount,
      'healthy_modules': healthyCount,
      'unhealthy_modules': totalCount - healthyCount,
      'modules': results,
    };
  }
  
  /// Comprehensive health check
  Map<String, dynamic> comprehensiveHealthCheck(BuildContext context) {
    _log.info('🔍 Running comprehensive health check...');
    
    try {
      final managersHealth = checkManagersHealth();
      final orchestratorHealth = checkOrchestratorHealth();
      final modulesHealth = checkAllModulesHealth();
      
      final isHealthy = managersHealth && 
                       orchestratorHealth['status'] == 'healthy' &&
                       modulesHealth['healthy_modules'] == modulesHealth['total_modules'];
      
      final result = {
        'overall_status': isHealthy ? 'healthy' : 'unhealthy',
        'timestamp': DateTime.now().toIso8601String(),
        'managers_health': managersHealth,
        'orchestrator_health': orchestratorHealth,
        'modules_health': modulesHealth,
        'app_initialized': appInitializer.isInitialized,
      };
      
      if (isHealthy) {
        _log.info('✅ Comprehensive health check passed');
      } else {
        _log.warning('⚠️ Comprehensive health check failed');
      }
      
      return result;
      
    } catch (e) {
      _log.error('❌ Comprehensive health check failed: $e');
      return {
        'overall_status': 'error',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
  
  /// Quick health check for critical components
  bool quickHealthCheck() {
    _log.info('🔍 Running quick health check...');
    
    try {
      final managersHealthy = checkManagersHealth();
      final appInitialized = appInitializer.isInitialized;
      
      final isHealthy = managersHealthy && appInitialized;
      
      if (isHealthy) {
        _log.info('✅ Quick health check passed');
      } else {
        _log.warning('⚠️ Quick health check failed');
      }
      
      return isHealthy;
      
    } catch (e) {
      _log.error('❌ Quick health check failed: $e');
      return false;
    }
  }
} 