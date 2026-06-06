import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

class AudioModule extends ModuleBase {
  static bool _isMuted = false;
  final Map<String, AudioSource> _cachedSources = {};
  final Set<AudioPlayer> _activeOneShotPlayers = {};
  final Map<AudioPlayer, String> _playerSoundKeys = {};
  final Map<String, int> _playingCounts = {};
  final Set<String> _currentlyPlaying = {};
  final Random _random = Random();

  AudioModule() : super("audio_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    unawaited(preloadAllSounds());
  }

  static bool get isMuted => _isMuted;

  Set<String> get currentlyPlaying => Set<String>.unmodifiable(_currentlyPlaying);

  final Map<String, String> correctSounds = {
    "correct_1": "assets/audio/correct01.mp3",
  };

  final Map<String, String> incorrectSounds = {
    "incorrect_1": "assets/audio/incorrect01.mp3",
  };

  final Map<String, String> flushingFiles = {
    "flushing_1": "assets/audio/flush007.mp3",
  };

  final Map<String, String> gameSounds = {
    "init_deal": "assets/audio/init_deal.mp3",
    "draw": "assets/audio/draw_002.mp3",
    "play": "assets/audio/play.mp3",
    "swap": "assets/audio/swap_002.mp3",
    "timer": "assets/audio/timer_002.mp3",
  };

  Future<void> preloadAllSounds() async {
    final allSounds = <String, String>{};
    allSounds.addAll(correctSounds);
    allSounds.addAll(incorrectSounds);
    allSounds.addAll(flushingFiles);
    allSounds.addAll(gameSounds);

    for (final entry in allSounds.entries) {
      await _cacheSource(entry.key, entry.value);
    }
  }

  Future<void> _cacheSource(String soundKey, String assetPath) async {
    if (_cachedSources.containsKey(soundKey)) return;
    try {
      _cachedSources[soundKey] = AudioSource.asset(assetPath);
      if (LOGGING_SWITCH) {
        customlog('AudioModule.preload: ok key=$soundKey path=$assetPath');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        customlog('AudioModule.preload: fail key=$soundKey path=$assetPath err=$e');
      }
    }
  }

  Future<void> playSound(String soundKey) async {
    if (_isMuted) {
      if (LOGGING_SWITCH) {
        customlog('AudioModule.playSound: skipped muted key=$soundKey');
      }
      return;
    }

    final assetPath = _getAssetPath(soundKey);
    if (assetPath == null) {
      if (LOGGING_SWITCH) {
        customlog('AudioModule.playSound: unknown key=$soundKey');
      }
      return;
    }

    AudioPlayer? player;
    StreamSubscription<PlayerState>? subscription;
    try {
      await _cacheSource(soundKey, assetPath);
      final source = _cachedSources[soundKey];
      if (source == null) return;

      player = AudioPlayer();
      _activeOneShotPlayers.add(player);
      _playerSoundKeys[player] = soundKey;
      _markPlaying(soundKey);

      await player.setAudioSource(source);
      if (LOGGING_SWITCH) {
        customlog(
          'AudioModule.playSound: playing key=$soundKey activePlayers=${_activeOneShotPlayers.length}',
        );
      }

      subscription = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          unawaited(_finishOneShot(player!, soundKey, subscription));
        }
      });

      await player.play();
    } catch (e) {
      if (LOGGING_SWITCH) {
        customlog('AudioModule.playSound: error key=$soundKey err=$e');
      }
      if (player != null) {
        await _finishOneShot(player, soundKey, subscription);
      }
    }
  }

  void _markPlaying(String soundKey) {
    _playingCounts[soundKey] = (_playingCounts[soundKey] ?? 0) + 1;
    _currentlyPlaying.add(soundKey);
  }

  void _markStopped(String soundKey) {
    final next = (_playingCounts[soundKey] ?? 1) - 1;
    if (next <= 0) {
      _playingCounts.remove(soundKey);
      _currentlyPlaying.remove(soundKey);
    } else {
      _playingCounts[soundKey] = next;
    }
  }

  Future<void> _finishOneShot(
    AudioPlayer player,
    String soundKey,
    StreamSubscription<PlayerState>? subscription,
  ) async {
    await subscription?.cancel();
    if (!_activeOneShotPlayers.remove(player)) return;
    _playerSoundKeys.remove(player);
    _markStopped(soundKey);
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
    if (LOGGING_SWITCH) {
      customlog(
        'AudioModule.playSound: completed key=$soundKey activePlayers=${_activeOneShotPlayers.length}',
      );
    }
  }

  Future<void> stopSound(String soundKey) async {
    final toStop = _playerSoundKeys.entries
        .where((e) => e.value == soundKey)
        .map((e) => e.key)
        .toList();
    for (final player in toStop) {
      await _finishOneShot(player, soundKey, null);
    }
  }

  Future<void> stopAllSounds() async {
    final toStop = _activeOneShotPlayers.toList();
    for (final player in toStop) {
      final soundKey = _playerSoundKeys[player] ?? '';
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
      _activeOneShotPlayers.remove(player);
      _playerSoundKeys.remove(player);
      if (soundKey.isNotEmpty) {
        _markStopped(soundKey);
      }
    }
    _playingCounts.clear();
    _currentlyPlaying.clear();
  }

  static void toggleMute() {
    _isMuted = !_isMuted;
  }

  static void setMute(bool muted) {
    _isMuted = muted;
  }

  String? _getAssetPath(String soundKey) {
    if (correctSounds.containsKey(soundKey)) {
      return correctSounds[soundKey];
    } else if (incorrectSounds.containsKey(soundKey)) {
      return incorrectSounds[soundKey];
    } else if (flushingFiles.containsKey(soundKey)) {
      return flushingFiles[soundKey];
    } else if (gameSounds.containsKey(soundKey)) {
      return gameSounds[soundKey];
    }
    return null;
  }

  Future<void> playRandomCorrectSound() async {
    final keys = correctSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[_random.nextInt(keys.length)];
      await playSound(randomKey);
    }
  }

  Future<void> playRandomIncorrectSound() async {
    final keys = incorrectSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[_random.nextInt(keys.length)];
      await playSound(randomKey);
    }
  }

  @override
  void dispose() {
    for (final player in _activeOneShotPlayers) {
      player.stop();
      player.dispose();
    }
    _activeOneShotPlayers.clear();
    _playerSoundKeys.clear();
    _playingCounts.clear();
    _currentlyPlaying.clear();
    _cachedSources.clear();
    super.dispose();
  }
}
