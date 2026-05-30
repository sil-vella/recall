import 'package:flutter/services.dart';

import 'dutch_share_package_names.dart';
import 'dutch_share_platform.dart';

/// Result of a native Android direct-share intent.
enum DutchDirectShareStatus {
  success,
  appNotInstalled,
  error,
}

/// MethodChannel bridge to [DutchDirectShareHandler] on Android.
class DutchDirectShareChannel {
  DutchDirectShareChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.reignofplay.dutch/direct_share',
  );

  /// Test override for unit tests (`null` restores platform channel).
  static Future<DutchDirectShareStatus> Function({
    required String packageName,
    required String filePath,
    required String mimeType,
    String? text,
  })? testShareHandler;

  static Future<bool> Function(String packageName)? testIsInstalledHandler;
  static Future<String?> Function()? testResolveTikTokHandler;

  static Future<bool> isAppInstalled(String packageName) async {
    if (testIsInstalledHandler != null) {
      return testIsInstalledHandler!(packageName);
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAppInstalled',
        {'packageName': packageName},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String?> resolveTikTokPackage() async {
    if (testResolveTikTokHandler != null) {
      return testResolveTikTokHandler!();
    }
    try {
      return await _channel.invokeMethod<String>('resolveTikTokPackage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<DutchDirectShareStatus> shareToApp({
    required String packageName,
    required String filePath,
    required String mimeType,
    String? text,
  }) async {
    if (testShareHandler != null) {
      return testShareHandler!(
        packageName: packageName,
        filePath: filePath,
        mimeType: mimeType,
        text: text,
      );
    }
    try {
      final result = await _channel.invokeMethod<String>(
        'shareToApp',
        {
          'packageName': packageName,
          'filePath': filePath,
          'mimeType': mimeType,
          'text': text,
        },
      );
      return _parseStatus(result);
    } on PlatformException {
      return DutchDirectShareStatus.error;
    } on MissingPluginException {
      return DutchDirectShareStatus.error;
    }
  }

  static Future<String?> resolvePackageForPlatform(
    DutchSharePlatform platform,
  ) async {
    switch (platform) {
      case DutchSharePlatform.facebook:
        final installed = await isAppInstalled(DutchSharePackageNames.facebook);
        return installed ? DutchSharePackageNames.facebook : null;
      case DutchSharePlatform.tiktok:
        return resolveTikTokPackage();
    }
  }

  static DutchDirectShareStatus _parseStatus(String? value) {
    switch (value) {
      case 'success':
        return DutchDirectShareStatus.success;
      case 'app_not_installed':
        return DutchDirectShareStatus.appNotInstalled;
      default:
        return DutchDirectShareStatus.error;
    }
  }
}
