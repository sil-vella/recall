import '../../../core/managers/state_manager.dart';
import '../../../utils/analytics_service.dart';

/// Dutch-specific Firebase (GA4) events. Product funnels only — not backend analytics.
abstract final class DutchFirebaseAnalytics {
  static final Set<String> _matchCompletedLoggedGameIds = <String>{};

  static void resetSession() {
    _matchCompletedLoggedGameIds.clear();
  }

  /// Server confirmed a new room the user created (lobby create, not random matchmaking).
  static Future<void> logRoomCreated({required String roomId}) {
    return AnalyticsService.logEvent(
      name: 'room_created',
      parameters: {'room_id': roomId},
    );
  }

  /// Server confirmed the user joined a room session (join, random join, or re-join).
  static Future<void> logRoomJoined({required String roomId}) {
    return AnalyticsService.logEvent(
      name: 'room_joined',
      parameters: {'room_id': roomId},
    );
  }

  /// Play screen Start Match button tap (practice or multiplayer).
  static Future<void> logStartMatchTapped({required String gameId}) {
    return AnalyticsService.logEvent(
      name: 'start_match_tapped',
      parameters: {'game_id': gameId},
    );
  }

  static Future<void> logLobbyRandomJoinFailed({required String reason}) {
    final trimmed = reason.trim();
    return AnalyticsService.logEvent(
      name: 'lobby_random_join_failed',
      parameters: {
        'reason': trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed,
      },
    );
  }

  static Future<void> logDutchCalled({required String gameId}) {
    return AnalyticsService.logEvent(
      name: 'dutch_called',
      parameters: {'game_id': gameId},
    );
  }

  static Future<void> logAdmobRewardedEarned() {
    return AnalyticsService.logEvent(name: 'admob_rewarded_earned');
  }

  static Future<void> logAdmobRewardedClaimFailed({required String reason}) {
    final trimmed = reason.trim();
    return AnalyticsService.logEvent(
      name: 'admob_rewarded_claim_failed',
      parameters: {
        'reason': trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed,
      },
    );
  }

  static Future<void> logAdmobInterstitialShown() {
    return AnalyticsService.logEvent(name: 'admob_interstitial_shown');
  }

  /// Premium subscription canceled or lapsed.
  ///
  /// [reason]: `purchase_sheet` (store UI dismissed) or `lapsed` (server sync, no longer premium).
  static Future<void> logPremiumSubscriptionCanceled({
    required bool isIos,
    required String reason,
    String? productId,
  }) {
    return AnalyticsService.logEvent(
      name: isIos
          ? 'apple_premium_subscription_canceled'
          : 'play_premium_subscription_canceled',
      parameters: {
        'reason': reason,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
      },
    );
  }

  /// Logs once per [gameId] when a match ends with standings.
  static Future<void> maybeLogMatchCompleted({
    required String gameId,
    required Map<String, dynamic> gameState,
    required bool isCurrentUserWinner,
  }) {
    if (gameId.isEmpty || _matchCompletedLoggedGameIds.contains(gameId)) {
      return Future<void>.value();
    }
    _matchCompletedLoggedGameIds.add(gameId);

    final dutchState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final isPractice = gameId.startsWith('practice_room_');
    final isClearAndCollect = _resolveIsClearAndCollect(gameId, gameState, dutchState);

    return AnalyticsService.logEvent(
      name: 'match_completed',
      parameters: {
        'game_id': gameId,
        'result': isCurrentUserWinner ? 'win' : 'loss',
        'game_type': isClearAndCollect ? 'clear_and_collect' : 'classic',
        'source': _resolveMatchSource(gameId, dutchState),
        'match_type': isPractice ? 'practice' : 'multiplayer',
      },
    );
  }

  static bool _resolveIsClearAndCollect(
    String gameId,
    Map<String, dynamic> gameState,
    Map<String, dynamic> dutchState,
  ) {
    if (gameState['isClearAndCollect'] == true) {
      return true;
    }
    final gt = gameState['game_type']?.toString() ?? '';
    if (gt == 'clear_and_collect') {
      return true;
    }
    if (gameId.startsWith('practice_room_')) {
      final practiceSettings =
          dutchState['practiceSettings'] as Map<String, dynamic>?;
      return practiceSettings?['isClearAndCollect'] == true;
    }
    final rj = dutchState['randomJoinIsClearAndCollect'] as bool?;
    if (rj != null) {
      return rj;
    }
    final games = dutchState['games'] as Map<String, dynamic>? ?? {};
    final entry = games[gameId] as Map<String, dynamic>?;
    final entryGt = entry?['game_type']?.toString() ?? '';
    return entryGt == 'clear_and_collect';
  }

  static String _resolveMatchSource(String gameId, Map<String, dynamic> dutchState) {
    if (gameId.startsWith('practice_room_')) {
      return 'practice';
    }

    var source = dutchState['pending_start_match_source']?.toString() ?? '';
    if (source.isNotEmpty) {
      return source;
    }

    final games = dutchState['games'] as Map<String, dynamic>? ?? {};
    final entry = games[gameId] as Map<String, dynamic>?;
    if (entry?['is_random_join'] == true) {
      return 'random_join';
    }

    final topOwner = dutchState['isRoomOwner'] == true;
    final entryOwner = entry?['isRoomOwner'] == true;
    return (topOwner || entryOwner) ? 'create_room' : 'join_room';
  }
}
