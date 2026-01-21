import 'package:flutter/material.dart';
import '../../../core/managers/module_manager.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/navigation_manager.dart';
import '../../connections_api_module/connections_api_module.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import '../../../core/services/shared_preferences.dart';
import '../../login_module/login_module.dart';
import '../managers/validated_event_emitter.dart';
import '../../dutch_game/managers/dutch_game_state_updater.dart';
import '../backend_core/services/game_state_store.dart';
import '../practice/practice_mode_bridge.dart';
import '../managers/game_coordinator.dart';

/// Convenient helper methods for dutch game operations
/// Provides type-safe, validated methods for common game actions
class DutchGameHelpers {
  // Singleton instances
  static final _eventEmitter = DutchGameEventEmitter.instance;
  static final _stateUpdater = DutchGameStateUpdater.instance;
  static final _logger = Logger();
  
  static const bool LOGGING_SWITCH = false; // Enabled for mode switching debugging
  
  // ========================================
  // EVENT EMISSION HELPERS
  // ========================================
  
  /// Create a new room with validation
  static Future<Map<String, dynamic>> createRoom({
    required String permission,
    required int maxPlayers,
    required int minPlayers,
    String gameType = 'classic',
    int turnTimeLimit = 30,
    bool autoStart = false,
    String? password,
  }) async {
    try {
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await clearAllGameStateBeforeNewGame();
      
      // Ensure WebSocket is ready (logged in, initialized, and connected)
      final isReady = await ensureWebSocketReady();
      if (!isReady) {
        return {
          'success': false,
          'error': 'WebSocket not ready - cannot create room. Please ensure you are logged in.',
        };
      }
      
    final data = {
      'permission': permission,
      'max_players': maxPlayers,
      'min_players': minPlayers,
      'game_type': gameType,
      'turn_time_limit': turnTimeLimit,
      'auto_start': autoStart,
    };
    
    // Add password for private rooms
    if (permission == 'private' && password != null) {
      data['password'] = password;
    }
    
      return await _eventEmitter.emit(
      eventType: 'create_room',
      data: data,
    );
    } catch (e) {
      _logger.error('DutchGameHelpers: Error creating room: $e', isOn: LOGGING_SWITCH);
      return {
        'success': false,
        'error': 'Failed to create room: $e',
      };
    }
  }

  /// Join an existing room with validation
  static Future<Map<String, dynamic>> joinRoom({
    required String roomId,
  }) async {
    try {
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await clearAllGameStateBeforeNewGame();
      
      // Ensure WebSocket is ready (logged in, initialized, and connected)
      final isReady = await ensureWebSocketReady();
      if (!isReady) {
        return {
          'success': false,
          'error': 'WebSocket not ready - cannot join room. Please ensure you are logged in.',
        };
      }
      
    final data = {
      'room_id': roomId,
    };
    
      return await _eventEmitter.emit(
      eventType: 'join_room',
      data: data,
    );
    } catch (e) {
      _logger.error('DutchGameHelpers: Error joining room: $e', isOn: LOGGING_SWITCH);
      return {
        'success': false,
        'error': 'Failed to join room: $e',
      };
    }
  }

  /// Fetch available games from the Dart backend via WebSocket
  /// Uses list_rooms WebSocket event to get all available rooms
  static Future<Map<String, dynamic>> fetchAvailableGames() async {
    try {
      // Ensure WebSocket is connected
      final wsManager = WebSocketManager.instance;
      if (!wsManager.isConnected) {
        final connected = await wsManager.connect();
        if (!connected) {
          // Don't navigate here - let the calling screen handle navigation
          // This prevents navigation when called from background or during app init
          throw Exception('WebSocket not connected - cannot fetch games');
        }
      }
      
      // Emit list_rooms event via validated event emitter
      // The response will come back as 'rooms_list' event
      await _eventEmitter.emit(
        eventType: 'list_rooms',
        data: {},
      );
      
      // The emit returns immediately, but the actual response comes via WebSocket event
      // The 'rooms_list' event handler will update the state automatically
      // Return success - the actual games will be updated via event handler
      return {
        'success': true,
        'message': 'Fetching games...',
        'games': [],
        'count': 0,
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fetch available games: $e',
        'games': [],
        'count': 0,
      };
    }
  }
  


  // ========================================
  // STATE UPDATE HELPERS
  // ========================================
  
  /// Navigate to account screen when WebSocket authentication fails
  static void navigateToAccountScreen(String reason, String message) {
    _logger.info('DutchGameHelpers: navigateToAccountScreen called - reason: $reason, message: $message', isOn: LOGGING_SWITCH);
    try {
      final navigationManager = NavigationManager();
      _logger.info('DutchGameHelpers: NavigationManager obtained, navigating to /account', isOn: LOGGING_SWITCH);
      navigationManager.navigateToWithDelay('/account', parameters: {
        'auth_reason': reason,
        'auth_message': message,
      });
      _logger.info('DutchGameHelpers: Navigation to /account initiated', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('DutchGameHelpers: Error navigating to account screen: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
    }
  }
  
  /// Ensure WebSocket is ready (user logged in, initialized, and connected)
  /// 
  /// If user is not logged in and no user data exists in SharedPreferences,
  /// automatically creates a guest user and retries.
  /// 
  /// [context] - Optional BuildContext. If not provided, will attempt to get from NavigationManager.
  /// Returns true if ready, false otherwise
  static Future<bool> ensureWebSocketReady({BuildContext? context}) async {
    _logger.info('DutchGameHelpers: ensureWebSocketReady called', isOn: LOGGING_SWITCH);
    
    // Check if user is logged in
    final stateManager = StateManager();
    final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
    final isLoggedIn = loginState['isLoggedIn'] == true;
    _logger.info('DutchGameHelpers: User login status - isLoggedIn: $isLoggedIn', isOn: LOGGING_SWITCH);
    
    if (!isLoggedIn) {
      _logger.info('DutchGameHelpers: User is not logged in, checking for existing user data', isOn: LOGGING_SWITCH);
      
      // Check SharedPreferences for username and email
      try {
        final sharedPref = SharedPrefManager();
        await sharedPref.initialize();
        final username = sharedPref.getString('username');
        final email = sharedPref.getString('email');
        
        _logger.info('DutchGameHelpers: SharedPreferences check - username: ${username != null && username.isNotEmpty ? "exists" : "null"}, email: ${email != null && email.isNotEmpty ? "exists" : "null"}', isOn: LOGGING_SWITCH);
        
        // If either username or email exists, user data exists - navigate to account screen
        if ((username != null && username.isNotEmpty) || (email != null && email.isNotEmpty)) {
          _logger.info('DutchGameHelpers: User data found in SharedPreferences, navigating to account screen', isOn: LOGGING_SWITCH);
          navigateToAccountScreen('ws_auth_required', 'Please log in to connect to game server.');
          return false;
        }
        
        // No user data found - attempt auto-guest creation
        _logger.info('DutchGameHelpers: No user data found, attempting auto-guest creation', isOn: LOGGING_SWITCH);
        
        // Get context from NavigationManager if not provided
        final navigationManager = NavigationManager();
        final effectiveContext = context ?? navigationManager.navigatorKey.currentContext;
        
        if (effectiveContext == null) {
          _logger.warning('DutchGameHelpers: Cannot auto-create guest - no context available', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Get LoginModule
        final moduleManager = ModuleManager();
        final loginModule = moduleManager.getModuleByType<LoginModule>();
        
        if (loginModule == null) {
          _logger.warning('DutchGameHelpers: Cannot auto-create guest - LoginModule not available', isOn: LOGGING_SWITCH);
          return false;
        }
        
        // Attempt guest registration
        _logger.info('DutchGameHelpers: Calling LoginModule.registerGuestUser', isOn: LOGGING_SWITCH);
        final result = await loginModule.registerGuestUser(context: effectiveContext);
        
        if (result['success'] != null) {
          _logger.info('DutchGameHelpers: Guest user created successfully, waiting for login completion', isOn: LOGGING_SWITCH);
          
          // Wait for login process to fully complete
          final loginCompleted = await _waitForLoginCompletion();
          if (!loginCompleted) {
            _logger.warning('DutchGameHelpers: Login completion timeout', isOn: LOGGING_SWITCH);
            return false;
          }
          
          _logger.info('DutchGameHelpers: Login completed, retrying ensureWebSocketReady', isOn: LOGGING_SWITCH);
          // Recursively retry - now user should be fully logged in
          // Pass context to avoid re-fetching it
          return await ensureWebSocketReady(context: effectiveContext);
        } else {
          _logger.warning('DutchGameHelpers: Guest creation failed: ${result['error']}', isOn: LOGGING_SWITCH);
          return false;
        }
      } catch (e, stackTrace) {
        _logger.error('DutchGameHelpers: Error during auto-guest creation check: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
        return false;
      }
    }
    
    // Get WebSocket manager
    final wsManager = WebSocketManager.instance;
    
    // Initialize if not already initialized
    if (!wsManager.isInitialized) {
      _logger.info('DutchGameHelpers: WebSocket not initialized, initializing...', isOn: LOGGING_SWITCH);
      final initialized = await wsManager.initialize();
      _logger.info('DutchGameHelpers: WebSocket initialization result: $initialized', isOn: LOGGING_SWITCH);
      if (!initialized) {
        _logger.warning('DutchGameHelpers: WebSocket initialization failed', isOn: LOGGING_SWITCH);
        return false;
      }
    } else {
      _logger.info('DutchGameHelpers: WebSocket already initialized', isOn: LOGGING_SWITCH);
    }
    
    // Connect if not already connected
    if (!wsManager.isConnected) {
      _logger.info('DutchGameHelpers: WebSocket not connected, connecting...', isOn: LOGGING_SWITCH);
      final connected = await wsManager.connect();
      _logger.info('DutchGameHelpers: WebSocket connection result: $connected', isOn: LOGGING_SWITCH);
      if (!connected) {
        _logger.warning('DutchGameHelpers: WebSocket connection failed', isOn: LOGGING_SWITCH);
        return false;
      }
    } else {
      _logger.info('DutchGameHelpers: WebSocket already connected', isOn: LOGGING_SWITCH);
    }
    
    // Wait for authentication to complete (with timeout)
    _logger.info('DutchGameHelpers: Waiting for authentication to complete...', isOn: LOGGING_SWITCH);
    final authCompleted = await _waitForAuthentication(timeoutSeconds: 5);
    if (!authCompleted) {
      _logger.warning('DutchGameHelpers: Authentication did not complete within timeout', isOn: LOGGING_SWITCH);
      return false;
    }
    _logger.info('DutchGameHelpers: Authentication completed', isOn: LOGGING_SWITCH);
    
    _logger.info('DutchGameHelpers: WebSocket is ready', isOn: LOGGING_SWITCH);
    return true;
  }
  
  /// Wait for WebSocket authentication to complete
  /// Returns true if authenticated, false if timeout
  static Future<bool> _waitForAuthentication({int timeoutSeconds = 5}) async {
    final stateManager = StateManager();
    final startTime = DateTime.now();
    const checkInterval = Duration(milliseconds: 100);
    
    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      final wsState = stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
      final isAuthenticated = wsState['is_authenticated'] == true;
      
      if (isAuthenticated) {
        _logger.info('DutchGameHelpers: Authentication confirmed', isOn: LOGGING_SWITCH);
        return true;
      }
      
      await Future.delayed(checkInterval);
    }
    
    _logger.warning('DutchGameHelpers: Authentication timeout after ${timeoutSeconds}s', isOn: LOGGING_SWITCH);
    return false;
  }
  
  /// Wait for login completion after guest creation
  /// Returns true if login is complete (isLoggedIn, userId, username, email all set), false if timeout
  static Future<bool> _waitForLoginCompletion({int timeoutSeconds = 10}) async {
    final stateManager = StateManager();
    final startTime = DateTime.now();
    const checkInterval = Duration(milliseconds: 100);
    
    _logger.info('DutchGameHelpers: Waiting for login completion...', isOn: LOGGING_SWITCH);
    
    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final isLoggedIn = loginState['isLoggedIn'] == true;
      final userId = loginState['userId']?.toString() ?? '';
      final username = loginState['username']?.toString() ?? '';
      final email = loginState['email']?.toString() ?? '';
      
      if (isLoggedIn && userId.isNotEmpty && username.isNotEmpty && email.isNotEmpty) {
        _logger.info('DutchGameHelpers: Login state complete - userId: $userId, username: $username, email: $email', isOn: LOGGING_SWITCH);
        // Wait a bit more to ensure auth_login_complete hook has been processed
        await Future.delayed(const Duration(milliseconds: 500));
        _logger.info('DutchGameHelpers: Login completion confirmed', isOn: LOGGING_SWITCH);
        return true;
      }
      
      await Future.delayed(checkInterval);
    }
    
    _logger.warning('DutchGameHelpers: Login completion timeout after ${timeoutSeconds}s', isOn: LOGGING_SWITCH);
    return false;
  }
  
  /// Update connection status
  static void updateConnectionStatus({
    required bool isConnected,
    bool? isLoading,
    String? lastError,
  }) {
    final updates = <String, dynamic>{
      'isConnected': isConnected,
    };
    
    if (isLoading != null) updates['isLoading'] = isLoading;
    if (lastError != null) updates['lastError'] = lastError;
    
    _stateUpdater.updateState(updates);
  }

  /// Update UI state using validated state updater
  static void updateUIState(Map<String, dynamic> updates) {
    _stateUpdater.updateState(updates);
  }

  /// Join a random available game or auto-create and start a new one
  /// Uses join_random_game WebSocket event
  static Future<Map<String, dynamic>> joinRandomGame({bool isClearAndCollect = true}) async {
    try {
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await clearAllGameStateBeforeNewGame();
      
      // Ensure WebSocket is ready (logged in, initialized, and connected)
      final isReady = await ensureWebSocketReady();
      if (!isReady) {
        throw Exception('WebSocket not ready - cannot join random game. Please ensure you are logged in.');
      }
      
      // Set flag to indicate we're in a random join flow (for navigation)
      // Store isClearAndCollect in state so it can be read when start_match is called
      // IMPORTANT: Use updateStateSync to ensure synchronous update before emitting event
      // Using updateUIState goes through StateQueueValidator which is async and can cause race conditions
      _stateUpdater.updateStateSync({
        'isRandomJoinInProgress': true,
        'randomJoinIsClearAndCollect': isClearAndCollect, // Store for use in start_match
      });
      _logger.info('🎯 Set isRandomJoinInProgress=true and randomJoinIsClearAndCollect=$isClearAndCollect using updateStateSync', isOn: LOGGING_SWITCH);
      
      // Emit join_random_game event via validated event emitter with isClearAndCollect flag
      await _eventEmitter.emit(
        eventType: 'join_random_game',
        data: {
          'isClearAndCollect': isClearAndCollect,
        },
      );
      
      // The emit returns immediately, but the actual response comes via WebSocket events
      // Return success - the actual join/creation will be handled via event handlers
      return {
        'success': true,
        'message': 'Searching for available game...',
      };
      
    } catch (e) {
      // Clear flag on error
      updateUIState({
        'isRandomJoinInProgress': false,
      });
      return {
        'success': false,
        'error': 'Failed to join random game: $e',
      };
    }
  }

  /// Find a specific game by room ID via API call
  static Future<Map<String, dynamic>> findRoom(String roomId) async {
    // Note: findRoom uses HTTP API, not WebSocket, so we only need to check login status
    // The API call will handle authentication via JWT token in headers
    try {
      // Get the ConnectionsApiModule instance from the global module manager
      final moduleManager = ModuleManager();
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      
      if (connectionsModule == null) {
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      // Make API call to find game
      final response = await connectionsModule.sendPostRequest(
        '/userauth/dutch/find-room',
        {'room_id': roomId},
      );
      
      // Check if response contains error
      if (response is Map && response.containsKey('error')) {
        throw Exception(response['message'] ?? response['error'] ?? 'Failed to find game');
      }
      
      // Extract game info from response
      final game = response['game'];
      final message = response['message'] ?? 'Game found successfully';
      
      return {
        'success': true,
        'message': message,
        'game': game,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Failed to find game',
        'game': null,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Fetch user dutch game statistics from the database
  /// Uses the dedicated /userauth/dutch/get-user-stats endpoint
  /// Returns the dutch_game module data including wins, losses, points, coins, level, rank, etc.
  /// 
  /// Returns:
  /// - Map with 'success': true and 'data' containing dutch_game module data on success
  /// - Map with 'success': false and 'error' message on failure
  /// - null if dutch_game module doesn't exist for the user
  static Future<Map<String, dynamic>?> getUserDutchGameData() async {
    try {
      _logger.info('📊 DutchGameHelpers: Fetching user dutch_game stats from API', isOn: LOGGING_SWITCH);
      
      // Get the ConnectionsApiModule instance from the global module manager
      final moduleManager = ModuleManager();
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      
      if (connectionsModule == null) {
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      // Make API call to get user dutch game stats (dedicated endpoint)
      final response = await connectionsModule.sendGetRequest('/userauth/dutch/get-user-stats');
      
      // Check if response contains error
      if (response is Map && response.containsKey('error')) {
        final errorMessage = response['message'] ?? response['error'] ?? 'Failed to fetch user stats';
        _logger.error('❌ DutchGameHelpers: API error: $errorMessage', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': errorMessage,
          'data': null,
        };
      }
      
      // Check if response indicates success
      if (response is! Map || response['success'] != true) {
        _logger.warning('⚠️ DutchGameHelpers: API response indicates failure', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': response['message'] ?? response['error'] ?? 'Failed to fetch user stats',
          'data': null,
        };
      }
      
      // Extract data from response
      final statsData = response['data'] as Map<String, dynamic>?;
      
      if (statsData == null) {
        _logger.warning('⚠️ DutchGameHelpers: Response missing data field', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': 'Response missing data field',
          'data': null,
        };
      }
      
      _logger.info('✅ DutchGameHelpers: Successfully fetched dutch_game stats: ${statsData.keys.toList()}', isOn: LOGGING_SWITCH);
      
      return {
        'success': true,
        'data': statsData,
        'timestamp': response['timestamp'] ?? DateTime.now().toIso8601String(),
      };
      
    } catch (e, stackTrace) {
      _logger.error('❌ DutchGameHelpers: Error fetching user dutch_game stats: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      return {
        'success': false,
        'error': e.toString(),
        'data': null,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Deduct game coins from multiple players when game starts
  /// 
  /// [coins] - Number of coins to deduct (default: 25)
  /// [gameId] - Game/room ID where coins are being deducted
  /// [playerIds] - List of user IDs (not session IDs) to deduct coins from
  /// 
  /// Returns:
  /// - Map with 'success': true and 'updated_players' list on success
  /// - Map with 'success': false and 'error' message on failure
  /// - null on exception
  static Future<Map<String, dynamic>?> deductGameCoins({
    required int coins,
    required String gameId,
    required List<String> playerIds,
  }) async {
    try {
      _logger.info('💰 DutchGameHelpers: Deducting $coins coins for game $gameId from ${playerIds.length} player(s)', isOn: LOGGING_SWITCH);
      
      // Get the ConnectionsApiModule instance from the global module manager
      final moduleManager = ModuleManager();
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      
      if (connectionsModule == null) {
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      // Prepare request body
      final requestBody = {
        'coins': coins,
        'game_id': gameId,
        'player_ids': playerIds,
      };
      
      // Make API call to deduct coins
      final response = await connectionsModule.sendPostRequest(
        '/userauth/dutch/deduct-game-coins',
        requestBody,
      );
      
      // Check if response contains error
      if (response is Map && response.containsKey('error')) {
        final errorMessage = response['message'] ?? response['error'] ?? 'Failed to deduct coins';
        _logger.error('❌ DutchGameHelpers: API error: $errorMessage', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': errorMessage,
          'updated_players': <Map<String, dynamic>>[],
        };
      }
      
      // Check if response indicates success
      if (response is! Map || response['success'] != true) {
        _logger.warning('⚠️ DutchGameHelpers: API response indicates failure', isOn: LOGGING_SWITCH);
        return {
          'success': false,
          'error': response['message'] ?? response['error'] ?? 'Failed to deduct coins',
          'updated_players': <Map<String, dynamic>>[],
        };
      }
      
      // Extract updated players from response
      final updatedPlayers = response['updated_players'] as List<dynamic>? ?? [];
      
      _logger.info('✅ DutchGameHelpers: Successfully deducted coins for ${updatedPlayers.length} player(s)', isOn: LOGGING_SWITCH);
      
      // Refresh user stats to show updated coin count
      await fetchAndUpdateUserDutchGameData();
      
      return {
        'success': true,
        'message': response['message'] ?? 'Coins deducted successfully',
        'game_id': response['game_id'] as String? ?? gameId,
        'coins_deducted': response['coins_deducted'] as int? ?? coins,
        'updated_players': updatedPlayers,
        'timestamp': response['timestamp'] ?? DateTime.now().toIso8601String(),
      };
      
    } catch (e, stackTrace) {
      _logger.error('❌ DutchGameHelpers: Error deducting game coins: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      return {
        'success': false,
        'error': e.toString(),
        'updated_players': <Map<String, dynamic>>[],
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Fetch user dutch_game data from API and update local state
  /// This is a convenience method that combines getUserDutchGameData() with state update
  /// 
  /// Returns:
  /// - true if data was successfully fetched and state was updated
  /// - false if there was an error or no data was found
  static Future<bool> fetchAndUpdateUserDutchGameData() async {
    try {
      _logger.info('📊 DutchGameHelpers: Fetching and updating user dutch_game data', isOn: LOGGING_SWITCH);
      
      // Fetch data from API
      final result = await getUserDutchGameData();
      
      if (result == null || result['success'] != true || result['data'] == null) {
        final error = result?['error'] ?? 'Unknown error';
        _logger.warning('⚠️ DutchGameHelpers: Failed to fetch dutch_game data: $error', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final dutchGameData = result['data'] as Map<String, dynamic>;
      
      // Update local state with fetched data
      // Store in a separate key to preserve game state while having user stats available
      _stateUpdater.updateState({
        'userStats': dutchGameData,
        // Removed userStatsLastUpdated - causes unnecessary state updates
      });
      
      _logger.info('✅ DutchGameHelpers: Successfully updated local state with dutch_game data', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e, stackTrace) {
      _logger.error('❌ DutchGameHelpers: Error fetching and updating user dutch_game data: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Get user dutch_game stats from local state
  /// Returns the userStats object if available, or null if not found
  static Map<String, dynamic>? getUserDutchGameStats() {
    try {
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      return dutchState['userStats'] as Map<String, dynamic>?;
    } catch (e) {
      _logger.error('❌ DutchGameHelpers: Error getting user stats from state: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }

  /// Check subscription tier from user stats
  /// 
  /// [fetchFromAPI] - If true, fetches fresh stats from API before checking (defaults to true)
  /// Returns the subscription tier string (defaults to 'promotional' if not found)
  static Future<String> getSubscriptionTier({bool fetchFromAPI = true}) async {
    try {
      String subscriptionTier = 'promotional';
      
      if (fetchFromAPI) {
        // Fetch fresh stats from API to ensure we have latest tier
        _logger.info('📊 DutchGameHelpers: Fetching fresh user stats from API for tier check', isOn: LOGGING_SWITCH);
        final statsResult = await getUserDutchGameData();
        
        if (statsResult != null && 
            statsResult['success'] == true && 
            statsResult['data'] != null) {
          final data = statsResult['data'] as Map<String, dynamic>?;
          if (data != null) {
            subscriptionTier = data['subscription_tier'] as String? ?? 'promotional';
          }
          _logger.info('📊 DutchGameHelpers: Fetched subscription_tier from API: $subscriptionTier', isOn: LOGGING_SWITCH);
        } else {
          _logger.warning('⚠️ DutchGameHelpers: Failed to fetch stats from API, falling back to state', isOn: LOGGING_SWITCH);
          // Fallback to state if API call fails
          final userStats = getUserDutchGameStats();
          subscriptionTier = userStats?['subscription_tier'] as String? ?? 'promotional';
        }
      } else {
        // Use cached state
        final userStats = getUserDutchGameStats();
        subscriptionTier = userStats?['subscription_tier'] as String? ?? 'promotional';
      }
      
      return subscriptionTier;
    } catch (e) {
      _logger.error('❌ DutchGameHelpers: Error checking subscription tier: $e', isOn: LOGGING_SWITCH);
      return 'promotional'; // Default to promotional on error
    }
  }

  /// Check if user has enough coins to join/create a game
  /// 
  /// [requiredCoins] - The number of coins required (defaults to 25)
  /// [fetchFromAPI] - If true, fetches fresh stats from API before checking (defaults to true)
  /// Returns true if user has enough coins or has promotional subscription tier, false otherwise
  /// Logs a warning if not enough coins
  /// 
  /// Logic:
  /// - If subscription_tier is 'promotional', skip coin check (promotional tier users play for free)
  /// - If subscription_tier is NOT 'promotional', check coins requirement (premium users need coins)
  static Future<bool> checkCoinsRequirement({int requiredCoins = 25, bool fetchFromAPI = true}) async {
    try {
      // First check subscription tier
      final subscriptionTier = await getSubscriptionTier(fetchFromAPI: fetchFromAPI);
      
      // If user has promotional tier, skip coin check (promotional tier is promotion period - play for free)
      if (subscriptionTier == 'promotional') {
        _logger.info('✅ DutchGameHelpers: User has promotional tier - skipping coin check (free play)', isOn: LOGGING_SWITCH);
        return true;
      }
      
      // For non-promotional tier users, check coins requirement
      _logger.info('📊 DutchGameHelpers: User has subscription tier "$subscriptionTier" - checking coins requirement', isOn: LOGGING_SWITCH);
      
      int currentCoins = 0;
      
      if (fetchFromAPI) {
        // Fetch fresh stats from API to ensure we have latest coin count
        _logger.info('📊 DutchGameHelpers: Fetching fresh user stats from API for coin check', isOn: LOGGING_SWITCH);
        final statsResult = await getUserDutchGameData();
        
        if (statsResult != null && 
            statsResult['success'] == true && 
            statsResult['data'] != null) {
          final data = statsResult['data'] as Map<String, dynamic>?;
          if (data != null) {
            currentCoins = data['coins'] as int? ?? 0;
          }
          _logger.info('📊 DutchGameHelpers: Fetched coins from API: $currentCoins', isOn: LOGGING_SWITCH);
        } else {
          _logger.warning('⚠️ DutchGameHelpers: Failed to fetch stats from API, falling back to state', isOn: LOGGING_SWITCH);
          // Fallback to state if API call fails
          final userStats = getUserDutchGameStats();
          currentCoins = userStats?['coins'] as int? ?? 0;
        }
      } else {
        // Use cached state
        final userStats = getUserDutchGameStats();
        if (userStats == null) {
          _logger.warning('⚠️ DutchGameHelpers: Cannot check coins - userStats not found', isOn: LOGGING_SWITCH);
          return false;
        }
        currentCoins = userStats['coins'] as int? ?? 0;
      }
      
      if (currentCoins < requiredCoins) {
        _logger.warning('⚠️ DutchGameHelpers: Insufficient coins - Required: $requiredCoins, Current: $currentCoins', isOn: LOGGING_SWITCH);
        return false;
      }
      
      _logger.info('✅ DutchGameHelpers: Coins check passed - Required: $requiredCoins, Current: $currentCoins', isOn: LOGGING_SWITCH);
      return true;
    } catch (e) {
      _logger.error('❌ DutchGameHelpers: Error checking coins requirement: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Remove player from specific game in games map and clear current game references
  /// This is called when a player leaves a game (after timer expires)
  /// Only clears game state, not websocket state (websocket module handles that)
  static void removePlayerFromGame({required String gameId}) {
    try {
      _logger.info('🧹 DutchGameHelpers: Removing player from game $gameId', isOn: LOGGING_SWITCH);
      
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
      
      // Remove the specific game from games map
      if (games.containsKey(gameId)) {
        games.remove(gameId);
        _logger.info('🧹 DutchGameHelpers: Removed game $gameId from games map', isOn: LOGGING_SWITCH);
      }
      
      // Clear currentGameId if it matches the game we're leaving
      final currentGameId = dutchState['currentGameId']?.toString() ?? '';
      final shouldClearCurrentGameId = currentGameId == gameId;
      
      // Update state to remove game and clear current game references
      // This will trigger widget updates through StateManager
      final updates = <String, dynamic>{
        'games': games,
      };
      
      if (shouldClearCurrentGameId) {
        updates['currentGameId'] = '';
        updates['currentRoomId'] = '';
        updates['isInRoom'] = false;
        updates['isRoomOwner'] = false;
        updates['isGameActive'] = false;
        updates['gamePhase'] = 'waiting';
        updates['gameStatus'] = 'inactive';
        
        // Clear widget-specific state slices
        updates['discardPile'] = <Map<String, dynamic>>[];
        updates['drawPileCount'] = 0;
        updates['discardPileCount'] = 0;
        updates['turn_events'] = <Map<String, dynamic>>[];
        
        // Clear round information
        updates['roundNumber'] = 0;
        updates['currentPlayer'] = null;
        updates['currentPlayerStatus'] = '';
        updates['roundStatus'] = '';
        
        _logger.info('🧹 DutchGameHelpers: Cleared current game references', isOn: LOGGING_SWITCH);
      }
      
      // Update state (this triggers widget rebuilds)
      _stateUpdater.updateState(updates);
      
      _logger.info('✅ DutchGameHelpers: Player removed from game $gameId, widgets will update', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ DutchGameHelpers: Error removing player from game: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clear all game state when leaving game play screen
  /// This should be called when navigating away from the game play screen
  /// to prevent stale data from affecting new games
  static void clearGameState({String? gameId}) {
    try {
      _logger.info('🧹 DutchGameHelpers: Clearing game state${gameId != null ? " for game $gameId" : ""}', isOn: LOGGING_SWITCH);
      
      // Clear all game-related state
      _stateUpdater.updateState({
        // Clear game identifiers
        'currentGameId': '',
        'currentRoomId': '',
        
        // Clear games map
        'games': <String, dynamic>{},
        
        // Clear game phase and status
        'gamePhase': 'waiting',
        'gameStatus': 'inactive',
        'isGameActive': false,
        'isInRoom': false,
        'isRoomOwner': false,
        
        // Clear round information
        'roundNumber': 0,
        'currentPlayer': null,
        'currentPlayerStatus': '',
        'roundStatus': '',
        
        // Clear widget-specific state slices
        'discardPile': <Map<String, dynamic>>[],
        'drawPileCount': 0,
        'discardPileCount': 0,
        
        // Clear turn events and animation data
        'turn_events': <Map<String, dynamic>>[],
        
        // Clear messages state (including modal state)
        'messages': {
          'session': <Map<String, dynamic>>[],
          'rooms': <String, List<Map<String, dynamic>>>{},
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': false,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
        
        // Clear instructions state
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
          'key': '',
          'dontShowAgain': <String, bool>{},
        },
        
        // Clear joined games list
        'joinedGames': <Map<String, dynamic>>[],
        'totalJoinedGames': 0,
        // Removed joinedGamesTimestamp - causes unnecessary state updates
      });
      
      _logger.info('✅ DutchGameHelpers: Game state cleared successfully', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ DutchGameHelpers: Error clearing game state: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clear all existing games, game maps, and game logic state before starting a new game
  /// This prevents overlapping or old game state from interfering with new games
  /// Should be called BEFORE: random join, create/join room, or practice match start
  /// 
  /// This method:
  /// - Triggers leave_room events for WebSocket rooms (multiplayer)
  /// - Ends practice sessions for practice rooms
  /// - Clears all game state from StateManager
  /// - Clears GameStateStore entries
  static Future<void> clearAllGameStateBeforeNewGame() async {
    try {
      _logger.info('🧹 DutchGameHelpers: Clearing ALL game state before starting new game', isOn: LOGGING_SWITCH);
      
      // 1. Get current state to find all games
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = dutchState['games'] as Map<String, dynamic>? ?? {};
      final currentGameId = dutchState['currentGameId']?.toString() ?? '';
      
      // 1a. Cancel any active leave game timers (we're leaving immediately)
      try {
        final gameCoordinator = GameCoordinator();
        gameCoordinator.cancelLeaveGameTimer(null); // Cancel any active timer
        _logger.info('🧹 DutchGameHelpers: Cancelled any active leave game timers', isOn: LOGGING_SWITCH);
      } catch (e) {
        _logger.warning('⚠️ DutchGameHelpers: Error cancelling leave game timer: $e', isOn: LOGGING_SWITCH);
      }
      
      // 1b. Reset transport mode to WebSocket FIRST (before leaving rooms)
      // This ensures leave_room events route to WebSocket, not practice bridge
      // This prevents mode conflicts when switching from practice to WebSocket or vice versa
      try {
        final eventEmitter = _eventEmitter; // Use existing instance
        eventEmitter.setTransportMode(EventTransportMode.websocket);
        _logger.info('🧹 DutchGameHelpers: Reset transport mode to WebSocket (before leaving rooms)', isOn: LOGGING_SWITCH);
      } catch (e) {
        _logger.warning('⚠️ DutchGameHelpers: Error resetting transport mode: $e', isOn: LOGGING_SWITCH);
      }
      
      // 2. Trigger room leaving logic for active games
      // This ensures backend/practice bridge properly handles player leaving
      
      // 2a. Leave current game if it exists (WebSocket room or practice room)
      if (currentGameId.isNotEmpty) {
        _logger.info('🧹 DutchGameHelpers: Leaving current game: $currentGameId', isOn: LOGGING_SWITCH);
        
        // For WebSocket rooms (multiplayer), send leave_room event
        if (currentGameId.startsWith('room_')) {
          try {
            final gameCoordinator = GameCoordinator();
            await gameCoordinator.leaveGame(gameId: currentGameId);
            _logger.info('🧹 DutchGameHelpers: Sent leave_room event for WebSocket room: $currentGameId', isOn: LOGGING_SWITCH);
          } catch (e) {
            _logger.warning('⚠️ DutchGameHelpers: Error leaving WebSocket room $currentGameId: $e', isOn: LOGGING_SWITCH);
          }
        }
        // For practice rooms, end practice session (handles cleanup)
        else if (currentGameId.startsWith('practice_room_')) {
          try {
            final practiceBridge = PracticeModeBridge.instance;
            practiceBridge.endPracticeSession();
            _logger.info('🧹 DutchGameHelpers: Ended practice session for room: $currentGameId', isOn: LOGGING_SWITCH);
          } catch (e) {
            _logger.warning('⚠️ DutchGameHelpers: Error ending practice session for $currentGameId: $e', isOn: LOGGING_SWITCH);
          }
        }
      }
      
      // 2b. Leave any other games in the games map (in case there are multiple)
      for (final gameId in games.keys) {
        if (gameId.toString() == currentGameId) continue; // Already handled above
        
        _logger.info('🧹 DutchGameHelpers: Leaving game from games map: $gameId', isOn: LOGGING_SWITCH);
        
        // For WebSocket rooms, send leave_room event
        if (gameId.toString().startsWith('room_')) {
          try {
            final gameCoordinator = GameCoordinator();
            await gameCoordinator.leaveGame(gameId: gameId.toString());
            _logger.info('🧹 DutchGameHelpers: Sent leave_room event for WebSocket room: $gameId', isOn: LOGGING_SWITCH);
          } catch (e) {
            _logger.warning('⚠️ DutchGameHelpers: Error leaving WebSocket room $gameId: $e', isOn: LOGGING_SWITCH);
          }
        }
        // For practice rooms, clear from GameStateStore (practice session already ended above)
        else if (gameId.toString().startsWith('practice_room_')) {
          try {
            final gameStateStore = GameStateStore.instance;
            gameStateStore.clear(gameId.toString());
            _logger.info('🧹 DutchGameHelpers: Cleared GameStateStore for practice room: $gameId', isOn: LOGGING_SWITCH);
          } catch (e) {
            _logger.warning('⚠️ DutchGameHelpers: Error clearing GameStateStore for $gameId: $e', isOn: LOGGING_SWITCH);
          }
        }
      }
      
      // 3. Clear all games from GameStateStore (practice mode backend state)
      final gameStateStore = GameStateStore.instance;
      for (final gameId in games.keys) {
        try {
          gameStateStore.clear(gameId.toString());
          _logger.info('🧹 DutchGameHelpers: Cleared GameStateStore for game: $gameId', isOn: LOGGING_SWITCH);
        } catch (e) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing GameStateStore for $gameId: $e', isOn: LOGGING_SWITCH);
        }
      }
      
      // 4. End any existing practice session (catch-all to ensure practice bridge is fully cleaned up)
      // This ensures practice bridge is cleaned up even if current game wasn't a practice room
      // NOTE: This is safe to call even if no practice session exists (method handles null checks)
      try {
        final practiceBridge = PracticeModeBridge.instance;
        practiceBridge.endPracticeSession();
        _logger.info('🧹 DutchGameHelpers: Ended existing practice session (catch-all cleanup)', isOn: LOGGING_SWITCH);
      } catch (e, stackTrace) {
        _logger.warning('⚠️ DutchGameHelpers: Error ending practice session: $e', isOn: LOGGING_SWITCH);
        _logger.warning('⚠️ DutchGameHelpers: Stack trace:\n$stackTrace', isOn: LOGGING_SWITCH);
        // Continue execution - don't let practice session cleanup block mode switching
      }
      
      // 4a. Clear practice user data and settings to ensure clean mode switch
      // This prevents practice mode state from interfering with WebSocket mode
      try {
        _stateUpdater.updateState({
          'practiceUser': null,
          'practiceSettings': null,
        });
        _logger.info('🧹 DutchGameHelpers: Cleared practice user data and settings', isOn: LOGGING_SWITCH);
      } catch (e) {
        _logger.warning('⚠️ DutchGameHelpers: Error clearing practice user data: $e', isOn: LOGGING_SWITCH);
      }
      
      // 5. Clear all game state using existing clearGameState method
      clearGameState();
      
      // 6. Clear additional state that might interfere
      // Use updateStateSync to ensure synchronous clearing before proceeding
      // This is critical when staying in the same mode (e.g., WebSocket to WebSocket)
      // to ensure state is fully cleared before the next join attempt
      _stateUpdater.updateStateSync({
        // Clear player-specific state
        'playerStatus': 'unknown',
        'myScore': 0,
        'isMyTurn': false,
        'myDrawnCard': null,
        'myCardsToPeek': <Map<String, dynamic>>[],
        'myHandCards': <Map<String, dynamic>>[],
        'selectedCardIndex': -1,
        
        // Clear protected data
        'protectedCardsToPeek': null,
        // Removed protectedCardsToPeekTimestamp - widget uses internal timer
        
        // Clear action errors
        'actionError': null,
        
        // Clear random join flags (CRITICAL: Must be cleared when staying in same mode)
        'isRandomJoinInProgress': false,
        'randomJoinIsClearAndCollect': null,
        
        // Clear same rank trigger counter
        'sameRankTriggerCount': 0,
      });
      
      _logger.info('✅ DutchGameHelpers: All game state cleared successfully before new game', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DutchGameHelpers: Error clearing all game state: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
    }
  }
    
}
