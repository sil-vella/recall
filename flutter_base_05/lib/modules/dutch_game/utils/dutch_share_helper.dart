import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../utils/analytics_service.dart';
import '../../../utils/consts/config.dart';
import '../../../utils/consts/theme_consts.dart';
import '../backend_core/utils/dutch_rank_level_change_checker.dart';
import 'dutch_share_moment.dart';
import 'dutch_share_payload.dart';

/// Builds share copy and invokes the native OS share sheet.
class DutchShareHelper {
  DutchShareHelper._();

  /// Store URL for the current platform (testable via [storeUrlOverride]).
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

  static DutchSharePayload buildWinPayload({
    required String winnerMessage,
    String? storeUrlOverride,
  }) {
    final outcome = winnerMessage.trim();
    final body = outcome.isEmpty
        ? 'I just won a match in Dutch Card Game!'
        : 'I just won in Dutch Card Game! $outcome';
    return _payload(
      subject: 'I won in Dutch!',
      body: body,
      storeUrlOverride: storeUrlOverride,
    );
  }

  static DutchSharePayload buildLevelUpPayload({
    required DutchRankLevelChangeResult change,
    String? storeUrlOverride,
  }) {
    final before = change.levelBefore;
    final after = change.levelAfter;
    final levelLine = (before != null && after != null)
        ? 'Level $before → $after'
        : 'I leveled up in Dutch Card Game!';
    final wins = change.winsAfter;
    final winsSuffix = wins != null ? ' • $wins wins' : '';
    return _payload(
      subject: 'Level up in Dutch!',
      body: '$levelLine$winsSuffix',
      storeUrlOverride: storeUrlOverride,
    );
  }

  static DutchSharePayload buildRankUpPayload({
    required DutchRankLevelChangeResult change,
    String? storeUrlOverride,
  }) {
    final before = _capitalise(change.rankBefore);
    final after = _capitalise(change.rankAfter);
    final rankLine = (before != null && after != null)
        ? 'Rank $before → $after'
        : (after != null
            ? "I'm now a $after in Dutch Card Game!"
            : 'I ranked up in Dutch Card Game!');
    final wins = change.winsAfter;
    final winsSuffix = wins != null ? ' • $wins wins' : '';
    return _payload(
      subject: 'Rank up in Dutch!',
      body: '$rankLine$winsSuffix',
      storeUrlOverride: storeUrlOverride,
    );
  }

  static DutchSharePayload buildPayload({
    required DutchShareMoment moment,
    String? winnerMessage,
    DutchRankLevelChangeResult? change,
    String? storeUrlOverride,
  }) {
    switch (moment) {
      case DutchShareMoment.win:
        return buildWinPayload(
          winnerMessage: winnerMessage ?? '',
          storeUrlOverride: storeUrlOverride,
        );
      case DutchShareMoment.levelUp:
        return buildLevelUpPayload(
          change: change ?? DutchRankLevelChangeResult.inconclusive(),
          storeUrlOverride: storeUrlOverride,
        );
      case DutchShareMoment.rankUp:
        return buildRankUpPayload(
          change: change ?? DutchRankLevelChangeResult.inconclusive(),
          storeUrlOverride: storeUrlOverride,
        );
    }
  }

  /// Opens the native share sheet; logs analytics; shows snackbar only on failure.
  static Future<void> share({
    required BuildContext context,
    required DutchSharePayload payload,
    required DutchShareMoment moment,
  }) async {
    await AnalyticsService.logEvent(
      name: 'dutch_share_tapped',
      parameters: {'moment': moment.analyticsValue},
    );

    final url = storeUrl();
    if (url.isEmpty) {
      await _logCompleted(moment, 'unavailable');
      if (context.mounted) {
        _showError(context, 'Sharing is not available right now.');
      }
      return;
    }

    try {
      final result = await Share.shareWithResult(
        payload.text,
        subject: payload.subject,
      );
      final status = _statusFromResult(result);
      await _logCompleted(moment, status);
      if (status == 'unavailable' && context.mounted) {
        _showError(context, 'Sharing is not available on this device.');
      }
    } catch (_) {
      await _logCompleted(moment, 'unavailable');
      if (context.mounted) {
        _showError(context, 'Could not open the share menu.');
      }
    }
  }

  static DutchSharePayload _payload({
    required String subject,
    required String body,
    String? storeUrlOverride,
  }) {
    final url = storeUrl(storeUrlOverride: storeUrlOverride);
    final text = url.isEmpty
        ? '$body\n\nPlay Dutch Card Game!'
        : '$body\n\nPlay Dutch Card Game:\n$url';
    return DutchSharePayload(text: text, subject: subject);
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

  static Future<void> _logCompleted(DutchShareMoment moment, String status) async {
    await AnalyticsService.logEvent(
      name: 'dutch_share_completed',
      parameters: {
        'moment': moment.analyticsValue,
        'status': status,
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

  static String? _capitalise(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }
}
