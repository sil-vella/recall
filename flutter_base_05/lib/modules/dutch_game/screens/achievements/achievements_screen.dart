import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../utils/dutch_achievement_catalog.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';

/// Route: `/dutch/achievements` — progress from [DutchGameHelpers.getUserDutchGameStats].
class AchievementsScreen extends BaseScreen {
  const AchievementsScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Achievements';

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
  BaseScreenState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends BaseScreenState<AchievementsScreen> {
  bool _loading = true;
  String? _error;
  Set<String> _unlocked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          _error = 'Could not load your achievements. Pull to refresh or try again later.';
          _unlocked = {};
        });
        return;
      }
      final stats = DutchGameHelpers.getUserDutchGameStats();
      final raw = stats?['achievements_unlocked_ids'];
      final ids = <String>{};
      if (raw is List) {
        for (final e in raw) {
          ids.add(e.toString());
        }
      }
      setState(() {
        _loading = false;
        _unlocked = ids;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentColor),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        color: AppColors.accentColor,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppPadding.defaultPadding,
          children: [
            DutchEmptyStateCard(
              title: 'Something went wrong',
              message: _error!,
              variant: DutchEmptyStateVariant.error,
              actionLabel: 'Retry',
              onAction: _load,
              semanticIdentifier: 'achievements_error',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
        children: [
          Semantics(
            identifier: 'achievements_summary',
            label: 'Current win streak and best',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StreakSummaryCard(
                stats: DutchGameHelpers.getUserDutchGameStats(),
              ),
            ),
          ),
          ...DutchAchievementCatalog.all.map((entry) {
            final done = _unlocked.contains(entry.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                identifier: 'achievement_row_${entry.id}',
                label: '${entry.title}, ${done ? "unlocked" : "locked"}',
                child: _AchievementTile(entry: entry, unlocked: done),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StreakSummaryCard extends StatelessWidget {
  const _StreakSummaryCard({required this.stats});

  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final cur = _int(stats?['win_streak_current']);
    final best = _int(stats?['win_streak_best']);
    return Container(
      padding: AppPadding.largePadding,
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.largeRadius,
        border: Border.all(color: AppColors.borderDefault, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department, color: AppColors.accentColor, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Win streak',
                  style: AppTextStyles.headingSmall(color: AppColors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: $cur   ·   Best: $best',
                  style: AppTextStyles.bodyMedium(color: AppColors.lightGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.entry,
    required this.unlocked,
  });

  final DutchAchievementEntry entry;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final tone = unlocked ? AppColors.accentColor : AppColors.lightGray;
    return Container(
      padding: AppPadding.largePadding,
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.largeRadius,
        border: Border.all(
          color: unlocked ? AppColors.accentColor.withValues(alpha: 0.45) : AppColors.borderDefault,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unlocked ? Icons.check_circle : Icons.lock_outline,
            color: tone,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: AppTextStyles.headingSmall(color: AppColors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  style: AppTextStyles.bodyMedium(color: AppColors.lightGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
