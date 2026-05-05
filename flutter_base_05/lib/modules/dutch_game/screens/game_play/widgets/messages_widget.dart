import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../backend_core/utils/level_matcher.dart';
import '../../../managers/dutch_event_handler_callbacks.dart';
import '../../../managers/validated_event_emitter.dart';
import '../../../utils/dutch_game_helpers.dart';
import '../../../widgets/dutch_slice_builder.dart';

/// Decoder for .lottie (dotlottie zip) assets: picks the first .json animation.
Future<LottieComposition?> _decodeDotLottie(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        if (f.name.endsWith('.json')) return f;
      }
      return files.isNotEmpty ? files.first : null;
    },
  );
}

/// Loads winner Lottie composition; returns null on any error (e.g. startFrame == endFrame assertion).
Future<LottieComposition?> _loadWinnerLottieSafe() async {
  try {
    final data = await rootBundle.load('assets/lottie/winner01.lottie');
    final bytes = data.buffer.asUint8List();
    return await _decodeDotLottie(bytes).catchError((_, __) => null);
  } catch (_) {
    return null;
  }
}

/// Deep JSON-style copy of [game_state] for [rematch] WS payload (best-effort).
Map<String, dynamic> _snapshotGameStateForRematch(Map<String, dynamic>? gs) {
  if (gs == null || gs.isEmpty) return {};
  try {
    final decoded = jsonDecode(jsonEncode(gs));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded.map((k, v) => MapEntry(k.toString(), v)));
  } catch (_) {}
  return Map<String, dynamic>.from(gs);
}

/// Show "Play Again" when not a random game: prefer `is_random_game` on game_state or gameData; else treat `is_random_join` as random.
bool _shouldShowPlayAgain(Map<String, dynamic>? gameState, Map<String, dynamic>? gameData) {
  if (gameState != null && gameState.containsKey('is_random_game')) {
    return gameState['is_random_game'] != true;
  }
  if (gameData != null && gameData.containsKey('is_random_game')) {
    return gameData['is_random_game'] != true;
  }
  return gameData?['is_random_join'] != true;
}

/// IRL (in-person) tournaments: `tournament_data.type` is present on [game_state] through game end (see server `game_state_updated`).
bool _tournamentDataHidesPlayAgain(Map<String, dynamic>? gameState) {
  final td = gameState?['tournament_data'];
  if (td is! Map) return false;
  final type = (td['type'] ?? '').toString().trim().toUpperCase();
  return type == 'IRL';
}

/// One row for tournament cumulative leaderboard (least points, then least cards).
class TournamentLeaderboardRow {
  const TournamentLeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.totalPoints,
    required this.totalCards,
    required this.isCurrentUser,
  });

  final int rank;
  final String displayName;
  final int totalPoints;
  final int totalCards;
  final bool isCurrentUser;
}

class _LbAgg {
  _LbAgg({required this.name});
  String name;
  int points = 0;
  int cards = 0;
}

/// [single_room_league] reuses one [room_id] per rematch. If the latest completed row for that
/// room already reflects this hand's points/cards (Mongo append merged into [tournament_data]),
/// returning true avoids adding [orderedWinners] again (double-count).
bool _latestCompletedMatchSameRoomMatchesWinners({
  required List<dynamic> matches,
  required String currentGameId,
  required List<Map<String, dynamic>> orderedWinners,
  required String Function(String sessionId) keyForSession,
}) {
  if (currentGameId.isEmpty || orderedWinners.isEmpty) return false;

  Map<String, dynamic>? best;
  var bestIdx = -1;
  for (final raw in matches) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    if ((m['room_id']?.toString() ?? '') != currentGameId) continue;
    if ((m['status']?.toString() ?? '') != 'completed') continue;
    final idxRaw = m['match_index'];
    final idx = idxRaw is int ? idxRaw : int.tryParse('$idxRaw') ?? 0;
    if (idx >= bestIdx) {
      bestIdx = idx;
      best = m;
    }
  }
  if (best == null) return false;

  final fromRow = <String, ({int p, int c})>{};
  final scores = best['scores'];
  if (scores is List) {
    for (final s in scores) {
      if (s is! Map) continue;
      final uid = s['user_id']?.toString() ?? '';
      if (uid.isEmpty) continue;
      final tp = s['total_end_points'];
      final ec = s['end_card_count'];
      final pi = tp is num ? tp.toInt() : int.tryParse('$tp') ?? 0;
      final ci = ec is num ? ec.toInt() : int.tryParse('$ec') ?? 0;
      fromRow[uid] = (p: pi, c: ci);
    }
  }
  if (fromRow.isEmpty) {
    final players = best['players'];
    if (players is List) {
      for (final p in players) {
        if (p is! Map) continue;
        final uid = p['user_id']?.toString() ?? '';
        if (uid.isEmpty) continue;
        final pts = p['points'];
        final pi = pts is num ? pts.toInt() : int.tryParse('$pts') ?? 0;
        final ncl = p['number_of_cards_left'];
        final ci = ncl is List ? ncl.length : (ncl is num ? ncl.toInt() : int.tryParse('$ncl') ?? 0);
        fromRow[uid] = (p: pi, c: ci);
      }
    }
  }
  if (fromRow.length != orderedWinners.length) return false;

  for (final w in orderedWinners) {
    final sid = w['playerId']?.toString() ?? '';
    final key = keyForSession(sid);
    final pts = w['points'];
    final cc = w['cardCount'];
    final pi = pts is num ? pts.toInt() : int.tryParse('$pts') ?? 0;
    final ci = cc is num ? cc.toInt() : int.tryParse('$cc') ?? 0;
    final row = fromRow[key];
    if (row == null || row.p != pi || row.c != ci) return false;
  }
  return true;
}

/// Cumulative stats from [tournament_data.matches] plus this game's [orderedWinners] when needed.
///
/// Bracket-style tournaments: skip the DB row for [currentGameId] (one room per match) and add
/// [orderedWinners] for the hand that just ended. [single_room_league]: same physical room for
/// every match — sum every completed row; add [orderedWinners] only if the latest completed row
/// for this room is not yet this hand (avoids double-count when Mongo append is already merged).
List<TournamentLeaderboardRow>? _buildTournamentLeaderboardRows({
  required Map<String, dynamic>? gameState,
  required List<Map<String, dynamic>> orderedWinners,
  required String currentGameId,
  required String currentUserId,
}) {
  if (gameState == null || gameState['is_tournament'] != true) return null;
  final td = gameState['tournament_data'];
  if (td is! Map) return null;
  final tournamentData = Map<String, dynamic>.from(td);
  final fmt = (tournamentData['format'] ?? '').toString().toLowerCase();
  final isSingleRoomLeague = fmt == 'single_room_league';
  final matchesRaw = tournamentData['matches'];
  final matches = matchesRaw is List ? matchesRaw : const [];

  final uidBySession = <String, String>{};
  final pl = gameState['players'];
  if (pl is List) {
    for (final p in pl) {
      if (p is! Map) continue;
      final sid = p['id']?.toString() ?? '';
      final uid = p['userId']?.toString() ?? '';
      if (sid.isNotEmpty && uid.isNotEmpty) uidBySession[sid] = uid;
    }
  }

  String keyForSession(String sessionId) {
    if (sessionId.isEmpty) return '';
    return uidBySession[sessionId] ?? sessionId;
  }

  final aggs = <String, _LbAgg>{};

  void bump(String key, int pts, int cards, String name) {
    if (key.isEmpty) return;
    aggs.putIfAbsent(key, () => _LbAgg(name: name.isNotEmpty ? name : 'Player'));
    final a = aggs[key]!;
    a.points += pts;
    a.cards += cards;
    if (name.isNotEmpty) a.name = name;
  }

  for (final raw in matches) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final rid = m['room_id']?.toString() ?? '';
    // Bracket / one room per match: exclude this room's row (filled async) and use orderedWinners.
    // single_room_league: same room_id for every match — never skip here or history is dropped.
    if (!isSingleRoomLeague && rid.isNotEmpty && rid == currentGameId) continue;
    final st = m['status']?.toString() ?? '';
    if (st.isNotEmpty && st != 'completed') continue;

    var fromScores = false;
    final scores = m['scores'];
    if (scores is List) {
      for (final s in scores) {
        if (s is! Map) continue;
        fromScores = true;
        final uid = s['user_id']?.toString() ?? '';
        final tp = s['total_end_points'];
        final ec = s['end_card_count'];
        final pi = tp is num ? tp.toInt() : int.tryParse('$tp') ?? 0;
        final ci = ec is num ? ec.toInt() : int.tryParse('$ec') ?? 0;
        bump(uid, pi, ci, '');
      }
    }
    if (!fromScores) {
      final players = m['players'];
      if (players is List) {
        for (final p in players) {
          if (p is! Map) continue;
          final uid = p['user_id']?.toString() ?? '';
          final pts = p['points'];
          final pi = pts is num ? pts.toInt() : int.tryParse('$pts') ?? 0;
          final ncl = p['number_of_cards_left'];
          final ci = ncl is List ? ncl.length : (ncl is num ? ncl.toInt() : int.tryParse('$ncl') ?? 0);
          final un = p['username']?.toString() ?? '';
          bump(uid, pi, ci, un);
        }
      }
    }
  }

  final skipWinnersBecauseMerged = isSingleRoomLeague &&
      _latestCompletedMatchSameRoomMatchesWinners(
        matches: matches,
        currentGameId: currentGameId,
        orderedWinners: orderedWinners,
        keyForSession: keyForSession,
      );

  if (!skipWinnersBecauseMerged) {
    for (final w in orderedWinners) {
      final sid = w['playerId']?.toString() ?? '';
      final key = keyForSession(sid);
      final pts = w['points'];
      final cc = w['cardCount'];
      final pi = pts is num ? pts.toInt() : int.tryParse('$pts') ?? 0;
      final ci = cc is num ? cc.toInt() : int.tryParse('$cc') ?? 0;
      final name = w['playerName']?.toString() ?? 'Player';
      bump(key, pi, ci, name);
    }
  }

  if (aggs.isEmpty) return null;

  final entries = aggs.entries.toList()
    ..sort((a, b) {
      final c = a.value.points.compareTo(b.value.points);
      if (c != 0) return c;
      return a.value.cards.compareTo(b.value.cards);
    });

  final out = <TournamentLeaderboardRow>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final isYou = currentUserId.isNotEmpty && e.key == currentUserId;
    out.add(
      TournamentLeaderboardRow(
        rank: i + 1,
        displayName: isYou ? 'You' : e.value.name,
        totalPoints: e.value.points,
        totalCards: e.value.cards,
        isCurrentUser: isYou,
      ),
    );
  }
  return out;
}

/// Immutable payload for the game-ended modal only. The modal subtree must use **only**
/// this object — never [StateManager] — so later WS/state merges cannot change the UI.
class GameEndedModalData {
  const GameEndedModalData({
    required this.title,
    required this.content,
    required this.messageType,
    required this.showCloseButton,
    required this.autoClose,
    required this.autoCloseDelay,
    required this.orderedWinners,
    required this.isCurrentUserWinner,
    required this.currentUserId,
    required this.gameId,
    required this.showPlayAgain,
    required this.rematchGameStateSnapshot,
    this.gameTableLevel,
    this.isCoinRequired = true,
    this.tournamentLeaderboard,
  });

  final String title;
  final String content;
  final String messageType;
  final bool showCloseButton;
  final bool autoClose;
  final int autoCloseDelay;
  /// Deep-copied rows from `game_state.winners` at capture time.
  final List<Map<String, dynamic>> orderedWinners;
  final bool isCurrentUserWinner;
  /// Captured once with the snapshot (for "You" labels); not read from globals in the modal.
  final String currentUserId;

  /// Current room/game id (e.g. `room_…`) for `rematch` emit.
  final String gameId;

  /// When true, show "Play Again" (not random match; see [_shouldShowPlayAgain]).
  final bool showPlayAgain;

  /// Snapshot of `game_state` sent with `rematch` (JSON round-trip copy).
  final Map<String, dynamic> rematchGameStateSnapshot;

  /// Room table tier from `game_state.gameLevel` at capture time (null → treat as 1 for coin fee).
  final int? gameTableLevel;

  /// From `game_state.isCoinRequired`; when false, skip client coin pre-check before `rematch`.
  final bool isCoinRequired;

  /// Cumulative tournament standings (from `game_state.tournament_data.matches` + this hand), when in a tournament.
  final List<TournamentLeaderboardRow>? tournamentLeaderboard;

  /// Single read from [dutchGameState] when scheduling the modal — not used during modal build.
  static GameEndedModalData? fromDutchStateOnce(Map<String, dynamic> dutchGameState) {
    final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
    final isVisible = messagesData['isVisible'] == true;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';
    if (!isVisible || gamePhase != 'game_ended') return null;

    final title = messagesData['title']?.toString() ?? 'Game Message';
    final content = messagesData['content']?.toString() ?? '';
    final messageType = messagesData['type']?.toString() ?? 'info';
    final showCloseButton = messagesData['showCloseButton'] ?? true;
    final autoClose = messagesData['autoClose'] ?? false;
    final autoCloseDelay = messagesData['autoCloseDelay'] as int? ?? 3000;
    final isCurrentUserWinner = messagesData['isCurrentUserWinner'] == true;

    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>?;
    final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
    final gameState = gameData?['game_state'] as Map<String, dynamic>?;
    final glRaw = gameState?['gameLevel'];
    final int? gameTableLevel = glRaw is int
        ? glRaw
        : glRaw is num
            ? glRaw.toInt()
            : int.tryParse('${glRaw ?? ''}');
    final rawCoinReq = gameState?['isCoinRequired'];
    final isCoinRequired = rawCoinReq is bool ? rawCoinReq : true;
    final rematchSnap = _snapshotGameStateForRematch(gameState);
    final showPlayAgain = _shouldShowPlayAgain(gameState, gameData) &&
        currentGameId.isNotEmpty &&
        rematchSnap.isNotEmpty &&
        !currentGameId.startsWith('practice_room_') &&
        !currentGameId.startsWith('demo_game_') &&
        !_tournamentDataHidesPlayAgain(gameState);
    final orderedWinnersRaw = gameState?['winners'] as List<dynamic>?;
    final hasOrderedWinners = orderedWinnersRaw != null && orderedWinnersRaw.isNotEmpty;
    if (!hasOrderedWinners && content.isEmpty) return null;

    final deepWinners = <Map<String, dynamic>>[];
    if (orderedWinnersRaw != null) {
      for (final e in orderedWinnersRaw) {
        if (e is Map<String, dynamic>) {
          deepWinners.add(Map<String, dynamic>.from(e));
        } else if (e is Map) {
          deepWinners.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();

    final tournamentLeaderboard = _buildTournamentLeaderboardRows(
      gameState: gameState,
      orderedWinners: deepWinners,
      currentGameId: currentGameId,
      currentUserId: currentUserId,
    );

    return GameEndedModalData(
      title: title,
      content: content,
      messageType: messageType,
      showCloseButton: showCloseButton,
      autoClose: autoClose,
      autoCloseDelay: autoCloseDelay,
      orderedWinners: deepWinners,
      isCurrentUserWinner: isCurrentUserWinner,
      currentUserId: currentUserId,
      gameId: currentGameId,
      showPlayAgain: showPlayAgain,
      rematchGameStateSnapshot: rematchSnap,
      gameTableLevel: gameTableLevel,
      isCoinRequired: isCoinRequired,
      tournamentLeaderboard: tournamentLeaderboard,
    );
  }
}

// --- Modal styling helpers (no [StateManager]) ---

Color _modalMessageTypeColor(String messageType) {
  switch (messageType) {
    case 'success':
      return AppColors.successColor;
    case 'warning':
      return AppColors.warningColor;
    case 'error':
      return AppColors.errorColor;
    case 'info':
    default:
      return AppColors.infoColor;
  }
}

IconData _modalMessageTypeIcon(String messageType) {
  switch (messageType) {
    case 'success':
      return Icons.check_circle;
    case 'warning':
      return Icons.warning;
    case 'error':
      return Icons.error;
    case 'info':
    default:
      return Icons.info;
  }
}

/// Ordered standings — uses only [orderedWinners] and [currentUserId] from [GameEndedModalData].
Widget _tournamentLeaderboardSection(List<TournamentLeaderboardRow> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: AppPadding.defaultPadding.top),
      Text(
        'Tournament leaderboard',
        textAlign: TextAlign.center,
        style: AppTextStyles.label().copyWith(
          color: AppColors.matchPotGold,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      SizedBox(height: AppPadding.smallPadding.top),
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) SizedBox(height: AppPadding.smallPadding.top / 2),
        Builder(
          builder: (context) {
            final r = rows[i];
            final nameColor = r.isCurrentUser ? AppColors.accentColor : AppColors.white;
            final subColor = r.isCurrentUser ? AppColors.accentColor : AppColors.textSecondary;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${r.rank}.',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: subColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.displayName,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: nameColor,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${r.totalPoints} pts · ${r.totalCards} cards',
                  style: AppTextStyles.bodyMedium().copyWith(color: subColor, fontSize: 13),
                ),
              ],
            );
          },
        ),
      ],
    ],
  );
}

Widget _gameEndedOrderedWinnersColumn(
  List<Map<String, dynamic>> orderedWinners,
  String currentUserId,
) {
  String winTypeLabel(dynamic winType) {
    switch (winType?.toString()) {
      case 'four_of_a_kind':
        return 'Four of a Kind';
      case 'empty_hand':
        return 'No Cards Left';
      case 'lowest_points':
        return 'Lowest Points';
      case 'dutch':
        return 'Dutch Called';
      case 'last_player':
        return 'Last Player';
      default:
        return 'Winner';
    }
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < orderedWinners.length; i++) ...[
        if (i > 0) SizedBox(height: AppPadding.smallPadding.top),
        Builder(
          builder: (context) {
            final e = orderedWinners[i];
            final playerId = e['playerId']?.toString() ?? '';
            final name = e['playerName']?.toString() ?? 'Unknown';
            final winType = e['winType'];
            final points = e['points'] as int?;
            final cardCount = e['cardCount'] as int?;
            final isWinner = winType != null && winType.toString().isNotEmpty;
            final isCurrentUser = currentUserId.isNotEmpty && playerId == currentUserId;
            final displayName = isCurrentUser ? 'You' : name;
            final rowColor = isWinner
                ? AppColors.matchPotGold
                : (isCurrentUser ? AppColors.accentColor : AppColors.white);
            final secondaryColor = isWinner
                ? AppColors.matchPotGold
                : (isCurrentUser ? AppColors.accentColor : AppColors.textSecondary);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${i + 1}. ',
                  style: AppTextStyles.bodyMedium().copyWith(
                    color: secondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    displayName,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: rowColor,
                      fontWeight: isWinner ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  isWinner
                      ? ' (${winTypeLabel(winType)}) — ${points ?? 0} pts, ${cardCount ?? 0} cards'
                      : (points != null && cardCount != null
                          ? ' — $points pts, $cardCount cards'
                          : ''),
                  style: AppTextStyles.bodyMedium().copyWith(
                    color: secondaryColor,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ],
  );
}

/// Game-ended overlay: **only** [GameEndedModalData] — no reads from [StateManager].
class _GameEndedModalLayer extends StatefulWidget {
  const _GameEndedModalLayer({
    required this.data,
    required this.onClose,
  });

  final GameEndedModalData data;
  final VoidCallback onClose;

  @override
  State<_GameEndedModalLayer> createState() => _GameEndedModalLayerState();
}

class _GameEndedModalLayerState extends State<_GameEndedModalLayer> {
  @override
  void initState() {
    super.initState();
    if (widget.data.autoClose) {
      Future<void>.delayed(Duration(milliseconds: widget.data.autoCloseDelay), () {
        if (mounted) widget.onClose();
      });
    }
  }

  /// Emits WS `rematch` via [DutchGameEventEmitter] (same path as `play_card`, etc.).
  Future<void> _emitRematch(BuildContext context) async {
    final d = widget.data;
    try {
      if (d.isCoinRequired) {
        final effectiveLevel = d.gameTableLevel ?? 1;
        final ok = await DutchGameHelpers.checkCoinsRequirement(
          gameLevel: effectiveLevel,
          fetchFromAPI: true,
        );
        if (!ok) {
          if (!context.mounted) return;
          final required = LevelMatcher.tableLevelToCoinFee(effectiveLevel, defaultFee: 25);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Not enough coins for this table (need $required). Buy coins or play a lower table.',
                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
              ),
              backgroundColor: AppColors.errorColor,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      final payload = <String, dynamic>{
        'game_id': d.gameId,
        'game_state': d.rematchGameStateSnapshot,
      };
      if (d.currentUserId.isNotEmpty) {
        payload['user_id'] = d.currentUserId;
      }

      await DutchGameEventEmitter.instance.emit(
        eventType: 'rematch',
        data: payload,
      );
      if (!context.mounted) return;
      StateManager().updateModuleState('dutch_game', {
        'rematch_waiting_game_id': d.gameId,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rematch failed: $e',
            style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final messageTypeColor = _modalMessageTypeColor(d.messageType);
    final headerBackgroundColor = Color.lerp(
          AppColors.widgetContainerBackground,
          messageTypeColor,
          0.15,
        ) ??
        AppColors.widgetContainerBackground;
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);
    final hasRows = d.orderedWinners.isNotEmpty;

    return Material(
      color: AppColors.black.withValues(alpha: 0.54),
      child: Center(
        child: Container(
          margin: AppPadding.defaultPadding,
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: AppPadding.cardPadding,
                decoration: BoxDecoration(
                  color: headerBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _modalMessageTypeIcon(d.messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        d.title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (d.showCloseButton)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              if (hasRows && d.isCurrentUserWinner) _WinnerTrophyInModal(),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: hasRows
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _gameEndedOrderedWinnersColumn(d.orderedWinners, d.currentUserId),
                            if (d.tournamentLeaderboard != null && d.tournamentLeaderboard!.isNotEmpty)
                              _tournamentLeaderboardSection(d.tournamentLeaderboard!),
                          ],
                        )
                      : Text(
                          d.content,
                          style: AppTextStyles.bodyMedium().copyWith(
                            color: AppColors.white,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              if (d.showCloseButton)
                Container(
                  padding: AppPadding.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.cardVariant,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (d.showPlayAgain)
                        DutchSliceBuilder<String>(
                          selector: (dg) => dg['rematch_waiting_game_id']?.toString() ?? '',
                          builder: (context, waitingId, _) {
                            final waiting = waitingId.isNotEmpty && waitingId == d.gameId;
                            return Semantics(
                              label: waiting ? 'Waiting Rematch' : 'Play Again',
                              identifier: 'game_ended_play_again',
                              button: true,
                              child: TextButton.icon(
                                onPressed: waiting ? null : () => unawaited(_emitRematch(context)),
                                icon: waiting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.matchPotGold,
                                        ),
                                      )
                                    : Icon(
                                        Icons.replay,
                                        color: AppColors.matchPotGold,
                                      ),
                                label: Text(
                                  waiting ? 'Waiting Rematch' : 'Play Again',
                                  style: AppTextStyles.buttonText().copyWith(
                                    color: AppColors.matchPotGold,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.matchPotGold,
                                ),
                              ),
                            );
                          },
                        )
                      else
                        const SizedBox.shrink(),
                      TextButton.icon(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textOnCard,
                        ),
                        label: Text(
                          'Close',
                          style: AppTextStyles.buttonText().copyWith(
                            color: AppColors.textOnCard,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textOnCard,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Non-game-ended messages (e.g. match start) — plain title/body from caller.
class _GenericMessageModalLayer extends StatefulWidget {
  const _GenericMessageModalLayer({
    required this.title,
    required this.content,
    required this.messageType,
    required this.showCloseButton,
    required this.autoClose,
    required this.autoCloseDelay,
    required this.onClose,
  });

  final String title;
  final String content;
  final String messageType;
  final bool showCloseButton;
  final bool autoClose;
  final int autoCloseDelay;
  final VoidCallback onClose;

  @override
  State<_GenericMessageModalLayer> createState() => _GenericMessageModalLayerState();
}

class _GenericMessageModalLayerState extends State<_GenericMessageModalLayer> {
  @override
  void initState() {
    super.initState();
    if (widget.autoClose) {
      Future<void>.delayed(Duration(milliseconds: widget.autoCloseDelay), () {
        if (mounted) widget.onClose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messageTypeColor = _modalMessageTypeColor(widget.messageType);
    final headerBackgroundColor = Color.lerp(
          AppColors.widgetContainerBackground,
          messageTypeColor,
          0.15,
        ) ??
        AppColors.widgetContainerBackground;
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);

    return Material(
      color: AppColors.black.withValues(alpha: 0.54),
      child: Center(
        child: Container(
          margin: AppPadding.defaultPadding,
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: AppPadding.cardPadding,
                decoration: BoxDecoration(
                  color: headerBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _modalMessageTypeIcon(widget.messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (widget.showCloseButton)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: Text(
                    widget.content,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.white,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (widget.showCloseButton)
                Container(
                  padding: AppPadding.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.cardVariant,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textOnCard,
                        ),
                        label: Text(
                          'Close',
                          style: AppTextStyles.buttonText().copyWith(
                            color: AppColors.textOnCard,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textOnCard,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Messages Widget for Dutch Game
///
/// This widget displays game messages as a modal overlay.
/// It's hidden by default and only shows when messages are triggered.
/// Used for match notifications like "Match Starting", "Match Over", "Winner", "Points", etc.
///
/// Game-ended modal: [GameEndedModalData] is captured once from state; the modal subtree
/// is built only from that immutable object (no live [StateManager] reads).
class MessagesWidget extends StatefulWidget {
  const MessagesWidget({Key? key}) : super(key: key);

  @override
  State<MessagesWidget> createState() => _MessagesWidgetState();
}

class _MessagesWidgetState extends State<MessagesWidget> {
  static const bool LOGGING_SWITCH = false; // Enabled for winner modal debugging
  static final Logger _logger = Logger();

  /// Immutable snapshot — modal UI reads only this, never live state.
  GameEndedModalData? _gameEndedData;
  bool _snapshotSchedulePending = false;

  @override
  Widget build(BuildContext context) {
    return DutchSliceBuilder<Map<String, dynamic>>(
      selector: (dutchGameState) => {
        'messages': Map<String, dynamic>.from(
          dutchGameState['messages'] as Map<String, dynamic>? ?? {},
        ),
        'gamePhase': dutchGameState['gamePhase']?.toString() ?? '',
        'currentGameId': dutchGameState['currentGameId']?.toString() ?? '',
        'games': Map<String, dynamic>.from(
          dutchGameState['games'] as Map<String, dynamic>? ?? {},
        ),
      },
      builder: (context, slice, child) {
        final messagesData = slice['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] == true;
        final gamePhase = slice['gamePhase']?.toString() ?? '';

        if (_gameEndedData != null) {
          if (gamePhase != 'game_ended' || !isVisible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              StateManager().updateModuleState('dutch_game', {
                'rematch_waiting_game_id': '',
              });
              setState(() {
                _gameEndedData = null;
                _snapshotSchedulePending = false;
              });
            });
            return const SizedBox.shrink();
          }
          return _GameEndedModalLayer(
            data: _gameEndedData!,
            onClose: () => _closeMessage(context),
          );
        }

        if (isVisible && gamePhase == 'game_ended') {
          final content = messagesData['content']?.toString() ?? '';
          final currentGameId = slice['currentGameId']?.toString() ?? '';
          final games = slice['games'] as Map<String, dynamic>? ?? {};
          final currentGame = games[currentGameId] as Map<String, dynamic>?;
          final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
          final gameState = gameData?['game_state'] as Map<String, dynamic>?;
          final orderedWinners = gameState?['winners'] as List<dynamic>?;
          final hasOrderedWinners = orderedWinners != null && orderedWinners.isNotEmpty;
          if (!hasOrderedWinners && content.isEmpty) {
            return const SizedBox.shrink();
          }

          if (!_snapshotSchedulePending) {
            _snapshotSchedulePending = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final snap = GameEndedModalData.fromDutchStateOnce(
                StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {},
              );
              if (snap != null) {
                setState(() {
                  _gameEndedData = snap;
                  _snapshotSchedulePending = false;
                });
              } else {
                setState(() {
                  _snapshotSchedulePending = false;
                });
              }
            });
          }
          return const SizedBox.shrink();
        }

        if (!isVisible) {
          return const SizedBox.shrink();
        }

        final title = messagesData['title']?.toString() ?? 'Game Message';
        final content = messagesData['content']?.toString() ?? '';
        final messageType = messagesData['type']?.toString() ?? 'info';
        final showCloseButton = messagesData['showCloseButton'] ?? true;
        final autoClose = messagesData['autoClose'] ?? false;
        final autoCloseDelay = messagesData['autoCloseDelay'] ?? 3000;

        if (LOGGING_SWITCH) {
          final contentPreview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
          _logger.info('📬 MessagesWidget: Non-game-ended modal - title="$title", content="$contentPreview"');
        }

        return _GenericMessageModalLayer(
          title: title,
          content: content,
          messageType: messageType,
          showCloseButton: showCloseButton,
          autoClose: autoClose,
          autoCloseDelay: autoCloseDelay,
          onClose: () => _closeMessage(context),
        );
      },
    );
  }

  void _closeMessage(BuildContext context) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('MessagesWidget: Closing message modal');
      }

      final wasGameEnded = _gameEndedData != null ||
          StateManager().getModuleState<Map<String, dynamic>>('dutch_game')?['gamePhase']?.toString() ==
              'game_ended';

      setState(() {
        _gameEndedData = null;
        _snapshotSchedulePending = false;
      });

      StateManager().updateModuleState('dutch_game', {
        'rematch_waiting_game_id': '',
      });

      // Update state to hide messages
      StateManager().updateModuleState('dutch_game', {
        'messages': {
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': true,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
      });
      
      if (wasGameEnded) {
        NavigationManager().navigateTo('/dutch/lobby');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('MessagesWidget: Failed to close message: $e');
      }
    }
  }
}

/// Lottie celebration above the standings when the current user won (no static trophy icon).
class _WinnerTrophyInModal extends StatefulWidget {
  @override
  State<_WinnerTrophyInModal> createState() => _WinnerTrophyInModalState();
}

class _WinnerTrophyInModalState extends State<_WinnerTrophyInModal>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _entryScale;
  late Animation<double> _pulseScale;
  late Future<LottieComposition?> _compositionFuture;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _entryScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.elasticOut),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 1), weight: 1),
    ]).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _entryController.forward();
    _entryController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.repeat(reverse: true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _pulseController.stop();
        });
      }
    });
    _compositionFuture = _loadWinnerLottieSafe();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_entryController, _pulseController]),
          builder: (context, child) {
            final scale = _entryScale.value * (_entryController.isCompleted ? _pulseScale.value : 1);
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: SizedBox(
            width: 100,
            height: 100,
            child: FutureBuilder<LottieComposition?>(
              future: _compositionFuture,
              builder: (context, snapshot) {
                final composition = snapshot.data;
                if (snapshot.hasError || composition == null) {
                  return const SizedBox(width: 100, height: 100);
                }
                return Lottie(
                  composition: composition,
                  fit: BoxFit.contain,
                  repeat: true,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
