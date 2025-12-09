import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modules/home_module/home_screen.dart';
import '../../screens/websocket_screen.dart';
import '../../screens/account_screen/account_screen.dart';
import '../../screens/auth_test_screen/auth_test_screen.dart';
import '../../screens/update_required_screen/update_required_screen.dart';
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
        // Pass state to screen builder so it can access query parameters
        final widget = screen(context);
        return widget;
      },
    );
    return route;
  }

  /// ✅ Helper method to check if route should appear in the drawer
  bool get shouldAppearInDrawer {
    return drawerTitle != null && drawerIcon != null;
  }
}

class NavigationManager extends ChangeNotifier {
  static final Logger _logger = Logger();
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
        
    // Register Auth Test screen
    registerRoute(
      path: '/auth-test',
      screen: (context) => const AuthTestScreen(),
      drawerTitle: 'Auth Test',
      drawerIcon: Icons.security,
      drawerPosition: 5,
    );
    
    // Register Update Required screen (no drawer entry - blocking screen)
    registerRoute(
      path: '/update-required',
      screen: (context) => const UpdateRequiredScreen(),
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
    _processPendingNavigations();
  }
  
  /// ✅ Mark router as initialized
  void markRouterInitialized() {
    if (_isRouterInitialized) {
      return;
    }
    
    _isRouterInitialized = true;
    _processPendingNavigations();
    
    // Trigger router initialized hook only once
    if (!_hasTriggeredRouterHook) {
      final hooksManager = HooksManager();
      hooksManager.triggerHook('router_initialized');
      _hasTriggeredRouterHook = true;
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

    notifyListeners();
  }


  /// ✅ Get the navigator key for global navigation
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  /// ✅ Create a dynamic GoRouter instance
  GoRouter get router {
    // If we already have a router instance, return it
    if (_routerInstance != null) {
      return _routerInstance!;
    }
    
    final allRoutes = [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      ...routes, // ✅ Include dynamically registered plugin routes
    ];
    
    final newRouter = GoRouter(
      navigatorKey: _navigatorKey,
      initialLocation: '/',
      routes: allRoutes,
    );
    
    // Store the router instance
    _routerInstance = newRouter;
    
    return newRouter;
  }

  /// ✅ Navigate to a specific route
  void navigateTo(String route, {Map<String, dynamic>? parameters}) {
    // Prevent duplicate navigation calls within 1 second
    final now = DateTime.now();
    if (_lastNavigationRoute == route && 
        _lastNavigationTime != null && 
        now.difference(_lastNavigationTime!).inMilliseconds < 1000) {
      return;
    }
    
    _lastNavigationRoute = route;
    _lastNavigationTime = now;
    
    // Append query parameters if provided
    String finalRoute = route;
    if (parameters != null && parameters.isNotEmpty) {
      final uri = Uri.parse(route);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      parameters.forEach((key, value) {
        queryParams[key] = value.toString();
      });
      finalRoute = uri.replace(queryParameters: queryParams).toString();
    }
    
    try {
      if (_routerInstance != null) {
        _routerInstance!.go(finalRoute);
      } else if (_navigationCallback != null) {
        _navigationCallback!(finalRoute);
      }
    } catch (e) {
      // Navigation failed
    }
  }
  
  /// ✅ Navigate to a specific route (queues if router not ready)
  void navigateToWithDelay(String route, {Map<String, dynamic>? parameters}) {
    if (_isRouterInitialized && _routerInstance != null) {
      // Router is ready, navigate immediately
      navigateTo(route, parameters: parameters);
    } else {
      // Router not ready, queue the navigation
      _pendingNavigations.add(() {
        navigateTo(route, parameters: parameters);
      });
    }
  }
  
  /// ✅ Process pending navigations
  void _processPendingNavigations() {
    if (_pendingNavigations.isNotEmpty) {
      for (final navigation in _pendingNavigations) {
        navigation();
      }
      _pendingNavigations.clear();
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
