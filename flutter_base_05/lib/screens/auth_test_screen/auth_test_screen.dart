import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
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
  
  // Auth manager
  final AuthManager _authManager = AuthManager();
  
  @override
  void initState() {
    super.initState();
    _initializeModules();
  }
  
  void _initializeModules() {
    _log.info('🔧 Initializing Auth Test Screen modules');
    // Initialize any required modules here
  }
  
  Future<void> _testJWT() async {
    try {
      _log.info('🧪 Testing JWT endpoint');
      
      // Get the ConnectionsApiModule instance from ModuleManager
      final connectionsApiModule = _moduleManager.getModule('connections_api') as ConnectionsApiModule;
      
      final response = await connectionsApiModule.sendPostRequest(
        '/test-jwt',
        {},
      );
      
      _log.info('✅ JWT test response: $response');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JWT test successful: ${response['message'] ?? 'Success'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.error('❌ JWT test failed: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JWT test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _setTtlTo10Seconds() async {
    try {
      // Get current TTL before setting
      final currentTtl = await _authManager.getAccessTokenTtl();
      _log.info('🔍 Current TTL before setting: ${currentTtl}s');
      
      await _authManager.setTtlTo10Seconds();
      _log.info('✅ Set TTL to 10 seconds');
      
      // Get TTL after setting to verify
      final newTtl = await _authManager.getAccessTokenTtl();
      _log.info('🔍 New TTL after setting: ${newTtl}s');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TTL set to 10 seconds for testing (was ${currentTtl}s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.error('❌ Failed to set TTL: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set TTL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              const SizedBox(height: 20),
              Text(
                'JWT Authentication Test',
                style: AppTextStyles.headingMedium(),
              ),
              const SizedBox(height: 16),
              Text(
                'Test JWT token validation and authentication',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _testJWT,
                icon: const Icon(Icons.security),
                label: const Text('Test JWT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _setTtlTo10Seconds,
                icon: const Icon(Icons.timer),
                label: const Text('Set TTL to 10s'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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