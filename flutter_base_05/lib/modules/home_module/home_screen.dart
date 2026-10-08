import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/widgets/feature_slot.dart';
import '../../utils/consts/theme_consts.dart';
import '../dutch_game/utils/dutch_game_helpers.dart';
import '../dutch_game/widgets/ui_kit/dutch_mastery_mark.dart';

class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<HomeScreen> createState() => _HomeScreenState();

  @override
  String computeTitle(BuildContext context) => 'Home';

  @override
  bool get useLogoInAppBar => true;

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
}

class _HomeScreenState extends BaseScreenState<HomeScreen> {
  @override
  String get featureScopeKey => 'HomeScreen';

  static const List<String> _homeButtonFeatureIds = [
    'dutch_game_play',
    'dutch_game_demo',
    'home_leaderboard',
    'home_customize',
    'home_account',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final appManager = Provider.of<AppManager>(context, listen: false);
        appManager.triggerHomeScreenMainHook(context);
      } catch (e, stackTrace) {
        // Home hook is best-effort; carousel still renders registered features.
      }
    });
  }

  @override
  void dispose() {
    try {
      clearAppBarActions();
      for (final id in _homeButtonFeatureIds) {
        unregisterHomeScreenButton(id);
      }
      super.dispose();
    } catch (e, stackTrace) {
      super.dispose();
    }
  }

  int _masteryFromStats() {
    final raw = DutchGameHelpers.getUserDutchGameStats()?['mastery'];
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  @override
  Widget buildContent(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppPadding.defaultPadding.left,
                AppPadding.smallPadding.top,
                AppPadding.defaultPadding.right,
                AppPadding.smallPadding.bottom,
              ),
              child: DutchMasteryMark.banner(
                value: _masteryFromStats(),
                semanticIdentifier: 'home_mastery',
                showIconBadge: false,
              ),
            ),
            Expanded(
              child: Center(
                child: FeatureSlot(
                  scopeKey: featureScopeKey,
                  slotId: 'home_screen_buttons',
                  contract: 'home_screen_button',
                  useTemplate: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
