import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/consts/theme_consts.dart';
import '../models/ad_registration.dart';
import 'advert_media_panel.dart';

/// Full-screen promotional overlay with optional delay before Skip is enabled.
class SwitchScreenAdOverlay {
  SwitchScreenAdOverlay._();

  static Future<void> show(
    BuildContext context, {
    required AdRegistration ad,
    required int delayBeforeSkipSeconds,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Promotional ad',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _SwitchScreenAdDialog(
          ad: ad,
          delayBeforeSkipSeconds: delayBeforeSkipSeconds,
        );
      },
    );
  }
}

class _SwitchScreenAdDialog extends StatefulWidget {
  const _SwitchScreenAdDialog({
    required this.ad,
    required this.delayBeforeSkipSeconds,
  });

  final AdRegistration ad;
  final int delayBeforeSkipSeconds;

  @override
  State<_SwitchScreenAdDialog> createState() => _SwitchScreenAdDialogState();
}

class _SwitchScreenAdDialogState extends State<_SwitchScreenAdDialog> {
  bool _canSkip = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final d = widget.delayBeforeSkipSeconds;
    if (d <= 0) {
      _canSkip = true;
    } else {
      _timer = Timer(Duration(seconds: d), () {
        if (mounted) {
          setState(() => _canSkip = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(widget.ad.link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ad.title ?? 'Promo';
    return SafeArea(
      child: Material(
        color: AppColors.surface,
        child: Padding(
          padding: AppPadding.defaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.headingSmall(),
                    ),
                  ),
                  TextButton(
                    onPressed: _canSkip ? () => Navigator.of(context).pop() : null,
                    child: Text(
                      'Skip',
                      style: AppTextStyles.bodyMedium().copyWith(
                        color: _canSkip ? AppColors.primaryColor : AppColors.lightGray,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AdvertMediaPanel(
                imageAssetPath: widget.ad.imageAssetPath,
                videoAssetPath: widget.ad.videoAssetPath,
                maxHeight: 280,
              ),
              const SizedBox(height: 12),
              Text(
                widget.ad.link,
                style: AppTextStyles.bodySmall(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _openLink,
                child: Text(
                  'Open link',
                  style: AppTextStyles.bodyMedium(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
