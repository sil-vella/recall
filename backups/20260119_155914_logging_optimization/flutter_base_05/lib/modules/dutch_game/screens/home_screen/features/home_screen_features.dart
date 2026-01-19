import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../managers/feature_registry_manager.dart';
import '../../../managers/feature_contracts.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

/// Scope and slot constants for the home screen
class HomeScreenFeatureSlots {
  // Must match HomeScreen's FeatureSlot scopeKey
  static const String scopeKey = 'HomeScreen';
  static const String slotButtons = 'home_screen_buttons';
}

/// Registers default home screen features (like play button)
class HomeScreenFeatureRegistrar {
  final FeatureRegistryManager _registry = FeatureRegistryManager.instance;
  static final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues

  /// Register Dutch game play button
  void registerDutchGamePlayButton(BuildContext context) {
    _logger.info('🎮 HomeScreenFeatureRegistrar: Registering Dutch game play button', isOn: LOGGING_SWITCH);
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_play',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Play Dutch',
      onTap: () {
        _logger.info('HomeScreen: Dutch game play button pressed', isOn: LOGGING_SWITCH);
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          _logger.debug('HomeScreen: NavigationManager obtained, navigating to /dutch/lobby', isOn: LOGGING_SWITCH);
          navigationManager.navigateTo('/dutch/lobby');
          _logger.debug('HomeScreen: Navigation to /dutch/lobby initiated', isOn: LOGGING_SWITCH);
        } catch (e, stackTrace) {
          _logger.error('HomeScreen: Error in Dutch game play button handler', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
        }
      },
      imagePath: 'assets/images/backgrounds/play_001.png',
      heightPercentage: 0.5, // 50% of available height
      priority: 100, // Default priority
      textStyle: AppTextStyles.headingMedium().copyWith(
        color: AppColors.textOnPrimary,
        fontWeight: FontWeight.bold,
      ),
    );
    
    _registry.register(
      scopeKey: HomeScreenFeatureSlots.scopeKey,
      feature: feature,
      context: context,
    );
    
    _logger.info('✅ HomeScreenFeatureRegistrar: Dutch game play button registered', isOn: LOGGING_SWITCH);
  }

  /// Register Dutch game demo button
  void registerDutchGameDemoButton(BuildContext context) {
    _logger.info('🎮 HomeScreenFeatureRegistrar: Registering Dutch game demo button', isOn: LOGGING_SWITCH);
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_demo',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Demo',
      onTap: () {
        _logger.info('HomeScreen: Dutch game demo button pressed', isOn: LOGGING_SWITCH);
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          _logger.debug('HomeScreen: NavigationManager obtained, navigating to /dutch/demo', isOn: LOGGING_SWITCH);
          navigationManager.navigateTo('/dutch/demo');
          _logger.debug('HomeScreen: Navigation to /dutch/demo initiated', isOn: LOGGING_SWITCH);
        } catch (e, stackTrace) {
          _logger.error('HomeScreen: Error in Dutch game demo button handler', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
        }
      },
      imagePath: 'assets/images/backgrounds/demo-feature-background.png',
      heightPercentage: 0.5, // 50% of available height
      priority: 90, // Lower priority than play button (appears after)
      textStyle: AppTextStyles.headingMedium().copyWith(
        color: AppColors.textOnPrimary,
        fontWeight: FontWeight.bold,
      ),
    );
    
    _registry.register(
      scopeKey: HomeScreenFeatureSlots.scopeKey,
      feature: feature,
      context: context,
    );
    
    _logger.info('✅ HomeScreenFeatureRegistrar: Dutch game demo button registered', isOn: LOGGING_SWITCH);
  }

  /// Unregister all home screen features
  void unregisterAll() {
    _registry.clearScope(HomeScreenFeatureSlots.scopeKey);
  }
}

