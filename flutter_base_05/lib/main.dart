import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:dutch/core/widgets/adsense_placeholder_stub.dart' if (dart.library.html) 'package:dutch/core/widgets/adsense_placeholder_web.dart' as adsense_placeholder;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/module_registry.dart';
import 'core/managers/navigation_manager.dart';
import 'core/managers/provider_manager.dart';
import 'modules/analytics_module/analytics_module.dart';
import 'tools/logging/logger.dart';
import 'utils/firebase_runtime_config.dart';
import 'utils/consts/theme_consts.dart';
import 'modules/promotional_ads_module/promotional_ads_config_loader.dart';

// Logging switch for main.dart - enable for debugging init (see .cursor/rules/enable-logging-switch.mdc)
const bool LOGGING_SWITCH = true; // App init — enable-logging-switch.mdc

Future<void> main() async {
  final logger = Logger();
  if (LOGGING_SWITCH) logger.info('main: start', isOn: true);

  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  if (LOGGING_SWITCH) logger.info('main: WidgetsBinding done', isOn: true);

  await PromotionalAdsConfigLoader.loadFromAsset('assets/promotional_ads.yaml');
  if (LOGGING_SWITCH) logger.info('main: promotional ads YAML loaded', isOn: true);

  // Initialize Firebase (Analytics, AdMob-ready) only when enabled.
  if (FirebaseRuntimeConfig.isEnabled) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      if (LOGGING_SWITCH) logger.info('main: Firebase.initializeApp done', isOn: true);
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') {
        // Native side already has default app (e.g. Android auto-init from google-services.json).
        if (LOGGING_SWITCH) logger.info('main: Firebase already initialized (duplicate-app ignored)', isOn: true);
      } else {
        if (LOGGING_SWITCH) logger.error('main: Firebase.initializeApp failed', error: e, stackTrace: e.stackTrace, isOn: true);
        rethrow;
      }
    } catch (e, st) {
      if (LOGGING_SWITCH) logger.error('main: Firebase.initializeApp failed', error: e, stackTrace: st, isOn: true);
      rethrow;
    }
  } else {
    if (LOGGING_SWITCH) logger.info('main: Firebase initialization skipped (FIREBASE_SWITCH=false)', isOn: true);
  }

  // Set up global error handlers for analytics tracking
  _setupErrorHandlers();
  if (LOGGING_SWITCH) logger.info('main: error handlers set', isOn: true);

  // Initialize platform-specific implementations
  await Future.wait([
    // Add any other platform-specific initializations here
  ]);

  // Initialize module registry and manager
  final moduleRegistry = ModuleRegistry();
  final moduleManager = ModuleManager();
  if (LOGGING_SWITCH) logger.info('main: ModuleRegistry/ModuleManager created', isOn: true);

  // Initialize registry and register all modules
  moduleRegistry.initializeRegistry();
  moduleRegistry.registerAllModules(moduleManager);
  if (LOGGING_SWITCH) logger.info('main: modules registered', isOn: true);

  // Register core providers
  ProviderManager().registerCoreProviders();
  if (LOGGING_SWITCH) logger.info('main: calling runApp', isOn: true);

  // AdSense view factories (web only); no-op on mobile
  if (kIsWeb) adsense_placeholder.registerAdSenseViewFactories();

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
  static final Logger _logger = Logger();

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
    if (LOGGING_SWITCH) _logger.info('_initializeApp: start', isOn: true);

    setState(() {
      _isInitializing = true;
    });

    try {
      final appManager = Provider.of<AppManager>(context, listen: false);
      final navigationManager = Provider.of<NavigationManager>(context, listen: false);
      if (LOGGING_SWITCH) _logger.info('_initializeApp: got AppManager and NavigationManager', isOn: true);

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
        if (LOGGING_SWITCH) _logger.info('_initializeApp: calling appManager.initializeApp', isOn: true);
        await appManager.initializeApp(context);
        if (LOGGING_SWITCH) _logger.info('_initializeApp: appManager.initializeApp done', isOn: true);
      }

      // Trigger rebuild after initialization is complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        if (LOGGING_SWITCH) _logger.info('🚀 App fully loaded and initialized successfully!', isOn: true);
      }

    } catch (e, st) {
      if (LOGGING_SWITCH) _logger.error('_initializeApp: error', error: e, stackTrace: st, isOn: true);
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
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Initializing app...', style: AppTextStyles.bodyMedium().copyWith(
                  color: AppColors.textOnPrimary,
                )),
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
      title: "Dutch App",
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}

/// Set up global error handlers for analytics tracking
void _setupErrorHandlers() {
  final logger = Logger();
  
  // Handle Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log to our logger system
    if (LOGGING_SWITCH) {
      logger.error(
        'Flutter Framework Error: ${details.exception}',
        error: details.exception,
        stackTrace: details.stack,
      );
    }
    
    // Log additional context
    if (LOGGING_SWITCH) {
      logger.debug(
        'Flutter Error Details - Library: ${details.library}, Context: ${details.context}',
      );
    }
    
    // Present error (shows red screen in debug mode)
    FlutterError.presentError(details);
    
    // Track in analytics
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
    // Log to our logger system
    if (LOGGING_SWITCH) {
      logger.error(
        'Platform Error: $error',
        error: error,
        stackTrace: stack,
      );
    }
    
    // Track in analytics
    _trackError(
      error: error.toString(),
      stackTrace: stack.toString(),
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