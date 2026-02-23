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
import '../backend_core/services/game_registry.dart';
import '../practice/practice_mode_bridge.dart';
import '../managers/game_coordinator.dart';
import 'state_queue_validator.dart';
import '../backend_core/utils/state_queue_validator.dart' as backend_validator;

/// Convenient helper methods for dutch game operations
/// Provides type-safe, validated methods for common game actions
class DutchGameHelpers {
  // Singleton instances
  static final _eventEmitter = DutchGameEventEmitter.instance;
  static final _stateUpdater = DutchGameStateUpdater.instance;
  static final _logger = Logger();
  
  static const bool LOGGING_SWITCH = true; // Enabled for create room/tournament flow, game clearing, leave_room verification
  
  /// Game IDs we just left (clear flow / leave button). Used to ignore stale game_state_updated.
  static final Set<String> _recentlyLeftGameIds = {};
  static bool wasGameRecentlyLeft(String gameId) => gameId.isNotEmpty && _recentlyLeftGameIds.contains(gameId);
  static void clearRecentlyLeftGameId(String gameId) {
    _recentlyLeftGameIds.remove(gameId);
  }

  /// Returns true if [gameId] is still in dutch_game state (in games map or is currentGameId).
  /// Used by Dutch WS listeners to ignore stale events for games we've left or cleared.
  static bool isGameStillInState(String gameId) {
    if (gameId.isEmpty) return false;
    final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = dutchState['currentGameId']?.toString() ?? '';
    return games.containsKey(gameId) || currentGameId == gameId;
  }

  /// True when a random-join is in progress (we sent join_random_game and are waiting for room/game_state).
  /// Used to allow initial game_state_updated for the new room even before it is in state.
  static bool get isRandomJoinInProgress {
    final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    return dutchState['isRandomJoinInProgress'] == true;
  }
  
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
    
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers.createRoom: emitting create_room payload: $data');
    }
    
      return await _eventEmitter.emit(
      eventType: 'create_room',
      data: data,
    );
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameHelpers: Error creating room: $e');
      }
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
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameHelpers: Error joining room: $e');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: navigateToAccountScreen called - reason: $reason, message: $message');
    }
    try {
      final navigationManager = NavigationManager();
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: NavigationManager obtained, navigating to /account');
      }
      navigationManager.navigateToWithDelay('/account', parameters: {
        'auth_reason': reason,
        'auth_message': message,
      });
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: Navigation to /account initiated');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameHelpers: Error navigating to account screen: $e', error: e, stackTrace: stackTrace);
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: ensureWebSocketReady called');
    }
    
    // Check if user is logged in
    final stateManager = StateManager();
    final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
    final isLoggedIn = loginState['isLoggedIn'] == true;
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: User login status - isLoggedIn: $isLoggedIn');
    }
    
    if (!isLoggedIn) {
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: User is not logged in, checking for existing user data');
      }
      
      // Check SharedPreferences for username and email
      try {
        final sharedPref = SharedPrefManager();
        await sharedPref.initialize();
        final username = sharedPref.getString('username');
        final email = sharedPref.getString('email');
        
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: SharedPreferences check - username: ${username != null && username.isNotEmpty ? "exists" : "null"}, email: ${email != null && email.isNotEmpty ? "exists" : "null"}');
        }
        
        // If either username or email exists, user data exists - navigate to account screen
        if ((username != null && username.isNotEmpty) || (email != null && email.isNotEmpty)) {
          if (LOGGING_SWITCH) {
            _logger.info('DutchGameHelpers: User data found in SharedPreferences, navigating to account screen');
          }
          navigateToAccountScreen('ws_auth_required', 'Please log in to connect to game server.');
          return false;
        }
        
        // No user data found - attempt auto-guest creation
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: No user data found, attempting auto-guest creation');
        }
        
        // Get context from NavigationManager if not provided
        final navigationManager = NavigationManager();
        final effectiveContext = context ?? navigationManager.navigatorKey.currentContext;
        
        if (effectiveContext == null) {
          if (LOGGING_SWITCH) {
            _logger.warning('DutchGameHelpers: Cannot auto-create guest - no context available');
          }
          return false;
        }
        
        // Get LoginModule
        final moduleManager = ModuleManager();
        final loginModule = moduleManager.getModuleByType<LoginModule>();
        
        if (loginModule == null) {
          if (LOGGING_SWITCH) {
            _logger.warning('DutchGameHelpers: Cannot auto-create guest - LoginModule not available');
          }
          return false;
        }
        
        // Attempt guest registration
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: Calling LoginModule.registerGuestUser');
        }
        final result = await loginModule.registerGuestUser(context: effectiveContext);
        
        if (result['success'] != null) {
          if (LOGGING_SWITCH) {
            _logger.info('DutchGameHelpers: Guest user created successfully, waiting for login completion');
          }
          
          // Wait for login process to fully complete
          final loginCompleted = await _waitForLoginCompletion();
          if (!loginCompleted) {
            if (LOGGING_SWITCH) {
              _logger.warning('DutchGameHelpers: Login completion timeout');
            }
            return false;
          }
          
          if (LOGGING_SWITCH) {
            _logger.info('DutchGameHelpers: Login completed, retrying ensureWebSocketReady');
          }
          // Recursively retry - now user should be fully logged in
          // Pass context to avoid re-fetching it
          return await ensureWebSocketReady(context: effectiveContext);
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('DutchGameHelpers: Guest creation failed: ${result['error']}');
          }
          return false;
        }
      } catch (e, stackTrace) {
        if (LOGGING_SWITCH) {
          _logger.error('DutchGameHelpers: Error during auto-guest creation check: $e', error: e, stackTrace: stackTrace);
        }
        return false;
      }
    }
    
    // Get WebSocket manager
    final wsManager = WebSocketManager.instance;
    
    // Initialize if not already initialized
    if (!wsManager.isInitialized) {
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket not initialized, initializing...');
      }
      final initialized = await wsManager.initialize();
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket initialization result: $initialized');
      }
      if (!initialized) {
        if (LOGGING_SWITCH) {
          _logger.warning('DutchGameHelpers: WebSocket initialization failed');
        }
        return false;
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket already initialized');
      }
    }
    
    // Connect if not already connected
    if (!wsManager.isConnected) {
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket not connected, connecting...');
      }
      final connected = await wsManager.connect();
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket connection result: $connected');
      }
      if (!connected) {
        if (LOGGING_SWITCH) {
          _logger.warning('DutchGameHelpers: WebSocket connection failed');
        }
        return false;
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('DutchGameHelpers: WebSocket already connected');
      }
    }
    
    // Wait for authentication to complete (with timeout; backend may call Python to validate token)
    const int authTimeoutSeconds = 10;
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: Waiting for authentication to complete...');
    }
    bool authCompleted = await _waitForAuthentication(timeoutSeconds: authTimeoutSeconds);
    if (!authCompleted) {
      // One retry: re-emit authenticate in case the first response was lost or backend was slow
      if (LOGGING_SWITCH) {
        _logger.warning('DutchGameHelpers: Auth timeout, retrying once...');
      }
      await wsManager.emitAuthenticate();
      authCompleted = await _waitForAuthentication(timeoutSeconds: authTimeoutSeconds);
    }
    if (!authCompleted) {
      if (LOGGING_SWITCH) {
        _logger.warning('DutchGameHelpers: Authentication did not complete within timeout');
      }
      return false;
    }
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: Authentication completed');
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: WebSocket is ready');
    }
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
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: Authentication confirmed');
        }
        return true;
      }
      
      await Future.delayed(checkInterval);
    }
    
    if (LOGGING_SWITCH) {
      _logger.warning('DutchGameHelpers: Authentication timeout after ${timeoutSeconds}s');
    }
    return false;
  }
  
  /// Wait for login completion after guest creation
  /// Returns true if login is complete (isLoggedIn, userId, username, email all set), false if timeout
  static Future<bool> _waitForLoginCompletion({int timeoutSeconds = 10}) async {
    final stateManager = StateManager();
    final startTime = DateTime.now();
    const checkInterval = Duration(milliseconds: 100);
    
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameHelpers: Waiting for login completion...');
    }
    
    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final isLoggedIn = loginState['isLoggedIn'] == true;
      final userId = loginState['userId']?.toString() ?? '';
      final username = loginState['username']?.toString() ?? '';
      final email = loginState['email']?.toString() ?? '';
      
      if (isLoggedIn && userId.isNotEmpty && username.isNotEmpty && email.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: Login state complete - userId: $userId, username: $username, email: $email');
        }
        // Wait a bit more to ensure auth_login_complete hook has been processed
        await Future.delayed(const Duration(milliseconds: 500));
        if (LOGGING_SWITCH) {
          _logger.info('DutchGameHelpers: Login completion confirmed');
        }
        return true;
      }
      
      await Future.delayed(checkInterval);
    }
    
    if (LOGGING_SWITCH) {
      _logger.warning('DutchGameHelpers: Login completion timeout after ${timeoutSeconds}s');
    }
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

  /// Set practice user and settings synchronously so state has them before any async/queue.
  /// CRITICAL for WS→Practice: ensures practiceUser is in state so handleGameStateUpdated
  /// ignores late WebSocket game_state_updated and getCurrentUserId returns practice ID.
  static void setPracticeStateSync(Map<String, dynamic> practiceUserData, Map<String, dynamic> practiceSettings) {
    _stateUpdater.updateStateSync({
      'practiceUser': practiceUserData,
      'practiceSettings': practiceSettings,
    });
  }

  /// Set current game state synchronously before navigating to game play screen.
  /// Ensures the game play screen reads the new game on first build (avoids showing stale or empty state).
  static void setCurrentGameSync(String gameId, Map<String, dynamic> games) {
    _stateUpdater.updateStateSync({
      'currentGameId': gameId,
      'games': games,
    });
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
      if (LOGGING_SWITCH) {
        _logger.info('🎯 Set isRandomJoinInProgress=true and randomJoinIsClearAndCollect=$isClearAndCollect using updateStateSync');
      }
      
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
      if (LOGGING_SWITCH) {
        _logger.info('📊 DutchGameHelpers: Fetching user dutch_game stats from API');
      }
      
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
        // Session expired / Unauthorized is expected when not logged in yet (e.g. before guest creation)
        final isSessionOrAuth = errorMessage.toString().toLowerCase().contains('session expired') ||
            errorMessage.toString().toLowerCase().contains('please log in again') ||
            (response['error']?.toString().toLowerCase() == 'unauthorized');
        if (LOGGING_SWITCH) {
          if (isSessionOrAuth) {
            _logger.warning('⚠️ DutchGameHelpers: API auth/session (expected when not logged in): $errorMessage');
          } else {
            _logger.error('❌ DutchGameHelpers: API error: $errorMessage');
          }
        }
        return {
          'success': false,
          'error': errorMessage,
          'data': null,
        };
      }
      
      // Check if response indicates success
      if (response is! Map || response['success'] != true) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: API response indicates failure');
        }
        return {
          'success': false,
          'error': response['message'] ?? response['error'] ?? 'Failed to fetch user stats',
          'data': null,
        };
      }
      
      // Extract data from response
      final statsData = response['data'] as Map<String, dynamic>?;
      
      if (statsData == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Response missing data field');
        }
        return {
          'success': false,
          'error': 'Response missing data field',
          'data': null,
        };
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Successfully fetched dutch_game stats: ${statsData.keys.toList()}');
      }
      
      return {
        'success': true,
        'data': statsData,
        'timestamp': response['timestamp'] ?? DateTime.now().toIso8601String(),
      };
      
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error fetching user dutch_game stats: $e', error: e, stackTrace: stackTrace);
      }
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
      if (LOGGING_SWITCH) {
        _logger.info('💰 DutchGameHelpers: Deducting $coins coins for game $gameId from ${playerIds.length} player(s)');
      }
      
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
        if (LOGGING_SWITCH) {
          _logger.error('❌ DutchGameHelpers: API error: $errorMessage');
        }
        return {
          'success': false,
          'error': errorMessage,
          'updated_players': <Map<String, dynamic>>[],
        };
      }
      
      // Check if response indicates success
      if (response is! Map || response['success'] != true) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: API response indicates failure');
        }
        return {
          'success': false,
          'error': response['message'] ?? response['error'] ?? 'Failed to deduct coins',
          'updated_players': <Map<String, dynamic>>[],
        };
      }
      
      // Extract updated players from response
      final updatedPlayers = response['updated_players'] as List<dynamic>? ?? [];
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Successfully deducted coins for ${updatedPlayers.length} player(s)');
      }
      
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
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error deducting game coins: $e', error: e, stackTrace: stackTrace);
      }
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
      if (LOGGING_SWITCH) {
        _logger.info('📊 DutchGameHelpers: Fetching and updating user dutch_game data');
      }
      
      // Fetch data from API
      final result = await getUserDutchGameData();
      
      if (result == null || result['success'] != true || result['data'] == null) {
        final error = result?['error'] ?? 'Unknown error';
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Failed to fetch dutch_game data: $error');
        }
        return false;
      }
      
      final dutchGameData = result['data'] as Map<String, dynamic>;
      
      // Update local state with fetched data
      // Store in a separate key to preserve game state while having user stats available
      _stateUpdater.updateState({
        'userStats': dutchGameData,
        // Removed userStatsLastUpdated - causes unnecessary state updates
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Successfully updated local state with dutch_game data');
      }
      
      return true;
      
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error fetching and updating user dutch_game data: $e', error: e, stackTrace: stackTrace);
      }
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
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error getting user stats from state: $e');
      }
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
        if (LOGGING_SWITCH) {
          _logger.info('📊 DutchGameHelpers: Fetching fresh user stats from API for tier check');
        }
        final statsResult = await getUserDutchGameData();
        
        if (statsResult != null && 
            statsResult['success'] == true && 
            statsResult['data'] != null) {
          final data = statsResult['data'] as Map<String, dynamic>?;
          if (data != null) {
            subscriptionTier = data['subscription_tier'] as String? ?? 'promotional';
          }
          if (LOGGING_SWITCH) {
            _logger.info('📊 DutchGameHelpers: Fetched subscription_tier from API: $subscriptionTier');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ DutchGameHelpers: Failed to fetch stats from API, falling back to state');
          }
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
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error checking subscription tier: $e');
      }
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
        if (LOGGING_SWITCH) {
          _logger.info('✅ DutchGameHelpers: User has promotional tier - skipping coin check (free play)');
        }
        return true;
      }
      
      // For non-promotional tier users, check coins requirement
      if (LOGGING_SWITCH) {
        _logger.info('📊 DutchGameHelpers: User has subscription tier "$subscriptionTier" - checking coins requirement');
      }
      
      int currentCoins = 0;
      
      if (fetchFromAPI) {
        // Fetch fresh stats from API to ensure we have latest coin count
        if (LOGGING_SWITCH) {
          _logger.info('📊 DutchGameHelpers: Fetching fresh user stats from API for coin check');
        }
        final statsResult = await getUserDutchGameData();
        
        if (statsResult != null && 
            statsResult['success'] == true && 
            statsResult['data'] != null) {
          final data = statsResult['data'] as Map<String, dynamic>?;
          if (data != null) {
            currentCoins = data['coins'] as int? ?? 0;
          }
          if (LOGGING_SWITCH) {
            _logger.info('📊 DutchGameHelpers: Fetched coins from API: $currentCoins');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ DutchGameHelpers: Failed to fetch stats from API, falling back to state');
          }
          // Fallback to state if API call fails
          final userStats = getUserDutchGameStats();
          currentCoins = userStats?['coins'] as int? ?? 0;
        }
      } else {
        // Use cached state
        final userStats = getUserDutchGameStats();
        if (userStats == null) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ DutchGameHelpers: Cannot check coins - userStats not found');
          }
          return false;
        }
        currentCoins = userStats['coins'] as int? ?? 0;
      }
      
      if (currentCoins < requiredCoins) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Insufficient coins - Required: $requiredCoins, Current: $currentCoins');
        }
        return false;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Coins check passed - Required: $requiredCoins, Current: $currentCoins');
      }
      return true;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error checking coins requirement: $e');
      }
      return false;
    }
  }

  /// Leaves the given game/room via existing WS logic and completely clears all state
  /// for this gameId, then triggers slice recomputation (joinedGamesSlice, etc.).
  /// Use this for explicit "Leave" from lobby or when removing the user from one game.
  /// For room_*: sends leave_room via GameCoordinator (does not change core WS module).
  /// For practice_room_*: ends practice session and clears backend state.
  static Future<void> leaveGameAndClearStateForGameId(String gameId) async {
    if (gameId.isEmpty) return;
    try {
      _recentlyLeftGameIds.add(gameId);
      if (LOGGING_SWITCH) {
        _logger.info('🚪 DutchGameHelpers: leaveGameAndClearStateForGameId($gameId) (marked recently left)');
      }
      final gameCoordinator = GameCoordinator();
      gameCoordinator.cancelLeaveGameTimer(gameId);
      if (gameId.startsWith('room_')) {
        try {
          await gameCoordinator.leaveGame(gameId: gameId);
          if (LOGGING_SWITCH) {
            _logger.info('🚪 DutchGameHelpers: Sent leave_room for $gameId');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ DutchGameHelpers: leave_room failed for $gameId: $e');
          }
        }
      } else if (gameId.startsWith('practice_room_')) {
        try {
          PracticeModeBridge.instance.endPracticeSession();
          if (LOGGING_SWITCH) {
            _logger.info('🚪 DutchGameHelpers: Ended practice session for $gameId');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ DutchGameHelpers: endPracticeSession for $gameId: $e');
          }
        }
      }
      try {
        GameStateStore.instance.clear(gameId);
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: GameStateStore.clear($gameId): $e');
        }
      }
      removePlayerFromGame(gameId: gameId);
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: leaveGameAndClearStateForGameId($gameId) done');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: leaveGameAndClearStateForGameId($gameId): $e');
      }
      rethrow;
    }
  }

  /// Leaves all games the user is in: gets all gameIds from state and calls
  /// [leaveGameAndClearStateForGameId] for each. Use when switching modes or logging out.
  static Future<void> leaveAllGamesAndClearState() async {
    try {
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = dutchState['games'] as Map<String, dynamic>? ?? {};
      final ids = games.keys.map((e) => e.toString()).toList();
      if (LOGGING_SWITCH) {
        _logger.info('🚪 DutchGameHelpers: leaveAllGamesAndClearState - ${ids.length} games');
      }
      for (final gameId in ids) {
        await leaveGameAndClearStateForGameId(gameId);
      }
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: leaveAllGamesAndClearState done');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: leaveAllGamesAndClearState: $e');
      }
      rethrow;
    }
  }

  /// Remove player from specific game in games map and clear current game references
  /// This is called when a player leaves a game (after timer expires)
  /// Only clears game state, not websocket state (websocket module handles that)
  static void removePlayerFromGame({required String gameId}) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🧹 DutchGameHelpers: Removing player from game $gameId');
      }
      
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
      
      // Remove the specific game from games map
      if (games.containsKey(gameId)) {
        games.remove(gameId);
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Removed game $gameId from games map');
        }
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
        updates['turn_events'] = <Map<String, dynamic>>[];
        
        // Clear round information
        updates['roundNumber'] = 0;
        updates['currentPlayer'] = null;
        updates['currentPlayerStatus'] = '';
        updates['roundStatus'] = '';
        
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Cleared current game references');
        }
      }
      
      // Update state (this triggers widget rebuilds)
      _stateUpdater.updateState(updates);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Player removed from game $gameId, widgets will update');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error removing player from game: $e');
      }
    }
  }

  /// Clear all game state when leaving game play screen
  /// This should be called when navigating away from the game play screen
  /// to prevent stale data from affecting new games
  static void clearGameState({String? gameId}) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🧹 DutchGameHelpers: Clearing game state${gameId != null ? " for game $gameId" : ""}');
      }
      
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
        
        // CRITICAL: Clear joinedGamesSlice when games map is cleared
        // This ensures lobby screen doesn't show stale games when switching modes
        'joinedGamesSlice': {
          'games': <Map<String, dynamic>>[],
          'totalGames': 0,
          'isLoadingGames': false,
        },
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: Game state cleared successfully');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error clearing game state: $e');
      }
    }
  }

  /// Clear all existing games, game maps, and game logic state before starting a new game.
  /// SSOT for "before starting a match" — called at the very beginning of createRoom, joinRoom,
  /// joinRandomGame, and lobby create/join/practice. Leaves all games (WS leave_room for multi)
  /// and clears state before any new match init or WS send to backend.
  static Future<void> clearAllGameStateBeforeNewGame() async {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🧹 DutchGameHelpers: Clearing ALL game state before starting new game (reset to init)');
      }
      
      // 1. Reset all game-related components to init state (coordinator, emitter, validator queue, store)
      // Order matches init: coordinator and emitter first, then validator queue so no stale updates re-apply.
      try {
        GameCoordinator().resetToInit();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: GameCoordinator.resetToInit()');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error resetting coordinator: $e');
        }
      }
      try {
        // Per MODE_SWITCHING_VERIFICATION: reset to WebSocket FIRST so leave_room routes to WS
        _eventEmitter.setTransportMode(EventTransportMode.websocket);
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Reset transport to WebSocket (before leaving rooms)');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error setting transport: $e');
        }
      }
      try {
        StateQueueValidator.instance.clearQueue();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Flutter StateQueueValidator queue cleared');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing Flutter validator queue: $e');
        }
      }
      try {
        backend_validator.StateQueueValidator.instance.clearQueue();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Backend StateQueueValidator queue cleared');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing backend validator queue: $e');
        }
      }
      
      // 2. SSOT: Leave all games and clear state (before any new match init / WS to backend)
      await leaveAllGamesAndClearState();
      
      // 2b. CRITICAL: Clear currentGameId and games synchronously so game play screen never sees old state.
      _stateUpdater.updateStateSync({
        'currentGameId': '',
        'games': <String, dynamic>{},
        'joinedGames': <Map<String, dynamic>>[],
        'totalJoinedGames': 0,
      });
      if (LOGGING_SWITCH) {
        _logger.info('🧹 DutchGameHelpers: Synchronously cleared currentGameId, games, joinedGames');
      }
      
      // 3. End practice session and clear backend store (practice bridge + GameStateStore)
      try {
        PracticeModeBridge.instance.endPracticeSession();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Ended practice session');
        }
      } catch (e, stackTrace) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error ending practice session: $e');
          _logger.warning('⚠️ DutchGameHelpers: Stack trace:\n$stackTrace');
        }
      }
      try {
        GameStateStore.instance.clearAll();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: GameStateStore.clearAll() (all room state reset)');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing GameStateStore: $e');
        }
      }
      try {
        GameRegistry.instance.clearAll();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: GameRegistry.clearAll() (all rounds reset)');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing GameRegistry: $e');
        }
      }
      
      // 4. Clear practice user data and settings synchronously so getCurrentUserId/_getSessionId use WS identity
      try {
        _stateUpdater.updateStateSync({
          'practiceUser': null,
          'practiceSettings': null,
        });
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Cleared practice user data and settings (sync)');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error clearing practice user data: $e');
        }
      }
      
      // 5. Clear all game state using existing clearGameState method
      clearGameState();
      
      // 6. Clear additional state that might interfere
      // Use updateStateSync to ensure synchronous clearing before proceeding
      // This is critical when staying in the same mode (e.g., WebSocket to WebSocket)
      // to ensure state is fully cleared before the next join attempt
      _stateUpdater.updateStateSync({
        // Clear player-specific state
        // Note: playerStatus must be one of the allowed values: waiting, ready, playing, same_rank_window, playing_card, drawing_card, queen_peek, jack_swap, peeking, initial_peek, finished, disconnected, winner
        // Use 'waiting' as the default cleared state (not 'unknown' which is not allowed)
        'playerStatus': 'waiting',
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
      });
      
      // 7. CRITICAL (WS → Practice): Clear state queue again so any updates enqueued by
      // leaveAllGamesAndClearState (removePlayerFromGame → updateState) cannot be processed
      // later and overwrite practice state when _startPracticeMatch sets currentGameId/games.
      try {
        StateQueueValidator.instance.clearQueue();
        if (LOGGING_SWITCH) {
          _logger.info('🧹 DutchGameHelpers: Flush queue after clear (prevent stale updates overwriting practice)');
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error flushing queue: $e');
        }
      }
      try {
        backend_validator.StateQueueValidator.instance.clearQueue();
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.warning('⚠️ DutchGameHelpers: Error flushing backend queue: $e');
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ DutchGameHelpers: All game state cleared successfully before new game');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ DutchGameHelpers: Error clearing all game state: $e', error: e, stackTrace: stackTrace);
      }
    }
  }
    
}
