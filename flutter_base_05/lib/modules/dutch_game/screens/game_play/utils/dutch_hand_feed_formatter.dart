import 'dutch_opponent_seat_layout.dart';

/// Formats my-hand feed lines for same-rank window events (animation-driven).
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

  static String? cardRankSuitParenthetical(Map<String, dynamic>? card) {
    if (card == null) return null;
    final rank = card['rank']?.toString() ?? '';
    final suit = card['suit']?.toString() ?? '';
    if (rank.isEmpty || rank == '?' || suit.isEmpty || suit == '?') {
      return null;
    }
    return '$rank of $suit';
  }

  static String messageForSameRankPlay({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
    required int playOrdinal,
    Map<String, dynamic>? card,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    final ordinal = _ordinal(playOrdinal);
    final detail = cardRankSuitParenthetical(card);
    final suffix = detail != null ? ' ($detail)' : '';
    if (who == 'You') {
      return 'You have played the $ordinal card during same rank$suffix';
    }
    return '$who has played the $ordinal card during same rank$suffix';
  }

  /// Phase-1 wrong attempt (card briefly hits discard; rebound follows).
  static String messageForWrongSameRankAttempt({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
    Map<String, dynamic>? card,
  }) {
    final who = actingPlayerLabel(
      actingPlayerId: actingPlayerId,
      currentUserId: currentUserId,
      opponents: opponents,
    );
    final detail = cardRankSuitParenthetical(card);
    final suffix = detail != null ? ' ($detail)' : '';
    if (who == 'You') {
      return 'You played the wrong rank during same rank$suffix';
    }
    return '$who played the wrong rank during same rank$suffix';
  }

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
      return 'You got a penalty card for wrong same rank';
    }
    return '$who got a penalty card for wrong same rank';
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

  /// [owner_id] from first [cards] entry in a [game_animation] payload.
  static String? ownerIdFromAnimationPayload(Map<String, dynamic> payload) {
    final cards = payload['cards'] as List? ?? [];
    if (cards.isEmpty) return null;
    final c0 = cards.first;
    if (c0 is! Map) return null;
    final owner = c0['owner_id']?.toString() ?? '';
    return owner.isEmpty ? null : owner;
  }

  static Map<String, dynamic>? cardFromAnimationPayload(Map<String, dynamic> payload) {
    final cards = payload['cards'] as List? ?? [];
    if (cards.isEmpty) return null;
    final c0 = cards.first;
    if (c0 is! Map) return null;
    final card = c0['card'];
    if (card is Map<String, dynamic>) {
      return Map<String, dynamic>.from(card);
    }
    if (card is Map) {
      return Map<String, dynamic>.from(card);
    }
    return null;
  }
}
