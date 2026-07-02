import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../utils/achievement_progress.dart';
import '../../utils/dutch_achievement_catalog.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';

const int _achievementsTabUnlocked = 0;
const int _achievementsTabLocked = 1;

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
  int _selectedTab = _achievementsTabUnlocked;

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
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _AchievementsTabBar(
              tabIndex: _selectedTab,
              unlockedCount: _unlocked.length,
              lockedCount: DutchAchievementCatalog.all.length - _unlocked.length,
              onChanged: (index) => setState(() => _selectedTab = index),
            ),
          ),
          ..._achievementRowsForTab(_selectedTab),
        ],
      ),
    );
  }

  List<Widget> _achievementRowsForTab(int tabIndex) {
    final stats = DutchGameHelpers.getUserDutchGameStats();
    final showUnlocked = tabIndex == _achievementsTabUnlocked;
    final entries = DutchAchievementCatalog.all.where((entry) {
      final done = _unlocked.contains(entry.id);
      return showUnlocked ? done : !done;
    }).toList();

    if (entries.isEmpty) {
      return [
        DutchEmptyStateCard(
          title: showUnlocked ? 'Nothing unlocked yet' : 'All caught up',
          message: showUnlocked
              ? 'Win games, climb the leaderboard, and complete challenges to unlock achievements.'
              : 'You have unlocked every achievement. Great work!',
          icon: showUnlocked ? Icons.lock_outline : Icons.emoji_events_outlined,
          semanticIdentifier: showUnlocked
              ? 'achievements_unlocked_empty'
              : 'achievements_locked_empty',
        ),
      ];
    }

    return entries.map((entry) {
      final done = _unlocked.contains(entry.id);
      final progress = achievementProgressFor(
        entry: entry,
        unlocked: done,
        stats: stats,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          identifier: 'achievement_row_${entry.id}',
          label: _semanticsLabel(entry, done, progress),
          child: _AchievementTile(
            entry: entry,
            unlocked: done,
            progress: progress,
          ),
        ),
      );
    }).toList();
  }

  String _semanticsLabel(
    DutchAchievementEntry entry,
    bool unlocked,
    AchievementProgress? progress,
  ) {
    if (unlocked) return '${entry.title}, unlocked';
    if (progress != null) {
      return '${entry.title}, locked, ${progress.current} of ${progress.required}';
    }
    return '${entry.title}, locked';
  }
}

/// Unlocked vs locked — matches join-random / leaderboard segmented toggle styling.
class _AchievementsTabBar extends StatelessWidget {
  const _AchievementsTabBar({
    required this.tabIndex,
    required this.unlockedCount,
    required this.lockedCount,
    required this.onChanged,
  });

  final int tabIndex;
  final int unlockedCount;
  final int lockedCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final inactiveBg = AppColors.accentContrast.withValues(alpha: 0.28);
    final inactiveFg = AppColors.textOnPrimary.withValues(alpha: 0.45);
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
            child: _AchievementsTabSegment(
              label: 'Unlocked ($unlockedCount)',
              selected: tabIndex == _achievementsTabUnlocked,
              inactiveBg: inactiveBg,
              inactiveFg: inactiveFg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              semanticsLabel: 'Achievements unlocked tab',
              semanticsIdentifier: 'achievements_tab_unlocked',
              onTap: () => onChanged(_achievementsTabUnlocked),
            ),
          ),
          Expanded(
            child: _AchievementsTabSegment(
              label: 'Locked ($lockedCount)',
              selected: tabIndex == _achievementsTabLocked,
              inactiveBg: inactiveBg,
              inactiveFg: inactiveFg,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              semanticsLabel: 'Achievements locked tab',
              semanticsIdentifier: 'achievements_tab_locked',
              onTap: () => onChanged(_achievementsTabLocked),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsTabSegment extends StatelessWidget {
  const _AchievementsTabSegment({
    required this.label,
    required this.selected,
    required this.inactiveBg,
    required this.inactiveFg,
    required this.borderRadius,
    required this.semanticsLabel,
    required this.semanticsIdentifier,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color inactiveBg;
  final Color inactiveFg;
  final BorderRadius borderRadius;
  final String semanticsLabel;
  final String semanticsIdentifier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Semantics(
          label: semanticsLabel,
          identifier: semanticsIdentifier,
          button: true,
          selected: selected,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentContrast : inactiveBg,
              borderRadius: borderRadius,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium(
                color: selected ? AppColors.textOnAccent : inactiveFg,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
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
        color: AppColors.accentContrast,
        borderRadius: AppBorderRadius.largeRadius,
        border: Border.all(
          color: AppColors.matchPotGold.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department, color: AppColors.matchPotGold, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Win streak',
                  style: AppTextStyles.headingSmall(color: AppColors.matchPotGold),
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
    this.progress,
  });

  final DutchAchievementEntry entry;
  final bool unlocked;
  final AchievementProgress? progress;

  @override
  Widget build(BuildContext context) {
    final tone = unlocked ? AppColors.matchPotGold : AppColors.lightGray;
    return Container(
      padding: AppPadding.largePadding,
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.largeRadius,
        border: Border.all(
          color: unlocked ? AppColors.matchPotGold.withValues(alpha: 0.45) : AppColors.borderDefault,
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
                  style: AppTextStyles.headingSmall(
                    color: unlocked ? AppColors.matchPotGold : AppColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  style: AppTextStyles.bodyMedium(color: AppColors.lightGray),
                ),
                if (!unlocked && progress != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${progress!.label}: ${progress!.current} / ${progress!.required}',
                    style: AppTextStyles.bodySmall(color: AppColors.matchPotGold),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: AppBorderRadius.smallRadius,
                    child: LinearProgressIndicator(
                      value: progress!.fraction,
                      minHeight: 6,
                      backgroundColor: AppColors.borderDefault,
                      color: AppColors.matchPotGold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
