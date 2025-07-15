import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modules/home_module/home_screen.dart';
import '../../screens/websocket_screen.dart';
import '../../screens/account_screen/account_screen.dart';
import '../../screens/room_management_screen.dart';
import '../00_base/module_base.dart';

/// widget RegisteredRoute - Flutter widget for UI components
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// RegisteredRoute()
/// ```
///
class RegisteredRoute {
  final String path;
  final Widget Function(BuildContext) screen;
  final String? drawerTitle;
  final IconData? drawerIcon;
  final int drawerPosition;

  RegisteredRoute({
    required this.path,
    required this.screen,
    this.drawerTitle,
    this.drawerIcon,
    this.drawerPosition = 999,
  });


  GoRoute toGoRoute() {
    return GoRoute(
      path: path,
      builder: (context, state) => screen(context),
    );
  }

  /// ✅ Helper method to check if route should appear in the drawer
  bool get shouldAppearInDrawer {
    return drawerTitle != null && drawerIcon != null;
  }
}

/// widget NavigationManager - Manages application state and operations
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// NavigationManager()
/// ```
///
class NavigationManager extends ChangeNotifier {
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal() {
    // Register default routes
    registerRoute(
      path: '/',
      screen: (context) => const HomeScreen(),
      drawerTitle: 'Home',
      drawerIcon: Icons.card_giftcard,
      drawerPosition: 1,
    );
    
    // Register Account screen
    registerRoute(
      path: '/account',
      screen: (context) => AccountScreen(),
      drawerTitle: 'Account',
      drawerIcon: Icons.account_circle,
      drawerPosition: 2,
    );
    
    // Register WebSocket test screen
    registerRoute(
      path: '/websocket',
      screen: (context) => const WebSocketScreen(),
      drawerTitle: 'WebSocket Test',
      drawerIcon: Icons.wifi,
      drawerPosition: 3,
    );
    
    // Register Room Management screen
    registerRoute(
      path: '/rooms',
      screen: (context) => const RoomManagementScreen(),
      drawerTitle: 'Room Management',
      drawerIcon: Icons.room,
      drawerPosition: 4,
    );
  }

  final Map<String, Map<String, ModuleBase>> _modules = {};

  // Getter to access modules
  Map<String, Map<String, ModuleBase>> get modules => _modules;

  final List<RegisteredRoute> _routes = [];

  /// ✅ Getter for dynamically registered routes
  List<GoRoute> get routes => _routes.map((r) => r.toGoRoute()).toList();

  List<RegisteredRoute> get drawerRoutes {
    final filteredRoutes = _routes.where((r) => r.shouldAppearInDrawer).toList();

    // ✅ Sort drawer items based on `drawerPosition`
    filteredRoutes.sort((a, b) => a.drawerPosition.compareTo(b.drawerPosition));

    return filteredRoutes;
  }

  void registerRoute({
    required String path,
    required Widget Function(BuildContext) screen,
    String? drawerTitle,
    IconData? drawerIcon,
    int drawerPosition = 999, // ✅ Default low priority
  }) {
    if (_routes.any((r) => r.path == path)) return; // Prevent duplicates

    final newRoute = RegisteredRoute(
      path: path,
      screen: screen,
      drawerTitle: drawerTitle,
      drawerIcon: drawerIcon,
      drawerPosition: drawerPosition,
    );

    _routes.add(newRoute);

    notifyListeners();
  }


  /// ✅ Create a dynamic GoRouter instance
  GoRouter get router {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        ...routes, // ✅ Include dynamically registered plugin routes
      ],
    );
  }
}
