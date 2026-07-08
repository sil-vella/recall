import 'package:flutter/material.dart';

import '../../../../../../utils/consts/theme_consts.dart';
import 'cosmetic_catalog_preview.dart';

/// Dark scrim behind modal title — matches customize shop tiles.
final Color _kTitleScrimFill = AppColors.darkGray.withValues(alpha: 0.92);

/// Large preview modal for card covers and table designs on the Customize screen.
class CosmeticPreviewModal extends StatelessWidget {
  const CosmeticPreviewModal({
    super.key,
    required this.item,
  });

  final Map<String, dynamic> item;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> item,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.black.withValues(alpha: AppOpacity.barrier),
      builder: (ctx) => CosmeticPreviewModal(item: item),
    );
  }

  void _close(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = cosmeticCatalogItemShortTitle(item);

    return PopScope(
      canPop: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppPadding.defaultPadding.horizontal,
          vertical: AppPadding.defaultPadding.vertical,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.95,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accentContrast,
              borderRadius: AppBorderRadius.mediumRadius,
              border: Border.all(color: AppColors.borderDefault),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: AppOpacity.shadow),
                  blurRadius: AppSizes.shadowBlur,
                  offset: AppSizes.shadowOffset,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: AppBorderRadius.mediumRadius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _kTitleScrimFill,
                      borderRadius: AppBorderRadius.only(
                        topLeft: AppBorderRadius.medium,
                        topRight: AppBorderRadius.medium,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTextStyles.caption(color: AppColors.white).copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _close(context),
                            icon: Icon(
                              Icons.close,
                              color: AppColors.white,
                              size: AppSizes.iconMedium,
                            ),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: AppPadding.cardPadding,
                      child: Center(
                        child: CosmeticCatalogPreview(
                          item: item,
                          size: CosmeticPreviewSize.modal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
