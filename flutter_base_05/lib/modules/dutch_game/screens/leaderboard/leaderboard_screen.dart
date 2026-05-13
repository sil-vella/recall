import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../backend_core/utils/rank_matcher.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';

const int _kLeaderboardDisplayLimit = 20;

/// Enable for leaderboard testing (period-wins). See `.cursor/rules/enable-logging-switch.mdc`.

/// Route: `/dutch/leaderboard` — one bundle fetch; monthly/yearly and rank tier filtered on device.
class LeaderboardScreen extends BaseScreen {
  const LeaderboardScreen({Key? key}) : super(key: key);

  /// Set by [_LeaderboardScreenState] so the app bar refresh action can call [_LeaderboardScreenState._load].
  static VoidCallback? refreshCallback;

  @override
  String computeTitle(BuildContext context) => 'Leaderboard';

  @override
  List<Widget>? getAppBarActions(BuildContext context) {
    return [
      Semantics(
        identifier: 'leaderboard_history',
        button: true,
        label: 'Leaderboard history',
        child: IconButton(
          icon: const Icon(Icons.history, color: AppColors.white),
          tooltip: 'History',
          onPressed: () => NavigationManager().navigateTo('/dutch/leaderboard/history'),
        ),
      ),
      Semantics(
        identifier: 'leaderboard_refresh',
        button: true,
        label: 'Refresh leaderboard',
        child: IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.white),
          tooltip: 'Refresh',
          onPressed: () => LeaderboardScreen.refreshCallback?.call(),
        ),
      ),
    ];
  }

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
  String _monthlyPeriodKey = '';
  String _yearlyPeriodKey = '';
  Map<String, dynamic>? _bundleViewer;
  bool _monthlyTruncated = false;
  bool _yearlyTruncated = false;
  int _tabIndex = 0;
  /// `null` = all ranks (client-side filter only).
  String? _selectedRankTier;

  @override
  void initState() {
    super.initState();
    LeaderboardScreen.refreshCallback = _load;
    _load();
  }

  @override
  void dispose() {
    LeaderboardScreen.refreshCallback = null;
    super.dispose();
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
      _bundleViewer = null;
      return;
    }
    _loadError = null;
    final m = response['monthly'];
    final y = response['yearly'];
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
    final v = response['viewer'];
    _bundleViewer = v is Map ? Map<String, dynamic>.from(v) : null;
  }

  String _leaderboardBundleUrl() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final uid = login['userId']?.toString() ?? login['user_id']?.toString() ?? '';
    if (uid.isEmpty) {
      return '/public/dutch/leaderboard-period-wins-bundle';
    }
    return '/public/dutch/leaderboard-period-wins-bundle?user_id=${Uri.encodeQueryComponent(uid)}';
  }

  String? _currentUserId() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return login['userId']?.toString() ?? login['user_id']?.toString();
  }

  String _capitalizeRank(String r) {
    if (r.isEmpty) return r;
    return '${r[0].toUpperCase()}${r.substring(1)}';
  }

  String _monthlyPeriodTitle() {
    final base =
        _monthlyPeriodKey.isEmpty ? 'This month (UTC)' : 'Month $_monthlyPeriodKey (UTC)';
    final t = _selectedRankTier;
    if (t == null || t.isEmpty) return base;
    return '$base · ${_capitalizeRank(t)} only';
  }

  String _yearlyPeriodTitle() {
    final base = _yearlyPeriodKey.isEmpty ? 'This year (UTC)' : 'Year $_yearlyPeriodKey (UTC)';
    final t = _selectedRankTier;
    if (t == null || t.isEmpty) return base;
    return '$base · ${_capitalizeRank(t)} only';
  }

  String _emptyMessageMonthly() {
    final t = _selectedRankTier;
    if (t == null || t.isEmpty) return 'No wins recorded this month yet.';
    return 'No wins recorded this month for ${_capitalizeRank(t)} players yet.';
  }

  String _emptyMessageYearly() {
    final t = _selectedRankTier;
    if (t == null || t.isEmpty) return 'No wins recorded this year yet.';
    return 'No wins recorded this year for ${_capitalizeRank(t)} players yet.';
  }

  String? _truncationNote(bool monthly) {
    final t = monthly ? _monthlyTruncated : _yearlyTruncated;
    if (!t) return null;
    return 'Server list may be capped; some players beyond the cap are omitted.';
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentColor),
      );
    }

    final monthlyRows = _visibleMonthly;
    final yearlyRows = _visibleYearly;
    final uid = _currentUserId();
    final monthlyViewerLine = _viewerLine(
      uid: uid,
      bundleViewer: _bundleViewer,
      periodKey: 'monthly',
      filteredRows: monthlyRows,
      selectedTier: _selectedRankTier,
    );
    final yearlyViewerLine = _viewerLine(
      uid: uid,
      bundleViewer: _bundleViewer,
      periodKey: 'yearly',
      filteredRows: yearlyRows,
      selectedTier: _selectedRankTier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'leaderboard_podium',
          child: Padding(
            padding: AppPadding.defaultPadding.copyWith(bottom: 8),
            child: _LeaderboardPodium(
              rows: _tabIndex == 0 ? monthlyRows : yearlyRows,
              periodError: _loadError,
            ),
          ),
        ),
        Padding(
          padding: AppPadding.defaultPadding.copyWith(bottom: 8),
          child: _PeriodTabBar(
            tabIndex: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),
        Padding(
          padding: AppPadding.defaultPadding.copyWith(bottom: 8),
          child: _RankTierChipBar(
            selectedTier: _selectedRankTier,
            onTierChanged: (tier) => setState(() => _selectedRankTier = tier),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accentColor,
            onRefresh: _load,
            child: _tabIndex == 0
                ? _PeriodLeaderboardBody(
                    error: _loadError,
                    rows: monthlyRows,
                    viewerLine: monthlyViewerLine,
                    truncationNote: _truncationNote(true),
                    periodLabel: _monthlyPeriodTitle(),
                    emptyMessage: _emptyMessageMonthly(),
                    onRetry: _load,
                  )
                : _PeriodLeaderboardBody(
                    error: _loadError,
                    rows: yearlyRows,
                    viewerLine: yearlyViewerLine,
                    truncationNote: _truncationNote(false),
                    periodLabel: _yearlyPeriodTitle(),
                    emptyMessage: _emptyMessageYearly(),
                    onRetry: _load,
                  ),
          ),
        ),
      ],
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
  if (!inPeriod && winsInPeriod <= 0) {
    return 'Your position: no wins in this period yet';
  }
  if (winsInPeriod > 0) {
    return 'Your position: not in the top $_kLeaderboardDisplayLimit for this view.';
  }
  return 'Your position: no wins in this period yet';
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

/// Monthly / Yearly toggle — deep plum track; active = full light plum, inactive = low-opacity plum.
class _PeriodTabBar extends StatelessWidget {
  const _PeriodTabBar({
    required this.tabIndex,
    required this.onChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final inactivePlum = AppColors.accentContrast.withValues(alpha: 0.28);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldDeepPlumColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardVariant,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(0),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: tabIndex == 0 ? AppColors.accentContrast : inactivePlum,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Monthly',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: tabIndex == 0
                          ? AppColors.white
                          : AppColors.white.withValues(alpha: 0.45),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(1),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: tabIndex == 1 ? AppColors.accentContrast : inactivePlum,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Yearly',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: tabIndex == 1
                          ? AppColors.white
                          : AppColors.white.withValues(alpha: 0.45),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodLeaderboardBody extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
        children: [
          DutchEmptyStateCard(
            title: 'Leaderboard unavailable',
            message: error!,
            variant: DutchEmptyStateVariant.error,
            actionLabel: 'Retry',
            onAction: () => onRetry(),
            semanticIdentifier: 'leaderboard_error',
          ),
        ],
      );
    }
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
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
          const SizedBox(height: 16),
          DutchEmptyStateCard(
            message: emptyMessage,
            icon: Icons.emoji_events_outlined,
            semanticIdentifier: 'leaderboard_empty',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppPadding.defaultPadding,
      itemCount: rows.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 4) : const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
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
            ),
          );
        }
        final row = rows[index - 1];
        final rank = row['rank']?.toString() ?? '';
        final rankNum = int.tryParse(rank);
        final isFirstPlace = rankNum == 1;
        final name = _displayNameFromPeriodRow(row);
        final wins = row['wins']?.toString() ?? '0';
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
              Text(
                '$wins wins',
                style: AppTextStyles.bodyMedium(
                  color: isFirstPlace
                      ? AppColors.matchPotGold
                      : AppColors.white.withValues(alpha: 0.72),
                ).copyWith(fontWeight: isFirstPlace ? FontWeight.w600 : FontWeight.normal),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RankTierChipBar extends StatelessWidget {
  const _RankTierChipBar({
    required this.selectedTier,
    required this.onTierChanged,
  });

  final String? selectedTier;
  final ValueChanged<String?> onTierChanged;

  @override
  Widget build(BuildContext context) {
    final tiers = RankMatcher.rankHierarchy;
    final inactiveBorder = AppColors.casinoBorderColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rank tier',
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  identifier: 'leaderboard_rank_tier_all',
                  button: true,
                  label: 'All ranks',
                  child: FilterChip(
                    label: Text('All', style: AppTextStyles.bodySmall(color: AppColors.white)),
                    selected: selectedTier == null,
                    onSelected: (v) {
                      if (v) onTierChanged(null);
                    },
                    showCheckmark: false,
                    selectedColor: AppColors.accentContrast,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: inactiveBorder),
                  ),
                ),
              ),
              for (final tier in tiers)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    identifier: 'leaderboard_rank_tier_$tier',
                    button: true,
                    label: 'Rank $tier',
                    child: FilterChip(
                      label: Text(
                        tier.isEmpty ? tier : '${tier[0].toUpperCase()}${tier.substring(1)}',
                        style: AppTextStyles.bodySmall(color: AppColors.white),
                      ),
                      selected: selectedTier == tier,
                      onSelected: (v) {
                        if (v) onTierChanged(tier);
                      },
                      showCheckmark: false,
                      selectedColor: AppColors.accentContrast,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: inactiveBorder),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
