import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Circular Timer Widget
///
/// Displays a circular progress ring that counts down from a specified duration.
/// Optionally wraps [centerChild] (e.g. profile avatar) so the ring reads as a border.
/// The timer automatically starts when the widget is built and resets when the duration changes.
class CircularTimerWidget extends StatefulWidget {
  final int durationSeconds;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  /// When set, drawn behind the ring (e.g. avatar). Ring stroke remains visible around it.
  final Widget? centerChild;

  const CircularTimerWidget({
    Key? key,
    required this.durationSeconds,
    this.size = 20.0,
    this.strokeWidth = 3.0,
    this.color,
    this.backgroundColor,
    this.centerChild,
  }) : super(key: key);

  @override
  State<CircularTimerWidget> createState() => _CircularTimerWidgetState();
}

class _CircularTimerWidgetState extends State<CircularTimerWidget> {
  Timer? _timer;
  int _remainingSeconds = 0;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(CircularTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart timer if duration changed
    if (oldWidget.durationSeconds != widget.durationSeconds) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _startTime = DateTime.now();
    _remainingSeconds = widget.durationSeconds;

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
      final elapsedSeconds = elapsed / 1000.0;
      final newRemaining = (widget.durationSeconds - elapsedSeconds).ceil();

      if (newRemaining != _remainingSeconds) {
        setState(() {
          _remainingSeconds = newRemaining.clamp(0, widget.durationSeconds);
        });
      }

      // Stop timer when it reaches 0
      if (_remainingSeconds <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Prevent division by zero or NaN - ensure durationSeconds is valid
    final safeDuration = widget.durationSeconds > 0 && widget.durationSeconds.isFinite 
        ? widget.durationSeconds 
        : 30; // Safe default
    final progress = safeDuration > 0 
        ? (_remainingSeconds / safeDuration).clamp(0.0, 1.0)
        : 0.0;
    final color = widget.color ?? AppColors.accentColor2;
    final backgroundColor = widget.backgroundColor ?? AppColors.surfaceVariant;
    final sw = widget.strokeWidth;
    final inner = math.max(0.0, widget.size - 2 * sw - 2);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.centerChild == null)
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundColor,
              ),
            ),
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: sw,
              backgroundColor: backgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (widget.centerChild != null)
            SizedBox(
              width: inner,
              height: inner,
              child: ClipOval(
                child: widget.centerChild,
              ),
            ),
        ],
      ),
    );
  }
}
