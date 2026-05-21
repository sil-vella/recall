import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../utils/platform/shared_imports.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../utils/dev_logger.dart';
import '../../../managers/dutch_event_handler_callbacks.dart';
import 'dutch_hand_feed_formatter.dart';

const bool LOGGING_SWITCH = true;

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

  static const int _maxHandFeedLines = 3;
  final List<String> _handFeedLines = [];
  int _sameRankPlayCount = 0;

  /// Mask key for [isAnimMaskedHandSlot]; matches layout `'$playerId|$handIndex'`.
  static String handSlotMaskKey(String playerId, int handIndex) => '$playerId|$handIndex';

  bool isAnimMaskedHandSlot(String playerId, int handIndex) =>
      _animMaskedHandSlots.contains(handSlotMaskKey(playerId, handIndex));

  /// Up to [_maxHandFeedLines] event lines for the my-hand feed (same-rank v1).
  List<String> get handFeedLines => List<String>.unmodifiable(_handFeedLines);

  int get sameRankPlayCount => _sameRankPlayCount;

  /// For [UnifiedGameBoardWidget] to rebuild the feed strip without [StateManager] patches.
  String get handFeedSignature {
    if (_handFeedLines.isEmpty && _sameRankPlayCount == 0) return '';
    return '${_handFeedLines.join('\x1e')}|$_sameRankPlayCount';
  }

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
    _clearHandFeed(notify: false);
    
    notifyListeners();
  }

  /// Resets same-rank ordinal counter for a new window (feed lines are not cleared here).
  void onSameRankWindowEntered() {
    _sameRankPlayCount = 0;
  }

  void _clearHandFeed({required bool notify}) {
    final hadLines = _handFeedLines.isNotEmpty;
    final hadCount = _sameRankPlayCount != 0;
    _handFeedLines.clear();
    _sameRankPlayCount = 0;
    if (notify && (hadLines || hadCount)) {
      notifyListeners();
    }
  }

  /// Append a feed line from [game_animation] (same-rank, jack swap, queen peek).
  void appendHandFeedFromGameAnimation(
    Map<String, dynamic> payload, {
    required String currentUserId,
  }) {
    final action = payload['action_type']?.toString() ?? '';
    final actingId = DutchHandFeedFormatter.actingPlayerIdFromAnimationPayload(
      action,
      payload,
    );
    if (actingId == null) return;

    final opponents = _opponentsFromState();
    String? line;
    if (action == 'same_rank_play') {
      final ctx = payload['context'];
      final rejected = ctx is Map && ctx['rejected'] == true;
      if (rejected) {
        return;
      }
      _sameRankPlayCount++;
      line = DutchHandFeedFormatter.messageForSameRankPlay(
        actingPlayerId: actingId,
        currentUserId: currentUserId,
        opponents: opponents,
        playOrdinal: _sameRankPlayCount,
      );
    } else if (action == 'same_rank_penalty_rebound') {
      line = DutchHandFeedFormatter.messageForWrongSameRankPenalty(
        actingPlayerId: actingId,
        currentUserId: currentUserId,
        opponents: opponents,
      );
    } else if (action == 'jack_swap') {
      line = DutchHandFeedFormatter.messageForJackSwap(
        actingPlayerId: actingId,
        currentUserId: currentUserId,
        opponents: opponents,
      );
    } else if (action == 'queen_peek') {
      line = DutchHandFeedFormatter.messageForQueenPeek(
        actingPlayerId: actingId,
        currentUserId: currentUserId,
        opponents: opponents,
      );
    } else {
      return;
    }

    if (line.isEmpty) return;
    _handFeedLines.add(line);
    while (_handFeedLines.length > _maxHandFeedLines) {
      _handFeedLines.removeAt(0);
    }
    if (LOGGING_SWITCH) {
      customlog('DutchAnimRuntime.handFeed: $line');
    }
    notifyListeners();
  }

  List<dynamic> _opponentsFromState() {
    final dutch =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final panel = dutch['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final fromPanel = panel['opponents'] as List? ?? [];
    if (fromPanel.isNotEmpty) {
      return List<dynamic>.from(fromPanel);
    }
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    final gameId = dutch['currentGameId']?.toString() ?? '';
    final games = dutch['games'] as Map<String, dynamic>? ?? {};
    final game = games[gameId] as Map<String, dynamic>?;
    final gs =
        (game?['gameData'] as Map<String, dynamic>?)?['game_state'] as Map<String, dynamic>?;
    final players = gs?['players'] as List? ?? [];
    return players
        .whereType<Map<String, dynamic>>()
        .where((p) => p['id']?.toString() != currentUserId)
        .toList();
  }

  void enqueueGameAnimation(Map<String, dynamic> payload) {
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
      if (action == 'jack_swap' ||
          action == 'queen_peek' ||
          action == 'initial_peek') {
        final cards = entry['cards'] as List? ?? [];
        customlog(
          'DutchAnimRuntime.enqueue: action=$action seq=$_eventSeq cards=${cards.length} queueLen=${_eventData.length}',
        );
      }
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

  void dequeueHead() {
    if (_eventData.isEmpty) return;
    final removed = _eventData.removeAt(0);
    if (LOGGING_SWITCH) {
      final action = removed['action_type']?.toString() ?? '';
      if (action == 'jack_swap' ||
          action == 'queen_peek' ||
          action == 'initial_peek') {
        customlog(
          'DutchAnimRuntime.dequeue: action=$action seq=${removed['_seq']} remaining=${_eventData.length}',
        );
      }
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
