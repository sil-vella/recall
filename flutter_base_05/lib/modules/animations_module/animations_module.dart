import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';

class AnimationsModule extends ModuleBase {
  static final Logger _log = Logger();
  final List<AnimationController> _controllers = [];
  final Map<String, ConfettiController> _confettiControllers = {};

  /// ✅ Constructor with module key and dependencies
  AnimationsModule() : super("animations_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _log.info('✅ AnimationsModule initialized with context.');
  }

  /// ✅ Cleanup logic for AnimationsModule
  @override
  void dispose() {
    _log.info('Cleaning up AnimationsModule resources.');

    for (final controller in _controllers) {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.dispose();
    }
    _controllers.clear();

    for (final confettiController in _confettiControllers.values) {
      confettiController.dispose();
    }
    _confettiControllers.clear();

    _log.info('AnimationsModule fully disposed.');
    super.dispose();
  }

  /// ✅ Registers an AnimationController for later cleanup
  void registerController(AnimationController controller) {
    _controllers.add(controller);
    _log.info('Registered AnimationController: $controller');
  }

  /// ✅ Method to trigger confetti animation
  void playConfetti({required String key}) {
    if (!_confettiControllers.containsKey(key)) {
      _confettiControllers[key] = ConfettiController(duration: const Duration(seconds: 2));
    }

    _confettiControllers[key]!.play();
    _log.info('🎉 Confetti started: $key');
  }

  /// ✅ Stop confetti animation
  void stopConfetti({required String key}) {
    if (_confettiControllers.containsKey(key)) {
      _confettiControllers[key]!.stop();
      _log.info('⏹️ Confetti stopped: $key');
    }
  }

  /// ✅ Create a new confetti controller
  ConfettiController createConfettiController({Duration? duration}) {
    final controller = ConfettiController(duration: duration ?? const Duration(seconds: 2));
    _confettiControllers['confetti_${_confettiControllers.length}'] = controller;
    return controller;
  }

  /// ✅ Get confetti controller by key
  ConfettiController? getConfettiController(String key) {
    return _confettiControllers[key];
  }

  /// ✅ Remove confetti controller
  void removeConfettiController(String key) {
    if (_confettiControllers.containsKey(key)) {
      _confettiControllers[key]!.dispose();
      _confettiControllers.remove(key);
      _log.info('🗑️ Removed confetti controller: $key');
    }
  }

  /// ✅ Play success animation
  void playSuccessAnimation() {
    playConfetti(key: 'success');
    _log.info('✅ Success animation played');
  }

  /// ✅ Play celebration animation
  void playCelebrationAnimation() {
    playConfetti(key: 'celebration');
    _log.info('🎉 Celebration animation played');
  }

  /// ✅ Play level up animation
  void playLevelUpAnimation() {
    playConfetti(key: 'level_up');
    _log.info('📈 Level up animation played');
  }
}
