import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../tools/logging/logger.dart';
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
  static const bool LOGGING_SWITCH = true; // Enabled for demo debugging
  
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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }
  

  @override
  Widget buildContent(BuildContext context) {
    return _buildDemoActionButtons();
  }

  Widget _buildDemoActionButtons() {
    return Padding(
      padding: AppPadding.defaultPadding,
      child: ListView.builder(
        itemCount: _demoActions.length,
        itemBuilder: (context, index) {
          final action = _demoActions[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _demoActions.length - 1 ? 16 : 0,
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
            _logger.info('🎮 DemoScreen: Demo action button tapped: $actionType', isOn: LOGGING_SWITCH);
            try {
              await _demoActionHandler.startDemoAction(actionType);
            } catch (e) {
              _logger.error('❌ DemoScreen: Error starting demo action: $e', isOn: LOGGING_SWITCH);
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
            padding: AppPadding.defaultPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 48),
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

