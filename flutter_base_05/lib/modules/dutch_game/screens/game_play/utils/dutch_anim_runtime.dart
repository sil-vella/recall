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

  static const String eventDataKey = 'eventData';
  static const String cardPositionsKey = 'cardPositions';
  static const String pileRectsKey = 'pileRects';
  static const String eventSeqKey = 'eventSeq';
  static const String cardPositionsVersionKey = 'cardPositionsVersion';
  /// Per [playerId] → [CardTableOrientation.name] (from [UnifiedGameBoardWidget] seat buckets).
  static const String playerTableOrientationsKey = 'playerTableOrientations';

  final List<Map<String, dynamic>> _eventData = [];
  Map<String, dynamic> _cardPositions = {};
  Map<String, dynamic> _pileRects = {};
  Map<String, String> _playerTableOrientations = {};
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
      playerTableOrientationsKey: Map<String, String>.from(_playerTableOrientations),
    };
  }

  void reset() {
    _eventData.clear();
    _cardPositions = {};
    _pileRects = {};
    _playerTableOrientations = {};
    _eventSeq = 0;
    _cardPositionsVersion = 0;
    _lastLayoutSignature = null;
    _animMaskedHandSlots.clear();
    
    notifyListeners();
  }

  void enqueueGameAnimation(Map<String, dynamic> payload) {
    _eventSeq++;
    final entry = Map<String, dynamic>.from(payload);
    entry['_seq'] = _eventSeq;
    entry['_receivedAt'] = DateTime.now().millisecondsSinceEpoch;
    _eventData.add(entry);
    
    notifyListeners();
  }

  void dequeueHead() {
    if (_eventData.isEmpty) return;
    final removed = _eventData.removeAt(0);
    
    notifyListeners();
  }

  /// Updates hand/pile rects. Does **not** notify if geometry unchanged (dedupe by JSON sig).
  /// When positions change, notifies **only** [DutchAnimRuntime] listeners (overlay), not [StateManager].
  void mergeLayout({
    required Map<String, dynamic> cardPositions,
    Map<String, dynamic>? pileRects,
    Map<String, String>? playerTableOrientations,
  }) {
    // Slots without a measured [GlobalKey] this frame (e.g. hand shrank after play, or a
    // collection-stack index skipped in the widget tree) are omitted from [cardPositions].
    // Carry forward any previous slot rects still missing so [reposition] / play-ghost can
    // resolve until the next layout captures that index again.
    final mergedPlayers = <String, dynamic>{};
    for (final e in cardPositions.entries) {
      final pid = e.key;
      final incoming = Map<String, dynamic>.from(e.value as Map? ?? {});
      final prevPm = _cardPositions[pid];
      if (prevPm is Map<String, dynamic>) {
        for (final ke in prevPm.entries) {
          if (!incoming.containsKey(ke.key)) {
            incoming[ke.key] = ke.value;
          }
        }
      }
      mergedPlayers[pid] = incoming;
    }
    if (playerTableOrientations != null) {
      _playerTableOrientations = Map<String, String>.from(playerTableOrientations);
    }
    final sig =
        '${jsonEncode(mergedPlayers)}|${jsonEncode(pileRects ?? _pileRects)}|${jsonEncode(_playerTableOrientations)}';
    if (sig == _lastLayoutSignature) {
      
      return;
    }
    _lastLayoutSignature = sig;
    _cardPositions = mergedPlayers;
    if (pileRects != null) {
      _pileRects = Map<String, dynamic>.from(pileRects);
    }
    _cardPositionsVersion++;
    
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
