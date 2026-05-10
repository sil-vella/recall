import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modules/home_module/home_screen.dart';
import '../../screens/websocket_screen.dart';
import '../../screens/account_screen/account_screen.dart';
import '../../screens/auth_test_screen/auth_test_screen.dart';
import '../../screens/notifications_screen/notifications_screen.dart';
// In-app purchases screens removed - switching to RevenueCat
import '../00_base/module_base.dart';
import 'hooks_manager.dart';
import '../../modules/analytics_module/analytics_module.dart';
import '../../utils/analytics_service.dart';
import '../../modules/promotional_ads_module/ads_navigator_observer.dart';
import 'module_manager.dart';

/// Hash URLs: `http://host/#/path?query`. Path URLs: `http://host/path?query`.
String computeWebInitialLocation() {
  if (!kIsWeb) return '/';

  final fragment = Uri.base.fragment;
  if (fragment.isNotEmpty) {
    final fromFragment = fragment.startsWith('/') ? fragment : '/$fragment';
    return fromFragment;
  }

  // Path-based Stripe return support (when success/cancel URL is not hash-based).
  final path = Uri.base.path;
  final q = Uri.base.query;
  final hasStripeReturnSignals =
      Uri.base.queryParameters.containsKey('session_id') ||
      Uri.base.queryParameters.containsKey('stripe_checkout');
  if (path == '/coin-purchase' || path.endsWith('/coin-purchase')) {
    final fromPath = q.isEmpty ? '/coin-purchase' : '/coin-purchase?$q';
    return fromPath;
  }
  if (hasStripeReturnSignals) {
    final fromSignal = q.isEmpty ? '/coin-purchase' : '/coin-purchase?$q';
    return fromSignal;
  }

  return '/';
}

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
  static final NavigationManager _instance = NavigationManager._internal();
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  // Router state
  bool _isRouterInitialized = false;
  bool _hasTriggeredRouterHook = false;
  final List<Function()> _pendingNavigations = [];
  final List<Function()> _pendingPushNavigations = [];
  
  // Analytics tracking
  AnalyticsModule? _analyticsModule;
  
  factory NavigationManager() => _instance;
  NavigationManager._internal() {
    // Register Account screen
    registerRoute(
      path: '/account',
      screen: (context) => AccountScreen(),
      drawerTitle: 'My Account',
      drawerIcon: Icons.account_circle,
      drawerPosition: 60, // After Dutch drawer items (10–50); keep below Leaderboard / Buy coins
    );

    registerRoute(
      path: '/notifications',
      screen: (context) => const NotificationsScreen(),
      drawerTitle: null,
      drawerIcon: null,
      drawerPosition: 999,
    );
    
    // Register WebSocket test screen (hidden from drawer)
    registerRoute(
      path: '/websocket',
      screen: (context) => const WebSocketScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
    );
        
    // Register Auth Test screen (hidden from drawer)
    registerRoute(
      path: '/auth-test',
      screen: (context) => const AuthTestScreen(),
      drawerTitle: null, // Hidden from drawer
      drawerIcon: null,
      drawerPosition: 999,
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

  final AdsSwitchScreenNavigatorObserver _adsSwitchScreenObserver =
      AdsSwitchScreenNavigatorObserver();

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

    // Sort by `drawerPosition`, then path (deterministic when positions tie).
    filteredRoutes.sort((a, b) {
      final byPos = a.drawerPosition.compareTo(b.drawerPosition);
      if (byPos != 0) return byPos;
      return a.path.compareTo(b.path);
    });

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
      initialLocation: kIsWeb ? computeWebInitialLocation() : '/',
      routes: allRoutes,
      observers: <NavigatorObserver>[_adsSwitchScreenObserver],
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
    
    // Track screen view
    _trackScreenView(route);
    
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

  /// Navigates with [GoRouter.push] so Android back returns to the previous route.
  ///
  /// If already on the same path as [route], uses [go] instead to avoid stacking
  /// duplicate entries. Analytics and dedup match [navigateTo].
  void navigateToPush(String route, {Map<String, dynamic>? parameters}) {
    final now = DateTime.now();
    if (_lastNavigationRoute == route &&
        _lastNavigationTime != null &&
        now.difference(_lastNavigationTime!).inMilliseconds < 1000) {
      return;
    }

    _lastNavigationRoute = route;
    _lastNavigationTime = now;

    _trackScreenView(route);

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
        final currentPath = _routerInstance!.routeInformationProvider.value.uri.path;
        final targetPath = Uri.parse(finalRoute).path;
        if (currentPath == targetPath) {
          _routerInstance!.go(finalRoute);
        } else {
          _routerInstance!.push(finalRoute);
        }
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

  /// Queues [navigateToPush] until the router is ready (mirrors [navigateToWithDelay]).
  void navigateToPushWithDelay(String route, {Map<String, dynamic>? parameters}) {
    if (_isRouterInitialized && _routerInstance != null) {
      navigateToPush(route, parameters: parameters);
    } else {
      _pendingPushNavigations.add(() {
        navigateToPush(route, parameters: parameters);
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
    if (_pendingPushNavigations.isNotEmpty) {
      for (final navigation in _pendingPushNavigations) {
        navigation();
      }
      _pendingPushNavigations.clear();
    }
  }

  /// ✅ Get current route
  String getCurrentRoute() {
    try {
      if (_routerInstance != null) {
        final uri = _routerInstance!.routeInformationProvider.value.uri;
        final path = uri.path;
        if (path.isNotEmpty) {
          return path;
        }
      }
    } catch (_) {
      // Fall through to best-effort fallback.
    }
    return _lastNavigationRoute ?? '/';
  }

  /// ✅ Check if route exists
  bool routeExists(String route) {
    return _routes.any((r) => r.path == route);
  }
  
  /// Track screen view for analytics
  void _trackScreenView(String route) {
    try {
      // Get analytics module if not already cached
      if (_analyticsModule == null) {
        final moduleManager = ModuleManager();
        _analyticsModule = moduleManager.getModuleByType<AnalyticsModule>();
      }
      
      // Extract screen name from route (remove leading slash)
      var screenName = route.startsWith('/') ? route.substring(1) : route;
      if (screenName.isEmpty) {
        screenName = 'home';
      }
      
      // Track screen view asynchronously (don't await to avoid blocking navigation)
      _analyticsModule?.trackScreenView(screenName);
      AnalyticsService.logScreenView(screenName);
    } catch (e) {
      // Silently fail - don't block navigation if analytics fails
    }
  }
}
