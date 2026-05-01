import 'package:flutter/material.dart';

import '../../../../../tools/logging/logger.dart';
import '../../../models/card_display_config.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../utils/dutch_anim_runtime.dart';

/// enable-logging-switch.mdc — overlay stall / flight trace.
const bool LOGGING_SWITCH = true;

/// Minimal flight overlay: reads [DutchAnimRuntime.instance] at anim time; subscribes only to that [Listenable].
class DutchCardAnimOverlay extends StatefulWidget {
  const DutchCardAnimOverlay({
    super.key,
    required this.tickerProvider,
  });

  final TickerProvider tickerProvider;

  @override
  State<DutchCardAnimOverlay> createState() => _DutchCardAnimOverlayState();
}

class _DutchCardAnimOverlayState extends State<DutchCardAnimOverlay> {
  static final Logger _logger = Logger();
  final DutchAnimRuntime _runtime = DutchAnimRuntime.instance;
  AnimationController? _controller;
  int? _runningSeq;
  int _stallFrames = 0;
  static const int _maxStallFrames = 24;

  static const CardModel _placeholderFaceDown = CardModel(
    cardId: '_anim',
    rank: '?',
    suit: '?',
    points: 0,
    isFaceDown: true,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: widget.tickerProvider,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener(_onAnimStatus);
    _runtime.addListener(_onRuntime);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  @override
  void dispose() {
    _runtime.removeListener(_onRuntime);
    _controller?.removeStatusListener(_onAnimStatus);
    _controller?.dispose();
    super.dispose();
  }

  void _onRuntime() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  void _onAnimStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      _runtime.dequeueHead();
      _runningSeq = null;
      _stallFrames = 0;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    }
  }

  int? _parseHandIndex(dynamic hi) {
    if (hi is int) return hi;
    if (hi is num) return hi.toInt();
    return null;
  }

  void _kick() {
    if (!mounted || _controller == null) return;
    if (_controller!.isAnimating) return;
    final anim = _runtime.snapshotForAnim();
    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.isEmpty) {
      _runningSeq = null;
      return;
    }
    final head = events.first;
    if (head is! Map) {
      _runtime.dequeueHead();
      return;
    }
    final seq = head['_seq'] as int?;
    if (seq == _runningSeq) return;

    final action = head['action_type']?.toString() ?? '';
    final supported = action == 'draw' || action == 'play_card';
    final fromTo = supported ? _resolveFromTo(anim, head as Map<String, dynamic>, action) : null;

    if (fromTo == null) {
      if (!supported) {
        _runtime.dequeueHead();
        _stallFrames = 0;
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
        return;
      }
      _stallFrames++;
      if (_stallFrames > _maxStallFrames) {
        if (LOGGING_SWITCH) {
          _logger.warning('DutchCardAnimOverlay: stall skip action=$action seq=$seq');
        }
        _runtime.dequeueHead();
        _stallFrames = 0;
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
      } else {
        if (mounted) setState(() {});
      }
      return;
    }
    _stallFrames = 0;
    _runningSeq = seq;
    if (LOGGING_SWITCH) {
      _logger.info('DutchCardAnimOverlay: start flight action=$action seq=$seq');
    }
    _controller!.reset();
    _controller!.forward();
  }

  /// Returns [fromRect, toRect, CardModel for ghost].
  List<Object>? _resolveFromTo(
    Map<String, dynamic> anim,
    Map<String, dynamic> head,
    String action,
  ) {
    final piles = anim[DutchAnimRuntime.pileRectsKey] as Map<String, dynamic>? ?? {};
    final positions = anim[DutchAnimRuntime.cardPositionsKey] as Map<String, dynamic>? ?? {};

    Map<String, double>? rectFor(String playerId, int handIndex) {
      final pm = positions[playerId];
      if (pm is! Map) return null;
      final slot = pm['$handIndex'];
      if (slot is! Map) return null;
      final left = (slot['left'] as num?)?.toDouble();
      final top = (slot['top'] as num?)?.toDouble();
      final w = (slot['width'] as num?)?.toDouble();
      final h = (slot['height'] as num?)?.toDouble();
      if (left == null || top == null || w == null || h == null) return null;
      return <String, double>{'left': left, 'top': top, 'width': w, 'height': h};
    }

    Map<String, double>? pileRect(String name) {
      final r = piles[name];
      if (r is! Map) return null;
      final left = (r['left'] as num?)?.toDouble();
      final top = (r['top'] as num?)?.toDouble();
      final w = (r['width'] as num?)?.toDouble();
      final h = (r['height'] as num?)?.toDouble();
      if (left == null || top == null || w == null || h == null) return null;
      return <String, double>{'left': left, 'top': top, 'width': w, 'height': h};
    }

    final cards = head['cards'] as List? ?? [];

    if (action == 'draw') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isEmpty || hi == null) return null;
      final source = head['source']?.toString() ?? 'deck';
      final from = source == 'discard' ? pileRect('discard') : pileRect('draw');
      final to = rectFor(owner, hi);
      if (from == null || to == null) return null;
      CardModel model = _placeholderFaceDown;
      final cardMap = c0['card'];
      if (cardMap is Map<String, dynamic>) {
        try {
          model = CardModel.fromMap(cardMap);
        } catch (_) {}
      }
      return <Object>[from, to, model];
    }

    if (action == 'play_card') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isEmpty || hi == null) return null;
      final from = rectFor(owner, hi);
      final to = pileRect('discard');
      if (from == null || to == null) return null;
      CardModel model = _placeholderFaceDown;
      final cardMap = c0['card'];
      if (cardMap is Map<String, dynamic>) {
        try {
          model = CardModel.fromMap(cardMap);
        } catch (_) {}
      }
      return <Object>[from, to, model];
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_controller!, _runtime]),
      builder: (context, _) {
        final anim = _runtime.snapshotForAnim();
        final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
        if (events.isEmpty) {
          return const SizedBox.shrink();
        }
        final head = events.first;
        if (head is! Map<String, dynamic>) return const SizedBox.shrink();
        final action = head['action_type']?.toString() ?? '';
        final resolved = (action == 'draw' || action == 'play_card')
            ? _resolveFromTo(anim, head, action)
            : null;
        if (resolved == null) {
          return const SizedBox.shrink();
        }
        final from = resolved[0] as Map<String, double>;
        final to = resolved[1] as Map<String, double>;
        final model = resolved[2] as CardModel;
        final t = _controller!.value;
        final left = from['left']! + (to['left']! - from['left']!) * t;
        final top = from['top']! + (to['top']! - from['top']!) * t;
        final w = from['width']!;
        final h = from['height']!;
        final dims = Size(w, h);

        return IgnorePointer(
          ignoring: !_controller!.isAnimating,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left,
                top: top,
                width: w,
                height: h,
                child: CardWidget(
                  card: model,
                  dimensions: dims,
                  config: CardDisplayConfig.forMyHand(),
                  showBack: !model.hasFullData,
                  isSelected: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
