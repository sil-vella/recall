import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../tools/logging/logger.dart';

class AudioModule extends ModuleBase {
  static final Logger _log = Logger();
  static bool _isMuted = false;
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, AudioPlayer> _preloadedPlayers = {};
  final Set<String> _currentlyPlaying = {};
  final Random _random = Random();

  /// ✅ Constructor with module key and dependencies
  AudioModule() : super("audio_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _log.info('✅ AudioModule initialized with context.');
  }

  /// ✅ Getter for global mute state
  static bool get isMuted => _isMuted;

  /// ✅ Get currently playing sounds
  Set<String> get currentlyPlaying => _currentlyPlaying;

  /// ✅ Get preloaded players
  Map<String, AudioPlayer> get preloadedPlayers => _preloadedPlayers;

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

  /// ✅ Preload all sounds
  Future<void> preloadAllSounds() async {
    _log.info('🎵 Preloading all sounds...');
    
    final allSounds = <String, String>{};
    allSounds.addAll(correctSounds);
    allSounds.addAll(incorrectSounds);
    allSounds.addAll(levelUpSounds);
    allSounds.addAll(flushingFiles);

    for (final entry in allSounds.entries) {
      await preloadSound(entry.key, entry.value);
    }
    
    _log.info('✅ All sounds preloaded successfully');
  }

  /// ✅ Preload a specific sound
  Future<void> preloadSound(String soundKey, String assetPath) async {
    try {
      final player = AudioPlayer();
      await player.setAsset(assetPath);
      _preloadedPlayers[soundKey] = player;
      _log.info('✅ Preloaded sound: $soundKey');
    } catch (e) {
      _log.error('❌ Failed to preload sound $soundKey: $e');
    }
  }

  /// ✅ Play a sound
  Future<void> playSound(String soundKey) async {
    if (_isMuted) {
      _log.info('🔇 Sound muted, skipping: $soundKey');
      return;
    }

    try {
      AudioPlayer? player;
      
      // Try to use preloaded player first
      if (_preloadedPlayers.containsKey(soundKey)) {
        player = _preloadedPlayers[soundKey];
      } else {
        // Create new player if not preloaded
        player = AudioPlayer();
        final assetPath = _getAssetPath(soundKey);
        if (assetPath != null) {
          await player!.setAsset(assetPath);
        } else {
          _log.error('❌ Sound not found: $soundKey');
          return;
        }
      }

      if (player != null) {
        await player.play();
        _currentlyPlaying.add(soundKey);
        _audioPlayers[soundKey] = player;
        
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            _currentlyPlaying.remove(soundKey);
            _audioPlayers.remove(soundKey);
          }
        });
        
        _log.info('🎵 Playing sound: $soundKey');
      }
    } catch (e) {
      _log.error('❌ Error playing sound $soundKey: $e');
    }
  }

  /// ✅ Stop a specific sound
  Future<void> stopSound(String soundKey) async {
    final player = _audioPlayers[soundKey];
    if (player != null) {
      await player.stop();
      _currentlyPlaying.remove(soundKey);
      _audioPlayers.remove(soundKey);
      _log.info('⏹️ Stopped sound: $soundKey');
    }
  }

  /// ✅ Stop all sounds
  Future<void> stopAllSounds() async {
    for (final player in _audioPlayers.values) {
      await player.stop();
    }
    _audioPlayers.clear();
    _currentlyPlaying.clear();
    _log.info('⏹️ Stopped all sounds');
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

  @override
  void dispose() {
    _log.info('🗑️ Disposing AudioModule...');
    
    // Stop and dispose all players
    for (final player in _audioPlayers.values) {
      player.stop();
      player.dispose();
    }
    _audioPlayers.clear();
    
    for (final player in _preloadedPlayers.values) {
      player.stop();
      player.dispose();
    }
    _preloadedPlayers.clear();
    
    _currentlyPlaying.clear();
    
    super.dispose();
  }
}
