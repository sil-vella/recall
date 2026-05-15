import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';
import '../../widgets/ui_kit/dutch_section_header.dart';

/// Hall of fame: counts how many completed months / years each user finished tied for #1 wins.
class _HallEntry {
  _HallEntry({
    required this.userId,
    required this.username,
    required this.monthlyTitles,
    required this.yearlyTitles,
  });

  final String userId;
  String username;
  int monthlyTitles;
  int yearlyTitles;

  int get totalTitles => monthlyTitles + yearlyTitles;
}

/// Route `/dutch/leaderboard/history` — one bundle fetch with ``history_months`` / ``history_years``;
/// all-time tallies computed on the client from those lists (plus current month/year top ties).
class LeaderboardHistoryScreen extends BaseScreen {
  const LeaderboardHistoryScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Leaderboard history';

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
  BaseScreenState<LeaderboardHistoryScreen> createState() => _LeaderboardHistoryScreenState();
}

class _LeaderboardHistoryScreenState extends BaseScreenState<LeaderboardHistoryScreen> {
  static const int _historyMonths = 36;
  static const int _historyYears = 10;
  static const int _bundleMaxEntries = 80;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _monthlyHistory = [];
  List<Map<String, dynamic>> _yearlyHistory = [];
  List<Map<String, dynamic>> _currentMonthRows = [];
  List<Map<String, dynamic>> _currentYearRows = [];
  String _currentMonthKey = '';
  String _currentYearKey = '';
  List<_HallEntry> _hall = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _bundleUrl() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final uid = login['userId']?.toString() ?? login['user_id']?.toString() ?? '';
    final base =
        '/public/dutch/leaderboard-period-wins-bundle?max_entries=$_bundleMaxEntries'
        '&history_months=$_historyMonths&history_years=$_historyYears';
    if (uid.isEmpty) return base;
    return '$base&user_id=${Uri.encodeQueryComponent(uid)}';
  }

  List<Map<String, dynamic>> _tiedTopWinners(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return [];
    var maxW = 0;
    for (final r in rows) {
      final w = (r['wins'] as num?)?.toInt() ?? 0;
      if (w > maxW) maxW = w;
    }
    if (maxW <= 0) return [];
    return rows
        .where((r) => ((r['wins'] as num?)?.toInt() ?? 0) == maxW)
        .map((r) => {
              'user_id': r['user_id']?.toString() ?? '',
              'username': r['username']?.toString() ?? '',
              'wins': (r['wins'] as num?)?.toInt() ?? 0,
            })
        .toList();
  }

  void _applyHallTallies(
    Map<String, _HallEntry> byId,
    List<Map<String, dynamic>> periods, {
    required bool isMonthly,
  }) {
    for (final p in periods) {
      final winners = p['winners'];
      if (winners is! List) continue;
      for (final w in winners) {
        if (w is! Map) continue;
        final m = Map<String, dynamic>.from(w);
        final id = m['user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final un = m['username']?.toString() ?? '';
        byId.putIfAbsent(
          id,
          () => _HallEntry(userId: id, username: un, monthlyTitles: 0, yearlyTitles: 0),
        );
        final e = byId[id]!;
        if (un.isNotEmpty) e.username = un;
        if (isMonthly) {
          e.monthlyTitles += 1;
        } else {
          e.yearlyTitles += 1;
        }
      }
    }
  }

  void _rebuildHallOfFame(
    List<Map<String, dynamic>> monthlyHist,
    List<Map<String, dynamic>> yearlyHist,
    List<Map<String, dynamic>> curMonthRows,
    List<Map<String, dynamic>> curYearRows,
  ) {
    final byId = <String, _HallEntry>{};
    _applyHallTallies(byId, monthlyHist, isMonthly: true);
    _applyHallTallies(byId, yearlyHist, isMonthly: false);

    void countCurrent(List<Map<String, dynamic>> rows, {required bool isMonthly}) {
      for (final w in _tiedTopWinners(rows)) {
        final id = w['user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final un = w['username']?.toString() ?? '';
        byId.putIfAbsent(
          id,
          () => _HallEntry(userId: id, username: un, monthlyTitles: 0, yearlyTitles: 0),
        );
        final e = byId[id]!;
        if (un.isNotEmpty) e.username = un;
        if (isMonthly) {
          e.monthlyTitles += 1;
        } else {
          e.yearlyTitles += 1;
        }
      }
    }

    countCurrent(curMonthRows, isMonthly: true);
    countCurrent(curYearRows, isMonthly: false);

    final list = byId.values.toList()
      ..sort((a, b) {
        final c = b.totalTitles.compareTo(a.totalTitles);
        if (c != 0) return c;
        final cm = b.monthlyTitles.compareTo(a.monthlyTitles);
        if (cm != 0) return cm;
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });
    _hall = list;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api == null) {
        _error = 'API not available';
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await api.sendGetRequest(_bundleUrl());
      if (response is! Map || response['success'] != true) {
        _error =
            (response is Map ? response['error']?.toString() : null) ?? 'Failed to load history';
        if (mounted) setState(() => _loading = false);
        return;
      }
      final mh = response['monthly_history'];
      _monthlyHistory = mh is List
          ? mh.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      final yh = response['yearly_history'];
      _yearlyHistory = yh is List
          ? yh.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];

      final curM = response['monthly'];
      if (curM is Map) {
        _currentMonthKey = curM['period_key']?.toString() ?? '';
        final rows = curM['rows'];
        _currentMonthRows = rows is List
            ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      } else {
        _currentMonthRows = [];
      }
      final curY = response['yearly'];
      if (curY is Map) {
        _currentYearKey = curY['period_key']?.toString() ?? '';
        final rows = curY['rows'];
        _currentYearRows = rows is List
            ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      } else {
        _currentYearRows = [];
      }

      _rebuildHallOfFame(_monthlyHistory, _yearlyHistory, _currentMonthRows, _currentYearRows);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _displayWinnerName(Map<String, dynamic> m) {
    final u = m['username']?.toString().trim() ?? '';
    if (u.isNotEmpty) return u;
    final id = m['user_id']?.toString() ?? '';
    if (id.length > 8) return 'Player ${id.substring(id.length - 8)}';
    if (id.isNotEmpty) return 'Player $id';
    return 'Player';
  }

  String _winnerLine(List<Map<String, dynamic>> winners) {
    if (winners.isEmpty) return '—';
    final parts = <String>[];
    for (final m in winners) {
      final name = _displayWinnerName(m);
      final wins = m['wins']?.toString() ?? '0';
      parts.add('$name ($wins)');
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Widget _periodCard({
    required String periodLabel,
    required List<Map<String, dynamic>> winners,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.widgetContainerBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.casinoBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              periodLabel,
              style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              _winnerLine(winners),
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentColor));
    }
    if (_error != null) {
      return ListView(
        padding: AppPadding.defaultPadding,
        children: [
          DutchEmptyStateCard(
            title: 'History unavailable',
            message: _error!,
            variant: DutchEmptyStateVariant.error,
            actionLabel: 'Retry',
            onAction: _load,
            semanticIdentifier: 'leaderboard_history_error',
          ),
        ],
      );
    }

    final curMonthWinners = _tiedTopWinners(_currentMonthRows);
    final curYearWinners = _tiedTopWinners(_currentYearRows);

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _load,
      child: ListView(
        padding: AppPadding.defaultPadding,
        children: [
          Text(
            'UTC periods · #1 wins (ties share the title). All-time counts include the current month and year.',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'leaderboard_history_refresh',
            button: true,
            label: 'Refresh history',
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textOnPrimary,
                  side: BorderSide(color: AppColors.casinoBorderColor),
                  backgroundColor: AppColors.widgetContainerBackground,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh, size: 20),
                label: Text(
                  'Refresh',
                  style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DutchSectionHeader(
            title: 'All-time greatest',
            icon: Icons.military_tech,
            semanticIdentifier: 'leaderboard_history_hall_header',
          ),
          if (_hall.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No champion data yet.',
                style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
              ),
            )
          else
            ...List.generate(_hall.length, (i) {
              final e = _hall[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accentContrast.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.casinoBorderColor),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '#${i + 1}',
                          style: AppTextStyles.bodyMedium(color: AppColors.matchPotGold)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.username.isNotEmpty ? e.username : 'Player ${e.userId}',
                          style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                        ),
                      ),
                      Text(
                        '${e.totalTitles} titles (${e.monthlyTitles} mo, ${e.yearlyTitles} yr)',
                        style: AppTextStyles.caption(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          DutchSectionHeader(
            title: 'Monthly champions',
            icon: Icons.calendar_month,
            semanticIdentifier: 'leaderboard_history_monthly_header',
          ),
          if (_currentMonthKey.isNotEmpty)
            _periodCard(
              periodLabel: 'Month $_currentMonthKey (current)',
              winners: curMonthWinners,
            ),
          ..._monthlyHistory.map((p) {
            final pk = p['period_key']?.toString() ?? '';
            final w = p['winners'];
            final wl = w is List
                ? w.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : <Map<String, dynamic>>[];
            return _periodCard(
              periodLabel: 'Month $pk',
              winners: wl,
            );
          }),
          const SizedBox(height: 20),
          DutchSectionHeader(
            title: 'Yearly champions',
            icon: Icons.calendar_today,
            semanticIdentifier: 'leaderboard_history_yearly_header',
          ),
          if (_currentYearKey.isNotEmpty)
            _periodCard(
              periodLabel: 'Year $_currentYearKey (current)',
              winners: curYearWinners,
            ),
          ..._yearlyHistory.map((p) {
            final pk = p['period_key']?.toString() ?? '';
            final w = p['winners'];
            final wl = w is List
                ? w.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : <Map<String, dynamic>>[];
            return _periodCard(
              periodLabel: 'Year $pk',
              winners: wl,
            );
          }),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => NavigationManager().navigateTo('/dutch/leaderboard'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentColor,
              side: BorderSide(color: AppColors.casinoBorderColor),
              backgroundColor: AppColors.widgetContainerBackground,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.arrow_back, size: 20),
            label: Text(
              'Back to live leaderboard',
              style: AppTextStyles.bodyMedium(color: AppColors.accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
