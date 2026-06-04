import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../backend_core/utils/rank_matcher.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';
import '../lobby_room/widgets/collapsible_section_widget.dart';

const int _kLeaderboardDisplayLimit = 20;

/// Route: `/dutch/leaderboard` — one bundle fetch; monthly/yearly/all-time; rank tier filtered on device.
class LeaderboardScreen extends BaseScreen {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Leaderboard';

  @override
  Decoration? getBackground(BuildContext context) {
    return const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/images/backgrounds/main-screens-background.webp'),
        fit: BoxFit.contain,
        alignment: Alignment.bottomRight,
      ),
    );
  }

  @override
  BaseScreenState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends BaseScreenState<LeaderboardScreen> {
  static const int _displayLimit = _kLeaderboardDisplayLimit;

  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _rawMonthly = [];
  List<Map<String, dynamic>> _rawYearly = [];
  List<Map<String, dynamic>> _rawAllTime = [];
  String _monthlyPeriodKey = '';
  String _yearlyPeriodKey = '';
  Map<String, dynamic>? _bundleViewer;
  bool _monthlyTruncated = false;
  bool _yearlyTruncated = false;
  bool _allTimeTruncated = false;
  /// `monthly` | `yearly` | `all_time` (client-side period scope).
  String _periodScope = 'monthly';
  /// `null` = all ranks (client-side filter only).
  String? _selectedRankTier;
  /// `null` = all game types; `classic` | `clear_and_collect` (server-filtered bundle).
  String? _selectedGameType;

  @override
  void initState() {
    super.initState();
    DutchGameHelpers.fetchPublicInitConfig();
    _load();
  }

  List<Map<String, dynamic>> _filteredAndRanked(List<Map<String, dynamic>> raw) {
    final tierLc = _selectedRankTier?.toLowerCase().trim();
    final filtered = <Map<String, dynamic>>[];
    if (tierLc == null || tierLc.isEmpty) {
      for (final r in raw) {
        filtered.add(Map<String, dynamic>.from(r));
      }
    } else {
      for (final r in raw) {
        final rt = (r['rank_tier'] ?? '').toString().toLowerCase();
        if (rt == tierLc) {
          filtered.add(Map<String, dynamic>.from(r));
        }
      }
    }
    final top = filtered.take(_displayLimit).toList();
    return List.generate(top.length, (i) {
      final m = Map<String, dynamic>.from(top[i]);
      m['rank'] = i + 1;
      return m;
    });
  }

  List<Map<String, dynamic>> get _visibleMonthly => _filteredAndRanked(_rawMonthly);
  List<Map<String, dynamic>> get _visibleYearly => _filteredAndRanked(_rawYearly);
  List<Map<String, dynamic>> get _visibleAllTime => _filteredAndRanked(_rawAllTime);
  List<Map<String, dynamic>> get _visibleRows {
    switch (_periodScope) {
      case 'yearly':
        return _visibleYearly;
      case 'all_time':
        return _visibleAllTime;
      default:
        return _visibleMonthly;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api == null) {
        _loadError = 'API not available';
        _rawMonthly = [];
        _rawYearly = [];
        _rawAllTime = [];
        _bundleViewer = null;
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await api.sendGetRequest(_leaderboardBundleUrl());
      _applyBundleResponse(response);
    } catch (e) {
      _loadError = e.toString();
      _rawMonthly = [];
      _rawYearly = [];
      _rawAllTime = [];
      _bundleViewer = null;
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _applyBundleResponse(dynamic response) {
    if (response is! Map || response['success'] != true) {
      _loadError =
          (response is Map ? response['error']?.toString() : null) ?? 'Failed to load leaderboard';
      _rawMonthly = [];
      _rawYearly = [];
      _rawAllTime = [];
      _bundleViewer = null;
      return;
    }
    _loadError = null;
    final m = response['monthly'];
    final y = response['yearly'];
    final at = response['all_time'];
    if (m is Map) {
      _monthlyPeriodKey = m['period_key']?.toString() ?? '';
      _monthlyTruncated = m['truncated'] == true;
      final rows = m['rows'];
      _rawMonthly = rows is List
          ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    } else {
      _rawMonthly = [];
    }
    if (y is Map) {
      _yearlyPeriodKey = y['period_key']?.toString() ?? '';
      _yearlyTruncated = y['truncated'] == true;
      final rows = y['rows'];
      _rawYearly = rows is List
          ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    } else {
      _rawYearly = [];
    }
    if (at is Map) {
      _allTimeTruncated = at['truncated'] == true;
      final rows = at['rows'];
      _rawAllTime = rows is List
          ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    } else {
      _rawAllTime = [];
    }
    final v = response['viewer'];
    _bundleViewer = v is Map ? Map<String, dynamic>.from(v) : null;
  }

  String _periodScopeLabel() {
    switch (_periodScope) {
      case 'yearly':
        return 'Yearly';
      case 'all_time':
        return 'All time';
      default:
        return 'Monthly';
    }
  }

  String _emptySpanLabel() {
    switch (_periodScope) {
      case 'yearly':
        return 'this year';
      case 'all_time':
        return 'all time';
      default:
        return 'this month';
    }
  }

  bool _truncatedForScope() {
    switch (_periodScope) {
      case 'yearly':
        return _yearlyTruncated;
      case 'all_time':
        return _allTimeTruncated;
      default:
        return _monthlyTruncated;
    }
  }

  String _leaderboardBundleUrl() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final uid = login['userId']?.toString() ?? login['user_id']?.toString() ?? '';
    final params = <String, String>{};
    if (uid.isNotEmpty) {
      params['user_id'] = uid;
    }
    final gt = _selectedGameType?.trim();
    if (gt != null && gt.isNotEmpty) {
      params['game_type'] = gt;
    }
    if (params.isEmpty) {
      return '/public/dutch/leaderboard-period-wins-bundle';
    }
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '/public/dutch/leaderboard-period-wins-bundle?$q';
  }

  void _onGameTypeChanged(String? gameType) {
    if (_selectedGameType == gameType) return;
    setState(() => _selectedGameType = gameType);
    _load();
  }

  String _gameTypeFilterSuffix() {
    switch (_selectedGameType) {
      case 'clear_and_collect':
        return ' · Clear and Collect';
      case 'classic':
        return ' · Classic';
      default:
        return '';
    }
  }

  /// Collapsed filter tab title — reflects current period, rank, and game type.
  String _filterSectionTitle() {
    final period = _periodScopeLabel();
    final game = _selectedGameType == 'classic'
        ? 'Classic'
        : (_selectedGameType == 'clear_and_collect'
            ? 'Clear and Collect'
            : 'All types');
    final rank = (_selectedRankTier == null || _selectedRankTier!.isEmpty)
        ? 'All ranks'
        : _capitalizeRank(_selectedRankTier!);
    return 'Filters · $period · $rank · $game';
  }

  String? _currentUserId() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return login['userId']?.toString() ?? login['user_id']?.toString();
  }

  String _capitalizeRank(String r) {
    if (r.isEmpty) return r;
    return '${r[0].toUpperCase()}${r.substring(1)}';
  }

  /// Current competitive rank from bundle viewer, then dutch_game userStats.
  String? _viewerRankTier() {
    final v = _bundleViewer;
    if (v != null) {
      for (final key in ['monthly', 'yearly', 'all_time']) {
        final ps = v[key];
        if (ps is Map) {
          final rt = (ps['rank_tier'] ?? '').toString().trim().toLowerCase();
          if (rt.isNotEmpty) return rt;
        }
      }
    }
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final stats = dutch['userStats'];
    if (stats is Map) {
      final rt = (stats['rank'] ?? '').toString().trim().toLowerCase();
      if (rt.isNotEmpty) return rt;
    }
    return null;
  }

  String _periodTitle() {
    final String base;
    switch (_periodScope) {
      case 'yearly':
        base = _yearlyPeriodKey.isEmpty
            ? 'This year (UTC)'
            : 'Year $_yearlyPeriodKey (UTC)';
        break;
      case 'all_time':
        base = 'All time';
        break;
      default:
        base = _monthlyPeriodKey.isEmpty
            ? 'This month (UTC)'
            : 'Month $_monthlyPeriodKey (UTC)';
    }
    final t = _selectedRankTier;
    final rankSuffix =
        (t == null || t.isEmpty) ? '' : ' · ${_capitalizeRank(t)} only';
    return '$base${_gameTypeFilterSuffix()}$rankSuffix';
  }

  String _emptyMessage() {
    final span = _emptySpanLabel();
    final gt = _selectedGameType;
    final modeLabel = gt == 'clear_and_collect'
        ? 'Clear and Collect'
        : (gt == 'classic' ? 'Classic' : null);
    final t = _selectedRankTier;
    if (modeLabel != null && t != null && t.isNotEmpty) {
      return 'No $modeLabel wins recorded $span for ${_capitalizeRank(t)} players yet.';
    }
    if (modeLabel != null) {
      return 'No $modeLabel wins recorded $span yet.';
    }
    if (t != null && t.isNotEmpty) {
      return 'No wins recorded $span for ${_capitalizeRank(t)} players yet.';
    }
    return 'No wins recorded $span yet.';
  }

  String? _truncationNote() {
    if (!_truncatedForScope()) return null;
    return 'Server list may be capped; some players beyond the cap are omitted.';
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentColor),
      );
    }

    final visibleRows = _visibleRows;
    final uid = _currentUserId();
    final viewerLine = _viewerLine(
      uid: uid,
      bundleViewer: _bundleViewer,
      periodKey: _periodScope,
      filteredRows: visibleRows,
      selectedTier: _selectedRankTier,
    );

    final periodBody = _PeriodLeaderboardBody(
      error: _loadError,
      rows: visibleRows,
      viewerLine: viewerLine,
      truncationNote: _truncationNote(),
      periodLabel: _periodTitle(),
      emptyMessage: _emptyMessage(),
      onRetry: _load,
    );

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Semantics(
              identifier: 'leaderboard_podium',
              child: Padding(
                padding: AppPadding.defaultPadding.copyWith(bottom: 8),
                child: _LeaderboardPodium(
                  rows: visibleRows,
                  periodError: _loadError,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Semantics(
              identifier: 'leaderboard_filters_collapsible',
              child: CollapsibleSectionWidget(
                title: _filterSectionTitle(),
                icon: Icons.tune,
                initiallyExpanded: false,
                compactHeader: true,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppPadding.defaultPadding.left,
                    4,
                    AppPadding.defaultPadding.right,
                    8,
                  ),
                  child: _LeaderboardFiltersPanel(
                    periodScope: _periodScope,
                    onPeriodScopeChanged: (scope) =>
                        setState(() => _periodScope = scope),
                    selectedGameType: _selectedGameType,
                    onGameTypeChanged: _onGameTypeChanged,
                    selectedRankTier: _selectedRankTier,
                    userRankTier: _viewerRankTier(),
                    onRankTierChanged: (tier) =>
                        setState(() => _selectedRankTier = tier),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppPadding.defaultPadding.copyWith(bottom: 8),
              child: _LeaderboardActionsRow(
                onHistory: () =>
                    NavigationManager().navigateTo('/dutch/leaderboard/history'),
                onAchievements: () =>
                    NavigationManager().navigateTo('/dutch/leaderboard/achievements'),
                onRefresh: _load,
              ),
            ),
          ),
          ...periodBody.buildSlivers(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// Resolve display name for a period-wins row (username or anonymized id tail).
String _displayNameFromPeriodRow(Map<String, dynamic> row) {
  final u = row['username']?.toString().trim();
  if (u != null && u.isNotEmpty) return u;
  final id = row['user_id']?.toString() ?? '';
  if (id.isNotEmpty) {
    final tail = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'Player $tail';
  }
  return 'Player';
}

int _periodPointsFromRow(Map<String, dynamic> row) {
  final v = row['period_points'];
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double? _avgWinSecondsFromRow(Map<String, dynamic> row) {
  final raw = row['avg_win_seconds'];
  if (raw is num) return raw.toDouble();
  final parsed = double.tryParse(raw?.toString() ?? '');
  if (parsed != null) return parsed;
  final wins = (row['wins'] as num?)?.toInt() ?? int.tryParse(row['wins']?.toString() ?? '') ?? 0;
  if (wins <= 0) return null;
  final pws = row['period_win_seconds'];
  final total = pws is num
      ? pws.toDouble()
      : double.tryParse(pws?.toString() ?? '');
  if (total == null) return null;
  return total / wins;
}

/// Wall-clock average win time as ``Xh Ym Zs`` (non-negative seconds).
String _formatDurationHrMinSec(num? totalSeconds) {
  var sec = (totalSeconds is num) ? totalSeconds.round() : 0;
  if (sec < 0) sec = 0;
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  return '${h}h ${m}m ${s}s';
}

/// Viewer subtitle from bundle ``viewer.monthly`` / ``viewer.yearly`` and client-filtered rows.
String? _viewerLine({
  required String? uid,
  required Map<String, dynamic>? bundleViewer,
  required String periodKey,
  required List<Map<String, dynamic>> filteredRows,
  required String? selectedTier,
}) {
  if (uid == null || uid.isEmpty || bundleViewer == null) return null;
  final ps = bundleViewer[periodKey];
  if (ps is! Map) return null;
  final stats = Map<String, dynamic>.from(ps);
  final winsInPeriod = (stats['wins'] as num?)?.toInt() ?? 0;
  final yrTier = stats['rank_tier']?.toString() ?? '';
  final inPeriod = stats['in_period'] == true;

  final idx = filteredRows.indexWhere((r) => r['user_id']?.toString() == uid);
  if (idx >= 0) {
    final w = filteredRows[idx]['wins'];
    return 'Your position: #${idx + 1} · $w wins';
  }

  final st = selectedTier?.toLowerCase().trim();
  if (st != null && st.isNotEmpty && winsInPeriod > 0) {
    if (yrTier.toLowerCase() != st) {
      return 'Your tier is $yrTier ($winsInPeriod wins this period); not on this rank board.';
    }
    return 'Your position: not in the top $_kLeaderboardDisplayLimit for this view.';
  }
  final noWinsMsg = periodKey == 'all_time'
      ? 'Your position: no wins recorded yet'
      : 'Your position: no wins in this period yet';
  if (!inPeriod && winsInPeriod <= 0) {
    return noWinsMsg;
  }
  if (winsInPeriod > 0) {
    return 'Your position: not in the top $_kLeaderboardDisplayLimit for this view.';
  }
  return noWinsMsg;
}

/// Top 3 for the active period (2nd – 1st – 3rd), aligned with list ordering from the API.
class _LeaderboardPodium extends StatelessWidget {
  const _LeaderboardPodium({
    required this.rows,
    required this.periodError,
  });

  final List<Map<String, dynamic>> rows;
  final String? periodError;

  @override
  Widget build(BuildContext context) {
    if (periodError != null) {
      return Center(
        child: Text(
          'Podium will show when rankings load.',
          style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    final r1 = rows.isNotEmpty ? rows[0] : null;
    final r2 = rows.length > 1 ? rows[1] : null;
    final r3 = rows.length > 2 ? rows[2] : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumPlace(place: 2, row: r2)),
        Expanded(child: _PodiumPlace(place: 1, row: r1)),
        Expanded(child: _PodiumPlace(place: 3, row: r3)),
      ],
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({
    required this.place,
    required this.row,
  });

  final int place;
  final Map<String, dynamic>? row;

  static const Color _silverTone = Color(0xFFB0BEC5);
  static const Color _bronzeTone = Color(0xFFA67C52);

  double get _pedestalHeight {
    switch (place) {
      case 1:
        return 56;
      case 2:
        return 44;
      case 3:
        return 32;
      default:
        return 40;
    }
  }

  Color get _iconColor {
    switch (place) {
      case 1:
        return AppColors.matchPotGold;
      case 2:
        return _silverTone;
      case 3:
        return _bronzeTone;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = row != null;
    final name = hasData ? _displayNameFromPeriodRow(row!) : '—';
    final wins = hasData ? (row!['wins']?.toString() ?? '0') : '';
    final periodPts = hasData ? _periodPointsFromRow(row!) : 0;
    final avgSec = hasData ? _avgWinSecondsFromRow(row!) : null;
    final avgTimeLabel =
        avgSec != null ? _formatDurationHrMinSec(avgSec) : null;
    final iconSize = place == 1 ? 36.0 : 28.0;
    final topPad = place == 1 ? 0.0 : 10.0;

    return Padding(
      padding: EdgeInsets.only(left: place == 2 ? 0 : 4, right: place == 3 ? 0 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Icon(
              Icons.emoji_events,
              size: iconSize,
              color: hasData ? _iconColor : AppColors.textSecondary.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall(color: AppColors.white).copyWith(
              fontWeight: place == 1 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (hasData && wins.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '$wins wins',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            Text(
              '$periodPts pts',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(color: AppColors.textTertiary),
            ),
            if (avgTimeLabel != null)
              Text(
                avgTimeLabel,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(color: AppColors.textTertiary),
              ),
          ],
          const SizedBox(height: 8),
          Container(
            height: _pedestalHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: AppColors.casinoBorderColor, width: 1),
              boxShadow: place == 1
                  ? [
                      BoxShadow(
                        color: AppColors.matchPotGold.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$place',
              style: AppTextStyles.headingSmall(
                color: hasData ? _iconColor : AppColors.textTertiary,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// History + refresh — below rank tier, above viewer position / list.
class _LeaderboardActionsRow extends StatelessWidget {
  const _LeaderboardActionsRow({
    required this.onHistory,
    required this.onAchievements,
    required this.onRefresh,
  });

  final VoidCallback onHistory;
  final VoidCallback onAchievements;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textOnPrimary,
      side: BorderSide(color: AppColors.casinoBorderColor),
      backgroundColor: AppColors.widgetContainerBackground,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                identifier: 'leaderboard_history',
                button: true,
                label: 'Leaderboard history',
                child: OutlinedButton.icon(
                  onPressed: onHistory,
                  style: buttonStyle,
                  icon: const Icon(Icons.history, size: 20),
                  label: Text(
                    'History',
                    style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                identifier: 'leaderboard_achievements',
                button: true,
                label: 'Achievement ranks',
                child: OutlinedButton.icon(
                  onPressed: onAchievements,
                  style: buttonStyle,
                  icon: const Icon(Icons.workspace_premium, size: 20),
                  label: Text(
                    'Achievements',
                    style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          identifier: 'leaderboard_refresh',
          button: true,
          label: 'Refresh leaderboard',
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              style: buttonStyle,
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(
                'Refresh',
                style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardChipOption {
  const _LeaderboardChipOption({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.semanticsIdentifier,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final String? semanticsIdentifier;
}

/// Label + horizontal chips (rank filter pattern).
class _LeaderboardFilterChipBar extends StatelessWidget {
  const _LeaderboardFilterChipBar({
    required this.label,
    required this.chips,
  });

  final String label;
  final List<_LeaderboardChipOption> chips;

  FilterChip _chip(_LeaderboardChipOption opt) {
    return FilterChip(
      label: Text(
        opt.label,
        style: AppTextStyles.bodySmall(
          color: opt.selected ? AppColors.textOnAccent : AppColors.textOnPrimary,
        ),
      ),
      selected: opt.selected,
      onSelected: (v) {
        if (v) opt.onSelect();
      },
      showCheckmark: false,
      selectedColor: AppColors.accentContrast,
      backgroundColor: AppColors.accentContrast.withValues(alpha: 0.28),
      side: BorderSide(
        color: opt.selected ? AppColors.accentColor : AppColors.casinoBorderColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++)
                Padding(
                  padding: EdgeInsets.only(right: i < chips.length - 1 ? 6 : 0),
                  child: chips[i].semanticsIdentifier != null
                      ? Semantics(
                          identifier: chips[i].semanticsIdentifier,
                          button: true,
                          label: chips[i].label,
                          child: _chip(chips[i]),
                        )
                      : _chip(chips[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Period, game type, and rank filters — uniform label + chip rows.
class _LeaderboardFiltersPanel extends StatelessWidget {
  const _LeaderboardFiltersPanel({
    required this.periodScope,
    required this.onPeriodScopeChanged,
    required this.selectedGameType,
    required this.onGameTypeChanged,
    required this.selectedRankTier,
    required this.userRankTier,
    required this.onRankTierChanged,
  });

  final String periodScope;
  final ValueChanged<String> onPeriodScopeChanged;
  final String? selectedGameType;
  final ValueChanged<String?> onGameTypeChanged;
  final String? selectedRankTier;
  final String? userRankTier;
  final ValueChanged<String?> onRankTierChanged;

  String _capitalize(String r) {
    if (r.isEmpty) return r;
    return '${r[0].toUpperCase()}${r.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final tiers = RankMatcher.rankHierarchy;
    final yours = userRankTier?.toLowerCase().trim();
    final otherTiers = yours == null || yours.isEmpty
        ? tiers
        : tiers.where((t) => t.toLowerCase() != yours).toList();

    final rankChips = <_LeaderboardChipOption>[
      _LeaderboardChipOption(
        label: 'All',
        selected: selectedRankTier == null,
        onSelect: () => onRankTierChanged(null),
        semanticsIdentifier: 'leaderboard_rank_tier_all',
      ),
      if (yours != null && yours.isNotEmpty)
        _LeaderboardChipOption(
          label: 'Your rank: ${_capitalize(yours)}',
          selected: selectedRankTier == yours,
          onSelect: () => onRankTierChanged(yours),
          semanticsIdentifier: 'leaderboard_rank_yours',
        ),
      for (final tier in otherTiers)
        _LeaderboardChipOption(
          label: _capitalize(tier),
          selected: selectedRankTier == tier,
          onSelect: () => onRankTierChanged(tier),
          semanticsIdentifier: 'leaderboard_rank_tier_$tier',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LeaderboardFilterChipBar(
          label: 'Period',
          chips: [
            _LeaderboardChipOption(
              label: 'Monthly',
              selected: periodScope == 'monthly',
              onSelect: () => onPeriodScopeChanged('monthly'),
              semanticsIdentifier: 'leaderboard_period_monthly',
            ),
            _LeaderboardChipOption(
              label: 'Yearly',
              selected: periodScope == 'yearly',
              onSelect: () => onPeriodScopeChanged('yearly'),
              semanticsIdentifier: 'leaderboard_period_yearly',
            ),
            _LeaderboardChipOption(
              label: 'All time',
              selected: periodScope == 'all_time',
              onSelect: () => onPeriodScopeChanged('all_time'),
              semanticsIdentifier: 'leaderboard_period_all_time',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LeaderboardFilterChipBar(
          label: 'Game type',
          chips: [
            _LeaderboardChipOption(
              label: 'All',
              selected: selectedGameType == null,
              onSelect: () => onGameTypeChanged(null),
              semanticsIdentifier: 'leaderboard_game_type_all',
            ),
            _LeaderboardChipOption(
              label: 'Classic',
              selected: selectedGameType == 'classic',
              onSelect: () => onGameTypeChanged('classic'),
              semanticsIdentifier: 'leaderboard_game_type_classic',
            ),
            _LeaderboardChipOption(
              label: 'Clear and Collect',
              selected: selectedGameType == 'clear_and_collect',
              onSelect: () => onGameTypeChanged('clear_and_collect'),
              semanticsIdentifier: 'leaderboard_game_type_clear_and_collect',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LeaderboardFilterChipBar(
          label: 'Rank',
          chips: rankChips,
        ),
      ],
    );
  }
}

class _PeriodLeaderboardBody {
  const _PeriodLeaderboardBody({
    required this.error,
    required this.rows,
    required this.viewerLine,
    required this.truncationNote,
    required this.periodLabel,
    required this.emptyMessage,
    required this.onRetry,
  });

  final String? error;
  final List<Map<String, dynamic>> rows;
  final String? viewerLine;
  final String? truncationNote;
  final String periodLabel;
  final String emptyMessage;
  final Future<void> Function() onRetry;

  /// List section slivers for the parent [CustomScrollView] (not a nested scroll view).
  List<Widget> buildSlivers() {
    if (error != null) {
      return [
        SliverPadding(
          padding: AppPadding.defaultPadding,
          sliver: SliverToBoxAdapter(
            child: DutchEmptyStateCard(
              title: 'Leaderboard unavailable',
              message: error!,
              variant: DutchEmptyStateVariant.error,
              actionLabel: 'Retry',
              onAction: () => onRetry(),
              semanticIdentifier: 'leaderboard_error',
            ),
          ),
        ),
      ];
    }

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _PeriodLeaderboardHeader(
          periodLabel: periodLabel,
          truncationNote: truncationNote,
          viewerLine: viewerLine,
        ),
      ),
    ];

    if (rows.isEmpty) {
      children.addAll([
        const SizedBox(height: 16),
        DutchEmptyStateCard(
          message: emptyMessage,
          icon: Icons.emoji_events_outlined,
          semanticIdentifier: 'leaderboard_empty',
        ),
      ]);
    } else {
      for (var i = 0; i < rows.length; i++) {
        if (i == 0) {
          children.add(const SizedBox(height: 4));
        } else {
          children.add(const SizedBox(height: 6));
        }
        children.add(_LeaderboardRankRow(row: rows[i]));
      }
    }

    return [
      SliverPadding(
        padding: AppPadding.defaultPadding,
        sliver: SliverList(delegate: SliverChildListDelegate(children)),
      ),
    ];
  }
}

class _PeriodLeaderboardHeader extends StatelessWidget {
  const _PeriodLeaderboardHeader({
    required this.periodLabel,
    required this.truncationNote,
    required this.viewerLine,
  });

  final String periodLabel;
  final String? truncationNote;
  final String? viewerLine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          periodLabel,
          style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
        ),
        if (truncationNote != null) ...[
          const SizedBox(height: 4),
          Text(
            truncationNote!,
            style: AppTextStyles.caption(color: AppColors.textTertiary),
          ),
        ],
        if (viewerLine != null) ...[
          const SizedBox(height: 6),
          Semantics(
            identifier: 'leaderboard_viewer_position',
            label: viewerLine!,
            child: Text(
              viewerLine!,
              style: AppTextStyles.bodyMedium(color: AppColors.white),
            ),
          ),
        ],
      ],
    );
  }
}

class _LeaderboardRankRow extends StatelessWidget {
  const _LeaderboardRankRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final rank = row['rank']?.toString() ?? '';
    final rankNum = int.tryParse(rank);
    final isFirstPlace = rankNum == 1;
    final name = _displayNameFromPeriodRow(row);
    final wins = row['wins']?.toString() ?? '0';
    final periodPts = _periodPointsFromRow(row);
    final avgSec = _avgWinSecondsFromRow(row);
    final avgTimeLabel = avgSec != null ? _formatDurationHrMinSec(avgSec) : '—';
    final statColor = isFirstPlace
        ? AppColors.matchPotGold
        : AppColors.white.withValues(alpha: 0.72);
    final statCaption = AppTextStyles.caption(color: AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: isFirstPlace
            ? AppColors.matchPotGold.withValues(alpha: 0.14)
            : AppColors.accentContrast.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFirstPlace
              ? AppColors.matchPotGold
              : AppColors.accentContrast.withValues(alpha: 0.45),
          width: isFirstPlace ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          if (rank.isNotEmpty)
            SizedBox(
              width: isFirstPlace ? 52 : 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFirstPlace) ...[
                    Icon(Icons.emoji_events, size: 18, color: AppColors.matchPotGold),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '#$rank',
                    style: AppTextStyles.bodyMedium(
                      color: isFirstPlace
                          ? AppColors.matchPotGold
                          : AppColors.white.withValues(alpha: 0.88),
                    ).copyWith(
                      fontWeight: isFirstPlace ? FontWeight.w800 : FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.bodyMedium(
                color: isFirstPlace
                    ? AppColors.white
                    : AppColors.white.withValues(alpha: 0.92),
              ).copyWith(
                fontWeight: isFirstPlace ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$wins wins',
                style: AppTextStyles.bodyMedium(color: statColor).copyWith(
                  fontWeight: isFirstPlace ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text('$periodPts pts', style: statCaption),
              Text(avgTimeLabel, style: statCaption),
            ],
          ),
        ],
      ),
    );
  }
}

