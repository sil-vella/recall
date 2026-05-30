import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'dutch_direct_share_channel.dart';
import 'dutch_share_asset_loader.dart';
import 'dutch_share_method.dart';
import 'dutch_share_package_names.dart';
import 'dutch_share_platform.dart';
import 'dutch_share_template.dart';

/// Routes celebration share to Android direct intents or share_plus fallback.
class DutchSharePlatformRouter {
  DutchSharePlatformRouter._();

  /// iPad / macOS popover anchor for [Share.shareXFiles].
  static Rect? shareOriginFromContext(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  static Future<DutchShareRouteResult> shareTemplate({
    required DutchSharePlatform platform,
    required DutchShareTemplate template,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    if (kIsWeb) {
      return _shareLinkOnly(text);
    }

    final file = await DutchShareAssetLoader.copyAssetToTempFile(template.assetPath);
    if (file == null) {
      return const DutchShareRouteResult(
        status: 'missing_asset',
        shareMethod: DutchShareMethod.sharePlus,
      );
    }

    final mime = DutchShareAssetLoader.mimeTypeForTemplate(template) ?? '*/*';

    if (Platform.isAndroid &&
        DutchSharePackageNames.supportsDirectAndroidShare(platform)) {
      final packageName =
          await DutchDirectShareChannel.resolvePackageForPlatform(platform);
      if (packageName != null) {
        final direct = await DutchDirectShareChannel.shareToApp(
          packageName: packageName,
          filePath: file.path,
          mimeType: mime,
          text: text,
        );
        if (direct == DutchDirectShareStatus.success) {
          return DutchShareRouteResult(
            status: 'success',
            shareMethod: DutchShareMethod.directAndroid,
          );
        }
      }
    }

    return _shareViaSharePlus(
      filePath: file.path,
      mimeType: mime,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<DutchShareRouteResult> shareLinkOnly(String text) async {
    return _shareLinkOnly(text);
  }

  static Future<DutchShareRouteResult> _shareLinkOnly(String text) async {
    try {
      final result = await Share.shareWithResult(
        text,
        sharePositionOrigin: null,
      );
      return DutchShareRouteResult(
        status: _statusFromResult(result),
        shareMethod: DutchShareMethod.linkOnly,
      );
    } catch (_) {
      return DutchShareRouteResult(
        status: 'unavailable',
        shareMethod: DutchShareMethod.linkOnly,
      );
    }
  }

  static Future<DutchShareRouteResult> _shareViaSharePlus({
    required String filePath,
    required String mimeType,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    try {
      final result = await Share.shareXFiles(
        [XFile(filePath, mimeType: mimeType)],
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      );
      return DutchShareRouteResult(
        status: _statusFromResult(result),
        shareMethod: DutchShareMethod.sharePlus,
      );
    } catch (_) {
      return DutchShareRouteResult(
        status: 'unavailable',
        shareMethod: DutchShareMethod.sharePlus,
      );
    }
  }

  static String _statusFromResult(ShareResult result) {
    switch (result.status) {
      case ShareResultStatus.success:
        return 'success';
      case ShareResultStatus.dismissed:
        return 'dismissed';
      case ShareResultStatus.unavailable:
        return 'unavailable';
    }
  }
}

class DutchShareRouteResult {
  const DutchShareRouteResult({
    required this.status,
    required this.shareMethod,
  });

  final String status;
  final String shareMethod;
}
