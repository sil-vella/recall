import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/module_registry.dart';
import 'core/managers/navigation_manager.dart';
import 'core/managers/provider_manager.dart';
import 'modules/analytics_module/analytics_module.dart';
import 'tools/logging/logger.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up global error handlers for analytics tracking
  _setupErrorHandlers();

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
  bool _isInitializing = false;
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) {
      return;
    }
    
    setState(() {
      _isInitializing = true;
    });

    try {
      final appManager = Provider.of<AppManager>(context, listen: false);
      final navigationManager = Provider.of<NavigationManager>(context, listen: false);

      // Set up navigation callback first
      navigationManager.setNavigationCallback((route) {
        final router = navigationManager.router;
        router.go(route);
      });
      
      // Mark router as initialized after MaterialApp is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigationManager.markRouterInitialized();
        // Hook is already triggered by markRouterInitialized()
      });
      
      // Initialize the app and wait for completion
      if (!appManager.isInitialized) {
        await appManager.initializeApp(context);
      }

      // Trigger rebuild after initialization is complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        
        // Test log after app is fully loaded
        _logger.info('🚀 App fully loaded and initialized successfully!', isOn: LOGGING_SWITCH);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appManager = Provider.of<AppManager>(context);
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);

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
    
    // Set the router instance in NavigationManager
    navigationManager.setRouterInstance(router);
    
    return MaterialApp.router(
      title: "Cleco App",
      theme: ThemeData.dark(),
      routerConfig: router,
    );
  }
}

/// Set up global error handlers for analytics tracking
void _setupErrorHandlers() {
  // Handle Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _trackError(
      error: details.exception.toString(),
      stackTrace: details.stack?.toString(),
      context: 'Flutter Framework Error',
      additionalData: {
        'library': details.library,
        'information': details.informationCollector?.call().toString(),
      },
    );
  };
  
  // Handle platform errors (async errors not caught by Flutter)
  PlatformDispatcher.instance.onError = (error, stack) {
    _trackError(
      error: error.toString(),
      stackTrace: stack?.toString(),
      context: 'Platform Error',
    );
    return true; // Return true to indicate error was handled
  };
}

/// Track error in analytics
void _trackError({
  required String error,
  String? stackTrace,
  String? context,
  Map<String, dynamic>? additionalData,
}) {
  try {
    // Get analytics module (may not be initialized yet, so handle gracefully)
    final moduleManager = ModuleManager();
    final analyticsModule = moduleManager.getModuleByType<AnalyticsModule>();
    
    if (analyticsModule != null) {
      // Track error asynchronously (don't await to avoid blocking)
      analyticsModule.trackError(
        error: error,
        stackTrace: stackTrace,
        context: context,
        additionalData: additionalData,
      );
    }
  } catch (e) {
    // Silently fail - don't break app if analytics fails
  }
}