import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Visual variants for [DutchEmptyStateCard].
enum DutchEmptyStateVariant {
  /// Neutral empty list (uses info / accent tones).
  empty,

  /// Error state (uses [AppColors.errorColor]).
  error,

  /// Informational note.
  info,
}

/// Reusable empty / error / info card — adapted from the empty-state
/// pattern in `assets/flutter-template-master/lib/screen/todo/todo_list/todo_list_screen.dart`.
///
/// Replaces ad-hoc empty/error blocks scattered across screens (lobby,
/// leaderboard, account, etc.) with a single themed card.
class DutchEmptyStateCard extends StatelessWidget {
  const DutchEmptyStateCard({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.variant = DutchEmptyStateVariant.empty,
    this.actionLabel,
    this.onAction,
    this.semanticIdentifier,
  });

  final String message;
  final String? title;
  final IconData? icon;
  final DutchEmptyStateVariant variant;

  /// When set with [onAction], an inline button is rendered (typically "Retry").
  final String? actionLabel;
  final VoidCallback? onAction;

  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(variant);
    final effectiveIcon = icon ?? _defaultIconFor(variant);
    final hasAction = actionLabel != null && onAction != null;

    return Semantics(
      identifier: semanticIdentifier,
      label: title != null ? '${title!} – $message' : message,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Container(
              padding: AppPadding.largePadding,
              decoration: BoxDecoration(
                color: tone.background,
                borderRadius: AppBorderRadius.largeRadius,
                border: Border.all(color: tone.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(effectiveIcon, color: tone.iconColor, size: 36),
                  const SizedBox(height: 12),
                  if (title != null) ...[
                    Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headingSmall(color: AppColors.white),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium(color: AppColors.white)
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (hasAction) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(actionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: tone.actionBackground,
                        foregroundColor: tone.actionForeground,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppBorderRadius.mediumRadius,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _defaultIconFor(DutchEmptyStateVariant v) {
    switch (v) {
      case DutchEmptyStateVariant.empty:
        return Icons.inbox_outlined;
      case DutchEmptyStateVariant.error:
        return Icons.error_outline;
      case DutchEmptyStateVariant.info:
        return Icons.info_outline;
    }
  }

  _Tone _toneFor(DutchEmptyStateVariant v) {
    switch (v) {
      case DutchEmptyStateVariant.empty:
        return _Tone(
          background: AppColors.accentContrast.withValues(alpha: 0.18),
          border: AppColors.accentContrast.withValues(alpha: 0.45),
          iconColor: AppColors.accentColor2,
          actionBackground: AppColors.accentColor,
          actionForeground: AppColors.textOnAccent,
        );
      case DutchEmptyStateVariant.error:
        return _Tone(
          background: AppColors.errorColor.withValues(alpha: 0.16),
          border: AppColors.errorColor.withValues(alpha: 0.55),
          iconColor: AppColors.errorColor,
          actionBackground: AppColors.errorColor,
          actionForeground: AppColors.white,
        );
      case DutchEmptyStateVariant.info:
        return _Tone(
          background: AppColors.infoColor.withValues(alpha: 0.14),
          border: AppColors.infoColor.withValues(alpha: 0.45),
          iconColor: AppColors.infoColor,
          actionBackground: AppColors.infoColor,
          actionForeground: AppColors.white,
        );
    }
  }
}

class _Tone {
  const _Tone({
    required this.background,
    required this.border,
    required this.iconColor,
    required this.actionBackground,
    required this.actionForeground,
  });

  final Color background;
  final Color border;
  final Color iconColor;
  final Color actionBackground;
  final Color actionForeground;
}
