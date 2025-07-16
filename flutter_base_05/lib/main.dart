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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appManager = Provider.of<AppManager>(context);
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!appManager.isInitialized) {
        appManager.initializeApp(context);
      }
    });

    if (!appManager.isInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: "recall App",
      theme: ThemeData.dark(),
      routerConfig: navigationManager.router,
    );
  }
}