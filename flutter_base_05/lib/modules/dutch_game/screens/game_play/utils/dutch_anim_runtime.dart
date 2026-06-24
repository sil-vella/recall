import 'dart:convert';

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../utils/platform/shared_imports.dart';
import '../../../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

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
  /// Snapshot of discard top before a [play_card] / [same_rank_play] flight lands.
  static const String priorDiscardTopKey = 'prior_discard_top';
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

  /// Discard pile top painted by [DutchCardAnimOverlay] until the head play flight completes.
  Map<String, dynamic>? _discardTopOverlayCard;

  /// While true, [enqueueGameAnimation] drops hints (app backgrounded).
  bool _lifecyclePaused = false;

  Timer? _resumeSuppressTimer;

  static const Duration _resumeEnqueueSuppressDuration = Duration(milliseconds: 800);

  /// Acting player id from a game_animation cards payload.
  static String? ownerIdFromAnimPayload(Map<String, dynamic> payload) {
    final cards = payload['cards'] as List? ?? [];
    for (final c in cards) {
      if (c is! Map) continue;
      final id = c['owner_id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// App lifecycle hook from [GamePlayScreen] — drop/stale anim while backgrounded.
  void handleAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _lifecyclePaused = false;
        flushPendingQueueOnForegroundResume();
        _resumeSuppressTimer?.cancel();
        _resumeSuppressTimer = Timer(_resumeEnqueueSuppressDuration, () {
          _resumeSuppressTimer = null;
        });
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _lifecyclePaused = true;
        _resumeSuppressTimer?.cancel();
        _resumeSuppressTimer = null;
        break;
    }
  }

  bool get _shouldDropIncomingAnimations =>
      _lifecyclePaused || _resumeSuppressTimer != null;

  /// Clear FIFO queue and hand masks after resume; board state is authoritative.
  void flushPendingQueueOnForegroundResume() {
    final hadQueue = _eventData.isNotEmpty;
    final hadMask = _animMaskedHandSlots.isNotEmpty;
    if (!hadQueue && !hadMask) return;
    _eventData.clear();
    _animMaskedHandSlots.clear();
    _discardTopOverlayCard = null;
    if (LOGGING_SWITCH) {
      customlog(
        'DutchAnimRuntime: flush on foreground resume '
        'hadQueue=$hadQueue hadMask=$hadMask',
      );
    }
    notifyListeners();
  }

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

  static bool isPlayToDiscardAction(String action) =>
      action == 'play_card' || action == 'same_rank_play';

  static bool _isPlayToDiscardAction(String action) => isPlayToDiscardAction(action);

  /// Prior discard top held in overlay until head [play_card] / [same_rank_play] dequeues.
  Map<String, dynamic>? get discardTopOverlayCard {
    final c = _discardTopOverlayCard;
    if (c == null || c.isEmpty) return null;
    return Map<String, dynamic>.from(c);
  }

  /// For [UnifiedGameBoardWidget] anim-runtime listener dedupe / rebuild.
  String get discardTopHoldSignature {
    final hold = discardTopOverlayCard;
    if (hold == null) return '';
    return hold['cardId']?.toString() ?? '';
  }

  void _syncDiscardTopOverlayFromQueueHead() {
    Map<String, dynamic>? hold;
    for (final entry in _eventData) {
      final action = entry['action_type']?.toString() ?? '';
      if (!_isPlayToDiscardAction(action)) continue;
      final prior = entry[priorDiscardTopKey];
      if (prior is Map && prior.isNotEmpty) {
        hold = Map<String, dynamic>.from(prior);
      }
      break;
    }
    final prevId = _discardTopOverlayCard?['cardId']?.toString() ?? '';
    final nextId = hold?['cardId']?.toString() ?? '';
    if (prevId == nextId && (hold != null) == (_discardTopOverlayCard != null)) {
      return;
    }
    _discardTopOverlayCard = hold;
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
    _resumeSuppressTimer?.cancel();
    _resumeSuppressTimer = null;
    _lifecyclePaused = false;
    _eventData.clear();
    _cardPositions = {};
    _pileRects = {};
    _playerTableOrientations = {};
    _eventSeq = 0;
    _cardPositionsVersion = 0;
    _lastLayoutSignature = null;
    _animMaskedHandSlots.clear();
    _discardTopOverlayCard = null;

    notifyListeners();
  }

  void enqueueGameAnimation(Map<String, dynamic> payload) {
    if (_shouldDropIncomingAnimations) {
      if (LOGGING_SWITCH) {
        final action = payload['action_type']?.toString() ?? '';
        customlog(
          'DutchAnimRuntime: drop enqueue action=$action '
          'paused=$_lifecyclePaused suppress=${_resumeSuppressTimer != null}',
        );
      }
      return;
    }
    final action = payload['action_type']?.toString() ?? '';
    if (action == 'initial_peek' && _eventData.isNotEmpty) {
      final tail = _eventData.last;
      if (tail['action_type']?.toString() == 'initial_peek') {
        _mergeInitialPeekInto(tail, payload);
        notifyListeners();
        return;
      }
    }
    _eventSeq++;
    final entry = Map<String, dynamic>.from(payload);
    entry['_seq'] = _eventSeq;
    entry['_receivedAt'] = DateTime.now().millisecondsSinceEpoch;
    _eventData.add(entry);
    if (LOGGING_SWITCH) {
      final action = entry['action_type']?.toString() ?? '';
      if (action == 'deal' ||
          action == 'deal_batch' ||
          action == 'draw' ||
          action == 'play_card' ||
          action == 'same_rank_play' ||
          action == 'reposition' ||
          action == 'collect_from_discard' ||
          action == 'jack_swap' ||
          action == 'queen_peek' ||
          action == 'initial_peek') {
        final cards = entry['cards'] as List? ?? [];
        final optimistic = entry['_client_optimistic'] == true;
        customlog(
          'DutchAnimRuntime.enqueue: action=$action seq=$_eventSeq cards=${cards.length} '
          'queueLen=${_eventData.length} optimistic=$optimistic',
        );
      }
    }
    if (_isPlayToDiscardAction(action)) {
      _syncDiscardTopOverlayFromQueueHead();
    }
    notifyListeners();
  }

  /// Combine slot hints so phase-end peeks paint in one overlay pass (not FIFO per player).
  void _mergeInitialPeekInto(
    Map<String, dynamic> tail,
    Map<String, dynamic> incoming,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    void addFrom(List? cards) {
      if (cards == null) return;
      for (final c in cards) {
        if (c is! Map) continue;
        final owner = c['owner_id']?.toString() ?? '';
        final hi = c['hand_index'];
        final hiStr = hi?.toString() ?? '';
        if (owner.isEmpty || hiStr.isEmpty) continue;
        final key = '$owner|$hiStr';
        if (seen.add(key)) {
          merged.add(Map<String, dynamic>.from(c));
        }
      }
    }
    addFrom(tail['cards'] as List?);
    addFrom(incoming['cards'] as List?);
    if (merged.isNotEmpty) {
      tail['cards'] = merged;
    }
    final ctx = Map<String, dynamic>.from(
      tail['context'] is Map ? tail['context'] as Map : <String, dynamic>{},
    );
    ctx['batch'] = true;
    tail['context'] = ctx;
  }

  /// True when the FIFO animation queue has no pending events.
  bool get isQueueEmpty => _eventData.isEmpty;

  int get queueLength => _eventData.length;

  void dequeueHead() {
    if (_eventData.isEmpty) return;
    final removed = _eventData.removeAt(0);
    final removedAction = removed['action_type']?.toString() ?? '';
    if (LOGGING_SWITCH) {
      if (removedAction == 'jack_swap' ||
          removedAction == 'queen_peek' ||
          removedAction == 'initial_peek' ||
          removedAction == 'play_card' ||
          removedAction == 'same_rank_play') {
        customlog(
          'DutchAnimRuntime.dequeue: action=$removedAction seq=${removed['_seq']} remaining=${_eventData.length}',
        );
      }
    }
    if (_isPlayToDiscardAction(removedAction)) {
      _syncDiscardTopOverlayFromQueueHead();
    }
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
