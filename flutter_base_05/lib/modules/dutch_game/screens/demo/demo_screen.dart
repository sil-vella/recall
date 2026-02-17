import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../tools/logging/logger.dart';
import '../../widgets/instructions_widget.dart';
import 'demo_action_handler.dart';

class DemoScreen extends BaseScreen {
  const DemoScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Dutch Game Demo';

  @override
  Decoration? getBackground(BuildContext context) {
    return BoxDecoration(
      color: AppColors.pokerTableGreen,
    );
  }

  @override
  DemoScreenState createState() => DemoScreenState();
}

class DemoScreenState extends BaseScreenState<DemoScreen> {
  // Logger for demo operations
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Enabled for demo debugging
  
  // Demo action handler
  final DemoActionHandler _demoActionHandler = DemoActionHandler.instance;
  
  // Demo actions list
  final List<Map<String, String>> _demoActions = [
    {'type': 'initial_peek', 'title': 'Initial Peek', 'icon': '👁️'},
    {'type': 'drawing', 'title': 'Drawing', 'icon': '🎴'},
    {'type': 'playing', 'title': 'Playing', 'icon': '🃏'},
    {'type': 'same_rank', 'title': 'Same Rank', 'icon': '🔄'},
    {'type': 'queen_peek', 'title': 'Queen Peek', 'icon': '👸'},
    {'type': 'jack_swap', 'title': 'Jack Swap', 'icon': '🃁'},
    {'type': 'call_dutch', 'title': 'Call Dutch', 'icon': '🏁'},
    {'type': 'collect_rank', 'title': 'Collect Rank', 'icon': '⭐'},
  ];

  @override
  void dispose() {
    super.dispose();
  }
  

  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Stack(
          children: [
            _buildDemoActionButtons(),
            // Instructions Modal Widget - handles its own state subscription
            const InstructionsWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoActionButtons() {
    return Padding(
      padding: AppPadding.defaultPadding,
      child: ListView.builder(
        itemCount: _demoActions.length + 2, // +1 Rules/Video row, +1 "Start Demo" button
        itemBuilder: (context, index) {
          // First item is the Rules and Video buttons row
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildRulesAndVideoRow(),
            );
          }
          // Second item is the "Start Demo" button
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: _buildStartDemoButton(),
            );
          }
          
          // Demo actions (indices 2+)
          final actionIndex = index - 2;
          final action = _demoActions[actionIndex];
          return Padding(
            padding: EdgeInsets.only(
              bottom: actionIndex < _demoActions.length - 1 ? 16 : 0,
            ),
            child: _buildActionButton(
              actionType: action['type']!,
              title: action['title']!,
              icon: action['icon']!,
            ),
          );
        },
      ),
    );
  }

  /// Rules and Video buttons side by side, same style as demo action buttons
  Widget _buildRulesAndVideoRow() {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildSmallActionButton(
              title: 'Rules',
              icon: '📜',
              onTap: () {
                NavigationManager().navigateTo('/dutch/game-rules');
              },
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _buildSmallActionButton(
              title: 'Video',
              icon: '🎬',
              onTap: () {
                NavigationManager().navigateTo('/dutch/video-tutorial');
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallActionButton({
    required String title,
    required String icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppPadding.defaultPadding.left,
              vertical: AppPadding.smallPadding.top,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTextStyles.headingSmall().copyWith(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStartDemoButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (LOGGING_SWITCH) {
              _logger.info('🎮 DemoScreen: Start Demo button tapped - starting sequential demos');
            }
            try {
              await _demoActionHandler.startSequentialDemos();
            } catch (e) {
              if (LOGGING_SWITCH) {
                _logger.error('❌ DemoScreen: Error starting sequential demos: $e');
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to start sequential demos: $e'),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: AppPadding.defaultPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '🚀',
                  style: const TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start Demo',
                  style: AppTextStyles.headingMedium().copyWith(
                    color: AppColors.textOnAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Run all demos sequentially',
                  style: AppTextStyles.bodySmall().copyWith(
                    color: AppColors.textOnAccent.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String actionType,
    required String title,
    required String icon,
  }) {
    return Container(
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
          onTap: () async {
            if (LOGGING_SWITCH) {
              _logger.info('🎮 DemoScreen: Demo action button tapped: $actionType');
            }
            try {
              await _demoActionHandler.startDemoAction(actionType);
            } catch (e) {
              if (LOGGING_SWITCH) {
                _logger.error('❌ DemoScreen: Error starting demo action: $e');
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to start demo: $e'),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppPadding.defaultPadding.left,
              vertical: AppPadding.smallPadding.top,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTextStyles.headingSmall().copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ],
                  ),
                ),
              ),
            ),
    );
  }

}

