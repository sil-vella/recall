import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../utils/consts/theme_consts.dart';

class AuthTestScreen extends BaseScreen {
  const AuthTestScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AuthTestScreen> createState() => _AuthTestScreenState();

  @override
  String computeTitle(BuildContext context) => 'Auth Test';
}

class _AuthTestScreenState extends BaseScreenState<AuthTestScreen> {
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
    // Initialize any required modules here
  }
  
  Future<void> _testJWT() async {
    try {
      // Get the ConnectionsApiModule instance from ModuleManager
      final connectionsApiModule = _moduleManager.getModule('connections_api') as ConnectionsApiModule;
      
      final response = await connectionsApiModule.sendPostRequest(
        '/test-jwt',
        {},
      );
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JWT test successful: ${response['message'] ?? 'Success'}'),
            backgroundColor: AppColors.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JWT test failed: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }
  
  Future<void> _setTtlTo10Seconds() async {
    try {
      // Get current TTL before setting
      final currentTtl = await _authManager.getAccessTokenTtl();
      await _authManager.setTtlTo10Seconds();
      // Get TTL after setting to verify
      final newTtl = await _authManager.getAccessTokenTtl();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access token TTL set to 10 seconds for testing (was ${currentTtl}s)'),
            backgroundColor: AppColors.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set access token TTL: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  Future<Map<String, int>> _getCurrentTtlValues() async {
    try {
      final accessTtl = await _authManager.getAccessTokenTtl();
      final refreshTtl = await _authManager.getRefreshTokenTtl();
      return {
        'access': accessTtl,
        'refresh': refreshTtl,
      };
    } catch (e) {
      return {
        'access': 0,
        'refresh': 0,
      };
    }
  }

  Future<void> _setRefreshTtlTo10Seconds() async {
    try {
      // Get current refresh TTL before setting
      final currentRefreshTtl = await _authManager.getRefreshTokenTtl();
      await _authManager.setRefreshTtlTo10Seconds();
      // Get refresh TTL after setting to verify
      final newRefreshTtl = await _authManager.getRefreshTokenTtl();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh token TTL set to 10 seconds for testing (was ${currentRefreshTtl}s)'),
            backgroundColor: AppColors.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set refresh token TTL: $e'),
            backgroundColor: AppColors.errorColor,
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
            style: AppTextStyles.bodyLarge().copyWith(
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
                style: AppTextStyles.bodyMedium(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
                            Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current TTL Values:',
                        style: AppTextStyles.headingSmall(),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            // This will rebuild the FutureBuilder
                          });
                        },
                        icon: Icon(Icons.refresh, color: AppColors.textOnPrimary),
                        tooltip: 'Refresh TTL values',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, int>>(
                    future: _getCurrentTtlValues(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final ttlData = snapshot.data!;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderDefault),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Access Token:', style: AppTextStyles.bodyMedium()),
                                  Text('${ttlData['access']}s', style: AppTextStyles.bodyMedium().copyWith(
                                    color: AppColors.accentColor,
                                    fontWeight: FontWeight.bold,
                                  )),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Refresh Token:', style: AppTextStyles.bodyMedium()),
                                  Text('${ttlData['refresh']}s', style: AppTextStyles.bodyMedium().copyWith(
                                    color: AppColors.accentColor,
                                    fontWeight: FontWeight.bold,
                                  )),
                                ],
                              ),
                            ],
                          ),
                        );
                      } else if (snapshot.hasError) {
                        return Text('Error loading TTL values: ${snapshot.error}');
                      } else {
                        return const CircularProgressIndicator();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _testJWT,
                icon: const Icon(Icons.security),
                label: const Text('Test JWT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.textOnAccent,
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
                label: const Text('Set Access Token TTL to 10s'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warningColor,
                  foregroundColor: AppColors.textOnAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _setRefreshTtlTo10Seconds,
                icon: const Icon(Icons.refresh),
                label: const Text('Set Refresh Token TTL to 10s'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor2,
                  foregroundColor: AppColors.textOnAccent,
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