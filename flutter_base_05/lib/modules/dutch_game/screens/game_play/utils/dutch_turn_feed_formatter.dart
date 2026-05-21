import 'dutch_opponent_seat_layout.dart';

/// Formats [turn_feed] entries from game state into short display lines.
class DutchTurnFeedFormatter {
  DutchTurnFeedFormatter._();

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
      if (ordered[i]['id']?.toString() == actingPlayerId) {
        return 'Seat ${i + 1}';
      }
    }
    return 'Seat ?';
  }

  static String _ordinalSuffix(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
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

  /// Returns display text, or null if the entry should be skipped.
  static String? formatTurnFeedEntry({
    required Map<String, dynamic> entry,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    final actionType = entry['action_type']?.toString() ?? '';
    final actingId = entry['acting_player_id']?.toString() ?? '';
    if (actingId.isEmpty) return null;

    final who = actingPlayerLabel(
      actingPlayerId: actingId,
      currentUserId: currentUserId,
      opponents: opponents,
    );

    switch (actionType) {
      case 'same_rank_play':
        final ordinalRaw = entry['play_ordinal'];
        final ordinal = ordinalRaw is int
            ? ordinalRaw
            : (ordinalRaw is num ? ordinalRaw.toInt() : int.tryParse('$ordinalRaw') ?? 0);
        if (ordinal <= 0) return null;
        return '$who played the ${_ordinalSuffix(ordinal)} card in same rank';

      case 'same_rank_penalty_rebound':
        if (who == 'You') {
          return 'Wrong same rank attempt. You were given a penalty card';
        }
        return 'Wrong same rank attempt. $who was given a penalty card';

      case 'jack_swap':
        return '$who swapped 2 cards';

      case 'queen_peek':
        return '$who peeked at a card';

      case 'timer_miss_draw':
        return '$who failed to draw a card';

      case 'timer_miss_play':
        return '$who failed to play a card';

      default:
        return null;
    }
  }
}
