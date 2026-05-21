import 'dutch_opponent_seat_layout.dart';

/// Formats my-hand feed lines for special-action animations (animation-driven).
class DutchHandFeedFormatter {
  DutchHandFeedFormatter._();

  /// Seat 1..N from table buckets (left, then top, then right). [currentUserId] → "You".
  static String actingPlayerLabel({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    if (actingPlayerId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        actingPlayerId == currentUserId) {
      return 'You';
    }
    final buckets = bucketOpponentsForDutchTable(opponents);
    final ordered = <Map<String, dynamic>>[
      ...buckets.left,
      ...buckets.top,
      ...buckets.right,
    ];
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i]['id']?.toString() ?? '';
      if (id == actingPlayerId) {
        return 'Seat ${i + 1}';
      }
    }
    return 'Seat ?';
  }

  /// Valid same-rank play — ordinal index only (no card rank/suit).
  static String messageForSameRankPlay({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
    required int playOrdinal,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    final ordinal = _ordinal(playOrdinal);
    if (who == 'You') {
      return 'You played the $ordinal card in same rank';
    }
    return '$who played the $ordinal card in same rank';
  }

  static String messageForJackSwap({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    if (who == 'You') {
      return 'You swapped 2 cards';
    }
    return '$who swapped 2 cards';
  }

  static String messageForQueenPeek({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    if (who == 'You') {
      return 'You peeked at a card';
    }
    return '$who peeked at a card';
  }

  /// Wrong same-rank — penalty draw only (no card details).
  static String messageForWrongSameRankPenalty({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    if (who == 'You') {
      return 'You were given a penalty card';
    }
    return '$who was given a penalty card';
  }

  static String _ordinal(int n) {
    if (n <= 0) return '${n}th';
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// Player who performed the action (varies by [actionType] / [context]).
  static String? actingPlayerIdFromAnimationPayload(
    String actionType,
    Map<String, dynamic> payload,
  ) {
    final ctx = payload['context'];
    if (ctx is Map) {
      final ctxMap = Map<String, dynamic>.from(ctx);
      if (actionType == 'jack_swap') {
        final id = ctxMap['acting_player_id']?.toString() ?? '';
        if (id.isNotEmpty) return id;
      }
      if (actionType == 'queen_peek') {
        final id = ctxMap['peeking_player_id']?.toString() ?? '';
        if (id.isNotEmpty) return id;
      }
    }
    return ownerIdFromAnimationPayload(payload);
  }

  /// [owner_id] from first [cards] entry in a [game_animation] payload.
  static String? ownerIdFromAnimationPayload(Map<String, dynamic> payload) {
    final cards = payload['cards'] as List? ?? [];
    if (cards.isEmpty) return null;
    final c0 = cards.first;
    if (c0 is! Map) return null;
    final owner = c0['owner_id']?.toString() ?? '';
    return owner.isEmpty ? null : owner;
  }
}
