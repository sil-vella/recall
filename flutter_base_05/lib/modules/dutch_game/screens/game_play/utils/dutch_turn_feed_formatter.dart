import '../../../../../utils/dev_logger.dart';
import 'dutch_opponent_seat_layout.dart';

/// When true, logs turn_feed seat resolution and hand_index fields ([LOGGING_SWITCH]).
const bool LOGGING_SWITCH = false;

/// Formats [turn_feed] entries from game state into short display lines.
class DutchTurnFeedFormatter {
  DutchTurnFeedFormatter._();

  static bool _seatIdMatches(Map<String, dynamic> player, String seatOrUserId) {
    if (seatOrUserId.isEmpty) return false;
    final pid = player['id']?.toString() ?? '';
    if (pid.isNotEmpty && pid == seatOrUserId) return true;
    final uid = player['userId']?.toString().trim() ??
        player['user_id']?.toString().trim() ??
        '';
    if (uid.isNotEmpty) {
      if (seatOrUserId == uid) return true;
      if (seatOrUserId == 'hum_$uid') return true;
      if (pid == 'hum_$uid' && seatOrUserId == uid) return true;
    }
    return false;
  }

  static int? _parseHandIndex(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  /// Game-state hand slot → user-facing label (0 → Card 1, 3 → Card 4).
  static String cardLabelForHandIndex(int logicalHandIndex) {
    if (logicalHandIndex < 0) return '';
    return 'Card ${logicalHandIndex + 1}';
  }

  static String _opponentIdsBrief(List<dynamic> opponents) {
    final parts = <String>[];
    for (final o in opponents) {
      if (o is! Map) continue;
      final m = Map<String, dynamic>.from(o);
      parts.add(
        'id=${m['id']?.toString() ?? ''} userId=${m['userId']?.toString() ?? m['user_id']?.toString() ?? ''}',
      );
    }
    return parts.isEmpty ? '(none)' : parts.join('; ');
  }

  /// Seat 1..N from table buckets (left, then top, then right). [currentUserId] → "You".
  static String actingPlayerLabel({
    required String actingPlayerId,
    required String currentUserId,
    required List<dynamic> opponents,
  }) {
    if (actingPlayerId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        actingPlayerId == currentUserId) {
      if (LOGGING_SWITCH) {
        customlog(
          'TurnFeedFormatter: actingPlayerLabel You '
          '(acting=$actingPlayerId currentUserId=$currentUserId)',
        );
      }
      return 'You';
    }
    final buckets = bucketOpponentsForDutchTable(opponents);
    final ordered = <Map<String, dynamic>>[
      ...buckets.left,
      ...buckets.top,
      ...buckets.right,
    ];
    for (var i = 0; i < ordered.length; i++) {
      if (_seatIdMatches(ordered[i], actingPlayerId)) {
        if (LOGGING_SWITCH) {
          customlog(
            'TurnFeedFormatter: actingPlayerLabel Seat ${i + 1} '
            '(acting=$actingPlayerId opponentId=${ordered[i]['id']})',
          );
        }
        return 'Seat ${i + 1}';
      }
    }
    if (LOGGING_SWITCH) {
      customlog(
        'TurnFeedFormatter: actingPlayerLabel Seat ? '
        '(acting=$actingPlayerId currentUserId=$currentUserId opponents=$_opponentIdsBrief(opponents))',
      );
    }
    return 'Seat ?';
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

    if (LOGGING_SWITCH) {
      customlog(
        'TurnFeedFormatter: format action=$actionType acting=$actingId who=$who '
        'hand_index=${entry['hand_index']} hand_indices=${entry['hand_indices']} '
        'swap_slots=${entry['swap_slots']} play_ordinal=${entry['play_ordinal']}',
      );
    }

    switch (actionType) {
      case 'same_rank_play':
        final handIndex = _parseHandIndex(entry['hand_index']);
        if (handIndex == null || handIndex < 0) return null;
        final card = cardLabelForHandIndex(handIndex);
        return '$who played $card in same rank';

      case 'same_rank_penalty_rebound':
        if (who == 'You') {
          return 'Wrong same rank attempt. You were given a penalty card';
        }
        return 'Wrong same rank attempt. $who was given a penalty card';

      case 'jack_swap_can':
        return '$who can swap cards';

      case 'queen_peek_can':
        return '$who can peek at a card';

      case 'jack_swap':
        return '$who swapped cards';

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
