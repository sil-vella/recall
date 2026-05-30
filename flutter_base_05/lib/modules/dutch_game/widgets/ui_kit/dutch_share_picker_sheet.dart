import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';
import '../../utils/dutch_share_helper.dart';
import '../../utils/dutch_share_moment.dart';
import '../../utils/dutch_share_platform.dart';
import '../../utils/dutch_share_platform_router.dart';
import '../../utils/dutch_share_template.dart';
import '../../utils/dutch_share_template_catalog.dart';

/// Bottom sheet: pick Facebook (image + link) or TikTok (video + caption).
class DutchSharePickerSheet extends StatelessWidget {
  const DutchSharePickerSheet({
    super.key,
    required this.moment,
  });

  final DutchShareMoment moment;

  static Future<void> show(BuildContext context, DutchShareMoment moment) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.scaffoldDeepPlumColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppBorderRadius.large)),
      ),
      builder: (ctx) => DutchSharePickerSheet(moment: moment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platforms = DutchShareTemplateCatalog.platformsFor(moment);

    return SafeArea(
      child: Padding(
        padding: AppPadding.defaultPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share',
              style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            Text(
              _momentHint(moment),
              style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            if (platforms.isEmpty)
              Padding(
                padding: AppPadding.cardPadding,
                child: Text(
                  'Share templates are not configured yet.',
                  style: AppTextStyles.bodyMedium().copyWith(color: AppColors.warningColor),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...platforms.map((platform) {
                final template = DutchShareTemplateCatalog.templateFor(
                  moment: moment,
                  platform: platform,
                );
                return Padding(
                  padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
                  child: _PlatformTile(
                    platform: platform,
                    template: template,
                    onTap: () async {
                      final origin =
                          DutchSharePlatformRouter.shareOriginFromContext(
                        context,
                      );
                      final rootContext = context;
                      Navigator.of(context).pop();
                      if (template == null) return;
                      await DutchShareHelper.shareTemplate(
                        context: rootContext,
                        moment: moment,
                        platform: platform,
                        template: template,
                        sharePositionOrigin: origin,
                      );
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _momentHint(DutchShareMoment moment) {
    switch (moment) {
      case DutchShareMoment.win:
        return 'Share your win';
      case DutchShareMoment.levelUp:
        return 'Share your level up';
      case DutchShareMoment.rankUp:
        return 'Share your rank up';
    }
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.template,
    required this.onTap,
  });

  final DutchSharePlatform platform;
  final DutchShareTemplate? template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = platform == DutchSharePlatform.tiktok;
    return Material(
      color: AppColors.primaryColor,
      borderRadius: BorderRadius.circular(AppBorderRadius.small),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBorderRadius.small),
        child: Padding(
          padding: AppPadding.cardPadding,
          child: Row(
            children: [
              Icon(
                isVideo ? Icons.movie_outlined : Icons.image_outlined,
                color: AppColors.matchPotGoldLight,
              ),
              SizedBox(width: AppPadding.smallPadding.left),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platform.label,
                      style: AppTextStyles.bodyMedium().copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isVideo ? 'Video + caption' : 'Image + download link',
                      style: AppTextStyles.caption().copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
