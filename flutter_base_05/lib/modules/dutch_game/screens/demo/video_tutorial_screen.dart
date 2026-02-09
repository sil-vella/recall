import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../utils/consts/theme_consts.dart';

/// Full-screen video player for the Dutch game tutorial asset.
/// Plays [dutch_vid_tutorial.mp4] from assets/videos/.
class VideoTutorialScreen extends BaseScreen {
  const VideoTutorialScreen({Key? key}) : super(key: key);

  static const String _videoAssetPath = 'assets/videos/dutch_vid_tutorial.mp4';

  @override
  String computeTitle(BuildContext context) => 'Tutorial Video';

  @override
  Decoration? getBackground(BuildContext context) {
    return BoxDecoration(color: AppColors.scaffoldBackgroundColor);
  }

  @override
  VideoTutorialScreenState createState() => VideoTutorialScreenState();
}

class VideoTutorialScreenState extends BaseScreenState<VideoTutorialScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(VideoTutorialScreen._videoAssetPath)
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller.play();
      }).catchError((Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load video: $e')),
          );
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            color: AppColors.textOnPrimary,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            onPressed: () => NavigationManager().navigateTo('/dutch/demo'),
          ),
        ),
      ],
    );
  }
}
