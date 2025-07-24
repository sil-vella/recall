import '../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';

/// Pure business logic for rewarded ads
/// Contains no Flutter/system dependencies
class RewardedAdModule {
  static final Logger _log = Logger();
  
  final String adUnitId;
  bool _isAdReady = false;
  Map<String, dynamic> _adData = {};

  /// ✅ Constructor
  RewardedAdModule(this.adUnitId);

  /// ✅ Load rewarded ad (business logic only)
  Future<Map<String, dynamic>> loadAd() async {
    _log.info('📢 Loading Rewarded Ad for ID: $adUnitId');
    
    // Simulate ad loading (orchestrator will handle actual loading)
          _isAdReady = true;
    _adData = {
      'adUnitId': adUnitId,
      'type': 'rewarded',
      'loadedAt': DateTime.now().toIso8601String(),
      'isReady': true,
    };

    return {
      'success': true,
      'message': 'Rewarded ad loaded successfully',
      'adUnitId': adUnitId,
      'isReady': true,
      'adData': _adData,
    };
  }

  /// ✅ Show rewarded ad (business logic only)
  Future<Map<String, dynamic>> showAd({
    Map<String, dynamic>? onUserEarnedReward,
    Map<String, dynamic>? onAdDismissed,
  }) async {
    if (!_isAdReady) {
      _log.error('❌ Rewarded Ad not ready for ID: $adUnitId');
      return {
        'success': false,
        'message': 'Ad not ready',
        'adUnitId': adUnitId,
        'isReady': false,
      };
    }

      _log.info('🎬 Showing Rewarded Ad for ID: $adUnitId');

    // Simulate ad showing (orchestrator will handle actual showing)
    _isAdReady = false;
    _adData['shownAt'] = DateTime.now().toIso8601String();
    _adData['isReady'] = false;
    _adData['userEarnedReward'] = onUserEarnedReward != null;
    _adData['adDismissed'] = onAdDismissed != null;

    return {
      'success': true,
      'message': 'Rewarded ad shown successfully',
      'adUnitId': adUnitId,
      'isReady': false,
      'adData': _adData,
      'callbacks': {
        'onUserEarnedReward': onUserEarnedReward,
        'onAdDismissed': onAdDismissed,
      },
    };
          }

  /// ✅ Get ad status
  Map<String, dynamic> getAdStatus() {
    return {
      'adUnitId': adUnitId,
      'isReady': _isAdReady,
      'adData': _adData,
    };
  }

  /// ✅ Dispose ad
  Map<String, dynamic> disposeAd() {
          _isAdReady = false;
    _adData.clear();
    _log.info('🗑 Rewarded Ad disposed for ID: $adUnitId');
    
    return {
      'success': true,
      'message': 'Ad disposed successfully',
      'adUnitId': adUnitId,
    };
  }

  /// ✅ Get hooks needed by this module
  List<Map<String, dynamic>> getHooksNeeded() {
    return [
      {
        'hookName': 'rewarded_ad_ready',
        'description': 'Triggered when rewarded ad is ready to show',
        'priority': 5,
      },
      {
        'hookName': 'rewarded_ad_shown',
        'description': 'Triggered when rewarded ad is shown',
        'priority': 5,
      },
      {
        'hookName': 'user_earned_reward',
        'description': 'Triggered when user earns reward',
        'priority': 10,
      },
    ];
  }

  /// ✅ Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/ads/rewarded/load',
        'method': 'POST',
        'description': 'Load rewarded ad',
      },
      {
        'route': '/ads/rewarded/show',
        'method': 'POST',
        'description': 'Show rewarded ad',
      },
      {
        'route': '/ads/rewarded/status',
        'method': 'GET',
        'description': 'Get rewarded ad status',
      },
    ];
  }

  /// ✅ Get config requirements
  List<String> getConfigRequirements() {
    return [
      'admobsRewarded01',
    ];
  }

  /// ✅ Validate ad unit ID
  bool validateAdUnitId() {
    if (adUnitId.isEmpty) {
      _log.error('❌ Ad unit ID cannot be empty');
      return false;
    }
    
    if (!adUnitId.startsWith('ca-app-pub-')) {
      _log.error('❌ Invalid ad unit ID format: $adUnitId');
      return false;
    }
    
    return true;
  }

  /// ✅ Check if ad is ready
  bool get isAdReady => _isAdReady;

  /// ✅ Get ad unit ID
  String get getAdUnitId => adUnitId;

  /// ✅ Process reward earning
  Map<String, dynamic> processRewardEarning() {
    _log.info('🏆 User earned reward for ad: $adUnitId');
    
    return {
      'success': true,
      'message': 'Reward processed successfully',
      'adUnitId': adUnitId,
      'rewardEarned': true,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// ✅ Process ad dismissal
  Map<String, dynamic> processAdDismissal() {
    _log.info('✅ Rewarded ad dismissed for ID: $adUnitId');
    
    return {
      'success': true,
      'message': 'Ad dismissed successfully',
      'adUnitId': adUnitId,
      'dismissed': true,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
