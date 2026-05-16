import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../modules/connections_api_module/connections_api_module.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../utils/dutch_achievement_catalog.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';

const int _kAchievementsDisplayLimit = 20;

/// Route `/dutch/leaderboard/achievements` — all-time achievement count ranking from bundle `achievements`.
class LeaderboardAchievementsScreen extends BaseScreen {
  const LeaderboardAchievementsScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Achievement ranks';

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
  BaseScreenState<LeaderboardAchievementsScreen> createState() =>
      _LeaderboardAchievementsScreenState();
}

class _LeaderboardAchievementsScreenState
    extends BaseScreenState<LeaderboardAchievementsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _truncated = false;
  String? _viewerLine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _bundleUrl() {
    final login = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final uid = login['userId']?.toString() ?? login['user_id']?.toString() ?? '';
    if (uid.isEmpty) {
      return '/public/dutch/leaderboard-period-wins-bundle';
    }
    return '/public/dutch/leaderboard-period-wins-bundle?user_id=${Uri.encodeQueryComponent(uid)}';
  }

  List<Map<String, dynamic>> _rankedRows(List<Map<String, dynamic>> raw) {
    final sorted = List<Map<String, dynamic>>.from(raw)
      ..sort((a, b) {
        final ca = (a['count'] as num?)?.toInt() ?? 0;
        final cb = (b['count'] as num?)?.toInt() ?? 0;
        final c = cb.compareTo(ca);
        if (c != 0) return c;
        final na = (a['username'] ?? '').toString().toLowerCase();
        final nb = (b['username'] ?? '').toString().toLowerCase();
        return na.compareTo(nb);
      });
    final top = sorted.take(_kAchievementsDisplayLimit).toList();
    return List.generate(top.length, (i) {
      final m = Map<String, dynamic>.from(top[i]);
      m['rank'] = i + 1;
      return m;
    });
  }

  String? _buildViewerLine(Map<String, dynamic>? viewer, List<Map<String, dynamic>> visible) {
    if (viewer == null) return null;
    final ach = viewer['achievements'];
    if (ach is! Map) return null;
    final stats = Map<String, dynamic>.from(ach);
    final count = (stats['count'] as num?)?.toInt() ?? 0;
    if (count <= 0) {
      return 'Your achievements: none unlocked yet';
    }
    final uid = viewer['user_id']?.toString() ?? '';
    final idx = visible.indexWhere((r) => r['user_id']?.toString() == uid);
    if (idx >= 0) {
      return 'Your position: #${idx + 1} · $count achievements';
    }
    if (stats['in_leaderboard'] == false) {
      return 'Your position: not in the top $_kAchievementsDisplayLimit · $count achievements';
    }
    return 'Your position: $count achievements';
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
        _error = (response is Map ? response['error']?.toString() : null) ??
            'Failed to load achievement ranks';
        _rows = [];
        if (mounted) setState(() => _loading = false);
        return;
      }
      final block = response['achievements'];
      if (block is Map) {
        _truncated = block['truncated'] == true;
        final rows = block['rows'];
        _rows = rows is List
            ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      } else {
        _truncated = false;
        _rows = [];
      }
      final visible = _rankedRows(_rows);
      final v = response['viewer'];
      _viewerLine = _buildViewerLine(
        v is Map ? Map<String, dynamic>.from(v) : null,
        visible,
      );
      _rows = visible;
    } catch (e) {
      _error = e.toString();
      _rows = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  String _displayName(Map<String, dynamic> row) {
    final u = row['username']?.toString().trim();
    if (u != null && u.isNotEmpty) return u;
    final id = row['user_id']?.toString() ?? '';
    if (id.length > 8) return 'Player ${id.substring(id.length - 8)}';
    if (id.isNotEmpty) return 'Player $id';
    return 'Player';
  }

  void _showAchievementTitles(Map<String, dynamic> row) {
    final raw = row['achievement_ids'];
    final ids = raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    final titles = ids.map(DutchAchievementCatalog.displayTitle).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: AppPadding.defaultPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _displayName(row),
                  style: AppTextStyles.headingSmall(color: AppColors.textOnPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${titles.length} achievement${titles.length == 1 ? '' : 's'}',
                  style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                if (titles.isEmpty)
                  Text(
                    'No achievements listed.',
                    style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                  )
                else
                  ...titles.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.workspace_premium,
                              size: 18, color: AppColors.matchPotGold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t,
                              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
            title: 'Achievement ranks unavailable',
            message: _error!,
            variant: DutchEmptyStateVariant.error,
            actionLabel: 'Retry',
            onAction: _load,
            semanticIdentifier: 'leaderboard_achievements_error',
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _load,
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppPadding.defaultPadding,
              children: [
                Text(
                  'All-time · most achievements unlocked',
                  style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                ),
                if (_viewerLine != null) ...[
                  const SizedBox(height: 6),
                  Text(_viewerLine!, style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
                ],
                const SizedBox(height: 16),
                DutchEmptyStateCard(
                  message: 'No achievement rankings yet.',
                  icon: Icons.workspace_premium_outlined,
                  semanticIdentifier: 'leaderboard_achievements_empty',
                ),
                const SizedBox(height: 16),
                _backButton(),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppPadding.defaultPadding,
              itemCount: _rows.length + 2,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox(height: 4) : const SizedBox(height: 6),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All-time · most achievements unlocked',
                        style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                      ),
                      if (_truncated) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Server list may be capped; some players beyond the cap are omitted.',
                          style: AppTextStyles.caption(color: AppColors.textTertiary),
                        ),
                      ],
                      if (_viewerLine != null) ...[
                        const SizedBox(height: 6),
                        Semantics(
                          identifier: 'leaderboard_achievements_viewer_position',
                          label: _viewerLine!,
                          child: Text(
                            _viewerLine!,
                            style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                          ),
                        ),
                      ],
                    ],
                  );
                }
                if (index == _rows.length + 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _backButton(),
                  );
                }
                final row = _rows[index - 1];
                final rank = row['rank']?.toString() ?? '';
                final count = (row['count'] as num?)?.toInt() ?? 0;
                final name = _displayName(row);
                return Semantics(
                  identifier: 'leaderboard_achievements_row_${row['user_id']}',
                  button: true,
                  label: '$name, $count achievements',
                  child: InkWell(
                    onTap: () => _showAchievementTitles(row),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accentContrast.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accentContrast.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (rank.isNotEmpty)
                            SizedBox(
                              width: 44,
                              child: Text(
                                '#$rank',
                                style: AppTextStyles.bodyMedium(
                                  color: AppColors.white.withValues(alpha: 0.88),
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              name,
                              style: AppTextStyles.bodyMedium(
                                color: AppColors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                          Text(
                            '$count',
                            style: AppTextStyles.bodyMedium(
                              color: AppColors.white.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 20, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _backButton() {
    return OutlinedButton.icon(
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
    );
  }
}
