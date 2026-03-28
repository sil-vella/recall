import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/consts/theme_consts.dart';

/// Thin strip for a single bottom promotional ad (YAML-driven).
class PromotionalBottomStrip extends StatelessWidget {
  const PromotionalBottomStrip({
    super.key,
    required this.title,
    required this.link,
    this.imageAssetPath,
  });

  final String title;
  final String link;

  /// Optional `assets/adverts/...` image (from YAML `image:`).
  final String? imageAssetPath;

  Future<void> _open() async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: AppPadding.cardPadding,
          child: Row(
            children: [
              if (imageAssetPath != null && imageAssetPath!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(
                    imageAssetPath!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.campaign_outlined,
                      color: AppColors.primaryColor,
                      size: 20,
                    ),
                  ),
                )
              else
                Icon(Icons.campaign_outlined, color: AppColors.primaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isNotEmpty ? title : link,
                  style: AppTextStyles.bodySmall(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.open_in_new, size: 18, color: AppColors.lightGray),
            ],
          ),
        ),
      ),
    );
  }
}
