import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'player_action.dart';
import '../utils/dutch_game_helpers.dart';

const bool LOGGING_SWITCH = true; // Enabled for testing game finding/initialization and leave_room event verification

/// Game Coordinator for handling all player game actions
/// 
/// This class centralizes all player game actions and ensures they go through
/// a consistent flow before being sent to the backend.
class GameCoordinator {
  static final GameCoordinator _instance = GameCoordinator._internal();
  
  factory GameCoordinator() => _instance;
  GameCoordinator._internal();
  
  final Logger _logger = Logger();
  Timer? _leaveGameTimer; // Track active leave timer (survives widget disposal)
  String? _pendingLeaveGameId; // Track which game has pending leave
  
  /// Get the pending leave game ID (for checking if user returned to same game)
  String? get pendingLeaveGameId => _pendingLeaveGameId;
  
  /// Join a game
  Future<bool> joinGame({
    String? gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) async {
    try {
      if (gameId == null || gameId.isEmpty) {
        return false;
      }
      
      final action = PlayerAction.joinGame(
        gameId: gameId,
        playerName: playerName,
        playerType: playerType,
        maxPlayers: maxPlayers,
      );
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Leave a game
  Future<bool> leaveGame({
    required String gameId,
  }) async {
    if (LOGGING_SWITCH) {
      _logger.info('GameCoordinator.leaveGame: Called with gameId: $gameId');
    }
    try {
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator.leaveGame: Creating PlayerAction.leaveGame for $gameId');
        _logger.info('GameCoordinator.leaveGame: Executing leave_room event for $gameId');
      }
      final action = PlayerAction.leaveGame(gameId: gameId);
      await action.execute();
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator.leaveGame: Successfully executed leave_room event for $gameId');
      }
      return true;
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('GameCoordinator.leaveGame: Error leaving game $gameId: $e');
      }
      return false;
    }
  }
  
  /// Start 30-second timer before leaving game
  /// Gives user chance to return to game within 30 seconds
  /// Timer is managed here (not in widget) so it survives widget disposal
  void startLeaveGameTimer(String gameId) {
    // Cancel any existing timer first
    if (_leaveGameTimer != null) {
      _leaveGameTimer?.cancel();
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator: Cancelled existing leave timer for $_pendingLeaveGameId');
      }
    }
    
    _pendingLeaveGameId = gameId;
    if (LOGGING_SWITCH) {
      _logger.info('GameCoordinator: Starting 30-second leave timer for game $gameId');
    }
    
    _leaveGameTimer = Timer(const Duration(seconds: 30), () {
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator: 30-second timer expired for game $gameId - executing leave');
      }
      _executeLeaveGame(gameId);
    });
  }
  
  /// Cancel the leave game timer
  /// Called when user returns to the same game within 30 seconds
  void cancelLeaveGameTimer(String? gameId) {
    if (_leaveGameTimer != null && (gameId == null || _pendingLeaveGameId == gameId)) {
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator: Cancelling leave timer for game $_pendingLeaveGameId');
      }
      _leaveGameTimer?.cancel();
      _leaveGameTimer = null;
      _pendingLeaveGameId = null;
    }
  }
  
  /// Execute leave game after timer expires
  /// Handles both multiplayer and practice mode
  void _executeLeaveGame(String gameId) {
    if (LOGGING_SWITCH) {
      _logger.info('GameCoordinator: Executing leave for game $gameId');
    }
    
    // Clear timer references
    _leaveGameTimer = null;
    _pendingLeaveGameId = null;
    
    // For multiplayer games (room_*), send leave_room event to backend
    // This removes the player from the game on the backend
    if (gameId.startsWith('room_')) {
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator: Sending leave_room event for multiplayer game $gameId');
      }
      leaveGame(gameId: gameId).catchError((e) {
        if (LOGGING_SWITCH) {
          _logger.error('GameCoordinator: Error leaving game: $e');
        }
        return false;
      });
    }
    
    // For practice games (practice_room_*), just clear state (no backend event needed)
    // Practice mode bridge handles its own cleanup
    if (gameId.startsWith('practice_room_')) {
      if (LOGGING_SWITCH) {
        _logger.info('GameCoordinator: Clearing state for practice game $gameId');
      }
    }
    
    // Clear game state: remove player from games map and clear current game references
    // This triggers widget updates through StateManager
    DutchGameHelpers.removePlayerFromGame(gameId: gameId);
    
    if (LOGGING_SWITCH) {
      _logger.info('GameCoordinator: Leave completed for game $gameId');
    }
  }
  
  /// Create and execute a start match action
  Future<bool> startMatch() async {
    try {
      // Get current game state
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        return false;
      }
      
      // Get practice settings if this is a practice game (for showInstructions and isClearAndCollect)
      final bool? showInstructions;
      final bool? isClearAndCollect;
      if (currentGameId.startsWith('practice_room_')) {
        final practiceSettings = dutchGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool?;
        isClearAndCollect = practiceSettings?['isClearAndCollect'] as bool?;
      } else {
        showInstructions = null; // Multiplayer games don't use showInstructions
        // For random join games, read isClearAndCollect from state (stored when join_random_game was called)
        // For regular multiplayer games, default to true (collection mode)
        isClearAndCollect = dutchGameState['randomJoinIsClearAndCollect'] as bool? ?? true;
      }
      
      // Create and execute the player action
      final action = PlayerAction.startMatch(
        gameId: currentGameId,
        showInstructions: showInstructions,
        isClearAndCollect: isClearAndCollect,
      );
      
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
}