import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/widgets/feature_slot.dart';
import '../../utils/consts/theme_consts.dart';
import '../../tools/logging/logger.dart';

class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<HomeScreen> createState() => _HomeScreenState();

  @override
  String computeTitle(BuildContext context) => 'Home';
}

class _HomeScreenState extends BaseScreenState<HomeScreen> {
  static const bool LOGGING_SWITCH = true; // Enabled for debugging navigation issues
  static final Logger _logger = Logger();
  
  @override
  void initState() {
    super.initState();
    _logger.info('HomeScreen: initState called', isOn: LOGGING_SWITCH);
    // Trigger home screen main hook
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _logger.debug('HomeScreen: Triggering home screen main hook', isOn: LOGGING_SWITCH);
        final appManager = Provider.of<AppManager>(context, listen: false);
        appManager.triggerHomeScreenMainHook(context);
        _logger.debug('HomeScreen: Home screen main hook triggered successfully', isOn: LOGGING_SWITCH);
      } catch (e, stackTrace) {
        _logger.error('HomeScreen: Error triggering home screen main hook', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      }
    });
  }

  @override
  void dispose() {
    _logger.debug('HomeScreen: dispose called', isOn: LOGGING_SWITCH);
    try {
      // Clean up app bar features when screen is disposed
      clearAppBarActions();
      // Clean up home screen button features
      unregisterHomeScreenButton('dutch_game_play');
      super.dispose();
      _logger.debug('HomeScreen: dispose completed successfully', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('HomeScreen: Error in dispose', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      super.dispose();
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    _logger.debug('HomeScreen: buildContent called', isOn: LOGGING_SWITCH);
    
    try {
      return Center(
        child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome text with app title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                child: Text(
              'Welcome to Dutch',
              style: AppTextStyles.headingLarge(),
              textAlign: TextAlign.center,
            ),
              ),
              const SizedBox(height: 24),
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
      _logger.error('HomeScreen: Error in buildContent', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
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