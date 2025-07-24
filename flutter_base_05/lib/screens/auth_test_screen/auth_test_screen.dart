import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../system/00_base/screen_base.dart';
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
  
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }
  
  void _initializeScreen() {
    _log.info('🔧 Initializing Auth Test Screen');
    // Get auth manager and login orchestrator for testing
    final loginOrchestrator = getOrchestrator('login');
    if (loginOrchestrator == null) {
      _log.error('❌ Login orchestrator not available');
    } else {
      _log.info('✅ Login orchestrator available');
    }
  }
  
  Future<void> _testJWT() async {
    try {
      _log.info('🧪 Testing JWT endpoint');
      
      // Use auth manager for JWT testing
      final hasValidToken = await authManager.hasValidToken();
      
      _log.info('✅ JWT test result: ${hasValidToken ? "Valid token" : "No valid token"}');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JWT test successful: ${hasValidToken ? "Valid token" : "No valid token"}'),
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
      final currentTtl = await authManager.getAccessTokenTtl();
      _log.info('🔍 Current access token TTL before setting: ${currentTtl}s');
      
      await authManager.setTtlTo10Seconds();
      _log.info('✅ Set access token TTL to 10 seconds');
      
      // Get TTL after setting to verify
      final newTtl = await authManager.getAccessTokenTtl();
      _log.info('🔍 New access token TTL after setting: ${newTtl}s');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access token TTL set to 10 seconds for testing (was ${currentTtl}s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.error('❌ Failed to set access token TTL: $e');
      
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

  Future<Map<String, int>> _getCurrentTtlValues() async {
    try {
      final accessTtl = await authManager.getAccessTokenTtl();
      final refreshTtl = await authManager.getRefreshTokenTtl();
      return {
        'access': accessTtl,
        'refresh': refreshTtl,
      };
    } catch (e) {
      _log.error('❌ Error getting TTL values: $e');
      return {
        'access': 0,
        'refresh': 0,
      };
    }
  }

  Future<void> _setRefreshTtlTo10Seconds() async {
    try {
      // Get current refresh TTL before setting
      final currentRefreshTtl = await authManager.getRefreshTokenTtl();
      _log.info('🔍 Current refresh token TTL before setting: ${currentRefreshTtl}s');
      
      await authManager.setRefreshTtlTo10Seconds();
      _log.info('✅ Set refresh token TTL to 10 seconds');
      
      // Get refresh TTL after setting to verify
      final newRefreshTtl = await authManager.getRefreshTokenTtl();
      _log.info('🔍 New refresh token TTL after setting: ${newRefreshTtl}s');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh token TTL set to 10 seconds for testing (was ${currentRefreshTtl}s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log.error('❌ Failed to set refresh token TTL: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set refresh token TTL: $e'),
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
                        icon: const Icon(Icons.refresh, color: Colors.white),
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
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[700]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Access Token:', style: AppTextStyles.bodyMedium),
                                  Text('${ttlData['access']}s', style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.accentColor,
                                    fontWeight: FontWeight.bold,
                                  )),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Refresh Token:', style: AppTextStyles.bodyMedium),
                                  Text('${ttlData['refresh']}s', style: AppTextStyles.bodyMedium.copyWith(
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
                label: const Text('Set Access Token TTL to 10s'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
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
                  backgroundColor: Colors.purple,
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