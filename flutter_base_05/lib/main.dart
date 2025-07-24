import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'system/orchestration/app_init/index.dart';
import 'system/managers/services_manager.dart';
import 'system/managers/state_manager.dart';
import 'system/managers/navigation_manager.dart';
import 'system/managers/auth_manager.dart';
import 'tools/logging/logger.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize platform-specific implementations
  await Future.wait([
    // Add any other platform-specific initializations here
  ]);

  final servicesManager = ServicesManager();
  await servicesManager.autoRegisterAllServices();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppInitializer()),
        ChangeNotifierProvider(create: (_) => servicesManager),
        ChangeNotifierProvider(create: (_) => StateManager()),
        ChangeNotifierProvider(create: (_) => NavigationManager()),
        ChangeNotifierProvider(create: (_) => AuthManager()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  static final Logger _log = Logger();
  
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appInitializer = Provider.of<AppInitializer>(context);
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Set up navigation callback first
      navigationManager.setNavigationCallback((route) {
        final router = navigationManager.router;
        _log.info('🧭 Navigation callback executing for route: $route');
        _log.info('🧭 Router instance: $router');
        router.go(route);
        _log.info('🧭 Router.go() called for route: $route');
      });
      
      // Mark router as initialized after MaterialApp is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigationManager.markRouterInitialized();
        // Hook is already triggered by markRouterInitialized()
      });
      
      // Then initialize the app
      if (!appInitializer.isInitialized) {
        appInitializer.initializeApp(context);
      }
    });

    if (!appInitializer.isInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = navigationManager.router;
    _log.info('🧭 MaterialApp.router using router: $router');
    
    // Set the router instance in NavigationManager
    navigationManager.setRouterInstance(router);
    
    return MaterialApp.router(
      title: "Recall App",
      theme: ThemeData.dark(),
      routerConfig: router,
    );
  }
}