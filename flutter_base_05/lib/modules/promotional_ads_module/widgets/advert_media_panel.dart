import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/consts/theme_consts.dart';

/// Shows optional video (preferred) or image for a promotional ad.
class AdvertMediaPanel extends StatefulWidget {
  const AdvertMediaPanel({
    super.key,
    this.imageAssetPath,
    this.videoAssetPath,
    this.maxHeight = 240,
  });

  final String? imageAssetPath;
  final String? videoAssetPath;
  final double maxHeight;

  @override
  State<AdvertMediaPanel> createState() => _AdvertMediaPanelState();
}

class _AdvertMediaPanelState extends State<AdvertMediaPanel> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    final v = widget.videoAssetPath;
    if (v != null && v.isNotEmpty) {
      _controller = VideoPlayerController.asset(v)
        ..initialize().then((_) {
          if (!mounted) {
            return;
          }
          setState(() {});
          _controller!.setLooping(true);
          _controller!.play();
        }).catchError((Object _) {
          if (mounted) {
            setState(() => _videoFailed = true);
          }
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.videoAssetPath;
    final i = widget.imageAssetPath;

    if (v != null && v.isNotEmpty && !_videoFailed && _controller != null && _controller!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio == 0
                ? 16 / 9
                : _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    if (v != null && v.isNotEmpty && !_videoFailed && _controller != null && !_controller!.value.isInitialized) {
      return SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryColor,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (i != null && i.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: Image.asset(
            i,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: AppPadding.defaultPadding,
                color: AppColors.surface,
                child: Row(
                  children: [
                    Icon(Icons.broken_image_outlined, color: AppColors.lightGray),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Missing asset: $i',
                        style: AppTextStyles.bodySmall(),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
