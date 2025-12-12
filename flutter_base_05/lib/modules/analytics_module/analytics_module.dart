import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../core/managers/auth_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../tools/logging/logger.dart';
import 'package:uuid/uuid.dart';

class AnalyticsModule extends ModuleBase {
  static const bool LOGGING_SWITCH = false;
  
  late ServicesManager _servicesManager;
  late ModuleManager _localModuleManager;
  SharedPrefManager? _sharedPref;
  ConnectionsApiModule? _connectionModule;
  AuthManager? _authManager;
  
  // Session management
  String? _currentSessionId;
  DateTime? _sessionStartTime;
  static const int _sessionTimeoutMinutes = 30;
  
  // Event queue for offline support
  final List<Map<String, dynamic>> _eventQueue = [];
  static const int _maxQueueSize = 100;
  Timer? _flushTimer;
  
  /// Constructor with module key and dependencies
  AnalyticsModule() : super("analytics_module", dependencies: ["connections_api_module"]);
  
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _localModuleManager = moduleManager;
    _initDependencies(context);
    _loadEventQueue(); // Load any previously queued events
    _initializeSession();
    _startFlushTimer();
  }
  
  /// Initialize dependencies
  void _initDependencies(BuildContext context) {
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    _connectionModule = _localModuleManager.getModuleByType<ConnectionsApiModule>();
    _authManager = AuthManager();
  }
  
  /// Initialize or refresh session
  void _initializeSession() {
    try {
      // Check if we have an existing session
      final storedSessionId = _sharedPref?.getString('analytics_session_id');
      final storedSessionTime = _sharedPref?.getString('analytics_session_time');
      
      if (storedSessionId != null && storedSessionTime != null) {
        final sessionTime = DateTime.parse(storedSessionTime);
        final now = DateTime.now();
        final difference = now.difference(sessionTime);
        
        // Check if session is still valid (within timeout)
        if (difference.inMinutes < _sessionTimeoutMinutes) {
          _currentSessionId = storedSessionId;
          _sessionStartTime = sessionTime;
          Logger().info("AnalyticsModule: Reusing existing session: $_currentSessionId", isOn: LOGGING_SWITCH);
          return;
        }
      }
      
      // Generate new session
      _generateNewSession();
    } catch (e) {
      Logger().error("AnalyticsModule: Error initializing session: $e", isOn: LOGGING_SWITCH);
      _generateNewSession();
    }
  }
  
  /// Generate a new session ID
  void _generateNewSession() {
    final uuid = const Uuid();
    _currentSessionId = uuid.v4();
    _sessionStartTime = DateTime.now();
    
    // Store session in SharedPreferences
    _sharedPref?.setString('analytics_session_id', _currentSessionId!);
    _sharedPref?.setString('analytics_session_time', _sessionStartTime!.toIso8601String());
    
    Logger().info("AnalyticsModule: Generated new session: $_currentSessionId", isOn: LOGGING_SWITCH);
  }
  
  /// Refresh session if needed
  void _refreshSessionIfNeeded() {
    if (_sessionStartTime == null) {
      _generateNewSession();
      return;
    }
    
    final now = DateTime.now();
    final difference = now.difference(_sessionStartTime!);
    
    if (difference.inMinutes >= _sessionTimeoutMinutes) {
      _generateNewSession();
    }
  }
  
  /// Start timer to periodically flush queued events
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _flushEventQueue();
    });
  }
  
  /// Get current user ID
  Future<String?> _getCurrentUserId() async {
    try {
      if (_authManager == null) return null;
      
      final authState = _authManager!.getAuthState();
      final userId = authState['userId'] as String?;
      
      if (userId != null && userId.isNotEmpty) {
        return userId;
      }
      
      // Fallback to SharedPreferences
      return _sharedPref?.getString('user_id');
    } catch (e) {
      Logger().error("AnalyticsModule: Error getting user ID: $e", isOn: LOGGING_SWITCH);
      return null;
    }
  }
  
  /// Get platform identifier
  String _getPlatform() {
    if (kIsWeb) {
      return 'web';
    } else if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'unknown';
    }
  }
  
  /// Track a generic event
  Future<void> trackEvent({
    required String eventType,
    Map<String, dynamic>? eventData,
  }) async {
    try {
      _refreshSessionIfNeeded();
      
      final userId = await _getCurrentUserId();
      
      // If no user ID, queue event for later
      if (userId == null) {
        _queueEvent(eventType, eventData ?? {});
        Logger().info("AnalyticsModule: Queued event (no user): $eventType", isOn: LOGGING_SWITCH);
        return;
      }
      
      // Try to send immediately
      final success = await _sendEventToBackend(
        userId: userId,
        eventType: eventType,
        eventData: eventData ?? {},
      );
      
      if (!success) {
        // Queue for retry if send failed
        _queueEvent(eventType, eventData ?? {}, userId: userId);
        Logger().info("AnalyticsModule: Queued event (send failed): $eventType", isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      Logger().error("AnalyticsModule: Error tracking event: $e", isOn: LOGGING_SWITCH);
      // Queue event even on error
      _queueEvent(eventType, eventData ?? {});
    }
  }
  
  /// Track screen view
  Future<void> trackScreenView(String screenName) async {
    await trackEvent(
      eventType: 'screen_viewed',
      eventData: {'screen_name': screenName},
    );
  }
  
  /// Track button click
  Future<void> trackButtonClick(String buttonName, {String? screenName}) async {
    await trackEvent(
      eventType: 'button_clicked',
      eventData: {
        'button_name': buttonName,
        if (screenName != null) 'screen_name': screenName,
      },
    );
  }
  
  /// Track error
  Future<void> trackError({
    required String error,
    String? stackTrace,
    String? context,
    Map<String, dynamic>? additionalData,
  }) async {
    await trackEvent(
      eventType: 'error_occurred',
      eventData: {
        'error': error,
        if (stackTrace != null) 'stack_trace': stackTrace,
        if (context != null) 'context': context,
        if (additionalData != null) ...additionalData,
      },
    );
  }
  
  /// Queue event for later sending
  void _queueEvent(String eventType, Map<String, dynamic> eventData, {String? userId}) {
    if (_eventQueue.length >= _maxQueueSize) {
      // Remove oldest event if queue is full
      _eventQueue.removeAt(0);
    }
    
    _eventQueue.add({
      'event_type': eventType,
      'event_data': eventData,
      'user_id': userId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Store queue in SharedPreferences for persistence
    _saveEventQueue();
  }
  
  /// Save event queue to SharedPreferences
  void _saveEventQueue() {
    try {
      final queueJson = jsonEncode(_eventQueue);
      _sharedPref?.setString('analytics_event_queue', queueJson);
    } catch (e) {
      Logger().error("AnalyticsModule: Error saving event queue: $e", isOn: LOGGING_SWITCH);
    }
  }
  
  /// Load event queue from SharedPreferences
  void _loadEventQueue() {
    try {
      final queueJson = _sharedPref?.getString('analytics_event_queue');
      if (queueJson != null && queueJson.isNotEmpty) {
        final decoded = jsonDecode(queueJson) as List;
        _eventQueue.clear();
        _eventQueue.addAll(decoded.map((e) => e as Map<String, dynamic>));
        Logger().info("AnalyticsModule: Loaded ${_eventQueue.length} queued events", isOn: LOGGING_SWITCH);
      }
    } catch (e) {
      Logger().error("AnalyticsModule: Error loading event queue: $e", isOn: LOGGING_SWITCH);
    }
  }
  
  /// Flush queued events to backend
  Future<void> _flushEventQueue() async {
    if (_eventQueue.isEmpty) return;
    
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) {
        // Still no user, keep events queued
        return;
      }
      
      // Process events in batches
      final eventsToSend = List<Map<String, dynamic>>.from(_eventQueue);
      _eventQueue.clear();
      
      int successCount = 0;
      for (final event in eventsToSend) {
        final eventUserId = event['user_id'] as String? ?? userId;
        final success = await _sendEventToBackend(
          userId: eventUserId,
          eventType: event['event_type'] as String,
          eventData: event['event_data'] as Map<String, dynamic>? ?? {},
        );
        
        if (success) {
          successCount++;
        } else {
          // Re-queue failed events
          _eventQueue.add(event);
        }
      }
      
      if (successCount > 0) {
        Logger().info("AnalyticsModule: Flushed $successCount/${eventsToSend.length} queued events", isOn: LOGGING_SWITCH);
        _saveEventQueue();
      }
    } catch (e) {
      Logger().error("AnalyticsModule: Error flushing event queue: $e", isOn: LOGGING_SWITCH);
    }
  }
  
  /// Send event to backend
  Future<bool> _sendEventToBackend({
    required String userId,
    required String eventType,
    required Map<String, dynamic> eventData,
  }) async {
    try {
      if (_connectionModule == null) {
        Logger().warning("AnalyticsModule: ConnectionsApiModule not available", isOn: LOGGING_SWITCH);
        return false;
      }
      
      final requestPayload = {
        'event_type': eventType,
        'event_data': eventData,
        'session_id': _currentSessionId,
        'platform': _getPlatform(),
      };
      
      final response = await _connectionModule!.sendPostRequest(
        '/userauth/analytics/track',
        requestPayload,
      );
      
      if (response is Map<String, dynamic>) {
        final success = response['success'] as bool? ?? false;
        if (success) {
          Logger().info("AnalyticsModule: Event tracked successfully: $eventType", isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().warning("AnalyticsModule: Event tracking failed: ${response['error']}", isOn: LOGGING_SWITCH);
          return false;
        }
      }
      
      return false;
    } catch (e) {
      Logger().error("AnalyticsModule: Error sending event to backend: $e", isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  @override
  void dispose() {
    _flushTimer?.cancel();
    // Flush remaining events before disposing
    _flushEventQueue();
    super.dispose();
  }
  
  @override
  Map<String, dynamic> healthCheck() {
    return {
      'module': 'analytics_module',
      'status': isInitialized ? 'healthy' : 'not_initialized',
      'session_id': _currentSessionId,
      'queued_events': _eventQueue.length,
      'connection_module_available': _connectionModule != null,
      'details': 'Analytics tracking module',
    };
  }
}
