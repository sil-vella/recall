import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../system/00_base/screen_base.dart';
import '../../system/orchestration/app_init/app_initializer.dart';
import '../../utils/consts/theme_consts.dart';

class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<HomeScreen> createState() => _HomeScreenState();

  @override
  String computeTitle(BuildContext context) => 'Home';
}

class _HomeScreenState extends BaseScreenState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger home screen main hook
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appInitializer = Provider.of<AppInitializer>(context, listen: false);
      appInitializer.triggerHomeScreenMainHook(context);
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Welcome text with app title
          const Text(
            'Welcome to Recall',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 