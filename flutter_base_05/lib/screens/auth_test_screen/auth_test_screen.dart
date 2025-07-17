import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/theme_consts.dart';

class AuthTestScreen extends BaseScreen {
  const AuthTestScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AuthTestScreen> createState() => _AuthTestScreenState();

  @override
  String computeTitle(BuildContext context) => 'Auth Test';
}

class _AuthTestScreenState extends BaseScreenState<AuthTestScreen> {
  static final Logger _log = Logger();
  
  // Module manager
  final ModuleManager _moduleManager = ModuleManager();
  
  @override
  void initState() {
    super.initState();
    _initializeModules();
  }
  
  void _initializeModules() {
    _log.info('🔧 Initializing Auth Test Screen modules');
    // Initialize any required modules here
  }
  

  
  Widget _buildHeader(BuildContext context) {
    return buildHeader(
      context,
      child: Column(
        children: [
          Icon(
            Icons.security,
            size: 48,
            color: AppColors.accentColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Authentication Test',
            style: AppTextStyles.headingLarge(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Test JWT authentication and token management',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.lightGray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        const SizedBox(height: 20),
        buildContentCard(
          context,
          child: Column(
            children: [
              // Empty content area as requested
              const SizedBox(height: 100),
              Text(
                'Auth Test Content',
                style: AppTextStyles.headingMedium(),
              ),
              const SizedBox(height: 16),
              Text(
                'Content area is empty for now',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ],
    );
  }
  

  
  Decoration _buildBackground() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primaryColor.withOpacity(0.1),
          AppColors.primaryColor.withOpacity(0.05),
        ],
      ),
    );
  }
} 