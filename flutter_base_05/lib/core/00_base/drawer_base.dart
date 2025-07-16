import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../utils/consts/theme_consts.dart';
import '../managers/navigation_manager.dart';

class CustomDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context);
    final drawerRoutes = navigationManager.drawerRoutes;

    print("Rendering Drawer Items: ${drawerRoutes.map((r) => r.path).toList()}");

    return Drawer(
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

              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Menu',
                  style: AppTextStyles.headingMedium(color: AppColors.white),
                ),
              ),
            ),
            // ✅ Drawer Items List
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: Icon(Icons.home, color: AppColors.accentColor),
                    title: Text('Home', style: AppTextStyles.bodyLarge),
                    onTap: () => context.go('/'),
                  ),
                  ...drawerRoutes.map((route) {
                    return ListTile(
                      leading: Icon(route.drawerIcon, color: AppColors.accentColor),
                      title: Text(route.drawerTitle ?? '', style: AppTextStyles.bodyLarge),
                      onTap: () => context.go(route.path),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
