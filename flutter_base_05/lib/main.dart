import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/module_registry.dart';
import 'core/managers/services_manager.dart';
import 'core/managers/state_manager.dart';
import 'core/managers/navigation_manager.dart';
import 'core/managers/auth_manager.dart';
import 'core/managers/hooks_manager.dart';
import 'tools/logging/logger.dart';

import 'utils/consts/config.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize platform-specific implementations
  await Future.wait([
    // Add any other platform-specific initializations here
  ]);

  final servicesManager = ServicesManager();
  await servicesManager.autoRegisterAllServices();

  // Initialize module registry and manager
  final moduleRegistry = ModuleRegistry();
  final moduleManager = ModuleManager();
  
  // Initialize registry and register all modules
  moduleRegistry.initializeRegistry();
  moduleRegistry.registerAllModules(moduleManager);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppManager()),
        ChangeNotifierProvider(create: (_) => moduleManager),
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
    final appManager = Provider.of<AppManager>(context);
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
      if (!appManager.isInitialized) {
        appManager.initializeApp(context);
      }
    });

    if (!appManager.isInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = navigationManager.router;
    _log.info('🧭 MaterialApp.router using router: $router');
    
    // Set the router instance in NavigationManager
    navigationManager.setRouterInstance(router);
    
    return MaterialApp.router(
      title: "recall App",
      theme: ThemeData.dark(),
      routerConfig: router,
    );
  }
}