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

  /// Label style for home carousel; icon color is enforced in [FeatureSlot].
  static TextStyle get _homeButtonLabelStyle => AppTextStyles.headingMedium().copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.bold,
      );
  /// Register Dutch game play button
  void registerDutchGamePlayButton(BuildContext context) {
    
    
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: 'dutch_game_play',
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: 'Play Dutch',
      tileAssetPath: 'assets/images/icons/play-dutch.webp',
      onTap: () {
        
        AnalyticsService.logEvent(name: 'home_play_dutch_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          
          navigationManager.navigateTo('/dutch/lobby');
          
        } catch (e, stackTrace) {
          
        }
      },
      heightPercentage: 0.28, // 28% of available height (max card height)
      priority: 10,
      textStyle: _homeButtonLabelStyle,
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
      tileAssetPath: 'assets/images/icons/demo.webp',
      onTap: () {
        
        AnalyticsService.logEvent(name: 'home_demo_tap');
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          
          navigationManager.navigateTo('/dutch/demo');
          
        } catch (e, stackTrace) {
          
        }
      },
      heightPercentage: 0.28, // 28% of available height (max card height)
      priority: 20,
      textStyle: _homeButtonLabelStyle,
    );
    
    _registry.register(
      scopeKey: HomeScreenFeatureSlots.scopeKey,
      feature: feature,
      context: context,
    );
    
    
  }

  void registerLeaderboardButton(BuildContext context) {
    _registerNavButton(
      context: context,
      featureId: 'home_leaderboard',
      text: 'Leaderboard',
      tileAssetPath: 'assets/images/icons/leaderboard.webp',
      path: '/dutch/leaderboard',
      analyticsName: 'home_leaderboard_tap',
      priority: 30,
    );
  }

  void registerCustomizeButton(BuildContext context) {
    _registerNavButton(
      context: context,
      featureId: 'home_customize',
      text: 'Customize',
      tileAssetPath: 'assets/images/icons/customize.webp',
      path: '/dutch-customize',
      analyticsName: 'home_customize_tap',
      priority: 40,
    );
  }

  void registerAccountButton(BuildContext context) {
    _registerNavButton(
      context: context,
      featureId: 'home_account',
      text: 'Account',
      tileAssetPath: 'assets/images/icons/account.webp',
      path: '/account',
      analyticsName: 'home_account_tap',
      priority: 50,
    );
  }

  void _registerNavButton({
    required BuildContext context,
    required String featureId,
    required String text,
    required String tileAssetPath,
    required String path,
    required String analyticsName,
    required int priority,
  }) {
    final feature = HomeScreenButtonFeatureDescriptor(
      featureId: featureId,
      slotId: HomeScreenFeatureSlots.slotButtons,
      text: text,
      tileAssetPath: tileAssetPath,
      onTap: () {
        AnalyticsService.logEvent(name: analyticsName);
        try {
          Provider.of<NavigationManager>(context, listen: false).navigateTo(path);
        } catch (e, stackTrace) {
          // Navigation failure is surfaced by router / screen layer.
        }
      },
      heightPercentage: 0.28,
      priority: priority,
      textStyle: _homeButtonLabelStyle,
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

