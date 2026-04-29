import 'dart:async' show StreamController, unawaited;
import 'package:flutter/material.dart';
import 'package:dutch/tools/logging/logger.dart';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../../../core/managers/navigation_manager.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../dutch_game/utils/dutch_game_helpers.dart';
import '../backend_core/utils/level_matcher.dart';
import '../../dutch_game/managers/dutch_event_listener_validator.dart';
import '../../dutch_game/managers/dutch_event_handler_callbacks.dart';


/// Message id for notification response success handling. Must match backend dutch_notifications.MSG_ID_MATCH_INVITE.
class _NotificationMsgId {
  static const String matchInvite = 'dutch_game_invite_to_match_001';
}

/// Handler called when a notification response succeeds. (response, message, context) from hook.
typedef _NotificationSuccessHandler = Future<void> Function(
  Map<String, dynamic> response,
  Map<String, dynamic> message,
  BuildContext? context,
);

class DutchEventManager {
  static const bool LOGGING_SWITCH = false; // Random join nav + room events; coin-purchase paths (enable-logging-switch.mdc; set false after test)
  static final DutchEventManager _instance = DutchEventManager._internal();
  factory DutchEventManager() => _instance;
  DutchEventManager._internal();

  final Logger _logger = Logger();
  final StateManager _stateManager = StateManager();

  /// Map msg_id -> success handler (same idea as backend: msg_id + action_identifier -> handler).
  final Map<String, _NotificationSuccessHandler> _notificationSuccessHandlers = {};

  final StreamController<List<Map<String, dynamic>>> _roomMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _sessionMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();

  // In-memory boards (roomId -> list), session board (global for this client)
  final Map<String, List<Map<String, dynamic>>> _roomBoards = {};
  final List<Map<String, dynamic>> _sessionBoard = [];



  Stream<List<Map<String, dynamic>>> roomMessages(String roomId) {
    return _roomMessagesController.stream.where((_) => true);
  }

  Stream<List<Map<String, dynamic>>> get sessionMessages => _sessionMessagesController.stream;

  Future<bool> initialize() async {
    try {
      // Register state domains
      _stateManager.registerModuleState("dutch_messages", {
        'session': <Map<String, dynamic>>[],
        'rooms': <String, List<Map<String, dynamic>>>{},
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Register hook callbacks for room events
      _registerHookCallbacks();

      // Register dutch-specific event listeners
      _registerDutchEventListeners();

      // Dutch-specific Socket.IO listeners are centralized in DutchGameCoordinator.
      // We subscribe only via WSEventManager callbacks here.
      return true;
      
    } catch (e) {
      return false;
    }
  }

  void _registerDutchEventListeners() {
    // Initialize the event listener validator
    DutchGameEventListenerValidator.instance.initialize();
  }

  // ========================================
  // PUBLIC EVENT HANDLER DELEGATES
  // ========================================

  /// Handle dutch_new_player_joined event
  void handleDutchNewPlayerJoined(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleDutchNewPlayerJoined(data);
  }

  /// Handle dutch_joined_games event
  void handleDutchJoinedGames(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleDutchJoinedGames(data);
  }

  /// Handle game_started event
  void handleGameStarted(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleGameStarted(data);
  }

  /// Handle turn_started event
  void handleTurnStarted(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleTurnStarted(data);
  }

  /// Handle game_state_updated event
  void handleGameStateUpdated(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleGameStateUpdated(data);
  }

  /// Handle game_state_partial_update event
  void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      _logger.info("handleGameStatePartialUpdate: $data");
    }
    DutchEventHandlerCallbacks.handleGameStatePartialUpdate(data);
  }

  /// Handle player_state_updated event
  void handlePlayerStateUpdated(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handlePlayerStateUpdated(data);
  }


  void _registerHookCallbacks() {
    // Register websocket_connect hook callback
    HooksManager().registerHookWithData('websocket_connect', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'connected') {
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: true);
        
        _addSessionMessage(
          level: 'success',
          title: 'WebSocket Connected',
          message: 'Successfully connected to game server',
          data: data,
        );
      }
    });
    
    // Register websocket_disconnect hook callback
    HooksManager().registerHookWithData('websocket_disconnect', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'disconnected') {
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: false);
        
        _addSessionMessage(
          level: 'warning',
          title: 'WebSocket Disconnected',
          message: 'Disconnected from game server',
          data: data,
        );
      }
    });
    
    // Register websocket_connect_error hook callback
    HooksManager().registerHookWithData('websocket_connect_error', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'error') {
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: false);
        
        _addSessionMessage(
          level: 'error',
          title: 'WebSocket Connection Error',
          message: 'Failed to connect to game server',
          data: data,
        );
      }
    });
    
    // Register room_creation hook callback
    HooksManager().registerHookWithData('room_creation', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      final roomId = data['room_id']?.toString() ?? '';
      final isRandomJoin = data['is_random_join'] == true;
      // For random join rooms, always set isOwner to false
      final isOwner = isRandomJoin ? false : (data['is_owner'] == true);
      
      switch (status) {
        case 'success':
          // Update state for successful room creation
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          DutchGameHelpers.updateUIState({
            'currentRoomId': roomId,
            'isRoomOwner': isOwner,
            'isInRoom': true,
            'gamePhase': 'waiting',
            'gameStatus': 'inactive',
            'isGameActive': false,
            'playerCount': 1, // Room creator is first player
            'currentSize': 1,
            'maxSize': maxPlayers, // Use actual max_players from backend
            'minSize': minPlayers, // Use actual min_players from backend
          });
          
          _addSessionMessage(
            level: 'success',
            title: 'Room Created',
            message: 'Successfully created room: $roomId',
            data: data,
          );
          
          // Auto-navigate only when this room was created by join_random_game (new room path).
          // Lobby create_room_success sets is_random_join: false — stay on lobby to invite / manage.
          if (isRandomJoin) {
            if (LOGGING_SWITCH) {
              _logger.info('🎮 Random join room created, navigating to game play screen');
            }
            DutchGameHelpers.updateUIState({
              'isRandomJoinInProgress': false,
            });
            Future.delayed(const Duration(milliseconds: 300), () {
              NavigationManager().navigateTo('/dutch/game-play');
            });
          }
          break;
          
        case 'created':
          // Update state for room created event (this contains the full room data)
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          DutchGameHelpers.updateUIState({
            'currentRoomId': roomId,
            'isInRoom': true,
            'gamePhase': 'waiting',
            'gameStatus': 'inactive',
            'isGameActive': false,
            'maxSize': maxPlayers, // Use actual max_players from backend
            'minSize': minPlayers, // Use actual min_players from backend
          });
          
          _addSessionMessage(
            level: 'info',
            title: 'Room Created',
            message: 'Room created: $roomId',
            data: data,
          );
          break;
          
        case 'error':
          // Update state for room creation error
          DutchGameHelpers.updateUIState({
            'currentRoomId': '',
            'isRoomOwner': false,
            'isInRoom': false,
            'lastError': data['error']?.toString() ?? 'Room creation failed',
          });
          
          final error = data['error']?.toString() ?? 'Unknown error';
          final details = data['details']?.toString() ?? '';
          _addSessionMessage(
            level: 'error',
            title: 'Room Creation Failed',
            message: '$error${details.isNotEmpty ? ': $details' : ''}',
            data: data,
          );
          break;
          
        default:
          _addSessionMessage(
            level: 'info',
            title: 'Room Event',
            message: 'Room event: $status',
            data: data,
          );
          break;
      }
    });
    
    // Map msg_id -> success handler (same idea as backend: msg_id + action_identifier -> handler).
    _notificationSuccessHandlers[_NotificationMsgId.matchInvite] = _onNotificationSuccessMatchInvite;

    HooksManager().registerHookWithData('instant_message_response_success', (data) async {
      final msgId = data['msg_id']?.toString() ?? '';
      final handler = _notificationSuccessHandlers[msgId];
      if (handler == null) return;
      final message = data['message'] is Map ? Map<String, dynamic>.from(data['message'] as Map) : <String, dynamic>{};
      final response = data['response'] is Map ? Map<String, dynamic>.from(data['response'] as Map) : <String, dynamic>{};
      final ctx = data['context'] is BuildContext ? data['context'] as BuildContext? : null;
      await handler(response, message, ctx);
    });

    // Insufficient coins on join_room / join_random / rematch_accept — stash + modal (retries if context null)
    HooksManager().registerHookWithData('websocket_join_room_error', (hookData) {
      try {
        final msg = hookData['message']?.toString().toLowerCase() ?? '';
        final insufficientCoins = msg.contains('insufficient coins') ||
            (msg.contains('insufficient') &&
                (msg.contains('coin') || msg.contains('balance')));
        if (!insufficientCoins) {
          return;
        }
        if (LOGGING_SWITCH) {
          _logger.info(
            '💰 websocket_join_room_error (insufficient coins): hookData keys=${hookData.keys.toList()} msg=$msg',
          );
        }
        final rawPayload = hookData['payload'];
        final payload = rawPayload is Map
            ? Map<String, dynamic>.from(rawPayload)
            : <String, dynamic>{};
        final roomId = hookData['room_id']?.toString() ?? payload['room_id']?.toString() ?? '';
        final glRaw = hookData['game_level'] ?? payload['game_level'];
        final gameLevel = _parseTableLevel(glRaw);
        final reqRaw = hookData['required_coins'] ?? payload['required_coins'];
        final requiredCoins = _parseRequiredCoins(reqRaw, gameLevel);

        final stash = <String, dynamic>{
          ...payload,
          'updatedAt': DateTime.now().toIso8601String(),
          'room_id': roomId.isNotEmpty ? roomId : payload['room_id'],
          'game_level': gameLevel,
          'required_coins': requiredCoins,
        };
        if (LOGGING_SWITCH) {
          _logger.info(
            '💰 Stashing lastCoinPurchaseJoinContext room_id=$roomId game_level=$gameLevel required_coins=$requiredCoins payloadKeys=${payload.keys.toList()}',
          );
        }
        unawaited(
          DutchGameHelpers.stashLastCoinPurchaseContextAndShowBuyModal(
            stash: stash,
            requiredCoins: requiredCoins,
          ),
        );
      } catch (e, st) {
        if (LOGGING_SWITCH) {
          _logger.error('💰 websocket_join_room_error hook failed: $e\n$st');
        }
      }
    });
    
    // Register websocket_join_room hook callback (for joining existing rooms)
    HooksManager().registerHookWithData('websocket_join_room', (data) {
      try {
        if (LOGGING_SWITCH) {
          _logger.info('🔍 websocket_join_room hook triggered with data: $data');
        }
        
        final status = data['status']?.toString() ?? 'unknown';
        final roomId = data['room_id']?.toString() ?? '';
        
        if (LOGGING_SWITCH) {
          _logger.info('🔍 websocket_join_room: status=$status, roomId=$roomId');
        }
        
        // 🎯 CRITICAL: For any successful room join, set currentGameId and currentRoomId
        // This ensures player 2 (and any joining player) has the game ID set before receiving game_state_updated
        if (status == 'success' && roomId.isNotEmpty) {
          final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final currentGameId = dutchState['currentGameId']?.toString() ?? '';
          
          // Set currentGameId if not already set (important for player 2 joining)
          if (currentGameId != roomId) {
            if (LOGGING_SWITCH) {
              _logger.info('🔍 websocket_join_room: Setting currentGameId to $roomId (was: $currentGameId)');
            }
            DutchGameHelpers.updateUIState({
              'currentGameId': roomId,
              'currentRoomId': roomId,
              'isInRoom': true,
            });
          }

          final currentRoute = NavigationManager().getCurrentRoute();
          if (currentRoute != '/dutch/game-play') {
            if (LOGGING_SWITCH) {
              _logger.info('🎮 websocket_join_room: Navigating to /dutch/game-play from $currentRoute');
            }
            Future.delayed(const Duration(milliseconds: 250), () {
              NavigationManager().navigateTo('/dutch/game-play');
            });
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('🎮 websocket_join_room: Already on /dutch/game-play, skipping navigation');
            }
          }
        }
        
        // Check if this is from a random join flow
        final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final isRandomJoinInProgress = dutchState['isRandomJoinInProgress'] == true;
        
        if (LOGGING_SWITCH) {
          _logger.info('🔍 websocket_join_room: isRandomJoinInProgress=$isRandomJoinInProgress, dutchState keys: ${dutchState.keys.toList()}');
        }
        
        if (status == 'success' && isRandomJoinInProgress && roomId.isNotEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 Random join: joined existing room, waiting for game_state_updated before navigating');
          }
          
          // Clear the random join flag
          DutchGameHelpers.updateUIState({
            'isRandomJoinInProgress': false,
          });
          
          // CRITICAL: Don't navigate immediately - wait for game_state_updated event
          // This ensures the game has actual player data before showing the screen
          // Navigation will be handled by handleGameStateUpdated when it receives valid game state
          if (LOGGING_SWITCH) {
            _logger.info('🎮 Random join: Deferring navigation until game_state_updated is received');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('🔍 websocket_join_room: Navigation skipped - status=$status, isRandomJoinInProgress=$isRandomJoinInProgress, roomId=$roomId');
          }
        }
      } catch (e) {
        if (LOGGING_SWITCH) {
          _logger.error('❌ Error in websocket_join_room hook callback: $e');
        }
      }
    });
    
    // Register websocket_user_joined_rooms hook callback
    HooksManager().registerHookWithData('websocket_user_joined_rooms', (data) {
      
      // final status = data['status']?.toString() ?? 'unknown';
      // final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
            
              // Update dutch game state to reflect the current room membership
        // When user leaves a room, total_rooms will be 0, so we should clear the joined games
        if (totalRooms == 0) {
          // User is not in any rooms, clear the joined games state
          DutchGameHelpers.updateUIState({
            'joinedGames': <Map<String, dynamic>>[],
            'totalJoinedGames': 0,
            // Removed joinedGamesTimestamp - causes unnecessary state updates
            'currentRoomId': '',
            'isInRoom': false,
            // Removed lastUpdated - causes unnecessary state updates
          });
        
      } else {
        // User is still in some rooms, but we need to update the joined games
        // This will be handled by the dutch_joined_games event when it's sent
      }
    });
    
  }

  /// Success handler for msg_id dutch_game_invite_to_match_001. On "Join", uses existing join_room logic to join the WS room and navigate to game-play.
  Future<void> _onNotificationSuccessMatchInvite(
    Map<String, dynamic> response,
    Map<String, dynamic> message,
    BuildContext? context,
  ) async {
    final action = (response['action'] ?? '').toString();
    if (action != 'join') return;

    final msgData = message['data'];
    String? roomId;
    if (msgData is Map<String, dynamic>) {
      final r = msgData['room_id'];
      roomId = r?.toString().trim();
    }
    roomId ??= response['room_id']?.toString().trim();
    if (roomId == null || roomId.isEmpty) {
      if (LOGGING_SWITCH) _logger.error('Match invite Join: no room_id in message data');
      return;
    }

    // [sendCustomEvent] returns success before server responds; block join/nav on insufficient coins locally.
    var inviteGameLevel = 1;
    if (msgData is Map<String, dynamic>) {
      final gl = msgData['game_level'] ?? msgData['gameLevel'];
      if (gl is int) {
        inviteGameLevel = gl;
      } else if (gl is num) {
        inviteGameLevel = gl.toInt();
      }
    }
    final glResp = response['game_level'] ?? response['gameLevel'];
    if (glResp is int) {
      inviteGameLevel = glResp;
    } else if (glResp is num) {
      inviteGameLevel = glResp.toInt();
    }
    if (!await DutchGameHelpers.checkCoinsRequirement(
          gameLevel: inviteGameLevel,
          fetchFromAPI: true,
        )) {
      final required = LevelMatcher.tableLevelToCoinFee(inviteGameLevel, defaultFee: 25);
      await DutchGameHelpers.stashLastCoinPurchaseContextAndShowBuyModal(
        stash: {
          'room_id': roomId,
          'game_level': inviteGameLevel,
          'source': 'match_invite_prejoin',
        },
        requiredCoins: required,
      );
      return;
    }

    final result = await DutchGameHelpers.joinRoom(roomId: roomId);
    if (result['success'] != true) {
      if (LOGGING_SWITCH) _logger.error('Match invite joinRoom failed: ${result['error']}');
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)!.showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'Failed to join room'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
    if (games.containsKey(roomId)) {
      DutchGameHelpers.setCurrentGameSync(roomId, games);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final retryState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final retryGames = Map<String, dynamic>.from(retryState['games'] as Map<String, dynamic>? ?? {});
      if (retryGames.containsKey(roomId)) {
        DutchGameHelpers.setCurrentGameSync(roomId, retryGames);
      }
    }
    NavigationManager().navigateTo('/dutch/game-play');
    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)!.showSnackBar(
        SnackBar(
          content: const Text('Joined. Opening game...'),
          backgroundColor: AppColors.successColor,
        ),
      );
    }
  }

  // void _addRoomMessage(String roomId, {required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
  //   final entry = _entry(level, title, message, data);
  //   final list = _roomBoards.putIfAbsent(roomId, () => <Map<String, dynamic>>[]);
  //   list.add(entry);
  //   if (list.length > 200) list.removeAt(0);
  //   _emitState();
  // }

  void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = _entry(level, title, message, data);
    _sessionBoard.add(entry);
    if (_sessionBoard.length > 200) _sessionBoard.removeAt(0);
    _emitState();
  }

  Map<String, dynamic> _entry(String? level, String? title, String? message, Map<String, dynamic>? data) {
    return {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _emitState() {
    // Push to StateManager using validated state updater
    final roomsCopy = <String, List<Map<String, dynamic>>>{};
    _roomBoards.forEach((k, v) => roomsCopy[k] = List<Map<String, dynamic>>.from(v));
    
    DutchGameHelpers.updateUIState({
      'messages': {
        'session': List<Map<String, dynamic>>.from(_sessionBoard),
        'rooms': roomsCopy,
      },
    });
  }

  List<Map<String, dynamic>> getSessionBoard() => List<Map<String, dynamic>>.from(_sessionBoard);
  List<Map<String, dynamic>> getRoomBoard(String roomId) => List<Map<String, dynamic>>.from(_roomBoards[roomId] ?? const []);

  static int _parseTableLevel(dynamic v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse(v?.toString() ?? '') ?? 1;
  }

  static int _parseRequiredCoins(dynamic v, int gameLevel) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return LevelMatcher.levelToCoinFee(gameLevel, defaultFee: 25);
  }

  void dispose() {
    _roomMessagesController.close();
    _sessionMessagesController.close();
  }
}