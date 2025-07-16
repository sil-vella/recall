# Troubleshooting Guide

## Overview

This troubleshooting guide provides solutions for common issues encountered when developing and deploying Flutter Base 05 applications. It covers debugging techniques, error resolution, and best practices for maintaining application stability.

## Common Issues and Solutions

### 1. Module Registration Issues

#### Problem: Module not found or not initialized

**Symptoms**:
- Error: "Module 'example_module' not found"
- Module not appearing in health checks
- Dependencies not resolved

**Solutions**:

1. **Check Module Registration**
   ```dart
   // Ensure module is registered in ModuleRegistry
   class ModuleRegistry {
     void registerAllModules(ModuleManager moduleManager) {
       moduleManager.registerModule(YourModule());
     }
   }
   ```

2. **Verify Dependencies**
   ```dart
   class YourModule extends ModuleBase {
     YourModule() : super("your_module", dependencies: ["required_module"]);
   }
   ```

3. **Check Initialization Order**
   ```dart
   // Ensure dependencies are initialized first
   @override
   void initialize(BuildContext context, ModuleManager moduleManager) {
     super.initialize(context, moduleManager);
     
     // Get dependencies
     final requiredModule = moduleManager.getModuleByType<RequiredModule>();
     if (requiredModule == null) {
       throw Exception("Required module not found");
     }
   }
   ```

#### Problem: Circular dependencies

**Symptoms**:
- Stack overflow during initialization
- Infinite loop in module registration

**Solutions**:

1. **Review Dependency Graph**
   ```dart
   // Avoid circular dependencies
   class ModuleA extends ModuleBase {
     ModuleA() : super("module_a", dependencies: ["module_b"]);
   }
   
   class ModuleB extends ModuleBase {
     ModuleB() : super("module_b", dependencies: []); // No circular dependency
   }
   ```

2. **Use Event-Based Communication**
   ```dart
   // Instead of direct dependencies, use events
   class EventBus {
     void publish(String event, [Map<String, dynamic>? data]);
     void subscribe(String event, Function callback);
   }
   ```

### 2. State Management Issues

#### Problem: State not updating or UI not rebuilding

**Symptoms**:
- UI not reflecting state changes
- State updates not persisting
- Memory leaks

**Solutions**:

1. **Check State Registration**
   ```dart
   // Ensure state is properly registered
   final stateManager = StateManager();
   stateManager.registerModuleState("module_key", {
     "initial_value": "default",
   });
   ```

2. **Verify State Updates**
   ```dart
   // Use proper state update method
   stateManager.updateModuleState("module_key", {
     "new_value": "updated",
   });
   ```

3. **Check Provider Setup**
   ```dart
   // Ensure StateManager is provided
   MultiProvider(
     providers: [
       ChangeNotifierProvider(create: (_) => StateManager()),
     ],
     child: MyApp(),
   )
   ```

4. **Debug State Changes**
   ```dart
   // Add logging to track state changes
   class StateManager with ChangeNotifier {
     void updateModuleState(String moduleKey, Map<String, dynamic> newState) {
       _log.info("Updating state for module: $moduleKey");
       _log.info("New state: $newState");
       // ... update logic
       notifyListeners();
     }
   }
   ```

#### Problem: State conflicts between modules

**Symptoms**:
- State overwritten by other modules
- Inconsistent state across modules

**Solutions**:

1. **Use Unique Module Keys**
   ```dart
   // Use descriptive, unique keys
   stateManager.registerModuleState("user_profile_module", {});
   stateManager.registerModuleState("game_state_module", {});
   ```

2. **Implement State Namespacing**
   ```dart
   // Use nested state structure
   stateManager.registerModuleState("user_module", {
     "profile": {},
     "preferences": {},
     "settings": {},
   });
   ```

### 3. Authentication Issues

#### Problem: JWT token not being sent with requests

**Symptoms**:
- 401 Unauthorized errors
- API requests failing
- Token not found in headers

**Solutions**:

1. **Check Token Storage**
   ```dart
   final authManager = AuthManager();
   final token = await authManager.getAccessToken();
   if (token == null) {
     // Handle missing token
     await authManager.handleAuthState(context, AuthStatus.loggedOut);
   }
   ```

2. **Verify Interceptor Setup**
   ```dart
   // Ensure AuthInterceptor is properly configured
   final InterceptedClient client = InterceptedClient.build(
     interceptors: [AuthInterceptor()],
     requestTimeout: const Duration(seconds: 10),
   );
   ```

3. **Check Token Refresh**
   ```dart
   // Ensure token refresh is working
   final validToken = await authManager.getCurrentValidToken();
   if (validToken == null) {
     // Handle invalid token
     await authManager.clearTokens();
   }
   ```

#### Problem: Session validation failing

**Symptoms**:
- User logged out unexpectedly
- Session expired errors
- Authentication state inconsistent

**Solutions**:

1. **Check Session Validation**
   ```dart
   final status = await authManager.validateSessionOnStartup();
   switch (status) {
     case AuthStatus.loggedIn:
       // Session is valid
       break;
     case AuthStatus.tokenExpired:
       // Handle token expiration
       await authManager.clearTokens();
       break;
     case AuthStatus.sessionExpired:
       // Handle session expiration
       await authManager.clearTokens();
       break;
   }
   ```

2. **Implement Proper Error Handling**
   ```dart
   try {
     await authManager.validateSessionOnStartup();
   } catch (e) {
     logger.error("Session validation failed", error: e);
     // Handle validation error
     await authManager.clearTokens();
   }
   ```

### 4. API Communication Issues

#### Problem: Network requests failing

**Symptoms**:
- Connection timeout errors
- Network unreachable errors
- API endpoint not found

**Solutions**:

1. **Check API Configuration**
   ```dart
   // Verify API URL configuration
   final apiUrl = Config.apiUrl;
   print("API URL: $apiUrl");
   
   // Test API connectivity
   final apiModule = ConnectionsApiModule(apiUrl);
   final response = await apiModule.sendGetRequest("/health");
   ```

2. **Implement Retry Logic**
   ```dart
   Future<dynamic> sendRequestWithRetry(String route, {
     required String method,
     Map<String, dynamic>? data,
     int maxRetries = 3,
   }) async {
     for (int i = 0; i < maxRetries; i++) {
       try {
         return await sendRequest(route, method: method, data: data);
       } catch (e) {
         if (i == maxRetries - 1) rethrow;
         await Future.delayed(Duration(seconds: 1 << i)); // Exponential backoff
       }
     }
   }
   ```

3. **Add Network Error Handling**
   ```dart
   try {
     final response = await apiModule.sendGetRequest("/endpoint");
     return response;
   } catch (e) {
     if (e.toString().contains("SocketException")) {
       // Handle network connectivity issues
       return {"error": "Network unavailable"};
     }
     rethrow;
   }
   ```

#### Problem: API response parsing errors

**Symptoms**:
- JSON parsing errors
- Unexpected response format
- Null pointer exceptions

**Solutions**:

1. **Add Response Validation**
   ```dart
   dynamic _processResponse(http.Response response) {
     try {
       if (response.body.isNotEmpty) {
         final decoded = jsonDecode(response.body);
         return decoded;
       }
       return null;
     } catch (e) {
       logger.error("Failed to parse response", error: e);
       return {"error": "Invalid response format"};
     }
   }
   ```

2. **Implement Type-Safe Response Handling**
   ```dart
   class ApiResponse<T> {
     final bool success;
     final T? data;
     final String? error;
     
     ApiResponse({required this.success, this.data, this.error});
     
     factory ApiResponse.fromJson(Map<String, dynamic> json) {
       return ApiResponse(
         success: json['success'] ?? false,
         data: json['data'],
         error: json['error'],
       );
     }
   }
   ```

### 5. Navigation Issues

#### Problem: Routes not working or navigation failing

**Symptoms**:
- Navigation not responding
- Deep links not working
- Route not found errors

**Solutions**:

1. **Check Route Configuration**
   ```dart
   final router = GoRouter(
     initialLocation: '/',
     routes: [
       GoRoute(
         path: '/',
         builder: (context, state) => const HomeScreen(),
       ),
       GoRoute(
         path: '/login',
         builder: (context, state) => const LoginScreen(),
       ),
     ],
   );
   ```

2. **Verify Navigation Setup**
   ```dart
   MaterialApp.router(
     routerConfig: navigationManager.router,
     // ... other configuration
   )
   ```

3. **Test Deep Links**
   ```dart
   // Test deep link handling
   final uri = Uri.parse("yourapp://profile");
   final router = GoRouter.of(context);
   router.go(uri.path);
   ```

### 6. Performance Issues

#### Problem: App running slowly or freezing

**Symptoms**:
- UI lag
- Memory usage increasing
- App crashes

**Solutions**:

1. **Check Memory Usage**
   ```dart
   // Monitor memory usage
   import 'dart:developer';
   
   void logMemoryUsage() {
     final memoryInfo = ProcessInfo.currentRss;
     print("Memory usage: ${memoryInfo ~/ 1024 ~/ 1024} MB");
   }
   ```

2. **Optimize State Updates**
   ```dart
   // Use Future.microtask to avoid build-time notifications
   void updateState() {
     Future.microtask(() => notifyListeners());
   }
   ```

3. **Implement Proper Disposal**
   ```dart
   @override
   void dispose() {
     // Clean up resources
     _timer?.cancel();
     _streamSubscription?.cancel();
     super.dispose();
   }
   ```

### 7. Build and Deployment Issues

#### Problem: Build failures

**Symptoms**:
- Compilation errors
- Missing dependencies
- Platform-specific build issues

**Solutions**:

1. **Clean and Rebuild**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. **Check Dependencies**
   ```bash
   flutter pub deps
   flutter doctor
   ```

3. **Platform-Specific Issues**
   ```bash
   # Android
   flutter doctor --android-licenses
   
   # iOS
   cd ios && pod install && cd ..
   ```

#### Problem: App signing issues

**Symptoms**:
- APK signing errors
- App Store rejection
- Certificate issues

**Solutions**:

1. **Check Keystore Configuration**
   ```properties
   # android/key.properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=<path to keystore>
   ```

2. **Verify Signing Setup**
   ```gradle
   // android/app/build.gradle
   android {
     signingConfigs {
       release {
         keyAlias keystoreProperties['keyAlias']
         keyPassword keystoreProperties['keyPassword']
         storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
         storePassword keystoreProperties['storePassword']
       }
     }
   }
   ```

## Debugging Techniques

### 1. Logging and Debugging

#### Enable Debug Logging
```dart
// Enable detailed logging
class Logger {
  void debug(String message) {
    if (Config.loggerOn) {
      print("DEBUG: $message");
    }
  }
}
```

#### Add Debug Information
```dart
// Add debug information to state updates
void updateModuleState(String moduleKey, Map<String, dynamic> newState) {
  _log.info("📊 Updating state for module: $moduleKey");
  _log.info("📊 New state: $newState");
  _log.info("📊 Current app state:");
  _logAppState();
  // ... update logic
}
```

### 2. State Inspection

#### Monitor State Changes
```dart
// Add state change listener
class StateManager with ChangeNotifier {
  void addStateChangeListener() {
    addListener(() {
      _log.info("📊 State changed");
      _logAppState();
    });
  }
}
```

#### Debug State Structure
```dart
// Log complete state structure
void _logAppState() {
  final allStates = getAllStates();
  _log.info("📊 Complete App State:");
  _log.info("🔧 Module States: ${allStates['module_states']}");
  _log.info("📱 Main App State: ${allStates['main_app_state']}");
}
```

### 3. Network Debugging

#### Monitor API Requests
```dart
// Add request logging
Future<dynamic> sendRequest(String route, {required String method, Map<String, dynamic>? data}) async {
  _log.info("📡 $method Request: $route");
  if (data != null) {
    _log.info("📡 Request Data: $data");
  }
  
  try {
    final response = await _performRequest(route, method, data);
    _log.info("📡 Response Status: ${response.statusCode}");
    return _processResponse(response);
  } catch (e) {
    _log.error("📡 Request failed: $e");
    rethrow;
  }
}
```

#### Test API Connectivity
```dart
// Test API connectivity
Future<bool> testApiConnection() async {
  try {
    final response = await sendGetRequest("/health");
    return response != null;
  } catch (e) {
    return false;
  }
}
```

### 4. Module Health Monitoring

#### Implement Health Checks
```dart
// Add comprehensive health checks
@override
Map<String, dynamic> healthCheck() {
  return {
    'module': moduleKey,
    'status': isInitialized ? 'healthy' : 'not_initialized',
    'dependencies': dependencies,
    'last_activity': DateTime.now().toIso8601String(),
    'memory_usage': _getMemoryUsage(),
    'error_count': _errorCount,
  };
}
```

#### Monitor Module Performance
```dart
// Track module performance
class ModulePerformance {
  final DateTime startTime;
  final Map<String, int> methodCallCount = {};
  final Map<String, Duration> methodDurations = {};
  
  void recordMethodCall(String methodName, Duration duration) {
    methodCallCount[methodName] = (methodCallCount[methodName] ?? 0) + 1;
    methodDurations[methodName] = duration;
  }
}
```

## Error Prevention

### 1. Input Validation

#### Validate API Responses
```dart
// Validate API response structure
bool isValidApiResponse(dynamic response) {
  if (response is! Map) return false;
  if (!response.containsKey('success')) return false;
  return true;
}
```

#### Validate State Updates
```dart
// Validate state before updating
void updateModuleState(String moduleKey, Map<String, dynamic> newState) {
  if (moduleKey.isEmpty) {
    throw ArgumentError("Module key cannot be empty");
  }
  
  if (newState == null) {
    throw ArgumentError("New state cannot be null");
  }
  
  // ... update logic
}
```

### 2. Error Boundaries

#### Implement Error Boundaries
```dart
class ErrorBoundary extends StatelessWidget {
  final Widget child;
  final Widget Function(Object error)? errorBuilder;
  
  const ErrorBoundary({
    required this.child,
    this.errorBuilder,
  });
  
  @override
  Widget build(BuildContext context) {
    return ErrorWidget.builder = (FlutterErrorDetails details) {
      return errorBuilder?.call(details.exception) ?? 
             Container(
               padding: EdgeInsets.all(16),
               child: Text("An error occurred"),
             );
    };
  }
}
```

### 3. Graceful Degradation

#### Handle Missing Dependencies
```dart
// Handle missing dependencies gracefully
void initialize(BuildContext context, ModuleManager moduleManager) {
  final requiredModule = moduleManager.getModuleByType<RequiredModule>();
  if (requiredModule == null) {
    _log.warning("Required module not found, using fallback");
    _useFallbackImplementation();
  } else {
    _useRequiredModule(requiredModule);
  }
}
```

## Performance Monitoring

### 1. Memory Monitoring

#### Track Memory Usage
```dart
// Monitor memory usage
class MemoryMonitor {
  static void logMemoryUsage() {
    final memoryInfo = ProcessInfo.currentRss;
    final memoryMB = memoryInfo ~/ 1024 ~/ 1024;
    
    if (memoryMB > 100) {
      Logger().warning("High memory usage: ${memoryMB}MB");
    }
  }
}
```

### 2. Performance Metrics

#### Track Method Performance
```dart
// Track method execution time
class PerformanceTracker {
  static Map<String, List<Duration>> _methodTimes = {};
  
  static void trackMethod(String methodName, Function method) {
    final stopwatch = Stopwatch()..start();
    method();
    stopwatch.stop();
    
    _methodTimes.putIfAbsent(methodName, () => []).add(stopwatch.elapsed);
  }
}
```

## Conclusion

This troubleshooting guide provides comprehensive solutions for common issues in Flutter Base 05 applications. By following these debugging techniques and error prevention strategies, developers can maintain stable and performant applications.

For additional support:
1. Check the Flutter documentation
2. Review platform-specific guides
3. Use the built-in logging system
4. Monitor application health metrics
5. Implement comprehensive error handling

Remember to always test thoroughly and monitor application performance in production environments. 