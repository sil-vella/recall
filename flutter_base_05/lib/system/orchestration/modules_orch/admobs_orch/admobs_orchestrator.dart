import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';
import '../../../managers/hooks_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/services_manager.dart';
import '../../../services/shared_preferences.dart';
import '../base_files/module_orch_base.dart';
import '../../../../modules/admobs/banner/banner_ad.dart';
import '../../../../modules/admobs/interstitial/interstitial_ad.dart';
import '../../../../modules/admobs/rewarded/rewarded_ad.dart';

/// AdMobs Orchestrator - Handles system integration for all ad types
/// Delegates business logic to pure modules
class AdMobsOrchestrator extends ModuleOrchestratorBase {
  static final Logger _log = Logger();
  
  // Pure business logic modules
  late BannerAdModule _bannerModule;
  late InterstitialAdModule _interstitialModule;
  late RewardedAdModule _rewardedModule;
  
  // Flutter-specific ad instances
  final Map<String, BannerAd> _bannerAds = {};
  final Map<String, InterstitialAd> _interstitialAds = {};
  final Map<String, RewardedAd> _rewardedAds = {};

  @override
  void initialize(BuildContext context) {
    _log.info('🎼 Initializing AdMobs Orchestrator...');
    
    // Initialize pure business logic modules
    _bannerModule = BannerAdModule();
    _interstitialModule = InterstitialAdModule(Config.admobsInterstitial01);
    _rewardedModule = RewardedAdModule(Config.admobsRewarded01);
    
    // Register hooks and routes
    _registerHooks();
    _registerRoutes();
    
    _log.info('✅ AdMobs Orchestrator initialized successfully');
  }

  @override
  void _registerHooks() {
    _log.info('🔗 Registering AdMobs hooks...');
    
    // Register hooks from banner module
    final bannerHooks = _bannerModule.getHooksNeeded();
    for (final hook in bannerHooks) {
      hooksManager.registerHookWithData(hook['hookName'], (data) {
        _log.info('📢 ${hook['hookName']} hook triggered');
        _handleBannerHook(hook['hookName'], data);
      }, priority: hook['priority']);
    }
    
    // Register hooks from interstitial module
    final interstitialHooks = _interstitialModule.getHooksNeeded();
    for (final hook in interstitialHooks) {
      hooksManager.registerHookWithData(hook['hookName'], (data) {
        _log.info('📢 ${hook['hookName']} hook triggered');
        _handleInterstitialHook(hook['hookName'], data);
      }, priority: hook['priority']);
    }
    
    // Register hooks from rewarded module
    final rewardedHooks = _rewardedModule.getHooksNeeded();
    for (final hook in rewardedHooks) {
      hooksManager.registerHookWithData(hook['hookName'], (data) {
        _log.info('📢 ${hook['hookName']} hook triggered');
        _handleRewardedHook(hook['hookName'], data);
      }, priority: hook['priority']);
    }
    
    _log.info('✅ AdMobs hooks registered successfully');
  }

  @override
  void _registerRoutes() {
    _log.info('🛣️ Registering AdMobs routes...');
    
    // Register routes from all modules
    final allRoutes = [
      ..._bannerModule.getRoutesNeeded(),
      ..._interstitialModule.getRoutesNeeded(),
      ..._rewardedModule.getRoutesNeeded(),
    ];
    
    for (final route in allRoutes) {
      _log.info('🛣️ Route: ${route['method']} ${route['route']} - ${route['description']}');
      // Routes would be registered with navigation system here
    }
    
    _log.info('✅ AdMobs routes registered successfully');
  }

  /// Handle banner ad hooks
  void _handleBannerHook(String hookName, Map<String, dynamic> data) {
    switch (hookName) {
      case 'top_banner_bar_loaded':
        _loadBannerAd(Config.admobsTopBanner);
        break;
      case 'bottom_banner_bar_loaded':
        _loadBannerAd(Config.admobsBottomBanner);
        break;
    }
  }

  /// Handle interstitial ad hooks
  void _handleInterstitialHook(String hookName, Map<String, dynamic> data) {
    switch (hookName) {
      case 'interstitial_ad_ready':
        _loadInterstitialAd();
        break;
      case 'interstitial_ad_shown':
        _showInterstitialAd();
        break;
    }
  }

  /// Handle rewarded ad hooks
  void _handleRewardedHook(String hookName, Map<String, dynamic> data) {
    switch (hookName) {
      case 'rewarded_ad_ready':
        _loadRewardedAd();
        break;
      case 'rewarded_ad_shown':
        _showRewardedAd();
        break;
      case 'user_earned_reward':
        _processRewardEarning();
        break;
    }
  }

  /// Load banner ad with system integration
  Future<void> _loadBannerAd(String adUnitId) async {
    _log.info('📢 Loading banner ad: $adUnitId');
    
    // Call business logic module
    final result = await _bannerModule.loadBannerAd(adUnitId);
    
    if (result['success']) {
      // Create actual Flutter BannerAd
      final bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            _log.info('✅ Banner Ad loaded: $adUnitId');
            _updateBannerState(adUnitId, true);
          },
          onAdFailedToLoad: (Ad ad, LoadAdError error) {
            _log.error('❌ Banner Ad failed to load: $adUnitId - ${error.message}');
            ad.dispose();
            _updateBannerState(adUnitId, false);
          },
        ),
      );
      
      await bannerAd.load();
      _bannerAds[adUnitId] = bannerAd;
      
      // Update state
      stateManager.updateModuleState('admobs_banner', {
        'adUnitId': adUnitId,
        'isLoaded': true,
        'adData': result['adData'],
      });
    }
  }

  /// Load interstitial ad with system integration
  Future<void> _loadInterstitialAd() async {
    _log.info('📢 Loading interstitial ad');
    
    // Call business logic module
    final result = await _interstitialModule.loadAd();
    
    if (result['success']) {
      // Create actual Flutter InterstitialAd
      InterstitialAd.load(
        adUnitId: Config.admobsInterstitial01,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAds[Config.admobsInterstitial01] = ad;
            _log.info('✅ Interstitial Ad loaded');
            _updateInterstitialState(true);
          },
          onAdFailedToLoad: (error) {
            _log.error('❌ Interstitial Ad failed to load: ${error.message}');
            _updateInterstitialState(false);
          },
        ),
      );
      
      // Update state
      stateManager.updateModuleState('admobs_interstitial', {
        'adUnitId': Config.admobsInterstitial01,
        'isReady': true,
        'adData': result['adData'],
      });
    }
  }

  /// Load rewarded ad with system integration
  Future<void> _loadRewardedAd() async {
    _log.info('📢 Loading rewarded ad');
    
    // Call business logic module
    final result = await _rewardedModule.loadAd();
    
    if (result['success']) {
      // Create actual Flutter RewardedAd
      RewardedAd.load(
        adUnitId: Config.admobsRewarded01,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAds[Config.admobsRewarded01] = ad;
            _log.info('✅ Rewarded Ad loaded');
            _updateRewardedState(true);
          },
          onAdFailedToLoad: (error) {
            _log.error('❌ Rewarded Ad failed to load: ${error.message}');
            _updateRewardedState(false);
          },
        ),
      );
      
      // Update state
      stateManager.updateModuleState('admobs_rewarded', {
        'adUnitId': Config.admobsRewarded01,
        'isReady': true,
        'adData': result['adData'],
      });
    }
  }

  /// Show interstitial ad with system integration
  Future<void> _showInterstitialAd() async {
    _log.info('🎬 Showing interstitial ad');
    
    // Call business logic module
    final result = await _interstitialModule.showAd();
    
    if (result['success']) {
      final ad = _interstitialAds[Config.admobsInterstitial01];
      if (ad != null) {
        ad.show();
        _interstitialAds.remove(Config.admobsInterstitial01);
        
        // Update state
        stateManager.updateModuleState('admobs_interstitial', {
          'adUnitId': Config.admobsInterstitial01,
          'isReady': false,
          'adData': result['adData'],
        });
        
        // Preload next ad
        _loadInterstitialAd();
      }
    }
  }

  /// Show rewarded ad with system integration
  Future<void> _showRewardedAd() async {
    _log.info('🎬 Showing rewarded ad');
    
    // Call business logic module
    final result = await _rewardedModule.showAd();
    
    if (result['success']) {
      final ad = _rewardedAds[Config.admobsRewarded01];
      if (ad != null) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (Ad ad) {
            _log.info('✅ Rewarded Ad dismissed');
            _processAdDismissal();
          },
          onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
            _log.error('❌ Failed to show Rewarded Ad: $error');
          },
        );
        
        ad.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
            _log.info('🏆 User earned reward');
            _processRewardEarning();
          },
        );
        
        _rewardedAds.remove(Config.admobsRewarded01);
        
        // Update state
        stateManager.updateModuleState('admobs_rewarded', {
          'adUnitId': Config.admobsRewarded01,
          'isReady': false,
          'adData': result['adData'],
        });
      }
    }
  }

  /// Process reward earning
  void _processRewardEarning() {
    final result = _rewardedModule.processRewardEarning();
    
    // Update shared preferences
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    if (sharedPref != null) {
      int rewardedViews = sharedPref.getInt('rewarded_ad_views') ?? 0;
      sharedPref.setInt('rewarded_ad_views', rewardedViews + 1);
    }
    
    // Update state
    stateManager.updateModuleState('admobs_rewarded', {
      'rewardEarned': true,
      'timestamp': result['timestamp'],
    });
    
    // Preload next ad
    _loadRewardedAd();
  }

  /// Process ad dismissal
  void _processAdDismissal() {
    final result = _rewardedModule.processAdDismissal();
    
    // Update state
    stateManager.updateModuleState('admobs_rewarded', {
      'dismissed': true,
      'timestamp': result['timestamp'],
    });
    
    // Preload next ad
    _loadRewardedAd();
  }

  /// Update banner state
  void _updateBannerState(String adUnitId, bool isLoaded) {
    stateManager.updateModuleState('admobs_banner', {
      'adUnitId': adUnitId,
      'isLoaded': isLoaded,
    });
  }

  /// Update interstitial state
  void _updateInterstitialState(bool isReady) {
    stateManager.updateModuleState('admobs_interstitial', {
      'isReady': isReady,
    });
  }

  /// Update rewarded state
  void _updateRewardedState(bool isReady) {
    stateManager.updateModuleState('admobs_rewarded', {
      'isReady': isReady,
    });
  }

  /// Get banner widget
  Widget getBannerWidget(BuildContext context, String adUnitId) {
    final ad = _bannerAds[adUnitId];
    if (ad == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      key: ValueKey('banner_ad_${DateTime.now().millisecondsSinceEpoch}'),
      alignment: Alignment.center,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }

  /// Get top banner widget
  Widget getTopBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsTopBanner);
  }

  /// Get bottom banner widget
  Widget getBottomBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsBottomBanner);
  }

  /// Health check
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': 'admobs_orchestrator',
      'status': 'healthy',
      'details': 'AdMobs orchestrator is running',
      'banner_ads': _bannerAds.length,
      'interstitial_ads': _interstitialAds.length,
      'rewarded_ads': _rewardedAds.length,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _log.info('🗑 Disposing AdMobs Orchestrator...');
    
    // Dispose banner ads
    for (final ad in _bannerAds.values) {
      ad.dispose();
    }
    _bannerAds.clear();
    
    // Dispose interstitial ads
    for (final ad in _interstitialAds.values) {
      ad.dispose();
    }
    _interstitialAds.clear();
    
    // Dispose rewarded ads
    for (final ad in _rewardedAds.values) {
      ad.dispose();
    }
    _rewardedAds.clear();
    
    super.dispose();
    _log.info('✅ AdMobs Orchestrator disposed');
  }
} 