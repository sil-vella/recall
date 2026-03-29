import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/consts/theme_consts.dart';

/// Shows optional video (preferred) or image for a promotional ad.
class AdvertMediaPanel extends StatefulWidget {
  const AdvertMediaPanel({
    super.key,
    this.imageAssetPath,
    this.videoAssetPath,
    this.imageNetworkUrl,
    this.videoNetworkUrl,
    this.maxHeight = 240,
  });

  final String? imageAssetPath;
  final String? videoAssetPath;
  final String? imageNetworkUrl;
  final String? videoNetworkUrl;
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
    _initVideo();
  }

  void _initVideo() {
    final net = widget.videoNetworkUrl;
    final asset = widget.videoAssetPath;
    if (net != null && net.isNotEmpty) {
      final uri = Uri.tryParse(net);
      if (uri != null && uri.hasScheme) {
        _controller = VideoPlayerController.networkUrl(uri)
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
        return;
      }
    }
    if (asset != null && asset.isNotEmpty) {
      _controller = VideoPlayerController.asset(asset)
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
    final vNet = widget.videoNetworkUrl;
    final vAsset = widget.videoAssetPath;
    final hasVideo = (vNet != null && vNet.isNotEmpty) || (vAsset != null && vAsset.isNotEmpty);

    if (hasVideo && !_videoFailed && _controller != null && _controller!.value.isInitialized) {
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

    if (hasVideo && !_videoFailed && _controller != null && !_controller!.value.isInitialized) {
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

    final iNet = widget.imageNetworkUrl;
    if (iNet != null && iNet.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: Image.network(
            iNet,
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
                        'Missing image: $iNet',
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

    final i = widget.imageAssetPath;
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

/// Full-screen image or video using [BoxFit.contain], centered (letterboxed on the black background).
class AdvertFullscreenCoverMedia extends StatefulWidget {
  const AdvertFullscreenCoverMedia({
    super.key,
    this.imageAssetPath,
    this.videoAssetPath,
    this.imageNetworkUrl,
    this.videoNetworkUrl,
  });

  final String? imageAssetPath;
  final String? videoAssetPath;
  final String? imageNetworkUrl;
  final String? videoNetworkUrl;

  @override
  State<AdvertFullscreenCoverMedia> createState() => _AdvertFullscreenCoverMediaState();
}

class _AdvertFullscreenCoverMediaState extends State<AdvertFullscreenCoverMedia> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    final net = widget.videoNetworkUrl;
    final asset = widget.videoAssetPath;
    if (net != null && net.isNotEmpty) {
      final uri = Uri.tryParse(net);
      if (uri != null && uri.hasScheme) {
        _controller = VideoPlayerController.networkUrl(uri)
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
        return;
      }
    }
    if (asset != null && asset.isNotEmpty) {
      _controller = VideoPlayerController.asset(asset)
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
    final vNet = widget.videoNetworkUrl;
    final vAsset = widget.videoAssetPath;
    final hasVideo = (vNet != null && vNet.isNotEmpty) || (vAsset != null && vAsset.isNotEmpty);

    if (hasVideo && !_videoFailed && _controller != null && _controller!.value.isInitialized) {
      final size = _controller!.value.size;
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
      );
    }

    if (hasVideo && !_videoFailed && _controller != null && !_controller!.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final iNet = widget.imageNetworkUrl;
    if (iNet != null && iNet.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.network(
            iNet,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return ColoredBox(
                color: AppColors.surface,
                child: Center(
                  child: Padding(
                    padding: AppPadding.defaultPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined, color: AppColors.lightGray),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Missing image: $iNet',
                            style: AppTextStyles.bodySmall(),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final i = widget.imageAssetPath;
    if (i != null && i.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.asset(
            i,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return ColoredBox(
                color: AppColors.surface,
                child: Center(
                  child: Padding(
                    padding: AppPadding.defaultPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined, color: AppColors.lightGray),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Missing asset: $i',
                            style: AppTextStyles.bodySmall(),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return const ColoredBox(color: Colors.black);
  }
}
