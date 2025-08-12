import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../utils/consts/theme_consts.dart';
import '../managers/navigation_manager.dart';

class CustomDrawer extends StatelessWidget {
  static const String drawerKey = 'drawer-main';
  static const String drawerCloseKey = 'drawer-close';
  static const String drawerOpenKey = 'drawer-burger';
  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context);
    final drawerRoutes = navigationManager.drawerRoutes;

    print("Rendering Drawer Items: ${drawerRoutes.map((r) => r.path).toList()}");

    return Semantics(
      container: true,
      label: 'drawer_container',
      identifier: 'drawer_container',
      explicitChildNodes: true,
      child: Drawer(
      key: const Key(drawerKey),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryColor, // ✅ Background color
          image: DecorationImage(
            image: AssetImage('assets/images/icon_foreground.png'), // ✅ Background image
            fit: BoxFit.cover, // ✅ Make sure it covers the drawer
            opacity: 0.2, // ✅ Adjust opacity to blend with background
          ),
        ),
        child: Column(
          children: [
            // ✅ Drawer Header with Image
            DrawerHeader(
              child: Row(
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
                  Text(
                    'Menu',
                    style: AppTextStyles.headingMedium(color: AppColors.white),
                  ),
                ],
              ),
            ),
            // ✅ Drawer Items List
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Semantics(
                    label: 'drawer_item_home',
                    identifier: 'drawer_item_home',
                    button: true,
                    child: ListTile(
                    leading: Icon(Icons.home, color: AppColors.accentColor),
                    title: Text('Home', style: AppTextStyles.bodyLarge),
                    onTap: () => context.go('/'),
                  ),
                  ),
                  ...drawerRoutes.map((route) {
                    return Semantics(
                      label: 'drawer_item_${route.drawerTitle ?? 'item'}',
                      identifier: 'drawer_item_${route.drawerTitle ?? 'item'}',
                      button: true,
                      child: ListTile(
                      leading: Icon(route.drawerIcon, color: AppColors.accentColor),
                      title: Text(route.drawerTitle ?? '', style: AppTextStyles.bodyLarge),
                      onTap: () => context.go(route.path),
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
