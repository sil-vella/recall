import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Reusable settings/profile row — adapted from `_SettingsLine` in
/// `assets/games-main/samples/multiplayer/lib/settings/settings_screen.dart`.
///
/// Keeps a consistent visual language for any "label + (optional value/icon)"
/// row across Account, Profile, Lobby and Leaderboard footers.
class DutchSettingsRow extends StatelessWidget {
  const DutchSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.onTap,
    this.semanticIdentifier,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;

  /// A trailing widget (icon, switch, value text, etc.).
  final Widget? trailing;

  final VoidCallback? onTap;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final isInteractive = onTap != null;

    final row = Row(
      children: [
        if (leadingIcon != null) ...[
          Icon(
            leadingIcon,
            size: AppSizes.iconMedium,
            color: AppColors.accentColor2,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium(color: AppColors.white)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          DefaultTextStyle.merge(
            style: AppTextStyles.bodyMedium(color: AppColors.white)
                .copyWith(fontWeight: FontWeight.w600),
            child: IconTheme.merge(
              data: IconThemeData(color: AppColors.accentColor2, size: 22),
              child: trailing!,
            ),
          ),
        ],
      ],
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: row,
    );

    final tile = Container(
      decoration: BoxDecoration(
        color: AppColors.accentContrast.withValues(alpha: 0.18),
        borderRadius: AppBorderRadius.mediumRadius,
        border: Border.all(
          color: AppColors.accentContrast.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      child: isInteractive
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppBorderRadius.mediumRadius,
                child: padded,
              ),
            )
          : padded,
    );

    return Semantics(
      identifier: semanticIdentifier,
      button: isInteractive,
      child: tile,
    );
  }
}

/// Editable value row — adapted from `_NameChangeLine` in the same source.
/// Renders `title` on the left and the current `value` on the right with a
/// pencil affordance, ready to wire to `showDutchEditTextDialog`.
class DutchEditableValueRow extends StatelessWidget {
  const DutchEditableValueRow({
    super.key,
    required this.title,
    required this.value,
    required this.onTapEdit,
    this.placeholder = 'Tap to set',
    this.leadingIcon,
    this.semanticIdentifier,
  });

  final String title;
  final String value;
  final VoidCallback onTapEdit;
  final String placeholder;
  final IconData? leadingIcon;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return DutchSettingsRow(
      title: title,
      leadingIcon: leadingIcon,
      onTap: onTapEdit,
      semanticIdentifier: semanticIdentifier,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              hasValue ? value : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium(
                color: hasValue
                    ? AppColors.white
                    : AppColors.textSecondary,
              ).copyWith(
                fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.edit_outlined,
            size: 18,
            color: AppColors.accentColor2,
          ),
        ],
      ),
    );
  }
}
