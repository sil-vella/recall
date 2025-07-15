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

/// widget MyApp - Flutter widget for UI components
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// MyApp()
/// ```
///
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// widget _MyAppState - Flutter widget for UI components
///
/// A Flutter widget that provides UI functionality
///
/// Example:
/// ```dart
/// _MyAppState()
/// ```
///
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final AppManager _appManager = AppManager();
  final StateManager _stateManager = StateManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Update app lifecycle state (separate from main app state)
    switch (state) {
      case AppLifecycleState.resumed:
        _stateManager.updateMainAppState("app_state", "resumed");
        break;
      case AppLifecycleState.inactive:
        _stateManager.updateMainAppState("app_state", "inactive");
        break;
      case AppLifecycleState.paused:
        _stateManager.updateMainAppState("app_state", "paused");
        break;
      case AppLifecycleState.detached:
        _stateManager.updateMainAppState("app_state", "detached");
        break;
      case AppLifecycleState.hidden:
        _stateManager.updateMainAppState("app_state", "hidden");
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_appManager.isInitialized) {
        _appManager.initializeApp(context);
      }
    });

    if (!_appManager.isInitialized) {
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
