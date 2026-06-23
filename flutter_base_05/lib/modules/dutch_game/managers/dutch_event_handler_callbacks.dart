import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../utils/platform/shared_imports.dart';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../core/managers/module_manager.dart';
import '../../../core/managers/navigation_manager.dart';
import '../../../core/widgets/instant_message_modal.dart';
import '../../dutch_game/utils/dutch_game_helpers.dart';
import '../utils/game_ended_modal_pin.dart';
import '../backend_core/utils/dutch_rank_level_change_checker.dart';
import '../utils/game_instructions_provider.dart';
import '../../../modules/analytics_module/analytics_module.dart';
import '../screens/demo/demo_action_handler.dart';
import '../screens/game_play/utils/dutch_anim_runtime.dart';
import '../screens/game_play/utils/dutch_optimistic_anim.dart';
import '../screens/promotion/dutch_promotion_screen.dart';
import '../screens/promotion/dutch_win_celebration_screen.dart';
import '../screens/promotion/dutch_achievement_celebration_screen.dart';
import '../utils/dutch_achievement_catalog.dart';
import '../../audio_module/audio_module.dart';
import 'game_coordinator.dart';
import '../utils/dutch_firebase_analytics.dart';
import '../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';
/// Pile-trim receive trace (`pileFilterRx`); separate from [LOGGING_SWITCH] to avoid noisy WS logs.
const bool PILE_FILTER_LOGGING_SWITCH = false; // testing — revert to false

/// Dedicated event handlers for Dutch game events
/// Contains all the business logic for processing specific event types
class DutchEventHandlerCallbacks {
  /// Dev log summary for peek lists (all entries, not only [List.first]).
  static String peekListLogSummary(List<dynamic> cards) {
    final parts = <String>[];
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      if (c is Map<String, dynamic>) {
        parts.add(
          '[$i] ${c['cardId']}:${c['rank']}/${c['suit']}',
        );
      } else {
        parts.add('[$i] ?');
      }
    }
    return parts.isEmpty ? '(none)' : parts.join(' ');
  }

  /// Compact roster line for dev traces: `seatId:status(h=N), …`
  static String playerStatusesLogSummary(
    List<dynamic>? players, {
    int maxEntries = 8,
  }) {
    if (players == null || players.isEmpty) return '(none)';
    final parts = <String>[];
    for (var i = 0; i < players.length && i < maxEntries; i++) {
      final raw = players[i];
      if (raw is! Map) continue;
      final p = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final id = p['id']?.toString() ?? '?';
      final shortId = id.length > 14 ? '…${id.substring(id.length - 10)}' : id;
      final status = p['status']?.toString() ?? '?';
      final handLen = (p['hand'] as List?)?.length ?? 0;
      parts.add('$shortId:$status(h=$handLen)');
    }
    if (players.length > maxEntries) {
      parts.add('+${players.length - maxEntries} more');
    }
    return parts.isEmpty ? '(none)' : parts.join(', ');
  }

  /// SSOT roster from [dutch_game].games[gameId].gameData.game_state.players.
  static List<dynamic>? rosterFromDutchGame(String gameId) {
    if (gameId.isEmpty) return null;
    final dg =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dg['games'] as Map<String, dynamic>? ?? {};
    final game = games[gameId] as Map<String, dynamic>? ?? {};
    final gameData = game['gameData'] as Map<String, dynamic>? ?? {};
    final gs = gameData['game_state'] as Map<String, dynamic>? ?? {};
    return gs['players'] as List<dynamic>?;
  }

  static String dutchGameRosterLog(String gameId) =>
      playerStatusesLogSummary(rosterFromDutchGame(gameId));

  static final Map<String, int> _lastStateVersionByGameId = <String, int>{};
  static final Map<String, String> _lastEventSignatureByGameId = <String, String>{};
  static String? _cachedCurrentUserId;
  static DateTime? _cachedCurrentUserIdAt;
  static bool _isBatchingGamesMapUpdates = false;
  static Map<String, dynamic>? _batchedGamesMap;
  
  // Analytics module cache
  static AnalyticsModule? _analyticsModule;
  static String? _lastPromotionSignature;
  static String? _lastWinCelebrationSignature;
  static String? _dealBootstrapGameId;

  static const int _kDealSlotsPerPlayer = 4;

  // ========================================
  // HELPER METHODS TO REDUCE DUPLICATION
  // ========================================
  
  /// Get analytics module instance
  static AnalyticsModule? _getAnalyticsModule() {
    if (_analyticsModule == null) {
      try {
        final moduleManager = ModuleManager();
        _analyticsModule = moduleManager.getModuleByType<AnalyticsModule>();
      } catch (e) {
        
      }
    }
    return _analyticsModule;
  }
  
  /// Refresh Dutch user stats after a match and detect rank/level changes vs pre-refresh snapshot.
  /// When [afterModalGate] is provided, waits for that modal flow to finish before
  /// showing follow-up celebrations so ordering stays deterministic.
  static void _refreshUserStatsAfterGameEnd(
    String logContext, {
    Future<void>? afterModalGate,
  }) {
    final userStatsBefore = DutchGameHelpers.getUserDutchGameStats();
    final statsBefore = DutchRankLevelChangeChecker.snapshotRankLevelWins(userStatsBefore);
    final achievementIdsBefore = _achievementIdsFromUserStats(userStatsBefore);
    DutchGameHelpers.fetchAndUpdateUserDutchGameData().then((success) async {
      
      if (!success) return;
      if (afterModalGate != null) {
        await afterModalGate;
      }
      final statsAfter = DutchRankLevelChangeChecker.snapshotRankLevelWins(
        DutchGameHelpers.getUserDutchGameStats(),
      );
      final change = DutchRankLevelChangeChecker.analyze(
        statsBefore: statsBefore,
        statsAfter: statsAfter,
      );
      final afterStats = DutchGameHelpers.getUserDutchGameStats();
      final achievementIdsAfter = _achievementIdsFromUserStats(afterStats);
      final newly = achievementIdsAfter.difference(achievementIdsBefore);
      // Avoid treating long-unlocked badges as "new" when local state predates API field.
      final canTrustAchievementDiff =
          userStatsBefore != null && userStatsBefore.containsKey('achievements_unlocked_ids');
      if (canTrustAchievementDiff && newly.isNotEmpty) {
        await _showNewAchievementModals(newly, logContext);
      }
      if (change.hadBeforeSnapshot && change.anyStoredFieldChanged) {
        await _showPromotionNotification(change, logContext);
        
      }
    });
  }

  static Set<String> _achievementIdsFromUserStats(Map<String, dynamic>? stats) {
    if (stats == null) return {};
    final raw = stats['achievements_unlocked_ids'];
    if (raw is! List) return {};
    return raw.map((e) => e.toString()).toSet();
  }

  /// Fullscreen celebration(s), same stack style as [DutchWinCelebrationScreen].
  static Future<void> _showNewAchievementModals(
    Set<String> newlyEarned,
    String logContext,
  ) async {
    if (newlyEarned.isEmpty) return;
    await _pushAchievementCelebrationsSequential(newlyEarned, logContext);
  }

  static Future<void> _pushAchievementCelebrationsSequential(
    Set<String> newlyEarned,
    String logContext,
  ) async {
    for (final id in newlyEarned) {
      final ctx = NavigationManager().navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final title = DutchAchievementCatalog.displayTitle(id);
      final entry = DutchAchievementEntry.byId(id);
      final body = entry?.description ?? '';
      try {
        
        await Navigator.of(ctx, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => DutchAchievementCelebrationScreen(
              achievementId: id,
              achievementTitle: title,
              achievementDescription: body,
            ),
          ),
        );
      } catch (e) {
        
        final fallback = NavigationManager().navigatorKey.currentContext;
        if (fallback != null && fallback.mounted) {
          InstantMessageModal.showFrontendOnlyInstant(
            fallback,
            title: title,
            body: body,
            data: {'event': 'dutch_achievement', 'achievement_id': id},
          );
        }
      }
    }
  }

  static Future<void> _showPromotionNotification(
    DutchRankLevelChangeResult change,
    String logContext,
  ) async {
    final rankPromoted = change.storedRankTrend == StoredTrend.progression;
    final levelPromoted = change.storedLevelTrend == StoredTrend.progression;
    if (!rankPromoted && !levelPromoted) return;

    final signature = '${change.rankAfter}|${change.levelAfter}|${change.winsAfter}';
    if (_lastPromotionSignature == signature) return;
    _lastPromotionSignature = signature;

    final context = NavigationManager().navigatorKey.currentContext;
    if (context == null) {
      
      return;
    }

    await _pushPromotionScreens(
      context: context,
      change: change,
      levelPromoted: levelPromoted,
      rankPromoted: rankPromoted,
      logContext: logContext,
    );
  }

  /// Show a fullscreen win celebration for the current user once per game end.
  static Future<void> _showWinCelebrationIfNeeded({
    required String gameId,
    required bool isCurrentUserWinner,
    required String winnerMessages,
    required String logContext,
  }) async {
    if (!isCurrentUserWinner) return;
    final signature = '$gameId|$winnerMessages';
    if (_lastWinCelebrationSignature == signature) return;
    _lastWinCelebrationSignature = signature;

    final context = NavigationManager().navigatorKey.currentContext;
    if (context == null) {
      
      return;
    }

    // One frame after the game-ended modal is shown so standings layer exists under this route
    // (same idea as level-up then rank-up: dismiss top screen to reveal the one below).
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = NavigationManager().navigatorKey.currentContext;
      if (ctx == null) {
        
        if (!completer.isCompleted) completer.complete();
        return;
      }
      unawaited(() async {
        try {
          if (!ctx.mounted) return;
          
          await Navigator.of(ctx, rootNavigator: true).push<void>(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => DutchWinCelebrationScreen(
                winnerMessage: 'Winner(s): $winnerMessages',
              ),
            ),
          );
        } catch (e) {
          
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      }());
    });
    await completer.future;
  }

  /// Sequenced fullscreen promotion screens. Level-up shows first; once the
  /// player closes it, rank-up follows. Falls back to [InstantMessageModal] if
  /// pushing the fullscreen route fails so a promotion is never silently lost.
  static Future<void> _pushPromotionScreens({
    required BuildContext context,
    required DutchRankLevelChangeResult change,
    required bool levelPromoted,
    required bool rankPromoted,
    required String logContext,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);

    Future<void> push(DutchPromotionKind kind) async {
      try {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => DutchPromotionScreen(
              kind: kind,
              change: change,
            ),
          ),
        );
      } catch (e) {
        
        // Re-resolve a fresh context after the async gap; the original context
        // may no longer be mounted.
        final fallbackContext = NavigationManager().navigatorKey.currentContext;
        if (fallbackContext == null) return;
        _showPromotionFallbackModal(
          context: fallbackContext,
          change: change,
          levelPromoted: levelPromoted,
          rankPromoted: rankPromoted,
        );
      }
    }

    

    if (levelPromoted) {
      
      await push(DutchPromotionKind.levelUp);
    }
    if (rankPromoted) {
      
      await push(DutchPromotionKind.rankUp);
    }
  }

  /// Legacy promotion modal — kept as a safety net for environments where the
  /// fullscreen route can't be pushed (e.g. navigator unavailable mid-teardown).
  static void _showPromotionFallbackModal({
    required BuildContext context,
    required DutchRankLevelChangeResult change,
    required bool levelPromoted,
    required bool rankPromoted,
  }) {
    final lines = <String>[];
    if (levelPromoted) {
      lines.add('Level Up: ${change.levelBefore ?? '-'} -> ${change.levelAfter ?? '-'}');
    }
    if (rankPromoted) {
      lines.add('Rank Up: ${change.rankBefore ?? '-'} -> ${change.rankAfter ?? '-'}');
    }
    if (change.winsAfter != null) {
      lines.add('Wins: ${change.winsAfter}');
    }
    final title = rankPromoted ? 'Promotion Unlocked!' : 'Level Up!';
    final body = lines.join('\n');

    InstantMessageModal.showFrontendOnlyInstant(
      context,
      title: title,
      body: body,
      data: {
        'event': 'dutch_promotion',
        'rank_before': change.rankBefore,
        'rank_after': change.rankAfter,
        'level_before': change.levelBefore,
        'level_after': change.levelAfter,
        'wins_before': change.winsBefore,
        'wins_after': change.winsAfter,
      },
    );
  }

  /// Track game event
  static Future<void> _trackGameEvent(String eventType, Map<String, dynamic> eventData) async {
    try {
      final analyticsModule = _getAnalyticsModule();
      if (analyticsModule != null) {
        await analyticsModule.trackEvent(
          eventType: eventType,
          eventData: eventData,
        );
      }
    } catch (e) {
      // Silently fail - don't block game events if analytics fails
      
    }
  }

  static int? _extractStateVersion(Map<String, dynamic> data, Map<String, dynamic> gameState) {
    final rootVersion = data['state_version'];
    if (rootVersion is int) return rootVersion;
    if (rootVersion is num) return rootVersion.toInt();
    final gameVersion = gameState['state_version'];
    if (gameVersion is int) return gameVersion;
    if (gameVersion is num) return gameVersion.toInt();
    return null;
  }

  static String _buildEventSignature(
    String eventType,
    String gameId,
    int? stateVersion,
    Map<String, dynamic> gameState,
    List<dynamic>? turnEvents,
    Map<String, dynamic>? partialState,
    List<dynamic>? changedProperties,
  ) {
    if (stateVersion != null) {
      return '$eventType|$gameId|v$stateVersion';
    }
    final phase = gameState['phase']?.toString() ?? '';
    final players = gameState['players'] as List<dynamic>? ?? const [];
    final currentPlayer = gameState['currentPlayer']?.toString() ?? '';
    final turnCount = turnEvents?.length ?? 0;
    final changed = changedProperties?.join(',') ?? '';
    final partialKeys = partialState?.keys.toList() ?? <String>[];
    partialKeys.sort();
    final keysStr = partialKeys.join(',');
    return '$eventType|$gameId|$phase|$currentPlayer|${players.length}|$turnCount|$changed|$keysStr';
  }

  /// Practice/demo synthetic user id from dutch_game state (empty when not practice).
  static String getPracticeUserId() {
    final dutchGameState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final practiceUser = dutchGameState['practiceUser'] as Map<String, dynamic>?;
    if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
      return practiceUser['userId']?.toString().trim() ?? '';
    }
    return '';
  }

  /// True when [player] is the local user's seat row (multiplayer, practice, or demo).
  static bool matchesLocalPlayerSeat(
    dynamic player, {
    required String seatId,
    required String loginUserId,
    String? practiceUserId,
  }) {
    if (player is! Map) return false;
    final pid = player['id']?.toString().trim() ?? '';
    final pUid = player['userId']?.toString().trim() ??
        player['user_id']?.toString().trim() ??
        '';
    final sid = seatId.trim();
    if (sid.isNotEmpty && pid.isNotEmpty && pid == sid) return true;
    final login = loginUserId.trim();
    if (login.isNotEmpty) {
      if (pid == 'hum_$login') return true;
      final human = player['isHuman'] == true;
      if (human && pUid.isNotEmpty && pUid == login) return true;
    }
    final practice = (practiceUserId ?? getPracticeUserId()).trim();
    if (practice.isNotEmpty) {
      if (pid == 'practice_session_$practice') return true;
      if (pid == 'hum_$practice') return true;
      if (pUid.isNotEmpty && pUid == practice) return true;
    }
    return false;
  }

  /// Find the local user's player map in [players], or null if not seated.
  static Map<String, dynamic>? findLocalPlayerInRoster(
    List<dynamic> players, {
    String? seatId,
    String? loginUserId,
    String? practiceUserId,
  }) {
    final sid = seatId ?? getCurrentUserId();
    final login = loginUserId ?? getCurrentLoginUserId();
    final practice = practiceUserId ?? getPracticeUserId();
    for (final p in players) {
      if (matchesLocalPlayerSeat(
        p,
        seatId: sid,
        loginUserId: login,
        practiceUserId: practice,
      )) {
        return p is Map<String, dynamic> ? p : null;
      }
    }
    return null;
  }

  /// True if the local user appears on [players] by session/practice id or login user id.
  static bool _localUserOnPlayerList(
    List<dynamic> players,
    String sessionOrPracticeId,
    String loginUserId,
  ) {
    final practiceUserId = getPracticeUserId();
    for (final p in players) {
      if (matchesLocalPlayerSeat(
        p,
        seatId: sessionOrPracticeId,
        loginUserId: loginUserId,
        practiceUserId: practiceUserId,
      )) {
        return true;
      }
    }
    return false;
  }

  static bool _shouldDropDuplicateOrStaleEvent({
    required String eventType,
    required String gameId,
    required int? stateVersion,
    required String signature,
  }) {
    final lastVersion = _lastStateVersionByGameId[gameId];
    if (stateVersion != null && lastVersion != null && stateVersion <= lastVersion) {
      
      return true;
    }
    final lastSignature = _lastEventSignatureByGameId[gameId];
    if (lastSignature == signature) {
      
      return true;
    }
    if (stateVersion != null) {
      _lastStateVersionByGameId[gameId] = stateVersion;
    }
    _lastEventSignatureByGameId[gameId] = signature;
    return false;
  }

  /// Get current games map from state manager
  static Map<String, dynamic> _getCurrentGamesMap() {
    if (_isBatchingGamesMapUpdates && _batchedGamesMap != null) {
      return Map<String, dynamic>.from(_batchedGamesMap!);
    }
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  }

  static void _beginGamesMapBatch(Map<String, dynamic> seedGames) {
    _isBatchingGamesMapUpdates = true;
    _batchedGamesMap = Map<String, dynamic>.from(seedGames);
  }

  static void _endGamesMapBatch({required bool commit}) {
    final gamesToCommit = _batchedGamesMap;
    _isBatchingGamesMapUpdates = false;
    _batchedGamesMap = null;
    if (commit && gamesToCommit != null) {
      DutchGameHelpers.updateUIState({'games': gamesToCommit});
    }
  }

  /// Copies `special_event_id` from `gameData.game_state` to the games-map entry root when present.
  /// Play UI ([resolveDutchGamePlaySpecialEventId], [CardWidget], [GamePlayScreen]) checks both; keeping
  /// the root field in sync avoids false "vanilla" matches where user equipped cosmetics override event art.
  static void _denormalizeSpecialEventIdOnGameEntry(Map<String, dynamic> gameEntry) {
    String? pick() {
      final top = gameEntry['special_event_id']?.toString().trim();
      if (top != null && top.isNotEmpty) return top;
      final gdRaw = gameEntry['gameData'];
      if (gdRaw is! Map) return null;
      final gdMap = Map<String, dynamic>.from(gdRaw);
      final gsRaw = gdMap['game_state'];
      if (gsRaw is! Map) return null;
      final nested = Map<String, dynamic>.from(gsRaw)['special_event_id']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested;
      return null;
    }

    final id = pick();
    if (id != null && id.isNotEmpty) {
      gameEntry['special_event_id'] = id;
    } else {
      gameEntry.remove('special_event_id');
    }
  }
  
  /// Update a specific game in the games map and sync to global state
  static void _updateGameInMap(String gameId, Map<String, dynamic> updates) {
    final currentGames = _isBatchingGamesMapUpdates && _batchedGamesMap != null
        ? _batchedGamesMap!
        : _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // CRITICAL: Preserve gameData if updates don't include it
      // This prevents gameData from being lost or overwritten with empty/null values
      final mergedGame = {
        ...currentGame,
        ...updates,
      };
      
      // CRITICAL: If updates don't include gameData, preserve the existing one
      if (!updates.containsKey('gameData')) {
        mergedGame['gameData'] = currentGameData;
      } else {
        // If updates includes gameData, ensure it has game_id set
        final updatedGameData = updates['gameData'] as Map<String, dynamic>? ?? {};
        if (updatedGameData.isNotEmpty && (updatedGameData['game_id'] == null || updatedGameData['game_id'].toString().isEmpty)) {
          
          updatedGameData['game_id'] = gameId;
          mergedGame['gameData'] = updatedGameData;
        }
      }
      
      // CRITICAL: Validate that gameData still has game_id after merge
      final finalGameData = mergedGame['gameData'] as Map<String, dynamic>? ?? {};
      if (finalGameData.isEmpty || finalGameData['game_id'] == null || finalGameData['game_id'].toString().isEmpty) {
        
        // Don't update if gameData is invalid - this prevents corrupting the games map
        return;
      }

      _denormalizeSpecialEventIdOnGameEntry(mergedGame);
      
      currentGames[gameId] = mergedGame;
      
      if (_isBatchingGamesMapUpdates) {
        _batchedGamesMap = currentGames;
      } else {
        
        // Update global state
        DutchGameHelpers.updateUIState({
          'games': currentGames,
        });
      }
    } else {
      
    }
  }
  
  /// Update game data within a game's gameData structure
  static void _updateGameData(String gameId, Map<String, dynamic> dataUpdates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // Update the game data
      final updatedGameData = Map<String, dynamic>.from(currentGameData);
      updatedGameData.addAll(dataUpdates);
      
      // Update the game with new game data
      _updateGameInMap(gameId, {
        'gameData': updatedGameData,
      });
    }
  }
  
  /// Game-facing identity used to match [game_state.players].[id].
  ///
  /// - Practice: `practice_session_<userId>`
  /// - Multiplayer (authenticated): `hum_<websocket user_id>` — same stable seat as Dart backend
  /// - Fallback: websocket `session_id` / socket id / login `userId`
  static String getCurrentUserId() {
    final cachedUserId = _cachedCurrentUserId;
    final cachedAt = _cachedCurrentUserIdAt;
    if (cachedUserId != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt).inMilliseconds < 75) {
      return cachedUserId;
    }

    // First check for practice user data (practice mode)
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final practiceUser = dutchGameState['practiceUser'] as Map<String, dynamic>?;
    
    if (practiceUser != null && practiceUser['isPracticeUser'] == true) {
      final practiceUserId = practiceUser['userId']?.toString();
      if (practiceUserId != null && practiceUserId.isNotEmpty) {
        // In practice mode, player ID is the sessionId, not the userId
        // SessionId format: practice_session_<userId>
        final practiceSessionId = 'practice_session_$practiceUserId';

        if (LOGGING_SWITCH) {
          customlog(
            'LocalPlayerSeat: getCurrentUserId source=practice '
            'id=$practiceSessionId practiceUserId=$practiceUserId',
          );
        }
        _cachedCurrentUserId = practiceSessionId;
        _cachedCurrentUserIdAt = DateTime.now();
        return practiceSessionId;
      }
    }

    // Fall back to login state (multiplayer mode).
    final websocketState =
        StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};

    // Multiplayer seated human id (`hum_<auth user id>`) — aligns with Dart `canonicalMultiplayerHumanPlayerId`.
    final wsAuthMongoId = websocketState['user_id']?.toString().trim() ?? '';
    if (wsAuthMongoId.isNotEmpty) {
      final stableSeat = 'hum_$wsAuthMongoId';

      if (LOGGING_SWITCH) {
        customlog(
          'LocalPlayerSeat: getCurrentUserId source=hum_ws id=$stableSeat',
        );
      }
      _cachedCurrentUserId = stableSeat;
      _cachedCurrentUserIdAt = DateTime.now();
      return stableSeat;
    }

    // Unauthenticated guest / pre-auth: use session ids from websocket state
    // Check both camelCase and snake_case keys for compatibility
    final sessionData = websocketState['sessionData'] as Map<String, dynamic>?;
    final sessionId = sessionData?['session_id']?.toString() ?? 
                      sessionData?['sessionId']?.toString();
    final normalizedSessionId = sessionId?.trim();
    
    if (normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        normalizedSessionId.toLowerCase() != 'unknown') {

      if (LOGGING_SWITCH) {
        customlog(
          'LocalPlayerSeat: getCurrentUserId source=session id=$normalizedSessionId',
        );
      }
      _cachedCurrentUserId = normalizedSessionId;
      _cachedCurrentUserIdAt = DateTime.now();
      return normalizedSessionId;
    }
    
    // Try to get sessionId directly from WebSocketManager socket
    try {
      final wsManager = WebSocketManager.instance;
      final directSessionId = wsManager.socket?.id;
      
      final normalizedSocketId = directSessionId?.trim();
      if (normalizedSocketId != null &&
          normalizedSocketId.isNotEmpty &&
          normalizedSocketId.toLowerCase() != 'unknown') {

        if (LOGGING_SWITCH) {
          customlog(
            'LocalPlayerSeat: getCurrentUserId source=socket id=$normalizedSocketId',
          );
        }
        _cachedCurrentUserId = normalizedSocketId;
        _cachedCurrentUserIdAt = DateTime.now();
        return normalizedSocketId;
      }
    } catch (e) {
      // WebSocketManager might not be initialized, continue to fallback
      
    }
    
    // Last resort: use login userId (for backward compatibility)
    // Note: This may not match player IDs in multiplayer mode where player.id = sessionId
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final loginUserId = loginState['userId']?.toString() ?? '';

    if (LOGGING_SWITCH) {
      customlog(
        'LocalPlayerSeat: getCurrentUserId source=login_fallback id=$loginUserId',
      );
    }
    _cachedCurrentUserId = loginUserId;
    _cachedCurrentUserIdAt = DateTime.now();
    return loginUserId;
  }

  /// Get current logged-in user id (not session id).
  static String getCurrentLoginUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// WS `game_state_updated` often omits root `current_player_status`; derive from [gameState].
  static String deriveWireCurrentPlayerStatus(
    Map<String, dynamic> gameState, {
    String? wireStatus,
  }) {
    final ws = wireStatus?.trim();
    if (ws != null && ws.isNotEmpty && ws != 'unknown') {
      return ws;
    }
    final cp = gameState['currentPlayer'];
    if (cp is Map<String, dynamic>) {
      final st = cp['status']?.toString().trim();
      if (st != null && st.isNotEmpty) {
        return st;
      }
      final id = cp['id']?.toString();
      if (id != null && id.isNotEmpty) {
        final players = gameState['players'] as List<dynamic>? ?? [];
        for (final p in players) {
          if (p is Map<String, dynamic> && p['id']?.toString() == id) {
            final pst = p['status']?.toString().trim();
            if (pst != null && pst.isNotEmpty) {
              return pst;
            }
            break;
          }
        }
      }
    }
    final phase = gameState['phase']?.toString().trim();
    if (phase != null && phase.isNotEmpty) {
      return phase;
    }
    return ws ?? 'unknown';
  }
  
  /// Check if current user is room owner for a specific game
  static bool _isCurrentUserRoomOwner(Map<String, dynamic> gameData) {
    final ownerId = gameData['owner_id']?.toString();
    if (ownerId == null || ownerId.isEmpty) {
      return false;
    }
    
    // Current identity can be either session id (player id) or logged-in user id.
    final currentUserId = getCurrentUserId();
    final currentLoginUserId = getCurrentLoginUserId();
    
    // Direct match (works for multiplayer where owner_id is sessionId)
    if (ownerId == currentUserId) {
      return true;
    }

    // Common backend payloads use owner_id as login user id.
    if (currentLoginUserId.isNotEmpty && ownerId == currentLoginUserId) {
      return true;
    }
    
    // In practice mode, owner_id is userId but currentUserId is sessionId
    // Check if currentUserId is a practice sessionId and extract userId for comparison
    if (currentUserId.startsWith('practice_session_')) {
      final extractedUserId = currentUserId.replaceFirst('practice_session_', '');
      if (ownerId == extractedUserId) {
        
        return true;
      }
    }
    
    // Also check if ownerId is a practice sessionId and currentUserId/currentLoginUserId is the userId
    if (ownerId.startsWith('practice_session_')) {
      final extractedOwnerUserId = ownerId.replaceFirst('practice_session_', '');
      // Check if currentUserId matches the extracted userId
      // This handles the case where owner_id might be set to sessionId
      if (currentUserId == extractedOwnerUserId ||
          currentUserId == ownerId ||
          (currentLoginUserId.isNotEmpty && currentLoginUserId == extractedOwnerUserId)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Add a game to the games map with standard structure
  static void _addGameToMap(String gameId, Map<String, dynamic> gameData, {String? gameStatus}) {
    final currentGames = _isBatchingGamesMapUpdates && _batchedGamesMap != null
        ? _batchedGamesMap!
        : _getCurrentGamesMap();
    
    // CRITICAL: Validate gameData has required fields before adding
    if (gameData.isEmpty) {
      
      return;
    }
    
    // CRITICAL: Ensure game_id is set in gameData (required for joinedGamesSlice computation)
    if (gameData['game_id'] == null || gameData['game_id'].toString().isEmpty) {
      
      gameData['game_id'] = gameId; // Ensure game_id is set
    }
    
    // Determine game status (phase is now managed in main state only)
    final status = gameStatus ?? gameData['game_state']?['status']?.toString() ?? 'inactive';
    
    // Preserve existing joinedAt and isRoomOwner when already set (e.g. creator before first game_state_updated)
    final existingGame = currentGames[gameId] as Map<String, dynamic>?;
    final joinedAt = existingGame?['joinedAt'] ?? DateTime.now().toIso8601String();
    final derivedIsOwner = _isCurrentUserRoomOwner(gameData);
    final isRoomOwner = (existingGame?['isRoomOwner'] == true) || derivedIsOwner;
    
    // Match-type state for Start button and logic
    final isPractice = gameId.startsWith('practice_room_');
    final Map<String, dynamic>? multiplayerType;
    if (isPractice) {
      multiplayerType = null;
    } else {
      final gameType = gameData['game_type']?.toString() ?? 'classic';
      final isRandom = gameData['is_random_join'] == true;
      multiplayerType = {
        'type': gameType == 'tournament' ? 'tournament' : 'classic',
        'isRandom': isRandom,
      };
    }
    
    // Add/update the game in the games map
    final gameEntry = <String, dynamic>{
      'gameData': gameData,  // Single source of truth
      'gameStatus': status,
      'isRoomOwner': isRoomOwner,
      'isPractice': isPractice,
      'multiplayerType': multiplayerType,
      'isInGame': true,
      'joinedAt': joinedAt,
    };
    _denormalizeSpecialEventIdOnGameEntry(gameEntry);
    currentGames[gameId] = gameEntry;
    
    
    
    if (_isBatchingGamesMapUpdates) {
      _batchedGamesMap = currentGames;
    } else {
      // Update global state
      DutchGameHelpers.updateUIState({
        'games': currentGames,
      });
    }
  }
  
  /// Update main game state (non-game-specific fields)
  static void _updateMainGameState(Map<String, dynamic> updates) {
    DutchGameHelpers.updateUIState(updates);
    // Removed lastUpdated - causes unnecessary state updates
  }

  /// Trigger instructions if showInstructions is enabled and state has changed
  /// 
  /// Checks if instructions should be shown based on game phase and player status,
  /// and updates the instructions state accordingly.
  static void _triggerInstructionsIfNeeded({
    required String gameId,
    required Map<String, dynamic> gameState,
    String? playerStatus,
    bool isMyTurn = false,
  }) {
    try {
      
      
      // Skip automatic instruction triggering if a demo action is active
      // Demo logic will handle showing instructions manually
      if (DemoActionHandler.isDemoActionActive()) {
        
        return;
      }
      
      // Get showInstructions flag from game state
      final showInstructions = gameState['showInstructions'] as bool? ?? false;
      
      
      if (!showInstructions) {
        // Instructions disabled, ensure they're hidden
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
        if (currentInstructions['isVisible'] == true) {
          // Hide instructions if they were previously visible
          StateManager().updateModuleState('dutch_game', {
            'instructions': {
              'isVisible': false,
              'title': '',
              'content': '',
              'key': '',
              'dontShowAgain': currentInstructions['dontShowAgain'] ?? {},
            },
          });
        }
        return;
      }

      final currentStateForDeal = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      if (currentStateForDeal['dealAnimActive'] == true) {
        return;
      }

      // Get current game phase
      final rawPhase = gameState['phase']?.toString();
      final gamePhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');

      // Check if game hasn't started yet (waiting phase) - show initial instructions
      // Also check practice settings if showInstructions is not in game state yet
      if (gamePhase == 'waiting') {
        // If showInstructions is not in game state, check practice settings
        bool effectiveShowInstructions = showInstructions;
        if (!showInstructions) {
          final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final practiceSettings = currentState['practiceSettings'] as Map<String, dynamic>?;
          final practiceShowInstructions = practiceSettings?['showInstructions'] as bool? ?? false;
          if (practiceShowInstructions) {
            
            effectiveShowInstructions = true;
          }
        }
        
        
        if (!effectiveShowInstructions) {
          
          return;
        }
        
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final instructionsData = currentState['instructions'] as Map<String, dynamic>? ?? {};
        final dontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        
        
        // Show initial instructions if not already marked as "don't show again"
        if (dontShowAgain[GameInstructionsProvider.KEY_INITIAL] != true) {
          // Check if initial instructions are already showing
          final instructionsData = currentState['instructions'] as Map<String, dynamic>? ?? {};
          final currentlyVisible = instructionsData['isVisible'] == true;
          final currentKey = instructionsData['key']?.toString();
          
          // Only show if not already showing
          if (!currentlyVisible || currentKey != GameInstructionsProvider.KEY_INITIAL) {
            final initialInstructions = GameInstructionsProvider.getInitialInstructions();
            StateManager().updateModuleState('dutch_game', {
              'instructions': {
                'isVisible': true,
                'title': initialInstructions['title'] ?? 'Welcome to Dutch!',
                'content': initialInstructions['content'] ?? '',
                'key': initialInstructions['key'] ?? GameInstructionsProvider.KEY_INITIAL,
                'hasDemonstration': initialInstructions['hasDemonstration'] ?? false,
                'dontShowAgain': dontShowAgain,
              },
            });
            
          } else {
            
          }
        } else {
          
        }
        return;
      }

      // Get current user's player status (not the current player's status)
      // We need the current user's status to show instructions for their actions
      String? currentUserPlayerStatus = playerStatus;
      if (currentUserPlayerStatus == null) {
        // Get from current user's player in game state
        final players = gameState['players'] as List<dynamic>? ?? [];
        final currentUserId = getCurrentUserId();
        try {
          final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
            (player) => player['id'] == currentUserId,
          );
          currentUserPlayerStatus = myPlayer['status']?.toString();
          
        } catch (e) {
          
          // Player not found, continue without status
        }
      }

      // Get previous instructions state to check if we should show new instructions
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final previousPhase = currentState['gamePhase']?.toString();
      
      // Get previous current user's player status (from myHand slice or playerStatus in main state)
      // Note: currentPlayerStatus in main state is the current player's status, not current user's
      final myHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      final previousUserPlayerStatus = myHand['playerStatus']?.toString() ?? 
                                       currentState['playerStatus']?.toString();
      
      final dontShowAgain = Map<String, bool>.from(
        (currentState['instructions'] as Map<String, dynamic>?)?['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );

      // Track same rank window triggers for collection card instruction
      int sameRankTriggerCount = currentState['sameRankTriggerCount'] as int? ?? 0;
      
      
      // Check if this is a same rank window phase
      if (gamePhase == 'same_rank_window') {
        // Increment counter ONLY when transitioning INTO same_rank_window (not when already in it)
        // This happens when previousPhase was NOT same_rank_window
        if (previousPhase != 'same_rank_window') {
          sameRankTriggerCount++;
          StateManager().updateModuleState('dutch_game', {
            'sameRankTriggerCount': sameRankTriggerCount,
          });
          
        } else {
          
        }
        
        // On 5th trigger, show collection card instruction instead of same rank window
        if (sameRankTriggerCount >= 5) {
          
          // Check if collection card instruction is already dismissed
          if (dontShowAgain[GameInstructionsProvider.KEY_COLLECTION_CARD] != true) {
            
            
            // Construct collection card instruction directly (no playerStatus 'collection_card' exists)
            final collectionInstructions = {
              'key': GameInstructionsProvider.KEY_COLLECTION_CARD,
              'title': 'Collection Cards',
              'hasDemonstration': true,
              'content': '''📚 **Collection Cards**

When anyone has played a card with the **same rank** as your **collection card** (the face-up card in your hand), you can collect it!

**How it works:**
• Your collection card is the face-up card in your hand
• If the last played card matches your collection card's rank, you can collect it
• The collected card is placed on top of your collection card (slightly offset to show stacking)
• Collected cards help you build your collection in attempt to collect all 4 cards of your rank and win the game.

**Example:** If your collection card is a 7 of Hearts and a 7 of Diamonds has just played, you can collect it!''',
            };
            
            final instructionKey = collectionInstructions['key'] ?? '';
            final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
            final currentlyVisible = currentInstructions['isVisible'] == true;
            final currentKey = currentInstructions['key']?.toString();
            
            
            
            // Only update if not already showing this instruction
            if (!currentlyVisible || currentKey != instructionKey) {
              StateManager().updateModuleState('dutch_game', {
                'instructions': {
                  'isVisible': true,
                  'title': collectionInstructions['title'] ?? 'Collection Cards',
                  'content': collectionInstructions['content'] ?? '',
                  'key': instructionKey,
                  'hasDemonstration': collectionInstructions['hasDemonstration'] ?? false,
                  'dontShowAgain': dontShowAgain,
                },
              });
              
              return; // Exit early, don't show same rank window instruction
            } else {
              
            }
          } else {
            
          }
        } else {
          
        }
      }

      

      // Check if instructions should be shown
      final shouldShow = GameInstructionsProvider.shouldShowInstructions(
        showInstructions: showInstructions,
        gamePhase: gamePhase,
        playerStatus: currentUserPlayerStatus,
        isMyTurn: isMyTurn,
        previousPhase: previousPhase,
        previousStatus: previousUserPlayerStatus,
        dontShowAgain: dontShowAgain,
      );
      
      

      if (shouldShow) {
        // Get instructions content
        final instructions = GameInstructionsProvider.getInstructions(
          gamePhase: gamePhase,
          playerStatus: currentUserPlayerStatus,
          isMyTurn: isMyTurn,
        );

        if (instructions != null) {
          final instructionKey = instructions['key'] ?? '';
          
          // Check if this instruction is already showing
          final currentInstructions = currentState['instructions'] as Map<String, dynamic>? ?? {};
          final currentlyVisible = currentInstructions['isVisible'] == true;
          final currentKey = currentInstructions['key']?.toString();
          
          // Only update if:
          // 1. No instruction is currently showing, OR
          // 2. The instruction key has changed (different instruction type)
          if (!currentlyVisible || currentKey != instructionKey) {
            // Update instructions state
            StateManager().updateModuleState('dutch_game', {
              'instructions': {
                'isVisible': true,
                'title': instructions['title'] ?? 'Game Instructions',
                'content': instructions['content'] ?? '',
                'key': instructionKey,
                'hasDemonstration': instructions['hasDemonstration'] ?? false,
                'dontShowAgain': dontShowAgain,
              },
            });
            
            
          } else {
            
          }
        }
      } else {
        // Don't show instructions, but don't hide if they're already showing
        // (let user close them manually)
      }
    } catch (e) {
      
    }
  }

  /// Check if demo action has completed and trigger endDemoAction if needed
  /// 
  /// Checks if:
  /// - Game is a practice game
  /// - showInstructions is enabled
  /// - A demo action is currently active
  /// - Player status has transitioned to indicate action completion
  static void _checkDemoActionCompletion({
    required String gameId,
    required Map<String, dynamic> gameState,
    required String? currentUserPlayerStatus,
  }) {
    try {
      // Get current state once
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      
      // Check if practice game
      final gameType = dutchGameState['gameType']?.toString() ?? '';
      if (gameType != 'practice') {
        if (LOGGING_SWITCH) {
          customlog('demoCompletion: skip gameType=$gameType (not practice)');
        }
        return; // Not a practice game, skip demo check
      }

      // Check if showInstructions is enabled
      bool showInstructions = gameState['showInstructions'] as bool? ?? false;
      if (!showInstructions) {
        // Fallback to practice settings
        final practiceSettings = dutchGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool? ?? false;
      }

      if (!showInstructions) {
        if (LOGGING_SWITCH) {
          customlog('demoCompletion: skip showInstructions=false');
        }
        return; // Instructions not enabled, skip demo check
      }

      // Check if demo action is active
      if (!DemoActionHandler.isDemoActionActive()) {
        if (LOGGING_SWITCH) {
          customlog('demoCompletion: skip demo action not active');
        }
        return; // No active demo action
      }

      final activeDemoAction = DemoActionHandler.getActiveDemoActionType();
      if (activeDemoAction == null) {
        return; // No active demo action type
      }

      // Get previous player status from state
      var previousPlayerStatus = dutchGameState['previousPlayerStatus']?.toString();

      if (activeDemoAction == 'initial_peek' &&
          (previousPlayerStatus == null || previousPlayerStatus.isEmpty) &&
          currentUserPlayerStatus == 'waiting') {
        previousPlayerStatus = 'initial_peek';
      }

      // Check if action is completed based on status transition (pass gameState for collect_rank demo)
      final demoHandler = DemoActionHandler.instance;
      var isCompleted = demoHandler.isActionCompleted(
        activeDemoAction,
        previousPlayerStatus,
        currentUserPlayerStatus,
        gameState: gameState,
      );

      if (isCompleted &&
          activeDemoAction == 'initial_peek' &&
          !DemoActionHandler.initialPeekCardsVisibleInState()) {
        if (LOGGING_SWITCH) {
          customlog(
            'demoCompletion: defer game_state_updated initial_peek '
            'peek cards not visible yet',
          );
        }
        isCompleted = false;
      }

      if (LOGGING_SWITCH) {
        customlog(
          'demoCompletion: game_state_updated action=$activeDemoAction '
          'prev=$previousPlayerStatus current=$currentUserPlayerStatus '
          'completed=$isCompleted gameId=$gameId '
          'peekLen=${(dutchGameState['myCardsToPeek'] as List?)?.length ?? 0}',
        );
      }

      if (isCompleted) {
        
        
        // Clear previous status
        StateManager().updateModuleState('dutch_game', {
          'previousPlayerStatus': null,
        });

        // Show after-action instruction for all demo actions
        
        demoHandler.showAfterActionInstruction(activeDemoAction);
      } else {
        // Update previous status for next check
        if (currentUserPlayerStatus != null) {
          StateManager().updateModuleState('dutch_game', {
            'previousPlayerStatus': currentUserPlayerStatus,
          });
        }
      }
    } catch (e) {
      
    }
  }

  /// Sync widget-specific states from game state
  /// Extracts current user's player data and updates widget state slices
  /// This ensures computed slices (like myHand.cards) stay in sync with game_state
  /// [turnEvents] Optional turn_events list to include in games map update for widget slices
  static void _syncWidgetStatesFromGameState(
    String gameId,
    Map<String, dynamic> gameState, {
    List<dynamic>? turnEvents,
    Map<String, dynamic>? mainStatePatch,
    /// Players list from before this `game_state_updated` / merge — used to detect kick-out (auto-leave).
    List<dynamic>? previousPlayers,
  }) {
    try {
      // 🎯 CRITICAL: Verify game exists in games map before updating
      // This prevents stale state updates when user has left the game
      final currentGames = _getCurrentGamesMap();
      if (!currentGames.containsKey(gameId)) {
        
        return;
      }
      
      // Get current user ID (checks practice user data first, then login state)
      // In multiplayer mode, this should return sessionId (which is the player ID)
      final currentUserId = getCurrentUserId();
      
      
      
      if (currentUserId.isEmpty) {
        
        return;
      }
      
      // Find player in gameState['players'] matching current user ID
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      
      
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final loginUserId = loginState['userId']?.toString() ?? '';
      final practiceUserId = getPracticeUserId();

      Map<String, dynamic>? myPlayer = findLocalPlayerInRoster(
        players,
        seatId: currentUserId,
        loginUserId: loginUserId,
        practiceUserId: practiceUserId,
      );
      if (LOGGING_SWITCH &&
          (gameId.startsWith('practice_room_') || practiceUserId.isNotEmpty)) {
        if (myPlayer != null) {
          final handLen = (myPlayer['hand'] as List<dynamic>? ?? []).length;
          customlog(
            'LocalPlayerSeat: syncWidget gameId=$gameId matchedId=${myPlayer['id']} '
            'handLen=$handLen seat=$currentUserId practice=$practiceUserId',
          );
        } else {
          final rosterBrief = players.map((p) {
            if (p is! Map) return '?';
            return '${p['id']}(u:${p['userId'] ?? p['user_id']})';
          }).join(',');
          customlog(
            'LocalPlayerSeat: syncWidget gameId=$gameId myPlayer=null '
            'seat=$currentUserId practice=$practiceUserId roster=[$rosterBrief]',
          );
        }
      }
      if (myPlayer != null) {
        
      } else {
        bool _matchesCurrentUser(dynamic p) => matchesLocalPlayerSeat(
              p,
              seatId: currentUserId,
              loginUserId: loginUserId,
              practiceUserId: practiceUserId,
            );
        final wasInGame = (previousPlayers ?? []).any(
          _matchesCurrentUser,
        );
        final kickState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final alreadyShownFor = kickState['kickedModalShownFor']?.toString() ?? '';
        final phase = gameState['phase']?.toString() ?? '';
        final currentRoomId = kickState['currentRoomId']?.toString() ?? '';
        final currentGameId = kickState['currentGameId']?.toString() ?? '';
        final isOnCurrentMatch = gameId == currentGameId || gameId == currentRoomId;
        if ((wasInGame || isOnCurrentMatch) &&
            alreadyShownFor != gameId &&
            (phase != 'waiting_for_players' || wasInGame) &&
            isOnCurrentMatch &&
            gameId.startsWith('room_')) {
          
          StateManager().updateModuleState('dutch_game', {'kickedModalShownFor': gameId});
          _addSessionMessage(
            level: 'warning',
            title: 'Removed from Game',
            message: 'You were removed for too many missed actions.',
            showModal: true,
            data: <String, dynamic>{'game_id': gameId, 'kicked': true},
          );
          return;
        }
        // kickedModalShownFor may be set from a false positive while we are still on the roster.
        // Do not permanently skip widget sync in that case (survivor would look "frozen").
        if (alreadyShownFor == gameId && players.any(_matchesCurrentUser)) {
          StateManager().updateModuleState('dutch_game', {'kickedModalShownFor': ''});
          myPlayer = findLocalPlayerInRoster(
            players,
            seatId: currentUserId,
            loginUserId: loginUserId,
            practiceUserId: practiceUserId,
          );
        }
        if (myPlayer == null) {
          
          return;
        }
      }

      // Extract widget-specific data from player
      final hand = myPlayer['hand'] as List<dynamic>? ?? [];
      final cardsToPeek = myPlayer['cardsToPeek'] as List<dynamic>? ?? [];
      final drawnCard = myPlayer['drawnCard'] as Map<String, dynamic>?;
      final status = myPlayer['status']?.toString() ?? 'unknown';

      // Check if cardsToPeek contains full card data (for protection mechanism)
      final hasFullCardData = cardsToPeek.isNotEmpty && cardsToPeek.any((card) {
        if (card is Map<String, dynamic>) {
          final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
          final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
          return hasSuit || hasRank;
        }
        return false;
      });
      
      
      final gamePhaseForPeek =
          (gameState['phase'] ?? gameState['gamePhase'])?.toString();
      if (cardsToPeek.isNotEmpty &&
          hasFullCardData &&
          DutchGameHelpers.statusAllowsPeekReveal(
            status,
            gamePhase: gamePhaseForPeek,
          )) {
        // Store protected data only during initial_peek (brief UI persistence)
        if (mainStatePatch != null) {
          mainStatePatch['protectedCardsToPeek'] = cardsToPeek;
        } else {
          _updateMainGameState({
            'protectedCardsToPeek': cardsToPeek,
          });
        }
      } else if (cardsToPeek.isEmpty ||
          !DutchGameHelpers.statusAllowsPeekReveal(
            status,
            gamePhase: gamePhaseForPeek,
          )) {
        // CRITICAL: Clear protectedCardsToPeek when cardsToPeek is empty
        // This ensures the widget doesn't show stale protected data
        
        if (mainStatePatch != null) {
          mainStatePatch['protectedCardsToPeek'] = null;
        } else {
          _updateMainGameState({
            'protectedCardsToPeek': null, // Clear protected data
          });
        }
      }
      
      // Extract score (can be 'points' or 'score' field)
      final score = myPlayer['score'] as int? ?? myPlayer['points'] as int? ?? 0;

      // Determine if it's current player's turn
      // Check both gameState['currentPlayer'] and player['isCurrentPlayer']
      final currentPlayerRaw = gameState['currentPlayer'];
      bool isCurrentPlayer = false;
      if (currentPlayerRaw is Map<String, dynamic>) {
        isCurrentPlayer = currentPlayerRaw['id']?.toString() == currentUserId;
      } else if (currentPlayerRaw is String) {
        isCurrentPlayer = currentPlayerRaw == currentUserId;
      } else {
        isCurrentPlayer = myPlayer['isCurrentPlayer'] == true;
      }
      
      // Update games map with widget-specific data
      // Include turn_events if provided (needed for widget slice animations)
      final widgetUpdates = <String, dynamic>{
        'myHandCards': hand,
        'myDrawnCard': drawnCard,
        'isMyTurn': isCurrentPlayer,
      };
      
      // Include turn_events in games map update so widget slices can access them
      if (turnEvents != null) {
        widgetUpdates['turn_events'] = turnEvents;
      }
      
      // Do not downgrade full peek data to id-only from game_state.players
      final existingPeekForMerge = mainStatePatch != null
          ? mainStatePatch['myCardsToPeek'] as List<dynamic>?
          : (StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ??
                  {})['myCardsToPeek'] as List<dynamic>?;
      var myCardsToPeekForPatch = DutchGameHelpers.preferFullPeekCards(
        cardsToPeek,
        existingPeekForMerge,
      );
      if (!DutchGameHelpers.statusAllowsPeekReveal(
        status,
        gamePhase: gamePhaseForPeek,
      )) {
        myCardsToPeekForPatch = [];
      } else if (status == 'queen_peek' &&
          !DutchGameHelpers.peekListHasFullData(myCardsToPeekForPatch)) {
        if (existingPeekForMerge != null &&
            DutchGameHelpers.peekListHasFullData(existingPeekForMerge)) {
          myCardsToPeekForPatch = existingPeekForMerge;
        } else {
          myCardsToPeekForPatch = [];
        }
      }

      // Update main game state with player information
      if (mainStatePatch != null) {
        mainStatePatch.addAll({
          'playerStatus': status,
          'myScore': score,
          'isMyTurn': isCurrentPlayer,
          'myDrawnCard': drawnCard,
          'myCardsToPeek': myCardsToPeekForPatch,
        });
      } else {
        _updateMainGameState({
          'playerStatus': status,
          'myScore': score,
          'isMyTurn': isCurrentPlayer,
          'myDrawnCard': drawnCard,
          'myCardsToPeek': myCardsToPeekForPatch,
        });
      }
      
      // Apply widget updates to games map
      _updateGameInMap(gameId, widgetUpdates);
      
      
    } catch (e) {
      
    }
  }

  /// True when [leftSessionId] from `leave_room_success` refers to this WebSocket connection
  /// (not multiplayer seat id from [getCurrentUserId], which is `hum_*`).
  static bool _leaveRoomSuccessSessionIsThisClient(String leftSessionId) {
    final trimmed = leftSessionId.trim();
    if (trimmed.isEmpty) return false;
    try {
      final sock = WebSocketManager.instance.socket;
      if (sock != null) {
        final sid = sock.id.trim();
        if (sid.isNotEmpty && sid == trimmed) return true;
      }
    } catch (_) {}
    final ws = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final sd = ws['sessionData'];
    if (sd is Map) {
      final fromState =
          sd['session_id']?.toString().trim() ?? sd['sessionId']?.toString().trim() ?? '';
      if (fromState.isNotEmpty && fromState == trimmed) return true;
    }
    return false;
  }

  /// Server removed this client from the room for inactivity (`leave_room_success` with `reason`).
  static void handleKickedForInactivityLeaveSuccess(Map<String, dynamic> data) {
    // Payload is for the WebSocket session that left; seat id (`hum_*`) must not be used here.
    final leftSessionId = data['session_id']?.toString() ?? '';
    final wsSessionMatchesKick =
        leftSessionId.isNotEmpty && _leaveRoomSuccessSessionIsThisClient(leftSessionId);
    if (leftSessionId.isEmpty || !wsSessionMatchesKick) {
      
      return;
    }
    final roomId = data['room_id']?.toString() ?? '';
    if (roomId.isEmpty || !roomId.startsWith('room_')) return;
    final dg = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dg['currentGameId']?.toString() ?? '';
    final currentRoomId = dg['currentRoomId']?.toString() ?? '';
    if (roomId != currentGameId && roomId != currentRoomId) {
      
      return;
    }
    
    StateManager().updateModuleState('dutch_game', {'kickedModalShownFor': roomId});
    _addSessionMessage(
      level: 'warning',
      title: 'Removed from Game',
      message: 'You were removed for too many missed actions.',
      showModal: true,
      data: <String, dynamic>{'game_id': roomId, 'kicked': true},
    );
  }
  
  /// Add a session message to the message board
  /// [showModal] - If true, displays the modal. Only set to true for game end messages.
  /// [isCurrentUserWinner] - When showModal is true for game end, store in messages so UI can show trophy/coin stream in standings.
  static void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data, bool showModal = false, bool? isCurrentUserWinner}) {
    
    final entry = {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Get current session messages
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentMessages = currentState['messages'] as Map<String, dynamic>? ?? {};
    final sessionMessages = List<Map<String, dynamic>>.from(currentMessages['session'] as List<dynamic>? ?? []);
    
    // Add new message
    sessionMessages.add(entry);
    if (sessionMessages.length > 200) sessionMessages.removeAt(0);
    
    // Update state - preserve existing modal fields and only update when showModal is true
    final messagesUpdate = {
      'session': sessionMessages,
      'rooms': currentMessages['rooms'] ?? {},
      // Preserve existing modal fields (isVisible, title, content, type, etc.) if they exist
      if (currentMessages.containsKey('isVisible')) 'isVisible': currentMessages['isVisible'],
      if (currentMessages.containsKey('title')) 'title': currentMessages['title'],
      if (currentMessages.containsKey('content')) 'content': currentMessages['content'],
      if (currentMessages.containsKey('type')) 'type': currentMessages['type'],
      if (currentMessages.containsKey('showCloseButton')) 'showCloseButton': currentMessages['showCloseButton'],
      if (currentMessages.containsKey('autoClose')) 'autoClose': currentMessages['autoClose'],
      if (currentMessages.containsKey('autoCloseDelay')) 'autoCloseDelay': currentMessages['autoCloseDelay'],
    };
    
    // Only show modal for game end messages (when showModal is true)
    // For non-game-end messages, preserve existing modal state
    if (showModal) {
      messagesUpdate['isVisible'] = true;
      messagesUpdate['title'] = title ?? '';
      messagesUpdate['content'] = message ?? '';
      messagesUpdate['type'] = (level ?? 'info');
      messagesUpdate['showCloseButton'] = true;
      messagesUpdate['autoClose'] = false;
      messagesUpdate['autoCloseDelay'] = 3000;
      if (isCurrentUserWinner != null) {
        messagesUpdate['isCurrentUserWinner'] = isCurrentUserWinner;
      }
      
    } else {
      // Don't modify modal fields for non-game-end messages - preserve existing state
      
    }
    
    // If showing modal, also ensure gamePhase is set to game_ended in the same update
    if (showModal) {
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGamePhase = currentState['gamePhase']?.toString() ?? '';
      final uiPatch = <String, dynamic>{
        'messages': messagesUpdate,
        'endGameModalOpen': true,
      };
      if (currentGamePhase != 'game_ended') {
        uiPatch['gamePhase'] = 'game_ended';
      }
      DutchGameHelpers.updateUIState(uiPatch);
    } else {
      DutchGameHelpers.updateUIState({
        'messages': messagesUpdate,
      });
    }
    
  }

  // ========================================
  // PUBLIC EVENT HANDLERS
  // ========================================

  /// Handle dutch_new_player_joined event
  static void handleDutchNewPlayerJoined(Map<String, dynamic> data) {
    final roomId = data['room_id']?.toString() ?? '';
    final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};

    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(roomId)) {
      
      return;
    }

    // Update the game data with the new game state using helper method
    _updateGameData(roomId, {
      'game_state': gameState,
    });
    
    // Add session message about new player
    _addSessionMessage(
      level: 'info',
      title: 'Player Joined',
      message: '${joinedPlayer['name']} joined the game',
      data: joinedPlayer,
    );
  }

  /// Handle dutch_joined_games event
  static void handleDutchJoinedGames(Map<String, dynamic> data) {
    // final sessionId = data['session_id']?.toString() ?? '';
    final games = data['games'] as List<dynamic>? ?? [];
    final totalGames = data['total_games'] ?? 0;
    
    // Update the games map with the joined games data using helper methods
    for (final gameData in games) {
      final gameId = gameData['game_id']?.toString() ?? '';
      if (gameId.isNotEmpty) {
        // Add/update the game in the games map using helper method
        _addGameToMap(gameId, gameData);
      }
    }
    
    // Set currentGameId to the first joined game (if any)
    String? currentGameId;
    if (games.isNotEmpty) {
      currentGameId = games.first['game_id']?.toString();
    }
    
    // Update dutch game state with joined games information using helper method
    _updateMainGameState({
      'joinedGames': games.cast<Map<String, dynamic>>(),
      'totalJoinedGames': totalGames,
      // Removed joinedGamesTimestamp - causes unnecessary state updates
      if (currentGameId != null) 'currentGameId': currentGameId,
    });
    
    // Add session message about joined games
    _addSessionMessage(
      level: 'info',
      title: 'Games Updated',
      message: 'You are now in $totalGames game${totalGames != 1 ? 's' : ''}',
      data: {'total_games': totalGames, 'games': games},
    );
  }

  /// Handle game_started event
  static void handleGameStarted(Map<String, dynamic> data) {
    
    final gameId = data['game_id']?.toString() ?? '';
    final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final startedBy = data['started_by']?.toString() ?? '';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      
      return;
    }
    
    // Extract player data
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Handle currentPlayer - it might be a Map (player object) or String (player ID) or null
    Map<String, dynamic>? currentPlayer;
    final currentPlayerRaw = gameState['currentPlayer'];
    if (currentPlayerRaw is Map<String, dynamic>) {
      currentPlayer = currentPlayerRaw;
    } else if (currentPlayerRaw is String && currentPlayerRaw.isNotEmpty) {
      // If currentPlayer is a string (player ID), find the player object in the players list
      currentPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentPlayerRaw,
        orElse: () => <String, dynamic>{},
      );
      if (currentPlayer.isEmpty) {
        currentPlayer = null;
      }
    } else {
      currentPlayer = null;
    }
    
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    
    // Find the current user's player data
    final seatId = getCurrentUserId();
    final loginUserId = getCurrentLoginUserId();
    final practiceUserId = getPracticeUserId();
    final myPlayer = findLocalPlayerInRoster(
      players,
      seatId: seatId,
      loginUserId: loginUserId,
      practiceUserId: practiceUserId,
    );
    
    // Extract opponent players (excluding current user seat)
    final opponents = players.where((p) {
      return !matchesLocalPlayerSeat(
        p,
        seatId: seatId,
        loginUserId: loginUserId,
        practiceUserId: practiceUserId,
      );
    }).toList();
    
    // Update the game data with the new game state using helper method
    _updateGameData(gameId, {
      'game_state': gameState,
    });
    
    // Update the game with game started information using helper method
    _updateGameInMap(gameId, {
      // Note: gamePhase is now managed in main state only - derived from main state in gameInfo slice
      'gameStatus': gameState['status'] ?? 'active',
      'isGameActive': true,
      'isRoomOwner': startedBy == seatId || startedBy == loginUserId,
      
      // Update game-specific fields for widget slices
      'drawPileCount': DutchGameHelpers.drawPileCountFromGameState(gameState),
      'discardPile': discardPile,
      'opponentPlayers': opponents.cast<Map<String, dynamic>>(),
      'currentPlayerIndex': currentPlayer != null ? players.indexOf(currentPlayer) : -1,
      'myHandCards': myPlayer?['hand'] ?? [],
      'selectedCardIndex': -1,
    });
    
    // 🎯 CRITICAL: Sync widget states from game state to ensure all widget slices are up to date
    // Extract turn_events from game state if available (for animations)
    final turnEvents = gameState['turn_events'] as List<dynamic>?;
    _syncWidgetStatesFromGameState(gameId, gameState, turnEvents: turnEvents);
    
    // Get fresh games map after widget sync (it may have been updated)
    final currentGamesAfterSync = _getCurrentGamesMap();
    
    final prevPhase =
        (StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ??
                {})['gamePhase']
            ?.toString();
    var uiPhase = DutchGameHelpers.effectiveUiGamePhase(
      gameState,
      fallbackPhase: prevPhase?.isNotEmpty == true ? prevPhase : 'playing',
    );
    if (uiPhase != 'same_rank_window' &&
        DutchGameHelpers.anyPlayerInSameRankWindow(gameState)) {
      uiPhase = 'same_rank_window';
    }
    final stateAfterSync = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final kickedModalShownFor = stateAfterSync['kickedModalShownFor']?.toString() ?? '';
    final stillOnRosterAfterKickFlag =
        _localUserOnPlayerList(players, seatId, loginUserId);
    if (kickedModalShownFor == gameId && !stillOnRosterAfterKickFlag) {
      // Keep kicked-user modal visible: `_addSessionMessage(showModal:true)` sets `gamePhase=game_ended`,
      // but this normal update path could otherwise overwrite it back to `playing`.
      uiPhase = 'game_ended';
      
    }
    
    final dutchBeforeGameStarted = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final prevCurrentGameIdForKick = dutchBeforeGameStarted['currentGameId']?.toString() ?? '';

    // Update main state with gamePhase to ensure status chip and game info widget update correctly
    _updateMainGameState({
      'currentGameId': gameId,  // Ensure currentGameId is set
      'games': currentGamesAfterSync, // Updated games map with widget data synced
      'gamePhase': uiPhase,  // ✅ Update gamePhase so status chip and game info widget reflect correct phase
      'isGameActive': uiPhase != 'game_ended', // Set to false when game has ended
      if (prevCurrentGameIdForKick.isNotEmpty && prevCurrentGameIdForKick != gameId) 'kickedModalShownFor': '',
    });
    
    // Trigger instructions if showInstructions is enabled
    // Use getCurrentUserId() to handle practice mode correctly (sessionId vs userId)
    final currentUserIdForInstructions = getCurrentUserId();
    final isMyTurn = currentPlayer?['id']?.toString() == currentUserIdForInstructions;
    
    // Get current user's player status (not the current player's status)
    String? currentUserPlayerStatus;
    try {
      final myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (player) => player['id'] == currentUserIdForInstructions,
      );
      currentUserPlayerStatus = myPlayer['status']?.toString();
    } catch (e) {
      // Player not found, will be handled in _triggerInstructionsIfNeeded
      currentUserPlayerStatus = null;
    }
    
    _triggerInstructionsIfNeeded(
      gameId: gameId,
      gameState: gameState,
      playerStatus: currentUserPlayerStatus, // Pass current user's player status
      isMyTurn: isMyTurn,
    );
    
    // Add session message about game started
    _addSessionMessage(
      level: 'success',
      title: 'Game Started',
      message: 'Game $gameId has started!',
      data: {
        'game_id': gameId,
        'started_by': startedBy,
        'game_state': gameState,
      },
    );
  }

  /// Handle turn_started event
  static void handleTurnStarted(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    // final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    final playerId = data['player_id']?.toString() ?? '';
    final playerStatus = data['player_status']?.toString() ?? 'unknown';
    final turnTimeout = data['turn_timeout'] as int? ?? 30;
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      
      return;
    }
    
    // Find the current user's player data
    final seatId = getCurrentUserId();
    final loginUserId = getCurrentLoginUserId();
    final isMyTurn = playerId == seatId ||
        (loginUserId.isNotEmpty && playerId == 'hum_$loginUserId');
    
    if (isMyTurn) {
      
      // Update UI state to show it's the current user's turn using helper method
      _updateMainGameState({
        'isMyTurn': true,
        'turnTimeout': turnTimeout,
        // Removed turnStartTime - causes unnecessary state updates
        'playerStatus': playerStatus,
        'statusBar': {
          'currentPhase': 'my_turn',
          'turnTimer': turnTimeout,
          // Removed turnStartTime - causes unnecessary state updates
          'playerStatus': playerStatus,
        },
      });

      if (playerStatus == 'drawing_card' ||
          playerStatus == 'queen_peek' ||
          playerStatus == 'jack_swap') {
        try {
          ModuleManager().getModuleByType<AudioModule>()?.playSound('timer');
        } catch (_) {}
        if (LOGGING_SWITCH) {
          customlog(
            'handleTurnStarted: timer sound gameId=$gameId playerId=$playerId status=$playerStatus',
          );
        }
      }
      
      // Add session message about turn started
      _addSessionMessage(
        level: 'info',
        title: 'Your Turn',
        message: 'It\'s your turn! You have $turnTimeout seconds to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'turn_timeout': turnTimeout,
          'is_my_turn': true,
        },
      );
    } else {
      
      // Update UI state to show it's another player's turn using helper method
      _updateMainGameState({
        'isMyTurn': false,
        'statusBar': {
          'currentPhase': 'opponent_turn',
          'currentPlayer': playerId,
        },
      });
      
      // Add session message about opponent's turn
      _addSessionMessage(
        level: 'info',
        title: 'Opponent\'s Turn',
        message: 'It\'s $playerId\'s turn to play.',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'is_my_turn': false,
        },
      );
    }
  }

  /// Fast path: patch peek cards before full [game_state_updated] merge.
  static void handleInitialPeekRevealed(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    if (gameId.isEmpty) return;

    final currentState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    final currentRoomId = currentState['currentRoomId']?.toString() ?? '';
    if (gameId != currentGameId && gameId != currentRoomId) {
      return;
    }

    final playerStatus = currentState['playerStatus']?.toString() ?? '';
    final gamePhase = currentState['gamePhase']?.toString();
    if (!DutchGameHelpers.statusAllowsPeekReveal(
      playerStatus,
      gamePhase: gamePhase,
    )) {
      return;
    }

    final incoming = data['cards_to_peek'] as List<dynamic>?;
    if (incoming == null || incoming.isEmpty) return;

    final previousPeek = currentState['myCardsToPeek'] as List<dynamic>?;
    final merged = DutchGameHelpers.preferFullPeekCards(incoming, previousPeek);
    if (!DutchGameHelpers.peekListHasFullData(merged)) return;

    if (LOGGING_SWITCH) {
      customlog(
        'handleInitialPeekRevealed: gameId=$gameId len=${merged.length} '
        'cards=${peekListLogSummary(merged)}',
      );
    }

    _updateMainGameState({
      'myCardsToPeek': merged,
      if (gamePhase == 'initial_peek' &&
          DutchGameHelpers.peekListHasFullData(merged))
        'protectedCardsToPeek': merged,
    });

    if (merged.length >= 2 &&
        DemoActionHandler.isDemoActionActive() &&
        DemoActionHandler.getActiveDemoActionType() == 'initial_peek') {
      if (LOGGING_SWITCH) {
        customlog(
          'handleInitialPeekRevealed: retry demo completion after 2-card patch',
        );
      }
      DemoActionHandler.instance.retryDemoCompletionAfterPeekReveal();
    }
  }

  /// After successful `resume_room`; snapshot follows via `game_state_updated`.
  static void handleRejoinSuccess(Map<String, dynamic> data) {
    final roomId = data['room_id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    final currentState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    if (currentGameId.isNotEmpty && roomId != currentGameId) {
      return;
    }

    if (LOGGING_SWITCH) {
      customlog(
        'handleRejoinSuccess: roomId=$roomId '
        'gamePlayerId=${data['game_player_id']}',
      );
    }
    DutchGameHelpers.clearMatchRecoveryResumePending();
  }

  /// Server broadcast when a seat enters disconnect grace (timers paused server-side).
  static void handlePlayerDisconnected(Map<String, dynamic> data) {
    final roomId = data['room_id']?.toString() ?? '';
    final gamePlayerId = data['game_player_id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    if (LOGGING_SWITCH) {
      customlog(
        'handlePlayerDisconnected: roomId=$roomId '
        'gamePlayerId=$gamePlayerId graceSeconds=${data['grace_seconds']}',
      );
    }
  }

  /// Handle [game_animation] from Dart backend (draw/play hints; arrives before matching state).
  static void handleGameAnimation(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final actionType = data['action_type']?.toString() ?? '';
    final source = data['source']?.toString() ?? '';
    final cards = data['cards'];
    final n = cards is List ? cards.length : 0;
    final ctx = data['context'];
    String ctxBrief = '';
    if (ctx is Map) {
      final keys = ctx.keys.map((k) => k.toString()).join(',');
      ctxBrief = keys.isEmpty ? '' : ' context_keys=$keys';
    }
    String handIdxBrief = '';
    if (cards is List) {
      final parts = <String>[];
      for (final e in cards) {
        if (e is Map) {
          final hi = e['hand_index'];
          if (hi != null) parts.add(hi.toString());
        }
      }
      if (parts.isNotEmpty) {
        handIdxBrief = ' hand_index=[${parts.join(',')}]';
      }
    }
    
    if (LOGGING_SWITCH &&
        (actionType == 'jack_swap' ||
            actionType == 'queen_peek' ||
            actionType == 'initial_peek' ||
            actionType == 'play_card' ||
            actionType == 'same_rank_play' ||
            actionType == 'draw' ||
            actionType == 'reposition' ||
            actionType == 'collect_from_discard')) {
      customlog(
        'handleGameAnimation: gameId=$gameId action=$actionType cards=$n$handIdxBrief$ctxBrief source=$source',
      );
    }
    if (DutchOptimisticAnim.shouldSkipServerDuplicate(data)) return;
    if (LOGGING_SWITCH &&
        (actionType == 'play_card' ||
            actionType == 'same_rank_play' ||
            actionType == 'draw')) {
      customlog(
        'handleGameAnimation: enqueue server action=$actionType gameId=$gameId$handIdxBrief',
      );
    }
    DutchAnimRuntime.instance.enqueueGameAnimation(
      _withPriorDiscardTopForPlayAnim(Map<String, dynamic>.from(data)),
    );
  }

  /// Attach [DutchAnimRuntime.priorDiscardTopKey] for server play hints when state already advanced.
  static Map<String, dynamic> _withPriorDiscardTopForPlayAnim(Map<String, dynamic> data) {
    final action = data['action_type']?.toString() ?? '';
    if (!DutchAnimRuntime.isPlayToDiscardAction(action)) return data;
    final existing = data[DutchAnimRuntime.priorDiscardTopKey];
    if (existing is Map && existing.isNotEmpty) return data;
    final prior = _inferPriorDiscardTopForPlayAnim(data);
    if (prior == null) return data;
    final copy = Map<String, dynamic>.from(data);
    copy[DutchAnimRuntime.priorDiscardTopKey] = prior;
    return copy;
  }

  static Map<String, dynamic>? _inferPriorDiscardTopForPlayAnim(Map<String, dynamic> data) {
    String? playedCardId;
    final cards = data['cards'] as List? ?? [];
    for (final e in cards) {
      if (e is! Map) continue;
      final card = e['card'];
      if (card is Map) {
        playedCardId = card['cardId']?.toString();
        if (playedCardId != null && playedCardId.isNotEmpty) break;
      }
    }

    final state = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    var pile = state['discardPile'] as List? ?? [];
    if (pile.isEmpty) {
      final gameId = state['currentGameId']?.toString() ?? data['game_id']?.toString() ?? '';
      final games = state['games'] as Map? ?? {};
      final game = games[gameId] as Map? ?? {};
      final gs = game['gameData']?['game_state'] as Map? ?? {};
      pile = gs['discardPile'] as List? ?? [];
    }
    if (pile.isEmpty) return null;

    final top = pile.last;
    if (top is! Map) return null;
    final topId = top['cardId']?.toString() ?? '';

    if (playedCardId != null &&
        playedCardId.isNotEmpty &&
        topId == playedCardId &&
        pile.length >= 2) {
      final prior = pile[pile.length - 2];
      if (prior is Map) return Map<String, dynamic>.from(prior);
      return null;
    }
    return Map<String, dynamic>.from(top);
  }

  static bool _playersHaveDealableCards(List<dynamic> players) {
    for (final raw in players) {
      if (raw is! Map<String, dynamic>) continue;
      final hand = raw['hand'] as List<dynamic>? ?? [];
      if (hand.isNotEmpty) return true;
    }
    return false;
  }

  /// True after [tryRunInitialDealBootstrap] enqueued flights for [gameId].
  static bool isDealBootstrapCompleteFor(String gameId) =>
      gameId.isNotEmpty && _dealBootstrapGameId == gameId;

  static void _scheduleInitialDealBootstrap(String gameId) {
    if (_dealBootstrapGameId == gameId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryRunInitialDealBootstrap(gameId);
    });
  }

  /// Enqueue initial-deal flights once layout + hand data are ready (idempotent per game).
  static void tryRunInitialDealBootstrap(String gameId) {
    if (_dealBootstrapGameId == gameId) return;
    final state = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    if (state['dealAnimActive'] != true) {
      if (LOGGING_SWITCH) {
        customlog('dealBootstrap: skip gameId=$gameId dealAnimActive=false');
      }
      return;
    }
    if (state['currentGameId']?.toString() != gameId) {
      if (LOGGING_SWITCH) {
        customlog(
          'dealBootstrap: skip gameId=$gameId currentGameId=${state['currentGameId']}',
        );
      }
      return;
    }
    final games = state['games'] as Map<String, dynamic>? ?? {};
    final entry = games[gameId] as Map<String, dynamic>?;
    final gameData = entry?['gameData'] as Map<String, dynamic>? ?? {};
    final gs = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final players = gs['players'] as List<dynamic>? ?? [];
    if (!_playersHaveDealableCards(players)) {
      if (LOGGING_SWITCH) {
        customlog('dealBootstrap: wait gameId=$gameId hands empty in games map');
      }
      return;
    }
    _dealBootstrapGameId = gameId;
    final n = _bootstrapInitialDealAnimation(players);
    if (LOGGING_SWITCH) {
      customlog(
        'dealBootstrap: enqueued gameId=$gameId flights=$n '
        'queueLen=${DutchAnimRuntime.instance.queueLength}',
      );
    }
  }

  static int _bootstrapInitialDealAnimation(List<dynamic> players) {
    final allCards = <Map<String, dynamic>>[];
    for (final raw in players) {
      if (raw is! Map<String, dynamic>) continue;
      final ownerId = raw['id']?.toString() ?? '';
      if (ownerId.isEmpty) continue;
      final hand = raw['hand'] as List<dynamic>? ?? [];
      for (int hi = 0; hi < _kDealSlotsPerPlayer; hi++) {
        Map<String, dynamic> cardPayload = <String, dynamic>{};
        if (hi < hand.length && hand[hi] is Map) {
          cardPayload = Map<String, dynamic>.from(hand[hi] as Map);
        }
        allCards.add({
          'owner_id': ownerId,
          'hand_index': hi,
          'card': cardPayload,
        });
      }
    }
    if (allCards.isEmpty) return 0;
    DutchAnimRuntime.instance.enqueueGameAnimation({
      'action_type': 'deal_batch',
      'source': 'deck',
      'cards': allCards,
      'context': {'is_initial_deal': true},
    });
    return allCards.length;
  }

  /// Handle game_state_updated event
  static void handleGameStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    
    // 🎯 CRITICAL (WS → Practice): When in practice mode, ignore WebSocket game_state_updated
    // so late WS events cannot overwrite practice state or block Start Match.
    final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final practiceUser = dutchState['practiceUser'];
    if (practiceUser != null && gameId.startsWith('room_')) {
      
      return;
    }
    var gameState = data['game_state'] as Map<String, dynamic>? ?? {};
    if (data['winners'] != null) {
      gameState = Map<String, dynamic>.from(gameState);
      gameState['winners'] = data['winners'];
    }
    final ownerId = data['owner_id']?.toString(); // Extract owner_id from main payload
    final turnEvents = data['turn_events'] as List<dynamic>? ?? []; // Extract turn_events for animations
    final turnFeedRaw = data['turn_feed'] as List<dynamic>? ?? [];
    final turnFeed = turnFeedRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (LOGGING_SWITCH && turnFeed.isNotEmpty) {
      for (final e in turnFeed) {
        customlog(
          'handleGameStateUpdated: turn_feed gameId=$gameId '
          'feed_id=${e['feed_id']} action=${e['action_type']} '
          'acting=${e['acting_player_id']} hand_index=${e['hand_index']} '
          'hand_indices=${e['hand_indices']} swap_slots=${e['swap_slots']} '
          'play_ordinal=${e['play_ordinal']}',
        );
      }
    }
    final stateVersion = _extractStateVersion(data, gameState);
    final signature = _buildEventSignature(
      'game_state_updated',
      gameId,
      stateVersion,
      gameState,
      turnEvents,
      null,
      null,
    );
    if (_shouldDropDuplicateOrStaleEvent(
      eventType: 'game_state_updated',
      gameId: gameId,
      stateVersion: stateVersion,
      signature: signature,
    )) {
      
      return;
    }
    final myCardsToPeekFromEvent = data['myCardsToPeek'] as List<dynamic>?; // Extract root-level myCardsToPeek if present
    if (LOGGING_SWITCH && myCardsToPeekFromEvent != null) {
      if (myCardsToPeekFromEvent.isEmpty) {
        customlog('handleGameStateUpdated: myCardsToPeekFromEvent cleared (empty)');
      } else {
        customlog(
          'handleGameStateUpdated: myCardsToPeekFromEvent len=${myCardsToPeekFromEvent.length} '
          'cards=${peekListLogSummary(myCardsToPeekFromEvent)} '
          'wireStatus=${data['current_player_status']}',
        );
      }
    }
    
    // 🔍 DEBUG: Check drawnCard data in received game_state
    final players = gameState['players'] as List<dynamic>? ?? [];
    final currentUserId = getCurrentUserId();
    
    for (final player in players) {
      if (player is Map<String, dynamic>) {
        final playerId = player['id']?.toString() ?? 'unknown';
        final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
        if (drawnCard != null) {
          final rank = drawnCard['rank']?.toString() ?? 'null';
          final suit = drawnCard['suit']?.toString() ?? 'null';
          final isIdOnly = rank == '?' && suit == '?';
          final isCurrentUser = playerId == currentUserId;
          
        }
      }
    }
    
    // 🔍 DEBUG: Log the extracted values
    
    final roundNumber = data['round_number'] as int? ?? 1;
    final currentPlayer = data['current_player'];
    final currentPlayerStatus = deriveWireCurrentPlayerStatus(
      gameState,
      wireStatus: data['current_player_status']?.toString(),
    );
    final roundStatus = data['round_status']?.toString() ?? 'active';
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Extract pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = DutchGameHelpers.drawPileCountFromGameState(gameState);
    final discardPileCount = DutchGameHelpers.discardPileCountFromGameState(gameState);
    if (PILE_FILTER_LOGGING_SWITCH &&
        (drawPileCount > drawPile.length || discardPileCount > discardPile.length)) {
      customlog(
        'pileFilterRx gameId=$gameId drawCount=$drawPileCount wireDraw=${drawPile.length} '
        'discardCount=$discardPileCount wireDiscard=${discardPile.length} '
        'stateVersion=$stateVersion',
      );
    }

    // Extract players list (used for game map update, widget sync handled separately)
    // Note: players is already defined above for debug logging
    
    // Check if game exists in games map, if not add it
    final currentGames = _getCurrentGamesMap();
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    final currentRoomId = currentState['currentRoomId']?.toString() ?? '';
    final isOnCurrentMatch = gameId == currentGameId || gameId == currentRoomId;
    final kickedAlreadyShownFor = currentState['kickedModalShownFor']?.toString() ?? '';
    final loginStateForKick = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final loginUserIdForKick = loginStateForKick['userId']?.toString() ?? '';
    bool matchesCurrentUserForKick(dynamic p) {
      if (p is! Map<String, dynamic>) return false;
      final pid = p['id']?.toString() ?? '';
      final pUserId = p['userId']?.toString() ?? p['user_id']?.toString() ?? '';
      return pid == currentUserId || (loginUserIdForKick.isNotEmpty && pUserId == loginUserIdForKick);
    }
    List<dynamic>? prevPlayersFromMapKick;
    if (currentGames.containsKey(gameId)) {
      final entryKick = currentGames[gameId] as Map<String, dynamic>?;
      final gdKick = entryKick?['gameData'] as Map<String, dynamic>?;
      final gsKick = gdKick?['game_state'] as Map<String, dynamic>?;
      prevPlayersFromMapKick = gsKick?['players'] as List<dynamic>?;
    }
    final wasPreviouslyOnRosterKick =
        (prevPlayersFromMapKick ?? []).any(matchesCurrentUserForKick);
    
    // 🎯 CRITICAL: If games map is empty but currentGameId is set, this might be a stale event
    // from a game that was just cleared. Only accept events for the current game or if currentGameId is empty.
    if (currentGames.isEmpty && currentGameId.isNotEmpty && gameId != currentGameId) {
      
      return; // Ignore stale events from games that were just cleared
    }
    
    // 🎯 CRITICAL: After clear we have games empty and currentGameId empty. A stale game_state_updated
    // from a room we just left would re-add that room. Only ignore if this gameId was recently left.
    if (currentGames.isEmpty && currentGameId.isEmpty && DutchGameHelpers.wasGameRecentlyLeft(gameId)) {
      
      return;
    }
    _beginGamesMapBatch(currentGames);
    final consolidatedMainStatePatch = <String, dynamic>{};
    /// Captured before overwriting `gameData.game_state` (for kicked-player modal detection).
    List<dynamic>? previousPlayersForWidgetSync;
    // Fallback kick detection directly in this handler (independent of widget-sync ordering).
    final userStillInPlayers = players.any(matchesCurrentUserForKick);
    if (userStillInPlayers && kickedAlreadyShownFor == gameId) {
      StateManager().updateModuleState('dutch_game', {'kickedModalShownFor': ''});
    }
    final phaseForKick = gameState['phase']?.toString() ?? '';
    final phaseAllowsKickFallback =
        phaseForKick != 'waiting_for_players' || wasPreviouslyOnRosterKick;
    if (isOnCurrentMatch &&
        gameId.startsWith('room_') &&
        kickedAlreadyShownFor != gameId &&
        phaseAllowsKickFallback &&
        !userStillInPlayers) {
      
      StateManager().updateModuleState('dutch_game', {'kickedModalShownFor': gameId});
      _addSessionMessage(
        level: 'warning',
        title: 'Removed from Game',
        message: 'You were removed for too many missed actions.',
        showModal: true,
        data: <String, dynamic>{'game_id': gameId, 'kicked': true},
      );
    }

    final wasNewGame = !currentGames.containsKey(gameId);
    String previousRawPhase = '';
    if (currentGames.containsKey(gameId)) {
      final prevEntry = currentGames[gameId] as Map<String, dynamic>?;
      final prevGd = prevEntry?['gameData'] as Map<String, dynamic>?;
      final prevGs = prevGd?['game_state'] as Map<String, dynamic>?;
      previousRawPhase = prevGs?['phase']?.toString() ?? '';
    }
    if (wasNewGame) {
      _dealBootstrapGameId = null;
      DutchAnimRuntime.instance.reset();
      // 🎯 CRITICAL: Only one game should exist in the games map at a time
      // Remove all other games when adding a new game
      if (currentGames.isNotEmpty) {
        
        currentGames.clear(); // Remove all existing games
      }
      // Add the game to the games map with the complete game state.
      // Include owner_id, game_type, is_random_join so client can set isRoomOwner and multiplayerType.
      final base = {
        'game_id': gameId,
        'game_state': gameState,
      };
      if (ownerId != null) {
        base['owner_id'] = ownerId;
      }
      final gameType = data['game_type']?.toString();
      if (gameType != null && gameType.isNotEmpty) {
        base['game_type'] = gameType;
      }
      final gameLevel = data['game_level'] as int?;
      if (gameLevel != null) {
        base['game_level'] = gameLevel;
      }
      if (data['is_random_join'] == true || DutchGameHelpers.isRandomJoinInProgress) {
        base['is_random_join'] = true;
      }
      _addGameToMap(gameId, base);
      
      
      // 🎯 CRITICAL: Immediately update the newly added game with additional information
      // This ensures the game has all the data it needs before widget sync
      final currentGamesAfterAdd = _getCurrentGamesMap();
      if (currentGamesAfterAdd.containsKey(gameId)) {
        final updateData = {
          'drawPileCount': drawPileCount,
          'discardPileCount': discardPileCount,
          'discardPile': discardPile,
          'players': players,  // Include all players data
          'turn_events': turnEvents, // Include turn_events for widget slices
        };
        _updateGameInMap(gameId, updateData);
      }
      
      // Keep the games map in batch and apply once in the final consolidated state patch.
      DutchGameHelpers.clearRecentlyLeftGameId(gameId);
    } else {
      // 🎯 CRITICAL: Verify game still exists in games map before updating
      // This prevents stale state updates when user has left the game
      final currentGamesForCheck = _getCurrentGamesMap();
      if (!currentGamesForCheck.containsKey(gameId)) {
        
        _endGamesMapBatch(commit: false);
        return;
      }
      
      // 🎯 CRITICAL: Only one game should exist in the games map at a time
      // If this game is not the currentGameId, remove it and all other games
      final currentStateForCheck = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameIdForCheck = currentStateForCheck['currentGameId']?.toString() ?? '';
      
      if (currentGameIdForCheck.isNotEmpty && currentGameIdForCheck != gameId) {
        // This is a stale game - remove it and keep only the current game
        
        final gamesToUpdate = _getCurrentGamesMap();
        gamesToUpdate.remove(gameId);
        // If the current game is still in the map, keep only that one
        if (gamesToUpdate.containsKey(currentGameIdForCheck)) {
          final currentGameData = gamesToUpdate[currentGameIdForCheck];
          gamesToUpdate.clear();
          gamesToUpdate[currentGameIdForCheck] = currentGameData;
        } else {
          gamesToUpdate.clear();
        }
        DutchGameHelpers.updateUIState({
          'games': gamesToUpdate,
        });
        _endGamesMapBatch(commit: false);
        return; // Don't update stale games
      }
      
      // Update existing game's game_state
      
      final mapBeforeStateUpdate = _getCurrentGamesMap();
      final prevEntryKick = mapBeforeStateUpdate[gameId] as Map<String, dynamic>?;
      final prevGdKick = prevEntryKick?['gameData'] as Map<String, dynamic>?;
      final prevGsKick = prevGdKick?['game_state'] as Map<String, dynamic>?;
      previousPlayersForWidgetSync = prevGsKick?['players'] as List<dynamic>?;

      _updateGameData(gameId, {
        'game_state': gameState,
      });
      // Dart backend now sends `is_random_join` on every game_state_updated; merge so game end modal can hide Play Again.
      if (data['is_random_join'] == true) {
        _updateGameData(gameId, {'is_random_join': true});
        final gt = (currentGamesForCheck[gameId] as Map<String, dynamic>?)?['gameData'] as Map<String, dynamic>?;
        final gameTypeStr = gt?['game_type']?.toString() ?? 'classic';
        _updateGameInMap(gameId, {
          'multiplayerType': {
            'type': gameTypeStr == 'tournament' ? 'tournament' : 'classic',
            'isRandom': true,
          },
        });
      }
      
      // Update owner_id in gameData and at top level, recalculate isRoomOwner
      if (ownerId != null) {
        final currentUserId = getCurrentUserId();
        final gameDataForOwnerCheck = {'owner_id': ownerId};
        final isOwner = _isCurrentUserRoomOwner(gameDataForOwnerCheck);
        
        _updateGameData(gameId, {'owner_id': ownerId});  // So gameData has owner_id for slices
        _updateGameInMap(gameId, {
          'owner_id': ownerId,
          'isRoomOwner': isOwner,
        });
      } else {
        
        // Preserve main state's isRoomOwner when ownerId is missing
        final currentMain = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final prevIsOwner = currentMain['isRoomOwner'] as bool? ?? false;
        consolidatedMainStatePatch['isRoomOwner'] = prevIsOwner;
      }
      
      // Set game_type, game_level and multiplayerType on existing entry when event provides them
      // (e.g. room_joined created entry first, then game_state_updated arrives)
      final gameType = data['game_type']?.toString();
      final gameLevel = data['game_level'] as int?;
      if (gameType != null && gameType.isNotEmpty) {
        final updateData = <String, dynamic>{'game_type': gameType};
        if (gameLevel != null) updateData['game_level'] = gameLevel;
        _updateGameData(gameId, updateData);
        final existingGame = currentGamesForCheck[gameId] as Map<String, dynamic>? ?? {};
        final existingMultiplayerType =
            existingGame['multiplayerType'] as Map<String, dynamic>? ?? {};
        final existingGameData =
            existingGame['gameData'] as Map<String, dynamic>? ?? {};
        final existingRandom =
            existingMultiplayerType['isRandom'] == true ||
            existingGameData['is_random_join'] == true;
        final isRandom =
            data['is_random_join'] == true ||
            DutchGameHelpers.isRandomJoinInProgress ||
            existingRandom;
        if (isRandom) {
          _updateGameData(gameId, {'is_random_join': true});
        }
        _updateGameInMap(gameId, {
          'multiplayerType': {
            'type': gameType == 'tournament' ? 'tournament' : 'classic',
            'isRandom': isRandom,
          },
        });
      } else if (gameLevel != null) {
        _updateGameData(gameId, {'game_level': gameLevel});
      }
    }
    
    // Update the games map with additional information first (needed for widget sync)
    // 🎯 CRITICAL: Only update if this wasn't a new game (new games are already updated above)
    if (!wasNewGame) {
      final updateData = {
        'drawPileCount': drawPileCount,
        'discardPileCount': discardPileCount,
        'discardPile': discardPile,
        'players': players,  // Include all players data
        'turn_events': turnEvents, // Include turn_events for widget slices
      };
      
      _updateGameInMap(gameId, updateData);
    }
    
    // 🎯 CRITICAL: Sync widget states from game state FIRST (matches practice mode pattern)
    // This ensures myHandCards, myDrawnCard, playerStatus, etc. are synced from game state
    // Must happen before main state update so widget slices recompute with turn_events
    _syncWidgetStatesFromGameState(
      gameId,
      gameState,
      turnEvents: turnEvents,
      mainStatePatch: consolidatedMainStatePatch,
      previousPlayers: previousPlayersForWidgetSync,
    );
    
    // Get fresh games map after widget sync (it may have been updated)
    final currentGamesAfterSync = _getCurrentGamesMap();
    
    // Extract currentPlayer from game state for main state update
    final currentPlayerFromState = gameState['currentPlayer'] as Map<String, dynamic>?;
    
    // Get current user's player status for instructions (not the current player's status)
    // Note: players list and currentUserId are already extracted above for debug logging
    final loginUserIdForInstructions =
        StateManager().getModuleState<Map<String, dynamic>>('login')?['userId']?.toString() ?? '';
    final myPlayerForInstructions = findLocalPlayerInRoster(
      players,
      seatId: currentUserId,
      loginUserId: loginUserIdForInstructions,
      practiceUserId: getPracticeUserId(),
    );
    final currentUserPlayerStatus = myPlayerForInstructions?['status']?.toString();
    
    
    final stateBeforePhase =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final previousUiPhase = stateBeforePhase['gamePhase']?.toString() ?? '';
    var endGameModalPinned =
        DutchGameHelpers.shouldKeepEndGameModalVisible(stateBeforePhase);
    final rawPhase = gameState['phase']?.toString() ??
        gameState['gamePhase']?.toString() ??
        '';
    if (endGameModalPinned &&
        rawPhase.isNotEmpty &&
        rawPhase != 'game_ended') {
      if (LOGGING_SWITCH) {
        customlog(
          'rematch: endModalDismiss serverMovedOn gameId=$gameId rawPhase=$rawPhase '
          'prevUi=$previousUiPhase prevRaw=$previousRawPhase '
          'roster=${playerStatusesLogSummary(players)}',
        );
      }
      GameEndedModalPin.dismissOverlay(navigateToLobby: false);
      endGameModalPinned = false;
      consolidatedMainStatePatch['rematch_waiting_game_id'] = '';
    }
    final rematchStarting = previousRawPhase == 'game_ended' &&
        rawPhase.isNotEmpty &&
        rawPhase != 'game_ended';
    if (rematchStarting) {
      consolidatedMainStatePatch['rematch_waiting_game_id'] = '';
      _lastStateVersionByGameId.remove(gameId);
      _lastEventSignatureByGameId.remove(gameId);
      consolidatedMainStatePatch['messages'] = {
        'isVisible': false,
        'title': '',
        'content': '',
        'type': 'info',
        'showCloseButton': true,
        'autoClose': false,
        'autoCloseDelay': 3000,
      };
      if (LOGGING_SWITCH) {
        customlog(
          'rematch: client phase transition gameId=$gameId '
          'prevRaw=$previousRawPhase nextRaw=$rawPhase '
          'prevUi=$previousUiPhase rematchWaiting=${stateBeforePhase['rematch_waiting_game_id']} '
          'myStatus=$currentUserPlayerStatus '
          'roster=${playerStatusesLogSummary(players)}',
        );
      }
    }
    var uiPhase = DutchGameHelpers.effectiveUiGamePhase(
      gameState,
      fallbackPhase: rematchStarting
          ? (rawPhase.isNotEmpty ? rawPhase : 'waiting_for_players')
          : (previousUiPhase.isNotEmpty ? previousUiPhase : 'playing'),
    );
    if (uiPhase != 'same_rank_window' &&
        DutchGameHelpers.anyPlayerInSameRankWindow(gameState)) {
      uiPhase = 'same_rank_window';
    }
    final kickedModalShownForPhase =
        stateBeforePhase['kickedModalShownFor']?.toString() ?? '';
    if (kickedModalShownForPhase == gameId && !userStillInPlayers) {
      uiPhase = 'game_ended';
    } else if (endGameModalPinned) {
      uiPhase = 'game_ended';
    }
    final enteringInitialPeekDeal = rawPhase == 'initial_peek' &&
        (wasNewGame || previousRawPhase != 'initial_peek');
    if (enteringInitialPeekDeal) {
      if (!wasNewGame) {
        _dealBootstrapGameId = null;
        DutchAnimRuntime.instance.reset();
      }
      consolidatedMainStatePatch['dealAnimActive'] = true;
      if (LOGGING_SWITCH) {
        customlog(
          'dealAnim: activate gameId=$gameId wasNewGame=$wasNewGame '
          'prevPhase=$previousRawPhase rawPhase=$rawPhase',
        );
      }
    }
    // Extract winners list if game has ended - check both data and gameState
    final winners = data['winners'] as List<dynamic>? ?? gameState['winners'] as List<dynamic>?;
    

    // 🎯 CRITICAL: Always ensure currentGameId is set (even for existing games)
    // This is essential for the game play screen to update correctly when match starts
    final currentStateForGameId = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final existingCurrentGameId = currentStateForGameId['currentGameId']?.toString() ?? '';
    // Only reset anim queue when switching to a *different* game. If currentGameId is still empty,
    // `game_animation` may have already enqueued — resetting here would drop those flights (intermittent "no anim").
    if (existingCurrentGameId.isNotEmpty && existingCurrentGameId != gameId) {
      
      DutchAnimRuntime.instance.reset();
    }

    // Entry-fee deduction is server-side (Dart WS → Python) on start_match; do not deduct from the client.

    // Then update main state with games map, discardPile, currentPlayer, turn_events (matches practice mode pattern)
    // 🎯 CRITICAL: Update gamePhase FIRST so MessagesWidget can check it
    if (existingCurrentGameId.isNotEmpty && existingCurrentGameId != gameId) {
      consolidatedMainStatePatch['kickedModalShownFor'] = '';
    }

    final stateBeforeMainPatch =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final previousMyCardsToPeek =
        stateBeforeMainPatch['myCardsToPeek'] as List<dynamic>?;
    List<dynamic> myCardsToPeekFinal;
    if (myCardsToPeekFromEvent != null) {
      myCardsToPeekFinal = DutchGameHelpers.preferFullPeekCards(
        myCardsToPeekFromEvent,
        previousMyCardsToPeek,
      );
    } else {
      final syncedPeek =
          consolidatedMainStatePatch['myCardsToPeek'] as List<dynamic>? ??
              <dynamic>[];
      myCardsToPeekFinal = DutchGameHelpers.preferFullPeekCards(
        syncedPeek,
        previousMyCardsToPeek,
      );
    }
    if (!DutchGameHelpers.statusAllowsPeekReveal(
      currentUserPlayerStatus,
      gamePhase: rawPhase,
    )) {
      myCardsToPeekFinal = [];
    } else if (currentUserPlayerStatus == 'queen_peek' &&
        !DutchGameHelpers.peekListHasFullData(myCardsToPeekFinal)) {
      if (previousMyCardsToPeek != null &&
          DutchGameHelpers.peekListHasFullData(previousMyCardsToPeek)) {
        myCardsToPeekFinal = previousMyCardsToPeek;
      } else {
        myCardsToPeekFinal = [];
      }
    } else if (currentUserPlayerStatus == 'peeking') {
      myCardsToPeekFinal = myCardsToPeekFinal
          .whereType<Map<String, dynamic>>()
          .where(DutchGameHelpers.peekCardHasFullData)
          .toList();
    }
    if (LOGGING_SWITCH) {
      final wireCurrentId = currentPlayerFromState?['id']?.toString() ??
          (currentPlayer is Map ? currentPlayer['id']?.toString() : null) ??
          data['current_player']?.toString();
      final turnLine =
          'handleGameStateUpdated: myStatus=$currentUserPlayerStatus '
          'currentPlayer=$wireCurrentId seat=$currentUserId '
          'isMyTurn=${currentPlayerFromState?['id']?.toString() == currentUserId}';
      if (myCardsToPeekFinal.isNotEmpty) {
        customlog(
          '$turnLine peek len=${myCardsToPeekFinal.length} '
          'cards=${peekListLogSummary(myCardsToPeekFinal)}',
        );
      } else {
        customlog('$turnLine peek empty');
      }
      if (gameId.startsWith('room_')) {
        final phaseChanged = previousUiPhase != uiPhase;
        final rawChanged = previousRawPhase != rawPhase;
        if (rematchStarting ||
            phaseChanged ||
            rawChanged ||
            endGameModalPinned) {
          customlog(
            'rematch: phaseCommit gameId=$gameId '
            'prevUi=$previousUiPhase ui=$uiPhase raw=$rawPhase prevRaw=$previousRawPhase '
            'modalPinned=$endGameModalPinned rematchStarting=$rematchStarting '
            'isGameActive=${uiPhase != 'game_ended'} '
            'myStatus=$currentUserPlayerStatus wireCurrentPlayerStatus=$currentPlayerStatus '
            'roster=${playerStatusesLogSummary(players)}',
          );
        }
      }
    }

    consolidatedMainStatePatch.addAll({
      'currentGameId': gameId,  // Always set currentGameId (CRITICAL for game play screen to update)
      'games': currentGamesAfterSync, // Updated games map with widget data synced
      'gamePhase': uiPhase, // 🎯 CRITICAL: Set gamePhase before checking for winners modal
      'isGameActive': uiPhase != 'game_ended', // Set to false when game has ended
      'roundNumber': roundNumber,
      'currentPlayer': currentPlayerFromState ?? currentPlayer, // Use currentPlayer from game state if available
      'currentPlayerStatus': currentPlayerStatus,
      'roundStatus': roundStatus,
      'discardPile': discardPile, // Updated discard pile for centerBoard slice
      'turn_events': turnEvents, // Include turn_events for animations (critical for widget slice recomputation)
      'turn_feed': turnFeed,
      'myCardsToPeek': myCardsToPeekFinal,
      if (myCardsToPeekFinal.isEmpty)
        'protectedCardsToPeek': null
      else if (rawPhase == 'initial_peek' &&
          DutchGameHelpers.peekListHasFullData(myCardsToPeekFinal))
        'protectedCardsToPeek': myCardsToPeekFinal,
    });
    
    // Trigger instructions if showInstructions is enabled
    final seatIdForTurn = myPlayerForInstructions?['id']?.toString() ?? currentUserId;
    final isMyTurn = currentPlayerFromState?['id']?.toString() == seatIdForTurn ||
        (currentPlayer is Map && currentPlayer['id']?.toString() == seatIdForTurn);
    
    _triggerInstructionsIfNeeded(
      gameId: gameId,
      gameState: gameState,
      playerStatus: currentUserPlayerStatus, // Pass current user's player status, not current player's status
      isMyTurn: isMyTurn,
    );
    
    // Add game to joinedGames list if it's not already there (one-time addition)
    // This ensures games appear in current rooms widget even if joined_games event is delayed
    // Only add if game is in games map (user is actually in the game) and not already in joinedGames
    final currentGamesForJoined = _getCurrentGamesMap();
    if (currentGamesForJoined.containsKey(gameId)) {
      final gameInMap = currentGamesForJoined[gameId] as Map<String, dynamic>? ?? {};
      final gameData = gameInMap['gameData'] as Map<String, dynamic>? ?? {};
      
      // Only proceed if we have valid gameData
      if (gameData.isNotEmpty && gameData['game_id'] != null) {
        // Get current joinedGames list
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentJoinedGames = List<Map<String, dynamic>>.from(currentState['joinedGames'] as List<dynamic>? ?? []);
        
        // Check if this game is already in joinedGames
        final existingIndex = currentJoinedGames.indexWhere((game) => game['game_id'] == gameId);
        
        if (existingIndex < 0) {
          // Game not in joinedGames - add it (one-time addition)
          
          currentJoinedGames.add(gameData);
          
          // Update joinedGames state
          consolidatedMainStatePatch.addAll({
            'joinedGames': currentJoinedGames,
            'totalJoinedGames': currentJoinedGames.length,
          });
        }
        // If game already exists in joinedGames, don't update it (prevents duplicates)
      }
    }

    _updateMainGameState(consolidatedMainStatePatch);

    final dealAnimPending = consolidatedMainStatePatch['dealAnimActive'] == true ||
        stateBeforeMainPatch['dealAnimActive'] == true;
    if (dealAnimPending && rawPhase == 'initial_peek') {
      _scheduleInitialDealBootstrap(gameId);
    }

    // Check for demo action completion
    _checkDemoActionCompletion(
      gameId: gameId,
      gameState: gameState,
      currentUserPlayerStatus: currentUserPlayerStatus,
    );
    
    // Add session message about game state update or game end
    
    if (uiPhase == 'game_ended' && winners != null && winners.isNotEmpty) {
      
      // Winners list is ordered: actual winners first (winType != null), then rest by points
      final actualWinners = winners.where((w) => w is Map<String, dynamic> && w['winType'] != null).toList();
      final winnerMessages = actualWinners.map((w) {
        if (w is Map<String, dynamic>) {
          final playerName = w['playerName']?.toString() ?? 'Unknown';
          final winType = w['winType']?.toString() ?? 'unknown';
          String winReason;
          switch (winType) {
            case 'four_of_a_kind':
              winReason = 'Four of a Kind';
              break;
            case 'empty_hand':
              winReason = 'No Cards Left';
              break;
            case 'lowest_points':
              winReason = 'Lowest Points';
              break;
            case 'dutch':
              winReason = 'Dutch Called';
              break;
            default:
              winReason = 'Unknown';
          }
          return '$playerName ($winReason)';
        }
        return 'Unknown';
      }).join(', ');
      
      final isCurrentUserWinner = actualWinners.any((w) {
        if (w is Map<String, dynamic>) {
          return (w['playerId'] ?? w['id'])?.toString() == currentUserId;
        }
        return false;
      });
      _addSessionMessage(
        level: 'success',
        title: 'Game Ended',
        message: 'Winner(s): $winnerMessages',
        data: {
          'game_id': gameId,
          'winners': winners,
          'game_ended': true,
        },
        // Always show standings modal; winners also get celebration pushed on top (see _showWinCelebrationIfNeeded).
        showModal: true,
        isCurrentUserWinner: isCurrentUserWinner,
      );
      final winCelebrationGate = _showWinCelebrationIfNeeded(
        gameId: gameId,
        isCurrentUserWinner: isCurrentUserWinner,
        winnerMessages: winnerMessages,
        logContext: 'handleGameStateUpdated',
      );
      
      // Track game completed event (only actual winners)
      final gameMode = gameState['game_mode']?.toString() ?? 'multiplayer';
      _trackGameEvent('game_completed', {
        'game_id': gameId,
        'game_mode': gameMode,
        'result': isCurrentUserWinner ? 'win' : 'loss',
        'winners_count': winners.length,
      });
      unawaited(DutchFirebaseAnalytics.maybeLogMatchCompleted(
        gameId: gameId,
        gameState: gameState,
        isCurrentUserWinner: isCurrentUserWinner,
      ));
      
      // Refresh user stats (including coins) after game ends to update app bar display
      // This ensures the coins display shows the updated balance after winning/losing
      
      _refreshUserStatsAfterGameEnd(
        'handleGameStateUpdated',
        afterModalGate: winCelebrationGate,
      );
    } else {
      // Normal game state update — hide stale modals only when end-game modal is not pinned open.
      if (uiPhase != 'game_ended') {
        final dutchNow =
            StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        if (!DutchGameHelpers.shouldKeepEndGameModalVisible(dutchNow)) {
          final currentMessages =
              dutchNow['messages'] as Map<String, dynamic>? ?? {};
          if (currentMessages['isVisible'] == true) {
            DutchGameHelpers.updateUIState({
              'messages': {
                ...currentMessages,
                'isVisible': false,
              },
            });
          }
        }
      }

      // Intentionally skip per-tick info message updates.
      // They create extra state writes and trigger avoidable rebuild churn.
    }
    // `games` is already included in consolidatedMainStatePatch.
    // Avoid committing a second games-only update that causes extra no-op updater passes.
    _endGamesMapBatch(commit: false);
  }

  /// Handle game_state_partial_update event
  static void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    
    final gameId = data['game_id']?.toString() ?? '';
    final changedProperties = data['changed_properties'] as List<dynamic>? ?? [];
    final partialGameState = data['partial_game_state'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Get current game state to merge with partial updates
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      return; // Game not found, ignore partial update
    }
    
    final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
    final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final currentGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Merge partial updates with current game state
    final updatedGameState = Map<String, dynamic>.from(currentGameState);
    updatedGameState.addAll(partialGameState);
    final stateVersion = _extractStateVersion(data, updatedGameState);
    final signature = _buildEventSignature(
      'game_state_partial_update',
      gameId,
      stateVersion,
      updatedGameState,
      null,
      partialGameState,
      changedProperties,
    );
    if (_shouldDropDuplicateOrStaleEvent(
      eventType: 'game_state_partial_update',
      gameId: gameId,
      stateVersion: stateVersion,
      signature: signature,
    )) {
      return;
    }
    if (data['winners'] != null) {
      updatedGameState['winners'] = data['winners'];
    }
    
    // Update the game data with merged state using helper method
    _updateGameData(gameId, {
      'game_state': updatedGameState,
    });
    
    // Update specific UI fields based on changed properties
    final updates = <String, dynamic>{};
    bool shouldSyncWidgetStates = false;
    
    for (final property in changedProperties) {
      final propName = property.toString();
      
      switch (propName) {
        case 'phase':
          // Update main state only - normalize backend phase to UI phase
          final dutchForPhase =
              StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          if (DutchGameHelpers.shouldKeepEndGameModalVisible(dutchForPhase)) {
            break;
          }
          final rawPhase = updatedGameState['phase']?.toString();
          final uiPhase = rawPhase == 'waiting_for_players'
              ? 'waiting'
              : (rawPhase == 'game_ended'
                  ? 'game_ended'
                  : (rawPhase ?? 'playing'));
          _updateMainGameState({
            'gamePhase': uiPhase,
          });
          break;
        case 'players':
          // Mark that we need to sync widget states since players changed
          shouldSyncWidgetStates = true;
          break;
        case 'current_player_id':
        case 'currentPlayer':
          // Mark that we need to sync widget states since current player changed
          shouldSyncWidgetStates = true;
          updates['currentPlayer'] = updatedGameState['current_player_id'] ?? updatedGameState['currentPlayer'];
          break;
        case 'draw_pile':
          updates['drawPileCount'] = DutchGameHelpers.drawPileCountFromGameState(updatedGameState);
          break;
        case 'discard_pile':
          final discardPile = updatedGameState['discardPile'] as List<dynamic>? ?? [];
          updates['discardPileCount'] = DutchGameHelpers.discardPileCountFromGameState(updatedGameState);
          updates['discardPile'] = discardPile;
          break;
        case 'dutch_called_by':
        case 'dutchCalledBy':
          updates['dutchCalledBy'] = updatedGameState['dutchCalledBy'] ??
              updatedGameState['dutch_called_by'];
          // Track Dutch call event
          final gameMode = updatedGameState['game_mode']?.toString() ?? 'multiplayer';
          _trackGameEvent('dutch_called', {
            'game_id': gameId,
            'game_mode': gameMode,
            'called_by': (updatedGameState['dutchCalledBy'] ??
                    updatedGameState['dutch_called_by'])
                ?.toString(),
          });
          break;
        case 'game_ended':
          updates['isGameActive'] = !(updatedGameState['game_ended'] == true);
          break;
        case 'winner':
          updates['winner'] = updatedGameState['winner'];
          break;
      }
    }

    
    // Apply UI updates if any
    if (updates.isNotEmpty) {
      _updateGameInMap(gameId, updates);
    }
    // 🎯 CRITICAL: Sync widget states if players or currentPlayer changed
    // This ensures computed slices (myHand.cards, etc.) stay in sync
    if (shouldSyncWidgetStates) {
      // Try to get turn_events from current games map if available
      final currentGamesForTurnEvents = _getCurrentGamesMap();
      final currentGameForTurnEvents = currentGamesForTurnEvents[gameId] as Map<String, dynamic>? ?? {};
      final turnEvents = currentGameForTurnEvents['turn_events'] as List<dynamic>?;
      _syncWidgetStatesFromGameState(
        gameId,
        updatedGameState,
        turnEvents: turnEvents,
        previousPlayers: currentGameState['players'] as List<dynamic>?,
      );
    }
    
    // Check if game has ended and show winner modal
    final dutchBeforePartialPhase =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final previousPartialUiPhase =
        dutchBeforePartialPhase['gamePhase']?.toString() ?? '';
    var endPartialModalPinned =
        DutchGameHelpers.shouldKeepEndGameModalVisible(dutchBeforePartialPhase);
    final rawPartialPhase = updatedGameState['phase']?.toString() ??
        updatedGameState['gamePhase']?.toString() ??
        '';
    if (endPartialModalPinned &&
        rawPartialPhase.isNotEmpty &&
        rawPartialPhase != 'game_ended') {
      GameEndedModalPin.dismissOverlay(navigateToLobby: false);
      endPartialModalPinned = false;
    }
    var uiPhase = DutchGameHelpers.effectiveUiGamePhase(
      updatedGameState,
      fallbackPhase: previousPartialUiPhase.isNotEmpty ? previousPartialUiPhase : 'playing',
    );
    if (endPartialModalPinned) {
      uiPhase = 'game_ended';
    } else if (rawPartialPhase.isNotEmpty && rawPartialPhase != 'game_ended') {
      uiPhase = DutchGameHelpers.effectiveUiGamePhase(
        updatedGameState,
        fallbackPhase: rawPartialPhase,
      );
    }
    if (LOGGING_SWITCH && gameId.startsWith('room_')) {
      final partialPlayers = updatedGameState['players'] as List<dynamic>?;
      if (previousPartialUiPhase != uiPhase ||
          (rawPartialPhase.isNotEmpty && rawPartialPhase != 'game_ended')) {
        customlog(
          'rematch: partialPhase gameId=$gameId prevUi=$previousPartialUiPhase ui=$uiPhase '
          'raw=$rawPartialPhase modalPinned=$endPartialModalPinned '
          'roster=${playerStatusesLogSummary(partialPlayers)}',
        );
      }
    }
    
    // Extract winners list if game has ended
    final winners = data['winners'] as List<dynamic>? ?? updatedGameState['winners'] as List<dynamic>?;
    
    
    // Add session message about partial update or game end
    if (uiPhase == 'game_ended' && winners != null && winners.isNotEmpty) {
      
      // Winners list is ordered: actual winners first (winType != null), then rest by points
      final actualWinnersPartial = winners.where((w) => w is Map<String, dynamic> && w['winType'] != null).toList();
      final winnerMessages = actualWinnersPartial.map((w) {
        if (w is Map<String, dynamic>) {
          final playerName = w['playerName']?.toString() ?? 'Unknown';
          final winType = w['winType']?.toString() ?? 'unknown';
          String winReason;
          switch (winType) {
            case 'four_of_a_kind':
              winReason = 'Four of a Kind';
              break;
            case 'empty_hand':
              winReason = 'No Cards Left';
              break;
            case 'lowest_points':
              winReason = 'Lowest Points';
              break;
            case 'dutch':
              winReason = 'Dutch Called';
              break;
            default:
              winReason = 'Unknown';
          }
          return '$playerName ($winReason)';
        }
        return 'Unknown';
      }).join(', ');
      
      final currentUserIdPartial = getCurrentUserId();
      final isCurrentUserWinnerPartial = actualWinnersPartial.any((w) {
        if (w is Map<String, dynamic>) {
          return (w['playerId'] ?? w['id'])?.toString() == currentUserIdPartial;
        }
        return false;
      });
      
      // Update gamePhase and show modal in the same state update to avoid race condition
      
      DutchGameHelpers.updateUIState({
        'gamePhase': 'game_ended', // Ensure gamePhase is set before showing modal
      });
      
      
      
      // Refresh user stats (including coins) after game ends to update app bar display
      // This ensures the coins display shows the updated balance after winning/losing
      
      Future<void>? winCelebrationGate;
      
      _addSessionMessage(
        level: 'success',
        title: 'Game Ended',
        message: 'Winner(s): $winnerMessages',
        data: {
          'game_id': gameId,
          'winners': winners,
          'game_ended': true,
        },
        showModal: true,
        isCurrentUserWinner: isCurrentUserWinnerPartial,
      );
      winCelebrationGate = _showWinCelebrationIfNeeded(
        gameId: gameId,
        isCurrentUserWinner: isCurrentUserWinnerPartial,
        winnerMessages: winnerMessages,
        logContext: 'handleGameStatePartialUpdate',
      );
      unawaited(DutchFirebaseAnalytics.maybeLogMatchCompleted(
        gameId: gameId,
        gameState: updatedGameState,
        isCurrentUserWinner: isCurrentUserWinnerPartial,
      ));
      _refreshUserStatsAfterGameEnd(
        'handleGameStatePartialUpdate',
        afterModalGate: winCelebrationGate,
      );
    } else {
      // Normal partial update — hide stale modals only when end-game modal is not pinned open.
      if (uiPhase != 'game_ended') {
        final dutchNow =
            StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        if (!DutchGameHelpers.shouldKeepEndGameModalVisible(dutchNow)) {
          final currentMessages =
              dutchNow['messages'] as Map<String, dynamic>? ?? {};
          if (currentMessages['isVisible'] == true) {
            DutchGameHelpers.updateUIState({
              'messages': {
                ...currentMessages,
                'isVisible': false,
              },
            });
          }
        }
      }

      // Intentionally skip per-tick info message updates to reduce write/rebuild churn.
    }
  }

  /// Handle player_state_updated event
  static void handlePlayerStateUpdated(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final playerId = data['player_id']?.toString() ?? '';
    final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // 🎯 CRITICAL: Verify game exists in games map before updating
    // This prevents stale state updates when user has left the game
    final currentGames = _getCurrentGamesMap();
    if (!currentGames.containsKey(gameId)) {
      
      return;
    }
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this update is for the current user
    final isMyUpdate = playerId == currentUserId;
    
    if (isMyUpdate) {
      
      // Extract player data fields
      final hand = playerData['hand'] as List<dynamic>? ?? [];
      // final visibleCards = playerData['visibleCards'] as List<dynamic>? ?? [];
      final cardsToPeek = playerData['cardsToPeek'] as List<dynamic>? ?? [];
      final drawnCard = playerData['drawnCard'] as Map<String, dynamic>?;
      final score = playerData['score'] as int? ?? 0;
      final status = playerData['status']?.toString() ?? 'unknown';
      final isCurrentPlayer = playerData['isCurrentPlayer'] == true;
      // final hasCalledDutch = playerData['hasCalledDutch'] == true;
      
      // Update the main game state with player information using helper method
      _updateMainGameState({
        'playerStatus': status,
        'myScore': score,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
        'myCardsToPeek': cardsToPeek,
      });
      
      // Update the games map with hand information using helper method
      _updateGameInMap(gameId, {
        'myHandCards': hand,
        'selectedCardIndex': -1,
        'isMyTurn': isCurrentPlayer,
        'myDrawnCard': drawnCard,
      });
      
      // Add session message about player state update
      _addSessionMessage(
        level: 'info',
        title: 'Player State Updated',
        message: 'Hand: ${hand.length} cards, Score: $score, Status: $status',
        data: {
          'game_id': gameId,
          'player_id': playerId,
          'hand_size': hand.length,
          'score': score,
          'status': status,
          'is_current_player': isCurrentPlayer,
        },
      );
    } else {
      
      // Get current opponents and update them using helper method
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      if (currentGames.containsKey(gameId)) {
        final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final currentOpponents = currentGameData['opponentPlayers'] as List<dynamic>? ?? [];
        
        // Update opponent information in the games map using helper method
        _updateGameData(gameId, {
          'opponentPlayers': currentOpponents.map((opponent) {
            if (opponent['id'] == playerId) {
              return {
                ...opponent,
                'hand': playerData['hand'] ?? [],
                'score': playerData['score'] ?? 0,
                'status': playerData['status'] ?? 'unknown',
                'hasCalledDutch': playerData['hasCalledDutch'] ?? false,
                'drawnCard': playerData['drawnCard'],
              };
            }
            return opponent;
          }).toList(),
        });
      }
    }
  }

  /// Handle queen_peek_result event
  static void handleQueenPeekResult(Map<String, dynamic> data) {
    final gameId = data['game_id']?.toString() ?? '';
    final peekingPlayerId = data['peeking_player_id']?.toString() ?? '';
    final targetPlayerId = data['target_player_id']?.toString() ?? '';
    final peekedCard = data['peeked_card'] as Map<String, dynamic>? ?? {};
    // final timestamp = data['timestamp']?.toString() ?? '';
    
    // Find the current user's player data
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Check if this peek result is for the current user
    final isMyPeekResult = peekingPlayerId == currentUserId;
    
    if (isMyPeekResult) {
      // Extract card details
      final cardId = peekedCard['card_id']?.toString() ?? '';
      final cardRank = peekedCard['rank']?.toString() ?? '';
      final cardSuit = peekedCard['suit']?.toString() ?? '';
      final cardPoints = peekedCard['points'] as int? ?? 0;
      final cardColor = peekedCard['color']?.toString() ?? '';
      final cardIndex = peekedCard['index'] as int? ?? -1;
      
      // Add session message about successful peek
      _addSessionMessage(
        level: 'info',
        title: 'Queen Peek Result',
        message: 'You peeked at $targetPlayerId\'s card: $cardRank of $cardSuit ($cardPoints points)',
        data: {
          'game_id': gameId,
          'target_player_id': targetPlayerId,
          'peeked_card': peekedCard,
          'card_details': {
            'id': cardId,
            'rank': cardRank,
            'suit': cardSuit,
            'points': cardPoints,
            'color': cardColor,
            'index': cardIndex,
          },
        },
      );
    } else {
      // This is another player's peek result - we can optionally show a generic message
      // or keep it private (current implementation keeps it private)
      _addSessionMessage(
        level: 'info',
        title: 'Queen Power Used',
        message: '$peekingPlayerId used Queen peek on $targetPlayerId',
        data: {
          'game_id': gameId,
          'peeking_player_id': peekingPlayerId,
          'target_player_id': targetPlayerId,
          'is_my_peek': false,
        },
      );
    }
  }

  /// Handle dutch_error event
  static void handleDutchError(Map<String, dynamic> data) {
    final message = data['message']?.toString() ?? 'An error occurred';
    
    // Add session message about the error
    _addSessionMessage(
      level: 'error',
      title: 'Action Error',
      message: message,
      data: data,
    );
    
    // Update state with action error for UI display
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    StateManager().updateModuleState('dutch_game', {
      ...currentState,
      'actionError': {
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
    
    
  }
}
