import 'package:flutter/material.dart';

import '../../../utils/consts/theme_consts.dart';

/// Dark plum panel used on [AccountScreen] (matches Account Information block).
BoxDecoration accountPanelDecoration() {
  return BoxDecoration(
    color: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: AppColors.accentContrast.withValues(alpha: 0.35),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.black.withValues(alpha: 0.18),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

/// Outlined actions on dark account panels (admin, premium sync, etc.).
ButtonStyle accountPanelOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.accentColor,
    side: BorderSide(color: AppColors.accentColor),
    padding: EdgeInsets.symmetric(
      vertical: AppPadding.mediumPadding.top,
      horizontal: AppPadding.defaultPadding.left,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppBorderRadius.large),
    ),
  );
}
