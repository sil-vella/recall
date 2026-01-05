import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/navigation_manager.dart';
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
  static const bool LOGGING_SWITCH = false; // Enable for debugging
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome text with app title
            Text(
              'Welcome to Dutch',
              style: AppTextStyles.headingLarge(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            // Play button - navigates to lobby
            ElevatedButton(
              onPressed: () {
                _logger.info('HomeScreen: Play button pressed', isOn: LOGGING_SWITCH);
                try {
                  final navigationManager = Provider.of<NavigationManager>(context, listen: false);
                  _logger.debug('HomeScreen: NavigationManager obtained, navigating to /dutch/lobby', isOn: LOGGING_SWITCH);
                  navigationManager.navigateTo('/dutch/lobby');
                  _logger.debug('HomeScreen: Navigation to /dutch/lobby initiated', isOn: LOGGING_SWITCH);
                } catch (e, stackTrace) {
                  _logger.error('HomeScreen: Error in Play button handler', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                minimumSize: const Size(200, 56),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Play',
                    style: AppTextStyles.headingMedium(),
                  ),
                ],
              ),
            ),
          ],
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