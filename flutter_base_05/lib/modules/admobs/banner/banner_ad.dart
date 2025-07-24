import '../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';

/// Pure business logic for banner ads
/// Contains no Flutter/system dependencies
class BannerAdModule {
  static final Logger _log = Logger();
  
  final Map<String, bool> _adLoaded = {};
  final Map<String, dynamic> _adData = {};

  /// ✅ Constructor
  BannerAdModule();

  /// ✅ Load banner ad (business logic only)
  Future<Map<String, dynamic>> loadBannerAd(String adUnitId) async {
    if (_adLoaded[adUnitId] == true) {
      _log.info('🔄 Banner Ad already loaded for ID: $adUnitId');
      return {
        'success': true,
        'message': 'Ad already loaded',
        'adUnitId': adUnitId,
        'isLoaded': true
      };
    }

    _log.info('📢 Loading Banner Ad for ID: $adUnitId');

    // Simulate ad loading (orchestrator will handle actual loading)
          _adLoaded[adUnitId] = true;
    _adData[adUnitId] = {
      'adUnitId': adUnitId,
      'size': 'banner',
      'loadedAt': DateTime.now().toIso8601String(),
    };

    return {
      'success': true,
      'message': 'Ad loaded successfully',
      'adUnitId': adUnitId,
      'isLoaded': true,
      'adData': _adData[adUnitId]
    };
    }

  /// ✅ Get banner ad status
  Map<String, dynamic> getBannerAdStatus(String adUnitId) {
    final isLoaded = _adLoaded[adUnitId] == true;
    return {
      'adUnitId': adUnitId,
      'isLoaded': isLoaded,
      'adData': isLoaded ? _adData[adUnitId] : null,
    };
  }

  /// ✅ Dispose banner ad
  Map<String, dynamic> disposeBannerAd(String adUnitId) {
    if (_adLoaded.containsKey(adUnitId)) {
      _adLoaded.remove(adUnitId);
      _adData.remove(adUnitId);
      _log.info('🗑 Banner Ad disposed for ID: $adUnitId');
      return {
        'success': true,
        'message': 'Ad disposed successfully',
        'adUnitId': adUnitId,
      };
    } else {
      _log.error('⚠️ Tried to dispose non-existing Banner Ad for ID: $adUnitId');
      return {
        'success': false,
        'message': 'Ad not found',
        'adUnitId': adUnitId,
      };
    }
  }

  /// ✅ Get hooks needed by this module
  List<Map<String, dynamic>> getHooksNeeded() {
    return [
      {
        'hookName': 'top_banner_bar_loaded',
        'description': 'Triggered when top banner bar is loaded',
        'priority': 10,
      },
      {
        'hookName': 'bottom_banner_bar_loaded',
        'description': 'Triggered when bottom banner bar is loaded',
        'priority': 10,
      },
    ];
  }

  /// ✅ Get routes needed by this module
  List<Map<String, dynamic>> getRoutesNeeded() {
    return [
      {
        'route': '/ads/banner/load',
        'method': 'POST',
        'description': 'Load banner ad',
      },
      {
        'route': '/ads/banner/status',
        'method': 'GET',
        'description': 'Get banner ad status',
      },
      {
        'route': '/ads/banner/dispose',
        'method': 'POST',
        'description': 'Dispose banner ad',
      },
    ];
  }

  /// ✅ Get config requirements
  List<String> getConfigRequirements() {
    return [
      'admobsTopBanner',
      'admobsBottomBanner',
    ];
  }

  /// ✅ Validate ad unit ID
  bool validateAdUnitId(String adUnitId) {
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

  /// ✅ Get all loaded ads
  Map<String, dynamic> getAllLoadedAds() {
    return {
      'loadedAds': _adLoaded.keys.toList(),
      'totalLoaded': _adLoaded.length,
      'adData': _adData,
    };
  }

  /// ✅ Clear all ads
  Map<String, dynamic> clearAllAds() {
    final count = _adLoaded.length;
    _adLoaded.clear();
    _adData.clear();
    _log.info('🗑 Cleared all banner ads ($count ads)');
    return {
      'success': true,
      'message': 'All ads cleared',
      'clearedCount': count,
    };
  }
}
