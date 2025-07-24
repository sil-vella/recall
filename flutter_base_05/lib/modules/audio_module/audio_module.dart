import 'dart:math';
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';

/// Pure business logic for audio
/// Contains no Flutter/system dependencies
class AudioModule {
  static final Logger _log = Logger();
  static bool _isMuted = false;
  
  final Map<String, Map<String, dynamic>> _audioData = {};
  final Map<String, bool> _currentlyPlaying = {};
  final Map<String, Map<String, dynamic>> _preloadedData = {};
  final Random _random = Random();

  /// ✅ Constructor
  AudioModule();

  /// ✅ Getter for global mute state
  static bool get isMuted => _isMuted;

  /// ✅ Get currently playing sounds
  Set<String> get currentlyPlaying => _currentlyPlaying.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();

  /// ✅ Get preloaded data
  Map<String, Map<String, dynamic>> get preloadedData => _preloadedData;

  final Map<String, String> correctSounds = {
    "correct_1": "assets/audio/correct01.mp3",
  };

  final Map<String, String> incorrectSounds = {
    "incorrect_1": "assets/audio/incorrect01.mp3",
  };

  final Map<String, String> levelUpSounds = {
    "level_up_1": "assets/audio/level_up001.mp3",
  };

  final Map<String, String> flushingFiles = {
    "flushing_1": "assets/audio/flush007.mp3",
  };

  /// ✅ Preload all sounds (business logic only)
  Map<String, dynamic> preloadAllSounds() {
    _log.info('🎵 Preloading all sounds...');
    
    final allSounds = <String, String>{};
    allSounds.addAll(correctSounds);
    allSounds.addAll(incorrectSounds);
    allSounds.addAll(levelUpSounds);
    allSounds.addAll(flushingFiles);

    int preloadedCount = 0;
    for (final entry in allSounds.entries) {
      final result = preloadSound(entry.key, entry.value);
      if (result['success']) {
        preloadedCount++;
      }
    }
    
    _log.info('✅ All sounds preloaded successfully');
    
    return {
      'success': true,
      'message': 'All sounds preloaded',
      'preloadedCount': preloadedCount,
      'totalSounds': allSounds.length,
    };
  }

  /// ✅ Preload a specific sound (business logic only)
  Map<String, dynamic> preloadSound(String soundKey, String assetPath) {
    try {
      final preloadData = {
        'soundKey': soundKey,
        'assetPath': assetPath,
        'preloadedAt': DateTime.now().toIso8601String(),
        'status': 'preloaded',
      };
      
      _preloadedData[soundKey] = preloadData;
      _log.info('✅ Preloaded sound: $soundKey');
      
      return {
        'success': true,
        'message': 'Sound preloaded successfully',
        'soundKey': soundKey,
        'preloadData': preloadData,
      };
    } catch (e) {
      _log.error('❌ Failed to preload sound $soundKey: $e');
      return {
        'success': false,
        'message': 'Failed to preload sound',
        'error': e.toString(),
        'soundKey': soundKey,
      };
    }
  }

  /// ✅ Play a sound (business logic only)
  Map<String, dynamic> playSound(String soundKey) {
    if (_isMuted) {
      _log.info('🔇 Sound muted, skipping: $soundKey');
      return {
        'success': false,
        'message': 'Sound muted',
        'soundKey': soundKey,
      };
    }

    try {
        final assetPath = _getAssetPath(soundKey);
      if (assetPath == null) {
          _log.error('❌ Sound not found: $soundKey');
        return {
          'success': false,
          'message': 'Sound not found',
          'soundKey': soundKey,
        };
      }

      final audioData = {
        'soundKey': soundKey,
        'assetPath': assetPath,
        'startedAt': DateTime.now().toIso8601String(),
        'status': 'playing',
        'isPreloaded': _preloadedData.containsKey(soundKey),
      };
      
      _audioData[soundKey] = audioData;
      _currentlyPlaying[soundKey] = true;
        
        _log.info('🎵 Playing sound: $soundKey');
      
      return {
        'success': true,
        'message': 'Sound started playing',
        'soundKey': soundKey,
        'audioData': audioData,
      };
    } catch (e) {
      _log.error('❌ Error playing sound $soundKey: $e');
      return {
        'success': false,
        'message': 'Error playing sound',
        'error': e.toString(),
        'soundKey': soundKey,
      };
    }
  }

  /// ✅ Stop a specific sound (business logic only)
  Map<String, dynamic> stopSound(String soundKey) {
    if (_currentlyPlaying.containsKey(soundKey) && _currentlyPlaying[soundKey]!) {
      _currentlyPlaying[soundKey] = false;
      
      if (_audioData.containsKey(soundKey)) {
        _audioData[soundKey]!['status'] = 'stopped';
        _audioData[soundKey]!['stoppedAt'] = DateTime.now().toIso8601String();
      }
      
      _log.info('⏹️ Stopped sound: $soundKey');
      
      return {
        'success': true,
        'message': 'Sound stopped',
        'soundKey': soundKey,
      };
    } else {
      return {
        'success': false,
        'message': 'Sound not playing',
        'soundKey': soundKey,
      };
    }
  }

  /// ✅ Stop all sounds (business logic only)
  Map<String, dynamic> stopAllSounds() {
    final count = _currentlyPlaying.length;
    
    for (final key in _currentlyPlaying.keys) {
      _currentlyPlaying[key] = false;
      if (_audioData.containsKey(key)) {
        _audioData[key]!['status'] = 'stopped';
        _audioData[key]!['stoppedAt'] = DateTime.now().toIso8601String();
      }
    }
    
    _log.info('⏹️ Stopped all sounds ($count sounds)');
    
    return {
      'success': true,
      'message': 'All sounds stopped',
      'stoppedCount': count,
    };
  }

  /// ✅ Toggle mute state
  static void toggleMute() {
    _isMuted = !_isMuted;
    _log.info('🔇 Audio ${_isMuted ? "muted" : "unmuted"}');
  }

  /// ✅ Set mute state
  static void setMute(bool muted) {
    _isMuted = muted;
    _log.info('🔇 Audio ${_isMuted ? "muted" : "unmuted"}');
  }

  /// ✅ Get asset path for sound key
  String? _getAssetPath(String soundKey) {
    if (correctSounds.containsKey(soundKey)) {
      return correctSounds[soundKey];
    } else if (incorrectSounds.containsKey(soundKey)) {
      return incorrectSounds[soundKey];
    } else if (levelUpSounds.containsKey(soundKey)) {
      return levelUpSounds[soundKey];
    } else if (flushingFiles.containsKey(soundKey)) {
      return flushingFiles[soundKey];
    }
    return null;
  }

  /// ✅ Play random correct sound
  Future<void> playRandomCorrectSound() async {
    final keys = correctSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[_random.nextInt(keys.length)];
      await playSound(randomKey);
    }
  }

  /// ✅ Play random incorrect sound
  Future<void> playRandomIncorrectSound() async {
    final keys = incorrectSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[_random.nextInt(keys.length)];
      await playSound(randomKey);
    }
  }

  /// ✅ Get audio status
  Map<String, dynamic> getAudioStatus(String soundKey) {
    final isPlaying = _currentlyPlaying[soundKey] ?? false;
    final data = _audioData[soundKey];
    final isPreloaded = _preloadedData.containsKey(soundKey);
    
    return {
      'soundKey': soundKey,
      'isPlaying': isPlaying,
      'isPreloaded': isPreloaded,
      'data': data,
    };
  }

  /// ✅ Get all active sounds
  Map<String, dynamic> getAllActiveSounds() {
    final activeKeys = _currentlyPlaying.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    
    return {
      'activeSounds': activeKeys,
      'totalActive': activeKeys.length,
      'allAudioData': _audioData,
    };
  }

  /// ✅ Get audio statistics
  Map<String, dynamic> getAudioStatistics() {
    final totalSounds = _audioData.length;
    final activeSounds = _currentlyPlaying.values.where((playing) => playing).length;
    final stoppedSounds = totalSounds - activeSounds;
    final preloadedCount = _preloadedData.length;
    
    return {
      'totalSounds': totalSounds,
      'activeSounds': activeSounds,
      'stoppedSounds': stoppedSounds,
      'preloadedCount': preloadedCount,
      'isMuted': _isMuted,
    };
  }

  /// ✅ Get hooks needed by this module
  List<Map<String, dynamic>> getHooksNeeded() {
    return [
      {
        'hookName': 'audio_play_sound',
        'description': 'Triggered when a sound should be played',
        'priority': 5,
      },
      {
        'hookName': 'audio_stop_sound',
        'description': 'Triggered when a sound should be stopped',
        'priority': 5,
      },
      {
        'hookName': 'audio_stop_all',
        'description': 'Triggered when all sounds should be stopped',
        'priority': 10,
      },
      {
        'hookName': 'audio_toggle_mute',
        'description': 'Triggered when mute state should be toggled',
        'priority': 5,
      },
    ];
  }

  /// ✅ Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/audio/play',
        'method': 'POST',
        'description': 'Play a sound',
      },
      {
        'route': '/audio/stop',
        'method': 'POST',
        'description': 'Stop a sound',
      },
      {
        'route': '/audio/stop_all',
        'method': 'POST',
        'description': 'Stop all sounds',
      },
      {
        'route': '/audio/mute',
        'method': 'POST',
        'description': 'Toggle mute state',
      },
      {
        'route': '/audio/status',
        'method': 'GET',
        'description': 'Get audio status',
      },
    ];
  }

  /// ✅ Get config requirements
  List<String> getConfigRequirements() {
    return [
      'audioEnabled',
      'defaultVolume',
      'muteState',
    ];
  }

  /// ✅ Validate sound key
  bool validateSoundKey(String soundKey) {
    if (soundKey.isEmpty) {
      _log.error('❌ Sound key cannot be empty');
      return false;
    }
    
    if (soundKey.length > 50) {
      _log.error('❌ Sound key too long: $soundKey');
      return false;
    }
    
    return true;
  }

  /// ✅ Cleanup resources (business logic only)
  Map<String, dynamic> cleanup() {
    _log.info('🗑️ Cleaning up AudioModule...');
    
    final activeCount = _currentlyPlaying.length;
    final preloadedCount = _preloadedData.length;
    
    // Clear all data
    _audioData.clear();
    _currentlyPlaying.clear();
    _preloadedData.clear();
    
    _log.info('✅ AudioModule cleaned up');
    
    return {
      'success': true,
      'message': 'AudioModule cleaned up',
      'activeCount': activeCount,
      'preloadedCount': preloadedCount,
    };
  }
}

