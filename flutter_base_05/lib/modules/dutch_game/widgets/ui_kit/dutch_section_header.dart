import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Compact section header for Lobby / Profile / Leaderboard subsections.
///
/// Shape: `[icon]  Title       [optional trailing chip / widget]`. Pure
/// presentation — does not own any toggle/expand state.
class DutchSectionHeader extends StatelessWidget {
  const DutchSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.subtitle,
    this.dense = false,
    this.semanticIdentifier,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final String? subtitle;
  final bool dense;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final iconSize = dense ? 18.0 : 22.0;
    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    return Semantics(
      identifier: semanticIdentifier,
      header: true,
      label: title,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: AppColors.accentColor2),
              const SizedBox(width: 8),
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
                    style: (dense
                            ? AppTextStyles.bodyMedium(color: AppColors.white)
                            : AppTextStyles.headingSmall(color: AppColors.white))
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
