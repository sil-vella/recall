import '../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';

/// Pure business logic for interstitial ads
/// Contains no Flutter/system dependencies
class InterstitialAdModule {
  static final Logger _log = Logger();
  
  final String adUnitId;
  bool _isAdReady = false;
  Map<String, dynamic> _adData = {};

  /// ✅ Constructor
  InterstitialAdModule(this.adUnitId);

  /// ✅ Load interstitial ad (business logic only)
  Future<Map<String, dynamic>> loadAd() async {
    _log.info('📢 Loading Interstitial Ad for ID: $adUnitId');
    
    // Simulate ad loading (orchestrator will handle actual loading)
          _isAdReady = true;
    _adData = {
      'adUnitId': adUnitId,
      'type': 'interstitial',
      'loadedAt': DateTime.now().toIso8601String(),
      'isReady': true,
    };

    return {
      'success': true,
      'message': 'Interstitial ad loaded successfully',
      'adUnitId': adUnitId,
      'isReady': true,
      'adData': _adData,
    };
  }

  /// ✅ Show interstitial ad (business logic only)
  Future<Map<String, dynamic>> showAd() async {
    if (!_isAdReady) {
      _log.error('❌ Interstitial Ad not ready for ID: $adUnitId');
      return {
        'success': false,
        'message': 'Ad not ready',
        'adUnitId': adUnitId,
        'isReady': false,
      };
    }

      _log.info('🎬 Showing Interstitial Ad for ID: $adUnitId');
    
    // Simulate ad showing (orchestrator will handle actual showing)
    _isAdReady = false;
    _adData['shownAt'] = DateTime.now().toIso8601String();
    _adData['isReady'] = false;

    return {
      'success': true,
      'message': 'Interstitial ad shown successfully',
      'adUnitId': adUnitId,
      'isReady': false,
      'adData': _adData,
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
    _log.info('🗑 Interstitial Ad disposed for ID: $adUnitId');
    
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
        'hookName': 'interstitial_ad_ready',
        'description': 'Triggered when interstitial ad is ready to show',
        'priority': 5,
      },
      {
        'hookName': 'interstitial_ad_shown',
        'description': 'Triggered when interstitial ad is shown',
        'priority': 5,
      },
    ];
  }

  /// ✅ Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/ads/interstitial/load',
        'method': 'POST',
        'description': 'Load interstitial ad',
      },
      {
        'route': '/ads/interstitial/show',
        'method': 'POST',
        'description': 'Show interstitial ad',
      },
      {
        'route': '/ads/interstitial/status',
        'method': 'GET',
        'description': 'Get interstitial ad status',
      },
    ];
  }

  /// ✅ Get config requirements
  List<String> getConfigRequirements() {
    return [
      'admobsInterstitial01',
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
}
