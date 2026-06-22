import 'dutch_anim_runtime.dart';
import '../../../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// Primary hand slot for matching optimistic vs server [game_animation] hints.
class _ActionSlot {
  const _ActionSlot({
    required this.ownerId,
    required this.actionType,
    required this.handIndex,
    this.cardId,
    this.source = '',
  });

  final String ownerId;
  final String actionType;
  final int handIndex;
  final String? cardId;
  final String source;
}

/// Client-side optimistic [game_animation] hints for local multiplayer actions.
///
/// Enqueues into [DutchAnimRuntime] on tap so flights start before the server
/// round-trip. Authoritative server hints are suppressed via fingerprint, pending
/// claim, or an optimistic entry still in the anim queue.
class DutchOptimisticAnim {
  DutchOptimisticAnim._();

  /// Cover flight (420ms) + reposition follow-up + network jitter.
  static const Duration _claimTtl = Duration(milliseconds: 900);

  static const String clientOptimisticKey = '_client_optimistic';
  static const String fingerprintKey = '_optimistic_fingerprint';

  static final Map<String, DateTime> _recentFingerprints = {};
  static final List<({_ActionSlot slot, DateTime registeredAt})> _pendingClaims = [];

  static const Set<String> _localOptimisticActions = {
    'draw',
    'play_card',
    'same_rank_play',
    'collect_from_discard',
  };

  static bool isMultiplayerRoom(String? gameId) {
    final id = gameId?.trim() ?? '';
    return id.startsWith('room_');
  }

  static int? _parseHandIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Stable key from action metadata — ghost-only card entries are omitted so
  /// server payloads with fewer [cards] still match.
  static String optimisticFingerprint(Map<String, dynamic> payload) {
    final action = payload['action_type']?.toString() ?? '';
    final source = payload['source']?.toString() ?? '';
    final cards = payload['cards'] as List? ?? [];
    final parts = <String>[action];
    if (source.isNotEmpty) {
      parts.add('src=$source');
    }
    for (final entry in cards) {
      if (entry is! Map) continue;
      final card = entry['card'];
      final isDrawLike = action == 'draw' || action == 'deal';
      if (card is! Map && !isDrawLike) {
        continue;
      }
      final owner = entry['owner_id']?.toString() ?? '';
      final handIndex = _parseHandIndex(entry['hand_index']);
      final fromIndex = _parseHandIndex(entry['from_hand_index']) ??
          _parseHandIndex(entry['fromHandIndex']);
      final cardId = card is Map ? (card['cardId']?.toString() ?? '') : '';
      parts.add('$owner|hi=$handIndex|from=$fromIndex|cid=$cardId');
    }
    return parts.join(';');
  }

  static _ActionSlot? _primarySlotFromPayload(Map<String, dynamic> payload) {
    final actionType = payload['action_type']?.toString() ?? '';
    if (actionType.isEmpty) return null;

    final source = payload['source']?.toString() ?? '';
    final cards = payload['cards'] as List? ?? [];
    if (cards.isEmpty) return null;

    Map<dynamic, dynamic>? primary;
    for (final entry in cards) {
      if (entry is Map && entry['card'] is Map) {
        primary = entry;
        break;
      }
    }
    primary ??= cards.first is Map ? cards.first as Map : null;
    if (primary == null) return null;

    final ownerId = primary['owner_id']?.toString() ?? '';
    final handIndex = _parseHandIndex(primary['hand_index']);
    if (ownerId.isEmpty || handIndex == null) return null;

    final card = primary['card'];
    final cardId = card is Map ? card['cardId']?.toString() : null;
    return _ActionSlot(
      ownerId: ownerId,
      actionType: actionType,
      handIndex: handIndex,
      cardId: cardId != null && cardId.isNotEmpty ? cardId : null,
      source: source,
    );
  }

  static bool _slotsMatch(_ActionSlot a, _ActionSlot b) {
    if (a.ownerId != b.ownerId) return false;
    if (a.actionType != b.actionType) return false;
    if (a.handIndex != b.handIndex) return false;
    if (a.source.isNotEmpty && b.source.isNotEmpty && a.source != b.source) {
      return false;
    }
    if (a.cardId != null && b.cardId != null && a.cardId != b.cardId) {
      return false;
    }
    return true;
  }

  static void _pruneExpired() {
    final now = DateTime.now();
    _recentFingerprints.removeWhere(
      (_, registeredAt) => now.difference(registeredAt) > _claimTtl,
    );
    _pendingClaims.removeWhere(
      (claim) => now.difference(claim.registeredAt) > _claimTtl,
    );
  }

  static void _registerFingerprint(String fingerprint) {
    _pruneExpired();
    _recentFingerprints[fingerprint] = DateTime.now();
  }

  static bool _hasFingerprint(String fingerprint) {
    _pruneExpired();
    return _recentFingerprints.containsKey(fingerprint);
  }

  static void _consumeFingerprint(String fingerprint) {
    _recentFingerprints.remove(fingerprint);
  }

  static void _registerClaim(_ActionSlot slot) {
    _pruneExpired();
    _pendingClaims.add((slot: slot, registeredAt: DateTime.now()));
  }

  static bool _consumeMatchingClaim(_ActionSlot serverSlot) {
    for (int i = 0; i < _pendingClaims.length; i++) {
      if (_slotsMatch(_pendingClaims[i].slot, serverSlot)) {
        _pendingClaims.removeAt(i);
        return true;
      }
    }
    return false;
  }

  static bool _hasMatchingClaim(_ActionSlot serverSlot) {
    _pruneExpired();
    for (final claim in _pendingClaims) {
      if (_slotsMatch(claim.slot, serverSlot)) return true;
    }
    return false;
  }

  static bool _serverCoveredByOptimisticQueue(_ActionSlot serverSlot) {
    final snapshot = DutchAnimRuntime.instance.snapshotForAnim();
    final events = snapshot[DutchAnimRuntime.eventDataKey] as List? ?? [];
    for (final entry in events) {
      if (entry is! Map || entry[clientOptimisticKey] != true) continue;
      final optimisticSlot = _primarySlotFromPayload(Map<String, dynamic>.from(entry));
      if (optimisticSlot != null && _slotsMatch(optimisticSlot, serverSlot)) {
        return true;
      }
    }
    return false;
  }

  /// Enqueue a local optimistic animation (multiplayer rooms only).
  static void enqueueLocal(Map<String, dynamic> payload, {required String gameId}) {
    if (!isMultiplayerRoom(gameId)) return;

    final fingerprint = optimisticFingerprint(payload);
    final entry = Map<String, dynamic>.from(payload);
    entry[clientOptimisticKey] = true;
    entry[fingerprintKey] = fingerprint;
    _registerFingerprint(fingerprint);

    final slot = _primarySlotFromPayload(payload);
    if (slot != null) {
      _registerClaim(slot);
    }

    if (LOGGING_SWITCH) {
      customlog(
        'DutchOptimisticAnim.enqueueLocal: gameId=$gameId action=${payload['action_type']} fp=$fingerprint',
      );
    }

    DutchAnimRuntime.instance.enqueueGameAnimation(entry);
  }

  /// Skip inbound server hint when local optimistic already owns this flight.
  static bool shouldSkipServerDuplicate(Map<String, dynamic> serverPayload) {
    if (serverPayload[clientOptimisticKey] == true) return false;

    final actionType = serverPayload['action_type']?.toString() ?? '';
    if (!_localOptimisticActions.contains(actionType)) return false;

    final serverSlot = _primarySlotFromPayload(serverPayload);
    if (serverSlot == null) return false;

    final fingerprint = optimisticFingerprint(serverPayload);
    if (_hasFingerprint(fingerprint)) {
      _consumeFingerprint(fingerprint);
      if (LOGGING_SWITCH) {
        customlog(
          'DutchOptimisticAnim.skipServerDuplicate: reason=fingerprint action=$actionType fp=$fingerprint',
        );
      }
      _consumeMatchingClaim(serverSlot);
      return true;
    }

    if (_hasMatchingClaim(serverSlot)) {
      _consumeMatchingClaim(serverSlot);
      if (LOGGING_SWITCH) {
        customlog(
          'DutchOptimisticAnim.skipServerDuplicate: reason=claim action=$actionType '
          'owner=${serverSlot.ownerId} handIndex=${serverSlot.handIndex}',
        );
      }
      return true;
    }

    if (_serverCoveredByOptimisticQueue(serverSlot)) {
      if (LOGGING_SWITCH) {
        customlog(
          'DutchOptimisticAnim.skipServerDuplicate: reason=queue action=$actionType '
          'owner=${serverSlot.ownerId} handIndex=${serverSlot.handIndex}',
        );
      }
      return true;
    }

    return false;
  }

  /// Optimistic [play_card] / [same_rank_play] — mirrors [DutchGameRound._emitActionAnimation].
  static void enqueuePlayFromHand({
    required String gameId,
    required String ownerId,
    required int handIndex,
    required Map<String, dynamic> card,
    required String actionType,
    Map<String, dynamic>? drawnCard,
    List<dynamic>? handCards,
    Map<String, dynamic>? priorDiscardTop,
  }) {
    if (!isMultiplayerRoom(gameId)) return;

    final cards = <Map<String, dynamic>>[
      <String, dynamic>{
        'owner_id': ownerId,
        'hand_index': handIndex,
        'card': Map<String, dynamic>.from(card),
      },
    ];

    final playedCardId = card['cardId']?.toString() ?? '';
    final drawnId = drawnCard?['cardId']?.toString() ?? '';
    if (drawnId.isNotEmpty &&
        drawnId != playedCardId &&
        handCards != null &&
        actionType == 'play_card') {
      for (int i = 0; i < handCards.length; i++) {
        final slot = handCards[i];
        if (slot is Map && slot['cardId']?.toString() == drawnId) {
          cards.add(<String, dynamic>{
            'owner_id': ownerId,
            'hand_index': i,
          });
          break;
        }
      }
    }

    final payload = <String, dynamic>{
      'action_type': actionType,
      'cards': cards,
    };
    if (priorDiscardTop != null && priorDiscardTop.isNotEmpty) {
      payload[DutchAnimRuntime.priorDiscardTopKey] =
          Map<String, dynamic>.from(priorDiscardTop);
    }
    enqueueLocal(payload, gameId: gameId);
  }

  /// Optimistic [draw] — drawn cards append to hand end (hand_index = current length).
  static void enqueueDraw({
    required String gameId,
    required String ownerId,
    required int handIndex,
    required String source,
    Map<String, dynamic>? card,
  }) {
    if (!isMultiplayerRoom(gameId)) return;

    final drawCard = <String, dynamic>{
      'owner_id': ownerId,
      'hand_index': handIndex,
    };
    if (source == 'discard' && card != null && card.isNotEmpty) {
      drawCard['card'] = Map<String, dynamic>.from(card);
    }

    enqueueLocal(<String, dynamic>{
      'action_type': 'draw',
      'source': source,
      'cards': [drawCard],
    }, gameId: gameId);
  }
}
