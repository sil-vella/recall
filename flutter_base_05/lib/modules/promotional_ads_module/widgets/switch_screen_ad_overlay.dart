import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/consts/theme_consts.dart';
import '../models/ad_registration.dart';
import 'advert_media_panel.dart';

/// enable-logging-switch.mdc

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
      barrierColor: Colors.black,
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
  Timer? _countdownTicker;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    final totalSecs = widget.delayBeforeSkipSeconds;
    if (totalSecs <= 0) {
      _canSkip = true;
      _progress = 1;
    } else {
      final start = DateTime.now();
      final totalMs = totalSecs * 1000;
      _countdownTicker = Timer.periodic(const Duration(milliseconds: 32), (_) {
        if (!mounted) return;
        final elapsedMs = DateTime.now().difference(start).inMilliseconds;
        final p = (elapsedMs / totalMs).clamp(0.0, 1.0);
        setState(() => _progress = p);
        if (elapsedMs >= totalMs) {
          _countdownTicker?.cancel();
          setState(() => _canSkip = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(widget.ad.link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildSkipOrTimer() {
    final secs = widget.delayBeforeSkipSeconds;
    if (_canSkip || secs <= 0) {
      return TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          'Skip',
          style: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.white,
          ),
        ),
      );
    }

    final remaining =
        (secs * (1 - _progress)).ceil().clamp(0, secs);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: _progress.clamp(0.0, 1.0),
            strokeWidth: 3,
            backgroundColor: Colors.white24,
            color: AppColors.white,
          ),
          Text(
            '$remaining',
            style: AppTextStyles.bodyMedium().copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AdvertFullscreenCoverMedia(
                imageAssetPath: widget.ad.imageAssetPath,
                videoAssetPath: widget.ad.videoAssetPath,
                imageNetworkUrl: widget.ad.networkImageUrl,
                videoNetworkUrl: widget.ad.networkVideoUrl,
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Material(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                        child: _buildSkipOrTimer(),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: AppPadding.defaultPadding,
                      child: FilledButton(
                        onPressed: _openLink,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: AppColors.white,
                        ),
                        child: Text(
                          'Open link',
                          style: AppTextStyles.bodyMedium(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
