import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';

class AnimationsModule extends ModuleBase {
  static const bool LOGGING_SWITCH = true;
  static final Logger _logger = Logger();
  final List<AnimationController> _controllers = [];
  final Map<String, ConfettiController> _confettiControllers = {};

  /// ✅ Constructor with module key and dependencies
  AnimationsModule() : super("animations_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _logger.info('✅ AnimationsModule initialized with context.', isOn: LOGGING_SWITCH);
  }

  /// ✅ Cleanup logic for AnimationsModule
  @override
  void dispose() {
    _logger.info('Cleaning up AnimationsModule resources.', isOn: LOGGING_SWITCH);

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

    _logger.info('AnimationsModule fully disposed.', isOn: LOGGING_SWITCH);
    super.dispose();
  }

  /// ✅ Registers an AnimationController for later cleanup
  void registerController(AnimationController controller) {
    _controllers.add(controller);
    _logger.info('Registered AnimationController: $controller', isOn: LOGGING_SWITCH);
  }

  /// ✅ Method to trigger confetti animation
  void playConfetti({required String key}) {
    if (!_confettiControllers.containsKey(key)) {
      _confettiControllers[key] = ConfettiController(duration: const Duration(seconds: 2));
    }

    _confettiControllers[key]!.play();
    _logger.info('🎉 Confetti started: $key', isOn: LOGGING_SWITCH);
  }

  /// ✅ Stop confetti animation
  void stopConfetti({required String key}) {
    if (_confettiControllers.containsKey(key)) {
      _confettiControllers[key]!.stop();
      _logger.info('⏹️ Confetti stopped: $key', isOn: LOGGING_SWITCH);
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
      _logger.info('🗑️ Removed confetti controller: $key', isOn: LOGGING_SWITCH);
    }
  }

  /// ✅ Play success animation
  void playSuccessAnimation() {
    playConfetti(key: 'success');
    _logger.info('✅ Success animation played', isOn: LOGGING_SWITCH);
  }

  /// ✅ Play celebration animation
  void playCelebrationAnimation() {
    playConfetti(key: 'celebration');
    _logger.info('🎉 Celebration animation played', isOn: LOGGING_SWITCH);
  }

  /// ✅ Play level up animation
  void playLevelUpAnimation() {
    playConfetti(key: 'level_up');
    _logger.info('📈 Level up animation played', isOn: LOGGING_SWITCH);
  }
}
