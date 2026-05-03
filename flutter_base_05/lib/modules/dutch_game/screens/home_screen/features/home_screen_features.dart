import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../managers/feature_registry_manager.dart';
import '../../../managers/feature_contracts.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/analytics_service.dart';

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
    if (LOGGING_SWITCH) {
      _logger.info('🎮 HomeScreenFeatureRegistrar: Registering Dutch game play button');
    }
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_play',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Play Dutch',
      iconSvgPath: 'assets/images/icons/play-icon.svg',
      onTap: () {
        if (LOGGING_SWITCH) {
          _logger.info('HomeScreen: Dutch game play button pressed');
        }
        AnalyticsService.logEvent(name: 'home_play_dutch_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          if (LOGGING_SWITCH) {
            _logger.debug('HomeScreen: NavigationManager obtained, navigating to /dutch/lobby');
          }
          navigationManager.navigateTo('/dutch/lobby');
          if (LOGGING_SWITCH) {
            _logger.debug('HomeScreen: Navigation to /dutch/lobby initiated');
          }
        } catch (e, stackTrace) {
          if (LOGGING_SWITCH) {
            _logger.error('HomeScreen: Error in Dutch game play button handler', error: e, stackTrace: stackTrace);
          }
        }
      },
      heightPercentage: 0.25, // 25% of available height (max card height)
      priority: 90, // Lower number sorts first in home carousel
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
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ HomeScreenFeatureRegistrar: Dutch game play button registered');
    }
  }

  /// Register Dutch game demo button
  void registerDutchGameDemoButton(BuildContext context) {
    if (LOGGING_SWITCH) {
      _logger.info('🎮 HomeScreenFeatureRegistrar: Registering Dutch game demo button');
    }
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_demo',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Demo',
      iconSvgPath: 'assets/images/icons/learn-icon.svg',
      onTap: () {
        if (LOGGING_SWITCH) {
          _logger.info('HomeScreen: Dutch game demo button pressed');
        }
        AnalyticsService.logEvent(name: 'home_demo_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          if (LOGGING_SWITCH) {
            _logger.debug('HomeScreen: NavigationManager obtained, navigating to /dutch/demo');
          }
          navigationManager.navigateTo('/dutch/demo');
          if (LOGGING_SWITCH) {
            _logger.debug('HomeScreen: Navigation to /dutch/demo initiated');
          }
        } catch (e, stackTrace) {
          if (LOGGING_SWITCH) {
            _logger.error('HomeScreen: Error in Dutch game demo button handler', error: e, stackTrace: stackTrace);
          }
        }
      },
      heightPercentage: 0.25, // 25% of available height (max card height)
      priority: 100, // After play (90) in ascending home carousel order
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
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ HomeScreenFeatureRegistrar: Dutch game demo button registered');
    }
  }

  /// Unregister all home screen features
  void unregisterAll() {
    _registry.clearScope(HomeScreenFeatureSlots.scopeKey);
  }
}

