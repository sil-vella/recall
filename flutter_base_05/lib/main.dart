import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/module_registry.dart';
import 'core/managers/navigation_manager.dart';
import 'core/managers/provider_manager.dart';
import 'tools/logging/logger.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Add a simple print to see if the app is even starting
  print('🚀 FLUTTER APP MAIN FUNCTION STARTED');
  debugPrint('🚀 FLUTTER APP MAIN FUNCTION STARTED');

  // Initialize platform-specific implementations
  await Future.wait([
    // Add any other platform-specific initializations here
  ]);

  // Initialize module registry and manager
  final moduleRegistry = ModuleRegistry();
  final moduleManager = ModuleManager();
  
  // Initialize registry and register all modules
  moduleRegistry.initializeRegistry();
  moduleRegistry.registerAllModules(moduleManager);

  // Register core providers
  ProviderManager().registerCoreProviders();

  runApp(
    MultiProvider(
      providers: [
        // All providers from ProviderManager
        ...ProviderManager().providers,
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final Logger _log = Logger();
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _log.info('🚀 MyApp initState called');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log.info('📅 PostFrameCallback executing, calling _initializeApp');
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    _log.info('🔍 _initializeApp called, _isInitializing: $_isInitializing');
    
    if (_isInitializing) {
      _log.info('⏳ Already initializing, returning early');
      return;
    }
    
    _log.info('🎯 Setting _isInitializing to true and starting initialization');
    setState(() {
      _isInitializing = true;
    });

    try {
      final appManager = Provider.of<AppManager>(context, listen: false);
      final navigationManager = Provider.of<NavigationManager>(context, listen: false);

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
      
      // Initialize the app and wait for completion
      if (!appManager.isInitialized) {
        _log.info('🚀 Starting app initialization from MyApp...');
        await appManager.initializeApp(context);
        _log.info('✅ App initialization completed in MyApp');
      }

      // Trigger rebuild after initialization is complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

    } catch (e) {
      _log.error('❌ App initialization failed in MyApp: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🏗️ MyApp build() called');
    debugPrint('🏗️ MyApp build() called');
    
    final appManager = Provider.of<AppManager>(context);
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);
    
    print('📊 AppManager isInitialized: ${appManager.isInitialized}');
    debugPrint('📊 AppManager isInitialized: ${appManager.isInitialized}');

    // Show loading screen while initializing
    if (_isInitializing || !appManager.isInitialized) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Initializing app...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
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