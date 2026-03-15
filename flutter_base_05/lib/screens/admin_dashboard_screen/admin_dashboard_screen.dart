import 'package:flutter/material.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../utils/consts/theme_consts.dart';

/// Admin-only dashboard screen. Accessible only to users with admin role.
/// Route: /admin/dashboard (not listed in drawer).
class AdminDashboardScreen extends BaseScreen {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();

  @override
  String computeTitle(BuildContext context) => 'Admin Dashboard';
}

class _AdminDashboardScreenState extends BaseScreenState<AdminDashboardScreen> {
  void _onTournamentsTap() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login');
    final role = loginState?['role']?.toString().trim().toLowerCase();
    if (role != 'admin') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Admin access required.',
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    NavigationManager().navigateTo('/admin/tournaments');
  }

  Widget _buildTournamentsButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: AppBorderRadius.largeRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onTournamentsTap,
          borderRadius: AppBorderRadius.largeRadius,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppPadding.defaultPadding.left,
              vertical: AppPadding.smallPadding.top,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events, color: AppColors.textOnPrimary, size: 24),
                SizedBox(width: AppPadding.smallPadding.left),
                Text(
                  'Tournaments',
                  style: AppTextStyles.headingSmall().copyWith(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: AppPadding.screenPadding,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppBorderRadius.large),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: AppPadding.largePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings,
                size: 64,
                color: AppColors.accentColor,
              ),
              SizedBox(height: AppPadding.defaultPadding.top),
              Text(
                'Admin Dashboard',
                style: AppTextStyles.headingMedium(),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppPadding.smallPadding.top),
              Text(
                'Administration tools and settings will appear here.',
                style: AppTextStyles.bodyMedium().copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppPadding.largePadding.top),
              _buildTournamentsButton(),
            ],
          ),
        ),
      ),
    );
  }
}
