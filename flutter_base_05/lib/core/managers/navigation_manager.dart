import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modules/home_module/home_screen.dart';
import '../../screens/websocket_screen.dart';
import '../../screens/account_screen/account_screen.dart';
import '../../screens/room_management_screen.dart';
import '../../screens/auth_test_screen/auth_test_screen.dart';
// In-app purchases screens removed - switching to RevenueCat
import '../00_base/module_base.dart';
import '../../tools/logging/logger.dart';
import 'hooks_manager.dart';

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
    final route = GoRoute(
      path: path,
      builder: (context, state) {
        Logger().info('🔍 Building route: $path');
        Logger().info('🔍 Route state: $state');
        Logger().info('🔍 Route parameters: ${state.uri.queryParameters}');
        Logger().info('🔍 Route path: ${state.uri.path}');
        Logger().info('🔍 Route full path: ${state.uri.toString()}');
        final widget = screen(context);
        Logger().info('🔍 Built widget for route: $path');
        return widget;
      },
    );
    Logger().info('🔍 Created GoRoute for path: $path');
    return route;
  }

  /// ✅ Helper method to check if route should appear in the drawer
  bool get shouldAppearInDrawer {
    return drawerTitle != null && drawerIcon != null;
  }
}

class NavigationManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final NavigationManager _instance = NavigationManager._internal();
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  // Router state
  bool _isRouterInitialized = false;
  bool _hasTriggeredRouterHook = false;
  final List<Function()> _pendingNavigations = [];
  
  factory NavigationManager() => _instance;
  NavigationManager._internal() {
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
    
    // Register Auth Test screen
    registerRoute(
      path: '/auth-test',
      screen: (context) => const AuthTestScreen(),
      drawerTitle: 'Auth Test',
      drawerIcon: Icons.security,
      drawerPosition: 5,
    );

    // In-app purchases screens removed - switching to RevenueCat
    // registerRoute(
    //   path: '/in-app-purchases',
    //   screen: (context) => const PurchaseScreen(),
    //   drawerTitle: 'In-App Purchases',
    //   drawerIcon: Icons.shopping_cart,
    //   drawerPosition: 6,
    // );
    
    // registerRoute(
    //   path: '/subscriptions',
    //   screen: (context) => const SubscriptionScreen(),
    //   drawerTitle: 'Subscriptions',
    //   drawerIcon: Icons.subscriptions,
    //   drawerPosition: 7,
    // );
  }

  final Map<String, Map<String, ModuleBase>> _modules = {};

  // Getter to access modules
  Map<String, Map<String, ModuleBase>> get modules => _modules;

  final List<RegisteredRoute> _routes = [];
  
  // Callback for navigation
  Function(String)? _navigationCallback;
  
  // Store router instance
  GoRouter? _routerInstance;
  
  // Prevent duplicate navigation calls
  String? _lastNavigationRoute;
  DateTime? _lastNavigationTime;

  /// ✅ Set navigation callback
  void setNavigationCallback(Function(String) callback) {
    _navigationCallback = callback;
  }
  
  /// ✅ Set router instance
  void setRouterInstance(GoRouter router) {
    _routerInstance = router;
    _isRouterInitialized = true;
    _log.info('🧭 Router instance set: $router');
    _log.info('🧭 Router initialized, processing pending navigations');
    _processPendingNavigations();
  }
  
  /// ✅ Mark router as initialized
  void markRouterInitialized() {
    if (_isRouterInitialized) {
      _log.info('⏸️ Router already initialized, skipping duplicate call');
      return;
    }
    
    _isRouterInitialized = true;
    _log.info('🧭 Router marked as initialized');
    _processPendingNavigations();
    
    // Trigger router initialized hook only once
    if (!_hasTriggeredRouterHook) {
      final hooksManager = HooksManager();
      hooksManager.triggerHook('router_initialized');
      _hasTriggeredRouterHook = true;
      _log.info('🔔 Router initialized hook triggered');
    }
  }

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
    if (_routes.any((r) => r.path == path)) {
      _log.info('⏸️ Route $path already registered, skipping duplicate');
      return; // Prevent duplicates
    }

    final newRoute = RegisteredRoute(
      path: path,
      screen: screen,
      drawerTitle: drawerTitle,
      drawerIcon: drawerIcon,
      drawerPosition: drawerPosition,
    );

    _routes.add(newRoute);
    _log.info('✅ Registered route: $path');

    notifyListeners();
  }


  /// ✅ Get the navigator key for global navigation
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  /// ✅ Create a dynamic GoRouter instance
  GoRouter get router {
    // If we already have a router instance, return it
    if (_routerInstance != null) {
      _log.info('🧭 Returning existing router instance: $_routerInstance');
      return _routerInstance!;
    }
    
    final allRoutes = [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      ...routes, // ✅ Include dynamically registered plugin routes
    ];
    
    _log.info('🧭 Router created with ${allRoutes.length} routes: ${allRoutes.map((r) => r.path).join(', ')}');
    
    final newRouter = GoRouter(
      navigatorKey: _navigatorKey,
      initialLocation: '/',
      routes: allRoutes,
    );
    
    // Store the router instance
    _routerInstance = newRouter;
    _log.info('🧭 Stored new router instance: $_routerInstance');
    
    return newRouter;
  }

  /// ✅ Navigate to a specific route
  void navigateTo(String route, {Map<String, dynamic>? parameters}) {
    // Prevent duplicate navigation calls within 1 second
    final now = DateTime.now();
    if (_lastNavigationRoute == route && 
        _lastNavigationTime != null && 
        now.difference(_lastNavigationTime!).inMilliseconds < 1000) {
      _log.info('⏸️ Duplicate navigation to $route within 1 second, skipping...');
      return;
    }
    
    _lastNavigationRoute = route;
    _lastNavigationTime = now;
    
    _log.info('🧭 Navigation requested to: $route');
    if (parameters != null) {
      _log.info('🧭 With parameters: $parameters');
    }
    
    try {
      if (_routerInstance != null) {
        _log.info('🧭 Using stored router instance for navigation to: $route');
        _log.info('🧭 Router instance: $_routerInstance');
        _log.info('🧭 Current location before navigation: ${_routerInstance!.routerDelegate.currentConfiguration.uri}');
        _routerInstance!.go(route);
        _log.info('✅ Successfully navigated to: $route');
        _log.info('🧭 Current location after navigation: ${_routerInstance!.routerDelegate.currentConfiguration.uri}');
      } else if (_navigationCallback != null) {
        _log.info('🧭 Executing navigation callback for route: $route');
        _navigationCallback!(route);
        _log.info('✅ Successfully navigated to: $route');
      } else {
        _log.error('❌ No router instance or callback available for route: $route');
      }
    } catch (e) {
      _log.error('❌ Navigation failed to $route: $e');
    }
  }
  
  /// ✅ Navigate to a specific route (queues if router not ready)
  void navigateToWithDelay(String route, {Map<String, dynamic>? parameters}) {
    _log.info('🧭 Navigation requested to: $route');
    if (parameters != null) {
      _log.info('🧭 With parameters: $parameters');
    }
    
    if (_isRouterInitialized && _routerInstance != null) {
      // Router is ready, navigate immediately
      navigateTo(route, parameters: parameters);
    } else {
      // Router not ready, queue the navigation
      _log.info('🧭 Router not ready, queuing navigation to: $route');
      _pendingNavigations.add(() {
        navigateTo(route, parameters: parameters);
      });
    }
  }
  
  /// ✅ Process pending navigations
  void _processPendingNavigations() {
    if (_pendingNavigations.isNotEmpty) {
      _log.info('🧭 Processing ${_pendingNavigations.length} pending navigations');
      for (final navigation in _pendingNavigations) {
        navigation();
      }
      _pendingNavigations.clear();
      _log.info('🧭 All pending navigations processed');
    }
  }

  /// ✅ Get current route
  String getCurrentRoute() {
    // TODO: Implement route tracking
    return '/';
  }

  /// ✅ Check if route exists
  bool routeExists(String route) {
    return _routes.any((r) => r.path == route);
  }
}
