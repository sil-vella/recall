import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../services/shared_preferences.dart';
import '../base_files/module_orch_base.dart';
import '../../../../modules/audio_module/audio_module.dart';

/// Audio Orchestrator - Handles system integration for audio
/// Delegates business logic to pure modules
class AudioOrchestrator extends ModuleOrchestratorBase {
  static final Logger _log = Logger();
  
  // Pure business logic module
  late AudioModule _audioModule;
  
  // Flutter-specific audio players
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, AudioPlayer> _preloadedPlayers = {};

  @override
  void initialize(BuildContext context) {
    _log.info('🎼 Initializing Audio Orchestrator...');
    
    // Initialize pure business logic module
    _audioModule = AudioModule();
    
    // Register hooks and routes
    _registerHooks();
    _registerRoutes();
    
    _log.info('✅ Audio Orchestrator initialized successfully');
  }

  @override
  void _registerHooks() {
    _log.info('🔗 Registering Audio hooks...');
    
    // Register hooks from audio module
    final audioHooks = _audioModule.getHooksNeeded();
    for (final hook in audioHooks) {
      hooksManager.registerHookWithData(hook['hookName'], (data) {
        _log.info('📢 ${hook['hookName']} hook triggered');
        _handleAudioHook(hook['hookName'], data);
      }, priority: hook['priority']);
    }
    
    _log.info('✅ Audio hooks registered successfully');
  }

  @override
  void _registerRoutes() {
    _log.info('🛣️ Registering Audio routes...');
    
    // Register routes from audio module
    final audioRoutes = _audioModule.getRoutesNeeded();
    
    for (final route in audioRoutes) {
      _log.info('🛣️ Route: ${route['method']} ${route['route']} - ${route['description']}');
      // Routes would be registered with navigation system here
    }
    
    _log.info('✅ Audio routes registered successfully');
  }

  /// Handle audio hooks
  void _handleAudioHook(String hookName, Map<String, dynamic> data) {
    switch (hookName) {
      case 'audio_play_sound':
        final soundKey = data['soundKey'];
        if (soundKey != null) {
          _playSound(soundKey);
        }
        break;
      case 'audio_stop_sound':
        final soundKey = data['soundKey'];
        if (soundKey != null) {
          _stopSound(soundKey);
        }
        break;
      case 'audio_stop_all':
        _stopAllSounds();
        break;
      case 'audio_toggle_mute':
        _toggleMute();
        break;
    }
  }

  /// Play sound with system integration
  void _playSound(String soundKey) {
    _log.info('🎵 Playing sound: $soundKey');
    
    // Call business logic module
    final result = _audioModule.playSound(soundKey);
    
    if (result['success']) {
      // Create actual Flutter AudioPlayer
      _createAndPlayAudioPlayer(soundKey, result['audioData']['assetPath']);
      
      // Update state
      stateManager.updateModuleState('audio', {
        'activeSounds': _getActiveSoundsList(),
        'lastPlayed': soundKey,
        'audioData': result['audioData'],
      });
      
      _log.info('✅ Sound started playing: $soundKey');
    } else {
      _log.error('❌ Failed to play sound: ${result['message']}');
    }
  }

  /// Stop sound with system integration
  void _stopSound(String soundKey) {
    _log.info('⏹️ Stopping sound: $soundKey');
    
    // Call business logic module
    final result = _audioModule.stopSound(soundKey);
    
    if (result['success']) {
      // Stop actual Flutter AudioPlayer
      final player = _audioPlayers[soundKey];
      if (player != null) {
        player.stop();
        _audioPlayers.remove(soundKey);
      }
      
      // Update state
      stateManager.updateModuleState('audio', {
        'activeSounds': _getActiveSoundsList(),
        'lastStopped': soundKey,
      });
      
      _log.info('✅ Sound stopped: $soundKey');
    } else {
      _log.error('❌ Failed to stop sound: ${result['message']}');
    }
  }

  /// Stop all sounds with system integration
  void _stopAllSounds() {
    _log.info('⏹️ Stopping all sounds');
    
    // Call business logic module
    final result = _audioModule.stopAllSounds();
    
    if (result['success']) {
      // Stop all Flutter AudioPlayers
      for (final player in _audioPlayers.values) {
        player.stop();
      }
      _audioPlayers.clear();
      
      // Update state
      stateManager.updateModuleState('audio', {
        'activeSounds': [],
        'allStoppedAt': DateTime.now().toIso8601String(),
      });
      
      _log.info('✅ All sounds stopped');
    } else {
      _log.error('❌ Failed to stop all sounds: ${result['message']}');
    }
  }

  /// Toggle mute state
  void _toggleMute() {
    _log.info('🔇 Toggling mute state');
    
    AudioModule.toggleMute();
    
    // Update state
    stateManager.updateModuleState('audio', {
      'isMuted': AudioModule.isMuted,
      'muteToggledAt': DateTime.now().toIso8601String(),
    });
    
    _log.info('✅ Mute state toggled: ${AudioModule.isMuted}');
  }

  /// Create and play audio player
  void _createAndPlayAudioPlayer(String soundKey, String assetPath) async {
    try {
      AudioPlayer? player;
      
      // Try to use preloaded player first
      if (_preloadedPlayers.containsKey(soundKey)) {
        player = _preloadedPlayers[soundKey];
      } else {
        // Create new player if not preloaded
        player = AudioPlayer();
        await player!.setAsset(assetPath);
      }

      if (player != null) {
        await player.play();
        _audioPlayers[soundKey] = player;
        
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            _audioPlayers.remove(soundKey);
            // Update business logic module
            _audioModule.stopSound(soundKey);
          }
        });
      }
    } catch (e) {
      _log.error('❌ Error creating audio player for $soundKey: $e');
    }
  }

  /// Preload sound with system integration
  Future<void> preloadSound(String soundKey, String assetPath) async {
    _log.info('🎵 Preloading sound: $soundKey');
    
    // Call business logic module
    final result = _audioModule.preloadSound(soundKey, assetPath);
    
    if (result['success']) {
      try {
        // Create actual Flutter AudioPlayer
        final player = AudioPlayer();
        await player.setAsset(assetPath);
        _preloadedPlayers[soundKey] = player;
        
        _log.info('✅ Sound preloaded: $soundKey');
      } catch (e) {
        _log.error('❌ Failed to preload sound $soundKey: $e');
      }
    } else {
      _log.error('❌ Failed to preload sound: ${result['message']}');
    }
  }

  /// Preload all sounds with system integration
  Future<void> preloadAllSounds() async {
    _log.info('🎵 Preloading all sounds');
    
    // Call business logic module
    final result = _audioModule.preloadAllSounds();
    
    if (result['success']) {
      // Preload all sounds defined in the module
      final allSounds = <String, String>{};
      allSounds.addAll(_audioModule.correctSounds);
      allSounds.addAll(_audioModule.incorrectSounds);
      allSounds.addAll(_audioModule.levelUpSounds);
      allSounds.addAll(_audioModule.flushingFiles);

      for (final entry in allSounds.entries) {
        await preloadSound(entry.key, entry.value);
      }
      
      _log.info('✅ All sounds preloaded');
    } else {
      _log.error('❌ Failed to preload all sounds: ${result['message']}');
    }
  }

  /// Play random correct sound
  Future<void> playRandomCorrectSound() async {
    _log.info('🎵 Playing random correct sound');
    
    final keys = _audioModule.correctSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[DateTime.now().millisecondsSinceEpoch % keys.length];
      _playSound(randomKey);
    }
  }

  /// Play random incorrect sound
  Future<void> playRandomIncorrectSound() async {
    _log.info('🎵 Playing random incorrect sound');
    
    final keys = _audioModule.incorrectSounds.keys.toList();
    if (keys.isNotEmpty) {
      final randomKey = keys[DateTime.now().millisecondsSinceEpoch % keys.length];
      _playSound(randomKey);
    }
  }

  /// Get list of active sounds
  List<String> _getActiveSoundsList() {
    return _audioPlayers.keys.toList();
  }

  /// Get audio status
  Map<String, dynamic> getAudioStatus(String soundKey) {
    final result = _audioModule.getAudioStatus(soundKey);
    final player = _audioPlayers[soundKey];
    
    result['hasFlutterPlayer'] = player != null;
    result['isFlutterPlayerPlaying'] = player?.playing ?? false;
    
    return result;
  }

  /// Get all active sounds
  Map<String, dynamic> getAllActiveSounds() {
    final result = _audioModule.getAllActiveSounds();
    result['flutterPlayers'] = _audioPlayers.keys.toList();
    result['preloadedPlayers'] = _preloadedPlayers.keys.toList();
    
    return result;
  }

  /// Get audio statistics
  Map<String, dynamic> getAudioStatistics() {
    final result = _audioModule.getAudioStatistics();
    result['flutterPlayers'] = _audioPlayers.length;
    result['preloadedPlayers'] = _preloadedPlayers.length;
    
    return result;
  }

  /// Health check
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': 'audio_orchestrator',
      'status': 'healthy',
      'details': 'Audio orchestrator is running',
      'audio_players': _audioPlayers.length,
      'preloaded_players': _preloadedPlayers.length,
      'active_sounds': _getActiveSoundsList().length,
      'is_muted': AudioModule.isMuted,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _log.info('🗑 Disposing Audio Orchestrator...');
    
    // Stop and dispose all audio players
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
    
    // Cleanup business logic module
    _audioModule.cleanup();
    
    super.dispose();
    _log.info('✅ Audio Orchestrator disposed');
  }
} 