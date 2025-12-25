import 'package:package_info_plus/package_info_plus.dart';
import '../00_base/service_base.dart';
import 'shared_preferences.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../utils/consts/config.dart';
import '../../tools/logging/logger.dart';

/// Service for checking app version updates
class VersionCheckService extends ServicesBase {
  static final VersionCheckService _instance = VersionCheckService._internal();
  
  factory VersionCheckService() => _instance;
  
  VersionCheckService._internal();
  
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false;
  
  // SharedPreferences keys
  static const String _keyLastCheckedVersion = 'last_checked_app_version';
  static const String _keyLastCheckTimestamp = 'app_version_last_check_timestamp';
  
  SharedPrefManager? _sharedPrefs;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _sharedPrefs = SharedPrefManager();
    await _sharedPrefs!.initialize();
    _isInitialized = true;
    // ConnectionsApiModule will be provided when checking updates
  }
  
  /// Get current app version from platform
  Future<String> getCurrentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      _logger.info('VersionCheck: Current app version: $version', isOn: LOGGING_SWITCH);
      return version;
    } catch (e) {
      _logger.error('VersionCheck: Error getting app version: $e', isOn: LOGGING_SWITCH);
      // Fallback to config value
      return Config.appVersion;
    }
  }
  
  /// Get last checked version from SharedPreferences
  String? getLastCheckedVersion() {
    return _sharedPrefs?.getString(_keyLastCheckedVersion);
  }
  
  /// Get last check timestamp from SharedPreferences
  String? getLastCheckTimestamp() {
    return _sharedPrefs?.getString(_keyLastCheckTimestamp);
  }
  
  /// Save last checked version to SharedPreferences
  Future<void> saveLastCheckedVersion(String version) async {
    try {
      await _sharedPrefs?.setString(_keyLastCheckedVersion, version);
      await _sharedPrefs?.setString(_keyLastCheckTimestamp, DateTime.now().toIso8601String());
      _logger.info('VersionCheck: Saved last checked version: $version', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('VersionCheck: Error saving last checked version: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Compare two semantic versions
  /// Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
  int compareVersions(String version1, String version2) {
    try {
      final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      // Pad shorter version with zeros
      final maxLength = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
      while (v1Parts.length < maxLength) v1Parts.add(0);
      while (v2Parts.length < maxLength) v2Parts.add(0);
      
      for (int i = 0; i < maxLength; i++) {
        if (v1Parts[i] < v2Parts[i]) return -1;
        if (v1Parts[i] > v2Parts[i]) return 1;
      }
      
      return 0;
    } catch (e) {
      _logger.error('VersionCheck: Error comparing versions: $e', isOn: LOGGING_SWITCH);
      return 0; // Assume equal on error
    }
  }
  
  /// Check for available updates with retry logic for connection failures
  /// 
  /// [apiModule] ConnectionsApiModule instance to make API calls
  /// [maxRetries] Maximum number of retry attempts (default: 3)
  /// [retryDelay] Delay between retries in seconds (default: 5)
  /// Returns Map with update information
  Future<Map<String, dynamic>> checkForUpdates(
    ConnectionsApiModule apiModule, {
    int maxRetries = 3,
    int retryDelay = 5,
  }) async {
    // Get current app version once
    final currentVersion = await getCurrentAppVersion();
    _logger.info('VersionCheck: Starting version check (current version: $currentVersion)', isOn: LOGGING_SWITCH);
      
    final route = '/public/check-updates?current_version=$currentVersion';
    int attempt = 0;
    
    while (attempt < maxRetries) {
      attempt++;
      try {
        _logger.info('VersionCheck: Attempt $attempt of $maxRetries', isOn: LOGGING_SWITCH);
      
      // Call API to get server version with current version as query parameter
      final response = await apiModule.sendGetRequest(route);
      
      if (response == null || response is! Map<String, dynamic>) {
          _logger.warning('VersionCheck: Invalid API response (attempt $attempt)', isOn: LOGGING_SWITCH);
          if (attempt < maxRetries) {
            _logger.info('VersionCheck: Retrying in $retryDelay seconds...', isOn: LOGGING_SWITCH);
            await Future.delayed(Duration(seconds: retryDelay));
            continue;
          }
        return {
          'success': false,
          'error': 'Invalid API response',
          'current_version': currentVersion,
        };
      }
        
        // Check if response indicates connection error (should retry)
        final errorMessage = response['error']?.toString() ?? '';
        final isConnectionError = errorMessage.toLowerCase().contains('connection') ||
                                  errorMessage.toLowerCase().contains('network') ||
                                  errorMessage.toLowerCase().contains('timeout') ||
                                  response['success'] != true && attempt < maxRetries;
        
        if (isConnectionError && attempt < maxRetries) {
          _logger.warning('VersionCheck: Connection error on attempt $attempt: $errorMessage', isOn: LOGGING_SWITCH);
          _logger.info('VersionCheck: Retrying in $retryDelay seconds...', isOn: LOGGING_SWITCH);
          await Future.delayed(Duration(seconds: retryDelay));
          continue;
        }
      
      if (response['success'] != true) {
        _logger.warning('VersionCheck: API returned error: ${response['error']}', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': response['error'] ?? 'Unknown error',
          'current_version': currentVersion,
        };
      }
      
      final serverVersion = response['server_version']?.toString() ?? response['current_version']?.toString() ?? response['latest_version']?.toString();
      if (serverVersion == null) {
        _logger.warning('VersionCheck: No version in API response', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': 'No version in API response',
          'current_version': currentVersion,
        };
      }
      
        _logger.info('VersionCheck: Server version: $serverVersion (succeeded on attempt $attempt)', isOn: LOGGING_SWITCH);
      
      // Extract update information from API response
      final updateAvailable = response['update_available'] == true;
      final updateRequired = response['update_required'] == true;
      final downloadLink = response['download_link']?.toString() ?? '';
      
      _logger.info('VersionCheck: Update available: $updateAvailable, Update required: $updateRequired', isOn: LOGGING_SWITCH);
      if (downloadLink.isNotEmpty) {
        _logger.info('VersionCheck: Download link: $downloadLink', isOn: LOGGING_SWITCH);
      }
      
      // Save last checked version
      await saveLastCheckedVersion(currentVersion);
      
      return {
        'success': true,
        'current_version': currentVersion,
        'server_version': serverVersion,
        'update_available': updateAvailable,
        'update_required': updateRequired,
        'download_link': downloadLink,
        'last_checked': DateTime.now().toIso8601String(),
        'app_id': response['app_id'],
        'app_name': response['app_name'],
      };
      
    } catch (e) {
        _logger.error('VersionCheck: Error on attempt $attempt: $e', isOn: LOGGING_SWITCH);
        
        // Check if it's a connection-related error that we should retry
        final errorString = e.toString().toLowerCase();
        final isConnectionError = errorString.contains('connection') ||
                                 errorString.contains('network') ||
                                 errorString.contains('timeout') ||
                                 errorString.contains('socket');
        
        if (isConnectionError && attempt < maxRetries) {
          _logger.info('VersionCheck: Connection error detected, retrying in $retryDelay seconds...', isOn: LOGGING_SWITCH);
          await Future.delayed(Duration(seconds: retryDelay));
          continue;
        }
        
        // If not a connection error or max retries reached, return error
      return {
        'success': false,
        'error': e.toString(),
          'current_version': currentVersion,
      };
    }
    }
    
    // If we get here, all retries failed
    _logger.error('VersionCheck: All $maxRetries attempts failed', isOn: LOGGING_SWITCH);
    return {
      'success': false,
      'error': 'Failed to check for updates after $maxRetries attempts',
      'current_version': currentVersion,
    };
  }
  
  @override
  void dispose() {
    super.dispose();
  }
}
