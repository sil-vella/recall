import '../../../core/managers/state_manager.dart';
import '../../../utils/analytics_service.dart';

/// Dutch-specific Firebase (GA4) events. Product funnels only — not backend analytics.
abstract final class DutchFirebaseAnalytics {
  static final Set<String> _matchCompletedLoggedGameIds = <String>{};

  static void resetSession() {
    _matchCompletedLoggedGameIds.clear();
  }

  static Future<void> logLobbyRandomJoinStarted({
    required bool isClearAndCollect,
    required int gameLevel,
    String? specialEventId,
  }) {
    return AnalyticsService.logEvent(
      name: 'lobby_random_join_started',
      parameters: {
        'mode': isClearAndCollect ? 'clear_collect' : 'classic',
        'game_level': gameLevel,
        if (specialEventId != null && specialEventId.isNotEmpty)
          'special_event_id': specialEventId,
      },
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

  static Future<void> logLobbyCreateRoom({
    required String gameType,
    required int autoStart,
    int? gameLevel,
  }) {
    return AnalyticsService.logEvent(
      name: 'lobby_create_room',
      parameters: {
        'game_type': gameType,
        'auto_start': autoStart,
        if (gameLevel != null) 'game_level': gameLevel,
      },
    );
  }

  static Future<void> logLobbyJoinRoom({required String roomId}) {
    return AnalyticsService.logEvent(
      name: 'lobby_join_room',
      parameters: {'room_id': roomId},
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
