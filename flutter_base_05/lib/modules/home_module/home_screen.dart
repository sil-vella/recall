import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/widgets/feature_slot.dart';
import '../../utils/consts/theme_consts.dart';
import '../../tools/logging/logger.dart';
import '../dutch_game/widgets/ui_kit/dutch_responsive_shell.dart';

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
  static const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues
  static final Logger _logger = Logger();
  
  // Override featureScopeKey to match the scope used by Dutch game module
  @override
  String get featureScopeKey => 'HomeScreen';
  
  @override
  void initState() {
    super.initState();
    if (LOGGING_SWITCH) {
      _logger.info('HomeScreen: initState called');
    }
    // Trigger home screen main hook
    // Note: HooksManager automatically re-triggers hooks for late-registering modules,
    // so modules that register after this trigger will still receive the hook
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (LOGGING_SWITCH) {
          _logger.debug('HomeScreen: Triggering home screen main hook');
        }
        final appManager = Provider.of<AppManager>(context, listen: false);
        appManager.triggerHomeScreenMainHook(context);
        if (LOGGING_SWITCH) {
          _logger.debug('HomeScreen: Home screen main hook triggered successfully');
        }
      } catch (e, stackTrace) {
        if (LOGGING_SWITCH) {
          _logger.error('HomeScreen: Error triggering home screen main hook', error: e, stackTrace: stackTrace);
        }
      }
    });
  }

  @override
  void dispose() {
    if (LOGGING_SWITCH) {
      _logger.debug('HomeScreen: dispose called');
    }
    try {
      // Clean up app bar features when screen is disposed
      clearAppBarActions();
      // Clean up home screen button features
      unregisterHomeScreenButton('dutch_game_play');
      super.dispose();
      if (LOGGING_SWITCH) {
        _logger.debug('HomeScreen: dispose completed successfully');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('HomeScreen: Error in dispose', error: e, stackTrace: stackTrace);
      }
      super.dispose();
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    if (LOGGING_SWITCH) {
      _logger.debug('HomeScreen: buildContent called');
    }
    
    try {
      return DutchResponsiveShell(
        hero: const _HomeHero(),
        menu: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Home screen button features slot - full-width buttons registered by modules
              FeatureSlot(
                scopeKey: featureScopeKey,
                slotId: 'home_screen_buttons',
                contract: 'home_screen_button',
                useTemplate: false,
              ),
            ],
          ),
        ),
      );
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('HomeScreen: Error in buildContent', error: e, stackTrace: stackTrace);
      }
      // Return a fallback widget to prevent red screen
      return Center(
        child: Text(
          'Error loading home screen',
          style: AppTextStyles.bodyMedium().copyWith(
            color: AppColors.errorColor,
          ),
        ),
      );
    }
  }
}

/// Hero block rendered above the home CTAs by [DutchResponsiveShell].
///
/// Centered, on-theme welcome card. Pure presentation — no state, no
/// hooks, no navigation. Designed to be safe to remove or replace later
/// without touching the feature slot wiring.
class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cap the visual size of the hero so very tall screens don't stretch
        // the orb out of proportion.
        final shortest = constraints.biggest.shortestSide;
        final orbSize = shortest * 0.45;

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: orbSize,
                height: orbSize,
                constraints: const BoxConstraints(
                  maxWidth: 220,
                  maxHeight: 220,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentColor2.withValues(alpha: 0.55),
                      AppColors.accentContrast.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/logo.webp',
                  width: orbSize * 0.5,
                  height: orbSize * 0.5,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Play, practice, and climb the leaderboard.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium(
                    color: AppColors.white.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 