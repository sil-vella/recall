import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../utils/analytics_service.dart';
import '../../../utils/consts/config.dart';
import '../../../utils/consts/theme_consts.dart';
import '../widgets/ui_kit/dutch_share_picker_sheet.dart';
import 'dutch_share_method.dart';
import 'dutch_share_moment.dart';
import 'dutch_share_platform.dart';
import 'dutch_share_platform_router.dart';
import 'dutch_share_template.dart';

/// Resolves bundled share templates and opens share targets (direct or sheet).
class DutchShareHelper {
  DutchShareHelper._();

  static String storeUrl({String? storeUrlOverride}) {
    if (storeUrlOverride != null && storeUrlOverride.isNotEmpty) {
      return storeUrlOverride;
    }
    if (!kIsWeb && Platform.isIOS) {
      final ios = Config.appStoreUrl.trim();
      if (ios.isNotEmpty) return ios;
    }
    return Config.playStoreUrl.trim();
  }

  static String shareTextFor({
    required DutchShareTextKind textKind,
    String? storeUrlOverride,
  }) {
    final url = storeUrl(storeUrlOverride: storeUrlOverride);
    switch (textKind) {
      case DutchShareTextKind.storeLink:
        return url;
      case DutchShareTextKind.tiktokCaption:
        return 'Play Dutch Card Game!\n$url';
    }
  }

  /// Shows platform picker (Facebook / TikTok) for the celebration [moment].
  static Future<void> showSharePicker({
    required BuildContext context,
    required DutchShareMoment moment,
  }) async {
    await AnalyticsService.logEvent(
      name: 'dutch_share_picker_opened',
      parameters: {'moment': moment.analyticsValue},
    );
    if (!context.mounted) return;
    await DutchSharePickerSheet.show(context, moment);
  }

  /// Shares a bundled template for [platform].
  static Future<void> shareTemplate({
    required BuildContext context,
    required DutchShareMoment moment,
    required DutchSharePlatform platform,
    required DutchShareTemplate template,
    Rect? sharePositionOrigin,
  }) async {
    await AnalyticsService.logEvent(
      name: 'dutch_share_tapped',
      parameters: {
        'moment': moment.analyticsValue,
        'platform': platform.analyticsValue,
      },
    );

    final text = shareTextFor(textKind: template.textKind);
    if (text.isEmpty) {
      await _logCompleted(
        moment: moment,
        platform: platform,
        status: 'unavailable',
        shareMethod: DutchShareMethod.sharePlus,
      );
      if (context.mounted) {
        _showError(context, 'Sharing is not available right now.');
      }
      return;
    }

    final routeResult = await DutchSharePlatformRouter.shareTemplate(
      platform: platform,
      template: template,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
    );

    await _logCompleted(
      moment: moment,
      platform: platform,
      status: routeResult.status,
      shareMethod: routeResult.shareMethod,
    );

    if (!context.mounted) return;

    if (routeResult.status == 'missing_asset') {
      _showError(
        context,
        'Share file missing. Add ${template.assetPath} to assets.',
      );
    } else if (routeResult.status == 'unavailable') {
      _showError(context, 'Sharing is not available on this device.');
    }
  }

  static Future<void> _logCompleted({
    required DutchShareMoment moment,
    required DutchSharePlatform platform,
    required String status,
    required String shareMethod,
  }) async {
    await AnalyticsService.logEvent(
      name: 'dutch_share_completed',
      parameters: {
        'moment': moment.analyticsValue,
        'platform': platform.analyticsValue,
        'status': status,
        'share_method': shareMethod,
      },
    );
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }
}
