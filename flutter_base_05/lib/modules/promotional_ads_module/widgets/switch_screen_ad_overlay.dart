import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/managers/module_manager.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../admobs/interstitial/interstitial_ad.dart';

/// Full-screen gate before an AdMob interstitial: countdown, then Skip (or dismiss if no ad / web).
class SwitchScreenAdOverlay {
  SwitchScreenAdOverlay._();

  static Future<void> show(
    BuildContext context, {
    required int delayBeforeSkipSeconds,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Interstitial ad',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _SwitchScreenAdDialog(
          delayBeforeSkipSeconds: delayBeforeSkipSeconds,
        );
      },
    );
  }
}

class _SwitchScreenAdDialog extends StatefulWidget {
  const _SwitchScreenAdDialog({
    required this.delayBeforeSkipSeconds,
  });

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ModuleManager().getModuleByType<InterstitialAdModule>()?.loadAd();
    });
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

  void _onSkipOrFinish() {
    if (!_canSkip) return;
    void close() {
      if (mounted) Navigator.of(context).pop();
    }

    final mod = ModuleManager().getModuleByType<InterstitialAdModule>();
    if (mod == null || kIsWeb) {
      close();
      return;
    }
    mod.showOrFinish(context, close);
  }

  Widget _buildSkipOrTimer() {
    final secs = widget.delayBeforeSkipSeconds;
    if (_canSkip || secs <= 0) {
      return TextButton(
        onPressed: _onSkipOrFinish,
        child: Text(
          'Skip',
          style: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.white,
          ),
        ),
      );
    }

    final remaining = (secs * (1 - _progress)).ceil().clamp(0, secs);
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
            const ColoredBox(color: Colors.black),
            SafeArea(
              child: Align(
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
            ),
          ],
        ),
      ),
    );
  }
}
