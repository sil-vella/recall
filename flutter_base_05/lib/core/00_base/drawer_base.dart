import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_avatar.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_section_header.dart';
import '../../modules/dutch_game/widgets/ui_kit/dutch_settings_row.dart';
import '../../utils/consts/theme_consts.dart';
import '../managers/navigation_manager.dart';
import '../managers/state_manager.dart';

class CustomDrawer extends StatelessWidget {
  static const String drawerKey = 'drawer-main';
  static const String drawerCloseKey = 'drawer-close';
  static const String drawerOpenKey = 'drawer-burger';

  const CustomDrawer({super.key});

  bool _isRouteActive(String currentPath, String routePath) {
    if (routePath == '/') return currentPath == '/';
    return currentPath == routePath || currentPath.startsWith('$routePath/');
  }

  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context);
    final drawerRoutes = navigationManager.drawerRoutes;
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentPath = GoRouterState.of(context).uri.path;
    final displayName = (loginState['username']?.toString() ?? '').trim();
    final email = (loginState['email']?.toString() ?? '').trim();
    final profilePicture = (loginState['profilePicture']?.toString() ?? '').trim();

    print("Rendering Drawer Items: ${drawerRoutes.map((r) => r.path).toList()}");

    return Semantics(
      container: true,
      label: 'drawer_container',
      identifier: 'drawer_container',
      explicitChildNodes: true,
      child: Drawer(
      key: const Key(drawerKey),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accentContrast,
              AppColors.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: AppColors.accentContrast.withValues(alpha: 0.28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'drawer_close',
                        identifier: 'drawer_close',
                        button: true,
                        child: IconButton(
                          key: const Key('drawer-close-button'),
                          icon: Icon(Icons.close, color: AppColors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const Expanded(
                        child: DutchSectionHeader(
                          title: 'Menu',
                          icon: Icons.menu,
                          dense: true,
                          semanticIdentifier: 'drawer_menu_header',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      DutchAvatar(
                        displayName: displayName.isNotEmpty
                            ? displayName
                            : (email.isNotEmpty ? email : 'Player'),
                        imageUrl: profilePicture.isNotEmpty ? profilePicture : null,
                        size: 38,
                        semanticIdentifier: 'drawer_profile_avatar',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName
                              : (email.isNotEmpty ? email : 'Welcome'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium(color: AppColors.white).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Drawer Items List
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Semantics(
                    label: 'drawer_item_home',
                    identifier: 'drawer_item_home',
                    button: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: DutchSettingsRow(
                        title: 'Home',
                        leadingIcon: Icons.home,
                        semanticIdentifier: 'drawer_item_home_row',
                        subtitle: _isRouteActive(currentPath, '/') ? 'Current screen' : null,
                        trailing: _isRouteActive(currentPath, '/')
                            ? Icon(Icons.check_circle, color: AppColors.accentColor, size: 18)
                            : Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                        onTap: () => context.go('/'),
                      ),
                    ),
                  ),
                  ...drawerRoutes.map((route) {
                    final title = route.drawerTitle ?? '';
                    final active = _isRouteActive(currentPath, route.path);
                    return Semantics(
                      label: 'drawer_item_${route.drawerTitle ?? 'item'}',
                      identifier: 'drawer_item_${route.drawerTitle ?? 'item'}',
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: DutchSettingsRow(
                          title: title,
                          leadingIcon: route.drawerIcon,
                          subtitle: active ? 'Current screen' : null,
                          trailing: active
                              ? Icon(Icons.check_circle, color: AppColors.accentColor, size: 18)
                              : Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                          onTap: () => context.go(route.path),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
