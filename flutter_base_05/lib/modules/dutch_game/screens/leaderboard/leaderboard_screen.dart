import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';

/// Enable for leaderboard testing (period-wins + snapshot history). See `.cursor/rules/enable-logging-switch.mdc`.
const bool LOGGING_SWITCH = false;

/// Route: `/dutch/leaderboard` — live period wins + optional snapshot history from public Dutch endpoints.
class LeaderboardScreen extends BaseScreen {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Leaderboard';

  @override
  Decoration? getBackground(BuildContext context) {
    return BoxDecoration(
      color: AppColors.scaffoldBackgroundColor,
      image: const DecorationImage(
        image: AssetImage('assets/images/backgrounds/leaderboard-screen-background_002.jpg'),
        fit: BoxFit.contain,
        alignment: Alignment.bottomRight,
      ),
    );
  }

  @override
  BaseScreenState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends BaseScreenState<LeaderboardScreen> {
  final Logger _logger = Logger();

  bool _loading = true;
  String? _monthlyError;
  String? _yearlyError;
  List<Map<String, dynamic>> _monthlyRows = [];
  List<Map<String, dynamic>> _yearlyRows = [];
  String _monthlyPeriodKey = '';
  String _yearlyPeriodKey = '';
  Map<String, dynamic>? _monthlyViewer;
  Map<String, dynamic>? _yearlyViewer;
  int _tabIndex = 0;

  bool _historyOpen = false;
  bool _historyLoading = false;
  String? _historyError;
  List<Map<String, String>> _historyMonthlyFlat = [];
  List<Map<String, String>> _historyYearlyFlat = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (LOGGING_SWITCH) {
      _logger.info('LeaderboardScreen: loading period-wins (monthly+yearly, limit 20)', isOn: LOGGING_SWITCH);
    }
    setState(() {
      _loading = true;
      _monthlyError = null;
      _yearlyError = null;
    });
    try {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api == null) {
        _monthlyError = 'API not available';
        _yearlyError = 'API not available';
        _monthlyRows = [];
        _yearlyRows = [];
        if (mounted) setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        api.sendGetRequest(_periodWinsUrl('monthly')),
        api.sendGetRequest(_periodWinsUrl('yearly')),
      ]);
      _applyResponse(results[0], isMonthly: true);
      _applyResponse(results[1], isMonthly: false);
      if (LOGGING_SWITCH) {
        _logger.info(
          'LeaderboardScreen: period-wins ok monthly_rows=${_monthlyRows.length} yearly_rows=${_yearlyRows.length} '
          'month_key=$_monthlyPeriodKey year_key=$_yearlyPeriodKey',
          isOn: LOGGING_SWITCH,
        );
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('LeaderboardScreen: load error', error: e, isOn: LOGGING_SWITCH);
      }
      final msg = e.toString();
      _monthlyError ??= msg;
      _yearlyError ??= msg;
      _monthlyRows = [];
      _yearlyRows = [];
      _monthlyViewer = null;
      _yearlyViewer = null;
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
    if (mounted && _historyOpen) {
      await _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (LOGGING_SWITCH) {
      _logger.info('LeaderboardScreen: loading snapshot history (monthly+yearly leaderboards)', isOn: LOGGING_SWITCH);
    }
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api == null) {
        _historyError = 'API not available';
        _historyMonthlyFlat = [];
        _historyYearlyFlat = [];
        if (mounted) setState(() => _historyLoading = false);
        return;
      }
      final results = await Future.wait([
        api.sendGetRequest('/public/dutch/leaderboards?leaderboard_type=monthly&limit=20'),
        api.sendGetRequest('/public/dutch/leaderboards?leaderboard_type=yearly&limit=20'),
      ]);
      final mOk = results[0] is Map && (results[0] as Map)['success'] == true;
      final yOk = results[1] is Map && (results[1] as Map)['success'] == true;
      if (mOk && yOk) {
        _historyMonthlyFlat = _flattenSnapshotLeaderboards((results[0] as Map)['leaderboards']);
        _historyYearlyFlat = _flattenSnapshotLeaderboards((results[1] as Map)['leaderboards']);
        _historyError = null;
        if (LOGGING_SWITCH) {
          _logger.info(
            'LeaderboardScreen: history ok flat_monthly=${_historyMonthlyFlat.length} flat_yearly=${_historyYearlyFlat.length}',
            isOn: LOGGING_SWITCH,
          );
        }
      } else {
        final err = (results[0] is Map ? (results[0] as Map)['error']?.toString() : null) ??
            (results[1] is Map ? (results[1] as Map)['error']?.toString() : null) ??
            'Failed to load history';
        _historyError = err;
        _historyMonthlyFlat = [];
        _historyYearlyFlat = [];
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('LeaderboardScreen: history load error', error: e, isOn: LOGGING_SWITCH);
      }
      _historyError = e.toString();
      _historyMonthlyFlat = [];
      _historyYearlyFlat = [];
    }
    if (mounted) {
      setState(() {
        _historyLoading = false;
      });
    }
  }

  List<Map<String, String>> _flattenSnapshotLeaderboards(dynamic raw) {
    final list = raw is List ? raw : const [];
    final rows = <Map<String, String>>[];
    for (final item in list) {
      final m = Map<String, dynamic>.from(item as Map);
      final dateLabel = _formatSnapshotDate(m['date_time']?.toString());
      for (final w in (m['winners'] as List?) ?? const []) {
        final wm = Map<String, dynamic>.from(w as Map);
        final un = wm['username']?.toString() ?? '';
        final uid = wm['user_id']?.toString() ?? '';
        rows.add({'username': un, 'date': dateLabel, 'user_id': uid});
      }
    }
    return rows;
  }

  /// Snapshot `date_time` from API (ISO); show YYYY-MM-DD for readability.
  String _formatSnapshotDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final l = d.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final mo = l.month.toString().padLeft(2, '0');
    final day = l.day.toString().padLeft(2, '0');
    return '$y-$mo-$day';
  }

  void _applyResponse(dynamic response, {required bool isMonthly}) {
    if (response is Map && response['success'] == true) {
      final raw = response['rows'];
      final list = raw is List ? raw : const [];
      final rows = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pk = response['period_key']?.toString() ?? '';
      final viewerRaw = response['viewer'];
      final viewer = viewerRaw is Map ? Map<String, dynamic>.from(viewerRaw) : null;
      if (isMonthly) {
        _monthlyRows = rows;
        _monthlyPeriodKey = pk;
        _monthlyError = null;
        _monthlyViewer = viewer;
      } else {
        _yearlyRows = rows;
        _yearlyPeriodKey = pk;
        _yearlyError = null;
        _yearlyViewer = viewer;
      }
    } else {
      final err = (response is Map ? response['error']?.toString() : null) ?? 'Failed to load leaderboard';
      if (isMonthly) {
        _monthlyRows = [];
        _monthlyError = err;
        _monthlyViewer = null;
      } else {
        _yearlyRows = [];
        _yearlyError = err;
        _yearlyViewer = null;
      }
    }
  }

  /// Public period-wins API; optional `user_id` for `viewer` block (no JWT).
  String _periodWinsUrl(String period) {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final uid = login['userId']?.toString() ?? login['user_id']?.toString() ?? '';
    if (uid.isEmpty) {
      return '/public/dutch/leaderboard-period-wins?period=$period&limit=20';
    }
    return '/public/dutch/leaderboard-period-wins?period=$period&limit=20&user_id=${Uri.encodeQueryComponent(uid)}';
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'leaderboard_podium',
          child: Padding(
            padding: AppPadding.defaultPadding.copyWith(bottom: 8),
            child: _LeaderboardPodium(
              rows: _tabIndex == 0 ? _monthlyRows : _yearlyRows,
              periodError: _tabIndex == 0 ? _monthlyError : _yearlyError,
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
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.accentColor,
                  onRefresh: _load,
                  child: _tabIndex == 0
                      ? _PeriodLeaderboardBody(
                          error: _monthlyError,
                          rows: _monthlyRows,
                          viewer: _monthlyViewer,
                          periodLabel: _monthlyPeriodKey.isEmpty ? 'This month (UTC)' : 'Month $_monthlyPeriodKey (UTC)',
                          emptyMessage: 'No wins recorded this month yet.',
                          onRetry: _load,
                        )
                      : _PeriodLeaderboardBody(
                          error: _yearlyError,
                          rows: _yearlyRows,
                          viewer: _yearlyViewer,
                          periodLabel: _yearlyPeriodKey.isEmpty ? 'This year (UTC)' : 'Year $_yearlyPeriodKey (UTC)',
                          emptyMessage: 'No wins recorded this year yet.',
                          onRetry: _load,
                        ),
                ),
              ),
              Semantics(
                label: 'leaderboard_history_section',
                identifier: 'leaderboard_history_section',
                child: Material(
                  color: AppColors.surface,
                  elevation: 1,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: AppColors.casinoBorderColor),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      backgroundColor: AppColors.surface,
                      collapsedBackgroundColor: AppColors.surface,
                      iconColor: AppColors.primaryColor,
                      collapsedIconColor: AppColors.primaryColor,
                      onExpansionChanged: (open) {
                        setState(() => _historyOpen = open);
                        if (open) {
                          _loadHistory();
                        }
                      },
                      title: Text(
                        'History',
                        style: AppTextStyles.headingSmall(color: AppColors.primaryColor),
                      ),
                      subtitle: Text(
                        'Past monthly & yearly winners',
                        style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                      ),
                      children: [
                        if (_historyLoading)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(color: AppColors.accentColor),
                            ),
                          )
                        else if (_historyError != null)
                          Padding(
                            padding: AppPadding.defaultPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _historyError!,
                                  style: AppTextStyles.bodyMedium(color: AppColors.errorColor),
                                ),
                                TextButton(
                                  onPressed: _loadHistory,
                                  style: TextButton.styleFrom(foregroundColor: AppColors.accentColor),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            height: 280,
                            child: ListView(
                              padding: AppPadding.defaultPadding,
                              children: [
                                Text(
                                  'Monthly',
                                  style: AppTextStyles.label(color: AppColors.primaryColor),
                                ),
                                const SizedBox(height: 8),
                                if (_historyMonthlyFlat.isEmpty)
                                  Text(
                                    'No monthly snapshots yet.',
                                    style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                                  )
                                else
                                  ..._historyMonthlyFlat.map(_historyUsernameDateRow),
                                const SizedBox(height: 16),
                                Text(
                                  'Yearly',
                                  style: AppTextStyles.label(color: AppColors.primaryColor),
                                ),
                                const SizedBox(height: 8),
                                if (_historyYearlyFlat.isEmpty)
                                  Text(
                                    'No yearly snapshots yet.',
                                    style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                                  )
                                else
                                  ..._historyYearlyFlat.map(_historyUsernameDateRow),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyUsernameDateRow(Map<String, String> row) {
    final name = _displayNameFromHistoryRow(row);
    final date = row['date'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.bodyMedium(color: AppColors.textOnCard),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            date,
            style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Text on list row cards: [AppColors.textOnCard] (rank #1 name uses [AppColors.white]).
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

String _displayNameFromHistoryRow(Map<String, String> row) {
  final u = row['username']?.trim();
  if (u != null && u.isNotEmpty) return u;
  final id = row['user_id']?.trim() ?? '';
  if (id.isNotEmpty) {
    final tail = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'Player $tail';
  }
  return 'Player';
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

class _PeriodTabBar extends StatelessWidget {
  const _PeriodTabBar({
    required this.tabIndex,
    required this.onChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TabSegment(
            label: 'Monthly',
            selected: tabIndex == 0,
            onTap: () => onChanged(0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TabSegment(
            label: 'Yearly',
            selected: tabIndex == 1,
            onTap: () => onChanged(1),
          ),
        ),
      ],
    );
  }
}

class _TabSegment extends StatelessWidget {
  const _TabSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryColor.withValues(alpha: 0.2) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryColor : AppColors.casinoBorderColor,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.bodyLarge(
              color: selected ? AppColors.primaryColor : AppColors.textOnCard,
            ).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
          ),
        ),
      ),
    );
  }
}

/// One-line copy for API `viewer` block from [get_period_wins_leaderboard_public].
String? _viewerPositionLine(Map<String, dynamic>? viewer) {
  if (viewer == null) return null;
  if (viewer['in_period'] == false) {
    return 'Your position: no wins in this period yet';
  }
  final rank = viewer['rank'];
  final wins = viewer['wins'];
  if (rank == null) return null;
  return 'Your position: #$rank · $wins wins';
}

class _PeriodLeaderboardBody extends StatelessWidget {
  const _PeriodLeaderboardBody({
    required this.error,
    required this.rows,
    required this.viewer,
    required this.periodLabel,
    required this.emptyMessage,
    required this.onRetry,
  });

  final String? error;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? viewer;
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
          Text(error!, style: AppTextStyles.bodyMedium(color: AppColors.errorColor)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => onRetry(),
            style: TextButton.styleFrom(foregroundColor: AppColors.accentColor),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final viewerLine = _viewerPositionLine(viewer);
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
        children: [
          Text(
            periodLabel,
            style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
          ),
          if (viewerLine != null) ...[
            const SizedBox(height: 6),
            Semantics(
              identifier: 'leaderboard_viewer_position',
              label: viewerLine,
              child: Text(
                viewerLine,
                style: AppTextStyles.bodyMedium(color: AppColors.white),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              emptyMessage,
              style: AppTextStyles.bodyLarge(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
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
          final line = _viewerPositionLine(viewer);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodLabel,
                  style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                ),
                if (line != null) ...[
                  const SizedBox(height: 6),
                  Semantics(
                    identifier: 'leaderboard_viewer_position',
                    label: line,
                    child: Text(
                      line,
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
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFirstPlace ? AppColors.matchPotGold : AppColors.casinoBorderColor,
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
                          color: isFirstPlace ? AppColors.matchPotGold : AppColors.primaryColor,
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
                    color: isFirstPlace ? AppColors.white : AppColors.textOnCard,
                  ).copyWith(
                    fontWeight: isFirstPlace ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                '$wins wins',
                style: AppTextStyles.bodyMedium(
                  color: isFirstPlace ? AppColors.matchPotGold : AppColors.textSecondary,
                ).copyWith(fontWeight: isFirstPlace ? FontWeight.w600 : FontWeight.normal),
              ),
            ],
          ),
        );
      },
    );
  }
}
