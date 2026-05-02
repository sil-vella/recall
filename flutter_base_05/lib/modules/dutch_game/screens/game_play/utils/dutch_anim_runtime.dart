import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../utils/platform/shared_imports.dart';

/// In-memory animation bus for Dutch: **not** written through [StateManager], so updating
/// queue or layout rects does **not** notify `dutch_game` listeners or rebuild unrelated widgets.
///
/// Registered once on `dutch_game['animRuntime']` for discovery/debug only — **do not** replace
/// that key in patches. At anim time, read [DutchAnimRuntime.instance] directly (or from module
/// state reference). The anim overlay and [UnifiedGameBoardWidget] may [addListener]; the board
/// should dedupe using [handAnimMaskSignature] so [mergeLayout] does not cause redundant rebuilds.
class DutchAnimRuntime extends ChangeNotifier {
  DutchAnimRuntime._();
  static final DutchAnimRuntime instance = DutchAnimRuntime._();

  static const bool LOGGING_SWITCH = false; // Anim queue / layout (enable-logging-switch.mdc; set false after test)
  final Logger _logger = Logger();

  static const String eventDataKey = 'eventData';
  static const String cardPositionsKey = 'cardPositions';
  static const String pileRectsKey = 'pileRects';
  static const String eventSeqKey = 'eventSeq';
  static const String cardPositionsVersionKey = 'cardPositionsVersion';

  final List<Map<String, dynamic>> _eventData = [];
  Map<String, dynamic> _cardPositions = {};
  Map<String, dynamic> _pileRects = {};
  int _eventSeq = 0;
  int _cardPositionsVersion = 0;
  String? _lastLayoutSignature;

  /// Hand slots (`playerId|handIndex`) whose real [CardWidget] should not paint during an
  /// in-flight overlay tween (see [DutchCardAnimOverlay]). Same keys as layout slot paths.
  final Set<String> _animMaskedHandSlots = {};

  /// Mask key for [isAnimMaskedHandSlot]; matches layout `'$playerId|$handIndex'`.
  static String handSlotMaskKey(String playerId, int handIndex) => '$playerId|$handIndex';

  bool isAnimMaskedHandSlot(String playerId, int handIndex) =>
      _animMaskedHandSlots.contains(handSlotMaskKey(playerId, handIndex));

  /// For listeners that should rebuild only when the mask set changes (not on every [mergeLayout]).
  String get handAnimMaskSignature {
    if (_animMaskedHandSlots.isEmpty) return '';
    final sorted = _animMaskedHandSlots.toList()..sort();
    return sorted.join(',');
  }

  void setAnimMaskedHandSlots(Set<String> keys) {
    final next = Set<String>.from(keys);
    if (_animMaskedHandSlots.length == next.length && _animMaskedHandSlots.containsAll(next)) {
      return;
    }
    _animMaskedHandSlots
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clearAnimMaskedHandSlots() {
    if (_animMaskedHandSlots.isEmpty) return;
    _animMaskedHandSlots.clear();
    notifyListeners();
  }

  /// Snapshot compatible with previous [animState] map shape (read-only copy).
  Map<String, dynamic> snapshotForAnim() {
    return <String, dynamic>{
      eventDataKey: List<Map<String, dynamic>>.from(_eventData),
      cardPositionsKey: Map<String, dynamic>.from(_cardPositions),
      pileRectsKey: Map<String, dynamic>.from(_pileRects),
      eventSeqKey: _eventSeq,
      cardPositionsVersionKey: _cardPositionsVersion,
    };
  }

  void reset() {
    _eventData.clear();
    _cardPositions = {};
    _pileRects = {};
    _eventSeq = 0;
    _cardPositionsVersion = 0;
    _lastLayoutSignature = null;
    _animMaskedHandSlots.clear();
    if (LOGGING_SWITCH) {
      _logger.info('DutchAnimRuntime: reset (queue + layout cleared)');
    }
    notifyListeners();
  }

  void enqueueGameAnimation(Map<String, dynamic> payload) {
    _eventSeq++;
    final entry = Map<String, dynamic>.from(payload);
    entry['_seq'] = _eventSeq;
    entry['_receivedAt'] = DateTime.now().millisecondsSinceEpoch;
    _eventData.add(entry);
    if (LOGGING_SWITCH) {
      final action = entry['action_type']?.toString() ?? '';
      final gid = entry['game_id']?.toString() ?? '';
      _logger.info(
        'DutchAnimRuntime: enqueue seq=$_eventSeq action=$action gameId=$gid queueLen=${_eventData.length}',
      );
    }
    notifyListeners();
  }

  void dequeueHead() {
    if (_eventData.isEmpty) return;
    final removed = _eventData.removeAt(0);
    if (LOGGING_SWITCH) {
      final seq = removed['_seq'];
      final action = removed['action_type']?.toString() ?? '';
      _logger.info(
        'DutchAnimRuntime: dequeueHead seq=$seq action=$action remaining=${_eventData.length}',
      );
    }
    notifyListeners();
  }

  /// Updates hand/pile rects. Does **not** notify if geometry unchanged (dedupe by JSON sig).
  /// When positions change, notifies **only** [DutchAnimRuntime] listeners (overlay), not [StateManager].
  void mergeLayout({
    required Map<String, dynamic> cardPositions,
    Map<String, dynamic>? pileRects,
  }) {
    // After play+draw shrink to 4 visible slots, layout no longer reports index `4`, but
    // `reposition` anim needs the last rect for the 5th (drawn) slot — carry it forward per player.
    final mergedPlayers = <String, dynamic>{};
    for (final e in cardPositions.entries) {
      final pid = e.key;
      final incoming = Map<String, dynamic>.from(e.value as Map? ?? {});
      final prevPm = _cardPositions[pid];
      if (prevPm is Map<String, dynamic>) {
        final prev4 = prevPm['4'];
        if (prev4 != null && !incoming.containsKey('4')) {
          incoming['4'] = prev4;
        }
      }
      mergedPlayers[pid] = incoming;
    }
    final sig = '${jsonEncode(mergedPlayers)}|${jsonEncode(pileRects ?? _pileRects)}';
    if (sig == _lastLayoutSignature) {
      if (LOGGING_SWITCH && _eventData.isNotEmpty) {
        _logger.debug(
          'DutchAnimRuntime: mergeLayout skipped (unchanged sig) queueLen=${_eventData.length}',
        );
      }
      return;
    }
    _lastLayoutSignature = sig;
    _cardPositions = mergedPlayers;
    if (pileRects != null) {
      _pileRects = Map<String, dynamic>.from(pileRects);
    }
    _cardPositionsVersion++;
    if (LOGGING_SWITCH) {
      final nPlayers = _cardPositions.length;
      _logger.info(
        'DutchAnimRuntime: mergeLayout applied version=$_cardPositionsVersion players=$nPlayers',
      );
    }
    notifyListeners();
  }

  /// Rect of [slot] relative to [anchor] top-left (global subtraction).
  static Map<String, double>? rectRelativeToAnchor(GlobalKey slotKey, GlobalKey anchorKey) {
    final slotCtx = slotKey.currentContext;
    final anchorCtx = anchorKey.currentContext;
    if (slotCtx == null || anchorCtx == null) return null;
    final slotBox = slotCtx.findRenderObject();
    final anchorBox = anchorCtx.findRenderObject();
    if (slotBox is! RenderBox || anchorBox is! RenderBox) return null;
    if (!slotBox.hasSize || !anchorBox.hasSize) return null;
    if (!slotBox.attached || !anchorBox.attached) return null;
    final slotOrigin = slotBox.localToGlobal(Offset.zero);
    final anchorOrigin = anchorBox.localToGlobal(Offset.zero);
    final topLeft = slotOrigin - anchorOrigin;
    final size = slotBox.size;
    return <String, double>{
      'left': topLeft.dx,
      'top': topLeft.dy,
      'width': size.width,
      'height': size.height,
    };
  }
}
