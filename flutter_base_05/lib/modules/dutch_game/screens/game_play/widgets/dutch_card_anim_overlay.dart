import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/platform/shared_imports.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../models/card_display_config.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../utils/dutch_anim_runtime.dart';


/// Same angles as [CardWidget]'s [RotatedBox] quarter-turns (radians, clockwise).
double _tableOrientationToRadians(CardTableOrientation o) {
  switch (o) {
    case CardTableOrientation.portraitUp:
      return 0;
    case CardTableOrientation.portraitDown:
      return math.pi;
    case CardTableOrientation.landscapeFromLeft:
      return math.pi / 2;
    case CardTableOrientation.landscapeFromRight:
      return 3 * math.pi / 2;
  }
}

/// [GlobalKey] layout rects for a [CardWidget]+[RotatedBox] hand slot: outer box may be swapped vs portrait logical size.
Size _portraitCardSizeFromLayoutRect(double layoutW, double layoutH) {
  if (layoutH >= layoutW) {
    return Size(layoutW, layoutH);
  }
  return Size(layoutH, layoutW);
}

CardTableOrientation _seatOrientationForPlayer(Map<String, dynamic> anim, String playerId) {
  final raw = anim[DutchAnimRuntime.playerTableOrientationsKey];
  if (raw is! Map) return CardTableOrientation.portraitUp;
  final s = raw[playerId]?.toString();
  if (s == null || s.isEmpty) return CardTableOrientation.portraitUp;
  for (final v in CardTableOrientation.values) {
    if (v.name == s) return v;
  }
  return CardTableOrientation.portraitUp;
}

/// Resolve slot-facing radians for a hand rect.
/// If seat mapping is missing but the slot rect is landscape, force landscape radians so
/// left/right opponents do not render vertical ghosts.
double _seatRadiansForHandRect(
  Map<String, dynamic> anim,
  String playerId,
  Map<String, double> rect,
) {
  final mapped = _seatOrientationForPlayer(anim, playerId);
  final mappedRadians = _tableOrientationToRadians(mapped);
  final isLandscapeRect = (rect['width'] ?? 0) > (rect['height'] ?? 0);
  final mappedPortrait =
      mapped == CardTableOrientation.portraitUp || mapped == CardTableOrientation.portraitDown;
  if (isLandscapeRect && mappedPortrait) {
    return math.pi / 2;
  }
  return mappedRadians;
}

enum _PlanTag { none, linear, jackSwap, queenPeek }

/// One card flying from [from] rect to [to] rect (anchor-relative pixels).
class _CardFlightData {
  const _CardFlightData({
    required this.from,
    required this.to,
    required this.model,
    this.fromRadians = 0,
    this.toRadians = 0,
  });
  final Map<String, double> from;
  final Map<String, double> to;
  final CardModel model;
  final double fromRadians;
  final double toRadians;
}

/// Resolved animation for the current queue head.
class _AnimPlan {
  const _AnimPlan.linear(this.a)
      : tag = _PlanTag.linear,
        b = null,
        peekTarget = null;
  const _AnimPlan.jackSwap(this.a, this.b)
      : tag = _PlanTag.jackSwap,
        peekTarget = null;
  const _AnimPlan.queenPeek(this.peekTarget)
      : tag = _PlanTag.queenPeek,
        a = null,
        b = null;

  final _PlanTag tag;
  final _CardFlightData? a;
  final _CardFlightData? b;
  final Map<String, double>? peekTarget;
}

/// FIFO card flights from [DutchAnimRuntime]: frozen A→B rects, one [AnimationController] tween
/// at a time; on [AnimationStatus.completed], post-frame dequeue then immediate [_kick] (same
/// frame) so chained flights stay visually continuous, plus a post-frame [_kick] for stalls.
class DutchCardAnimOverlay extends StatefulWidget {
  const DutchCardAnimOverlay({super.key});

  @override
  State<DutchCardAnimOverlay> createState() => _DutchCardAnimOverlayState();
}

class _DutchCardAnimOverlayState extends State<DutchCardAnimOverlay>
    with SingleTickerProviderStateMixin {
  final DutchAnimRuntime _runtime = DutchAnimRuntime.instance;

  AnimationController? _controller;
  int? _runningSeq;
  int _stallFrames = 0;
  static const int _maxStallFrames = 24;

  _PlanTag _activePlan = _PlanTag.none;

  Map<String, double>? _flightFromRect;
  Map<String, double>? _flightToRect;
  CardModel? _flightModel;
  double _flightFromRadians = 0;
  double _flightToRadians = 0;

  Map<String, double>? _jackFromB;
  Map<String, double>? _jackToB;
  CardModel? _jackModelB;
  double _jackFromRadiansB = 0;
  double _jackToRadiansB = 0;

  Map<String, double>? _peekTargetRect;

  /// Static ghost during [play_card] / [same_rank_play]: next [reposition]'s `from` rect, else draw pile.
  Map<String, double>? _playDeckGhostRect;
  CardModel? _playDeckGhostModel;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHandMaskFromQueueHead();
      _kick();
    });
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
    // Mask destination slots from payload as soon as the queue changes, so a same-frame or
    // early [game_state_updated] cannot paint the real card before [_kick] resolves rects.
    _syncHandMaskFromQueueHead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  /// Drive repaints on every [AnimationController] tick via [setState] so layout lerps every frame.
  void _onAnimTick() {
    if (!mounted) return;
    if (_shouldPaintAnim()) {
      setState(() {});
    }
  }

  void _onAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller == null || _controller!.status != AnimationStatus.completed) return;
      
      // Dequeue first; do not clear frozen rects here — [_kick] -> [_applyPlan] replaces them
      // in the same frame so the draw ghost does not vanish for a frame before play starts.
      _runtime.dequeueHead();
      _syncHandMaskFromQueueHead();
      _runningSeq = null;
      _stallFrames = 0;
      if (mounted) {
        _kick();
        setState(() {});
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    });
  }

  void _clearFrozenFlightVisuals() {
    _activePlan = _PlanTag.none;
    _flightFromRect = null;
    _flightToRect = null;
    _flightModel = null;
    _flightFromRadians = 0;
    _flightToRadians = 0;
    _jackFromB = null;
    _jackToB = null;
    _jackModelB = null;
    _jackFromRadiansB = 0;
    _jackToRadiansB = 0;
    _peekTargetRect = null;
  }

  /// Rect for the static ghost during a play flight: queued [reposition]'s `from`, else draw pile.
  Map<String, double>? _rectForPlayStaticGhost(Map<String, dynamic> anim) {
    final positions = anim[DutchAnimRuntime.cardPositionsKey] as Map<String, dynamic>? ?? {};
    Map<String, double>? slotRect(String playerId, int handIndex) {
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

    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.length >= 2) {
      final second = events[1];
      if (second is Map<String, dynamic>) {
        final nextAction = second['action_type']?.toString() ?? '';
        if (nextAction == 'reposition') {
          final p = _resolveAnimPlan(anim, second, 'reposition');
          if (p?.tag == _PlanTag.linear && p!.a != null) {
            return Map<String, double>.from(p.a!.from);
          }
        }
      }
    }
    if (events.isNotEmpty && events.first is Map<String, dynamic>) {
      final head = events.first as Map<String, dynamic>;
      final headAction = head['action_type']?.toString() ?? '';
      if (headAction == 'play_card' || headAction == 'same_rank_play') {
        final headCards = head['cards'] as List? ?? [];
        if (headCards.length >= 2 && headCards[1] is Map<String, dynamic>) {
          final hint = headCards[1] as Map<String, dynamic>;
          final o = hint['owner_id']?.toString() ?? '';
          final hi = _parseHandIndex(hint['hand_index']);
          if (o.isNotEmpty && hi != null) {
            final r = slotRect(o, hi);
            if (r != null) return r;
          }
        }
      }
    }
    final piles = anim[DutchAnimRuntime.pileRectsKey] as Map<String, dynamic>? ?? {};
    final r = piles['draw'];
    if (r is! Map) return null;
    final left = (r['left'] as num?)?.toDouble();
    final top = (r['top'] as num?)?.toDouble();
    final w = (r['width'] as num?)?.toDouble();
    final h = (r['height'] as num?)?.toDouble();
    if (left == null || top == null || w == null || h == null) return null;
    return <String, double>{'left': left, 'top': top, 'width': w, 'height': h};
  }

  /// Updates hand-slot mask from the current queue head (payload only; no layout resolve).
  void _syncHandMaskFromQueueHead() {
    if (!mounted) return;
    final anim = _runtime.snapshotForAnim();
    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.isEmpty) {
      _runtime.clearAnimMaskedHandSlots();
      return;
    }
    final head = events.first;
    if (head is! Map) {
      _runtime.clearAnimMaskedHandSlots();
      return;
    }
    final hm = Map<String, dynamic>.from(head);
    final action = hm['action_type']?.toString() ?? '';
    if (!_isSupportedAction(action)) {
      _runtime.setAnimMaskedHandSlots({});
      return;
    }
    _runtime.setAnimMaskedHandSlots(_maskKeysFromHeadPayload(hm));
  }

  int? _parseHandIndex(dynamic hi) {
    if (hi is int) return hi;
    if (hi is num) return hi.toInt();
    if (hi is String) return int.tryParse(hi);
    return null;
  }

  bool _isSupportedAction(String action) {
    const supported = <String>{
      'draw',
      'play_card',
      'reposition',
      'collect_from_discard',
      'same_rank_play',
      'same_rank_penalty_rebound',
      'jack_swap',
      'queen_peek',
    };
    return supported.contains(action);
  }

  void _kick() {
    if (!mounted || _controller == null) return;
    if (_controllerIsDrivingTween()) return;

    final anim = _runtime.snapshotForAnim();
    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.isEmpty) {
      _runningSeq = null;
      _syncHandMaskFromQueueHead();
      _clearFrozenFlightVisuals();
      _playDeckGhostRect = null;
      _playDeckGhostModel = null;
      return;
    }
    final head = events.first;
    if (head is! Map) {
      _runtime.dequeueHead();
      _syncHandMaskFromQueueHead();
      return;
    }
    final seq = head['_seq'] as int?;
    if (seq == _runningSeq) return;

    final action = head['action_type']?.toString() ?? '';
    final supported = _isSupportedAction(action);
    final plan = supported ? _resolveAnimPlan(anim, head as Map<String, dynamic>, action) : null;

    if (plan == null) {
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
        
        _runtime.dequeueHead();
        _stallFrames = 0;
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
        return;
      }
      if (action == 'jack_swap') {
        final cards = head['cards'] as List? ?? [];
        if (cards.length < 2) {
          _runtime.dequeueHead();
          _stallFrames = 0;
          if (mounted) setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
          return;
        }
      }
      _stallFrames++;
      if (_stallFrames > _maxStallFrames) {
        
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
    _applyPlan(plan, head as Map<String, dynamic>);
    
    if (mounted) setState(() {});
    _controller!.forward(from: 0.0);
  }

  void _applyPlan(_AnimPlan plan, Map<String, dynamic> head) {
    // Do not clear hand mask here — it may already be set from [_onRuntime] on enqueue.
    final action = head['action_type']?.toString() ?? '';
    _playDeckGhostRect = null;
    _playDeckGhostModel = null;
    _clearFrozenFlightVisuals();
    _activePlan = plan.tag;
    switch (plan.tag) {
      case _PlanTag.linear:
        final a = plan.a!;
        _flightFromRect = Map<String, double>.from(a.from);
        _flightToRect = Map<String, double>.from(a.to);
        _flightModel = a.model;
        _flightFromRadians = a.fromRadians;
        _flightToRadians = a.toRadians;
        if (action == 'play_card' || action == 'same_rank_play') {
          final animSnap = _runtime.snapshotForAnim();
          final ghostRect = _rectForPlayStaticGhost(animSnap);
          if (ghostRect != null && _flightModel != null) {
            _playDeckGhostRect = ghostRect;
            _playDeckGhostModel = _placeholderFaceDown;
            
          }
        }
        
        break;
      case _PlanTag.jackSwap:
        final a = plan.a!;
        final b = plan.b!;
        _flightFromRect = Map<String, double>.from(a.from);
        _flightToRect = Map<String, double>.from(a.to);
        _flightModel = a.model;
        _flightFromRadians = a.fromRadians;
        _flightToRadians = a.toRadians;
        _jackFromB = Map<String, double>.from(b.from);
        _jackToB = Map<String, double>.from(b.to);
        _jackModelB = b.model;
        _jackFromRadiansB = b.fromRadians;
        _jackToRadiansB = b.toRadians;
        break;
      case _PlanTag.queenPeek:
        _peekTargetRect = Map<String, double>.from(plan.peekTarget!);
        break;
      case _PlanTag.none:
        break;
    }
    _runtime.setAnimMaskedHandSlots(_maskKeysFromHeadPayload(head));
  }

  /// Hand slots to mask, derived only from [head] (same rules as [_AnimPlan] masking).
  Set<String> _maskKeysFromHeadPayload(Map<String, dynamic> head) {
    final keys = <String>{};
    final action = head['action_type']?.toString() ?? '';
    final cards = head['cards'] as List? ?? [];

    if (action == 'jack_swap') {
      if (cards.length < 2) return keys;
      final c0 = cards[0];
      final c1 = cards[1];
      if (c0 is! Map || c1 is! Map) return keys;
      final o0 = c0['owner_id']?.toString() ?? '';
      final i0 = _parseHandIndex(c0['hand_index']);
      final o1 = c1['owner_id']?.toString() ?? '';
      final i1 = _parseHandIndex(c1['hand_index']);
      if (o1.isNotEmpty && i1 != null) keys.add(DutchAnimRuntime.handSlotMaskKey(o1, i1));
      if (o0.isNotEmpty && i0 != null) keys.add(DutchAnimRuntime.handSlotMaskKey(o0, i0));
      return keys;
    }
    if (action == 'queen_peek') {
      if (cards.isEmpty) return keys;
      final c0 = cards.first;
      if (c0 is! Map) return keys;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isNotEmpty && hi != null) {
        keys.add(DutchAnimRuntime.handSlotMaskKey(owner, hi));
      }
      return keys;
    }
    if (action == 'play_card' || action == 'same_rank_play') return keys;
    if (cards.isEmpty) return keys;
    final c0 = cards.first;
    if (c0 is! Map) return keys;
    if (action == 'draw' || action == 'collect_from_discard' || action == 'same_rank_penalty_rebound') {
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isNotEmpty && hi != null) {
        keys.add(DutchAnimRuntime.handSlotMaskKey(owner, hi));
      }
    } else if (action == 'reposition') {
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isNotEmpty && hi != null) {
        keys.add(DutchAnimRuntime.handSlotMaskKey(owner, hi));
      }
    }
    return keys;
  }

  /// Paint while tweening or for one completed frame at t=1 before post-frame cleanup.
  bool _shouldPaintAnim() {
    final c = _controller;
    if (c == null || _runningSeq == null) return false;
    final s = c.status;
    final inWindow = s == AnimationStatus.forward ||
        s == AnimationStatus.reverse ||
        (s == AnimationStatus.completed && c.value >= 1.0 - 1e-9);
    if (!inWindow) return false;
    switch (_activePlan) {
      case _PlanTag.none:
        return false;
      case _PlanTag.linear:
        return _flightFromRect != null &&
            _flightToRect != null &&
            _flightModel != null;
      case _PlanTag.jackSwap:
        return _flightFromRect != null &&
            _flightToRect != null &&
            _flightModel != null &&
            _jackFromB != null &&
            _jackToB != null &&
            _jackModelB != null;
      case _PlanTag.queenPeek:
        return _peekTargetRect != null;
    }
  }

  _AnimPlan? _resolveAnimPlan(
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

    CardModel modelFromCardMap(Map c0) {
      CardModel model = _placeholderFaceDown;
      final cardMap = c0['card'];
      if (cardMap is Map<String, dynamic>) {
        try {
          model = CardModel.fromMap(cardMap);
        } catch (_) {}
      }
      return model;
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
      final deckTilt = source == 'deck' ? -0.13 : 0.0;
      final toSeat = _tableOrientationToRadians(_seatOrientationForPlayer(anim, owner));
      return _AnimPlan.linear(
        _CardFlightData(
          from: from,
          to: to,
          model: modelFromCardMap(c0),
          fromRadians: deckTilt,
          toRadians: toSeat,
        ),
      );
    }

    if (action == 'collect_from_discard') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isEmpty || hi == null) return null;
      final from = pileRect('discard');
      final to = rectFor(owner, hi);
      if (from == null || to == null) return null;
      final toSeat = _tableOrientationToRadians(_seatOrientationForPlayer(anim, owner));
      return _AnimPlan.linear(
        _CardFlightData(
          from: from,
          to: to,
          model: modelFromCardMap(c0),
          fromRadians: 0.06,
          toRadians: toSeat,
        ),
      );
    }

    if (action == 'same_rank_penalty_rebound') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isEmpty || hi == null) return null;
      final from = pileRect('discard');
      final to = rectFor(owner, hi);
      if (from == null || to == null) return null;
      final toSeat = _tableOrientationToRadians(_seatOrientationForPlayer(anim, owner));
      return _AnimPlan.linear(
        _CardFlightData(
          from: from,
          to: to,
          model: modelFromCardMap(c0),
          fromRadians: 0.1,
          toRadians: toSeat,
        ),
      );
    }

    if (action == 'play_card' || action == 'same_rank_play') {
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
      final fromSeat = _tableOrientationToRadians(_seatOrientationForPlayer(anim, owner));
      final discardUpright = _tableOrientationToRadians(CardTableOrientation.portraitUp);
      return _AnimPlan.linear(
        _CardFlightData(
          from: from,
          to: to,
          model: modelFromCardMap(c0),
          fromRadians: fromSeat,
          toRadians: discardUpright + 0.11,
        ),
      );
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
      final seatR = _seatRadiansForHandRect(anim, owner, to);
      return _AnimPlan.linear(
        _CardFlightData(
          from: from,
          to: to,
          model: modelFromCardMap(c0),
          fromRadians: seatR,
          toRadians: seatR,
        ),
      );
    }

    if (action == 'jack_swap') {
      if (cards.length < 2) return null;
      final c0 = cards[0];
      final c1 = cards[1];
      if (c0 is! Map || c1 is! Map) return null;
      final o0 = c0['owner_id']?.toString() ?? '';
      final o1 = c1['owner_id']?.toString() ?? '';
      final i0 = _parseHandIndex(c0['hand_index']);
      final i1 = _parseHandIndex(c1['hand_index']);
      if (o0.isEmpty || o1.isEmpty || i0 == null || i1 == null) return null;
      final r0 = rectFor(o0, i0);
      final r1 = rectFor(o1, i1);
      if (r0 == null || r1 == null) return null;
      final seat0 = _tableOrientationToRadians(_seatOrientationForPlayer(anim, o0));
      final seat1 = _tableOrientationToRadians(_seatOrientationForPlayer(anim, o1));
      // Jack swap: always face-down ghosts (no rank/suit from server payload on the flight tiles).
      return _AnimPlan.jackSwap(
        _CardFlightData(
          from: r0,
          to: r1,
          model: _placeholderFaceDown,
          fromRadians: seat0 + 0.05,
          toRadians: seat1 - 0.05,
        ),
        _CardFlightData(
          from: r1,
          to: r0,
          model: _placeholderFaceDown,
          fromRadians: seat1 - 0.05,
          toRadians: seat0 + 0.05,
        ),
      );
    }

    if (action == 'queen_peek') {
      if (cards.isEmpty) return null;
      final c0 = cards.first;
      if (c0 is! Map) return null;
      final owner = c0['owner_id']?.toString() ?? '';
      final hi = _parseHandIndex(c0['hand_index']);
      if (owner.isEmpty || hi == null) return null;
      final r = rectFor(owner, hi);
      if (r == null) return null;
      return _AnimPlan.queenPeek(r);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const SizedBox.shrink();
    if (!_shouldPaintAnim()) {
      return const SizedBox.shrink();
    }
    final anim = _runtime.snapshotForAnim();
    final events = anim[DutchAnimRuntime.eventDataKey] as List? ?? [];
    if (events.isEmpty) return const SizedBox.shrink();
    final head = events.first;
    if (head is! Map<String, dynamic>) return const SizedBox.shrink();
    final seq = head['_seq'] as int?;
    if (seq != _runningSeq) return const SizedBox.shrink();

    final t = _controller!.value;

    if (_activePlan == _PlanTag.queenPeek) {
      final r = _peekTargetRect!;
      final pulse = sin(pi * t);
      final glow = AppColors.statusQueenPeek.withValues(
        alpha: (0.35 + 0.45 * pulse).clamp(0.0, 1.0),
      );
      return TickerMode(
        enabled: true,
        child: RepaintBoundary(
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: r['left']! - 4,
                  top: r['top']! - 4,
                  width: r['width']! + 8,
                  height: r['height']! + 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: glow, width: 2.5 + pulse * 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentColor.withValues(
                            alpha: (0.25 + 0.35 * pulse).clamp(0.0, 1.0),
                          ),
                          blurRadius: 10 + 18 * pulse,
                          spreadRadius: 1 + 3 * pulse,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget positionedCard({
      required Map<String, double> from,
      required Map<String, double> to,
      required CardModel model,
      double fromRadians = 0,
      double toRadians = 0,
    }) {
      final left = from['left']! + (to['left']! - from['left']!) * t;
      final top = from['top']! + (to['top']! - from['top']!) * t;
      final outerW = from['width']! + (to['width']! - from['width']!) * t;
      final outerH = from['height']! + (to['height']! - from['height']!) * t;
      final pf = _portraitCardSizeFromLayoutRect(from['width']!, from['height']!);
      final pt = _portraitCardSizeFromLayoutRect(to['width']!, to['height']!);
      final portraitW = pf.width + (pt.width - pf.width) * t;
      final portraitH = pf.height + (pt.height - pf.height) * t;
      final dims = Size(portraitW, portraitH);
      final angle = fromRadians + (toRadians - fromRadians) * t;
      return Positioned(
        left: left,
        top: top,
        width: outerW,
        height: outerH,
        child: Transform.rotate(
          angle: angle,
          alignment: Alignment.center,
          // Layout rect centering for [GlobalKey] alignment—not my-hand row centering on the board.
          child: Center(
            child: CardWidget(
              card: model,
              dimensions: dims,
              config: CardDisplayConfig.forMyHand(),
              showBack: _activePlan == _PlanTag.jackSwap || !model.hasFullData,
              isSelected: false,
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (_playDeckGhostRect != null &&
        _playDeckGhostModel != null &&
        _activePlan == _PlanTag.linear) {
      final g = _playDeckGhostRect!;
      final gm = _playDeckGhostModel!;
      final gw = g['width']!;
      final gh = g['height']!;
      final ghostPortrait = _portraitCardSizeFromLayoutRect(gw, gh);
      children.add(
        Positioned(
          left: g['left']!,
          top: g['top']!,
          width: gw,
          height: gh,
          child: Center(
            // Same as [positionedCard]: portrait card centered in pile/slot rect for paint alignment.
            child: CardWidget(
              card: gm,
              dimensions: ghostPortrait,
              config: CardDisplayConfig.forMyHand(),
              showBack: true,
              isSelected: false,
            ),
          ),
        ),
      );
    }
    children.add(
      positionedCard(
        from: _flightFromRect!,
        to: _flightToRect!,
        model: _flightModel!,
        fromRadians: _flightFromRadians,
        toRadians: _flightToRadians,
      ),
    );
    if (_activePlan == _PlanTag.jackSwap) {
      children.add(
        positionedCard(
          from: _jackFromB!,
          to: _jackToB!,
          model: _jackModelB!,
          fromRadians: _jackFromRadiansB,
          toRadians: _jackToRadiansB,
        ),
      );
    }

    return TickerMode(
      enabled: true,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: children,
          ),
        ),
      ),
    );
  }
}
