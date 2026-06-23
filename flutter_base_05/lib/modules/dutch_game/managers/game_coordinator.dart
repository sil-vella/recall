import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import 'player_action.dart';
import '../utils/dutch_firebase_analytics.dart';
import '../utils/dutch_game_helpers.dart';


/// Game Coordinator for handling all player game actions
/// 
/// This class centralizes all player game actions and ensures they go through
/// a consistent flow before being sent to the backend.
class GameCoordinator {
  static final GameCoordinator _instance = GameCoordinator._internal();
  
  factory GameCoordinator() => _instance;
  GameCoordinator._internal();
  
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
    
    try {
      
      final action = PlayerAction.leaveGame(gameId: gameId);
      await action.execute();
      
      return true;
    } catch (e) {
      
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
      
    }
    
    _pendingLeaveGameId = gameId;
    
    
    _leaveGameTimer = Timer(const Duration(seconds: 30), () {
      
      _executeLeaveGame(gameId);
    });
  }
  
  /// Cancel the leave game timer
  /// Called when user returns to the same game within 30 seconds
  void cancelLeaveGameTimer(String? gameId) {
    if (_leaveGameTimer != null && (gameId == null || _pendingLeaveGameId == gameId)) {
      
      _leaveGameTimer?.cancel();
      _leaveGameTimer = null;
      _pendingLeaveGameId = null;
    }
  }

  /// Reset coordinator to init state (no timer, no pending leave). Call when clearing all games.
  void resetToInit() {
    if (_leaveGameTimer != null) {
      _leaveGameTimer!.cancel();
      _leaveGameTimer = null;
    }
    _pendingLeaveGameId = null;
    DutchFirebaseAnalytics.resetSession();
  }
  
  /// Execute leave game after timer expires
  /// Handles both multiplayer and practice mode
  void _executeLeaveGame(String gameId) {
    
    
    // Clear timer references
    _leaveGameTimer = null;
    _pendingLeaveGameId = null;
    
    // For multiplayer games (room_*), send leave_room event to backend
    // This removes the player from the game on the backend
    if (gameId.startsWith('room_')) {
      
      leaveGame(gameId: gameId).catchError((e) {
        
        return false;
      });
    }
    
    // For practice games (practice_room_*), just clear state (no backend event needed)
    // Practice mode bridge handles its own cleanup
    if (gameId.startsWith('practice_room_')) {
      
    }
    
    // Clear game state: remove player from games map and clear current game references
    // This triggers widget updates through StateManager
    DutchGameHelpers.removePlayerFromGame(gameId: gameId);
    
    
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
        isClearAndCollect = _resolveIsClearAndCollect(currentGameId, dutchGameState);
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
      
      rethrow;
    }
  }

  bool _resolveIsClearAndCollect(
    String currentGameId,
    Map<String, dynamic> dutchGameState,
  ) {
    if (currentGameId.startsWith('practice_room_')) {
      final practiceSettings =
          dutchGameState['practiceSettings'] as Map<String, dynamic>?;
      return practiceSettings?['isClearAndCollect'] == true;
    }

    final rj = dutchGameState['randomJoinIsClearAndCollect'] as bool?;
    if (rj != null) {
      return rj;
    }

    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final entry = games[currentGameId] as Map<String, dynamic>?;
    final gt = entry?['game_type']?.toString() ?? 'classic';
    return gt == 'clear_and_collect';
  }
}
