import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/theme_consts.dart';

class MainHelperModule extends ModuleBase {
  static final Logger _log = Logger();
  static final Random _random = Random();

  Timer? _activeTimer;
  int _remainingTime = 0;
  bool _isPaused = false;
  bool _isRunning = false;

  /// ✅ Constructor with module key and dependencies
  MainHelperModule() : super("main_helper_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _log.info('✅ MainHelperModule initialized with context.');
  }

  /// Retrieve background by index (looping if out of range)
  static String getBackground(int index) {
    if (AppBackgrounds.backgrounds.isEmpty) {
      _log.error('No backgrounds available.');
      return '';
    }
    return AppBackgrounds.backgrounds[index % AppBackgrounds.backgrounds.length];
  }

  /// Retrieve a random background
  static String getRandomBackground() {
    if (AppBackgrounds.backgrounds.isEmpty) {
      _log.error('No backgrounds available.');
      return '';
    }
    return AppBackgrounds.backgrounds[_random.nextInt(AppBackgrounds.backgrounds.length)];
  }

  /// ✅ Update user information in Shared Preferences
  Future<void> updateUserInfo(BuildContext context, String key, dynamic value) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref != null) {
      try {
        if (value is String) {
          await sharedPref.setString(key, value);
        } else if (value is int) {
          await sharedPref.setInt(key, value);
        } else if (value is bool) {
          await sharedPref.setBool(key, value);
        } else if (value is double) {
          await sharedPref.setDouble(key, value);
        } else {
          _log.error('Unsupported value type for key: $key');
          return;
        }
        _log.info('Updated $key: $value');
      } catch (e) {
        _log.error('Error updating user info: $e');
      }
    } else {
      _log.error('SharedPrefManager not available.');
    }
  }

  /// ✅ Retrieve stored user information
  Future<dynamic> getUserInfo(BuildContext context, String key) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref != null) {
      try {
        dynamic value;
        if (key == 'points') {
          value = sharedPref.getInt(key);
        } else {
          value = sharedPref.getString(key);
        }
        _log.info('Retrieved $key: $value');
        return value;
      } catch (e) {
        _log.error('Error retrieving user info: $e');
      }
    } else {
      _log.error('SharedPrefManager not available.');
    }
    return null;
  }

  @override
  void dispose() {
    _activeTimer?.cancel();
    super.dispose();
  }
}