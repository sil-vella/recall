import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';

/// Pure business logic for animations
/// Contains no Flutter/system dependencies
class AnimationsModule {
  static final Logger _log = Logger();
  
  final Map<String, Map<String, dynamic>> _animationData = {};
  final Map<String, bool> _activeAnimations = {};

  /// ✅ Constructor
  AnimationsModule();

  /// ✅ Play confetti animation (business logic only)
  Map<String, dynamic> playConfetti({required String key, Duration? duration}) {
    _log.info('🎉 Playing confetti animation: $key');
    
    final animationData = {
      'key': key,
      'type': 'confetti',
      'duration': duration?.inMilliseconds ?? 2000,
      'startedAt': DateTime.now().toIso8601String(),
      'status': 'playing',
    };
    
    _animationData[key] = animationData;
    _activeAnimations[key] = true;
    
    return {
      'success': true,
      'message': 'Confetti animation started',
      'key': key,
      'animationData': animationData,
    };
  }

  /// ✅ Stop confetti animation (business logic only)
  Map<String, dynamic> stopConfetti({required String key}) {
    _log.info('⏹️ Stopping confetti animation: $key');
    
    if (_activeAnimations.containsKey(key)) {
      _activeAnimations[key] = false;
      
      if (_animationData.containsKey(key)) {
        _animationData[key]!['status'] = 'stopped';
        _animationData[key]!['stoppedAt'] = DateTime.now().toIso8601String();
  }

      return {
        'success': true,
        'message': 'Confetti animation stopped',
        'key': key,
      };
    } else {
      return {
        'success': false,
        'message': 'Animation not found',
        'key': key,
      };
    }
  }

  /// ✅ Create confetti controller data (business logic only)
  Map<String, dynamic> createConfettiController({Duration? duration}) {
    final key = 'confetti_${_animationData.length}';
    final controllerData = {
      'key': key,
      'type': 'confetti_controller',
      'duration': duration?.inMilliseconds ?? 2000,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'created',
    };
    
    _animationData[key] = controllerData;
    
    return {
      'success': true,
      'message': 'Confetti controller created',
      'key': key,
      'controllerData': controllerData,
    };
  }

  /// ✅ Get confetti controller data
  Map<String, dynamic>? getConfettiControllerData(String key) {
    return _animationData[key];
  }

  /// ✅ Remove confetti controller
  Map<String, dynamic> removeConfettiController(String key) {
    if (_animationData.containsKey(key)) {
      _animationData.remove(key);
      _activeAnimations.remove(key);
      _log.info('🗑️ Removed confetti controller: $key');
      
      return {
        'success': true,
        'message': 'Confetti controller removed',
        'key': key,
      };
    } else {
      return {
        'success': false,
        'message': 'Controller not found',
        'key': key,
      };
    }
  }

  /// ✅ Play success animation
  Map<String, dynamic> playSuccessAnimation() {
    _log.info('✅ Playing success animation');
    
    final result = playConfetti(key: 'success');
    result['animationType'] = 'success';
    
    return result;
  }

  /// ✅ Play celebration animation
  Map<String, dynamic> playCelebrationAnimation() {
    _log.info('🎉 Playing celebration animation');
    
    final result = playConfetti(key: 'celebration');
    result['animationType'] = 'celebration';
    
    return result;
  }

  /// ✅ Play level up animation
  Map<String, dynamic> playLevelUpAnimation() {
    _log.info('📈 Playing level up animation');
    
    final result = playConfetti(key: 'level_up');
    result['animationType'] = 'level_up';
    
    return result;
  }

  /// ✅ Get animation status
  Map<String, dynamic> getAnimationStatus(String key) {
    final isActive = _activeAnimations[key] ?? false;
    final data = _animationData[key];
    
    return {
      'key': key,
      'isActive': isActive,
      'data': data,
    };
  }

  /// ✅ Get all active animations
  Map<String, dynamic> getAllActiveAnimations() {
    final activeKeys = _activeAnimations.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    
    return {
      'activeAnimations': activeKeys,
      'totalActive': activeKeys.length,
      'allAnimations': _animationData,
    };
  }

  /// ✅ Stop all animations
  Map<String, dynamic> stopAllAnimations() {
    final count = _activeAnimations.length;
    
    for (final key in _activeAnimations.keys) {
      _activeAnimations[key] = false;
      if (_animationData.containsKey(key)) {
        _animationData[key]!['status'] = 'stopped';
        _animationData[key]!['stoppedAt'] = DateTime.now().toIso8601String();
      }
    }
    
    _log.info('⏹️ Stopped all animations ($count animations)');
    
    return {
      'success': true,
      'message': 'All animations stopped',
      'stoppedCount': count,
    };
  }

  /// ✅ Get hooks needed by this module
  List<Map<String, dynamic>> getHooksNeeded() {
    return [
      {
        'hookName': 'animation_success',
        'description': 'Triggered when success animation should play',
        'priority': 5,
      },
      {
        'hookName': 'animation_celebration',
        'description': 'Triggered when celebration animation should play',
        'priority': 5,
      },
      {
        'hookName': 'animation_level_up',
        'description': 'Triggered when level up animation should play',
        'priority': 5,
      },
      {
        'hookName': 'animation_stop_all',
        'description': 'Triggered when all animations should stop',
        'priority': 10,
      },
    ];
  }

  /// ✅ Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/animations/confetti/play',
        'method': 'POST',
        'description': 'Play confetti animation',
      },
      {
        'route': '/animations/confetti/stop',
        'method': 'POST',
        'description': 'Stop confetti animation',
      },
      {
        'route': '/animations/success',
        'method': 'POST',
        'description': 'Play success animation',
      },
      {
        'route': '/animations/celebration',
        'method': 'POST',
        'description': 'Play celebration animation',
      },
      {
        'route': '/animations/level_up',
        'method': 'POST',
        'description': 'Play level up animation',
      },
      {
        'route': '/animations/status',
        'method': 'GET',
        'description': 'Get animation status',
      },
    ];
  }

  /// ✅ Get config requirements
  List<String> getConfigRequirements() {
    return [
      'animationDuration',
      'confettiDuration',
    ];
  }

  /// ✅ Validate animation key
  bool validateAnimationKey(String key) {
    if (key.isEmpty) {
      _log.error('❌ Animation key cannot be empty');
      return false;
    }
    
    if (key.length > 50) {
      _log.error('❌ Animation key too long: $key');
      return false;
    }
    
    return true;
  }

  /// ✅ Get animation statistics
  Map<String, dynamic> getAnimationStatistics() {
    final totalAnimations = _animationData.length;
    final activeAnimations = _activeAnimations.values.where((active) => active).length;
    final stoppedAnimations = totalAnimations - activeAnimations;
    
    return {
      'totalAnimations': totalAnimations,
      'activeAnimations': activeAnimations,
      'stoppedAnimations': stoppedAnimations,
      'animationTypes': _animationData.values.map((data) => data['type']).toSet().toList(),
    };
  }
}
