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
    this.imageNetworkUrl,
  });

  final String title;
  final String link;

  /// Optional bundled asset path (rare; production uses [imageNetworkUrl]).
  final String? imageAssetPath;

  /// Optional HTTPS URL for server-driven ads (`/sponsors/adverts/...`).
  final String? imageNetworkUrl;

  Future<void> _open() async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = title.isNotEmpty ? title : link;
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: AppColors.accentContrast,
        child: InkWell(
          onTap: _open,
          child: Row(
            children: [
              Expanded(
                child: (imageNetworkUrl != null && imageNetworkUrl!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          imageNetworkUrl!,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.campaign_outlined,
                            color: AppColors.primaryColor,
                            size: 20,
                          ),
                        ),
                      )
                    : (imageAssetPath != null && imageAssetPath!.isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              imageAssetPath!,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.campaign_outlined,
                                color: AppColors.primaryColor,
                                size: 20,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.campaign_outlined,
                              color: AppColors.primaryColor,
                              size: 20,
                            ),
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
