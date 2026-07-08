import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../utils/dutch_game_helpers.dart';
import '../../utils/progression_ladder.dart';
import '../../widgets/ui_kit/dutch_empty_state_card.dart';

const int _tabRanks = 0;
const int _tabLevels = 1;
const int _tabTables = 2;

/// Route: `/dutch/progression` — ranks, user levels, and table tiers vs current stats.
class ProgressionScreen extends BaseScreen {
  const ProgressionScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Progression';

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
  BaseScreenState<ProgressionScreen> createState() => _ProgressionScreenState();
}

class _ProgressionScreenState extends BaseScreenState<ProgressionScreen> {
  bool _loading = true;
  String? _error;
  int _selectedTab = _tabRanks;
  Map<String, dynamic>? _stats;

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
          _error = 'Could not load your progression. Pull to refresh or try again later.';
          _stats = null;
        });
        return;
      }
      setState(() {
        _loading = false;
        _stats = DutchGameHelpers.getUserDutchGameStats();
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
      return Center(child: CircularProgressIndicator(color: AppColors.accentColor));
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
              semanticIdentifier: 'progression_error',
            ),
          ],
        ),
      );
    }

    final userLevel = resolveUserLevelFromStats(_stats);
    final wins = _int(_stats?['wins']);
    final summary = buildProgressionSummary(_stats);
    final rankEntries = buildRankLadderEntries(userLevel: userLevel, wins: wins);
    final levelEntries = buildLevelLadderEntries(userLevel: userLevel, wins: wins);
    final tableEntries = buildTableTierLadderEntries(userLevel: userLevel, wins: wins);

    return RefreshIndicator(
      color: AppColors.accentColor,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppPadding.defaultPadding,
        children: [
          Semantics(
            identifier: 'progression_summary',
            label: 'Your wins, level, and rank',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProgressionSummaryCard(summary: summary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ProgressionTabBar(
              tabIndex: _selectedTab,
              onChanged: (index) => setState(() => _selectedTab = index),
            ),
          ),
          ..._rowsForTab(
            _selectedTab,
            rankEntries: rankEntries,
            levelEntries: levelEntries,
            tableEntries: tableEntries,
          ),
        ],
      ),
    );
  }

  List<Widget> _rowsForTab(
    int tabIndex, {
    required List<ProgressionLadderEntry> rankEntries,
    required List<ProgressionLadderEntry> levelEntries,
    required List<ProgressionLadderEntry> tableEntries,
  }) {
    final entries = switch (tabIndex) {
      _tabLevels => levelEntries,
      _tabTables => tableEntries,
      _ => rankEntries,
    };

    if (entries.isEmpty) {
      return const [
        DutchEmptyStateCard(
          title: 'No progression data',
          message: 'Progression rules are still loading. Pull to refresh.',
          icon: Icons.hourglass_empty,
          semanticIdentifier: 'progression_empty',
        ),
      ];
    }

    return entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          identifier: 'progression_row_${entry.id}',
          label: _semanticsLabel(entry),
          child: _ProgressionTile(entry: entry),
        ),
      );
    }).toList();
  }

  String _semanticsLabel(ProgressionLadderEntry entry) {
    switch (entry.status) {
      case ProgressionLadderStatus.completed:
        return '${entry.title}, reached';
      case ProgressionLadderStatus.current:
        if (entry.progressCurrent != null && entry.progressRequired != null) {
          return '${entry.title}, in progress, ${entry.progressCurrent} of ${entry.progressRequired}';
        }
        return '${entry.title}, in progress';
      case ProgressionLadderStatus.locked:
        return '${entry.title}, locked';
    }
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class _ProgressionSummaryCard extends StatelessWidget {
  const _ProgressionSummaryCard({required this.summary});

  final ProgressionSummary summary;

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, color: AppColors.matchPotGold, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your progression',
                      style: AppTextStyles.headingSmall(color: AppColors.matchPotGold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.wins} wins · Level ${summary.userLevel} · ${summary.rankLabel}',
                      style: AppTextStyles.bodyMedium(color: AppColors.lightGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.nextLevel != null &&
              summary.winsProgressFraction != null &&
              summary.winsToNextLevel != null) ...[
            const SizedBox(height: 14),
            Text(
              'Next: Level ${summary.nextLevel} · ${summary.winsToNextLevel} wins to go',
              style: AppTextStyles.bodySmall(color: AppColors.matchPotGold),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: AppBorderRadius.smallRadius,
              child: LinearProgressIndicator(
                value: summary.winsProgressFraction,
                minHeight: 8,
                backgroundColor: AppColors.borderDefault,
                color: AppColors.matchPotGold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressionTabBar extends StatelessWidget {
  const _ProgressionTabBar({
    required this.tabIndex,
    required this.onChanged,
  });

  final int tabIndex;
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
            child: _ProgressionTabSegment(
              label: 'Ranks',
              selected: tabIndex == _tabRanks,
              inactiveBg: inactiveBg,
              inactiveFg: inactiveFg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              semanticsLabel: 'Progression ranks tab',
              semanticsIdentifier: 'progression_tab_ranks',
              onTap: () => onChanged(_tabRanks),
            ),
          ),
          Expanded(
            child: _ProgressionTabSegment(
              label: 'Levels',
              selected: tabIndex == _tabLevels,
              inactiveBg: inactiveBg,
              inactiveFg: inactiveFg,
              borderRadius: BorderRadius.zero,
              semanticsLabel: 'Progression levels tab',
              semanticsIdentifier: 'progression_tab_levels',
              onTap: () => onChanged(_tabLevels),
            ),
          ),
          Expanded(
            child: _ProgressionTabSegment(
              label: 'Tables',
              selected: tabIndex == _tabTables,
              inactiveBg: inactiveBg,
              inactiveFg: inactiveFg,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              semanticsLabel: 'Progression tables tab',
              semanticsIdentifier: 'progression_tab_tables',
              onTap: () => onChanged(_tabTables),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressionTabSegment extends StatelessWidget {
  const _ProgressionTabSegment({
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

class _ProgressionTile extends StatelessWidget {
  const _ProgressionTile({required this.entry});

  final ProgressionLadderEntry entry;

  @override
  Widget build(BuildContext context) {
    final unlocked = entry.status == ProgressionLadderStatus.completed;
    final inProgress = entry.status == ProgressionLadderStatus.current;
    final tone = unlocked
        ? AppColors.matchPotGold
        : inProgress
            ? AppColors.accentColor2
            : AppColors.lightGray;
    final borderColor = unlocked
        ? AppColors.matchPotGold.withValues(alpha: 0.45)
        : inProgress
            ? AppColors.accentColor2.withValues(alpha: 0.5)
            : AppColors.borderDefault;

    return Container(
      padding: AppPadding.largePadding,
      decoration: BoxDecoration(
        color: inProgress
            ? AppColors.widgetContainerBackground.withValues(alpha: 0.95)
            : AppColors.widgetContainerBackground,
        borderRadius: AppBorderRadius.largeRadius,
        border: Border.all(color: borderColor, width: inProgress ? 1.5 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unlocked
                ? Icons.check_circle
                : inProgress
                    ? Icons.radio_button_checked
                    : Icons.lock_outline,
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
                    color: unlocked
                        ? AppColors.matchPotGold
                        : inProgress
                            ? AppColors.white
                            : AppColors.lightGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.subtitle,
                  style: AppTextStyles.bodyMedium(color: AppColors.lightGray),
                ),
                if (!unlocked &&
                    entry.progressLabel != null &&
                    entry.progressCurrent != null &&
                    entry.progressRequired != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${entry.progressLabel}: ${entry.progressCurrent} / ${entry.progressRequired}',
                    style: AppTextStyles.bodySmall(color: tone),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: AppBorderRadius.smallRadius,
                    child: LinearProgressIndicator(
                      value: entry.progressFraction?.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.borderDefault,
                      color: tone,
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
