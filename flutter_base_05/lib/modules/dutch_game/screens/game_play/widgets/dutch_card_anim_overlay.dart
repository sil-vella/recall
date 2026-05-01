import 'package:flutter/material.dart';

import '../../../../../tools/logging/logger.dart';
import '../../../models/card_display_config.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../utils/dutch_anim_runtime.dart';

/// enable-logging-switch.mdc — when true: start flight, flight complete, stall skip only.
const bool LOGGING_SWITCH = false;

/// FIFO card flights from [DutchAnimRuntime]: frozen A→B rects, one [AnimationController] tween
/// at a time; on [AnimationStatus.completed], post-frame dequeue then [_kick] next head.
class DutchCardAnimOverlay extends StatefulWidget {
  const DutchCardAnimOverlay({super.key});

  @override
  State<DutchCardAnimOverlay> createState() => _DutchCardAnimOverlayState();
}

class _DutchCardAnimOverlayState extends State<DutchCardAnimOverlay>
    with SingleTickerProviderStateMixin {
  static final Logger _logger = Logger();
  final DutchAnimRuntime _runtime = DutchAnimRuntime.instance;

  AnimationController? _controller;
  int? _runningSeq;
  int _stallFrames = 0;
  static const int _maxStallFrames = 24;

  Map<String, double>? _flightFromRect;
  Map<String, double>? _flightToRect;
  CardModel? _flightModel;

  static const CardModel _placeholderFaceDown = CardModel(
    cardId: '_anim',
    rank: '?',
    suit: '?',
    points: 0,
    isFaceDown: true,
  );

  /// True while [AnimationController.status] is forward/reverse (not [isAnimating] / ticker mute).
  bool _controllerIsDrivingTween() {
    final c = _controller;
    if (c == null) return false;
    return c.status == AnimationStatus.forward || c.status == AnimationStatus.reverse;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      animationBehavior: AnimationBehavior.preserve,
    )
      ..addStatusListener(_onAnimStatus)
      ..addListener(_onAnimTick);
    _runtime.addListener(_onRuntime);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  @override
  void dispose() {
    _runtime.removeListener(_onRuntime);
    _controller?.removeListener(_onAnimTick);
    _controller?.removeStatusListener(_onAnimStatus);
    _controller?.dispose();
    super.dispose();
  }

  void _onRuntime() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  /// Drive repaints on every [AnimationController] tick via [setState] so layout lerps every frame.
  void _onAnimTick() {
    if (!mounted) return;
    if (_shouldPaintFlightGhost()) {
      setState(() {});
    }
  }

  void _onAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller == null || _controller!.status != AnimationStatus.completed) return;
      if (LOGGING_SWITCH) {
        _logger.info(
          'DutchCardAnimOverlay: flight complete seq=$_runningSeq value=${_controller!.value.toStringAsFixed(3)}',
        );
      }
      _flightFromRect = null;
      _flightToRect = null;
      _flightModel = null;
      _runtime.dequeueHead();
      _runningSeq = null;
      _stallFrames = 0;
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    });
  }

  int? _parseHandIndex(dynamic hi) {
    if (hi is int) return hi;
    if (hi is num) return hi.toInt();
    if (hi is String) return int.tryParse(hi);
    return null;
  }

  void _kick() {
    if (!mounted || _controller == null) return;
    if (_controllerIsDrivingTween()) return;

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
    final supported = action == 'draw' || action == 'play_card' || action == 'reposition';
    final fromTo = supported ? _resolveFromTo(anim, head as Map<String, dynamic>, action) : null;

    if (fromTo == null) {
      if (!supported) {
        _runtime.dequeueHead();
        _stallFrames = 0;
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
        return;
      }
      if (action == 'reposition') {
        final cards = head['cards'] as List?;
        final c0 = cards != null && cards.isNotEmpty && cards.first is Map ? cards.first as Map : null;
        final hasFrom = c0 != null &&
            (_parseHandIndex(c0['from_hand_index']) != null || _parseHandIndex(c0['fromHandIndex']) != null);
        if (LOGGING_SWITCH) {
          _logger.info(
            'DutchCardAnimOverlay: skip reposition seq=$seq reason=${hasFrom ? 'unresolved_rects' : 'missing_from_index'}',
          );
        }
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
      }
      return;
    }
    _stallFrames = 0;
    _runningSeq = seq;
    _flightFromRect = Map<String, double>.from(fromTo[0] as Map<String, double>);
    _flightToRect = Map<String, double>.from(fromTo[1] as Map<String, double>);
    _flightModel = fromTo[2] as CardModel;
    if (LOGGING_SWITCH) {
      _logger.info('DutchCardAnimOverlay: start flight action=$action seq=$seq');
    }
    if (mounted) setState(() {});
    _controller!.forward(from: 0.0);
  }

  /// Paint ghost while tweening or for one completed frame at t=1 before post-frame cleanup.
  bool _shouldPaintFlightGhost() {
    final c = _controller;
    if (c == null) return false;
    if (_runningSeq == null ||
        _flightFromRect == null ||
        _flightToRect == null ||
        _flightModel == null) {
      return false;
    }
    final s = c.status;
    if (s == AnimationStatus.forward || s == AnimationStatus.reverse) return true;
    if (s == AnimationStatus.completed && c.value >= 1.0 - 1e-9) return true;
    return false;
  }

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
      Map? played;
      for (final e in cards) {
        if (e is Map && e['card'] is Map) {
          played = e;
          break;
        }
      }
      played ??= cards.isNotEmpty ? cards.first : null;
      if (played is! Map) return null;
      final c0 = played;
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

    if (action == 'reposition') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final toIdx = _parseHandIndex(c0['hand_index']);
      final fromIdx =
          _parseHandIndex(c0['from_hand_index']) ?? _parseHandIndex(c0['fromHandIndex']);
      if (owner.isEmpty || toIdx == null || fromIdx == null) return null;
      final from = rectFor(owner, fromIdx);
      final to = rectFor(owner, toIdx);
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
    if (!_shouldPaintFlightGhost()) {
      return const SizedBox.shrink();
    }
    final anim = _runtime.snapshotForAnim();
    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.isEmpty) return const SizedBox.shrink();
    final head = events.first;
    if (head is! Map<String, dynamic>) return const SizedBox.shrink();
    final seq = head['_seq'] as int?;
    if (seq != _runningSeq) return const SizedBox.shrink();

    final from = _flightFromRect!;
    final to = _flightToRect!;
    final model = _flightModel!;
    final t = _controller!.value;
    final left = from['left']! + (to['left']! - from['left']!) * t;
    final top = from['top']! + (to['top']! - from['top']!) * t;
    final w = from['width']!;
    final h = from['height']!;
    final dims = Size(w, h);

    return TickerMode(
      enabled: true,
      child: RepaintBoundary(
        child: IgnorePointer(
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
        ),
      ),
    );
  }
}
