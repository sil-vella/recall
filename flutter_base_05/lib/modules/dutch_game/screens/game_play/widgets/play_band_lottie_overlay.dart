import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../../utils/dev_logger.dart';
import '../../../utils/dutch_dot_lottie.dart';

const bool LOGGING_SWITCH = false;

/// Minimum play-band [Positioned] height (layout geometry).
const double kPlayBandContainerMinHeight = 168;

/// Legacy default; Lottie now fills the play-band container (see [PlayBandLottieOverlay]).
const double kPlayBandLottieBox = kPlayBandContainerMinHeight;

/// Non-interactive play-band Lottie. [triggerToken] increments to play once.
class PlayBandLottieOverlay extends StatefulWidget {
  const PlayBandLottieOverlay({
    super.key,
    required this.triggerToken,
    required this.lottieAsset,
    this.boxSize = kPlayBandLottieBox,
  });

  final int triggerToken;
  final String lottieAsset;

  /// Unused at render time; Lottie scales to the play-band container bounds.
  final double boxSize;

  /// Last [triggerToken] played per [lottieAsset] — survives widget remounts.
  static final Map<String, int> _playedTokenByAsset = {};

  /// Clears cross-mount playback dedupe (call on game switch / new deal).
  static void resetPlayedTokens() => _playedTokenByAsset.clear();

  static int _globalLastToken(String asset) => _playedTokenByAsset[asset] ?? 0;

  static void _markTokenPlayed(String asset, int token) {
    _playedTokenByAsset[asset] = token;
  }

  @override
  State<PlayBandLottieOverlay> createState() => _PlayBandLottieOverlayState();
}

class _PlayBandLottieOverlayState extends State<PlayBandLottieOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Future<LottieComposition?> _compositionFuture;
  LottieComposition? _composition;
  int _lastHandledToken = 0;
  int _pendingPlays = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _compositionFuture = loadDotLottieFromAsset(widget.lottieAsset);
    _controller.addStatusListener(_onControllerStatus);
    _lastHandledToken = PlayBandLottieOverlay._globalLastToken(widget.lottieAsset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTrigger(widget.triggerToken);
    });
  }

  @override
  void didUpdateWidget(covariant PlayBandLottieOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lottieAsset != widget.lottieAsset) {
      _composition = null;
      _compositionFuture = loadDotLottieFromAsset(widget.lottieAsset);
    }
    if (oldWidget.triggerToken != widget.triggerToken) {
      _syncTrigger(widget.triggerToken);
    }
  }

  void _syncTrigger(int token, {bool scheduleFrame = true}) {
    final globalLast = PlayBandLottieOverlay._globalLastToken(widget.lottieAsset);
    final effectiveLast = _lastHandledToken > globalLast ? _lastHandledToken : globalLast;
    if (token <= effectiveLast) {
      _lastHandledToken = token;
      return;
    }
    final delta = token - effectiveLast;
    _lastHandledToken = token;
    PlayBandLottieOverlay._markTokenPlayed(widget.lottieAsset, token);
    _pendingPlays += delta;
    if (LOGGING_SWITCH) {
      customlog(
        'PlayBandLottieOverlay: syncTrigger asset=${widget.lottieAsset} '
        'token=$token delta=$delta pending=$_pendingPlays globalLast=$globalLast',
      );
    }
    if (scheduleFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryStartPlayback());
    } else {
      _tryStartPlayback();
    }
  }

  void _onControllerStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_pendingPlays > 0) {
      _tryStartPlayback();
      return;
    }
    if (mounted) {
      setState(() => _visible = false);
    }
  }

  Future<void> _tryStartPlayback() async {
    if (!mounted || _pendingPlays <= 0) return;
    if (_controller.isAnimating) return;

    final composition = _composition ?? await _compositionFuture;
    if (!mounted || composition == null) {
      if (LOGGING_SWITCH) {
        customlog(
          'PlayBandLottieOverlay: composition null asset=${widget.lottieAsset} '
          'pending=$_pendingPlays — playback aborted',
        );
      }
      _pendingPlays = 0;
      return;
    }

    _composition = composition;
    _pendingPlays--;
    _controller
      ..duration = composition.duration
      ..reset();
    if (LOGGING_SWITCH) {
      customlog(
        'PlayBandLottieOverlay: playing asset=${widget.lottieAsset} '
        'duration=${composition.duration.inMilliseconds}ms',
      );
    }
    setState(() => _visible = true);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onControllerStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _composition == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : kPlayBandContainerMinHeight;

        return SizedBox(
          width: w,
          height: h,
          child: Lottie(
            composition: _composition!,
            controller: _controller,
            animate: false,
            repeat: false,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
          ),
        );
      },
    );
  }
}
