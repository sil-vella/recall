import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../managers/feature_registry_manager.dart';
import '../../../managers/feature_contracts.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';
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
  /// Register Dutch game play button
  void registerDutchGamePlayButton(BuildContext context) {
    
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_play',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Play Dutch',
      iconSvgPath: 'assets/images/icons/play-icon.svg',
      onTap: () {
        
        AnalyticsService.logEvent(name: 'home_play_dutch_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          
          navigationManager.navigateTo('/dutch/lobby');
          
        } catch (e, stackTrace) {
          
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
    
    
  }

  /// Register Dutch game demo button
  void registerDutchGameDemoButton(BuildContext context) {
    
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_demo',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Demo',
      iconSvgPath: 'assets/images/icons/learn-icon.svg',
      onTap: () {
        
        AnalyticsService.logEvent(name: 'home_demo_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          
          navigationManager.navigateTo('/dutch/demo');
          
        } catch (e, stackTrace) {
          
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
    
    
  }

  /// Unregister all home screen features
  void unregisterAll() {
    _registry.clearScope(HomeScreenFeatureSlots.scopeKey);
  }
}

