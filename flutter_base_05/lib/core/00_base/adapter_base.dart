import 'package:flutter/material.dart';
import '../managers/app_manager.dart';
import '../managers/state_manager.dart';
import '../managers/hooks_manager.dart';
import '../managers/auth_manager.dart';
import '../../tools/logging/logger.dart';

/// Base class for all adapters that integrate external services
/// Provides access to AppManager and common functionality
abstract class AdapterBase {
  static final Logger _log = Logger();
  
  late AppManager _appManager;
  bool _isInitialized = false;
  
  /// Get the adapter key (unique identifier)
  String get adapterKey;
  
  /// Get adapter dependencies (other adapters this depends on)
  List<String> get dependencies => [];
  
  /// Get adapter status
  bool get isInitialized => _isInitialized;
  
  /// Initialize the adapter with AppManager
  Future<void> initialize(AppManager appManager) async {
    if (_isInitialized) return;
    
    _appManager = appManager;
    _log.info('🔧 Initializing adapter: $adapterKey');
    
    try {
      await _initializeAdapter();
      _isInitialized = true;
      _log.info('✅ Adapter initialized: $adapterKey');
    } catch (e) {
      _log.error('❌ Error initializing adapter $adapterKey: $e');
      rethrow;
    }
  }
  
  /// Initialize adapter-specific logic (to be implemented by subclasses)
  Future<void> _initializeAdapter();
  
  /// Get AppManager instance
  AppManager get appManager => _appManager;
  
  /// Get StateManager instance
  StateManager get stateManager => StateManager();
  
  /// Get HooksManager instance
  HooksManager get hooksManager => HooksManager();
  
  /// Get AuthManager instance
  AuthManager get authManager => AuthManager();
  
  /// Health check for the adapter
  Map<String, dynamic> healthCheck() {
    return {
      'adapter': adapterKey,
      'status': _isInitialized ? 'healthy' : 'not_initialized',
      'dependencies': dependencies,
    };
  }
  
  /// Dispose adapter resources
  void dispose() {
    _log.info('🛑 Disposing adapter: $adapterKey');
    _isInitialized = false;
  }
} 