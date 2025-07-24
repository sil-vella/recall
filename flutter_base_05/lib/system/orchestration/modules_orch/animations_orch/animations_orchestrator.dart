import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../services/shared_preferences.dart';
import '../base_files/module_orch_base.dart';
import '../../../../modules/animations_module/animations_module.dart';

/// Animations Orchestrator - Handles system integration for animations
/// Delegates business logic to pure modules
class AnimationsOrchestrator extends ModuleOrchestratorBase {
  static final Logger _log = Logger();
  
  // Pure business logic module
  late AnimationsModule _animationsModule;
  
  // Flutter-specific animation controllers
  final List<AnimationController> _controllers = [];
  final Map<String, ConfettiController> _confettiControllers = {};

  @override
  void initialize(BuildContext context) {
    _log.info('🎼 Initializing Animations Orchestrator...');
    
    // Initialize pure business logic module
    _animationsModule = AnimationsModule();
    
    // Register hooks and routes
    _registerHooks();
    _registerRoutes();
    
    _log.info('✅ Animations Orchestrator initialized successfully');
  }

  @override
  void _registerHooks() {
    _log.info('🔗 Registering Animations hooks...');
    
    // Register hooks from animations module
    final animationsHooks = _animationsModule.getHooksNeeded();
    for (final hook in animationsHooks) {
      hooksManager.registerHookWithData(hook['hookName'], (data) {
        _log.info('📢 ${hook['hookName']} hook triggered');
        _handleAnimationHook(hook['hookName'], data);
      }, priority: hook['priority']);
    }
    
    _log.info('✅ Animations hooks registered successfully');
  }

  @override
  void _registerRoutes() {
    _log.info('🛣️ Registering Animations routes...');
    
    // Register routes from animations module
    final animationsRoutes = _animationsModule.getRoutesNeeded();
    
    for (final route in animationsRoutes) {
      _log.info('🛣️ Route: ${route['method']} ${route['route']} - ${route['description']}');
      // Routes would be registered with navigation system here
    }
    
    _log.info('✅ Animations routes registered successfully');
  }

  /// Handle animation hooks
  void _handleAnimationHook(String hookName, Map<String, dynamic> data) {
    switch (hookName) {
      case 'animation_success':
        _playSuccessAnimation();
        break;
      case 'animation_celebration':
        _playCelebrationAnimation();
        break;
      case 'animation_level_up':
        _playLevelUpAnimation();
        break;
      case 'animation_stop_all':
        _stopAllAnimations();
        break;
    }
  }

  /// Play confetti animation with system integration
  void _playConfetti({required String key, Duration? duration}) {
    _log.info('🎉 Playing confetti animation: $key');
    
    // Call business logic module
    final result = _animationsModule.playConfetti(key: key, duration: duration);
    
    if (result['success']) {
      // Create actual Flutter ConfettiController
      final confettiController = ConfettiController(
        duration: Duration(milliseconds: result['animationData']['duration']),
      );
      
      _confettiControllers[key] = confettiController;
      confettiController.play();
      
      // Update state
      stateManager.updateModuleState('animations', {
        'activeAnimations': _getActiveAnimationsList(),
        'lastPlayed': key,
        'animationData': result['animationData'],
      });
      
      _log.info('✅ Confetti animation started: $key');
    }
  }

  /// Stop confetti animation with system integration
  void _stopConfetti({required String key}) {
    _log.info('⏹️ Stopping confetti animation: $key');
    
    // Call business logic module
    final result = _animationsModule.stopConfetti(key: key);
    
    if (result['success']) {
      // Stop actual Flutter ConfettiController
      final confettiController = _confettiControllers[key];
      if (confettiController != null) {
        confettiController.stop();
      }
      
      // Update state
      stateManager.updateModuleState('animations', {
        'activeAnimations': _getActiveAnimationsList(),
        'lastStopped': key,
      });
      
      _log.info('✅ Confetti animation stopped: $key');
    }
  }

  /// Play success animation
  void _playSuccessAnimation() {
    _log.info('✅ Playing success animation');
    
    // Call business logic module
    final result = _animationsModule.playSuccessAnimation();
    
    if (result['success']) {
      _playConfetti(key: 'success');
      
      // Update state
      stateManager.updateModuleState('animations', {
        'lastSuccessAnimation': DateTime.now().toIso8601String(),
        'animationType': 'success',
      });
    }
  }

  /// Play celebration animation
  void _playCelebrationAnimation() {
    _log.info('🎉 Playing celebration animation');
    
    // Call business logic module
    final result = _animationsModule.playCelebrationAnimation();
    
    if (result['success']) {
      _playConfetti(key: 'celebration');
      
      // Update state
      stateManager.updateModuleState('animations', {
        'lastCelebrationAnimation': DateTime.now().toIso8601String(),
        'animationType': 'celebration',
      });
    }
  }

  /// Play level up animation
  void _playLevelUpAnimation() {
    _log.info('📈 Playing level up animation');
    
    // Call business logic module
    final result = _animationsModule.playLevelUpAnimation();
    
    if (result['success']) {
      _playConfetti(key: 'level_up');
      
      // Update state
      stateManager.updateModuleState('animations', {
        'lastLevelUpAnimation': DateTime.now().toIso8601String(),
        'animationType': 'level_up',
      });
    }
  }

  /// Stop all animations
  void _stopAllAnimations() {
    _log.info('⏹️ Stopping all animations');
    
    // Call business logic module
    final result = _animationsModule.stopAllAnimations();
    
    if (result['success']) {
      // Stop all Flutter ConfettiControllers
      for (final controller in _confettiControllers.values) {
        controller.stop();
      }
      
      // Update state
      stateManager.updateModuleState('animations', {
        'activeAnimations': [],
        'allStoppedAt': DateTime.now().toIso8601String(),
      });
      
      _log.info('✅ All animations stopped');
    }
  }

  /// Get list of active animations
  List<String> _getActiveAnimationsList() {
    return _confettiControllers.keys.toList();
  }

  /// Register AnimationController for cleanup
  void registerController(AnimationController controller) {
    _controllers.add(controller);
    _log.info('✅ Registered AnimationController: $controller');
  }

  /// Create confetti controller with system integration
  ConfettiController createConfettiController({Duration? duration}) {
    _log.info('🎉 Creating confetti controller');
    
    // Call business logic module
    final result = _animationsModule.createConfettiController(duration: duration);
    
    if (result['success']) {
      // Create actual Flutter ConfettiController
      final confettiController = ConfettiController(
        duration: Duration(milliseconds: result['controllerData']['duration']),
      );
      
      final key = result['key'];
      _confettiControllers[key] = confettiController;
      
      // Update state
      stateManager.updateModuleState('animations', {
        'controllers': _confettiControllers.keys.toList(),
        'lastCreatedController': key,
      });
      
      _log.info('✅ Confetti controller created: $key');
      return confettiController;
    } else {
      throw Exception('Failed to create confetti controller');
    }
  }

  /// Get confetti controller by key
  ConfettiController? getConfettiController(String key) {
    return _confettiControllers[key];
  }

  /// Remove confetti controller
  void removeConfettiController(String key) {
    _log.info('🗑️ Removing confetti controller: $key');
    
    // Call business logic module
    final result = _animationsModule.removeConfettiController(key);
    
    if (result['success']) {
      // Dispose actual Flutter ConfettiController
      final confettiController = _confettiControllers[key];
      if (confettiController != null) {
        confettiController.dispose();
        _confettiControllers.remove(key);
      }
      
      // Update state
      stateManager.updateModuleState('animations', {
        'controllers': _confettiControllers.keys.toList(),
        'lastRemovedController': key,
      });
      
      _log.info('✅ Confetti controller removed: $key');
    }
  }

  /// Get animation status
  Map<String, dynamic> getAnimationStatus(String key) {
    final result = _animationsModule.getAnimationStatus(key);
    final confettiController = _confettiControllers[key];
    
    result['hasFlutterController'] = confettiController != null;
    result['isFlutterControllerPlaying'] = confettiController?.state == ConfettiControllerState.playing;
    
    return result;
  }

  /// Get all active animations
  Map<String, dynamic> getAllActiveAnimations() {
    final result = _animationsModule.getAllActiveAnimations();
    result['flutterControllers'] = _confettiControllers.keys.toList();
    result['animationControllers'] = _controllers.length;
    
    return result;
  }

  /// Get animation statistics
  Map<String, dynamic> getAnimationStatistics() {
    final result = _animationsModule.getAnimationStatistics();
    result['flutterControllers'] = _confettiControllers.length;
    result['animationControllers'] = _controllers.length;
    
    return result;
  }

  /// Health check
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': 'animations_orchestrator',
      'status': 'healthy',
      'details': 'Animations orchestrator is running',
      'confetti_controllers': _confettiControllers.length,
      'animation_controllers': _controllers.length,
      'active_animations': _getActiveAnimationsList().length,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _log.info('🗑 Disposing Animations Orchestrator...');
    
    // Stop all confetti controllers
    for (final controller in _confettiControllers.values) {
      controller.stop();
      controller.dispose();
    }
    _confettiControllers.clear();
    
    // Dispose all animation controllers
    for (final controller in _controllers) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.dispose();
    }
    _controllers.clear();
    
    super.dispose();
    _log.info('✅ Animations Orchestrator disposed');
  }
} 