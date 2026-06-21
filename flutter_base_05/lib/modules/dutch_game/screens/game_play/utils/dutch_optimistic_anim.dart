import 'dutch_anim_runtime.dart';
import '../../../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// Client-side optimistic [game_animation] hints for local multiplayer actions.
///
/// Enqueues into [DutchAnimRuntime] on tap so flights start before the server
/// round-trip. Authoritative server hints are deduped via [shouldSkipServerDuplicate].
class DutchOptimisticAnim {
  DutchOptimisticAnim._();

  static const Duration _fingerprintTtl = Duration(milliseconds: 600);

  static const String clientOptimisticKey = '_client_optimistic';
  static const String fingerprintKey = '_optimistic_fingerprint';

  static final Map<String, DateTime> _recentFingerprints = {};

  static bool isMultiplayerRoom(String? gameId) {
    final id = gameId?.trim() ?? '';
    return id.startsWith('room_');
  }

  static int? _parseHandIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Stable key from action metadata — must match server [game_animation] shape.
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
      final owner = entry['owner_id']?.toString() ?? '';
      final handIndex = _parseHandIndex(entry['hand_index']);
      final fromIndex = _parseHandIndex(entry['from_hand_index']) ??
          _parseHandIndex(entry['fromHandIndex']);
      final card = entry['card'];
      final cardId = card is Map ? (card['cardId']?.toString() ?? '') : '';
      parts.add('$owner|hi=$handIndex|from=$fromIndex|cid=$cardId');
    }
    return parts.join(';');
  }

  static void _pruneExpiredFingerprints() {
    final now = DateTime.now();
    _recentFingerprints.removeWhere(
      (_, registeredAt) => now.difference(registeredAt) > _fingerprintTtl,
    );
  }

  static void _registerFingerprint(String fingerprint) {
    _pruneExpiredFingerprints();
    _recentFingerprints[fingerprint] = DateTime.now();
  }

  static bool _hasFingerprint(String fingerprint) {
    _pruneExpiredFingerprints();
    return _recentFingerprints.containsKey(fingerprint);
  }

  static void _consumeFingerprint(String fingerprint) {
    _recentFingerprints.remove(fingerprint);
  }

  /// Enqueue a local optimistic animation (multiplayer rooms only).
  static void enqueueLocal(Map<String, dynamic> payload, {required String gameId}) {
    if (!isMultiplayerRoom(gameId)) return;

    final fingerprint = optimisticFingerprint(payload);
    final entry = Map<String, dynamic>.from(payload);
    entry[clientOptimisticKey] = true;
    entry[fingerprintKey] = fingerprint;
    _registerFingerprint(fingerprint);

    if (LOGGING_SWITCH) {
      customlog(
        'DutchOptimisticAnim.enqueueLocal: gameId=$gameId action=${payload['action_type']} fp=$fingerprint',
      );
    }

    DutchAnimRuntime.instance.enqueueGameAnimation(entry);
  }

  /// Skip inbound server hint when it duplicates a recent optimistic enqueue.
  static bool shouldSkipServerDuplicate(Map<String, dynamic> serverPayload) {
    if (serverPayload[clientOptimisticKey] == true) return false;

    final fingerprint = optimisticFingerprint(serverPayload);
    if (!_hasFingerprint(fingerprint)) return false;

    _consumeFingerprint(fingerprint);
    if (LOGGING_SWITCH) {
      customlog(
        'DutchOptimisticAnim.skipServerDuplicate: action=${serverPayload['action_type']} fp=$fingerprint',
      );
    }
    return true;
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
    if (drawnId.isNotEmpty && drawnId != playedCardId && handCards != null) {
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

    enqueueLocal(<String, dynamic>{
      'action_type': actionType,
      'cards': cards,
    }, gameId: gameId);
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
