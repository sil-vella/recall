import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../utils/consts/config.dart';
import '../../../backend_core/utils/level_matcher.dart';
import '../../../managers/dutch_event_handler_callbacks.dart';
import '../../../managers/validated_event_emitter.dart';
import '../../../utils/dutch_game_helpers.dart';
import '../../../utils/game_ended_modal_pin.dart';
import '../../../widgets/dutch_slice_builder.dart';
import '../../../widgets/ui_kit/dutch_animated_cta_button.dart';
import '../../../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// Decoder for .lottie (dotlottie zip) assets: picks the first .json animation.
Future<LottieComposition?> _decodeDotLottie(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        final name = f.name.toLowerCase();
        if (name.endsWith('.json') && !name.endsWith('manifest.json')) {
          return f;
        }
      }
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

/// `special_events[].metadata.end_match_modal` from live [game_state], or catalog fallback via [special_event_id].
Map<String, dynamic>? _resolvedSpecialEventEndModal(Map<String, dynamic>? gameState) {
  if (gameState == null) return null;
  final raw = gameState['special_event_end_match_modal'];
  if (raw is Map && raw.isNotEmpty) {
    return Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
  }
  final seId = gameState['special_event_id']?.toString().trim();
  if (seId == null || seId.isEmpty) return null;
  return LevelMatcher.endMatchModalSnapshotForSpecialEventId(seId);
}

String? _resolveEndMatchModalBackgroundUrl(
  Map<String, dynamic> modal, {
  String? eventId,
}) {
  final url = modal['background_image_url']?.toString().trim();
  if (url != null && url.isNotEmpty) return url;
  final file = modal['background_image_file']?.toString().trim();
  if (file == null || file.isEmpty) return null;
  final eid = eventId?.trim();
  if (eid == null || eid.isEmpty) return null;
  final base = Config.apiUrl.replaceAll(RegExp(r'/$'), '');
  return '$base/app_media/media/event_media/${Uri.encodeComponent(eid)}/${Uri.encodeComponent(file)}';
}

void _navigateEndMatchModalCta(Map<String, dynamic> cta, VoidCallback onClose) {
  final dest =
      (cta['redirect_to_screen'] ?? cta['redirectToScreen'] ?? '').toString().trim().toLowerCase();
  switch (dest) {
    case 'achievements':
      NavigationManager().navigateTo('/dutch/achievements');
      break;
    default:
      break;
  }
  onClose();
}

/// Show "Play Again" when not a random game:
/// prefer `is_random_game` on game_state or gameData; else treat `is_random_join` as random.
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
    this.specialEventEndMatchModal,
    this.specialEventId,
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

  /// Catalog / server snapshot: `special_events[].metadata.end_match_modal` (hero text, optional art, CTA).
  final Map<String, dynamic>? specialEventEndMatchModal;

  /// `game_state.special_event_id` at capture time (for event_media URL fallback).
  final String? specialEventId;

  /// Single read from [dutchGameState] when scheduling the modal — not used during modal build.
  static GameEndedModalData? fromDutchStateOnce(Map<String, dynamic> dutchGameState) {
    final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
    final isVisible = messagesData['isVisible'] == true;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';
    final endGameModalOpen = dutchGameState['endGameModalOpen'] == true;
    final pinned = GameEndedModalPin.readRaw();
    if (pinned != null) {
      return fromJson(pinned);
    }
    if (!endGameModalOpen && (!isVisible || gamePhase != 'game_ended')) {
      return null;
    }

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
    final specialEventEndModal = _resolvedSpecialEventEndModal(gameState);
    final specialEventId = gameState?['special_event_id']?.toString().trim();
    final specialHeroText = specialEventEndModal?['text']?.toString().trim() ?? '';
    final specialHeroBg = specialEventEndModal != null
        ? _resolveEndMatchModalBackgroundUrl(
            specialEventEndModal,
            eventId: specialEventId,
          )
        : null;
    final hasSpecialEndUi =
        specialHeroText.isNotEmpty || (specialHeroBg != null && specialHeroBg.isNotEmpty);

    if (!hasOrderedWinners && content.isEmpty && !hasSpecialEndUi) return null;

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
      specialEventEndMatchModal: specialEventEndModal,
      specialEventId: (specialEventId != null && specialEventId.isNotEmpty) ? specialEventId : null,
    );
  }

  /// JSON snapshot for [GameEndedModalPin] — detached from live game state after capture.
  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'messageType': messageType,
        'showCloseButton': showCloseButton,
        'autoClose': autoClose,
        'autoCloseDelay': autoCloseDelay,
        'orderedWinners': orderedWinners.map(Map<String, dynamic>.from).toList(),
        'isCurrentUserWinner': isCurrentUserWinner,
        'currentUserId': currentUserId,
        'gameId': gameId,
        'showPlayAgain': showPlayAgain,
        'rematchGameStateSnapshot':
            Map<String, dynamic>.from(rematchGameStateSnapshot),
        'gameTableLevel': gameTableLevel,
        'isCoinRequired': isCoinRequired,
        'tournamentLeaderboard': tournamentLeaderboard
            ?.map(
              (r) => {
                'rank': r.rank,
                'displayName': r.displayName,
                'totalPoints': r.totalPoints,
                'totalCards': r.totalCards,
                'isCurrentUser': r.isCurrentUser,
              },
            )
            .toList(),
        'specialEventEndMatchModal': specialEventEndMatchModal != null
            ? Map<String, dynamic>.from(specialEventEndMatchModal!)
            : null,
        'specialEventId': specialEventId,
      };

  static GameEndedModalData? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final winnersRaw = json['orderedWinners'];
    final winners = <Map<String, dynamic>>[];
    if (winnersRaw is List) {
      for (final e in winnersRaw) {
        if (e is Map<String, dynamic>) {
          winners.add(Map<String, dynamic>.from(e));
        } else if (e is Map) {
          winners.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    List<TournamentLeaderboardRow>? tournamentRows;
    final lbRaw = json['tournamentLeaderboard'];
    if (lbRaw is List) {
      tournamentRows = [];
      for (final e in lbRaw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v)));
        tournamentRows.add(
          TournamentLeaderboardRow(
            rank: (m['rank'] as num?)?.toInt() ?? 0,
            displayName: m['displayName']?.toString() ?? '',
            totalPoints: (m['totalPoints'] as num?)?.toInt() ?? 0,
            totalCards: (m['totalCards'] as num?)?.toInt() ?? 0,
            isCurrentUser: m['isCurrentUser'] == true,
          ),
        );
      }
    }
    final se = json['specialEventEndMatchModal'];
    return GameEndedModalData(
      title: json['title']?.toString() ?? 'Game Ended',
      content: json['content']?.toString() ?? '',
      messageType: json['messageType']?.toString() ?? 'success',
      showCloseButton: json['showCloseButton'] != false,
      autoClose: json['autoClose'] == true,
      autoCloseDelay: (json['autoCloseDelay'] as num?)?.toInt() ?? 3000,
      orderedWinners: winners,
      isCurrentUserWinner: json['isCurrentUserWinner'] == true,
      currentUserId: json['currentUserId']?.toString() ?? '',
      gameId: json['gameId']?.toString() ?? '',
      showPlayAgain: json['showPlayAgain'] == true,
      rematchGameStateSnapshot: json['rematchGameStateSnapshot'] is Map
          ? Map<String, dynamic>.from(
              (json['rematchGameStateSnapshot'] as Map).map(
                (k, v) => MapEntry(k.toString(), v),
              ),
            )
          : const {},
      gameTableLevel: (json['gameTableLevel'] as num?)?.toInt(),
      isCoinRequired: json['isCoinRequired'] != false,
      tournamentLeaderboard: tournamentRows,
      specialEventEndMatchModal: se is Map
          ? Map<String, dynamic>.from(se.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      specialEventId: json['specialEventId']?.toString(),
    );
  }

  static void pinToModuleState(GameEndedModalData data) {
    GameEndedModalPin.write(data.toJson());
  }

  static GameEndedModalData? readPinned() {
    return fromJson(GameEndedModalPin.readRaw());
  }

  static void clearPinned() {
    GameEndedModalPin.clear();
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

Widget? _specialEventEndMatchHero(
  Map<String, dynamic> modal, {
  String? eventId,
  bool showWinnerLottie = false,
}) {
  final text = modal['text']?.toString().trim() ?? '';
  final bgUrl = _resolveEndMatchModalBackgroundUrl(modal, eventId: eventId);
  final hasBg = bgUrl != null && bgUrl.isNotEmpty;
  if (text.isEmpty && !hasBg && !showWinnerLottie) return null;

  if (hasBg) {
    final heroHeight = showWinnerLottie ? 190.0 : 140.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.network(
            bgUrl,
            height: heroHeight,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: heroHeight,
              color: AppColors.cardVariant,
            ),
          ),
          Container(
            height: heroHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.black.withValues(alpha: 0.3),
                  AppColors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          Padding(
            padding: AppPadding.smallPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showWinnerLottie) ...[
                  const _WinnerLottieCelebration(size: 76),
                  if (text.isNotEmpty) SizedBox(height: AppPadding.smallPadding.top * 0.35),
                ],
                if (text.isNotEmpty)
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      shadows: const [
                        Shadow(
                          color: AppColors.black,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  if (showWinnerLottie) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _WinnerLottieCelebration(),
        if (text.isNotEmpty) ...[
          SizedBox(height: AppPadding.smallPadding.top * 0.5),
          Padding(
            padding: AppPadding.smallPadding,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium().copyWith(
                color: AppColors.matchPotGold,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  return Padding(
    padding: AppPadding.smallPadding,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTextStyles.bodyMedium().copyWith(
        color: AppColors.matchPotGold,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    ),
  );
}

bool _isWinnerOnlySpecialEventText(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('you won');
}

/// Game-ended overlay: **only** [GameEndedModalData] — no reads from [StateManager].
class _GameEndedModalLayer extends StatefulWidget {
  const _GameEndedModalLayer({
    required this.data,
    required this.onClose,
    required this.onDismissOverlay,
  });

  final GameEndedModalData data;
  final VoidCallback onClose;
  /// Close overlay only — stay on game-play (Play Again / rematch accept).
  final VoidCallback onDismissOverlay;

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
      final loginUserId = DutchEventHandlerCallbacks.getCurrentLoginUserId();
      if (loginUserId.isNotEmpty) {
        payload['user_id'] = loginUserId;
      }

      if (LOGGING_SWITCH) {
        customlog(
          'rematch: playAgain emit gameId=${d.gameId} userId=$loginUserId '
          'roster=${DutchEventHandlerCallbacks.dutchGameRosterLog(d.gameId)}',
        );
      }

      await DutchGameEventEmitter.instance.emit(
        eventType: 'rematch',
        data: payload,
      );
      if (!context.mounted) return;
      StateManager().updateModuleState('dutch_game', {
        'rematch_waiting_game_id': d.gameId,
      });
      if (LOGGING_SWITCH) {
        final dg =
            StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        customlog(
          'rematch: playAgain overlayDismiss gameId=${d.gameId} '
          'gamePhase=${dg['gamePhase']} rematchWaiting=${dg['rematch_waiting_game_id']} '
          'roster=${DutchEventHandlerCallbacks.dutchGameRosterLog(d.gameId)}',
        );
      }
      widget.onDismissOverlay();
    } catch (e) {
      if (LOGGING_SWITCH) {
        customlog('rematch: playAgain emit failed gameId=${d.gameId} error=$e');
      }
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
    final endModal = d.specialEventEndMatchModal;
    final showWinnerLottieInHero =
        hasRows && d.isCurrentUserWinner && endModal != null;
    Map<String, dynamic>? effectiveEndModal = endModal;
    if (endModal != null && !d.isCurrentUserWinner) {
      final heroText = endModal['text']?.toString() ?? '';
      if (_isWinnerOnlySpecialEventText(heroText)) {
        effectiveEndModal = Map<String, dynamic>.from(endModal);
        effectiveEndModal['text'] = '';
      }
    }
    final heroWidget = effectiveEndModal != null
        ? _specialEventEndMatchHero(
            effectiveEndModal,
            eventId: d.specialEventId,
            showWinnerLottie: showWinnerLottieInHero,
          )
        : null;
    final showStandaloneWinnerLottie =
        hasRows && d.isCurrentUserWinner && !showWinnerLottieInHero;
    Map<String, dynamic>? ctaMap;
    final ctaRaw = endModal?['cta_text'];
    if (ctaRaw is Map) {
      ctaMap = Map<String, dynamic>.from(ctaRaw.map((k, v) => MapEntry(k.toString(), v)));
    }
    final ctaLabel = ctaMap?['text']?.toString().trim() ?? '';

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
              if (showStandaloneWinnerLottie) _WinnerTrophyInModal(),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: hasRows
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (heroWidget != null) ...[
                              heroWidget,
                              SizedBox(height: AppPadding.smallPadding.top),
                            ],
                            _gameEndedOrderedWinnersColumn(d.orderedWinners, d.currentUserId),
                            if (d.tournamentLeaderboard != null && d.tournamentLeaderboard!.isNotEmpty)
                              _tournamentLeaderboardSection(d.tournamentLeaderboard!),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (heroWidget != null) ...[
                              heroWidget,
                              SizedBox(height: AppPadding.smallPadding.top),
                            ],
                            if (d.content.trim().isNotEmpty)
                              Text(
                                d.content,
                                style: AppTextStyles.bodyMedium().copyWith(
                                  color: AppColors.white,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ctaMap != null && ctaLabel.isNotEmpty)
                        DutchAnimatedCtaButton(
                          label: ctaLabel,
                          variant: DutchCtaVariant.primary,
                          expand: true,
                          semanticIdentifier: 'game_ended_special_event_cta',
                          onPressed: () =>
                              _navigateEndMatchModalCta(ctaMap!, widget.onClose),
                        ),
                      if (d.showPlayAgain) ...[
                        if (ctaMap != null && ctaLabel.isNotEmpty)
                          SizedBox(height: AppPadding.smallPadding.top),
                        DutchSliceBuilder<String>(
                          selector: (dg) =>
                              dg['rematch_waiting_game_id']?.toString() ?? '',
                          builder: (context, waitingId, _) {
                            final waiting =
                                waitingId.isNotEmpty && waitingId == d.gameId;
                            return DutchAnimatedCtaButton(
                              label: waiting ? 'Waiting Rematch' : 'Play Again',
                              variant: DutchCtaVariant.secondary,
                              expand: true,
                              leadingIcon: waiting ? null : Icons.replay,
                              semanticIdentifier: 'game_ended_play_again',
                              onPressed: waiting
                                  ? null
                                  : () => unawaited(_emitRematch(context)),
                            );
                          },
                        ),
                      ],
                      if ((ctaMap != null && ctaLabel.isNotEmpty) || d.showPlayAgain)
                        SizedBox(height: AppPadding.smallPadding.top),
                      DutchAnimatedCtaButton(
                        label: 'Close',
                        variant: DutchCtaVariant.secondary,
                        expand: true,
                        leadingIcon: Icons.close,
                        semanticIdentifier: 'game_ended_close',
                        onPressed: widget.onClose,
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
                  child: DutchAnimatedCtaButton(
                    label: 'Close',
                    variant: DutchCtaVariant.secondary,
                    expand: true,
                    leadingIcon: Icons.close,
                    semanticIdentifier: 'game_message_close',
                    onPressed: widget.onClose,
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
  /// Immutable snapshot — modal UI reads only this, never live state.
  GameEndedModalData? _gameEndedData;
  bool _snapshotSchedulePending = false;

  @override
  void initState() {
    super.initState();
    _gameEndedData = GameEndedModalData.readPinned();
  }

  void _applyPinnedSnapshot(GameEndedModalData data) {
    _gameEndedData = data;
    GameEndedModalData.pinToModuleState(data);
  }

  GameEndedModalData? _activeEndedModal() {
    final pinned = GameEndedModalData.readPinned();
    final dutch =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final open = dutch['endGameModalOpen'] == true;
    if (!open && pinned == null) return null;
    return pinned ?? _gameEndedData;
  }

  void _dismissGameEndedOverlay({required bool navigateToLobby}) {
    setState(() {
      _gameEndedData = null;
      _snapshotSchedulePending = false;
    });
    GameEndedModalPin.dismissOverlay(navigateToLobby: navigateToLobby);
  }

  bool _shouldLeaveToLobbyOnClose() {
    final dutch =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final waiting = dutch['rematch_waiting_game_id']?.toString() ?? '';
    return waiting.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return DutchSliceBuilder<bool>(
      selector: (dg) =>
          dg['endGameModalOpen'] == true || GameEndedModalPin.readRaw() != null,
      builder: (context, modalPinned, _) {
        final active = _activeEndedModal();
        if (active != null) {
          if (_gameEndedData == null) {
            _gameEndedData = active;
          }
          return _GameEndedModalLayer(
            data: active,
            onClose: () => _dismissGameEndedOverlay(
              navigateToLobby: _shouldLeaveToLobbyOnClose(),
            ),
            onDismissOverlay: () =>
                _dismissGameEndedOverlay(navigateToLobby: false),
          );
        }

        if (_gameEndedData != null || _snapshotSchedulePending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_gameEndedData != null || _snapshotSchedulePending) {
              setState(() {
                _gameEndedData = null;
                _snapshotSchedulePending = false;
              });
            }
          });
        }

        return _buildNonGameEndedMessages(context);
      },
    );
  }

  Widget _buildNonGameEndedMessages(BuildContext context) {
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
        'endGameModalOpen': dutchGameState['endGameModalOpen'] == true,
      },
      builder: (context, slice, child) {
        final messagesData = slice['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] == true;
        final gamePhase = slice['gamePhase']?.toString() ?? '';
        final endGameModalOpen = slice['endGameModalOpen'] == true;

        final shouldCaptureEndModal = endGameModalOpen ||
            (isVisible && gamePhase == 'game_ended');
        if (shouldCaptureEndModal) {
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

          final dutch =
              StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final immediate = GameEndedModalData.fromDutchStateOnce(dutch);
          if (immediate != null) {
            _applyPinnedSnapshot(immediate);
            return _GameEndedModalLayer(
              data: immediate,
              onClose: () => _dismissGameEndedOverlay(
                navigateToLobby: _shouldLeaveToLobbyOnClose(),
              ),
              onDismissOverlay: () =>
                  _dismissGameEndedOverlay(navigateToLobby: false),
            );
          }

          if (!_snapshotSchedulePending) {
            _snapshotSchedulePending = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final snap = GameEndedModalData.fromDutchStateOnce(
                StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {},
              );
              if (snap != null) {
                _applyPinnedSnapshot(snap);
                setState(() {
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

        

        return _GenericMessageModalLayer(
          title: title,
          content: content,
          messageType: messageType,
          showCloseButton: showCloseButton,
          autoClose: autoClose,
          autoCloseDelay: autoCloseDelay,
          onClose: () => _dismissGameEndedOverlay(navigateToLobby: false),
        );
      },
    );
  }
}

/// Embeddable winner Lottie (special-event hero or standalone trophy row).
class _WinnerLottieCelebration extends StatefulWidget {
  const _WinnerLottieCelebration({this.size = 90});

  final double size;

  @override
  State<_WinnerLottieCelebration> createState() => _WinnerLottieCelebrationState();
}

class _WinnerLottieCelebrationState extends State<_WinnerLottieCelebration>
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
    final box = widget.size;
    return AnimatedBuilder(
      animation: Listenable.merge([_entryController, _pulseController]),
      builder: (context, child) {
        final scale = _entryScale.value * (_entryController.isCompleted ? _pulseScale.value : 1);
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: SizedBox(
        width: box,
        height: box,
        child: FutureBuilder<LottieComposition?>(
          future: _compositionFuture,
          builder: (context, snapshot) {
            final composition = snapshot.data;
            if (snapshot.hasError || composition == null) {
              return SizedBox(width: box, height: box);
            }
            return Lottie(
              composition: composition,
              fit: BoxFit.contain,
              repeat: true,
            );
          },
        ),
      ),
    );
  }
}

/// Lottie celebration above the standings when the current user won (non–special-event).
class _WinnerTrophyInModal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
      child: const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: 4),
          child: _WinnerLottieCelebration(),
        ),
      ),
    );
  }
}
